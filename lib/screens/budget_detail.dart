import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/finance_api_service.dart';
import '../services/calendar_api_service.dart';
import '../services/auth_session_service.dart';
import '../services/budget_storage_service.dart';
import '../services/calendar_storage_service.dart';
import '../services/notification_service.dart';
import '../services/calendar_refresh_notifier.dart';
import '../widgets/budget/budget_components.dart';

class BudgetDetailScreen extends StatefulWidget {
  final Map<String, dynamic> item;
  final String categoryKey;
  const BudgetDetailScreen({super.key, required this.item, required this.categoryKey});

  @override
  State<BudgetDetailScreen> createState() => _BudgetDetailScreenState();
}

class _BudgetDetailScreenState extends State<BudgetDetailScreen> {
  final BudgetStorageService _storage = BudgetStorageService();
  final AuthSessionService _sessionService = AuthSessionService();
  final FinanceApiService _financeApiService = FinanceApiService();
  bool _loading = true;
  Map<String, dynamic>? _item;
  String _monthKey = '';
  bool _didChange = false;
  bool _canPop = false;

  final CalendarStorageService _calendarStorageService = CalendarStorageService();
  final List<FlSpot> _chartSpots = [];
  int _actualDailySpend = 0;
  int _estimatedDailySpend = 0;
  int _safeToSpendToday = 0;
  int _totalSpent = 0;
  int _daysRemaining = 0;
  List<Map<String, dynamic>> _relatedPosts = [];
  String _chartPeriodLabel = 'Tháng';
  String _displayRange = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _item = Map<String, dynamic>.from(widget.item);
    if (!mounted) return;

    // Load related posts from calendar
    final prefs = await SharedPreferences.getInstance();
    final storageKey = await _calendarStorageService.currentCalendarKey();
    final raw = prefs.getString(storageKey);
    List<Map<String, dynamic>> posts = [];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final postItem in decoded) {
            if (postItem is Map) {
              final catKey = postItem['categoryKey']?.toString() ?? postItem['categoryLabel']?.toString() ?? postItem['category_name']?.toString() ?? '';
              if (catKey == widget.categoryKey || catKey.toLowerCase() == widget.categoryKey.toLowerCase()) {
                posts.add(Map<String, dynamic>.from(postItem));
              }
            }
          }
        }
      } catch (_) {}
    }

    _monthKey = _item?['monthKey']?.toString() ?? _currentMonthKey();
    _relatedPosts = posts;
    _calculateChartData();

    if (!mounted) return;
    setState(() {
      _loading = false;
    });
  }

  void _calculateChartData() {
    if (_item == null) return;
    final limit = int.tryParse(_item?['limit']?.toString() ?? '0') ?? 0;
    final now = DateTime.now();

    DateTime startDate;
    DateTime endDate;
    if (_item!['startDate'] != null && _item!['endDate'] != null) {
      startDate = DateTime.parse(_item!['startDate'].toString()).toLocal();
      endDate = DateTime.parse(_item!['endDate'].toString()).toLocal();
      startDate = DateTime(startDate.year, startDate.month, startDate.day);
      endDate = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
    } else {
      final period = _rangeFromMonthKey(_monthKey.isNotEmpty ? _monthKey : _currentMonthKey());
      startDate = period.start;
      endDate = period.end;
      endDate = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
    }

    _displayRange = '${startDate.day.toString().padLeft(2, '0')}/${startDate.month.toString().padLeft(2, '0')} - ${endDate.day.toString().padLeft(2, '0')}/${endDate.month.toString().padLeft(2, '0')}';

    final totalDays = endDate.difference(startDate).inDays + 1;
    final isGroupedByMonth = totalDays > 62;
    int totalGroups = isGroupedByMonth 
        ? (endDate.year - startDate.year) * 12 + endDate.month - startDate.month + 1 
        : totalDays;

    String periodLabel = 'Ngày';
    if (totalDays > 92) {
      periodLabel = 'Năm';
    } else if (totalDays > 31) {
      periodLabel = 'Quý';
    } else if (totalDays >= 28) {
      periodLabel = 'Tháng';
    } else if (totalDays >= 7) {
      periodLabel = 'Tuần';
    } else {
      periodLabel = '$totalDays Ngày';
    }
    _chartPeriodLabel = periodLabel;

    final groupedSpend = <int, int>{};
    _totalSpent = 0;

    for (final post in _relatedPosts) {
      final dateStr = post['localDateTime']?.toString() ?? post['entryTs']?.toString() ?? post['date']?.toString();
      if (dateStr == null) continue;
      final dt = DateTime.tryParse(dateStr)?.toLocal();
      if (dt == null) continue;
      
      if (dt.isAfter(startDate.subtract(const Duration(seconds: 1))) && dt.isBefore(endDate.add(const Duration(seconds: 1)))) {
        final amount = int.tryParse(post['amount']?.toString() ?? '0') ?? 0;
        final kind = post['kind']?.toString() ?? 'expense';
        if (kind != 'income') {
          int groupIndex;
          if (isGroupedByMonth) {
            groupIndex = (dt.year - startDate.year) * 12 + dt.month - startDate.month + 1;
          } else {
            groupIndex = dt.difference(startDate).inDays + 1;
          }
          groupedSpend[groupIndex] = (groupedSpend[groupIndex] ?? 0) + amount;
          _totalSpent += amount;
        }
      }
    }

    int daysElapsed = 0;
    if (now.isAfter(endDate)) {
      daysElapsed = totalDays;
    } else if (now.isBefore(startDate)) {
      daysElapsed = 0;
    } else {
      daysElapsed = now.difference(startDate).inDays + 1;
    }

    _actualDailySpend = daysElapsed > 0 ? (_totalSpent / daysElapsed).round() : 0;
    _estimatedDailySpend = totalDays > 0 ? (limit / totalDays).round() : 0;

    int daysRemaining = 0;
    if (now.isBefore(startDate)) {
      daysRemaining = totalDays;
    } else if (now.isAfter(endDate)) {
      daysRemaining = 0;
    } else {
      // Create date-only versions to avoid time differences causing issues
      final nowDay = DateTime(now.year, now.month, now.day);
      final endDay = DateTime(endDate.year, endDate.month, endDate.day);
      daysRemaining = endDay.difference(nowDay).inDays + 1; // bao gồm cả ngày hôm nay
    }
    _daysRemaining = daysRemaining;
    
    final remainingBudget = limit - _totalSpent;
    final clampedRemaining = remainingBudget < 0 ? 0 : remainingBudget;
    _safeToSpendToday = daysRemaining > 0 ? (clampedRemaining / daysRemaining).round() : clampedRemaining;

    _chartSpots.clear();
    for (int i = 1; i <= totalGroups; i++) {
      _chartSpots.add(FlSpot(i.toDouble(), (groupedSpend[i] ?? 0).toDouble()));
    }

    if (_actualDailySpend > _estimatedDailySpend) {
      final name = _item?['name']?.toString() ?? widget.categoryKey;
      NotificationService().showWarningNotification(name, _actualDailySpend, _estimatedDailySpend);
    }
  }

  String _formatVnd(int value) =>
      NumberFormat.decimalPattern('vi_VN').format(value);

  String _currentMonthKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
  }

  DateTimeRange _rangeFromMonthKey(String monthKey) {
    final parts = monthKey.split('-');
    final year =
        int.tryParse(parts.length == 2 ? parts[0] : '') ?? DateTime.now().year;
    final month =
        int.tryParse(parts.length == 2 ? parts[1] : '') ?? DateTime.now().month;
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 0);
    return DateTimeRange(start: start, end: end);
  }

  Future<void> _saveEditedItem({
    required String name,
    required int limitAmount,
    required DateTimeRange period,
    String? newIconKey,
  }) async {
    final nextMonthKey =
        '${period.start.year.toString().padLeft(4, '0')}-${period.start.month.toString().padLeft(2, '0')}';
    final token = await _sessionService.getToken();
    final categoryKey = widget.categoryKey;
    final iconKey = (newIconKey != null && newIconKey.isNotEmpty) 
        ? newIconKey 
        : ((_item?['iconKey']?.toString().trim().isNotEmpty == true)
            ? _item!['iconKey'].toString()
            : categoryKey);
    final kind = _item?['kind']?.toString();
    final color = _item?['color']?.toString();
    final categoryId = int.tryParse(_item?['categoryId']?.toString() ?? '');
    final isRepeat = _item?['isRepeat'] == true;
    final budgetId = _item?['id']?.toString();

    if (token != null && token.trim().isNotEmpty) {
      await _financeApiService.upsertCategory(
        token: token,
        id: categoryId?.toString(),
        name: name,
        kind: kind,
        iconKey: iconKey,
        color: color,
      );
      await _financeApiService.upsertBudget(
        token: token,
        id: budgetId,
        name: name,
        limitAmount: limitAmount,
        monthKey: nextMonthKey,
        categoryId: categoryId,
        slug: categoryKey,
        kind: kind,
        iconKey: iconKey,
        color: color,
        isRepeat: isRepeat,
        startDate: DateFormat('yyyy-MM-dd').format(period.start),
        endDate: DateFormat('yyyy-MM-dd').format(period.end),
      );
    }

    final items = await _storage.readBudgetItems();
    final updatedItems = items.map((item) {
      final myId = _item?['id']?.toString() ?? '';
      final itemId = item['id']?.toString() ?? '';
      
      bool isMatch = false;
      if (myId.isNotEmpty && itemId.isNotEmpty) {
        isMatch = myId == itemId;
      } else {
        final ik = (item['categoryKey'] ?? item['key'])?.toString() ?? '';
        isMatch = ik == widget.categoryKey;
      }
      
      if (!isMatch) return item;
      final next = Map<String, dynamic>.from(item);
      next['name'] = name;
      next['limit'] = limitAmount;
      next['monthKey'] = nextMonthKey;
      next['updatedAt'] = DateTime.now().millisecondsSinceEpoch.toString();
      next['startDate'] = DateFormat('yyyy-MM-dd').format(period.start);
      next['endDate'] = DateFormat('yyyy-MM-dd').format(period.end);
      if (newIconKey != null && newIconKey.isNotEmpty) {
        next['iconKey'] = newIconKey;
      }
      return next;
    }).toList();
    await _storage.saveBudgetItems(updatedItems);

    final groups = await _storage.readBudgetGroups();
    final updatedGroups = groups.map((group) {
      if ((group['key'] ?? '').trim().toLowerCase() !=
          categoryKey.trim().toLowerCase()) {
        return group;
      }
      final nextGroup = {...group, 'label': name};
      if (newIconKey != null && newIconKey.isNotEmpty) {
        nextGroup['iconKey'] = newIconKey;
      }
      return nextGroup;
    }).toList();
    await _storage.saveBudgetGroups(updatedGroups);
    // Notify listeners so other screens (Budget list, Home) refresh
    try {
      calendarRefreshNotifier.value++;
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _item = {
        ...?_item,
        'name': name,
        'limit': limitAmount,
        'monthKey': nextMonthKey,
        'updatedAt': DateTime.now().millisecondsSinceEpoch.toString(),
        'startDate': period.start.toIso8601String(),
        'endDate': period.end.toIso8601String(),
      };
      if (newIconKey != null && newIconKey.isNotEmpty) {
        _item?['iconKey'] = newIconKey;
      }
      _monthKey = nextMonthKey;
      _didChange = true;
      _calculateChartData();
    });
    // Reload parent list data to apply iconKey change immediately
    // so that when user navigates back, the icon is already updated.
    Navigator.of(context).pop(true);
  }

  Future<void> _showEditDialog() async {
    final currentName = _item?['name']?.toString() ?? widget.categoryKey;
    final currentLimit = int.tryParse(_item?['limit']?.toString() ?? '0') ?? 0;
    
    DateTimeRange selectedPeriod;
    if (_item?['startDate'] != null && _item?['endDate'] != null) {
      selectedPeriod = DateTimeRange(
        start: DateTime.parse(_item!['startDate'].toString()).toLocal(),
        end: DateTime.parse(_item!['endDate'].toString()).toLocal(),
      );
    } else {
      selectedPeriod = _rangeFromMonthKey(
        _monthKey.isNotEmpty ? _monthKey : _currentMonthKey(),
      );
    }

    if (!mounted) return;
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (dialogContext) {
        return SafeKeyboardPadding(
          child: BudgetEditSheet(
            initialName: currentName,
            initialAmount: currentLimit,
            initialPeriod: selectedPeriod,
            initialIconKey: _item?['iconKey']?.toString() ?? widget.categoryKey,
          ),
        );
      },
    );

    if (result == null) return;
    final name = result['name']?.toString() ?? '';
    final amount = result['amount'] is int
        ? result['amount'] as int
        : int.tryParse(result['amount']?.toString() ?? '') ?? 0;
    final period = result['period'] is DateTimeRange
        ? result['period'] as DateTimeRange
        : _rangeFromMonthKey(_currentMonthKey());
    final pickedIconKey = result['iconKey']?.toString();
    if (name.isEmpty || amount <= 0) return;
    await _saveEditedItem(
      name: name,
      limitAmount: amount,
      period: period,
      newIconKey: pickedIconKey,
    );
  }

  Future<void> _deleteItem() async {
    final token = await _sessionService.getToken();
    final budgetId = int.tryParse(_item?['id']?.toString() ?? '');

    if (token != null &&
        token.trim().isNotEmpty &&
        budgetId != null &&
        budgetId > 0) {
      await _financeApiService.deleteBudget(token: token, budgetId: budgetId);
    }

    final items = await _storage.readBudgetItems();
    final next = items.where((it) {
      final id = it['id']?.toString() ?? '';
      final myId = _item?['id']?.toString() ?? '';
      if (myId.isNotEmpty && id.isNotEmpty) {
        return id != myId;
      }
      final ik =
          (it['iconKey'] ?? it['categoryKey'] ?? it['key'])?.toString() ?? '';
      return ik != widget.categoryKey;
    }).toList();
    await _storage.saveBudgetItems(next);
    if (!mounted) return;
    _didChange = true;
    Navigator.of(context).pop(true);
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
    final s = absValue.toString();
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
    return '${negative ? '-' : ''}${buffer.toString().split('').reversed.join()}đ';
  }

  String _formatViewerTime(Map<String, dynamic> post) {
    final raw = post['entryTs']?.toString() ?? post['date']?.toString() ?? '';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return '';
    final local = parsed.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  ImageProvider? _postImageProvider(Map<String, dynamic> post) {
    final path = post['imageUrl']?.toString().trim() ?? post['imagePath']?.toString().trim();
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return NetworkImage(path);
    }
    try {
      final file = File(path);
      if (file.existsSync()) {
        return FileImage(file);
      }
    } catch (_) {}
    if (path.startsWith('/uploads/') || path.startsWith('uploads/')) {
      final resolved = CalendarApiService.resolveAssetUrl(path);
      if (resolved.isNotEmpty) return NetworkImage(resolved);
    }
    return null;
  }

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

  void _openGalleryPreview(BuildContext context, int initialIndex) {
    var selectedIndex = initialIndex;
    final pageController = PageController(initialPage: selectedIndex);
    
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'gallery_preview',
      barrierColor: Colors.black.withValues(alpha: 0.9),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Material(
              color: Colors.black,
              child: SafeArea(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.black, Colors.black, Colors.black],
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
                              IconButton(
                                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                                onPressed: () => Navigator.of(dialogContext).pop(),
                              ),
                              Column(
                                children: [
                                  Text(
                                    _item?['name']?.toString() ?? widget.categoryKey,
                                    style: GoogleFonts.manrope(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    '${selectedIndex + 1}/${_relatedPosts.length}',
                                    style: GoogleFonts.manrope(
                                      color: const Color(0xFFCFC8C3),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 48),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: Center(
                            child: PageView.builder(
                              controller: pageController,
                              itemCount: _relatedPosts.length,
                              onPageChanged: (index) => setState(() {
                                selectedIndex = index;
                              }),
                              itemBuilder: (context, index) {
                                final post = _relatedPosts[index];
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
                                                              child: Icon(Icons.image_rounded, color: Colors.white54, size: 56),
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
                                                                  color: post['isExpense'] == true ? const Color(0xFFFF6B6B) : const Color(0xFF4CD964),
                                                                  fontSize: 16,
                                                                  fontWeight: FontWeight.w800,
                                                                  letterSpacing: 0.2,
                                                                ),
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
                                        const SizedBox(height: 12),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            _item?['name']?.toString() ?? widget.categoryKey,
                                            style: GoogleFonts.manrope(
                                              color: Colors.black,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 50),
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

  @override
  Widget build(BuildContext context) {
    final name = _item?['name']?.toString() ?? widget.categoryKey;
    final limit = _item != null
        ? (int.tryParse(_item!['limit']?.toString() ?? '0') ?? 0)
        : 0;
    final spent = _item != null
        ? (int.tryParse(_item!['spent']?.toString() ?? '0') ?? 0)
        : 0;
    final remaining = (limit - spent).clamp(0, limit);
    final progress = limit <= 0 ? 0.0 : (spent / limit).clamp(0.0, 1.0);
    final kind = _item?['kind']?.toString() ?? 'expense';
    final themeColor = kind == 'income' ? const Color(0xFF2ECC71) : Colors.redAccent;

    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        setState(() {
          _canPop = true;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.of(context).pop(result ?? _didChange);
          }
        });
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () => Navigator.of(context).pop(_didChange),
          ),
          title: Text(
            name,
            style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
          ),
          actions: [
            TextButton.icon(
              onPressed: _showEditDialog,
              icon: const Icon(
                Icons.edit_outlined,
                color: Colors.white,
                size: 18,
              ),
              label: Text(
                'Sửa',
                style: GoogleFonts.manrope(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(18.0),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1C),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: themeColor.withValues(alpha: 0.18),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: buildCategoryWidget(
                                    _item?['iconKey']?.toString() ?? widget.categoryKey,
                                    size: 22,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _formatVnd(limit),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Đã chi',
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.6,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatVnd(spent),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'Còn lại',
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.6,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatVnd(remaining),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 10,
                              backgroundColor: Colors.white10,
                              valueColor: AlwaysStoppedAnimation(themeColor),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(
                                Icons.calendar_today,
                                color: Colors.white54,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _displayRange,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.85,
                                      ),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    _daysRemaining > 1
                                        ? (_chartPeriodLabel == 'Tuần' || _chartPeriodLabel == 'Tháng' || _chartPeriodLabel == 'Quý' || _chartPeriodLabel == 'Năm')
                                            ? 'Còn $_daysRemaining ngày hết ${_chartPeriodLabel.toLowerCase()}'
                                            : 'Còn $_daysRemaining ngày'
                                        : _daysRemaining == 1
                                            ? 'Hôm nay là ngày cuối cùng'
                                            : 'Đã hết hạn',
                                    style: const TextStyle(color: Colors.white54),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  'Phân tích chi tiêu',
                                  style: GoogleFonts.manrope(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (_chartPeriodLabel.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.2),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.auto_awesome,
                                        size: 14,
                                        color: Color(0xFF5B4BFF),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _chartPeriodLabel,
                                        style: GoogleFonts.manrope(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            height: 180,
                            child: _chartSpots.isEmpty
                                ? const Center(
                                    child: Text(
                                      'Chưa có dữ liệu giao dịch',
                                      style: TextStyle(color: Colors.white54),
                                    ),
                                  )
                                : LineChart(
                                    LineChartData(
                                      gridData: const FlGridData(show: false),
                                      titlesData: const FlTitlesData(show: false),
                                      borderData: FlBorderData(show: false),
                                      lineBarsData: [
                                        LineChartBarData(
                                          spots: _chartSpots,
                                          isCurved: true,
                                          color: themeColor,
                                          barWidth: 3,
                                          isStrokeCapRound: true,
                                          dotData: const FlDotData(show: false),
                                          belowBarData: BarAreaData(
                                            show: true,
                                            gradient: LinearGradient(
                                              colors: [
                                                themeColor.withValues(alpha: 0.3),
                                                themeColor.withValues(alpha: 0.0),
                                              ],
                                              begin: Alignment.topCenter,
                                              end: Alignment.bottomCenter,
                                            ),
                                          ),
                                        ),
                                      ],
                                      lineTouchData: LineTouchData(
                                        touchTooltipData: LineTouchTooltipData(
                                          getTooltipColor: (spot) => const Color(0xFF2C2C2E),
                                          getTooltipItems: (touchedSpots) {
                                            return touchedSpots.map((spot) {
                                              return LineTooltipItem(
                                                _formatVnd(spot.y.toInt()),
                                                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                              );
                                            }).toList();
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.1),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      const Text(
                                        'Hôm nay bạn được tiêu',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        _formatVnd(_safeToSpendToday),
                                        style: TextStyle(
                                          color: _safeToSpendToday == 0 && (limit - _totalSpent) < 0 
                                              ? Colors.redAccent 
                                              : const Color(0xFF2ECC71),
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),
                    Row(
                      children: [
                        const Text(
                          'Ảnh giao dịch',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_relatedPosts.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Chưa có ảnh nào.',
                            style: TextStyle(color: Colors.white54, fontSize: 15),
                          ),
                        ),
                      )
                    else
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 1.0,
                        ),
                        itemCount: _relatedPosts.length,
                        itemBuilder: (context, index) {
                          final post = _relatedPosts[index];
                          final provider = _resizedImageProviderForPost(context, post, 120.0);
                          final hasImage = provider != null;
                          return GestureDetector(
                            onTap: () => _openGalleryPreview(context, index),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                color: const Color(0xFF2C2C2E),
                                child: hasImage
                                    ? Image(image: provider, fit: BoxFit.cover)
                                    : const Center(
                                        child: Icon(Icons.image_rounded, color: Colors.white24, size: 28),
                                      ),
                              ),
                            ),
                          );
                        },
                      ),

                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (dctx) => AlertDialog(
                              title: const Text('Xác nhận'),
                              content: const Text(
                                'Bạn có chắc muốn xóa hạng mục này?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(dctx).pop(false),
                                  child: const Text('Huỷ'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.of(dctx).pop(true),
                                  child: const Text('Xóa'),
                                ),
                              ],
                            ),
                          );
                          if (ok == true) await _deleteItem();
                        },
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Text(
                            'Xóa',
                            style: TextStyle(
                              color: Color(0xFFFF4D4D),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
