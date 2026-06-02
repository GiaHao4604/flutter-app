import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/services/auth_session_service.dart';
import 'package:flutter_application_1/services/calendar_api_service.dart';
import 'package:flutter_application_1/services/calendar_refresh_notifier.dart';
import 'package:flutter_application_1/services/calendar_storage_service.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CircleActionButton extends StatelessWidget {
  const _CircleActionButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFF4A403A).withValues(alpha: 0.72),
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.10),
            width: 1,
          ),
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _visibleMonth = DateTime.now();
  Map<int, List<Map<String, dynamic>>> _postsByDay = {};
  int _monthIncome = 0;
  int _monthExpense = 0;
  final CalendarStorageService _storageService = CalendarStorageService();
  final AuthSessionService _sessionService = AuthSessionService();
  final CalendarApiService _apiService = CalendarApiService();
  late final VoidCallback _refreshListener;

  @override
  void initState() {
    super.initState();
    _refreshListener = () {
      if (mounted) {
        _loadMonthData();
      }
    };
    calendarRefreshNotifier.addListener(_refreshListener);
    _loadMonthData();
  }

  @override
  void dispose() {
    calendarRefreshNotifier.removeListener(_refreshListener);
    super.dispose();
  }

Future<void> _loadMonthData() async {
  final prefs = await SharedPreferences.getInstance();
  final storageKey = await _storageService.currentCalendarKey();

  List<Map<String, dynamic>> localPosts = [];
  final raw = prefs.getString(storageKey);

  if (raw != null && raw.isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final item in decoded) {
          if (item is Map) {
            localPosts.add(_normalizeCalendarPost(Map<String, dynamic>.from(item)));
          }
        }
      }
    } catch (_) {}
  }

  // Build multiple lookup maps for robust merging
  final localByKey = <String, Map<String, dynamic>>{};
  final localById = <String, Map<String, dynamic>>{};
  final localByLocalId = <String, Map<String, dynamic>>{};
  final localByImageBase = <String, Map<String, dynamic>>{};

  for (final post in localPosts) {
    localByKey[_postMergeKey(post)] = post;
    final id = post['id']?.toString().trim() ?? '';
    if (id.isNotEmpty) localById['id:$id'] = post;
    final localId = post['localId']?.toString().trim() ?? '';
    if (localId.isNotEmpty) localByLocalId['localId:$localId'] = post;
    final img = _postImagePath(post);
    if (img != null) {
      try {
        final base = p.basename(img);
        if (base.isNotEmpty) localByImageBase[base] = post;
      } catch (_) {}
    }
  }

  final mergedByKey = <String, Map<String, dynamic>>{};
  for (final post in localPosts) {
    mergedByKey[_postMergeKey(post)] = post;
  }

  List<Map<String, dynamic>> visiblePosts = localPosts;

  try {
    final token = await _sessionService.getToken();
    if (token != null && token.trim().isNotEmpty) {
      final remote = await _apiService.getMonth(
        token: token,
        month: _visibleMonth,
      );

      if (remote.success &&
          remote.data != null &&
          remote.data is Map<String, dynamic>) {
        final server = Map<String, dynamic>.from(remote.data!);
        final entries = (server['entries'] is List) ? List.from(server['entries']) : null;

        if (entries != null) {
          final List<Map<String, dynamic>> remotePosts = [];

          for (final e in entries) {
              if (e is Map) {
                final m = Map<String, dynamic>.from(e);
              final remotePost = <String, dynamic>{
                  'id': m['id']?.toString(),
                  'imageUrl': m['imageUrl'] ?? m['image_url'],
                  // keep imagePath null for remote records so local file checks don't misinterpret URLs
                  'imagePath': m['imagePath'] ?? m['image_path'],
                  // keep both entryTs and dateKey; prefer dateKey when grouping
                  'date': m['date'] ?? m['entryTs'],
                  'dateKey': m['dateKey'] ?? m['date_key'],
                  'amount': m['amount'] ?? 0,
                  'isExpense': m['isExpense'] ?? m['is_expense'] ?? false,
                  'note': m['note'],
                  'entryTs': m['entryTs'] ?? m['entry_ts'],
                };

                // Attempt to find a matching local post using several heuristics so
                // we preserve local-only fields like `imagePath` when possible.
                Map<String, dynamic>? matchedLocal;
                // 1) exact id match
                final rid = remotePost['id']?.toString().trim() ?? '';
                if (rid.isNotEmpty && localById.containsKey('id:$rid')) {
                  matchedLocal = localById['id:$rid'];
                }

                // 2) if not found, try matching by client localId
                if (matchedLocal == null) {
                  final rlocal = remotePost['clientLocalId']?.toString() ?? remotePost['localId']?.toString();
                  if (rlocal != null && rlocal.isNotEmpty && localByLocalId.containsKey('localId:$rlocal')) {
                    matchedLocal = localByLocalId['localId:$rlocal'];
                  }
                }

                // 3) if still not found, try matching by image basename
                if (matchedLocal == null) {
                  final rimg = remotePost['imageUrl']?.toString() ?? remotePost['image_path']?.toString();
                  if (rimg != null && rimg.isNotEmpty) {
                    try {
                      final base = p.basename(rimg);
                      if (base.isNotEmpty && localByImageBase.containsKey(base)) {
                        matchedLocal = localByImageBase[base];
                      }
                    } catch (_) {}
                  }
                }

                // 4) fallback: match by dateKey + note (same heuristic as _postMergeKey fallback)
                if (matchedLocal == null) {
                  final fk = _fallbackMergeKey(remotePost);
                  matchedLocal = localByKey[fk];
                }

                final merged = _mergeCalendarPost(
                  matchedLocal,
                  remotePost,
                );
                final normalizedMerged = _normalizeCalendarPost(merged);
                remotePosts.add(normalizedMerged);
                mergedByKey[_postMergeKey(normalizedMerged)] = normalizedMerged;
              }
          }

          final mergedPosts = mergedByKey.values
              .map(_normalizeCalendarPost)
              .toList();

          visiblePosts = mergedPosts;

          try {
            await prefs.setString(storageKey, jsonEncode(mergedPosts));
          } catch (_) {}
        }
      }
    }
  } catch (_) {}

  final Map<int, List<Map<String, dynamic>>> byDay = {};
  var income = 0;
  var expense = 0;

  for (final map in visiblePosts) {
    final dt = _resolvePostDate(map);
    if (dt == null) continue;

    if (dt.year == _visibleMonth.year && dt.month == _visibleMonth.month) {
      final day = dt.day;
      byDay.putIfAbsent(day, () => []).add(map);

      final amount = (map['amount'] is int)
          ? map['amount'] as int
          : int.tryParse(map['amount']?.toString() ?? '0') ?? 0;
      final isExp = map['isExpense'] == true;

      if (isExp) {
        expense += amount;
      } else {
        income += amount;
      }
    }
  }

  if (!mounted) return;
  setState(() {
    _postsByDay = byDay;
    _monthIncome = income;
    _monthExpense = expense;
  });
}

  String _postMergeKey(Map<String, dynamic> post) {
    final id = post['id']?.toString().trim() ?? '';
    if (id.isNotEmpty) {
      return 'id:$id';
    }

    final dateKey = post['dateKey']?.toString().trim() ?? '';
    final imagePath = post['imagePath']?.toString().trim() ?? '';
    final imageUrl = post['imageUrl']?.toString().trim() ?? '';
    final note = post['note']?.toString().trim() ?? '';
    return 'fallback:$dateKey|${imagePath.isNotEmpty ? imagePath : imageUrl}|$note';
  }

  String _fallbackMergeKey(Map<String, dynamic> post) {
    final dateKey = post['dateKey']?.toString().trim() ?? '';
    final imagePath = post['imagePath']?.toString().trim() ?? '';
    final imageUrl = post['imageUrl']?.toString().trim() ?? '';
    final note = post['note']?.toString().trim() ?? '';
    return 'fallback:$dateKey|${imagePath.isNotEmpty ? imagePath : imageUrl}|$note';
  }

  Map<String, dynamic> _mergeCalendarPost(
    Map<String, dynamic>? local,
    Map<String, dynamic> remote,
  ) {
    if (local == null) {
      return remote;
    }

    final merged = <String, dynamic>{...local, ...remote};

    final localImagePath = local['imagePath']?.toString().trim();
    final remoteImagePath = remote['imagePath']?.toString().trim();
    if (localImagePath != null && localImagePath.isNotEmpty) {
      merged['imagePath'] = localImagePath;
    } else if (remoteImagePath == null || remoteImagePath.isEmpty) {
      final localImageUrl = local['imageUrl']?.toString().trim();
      if (localImageUrl != null && localImageUrl.isNotEmpty) {
        merged['imageUrl'] = localImageUrl;
      }
    }

    final localDateKey = local['dateKey']?.toString().trim();
    if (localDateKey != null && localDateKey.isNotEmpty) {
      merged['dateKey'] = localDateKey;
    }

    final localDate = local['date']?.toString().trim();
    if (localDate != null && localDate.isNotEmpty) {
      merged['date'] = localDate;
    }

    final localEntryTs = local['entryTs']?.toString().trim();
    if (localEntryTs != null && localEntryTs.isNotEmpty) {
      merged['entryTs'] = localEntryTs;
    }

    return merged;
  }

  Map<String, dynamic> _normalizeCalendarPost(Map<String, dynamic> post) {
    final normalized = <String, dynamic>{...post};

    final localDateTime = normalized['localDateTime']?.toString().trim();
    if (localDateTime != null && localDateTime.isNotEmpty) {
      return normalized;
    }

    final rawEntryTs = normalized['entryTs']?.toString().trim();
    if (rawEntryTs != null && rawEntryTs.isNotEmpty) {
      final parsedEntryTs = DateTime.tryParse(rawEntryTs);
      if (parsedEntryTs != null) {
        normalized['localDateTime'] = parsedEntryTs.toLocal().toIso8601String();
        return normalized;
      }
    }

    final rawDate = normalized['date']?.toString().trim();
    if (rawDate != null && rawDate.isNotEmpty) {
      final parsedDate = DateTime.tryParse(rawDate);
      if (parsedDate != null) {
        normalized['localDateTime'] = parsedDate.toLocal().toIso8601String();
        return normalized;
      }
    }

    final dateKey = normalized['dateKey']?.toString().trim();
    if (dateKey != null && dateKey.isNotEmpty) {
      normalized['localDateTime'] = '${dateKey}T00:00:00';
    }

    return normalized;
  }

  DateTime? _resolvePostDate(Map<String, dynamic> map) {
    // Prefer explicit dateKey first (user-local date), then explicit ISO date, then entryTs
    final dateKey = map['dateKey']?.toString().trim();
    if (dateKey != null && dateKey.isNotEmpty) {
      final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(dateKey);
      if (m != null) {
        final y = int.parse(m.group(1)!);
        final mo = int.parse(m.group(2)!);
        final d = int.parse(m.group(3)!);
        return DateTime(y, mo, d);
      }
    }

    // Next prefer explicit ISO date (client-local stored 'date')
    final rawDate = map['date']?.toString().trim();
    if (rawDate != null && rawDate.isNotEmpty) {
      final parsed = DateTime.tryParse(rawDate);
      if (parsed != null) {
        final local = parsed.toLocal();
        return DateTime(local.year, local.month, local.day);
      }
    }

    // Fallback to server canonical timestamp 'entryTs' (ISO UTC)
    final rawEntryTs = map['entryTs']?.toString().trim();
    if (rawEntryTs != null && rawEntryTs.isNotEmpty) {
      final parsed = DateTime.tryParse(rawEntryTs);
      if (parsed != null) {
        final local = parsed.toLocal();
        return DateTime(local.year, local.month, local.day);
      }
    }

    return null;
  }

  String _formatVnd(int value) {
    final s = value.toString();
    final buffer = StringBuffer();
    int count = 0;
    for (int i = s.length - 1; i >= 0; i--) {
      buffer.write(s[i]);
      count++;
      if (count == 3 && i != 0) {
        buffer.write('.');
        count = 0;
      }
    }
    return buffer.toString().split('').reversed.join();
  }

  String _formatCompact(int value) {
    final negative = value < 0;
    final absValue = value.abs();
    if (absValue >= 1000000000) {
      final doubleVal = absValue / 1000000000;
      final formatted = (absValue % 1000000000 == 0) ? doubleVal.toStringAsFixed(0) : doubleVal.toStringAsFixed(1);
      return '${negative ? '-' : ''}${formatted}T';
    }
    if (absValue >= 1000000) {
      final doubleVal = absValue / 1000000;
      final formatted = (absValue % 1000000 == 0) ? doubleVal.toStringAsFixed(0) : doubleVal.toStringAsFixed(1);
      return '${negative ? '-' : ''}${formatted}tr';
    }
    return '${_formatVnd(value)}đ';
  }

  String? _postImagePath(Map<String, dynamic> post) {
    final rawPath = post['imagePath'] ?? post['imageUrl'];
    if (rawPath == null) return null;
    final value = rawPath.toString().trim();
    return value.isEmpty ? null : value;
  }

  ImageProvider? _postImageProvider(Map<String, dynamic> post) {
    final path = _postImagePath(post);
    if (path == null) return null;
    // If the path already looks like an absolute HTTP URL, use it.
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return NetworkImage(path);
    }

    try {
      final file = File(path);
      if (file.existsSync()) {
        return FileImage(file);
      }
    } catch (_) {}

    // Only resolve known server asset paths to an absolute URL.
    if (path.startsWith('/uploads/') || path.startsWith('uploads/')) {
      final resolved = CalendarApiService.resolveAssetUrl(path);
      if (resolved.isNotEmpty) return NetworkImage(resolved);
    }

    return null;
  }

  /// Return a ResizeImage wrapped provider sized to [logicalWidth] logical pixels
  /// (the helper will multiply by devicePixelRatio internally). This reduces
  /// decode cost for large images and is useful for thumbnails/main viewer.
  ImageProvider? _resizedImageProviderForPost(BuildContext ctx, Map<String, dynamic> post, double logicalWidth) {
    final base = _postImageProvider(post);
    if (base == null) return null;
    try {
      final dpr = MediaQuery.of(ctx).devicePixelRatio;
      final cacheWidth = (logicalWidth * dpr).round();
      return ResizeImage(base, width: cacheWidth);
    } catch (_) {
      return base;
    }
  }

  String _formatViewerTime(Map<String, dynamic> post) {
    final raw = post['localDateTime']?.toString() ?? post['entryTs']?.toString() ?? post['date']?.toString() ?? '';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return '';
    final local = parsed.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatViewerDay(DateTime dateTime) {
    return 'ngày ${dateTime.day} tháng ${dateTime.month}';
  }

  DateTime _selectedDayDate(int dayIndex) {
    return DateTime(_visibleMonth.year, _visibleMonth.month, dayIndex);
  }

  Future<void> _showDiagnostics() async {
    final prefs = await SharedPreferences.getInstance();
    final storageKey = await _storageService.currentCalendarKey();
    final raw = prefs.getString(storageKey);
    final posts = <Map<String, dynamic>>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) posts.add(Map<String, dynamic>.from(item));
          }
        }
      } catch (_) {}
    }

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (c) {
        return AlertDialog(
          title: const Text('Calendar Diagnostics'),
          content: SizedBox(
            width: double.maxFinite,
            height: 360,
            child: posts.isEmpty
                ? const Center(child: Text('No entries stored locally'))
                : ListView.builder(
                    itemCount: posts.length,
                    itemBuilder: (ctx, i) {
                      final pmap = posts[i];
                      final id = pmap['id']?.toString() ?? pmap['localId']?.toString() ?? '';
                      final dk = pmap['dateKey']?.toString() ?? pmap['date']?.toString() ?? '';
                      final path = _postImagePath(pmap);
                      final exists = path != null && File(path).existsSync();
                      return ListTile(
                        title: Text('$dk — $id'),
                        subtitle: Text('path: ${path ?? '—'}\nexists: $exists'),
                        isThreeLine: true,
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('Close')),
          ],
        );
      },
    );
  }

  void _openDayPreview(
    BuildContext context,
    int dayIndex,
    List<Map<String, dynamic>> posts,
  ) {
    var selectedIndex = 0;
    final pageController = PageController(initialPage: selectedIndex);
    final thumbScrollController = ScrollController();
    var currentPage = selectedIndex.toDouble();
    var listenerAttached = false;
    void prefetchAround(int center) {
      try {
        final start = (center - 2).clamp(0, posts.length - 1);
        final end = (center + 2).clamp(0, posts.length - 1);
        for (int i = start; i <= end; i++) {
          final logical = (i == center) ? 560.0 : 160.0;
          final prov = _resizedImageProviderForPost(context, posts[i], logical);
          if (prov != null) precacheImage(prov, context);
        }
      } catch (_) {}
    }

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'day_preview',
      barrierColor: Colors.black.withValues(alpha: 0.9),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return StatefulBuilder(
          builder: (context, setState) {
            final headerDate = _selectedDayDate(dayIndex);
            return Material(
              color: const Color(0xFF2A241F),
              child: SafeArea(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0xFF332C28),
                              Color(0xFF1D1714),
                              Color(0xFF120F0D),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _CircleActionButton(
                                icon: Icons.close_rounded,
                                onTap: () => Navigator.of(dialogContext).pop(),
                              ),
                              Column(
                                children: [
                                  Text(
                                    '${headerDate.year}',
                                    style: GoogleFonts.manrope(
                                      color: const Color(0xFFCFC8C3),
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _formatViewerDay(headerDate),
                                    style: GoogleFonts.manrope(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                              _CircleActionButton(
                                icon: Icons.ios_share_rounded,
                                onTap: () {},
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: Center(
                            child: PageView.builder(
                              controller: pageController,
                              itemCount: posts.length,
                              onPageChanged: (index) => setState(() {
                                selectedIndex = index;
                              }),
                              itemBuilder: (context, index) {
                                // attach listener once to update currentPage, auto-scroll thumbnails and prefetch images
                                if (!listenerAttached) {
                                  listenerAttached = true;
                                  pageController.addListener(() {
                                    final p = pageController.page ?? selectedIndex.toDouble();
                                    if (p == currentPage) return;
                                    currentPage = p;
                                    try {
                                      final screenW = MediaQuery.of(context).size.width;
                                      const thumbSize = 62.0;
                                      const thumbSpacing = 8.0;
                                      final itemExtent = thumbSize + thumbSpacing;
                                      final targetOffset = (p * itemExtent) - (screenW / 2 - thumbSize / 2);
                                      final max = thumbScrollController.hasClients ? thumbScrollController.position.maxScrollExtent : 0.0;
                                      final offsetClamped = targetOffset.clamp(0.0, max);
                                      if (thumbScrollController.hasClients) {
                                        thumbScrollController.animateTo(offsetClamped, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
                                      }
                                    } catch (_) {}
                                    try {
                                      final nearest = (pageController.page ?? selectedIndex.toDouble()).round();
                                      prefetchAround(nearest);
                                    } catch (_) {}
                                  });
                                  // initial prefetch for visible index
                                  try {
                                    prefetchAround(selectedIndex);
                                  } catch (_) {}
                                }
                                final post = posts[index];
                                final provider = _resizedImageProviderForPost(context, post, 560.0);
                                final timeText = _formatViewerTime(post);
                                final amountValue = (post['amount'] is int)
                                    ? post['amount'] as int
                                    : int.tryParse(post['amount']?.toString() ?? '0') ?? 0;
                                final amountLabel = '${post['isExpense'] == true ? '-' : '+'}${_formatCompact(amountValue)}';
                                final hasAmount = amountValue > 0;
                                final captionText = post['note']?.toString().trim() ?? '';
                                final hasCaption = captionText.isNotEmpty;

                                return Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 24),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Expanded(
                                          child: Center(
                                            child: ConstrainedBox(
                                              constraints: const BoxConstraints(maxWidth: 560),
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(34),
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF4A403A),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: Colors.black.withValues(alpha: 0.35),
                                                        blurRadius: 40,
                                                        offset: const Offset(0, 18),
                                                      ),
                                                    ],
                                                  ),
                                                  child: AspectRatio(
                                                    aspectRatio: 0.86,
                                                    child: Stack(
                                                      fit: StackFit.expand,
                                                      children: [
                                                        if (provider != null)
                                                          Image(
                                                            image: provider,
                                                            fit: BoxFit.cover,
                                                          )
                                                        else
                                                          Container(
                                                            color: const Color(0xFF5A4D46),
                                                            child: const Center(
                                                              child: Icon(
                                                                Icons.image_rounded,
                                                                color: Colors.white54,
                                                                size: 56,
                                                              ),
                                                            ),
                                                          ),
                                                        if (hasAmount)
                                                          Positioned(
                                                            left: 16,
                                                            top: 16,
                                                            child: Container(
                                                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                                              decoration: BoxDecoration(
                                                                color: Colors.black.withValues(alpha: 0.32),
                                                                borderRadius: BorderRadius.circular(20),
                                                                border: Border.all(
                                                                  color: Colors.white.withValues(alpha: 0.14),
                                                                  width: 1,
                                                                ),
                                                              ),
                                                              child: Text(
                                                                amountLabel,
                                                                style: GoogleFonts.manrope(
                                                                  color: post['isExpense'] == true
                                                                      ? const Color(0xFFFF6B6B)
                                                                      : const Color(0xFF4CD964),
                                                                  fontSize: 16,
                                                                  fontWeight: FontWeight.w800,
                                                                  letterSpacing: 0.2,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        Container(
                                                          decoration: const BoxDecoration(
                                                            gradient: LinearGradient(
                                                              begin: Alignment.topCenter,
                                                              end: Alignment.bottomCenter,
                                                              colors: [
                                                                Color(0x14000000),
                                                                Color(0x00000000),
                                                                Color(0x66000000),
                                                              ],
                                                              stops: [0.0, 0.55, 1.0],
                                                            ),
                                                          ),
                                                        ),
                                                        if (hasCaption)
                                                          Positioned(
                                                            left: 18,
                                                            right: 18,
                                                            bottom: 16,
                                                            child: Container(
                                                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                                              decoration: BoxDecoration(
                                                                color: const Color(0xFFD1C5BC).withValues(alpha: 0.88),
                                                                borderRadius: BorderRadius.circular(24),
                                                              ),
                                                              child: Text(
                                                                captionText,
                                                                textAlign: TextAlign.center,
                                                                maxLines: 2,
                                                                overflow: TextOverflow.ellipsis,
                                                                style: GoogleFonts.manrope(
                                                                  color: const Color(0xFF3A302B),
                                                                  fontSize: 15,
                                                                  fontWeight: FontWeight.w700,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          timeText,
                                          style: GoogleFonts.manrope(
                                            color: const Color(0xFFB9B1AA),
                                            fontSize: 18,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 216),
                                        // Thumbnail strip removed per request.
                                        const SizedBox(height: 10),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
    );
  }

  void _prevMonth() {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1, 1);
    });
    _loadMonthData();
  }

  void _nextMonth() {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 1);
    });
    _loadMonthData();
  }

  int _daysInMonth(DateTime m) => DateTime(m.year, m.month + 1, 0).day;

  int _firstWeekday(DateTime m) => DateTime(m.year, m.month, 1).weekday; // 1 = Mon

 @override
Widget build(BuildContext context) {
  final monthLabel = 'Tháng ${_visibleMonth.month} ${_visibleMonth.year}';
  final daysCount = _daysInMonth(_visibleMonth);
  final firstWeekday = _firstWeekday(_visibleMonth);

  return Scaffold(
    backgroundColor: const Color(0xFF080808),
    appBar: AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
        title: Text('Lịch', style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'Diagnostics',
            onPressed: _showDiagnostics,
            icon: const Icon(Icons.bug_report, color: Colors.white),
          ),
        ],
      automaticallyImplyLeading: true,
    ),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),

            // Month header with prev/next
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: _prevMonth,
                  icon: const Icon(Icons.chevron_left_rounded, color: Colors.white),
                ),
                Text(monthLabel, style: GoogleFonts.manrope(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                IconButton(
                  onPressed: _nextMonth,
                  icon: const Icon(Icons.chevron_right_rounded, color: Colors.white),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Finance summary row (Chi tiêu / Thu nhập)
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F0F0F),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: const BoxDecoration(
                            color: Color(0xFF2B2B2B),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Icon(Icons.arrow_upward_rounded, color: Color(0xFFFF6B6B)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Chi tiêu', style: GoogleFonts.manrope(color: Colors.white, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text('-${_formatCompact(_monthExpense)}', style: GoogleFonts.manrope(color: const Color(0xFFFF6B6B), fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: const BoxDecoration(
                            color: Color(0xFF2B2B2B),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Icon(Icons.arrow_downward_rounded, color: Color(0xFF4CD964)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Thu nhập', style: GoogleFonts.manrope(color: Colors.white, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text('+${_formatCompact(_monthIncome)}', style: GoogleFonts.manrope(color: const Color(0xFF4CD964), fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Weekday labels (Mon..Sun)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(7, (i) {
                final labels = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
                return Expanded(
                  child: Center(
                    child: Text(
                      labels[i], 
                      style: GoogleFonts.manrope(
                        color: labels[i] == 'CN' ? const Color(0xFFFF453A) : const Color(0xFF9A9A9A), 
                        fontSize: 13,
                        fontWeight: FontWeight.w600
                      ),
                    ),
                  ),
                );
              }),
            ),

            const SizedBox(height: 8),

            // Calendar grid
            Expanded(
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.0, // Thay đổi thành ô vuông tỉ lệ 1:1 tuyệt đối như Ảnh 2
                ),
                itemCount: firstWeekday - 1 + daysCount,
                itemBuilder: (context, index) {
                  final dayIndex = index - (firstWeekday - 2);
                  if (dayIndex <= 0) {
                    return const SizedBox.shrink();
                  }

                  final posts = _postsByDay[dayIndex] ?? [];
                  final hasPosts = posts.isNotEmpty;
                  final firstPost = hasPosts ? posts.first : null;

                  return GestureDetector(
                    onTap: () {
                      _openDayPreview(context, dayIndex, posts);
                    },
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            // 1. Ô nền vuông (Hoặc là ảnh cover, hoặc là ô trống màu xám tối)
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: hasPosts ? const Color(0xFF1E1E1E) : const Color(0xFF1C1C1E),
                                  borderRadius: BorderRadius.circular(12), // Bo góc nhẹ hiện đại giống Ảnh 2
                                ),
                                  child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: (() {
                                    try {
                                      if (hasPosts && firstPost != null) {
                                        final prov = _resizedImageProviderForPost(context, firstPost, constraints.maxWidth);
                                        if (prov != null) {
                                          return Image(
                                            image: prov,
                                            fit: BoxFit.cover,
                                            color: Colors.black.withValues(alpha: 0.25), // Làm tối ảnh nhẹ để nổi số ngày
                                            colorBlendMode: BlendMode.darken,
                                          );
                                        }
                                      }
                                    } catch (_) {}
                                    return hasPosts ? Container(color: const Color(0xFF343434)) : null;
                                  })(),
                                ),
                              ),
                            ),

                            // 2. Text hiển thị số ngày (Nằm chính giữa đè lên ô/ảnh)
                            Text(
                              '$dayIndex',
                              style: GoogleFonts.manrope(
                                color: hasPosts ? Colors.white : const Color(0xFF8E8E93),
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                shadows: hasPosts
                                    ? const [Shadow(color: Colors.black87, blurRadius: 6, offset: Offset(0, 1))]
                                    : null,
                              ),
                            ),

                            // 3. Badge số lượng ảnh nằm góc trên cùng bên phải của ô vuông (Nếu có ảnh)
                            if (hasPosts)
                              Positioned(
                                right: 5,
                                top: 5,
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  constraints: const BoxConstraints(
                                    minWidth: 16,
                                    minHeight: 16,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFBF5AF2), // Màu hồng/tím neon chuẩn Ảnh 2
                                    shape: BoxShape.circle,
                                    border: Border.all(color: const Color(0xFF1C1C1E), width: 1),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${posts.length}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      }
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}
