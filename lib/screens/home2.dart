import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/services/auth_session_service.dart';
import 'package:flutter_application_1/services/calendar_api_service.dart';
import 'package:flutter_application_1/services/calendar_refresh_notifier.dart';
import 'package:flutter_application_1/services/calendar_storage_service.dart';
import 'package:flutter_application_1/services/finance_api_service.dart';
import 'package:flutter_application_1/services/post_api_service.dart';
import 'package:flutter_application_1/services/budget_storage_service.dart';

class Home2 extends StatefulWidget {
  final File imageFile;
  final DateTime? capturedAt;

  const Home2({super.key, required this.imageFile, this.capturedAt});

  @override
  State<Home2> createState() => _Home2State();
}

class _Home2State extends State<Home2> {
  final TextEditingController _captionController = TextEditingController();

  // Đổi giá trị mặc định thành chuỗi rỗng để sử dụng hintText làm mờ số 0
  final TextEditingController _amountController = TextEditingController(
    text: '',
  );
  bool _isFormatting = false;

  bool _isUploading = false;
  bool _isExpense = true; // true: Chi tiêu, false: Thu nhập

  String? _displayAmount;
  bool _displayIsExpense = true;
  int _pendingAmount = 0;
  String? _selectedCategoryKey;
  String? _selectedCategoryLabel;
  final AuthSessionService _sessionService = AuthSessionService();
  final CalendarApiService _apiService = CalendarApiService();
  final CalendarStorageService _storageService = CalendarStorageService();
  final FinanceApiService _financeApiService = FinanceApiService();
  final PostApiService _postApiService = PostApiService();
  final BudgetStorageService _budgetStorageService = BudgetStorageService();
  // removed unused fields: _lastSafeAmountText, _maxAllowedVnd

  // HÀM 1: Đăng bài khi ấn nút Định vị ở giữa
  Future<void> uploadPost() async {
    if (_isUploading) return;

    setState(() => _isUploading = true);
    await Future.delayed(const Duration(seconds: 1));

    await _saveCalendarPost();

    if (!mounted) return;
    setState(() => _isUploading = false);

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Đăng bài thành công')));
    Navigator.pop(context);
  }

  Future<void> _saveCalendarPost() async {
    final now = widget.capturedAt ?? DateTime.now();
    final amountToSave = _pendingAmount > 0 ? _pendingAmount : _parseAmount();
    final token = await _sessionService.getToken();
    final selectedCategoryKey = _selectedCategoryKey?.trim();
    final selectedCategoryId = await _resolveRemoteCategoryId(
      selectedCategoryKey,
      _selectedCategoryLabel,
    );

    if (token != null && token.trim().isNotEmpty) {
      final clientLocalId = now.millisecondsSinceEpoch.toString();
      final remote = await _apiService.createEntry(
        token: token,
        imageFile: widget.imageFile,
        amount: amountToSave,
        isExpense: _isExpense,
        dateKey: _dateKey(now),
        date: now.toUtc().toIso8601String(),
        clientLocalId: clientLocalId,
        categoryId: selectedCategoryId,
        categoryKey: selectedCategoryKey,
        slug: selectedCategoryKey,
        note: _captionController.text.trim(),
      );

      if (remote.success &&
          remote.data != null &&
          remote.data is Map<String, dynamic>) {
        final serverData = Map<String, dynamic>.from(remote.data!);
        await _syncTransactionForBudget(
          token: token,
          amount: amountToSave,
          now: now,
          serverData: serverData,
          categoryId: selectedCategoryId,
        );
        await _saveCalendarPostLocally(
          now: now,
          amountToSave: amountToSave,
          serverData: serverData,
        );
        await _syncSocialPost(token: token);
        return;
      }
    }

    await _saveCalendarPostLocally(now: now, amountToSave: amountToSave);
    if (token != null && token.trim().isNotEmpty) {
      await _syncSocialPost(token: token);
    }
  }

  Future<void> _syncSocialPost({required String token}) async {
    final caption = _captionController.text.trim();
    final result = await _postApiService.createPost(
      token: token,
      imageFile: widget.imageFile,
      caption: caption,
    );

    if (result.success) {
      try {
        calendarRefreshNotifier.value++;
      } catch (_) {}
    }
  }

  Future<void> _syncTransactionForBudget({
    required String token,
    required int amount,
    required DateTime now,
    required Map<String, dynamic> serverData,
    required int? categoryId,
  }) async {
    if (amount <= 0 || categoryId == null) return;

    final calendarEntryId = int.tryParse(serverData['id']?.toString() ?? '');
    if (calendarEntryId == null) return;

    final result = await _financeApiService.createTransaction(
      token: token,
      amount: amount,
      isExpense: _isExpense,
      transactionDate: _dateKey(now),
      categoryId: categoryId,
      note: _captionController.text.trim(),
      calendarEntryId: calendarEntryId,
    );

    // If the transaction sync succeeded on the server, notify listeners so
    // that UI screens (like the Budget screen) can refresh and pick up the
    // latest spent amounts returned by the finance API.
    if (result.success) {
      try {
        calendarRefreshNotifier.value++;
      } catch (_) {}
    }
  }

  Future<void> _saveCalendarPostLocally({
    required DateTime now,
    required int amountToSave,
    Map<String, dynamic>? serverData,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final storageKey = await _storageService.currentCalendarKey();
    final raw = prefs.getString(storageKey);
    final posts = <Map<String, dynamic>>[];

    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              posts.add(Map<String, dynamic>.from(item));
            }
          }
        }
      } catch (_) {}
    }

    final storedImagePath = await _persistCalendarImage(widget.imageFile);
    final localId = now.millisecondsSinceEpoch.toString();
    final entry = <String, dynamic>{
      'id': serverData != null && serverData['id'] != null
          ? serverData['id'].toString()
          : localId,
      'localId': localId,
      'imagePath': storedImagePath,
      'localDateTime': now.toLocal().toIso8601String(),
      'date': serverData != null && serverData['entryTs'] != null
          ? DateTime.tryParse(
                  serverData['entryTs'].toString(),
                )?.toUtc().toIso8601String() ??
                now.toUtc().toIso8601String()
          : now.toUtc().toIso8601String(),
      'dateKey': serverData != null && serverData['dateKey'] != null
          ? serverData['dateKey'].toString()
          : _dateKey(now),
      'amount': serverData != null && serverData['amount'] != null
          ? int.tryParse(serverData['amount'].toString()) ?? amountToSave
          : amountToSave,
      'isExpense': serverData != null && serverData['isExpense'] != null
          ? serverData['isExpense'] == true
          : _isExpense,
      'note': serverData != null && serverData['note'] != null
          ? serverData['note'].toString()
          : _captionController.text.trim(),
      'categoryId': serverData != null && serverData['categoryId'] != null
          ? serverData['categoryId'].toString()
          : _selectedCategoryKey,
      'categoryKey': serverData != null && serverData['categoryKey'] != null
          ? serverData['categoryKey'].toString()
          : _selectedCategoryKey,
      'categoryLabel': _selectedCategoryLabel,
      'imageUrl': serverData != null && serverData['imageUrl'] != null
          ? serverData['imageUrl'].toString()
          : null,
      'entryTs': serverData != null && serverData['entryTs'] != null
          ? serverData['entryTs'].toString()
          : null,
    };

    // If server returned clientLocalId, try to replace existing local record
    final clientLocalFromServer = serverData != null
        ? (serverData['clientLocalId'] ?? serverData['localId'])?.toString()
        : null;
    if (clientLocalFromServer != null && clientLocalFromServer.isNotEmpty) {
      final idx = posts.indexWhere(
        (p) => p['localId']?.toString() == clientLocalFromServer,
      );
      if (idx != -1) {
        posts[idx] = entry;
      } else {
        posts.add(entry);
      }
    } else {
      posts.add(entry);
    }

    await prefs.setString(storageKey, jsonEncode(posts));
    calendarRefreshNotifier.value++;
  }

  Future<String> _persistCalendarImage(File sourceFile) async {
    final directory = await getApplicationDocumentsDirectory();
    final calendarDir = Directory(p.join(directory.path, 'calendar_posts'));
    if (!calendarDir.existsSync()) {
      calendarDir.createSync(recursive: true);
    }

    final safeName =
        '${DateTime.now().millisecondsSinceEpoch}_${p.basename(sourceFile.path)}';
    final targetPath = p.join(calendarDir.path, safeName);
    final storedFile = await sourceFile.copy(targetPath);
    return storedFile.path;
  }

  Future<int?> _resolveRemoteCategoryId(String? key, String? label) async {
    final token = await _sessionService.getToken();
    if (token == null || token.trim().isEmpty) return null;
    if (key == null || key.trim().isEmpty) return null;

    final remote = await _financeApiService.getCategories(token: token);
    if (!remote.success ||
        remote.data == null ||
        remote.data!['data'] is! List) {
      return null;
    }

    for (final entry in remote.data!['data'] as List) {
      if (entry is! Map) continue;
      final item = Map<String, dynamic>.from(entry);
      final itemId = item['id']?.toString() ?? '';
      final itemKey = item['key']?.toString() ?? item['slug']?.toString() ?? '';
      final itemLabel =
          item['label']?.toString() ?? item['name']?.toString() ?? '';
      if (itemId == key ||
          itemKey == key ||
          (label != null && itemLabel == label)) {
        return int.tryParse(itemId);
      }
    }

    return null;
  }

  int _parseAmount() {
    final digits = _amountController.text.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(digits) ?? 0;
  }

  String _dateKey(DateTime dateTime) {
    final local = dateTime.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _groupSignature(Map<String, String> group) {
    final key = group['key']?.trim().toLowerCase() ?? '';
    final label = group['label']?.trim().toLowerCase() ?? '';
    if (key.isNotEmpty) return key;
    return label;
  }

  List<Map<String, String>> _dedupeAndFilterGroups(
    Iterable<Map<String, String>> groups,
  ) {
    final seen = <String>{};
    final result = <Map<String, String>>[];

    for (final group in groups) {
      final kind = group['kind']?.trim() ?? '';
      final label = group['label']?.trim() ?? '';
      final key = group['key']?.trim() ?? '';

      if (kind.isEmpty || label.isEmpty) continue;

      // Candidates to detect duplicates: key and label (case-insensitive)
      final candidates = <String>[];
      if (key.isNotEmpty) candidates.add(key.toLowerCase());
      if (label.isNotEmpty) candidates.add(label.toLowerCase());

      var isDuplicate = false;
      for (final c in candidates) {
        if (c.isEmpty) continue;
        if (seen.contains(c)) {
          isDuplicate = true;
          break;
        }
      }
      if (isDuplicate) continue;

      // mark both key and label as seen so future groups with same label or key are skipped
      for (final c in candidates) {
        if (c.isNotEmpty) seen.add(c);
      }

      result.add({'key': key, 'label': label, 'kind': kind});
    }

    return result;
  }

  double _amountFontSize(String text) {
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    final length = digits.length;
    if (length <= 6) return 42;
    if (length <= 8) return 36;
    if (length <= 10) return 30;
    return 24;
  }

  @override
  void initState() {
    super.initState();
    _amountController.addListener(() {
      if (_isFormatting) return;
      _isFormatting = true;
      final raw = _amountController.text;
      // Remove any non-digit characters
      final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.isEmpty) {
        _amountController.text = '';
        _amountController.selection = TextSelection.collapsed(offset: 0);
        _isFormatting = false;
        return;
      }
      final formatted = _formatWithDots(digits);
      if (formatted != raw) {
        _amountController.text = formatted;
        _amountController.selection = TextSelection.collapsed(
          offset: formatted.length,
        );
      }
      _isFormatting = false;
    });
    // Listen for external changes (budget/group edits) so UI here updates
    try {
      calendarRefreshNotifier.addListener(_handleCalendarRefresh);
    } catch (_) {}
  }

  void _handleCalendarRefresh() {
    if (!mounted) return;
    _refreshSelectedCategoryLabel();
  }

  Future<void> _refreshSelectedCategoryLabel() async {
    final key = _selectedCategoryKey?.trim();
    if (key == null || key.isEmpty) return;

    try {
      List<Map<String, String>> groups = [];
      final token = await _sessionService.getToken();
      if (token != null && token.trim().isNotEmpty) {
        final remote = await _financeApiService.getCategories(token: token);
        if (remote.success &&
            remote.data != null &&
            remote.data!['data'] is List) {
          groups = (remote.data!['data'] as List)
              .whereType<Map>()
              .map((entry) => Map<String, dynamic>.from(entry))
              .where(
                (item) => item['isGlobal'] != true,
              ) // ignore global defaults
              .map((item) {
                return {
                  'key':
                      item['key']?.toString() ??
                      item['slug']?.toString() ??
                      item['id']?.toString() ??
                      '',
                  'label':
                      item['label']?.toString() ??
                      item['name']?.toString() ??
                      '',
                  'kind': item['kind']?.toString() ?? '',
                };
              })
              .where((e) => (e['key'] ?? '').isNotEmpty)
              .toList();
        } else {
          groups = await _budgetStorageService.readBudgetGroups();
        }
      } else {
        groups = await _budgetStorageService.readBudgetGroups();
      }

      final lk = key.toLowerCase();
      Map<String, String> found = {};
      for (final g in groups) {
        final gKey = (g['key'] ?? '').toString().trim().toLowerCase();
        final gSlug = (g['slug'] ?? g['key'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        final gLabel = (g['label'] ?? '').toString().trim().toLowerCase();
        if (gKey.isNotEmpty && (gKey == lk || gSlug == lk || gLabel == lk)) {
          found = {
            'key': g['key'] ?? '',
            'label': g['label'] ?? '',
            'kind': g['kind'] ?? '',
          };
          break;
        }
      }

      if (!mounted) return;

      setState(() {
        if (found.isNotEmpty) {
          _selectedCategoryKey = found['key'];
          _selectedCategoryLabel = found['label'];
        } else {
          _selectedCategoryKey = null;
          _selectedCategoryLabel = null;
        }
      });
    } catch (_) {}
  }

  int _parseAmountFromString(String s) {
    return _parseAmountInputToVnd(s);
  }

  int _parseAmountInputToVnd(String s) {
    if (s.trim().isEmpty) return 0;
    final input = s.trim();
    final lower = input.toLowerCase();
    final hasTr = lower.contains('tr');
    final hasTonly =
        !hasTr && (lower.contains('t')); // 'T' or 't' as billion marker

    final match = RegExp(r'[0-9.,]+').firstMatch(input);
    if (match == null) return 0;
    var numToken = match.group(0) ?? '';

    // Decide whether '.' is thousands separator or decimal point
    if (numToken.contains('.')) {
      final parts = numToken.split('.');
      final lastLen = parts.isNotEmpty ? parts.last.length : 0;
      // If last group has length 3, assume thousands separators -> remove all dots
      if (lastLen == 3 && parts.length > 1) {
        numToken = numToken.replaceAll('.', '');
      } else {
        // treat dot as decimal separator
      }
    }
    // normalize decimal comma to dot
    numToken = numToken.replaceAll(',', '.');

    final valueDouble = double.tryParse(numToken) ?? 0.0;
    double vnd = valueDouble;
    if (hasTr) {
      vnd = valueDouble * 1000000.0;
    } else if (hasTonly) {
      vnd = valueDouble * 1000000000.0;
    }
    final result = vnd.round();
    return result;
  }

  String _formatCompactFromInt(int value) {
    if (value >= 1000000000) {
      final doubleVal = value / 1000000000;
      final formatted = (value % 1000000000 == 0)
          ? doubleVal.toStringAsFixed(0)
          : doubleVal.toStringAsFixed(1);
      return '${formatted}T';
    }
    if (value >= 1000000) {
      final doubleVal = value / 1000000;
      final formatted = (value % 1000000 == 0)
          ? doubleVal.toStringAsFixed(0)
          : doubleVal.toStringAsFixed(1);
      return '${formatted}tr';
    }
    return _formatWithDots(value.toString());
  }

  // HÀM 2: Mở ví - Giao diện số 0 mờ (Hint Text) thông minh
  Future<void> openWallet() async {
    // Reset về chuỗi rỗng khi mở ví để hiện số 0 mờ
    _amountController.text = '';

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (bottomSheetContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              decoration: const BoxDecoration(
                color: Color(0xFF000000),
                borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
              ),
              child: Column(
                children: [
                  // --- TIÊU ĐỀ APP BAR CỦA BOTTOM SHEET ---
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 12,
                      right: 12,
                      top: 16,
                      bottom: 10,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 28,
                          ),
                          onPressed: () =>
                              Navigator.of(bottomSheetContext).pop(),
                        ),
                        const Text(
                          'Thêm giao dịch',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),

                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        children: [
                          const SizedBox(height: 10),

                          // --- TỔ HỢP 2 NÚT TAB: CHI TIÊU & THU NHẬP ---
                          Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF161618),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Row(
                              children: [
                                // Nút Chi tiêu
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () =>
                                        setModalState(() => _isExpense = true),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _isExpense
                                            ? const Color(0xFFE54A44)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(25),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: const [
                                          Icon(
                                            Icons.north_east_rounded,
                                            color: Colors.white,
                                            size: 18,
                                          ),
                                          SizedBox(width: 6),
                                          Text(
                                            'Chi tiêu',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                // Nút Thu nhập
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () =>
                                        setModalState(() => _isExpense = false),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: !_isExpense
                                            ? const Color(0xFF2E7D32)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(25),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: const [
                                          Icon(
                                            Icons.south_west_rounded,
                                            color: Colors.white,
                                            size: 18,
                                          ),
                                          SizedBox(width: 6),
                                          Text(
                                            'Thu nhập',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 32),

                          // --- VÙNG NHẬP SỐ TIỀN (SỐ 0 ĐÃ LÀM MỜ) ---
                          Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 36,
                              horizontal: 16,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1C1C1E),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  IntrinsicWidth(
                                    child:
                                        ValueListenableBuilder<
                                          TextEditingValue
                                        >(
                                          valueListenable: _amountController,
                                          builder: (context, value, child) {
                                            final isZeroOrEmpty =
                                                value.text.isEmpty ||
                                                value.text == '0';
                                            return TextField(
                                              controller: _amountController,
                                              keyboardType:
                                                  TextInputType.number,
                                              inputFormatters: [
                                                FilteringTextInputFormatter
                                                    .digitsOnly,
                                                LengthLimitingTextInputFormatter(
                                                  12,
                                                ),
                                              ],
                                              showCursor: false,
                                              cursorColor: Colors.transparent,
                                              style: TextStyle(
                                                color: isZeroOrEmpty
                                                    ? Colors.white38
                                                    : Colors.white,
                                                fontSize: _amountFontSize(
                                                  value.text,
                                                ),
                                                fontWeight: FontWeight.w700,
                                              ),
                                              maxLines: 1,
                                              textAlignVertical:
                                                  TextAlignVertical.center,
                                              textAlign: TextAlign.center,
                                              decoration: const InputDecoration(
                                                hintText: '0',
                                                hintStyle: TextStyle(
                                                  color: Colors.white38,
                                                  fontSize: 42,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                                border: InputBorder.none,
                                                isDense: true,
                                                contentPadding: EdgeInsets.zero,
                                              ),
                                            );
                                          },
                                        ),
                                  ),
                                  ValueListenableBuilder<TextEditingValue>(
                                    valueListenable: _amountController,
                                    builder: (context, value, child) {
                                      final hasLetters = RegExp(
                                        r'[a-zA-Z]',
                                      ).hasMatch(value.text);
                                      if (hasLetters)
                                        return const SizedBox.shrink();
                                      return const Text(
                                        ' đ',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 34,
                                          fontWeight: FontWeight.w500,
                                          decoration: TextDecoration.underline,
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 12),
                                  GestureDetector(
                                    onTap: () => setModalState(
                                      () => _amountController.text = '',
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        color: Colors.white24,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 36),

                          // --- NÚT LƯU GIAO DỊCH ---
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFBC26F6),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                elevation: 0,
                              ),
                              onPressed: () {
                                // Nếu người dùng không nhập gì thì mặc định trả về '0'
                                final finalAmount =
                                    _amountController.text.isEmpty
                                    ? '0'
                                    : _amountController.text;
                                Navigator.of(bottomSheetContext).pop({
                                  'isExpense': _isExpense,
                                  'amount': finalAmount,
                                });
                              },
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'Lưu',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (!mounted || result == null) return;

    setState(() {
      _displayAmount = result['amount'] as String?;
      _displayIsExpense = result['isExpense'] == true;
    });

    _pendingAmount = _parseAmountFromString(result['amount'] as String? ?? '0');

    final typeText = result['isExpense'] ? 'Khoản chi tiêu' : 'Khoản thu nhập';
    final displayLabel = _formatCompactFromInt(_pendingAmount);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã lưu thành công: $typeText $displayLabel')),
    );
  }

  // HÀM 3: Mở menu tài chính (Ngân sách / Thống kê)
  Future<void> openFinanceMenu() async {
    final token = await _sessionService.getToken();

    List<Map<String, String>> existing = [];
    final localGroups = await _budgetStorageService.readBudgetGroups();
    if (token != null && token.trim().isNotEmpty) {
      final remote = await _financeApiService.getCategories(token: token);
      if (remote.success &&
          remote.data != null &&
          remote.data!['data'] is List) {
        // Build map from remote then overlay local groups (local wins)
        final remoteList = (remote.data!['data'] as List)
            .whereType<Map>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .where((item) => item['isGlobal'] != true) // ignore global defaults
            .map((item) {
              return {
                'key':
                    item['key']?.toString() ??
                    item['slug']?.toString() ??
                    item['id']?.toString() ??
                    '',
                'label':
                    item['label']?.toString() ?? item['name']?.toString() ?? '',
                'kind': item['kind']?.toString() ?? '',
              };
            })
            .toList();

        final mapByKey = <String, Map<String, String>>{};
        for (final r in remoteList) {
          final k = (r['key'] ?? '').toString().trim().toLowerCase();
          if (k.isEmpty) continue;
          mapByKey[k] = {
            'key': r['key'] ?? '',
            'label': r['label'] ?? '',
            'kind': r['kind'] ?? '',
          };
        }
        for (final lg in localGroups) {
          final lk = (lg['key'] ?? '').toString().trim().toLowerCase();
          if (lk.isEmpty) continue;
          // override or add
          mapByKey[lk] = {
            'key': lg['key'] ?? lg['label'] ?? '',
            'label': lg['label'] ?? '',
            'kind': lg['kind'] ?? '',
          };
        }
        existing = mapByKey.values.toList();
      } else {
        existing = localGroups;
      }
    } else {
      existing = localGroups;
    }

    final combined = _dedupeAndFilterGroups(existing);

    if (!mounted) return;

    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F0F0F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text(
                        'Huỷ',
                        style: TextStyle(color: Colors.white60),
                      ),
                    ),
                    const Text(
                      'Chọn hạng mục',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 60),
                  ],
                ),
                const SizedBox(height: 12),
                if (combined.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'chưa có hạng mục ngân sách nào hãy tạo mới',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          ...combined.map((g) {
                            final key = g['key'] ?? g['label'] ?? '';
                            final label = g['label'] ?? key;
                            final kind = g['kind'];
                            final selected = _selectedCategoryKey == key;
                            final borderColor = selected
                                ? Colors.white
                                : kind == 'income'
                                ? const Color(0xFF2ECC71).withValues(alpha: 0.9)
                                : const Color(
                                    0xFFFF4D4D,
                                  ).withValues(alpha: 0.9);
                            final fillColor = selected
                                ? Colors.white.withValues(alpha: 0.14)
                                : const Color(0xFF1A1A1C);

                            return InkWell(
                              onTap: () => Navigator.pop(ctx, key),
                              borderRadius: BorderRadius.circular(999),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: fillColor,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: borderColor,
                                    width: 1.1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.18,
                                      ),
                                      blurRadius: 10,
                                      offset: const Offset(0, 5),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 22,
                                      height: 22,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: kind == 'income'
                                            ? const Color(
                                                0xFF2ECC71,
                                              ).withValues(alpha: 0.16)
                                            : const Color(
                                                0xFFFF4D4D,
                                              ).withValues(alpha: 0.16),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(
                                        label.isNotEmpty ? label[0] : '?',
                                        style: TextStyle(
                                          color: selected
                                              ? Colors.white
                                              : Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      label,
                                      style: TextStyle(
                                        color: selected
                                            ? Colors.white
                                            : Colors.white70,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (selected) ...[
                                      const SizedBox(width: 8),
                                      const Icon(
                                        Icons.check_rounded,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );

    if (choice == null) return;

    final found = combined.firstWhere(
      (group) => group['key'] == choice,
      orElse: () => {},
    );
    if (found.isNotEmpty && mounted) {
      setState(() {
        _selectedCategoryKey = found['key'];
        _selectedCategoryLabel = found['label'];
      });
    }
  }

  @override
  void dispose() {
    _captionController.dispose();
    _amountController.dispose();
    try {
      calendarRefreshNotifier.removeListener(_handleCalendarRefresh);
    } catch (_) {}
    super.dispose();
  }

  String _formatWithDots(String digits) {
    final rev = digits.split('').reversed.toList();
    final parts = <String>[];
    for (var i = 0; i < rev.length; i += 3) {
      parts.add(rev.sublist(i, min(i + 3, rev.length)).reversed.join());
    }
    return parts.reversed.join('.');
  }

  String _buildSignedAmountLabel() {
    final amount = _displayAmount ?? '';
    final value = _parseAmountFromString(amount);
    final formattedAmount = _formatCompactFromInt(value);
    final sign = _displayIsExpense ? '-' : '+';
    return '$sign$formattedAmount';
  }

  Color _buildSignedAmountColor() {
    return _displayIsExpense
        ? const Color(0xFFE54A44)
        : const Color(0xFF2E7D32);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Gửi đến...',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(
              Icons.download_rounded,
              color: Colors.white,
              size: 28,
            ),
            onPressed: _isUploading ? null : uploadPost,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            /// ================= SQUARE PREVIEW AREA =================
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Center(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 30,
                          offset: const Offset(0, 20),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.file(
                              widget.imageFile,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                              errorBuilder: (context, error, stack) =>
                                  Container(color: Colors.black),
                            ),
                            Container(
                              color: Colors.black.withValues(alpha: 0.05),
                            ),
                            if (_displayAmount != null &&
                                _displayAmount!.isNotEmpty)
                              Positioned(
                                left: 6,
                                top: 10,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _buildSignedAmountColor().withValues(
                                      alpha: 0.18,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _buildSignedAmountColor()
                                          .withValues(alpha: 0.55),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Text(
                                    _buildSignedAmountLabel(),
                                    style: TextStyle(
                                      color: _buildSignedAmountColor(),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            if (_selectedCategoryLabel != null &&
                                _selectedCategoryLabel!.isNotEmpty)
                              Positioned(
                                left: 6,
                                top: 42,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white12,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.white10,
                                      width: 0.6,
                                    ),
                                  ),
                                  child: Text(
                                    _selectedCategoryLabel!,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            Positioned(
                              bottom: 24,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: IntrinsicWidth(
                                  child: Container(
                                    constraints: const BoxConstraints(
                                      minWidth: 180,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF6C4D3F,
                                      ).withValues(alpha: 0.9),
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                    child: TextField(
                                      controller: _captionController,
                                      textAlign: TextAlign.left,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w500,
                                        fontSize: 15,
                                      ),
                                      cursorColor: Colors.white,
                                      decoration: const InputDecoration(
                                        hintText: 'Thêm một tin nhắn',
                                        hintStyle: TextStyle(
                                          color: Color(0xFFEFEFEF),
                                          fontWeight: FontWeight.w500,
                                          fontSize: 15,
                                        ),
                                        border: InputBorder.none,
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(
                                          vertical: 8,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: IgnorePointer(
                                ignoring: true,
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(28),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.08,
                                      ),
                                      width: 1,
                                    ),
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

            /// ================= BOTTOM ACTION ROW =================
            Container(
              height: 135,
              width: double.infinity,
              color: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  /// 1. ICON VÍ
                  GestureDetector(
                    onTap: _isUploading ? null : openWallet,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: 60,
                      height: 60,
                      alignment: Alignment.center,
                      child: CustomPaint(
                        size: const Size(36, 28),
                        painter: CustomWalletPainter(),
                      ),
                    ),
                  ),

                  /// 2. NÚT ĐỊNH VỊ GIỮA
                  GestureDetector(
                    onTap: _isUploading ? null : uploadPost,
                    child: Container(
                      width: 82,
                      height: 82,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF404040),
                          width: 3.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Container(
                        width: 70,
                        height: 70,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                        child: Center(
                          child: _isUploading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.black,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.near_me_rounded,
                                  color: Colors.black,
                                  size: 34,
                                ),
                        ),
                      ),
                    ),
                  ),

                  /// 3. ICON CHỒNG SÁCH
                  GestureDetector(
                    onTap: _isUploading ? null : openFinanceMenu,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: 60,
                      height: 60,
                      alignment: Alignment.center,
                      child: CustomPaint(
                        size: const Size(36, 26),
                        painter: CustomBooksPainter(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ================= CUSTOM PAINTERS =================

class CustomWalletPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;

    final walletPath = Path()
      ..moveTo(w * 0.32, h * 0.05)
      ..lineTo(w * 0.85, h * 0.05)
      ..arcToPoint(Offset(w, h * 0.25), radius: const Radius.circular(6))
      ..lineTo(w, h * 0.75)
      ..arcToPoint(Offset(w * 0.85, h * 0.95), radius: const Radius.circular(6))
      ..lineTo(w * 0.32, h * 0.95)
      ..arcToPoint(Offset(w * 0.24, h * 0.85), radius: const Radius.circular(4))
      ..lineTo(w * 0.24, h * 0.75);
    canvas.drawPath(walletPath, paint);

    final leftTopCurve = Path()
      ..moveTo(w * 0.24, h * 0.25)
      ..lineTo(w * 0.24, h * 0.15)
      ..arcToPoint(
        Offset(w * 0.32, h * 0.05),
        radius: const Radius.circular(4),
      );
    canvas.drawPath(leftTopCurve, paint);

    final lockPath = Path()
      ..moveTo(w * 0.92, h * 0.4)
      ..lineTo(w * 0.82, h * 0.4)
      ..arcToPoint(Offset(w * 0.82, h * 0.6), radius: const Radius.circular(3))
      ..lineTo(w * 0.92, h * 0.6);
    canvas.drawPath(lockPath, paint);

    final coinPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;

    canvas.drawCircle(Offset(w * 0.14, h * 0.72), 5.5, coinPaint);
    canvas.drawCircle(Offset(w * 0.14, h * 0.53), 5.5, coinPaint);
    canvas.drawCircle(Offset(w * 0.14, h * 0.34), 5.5, coinPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class CustomBooksPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;

    // Quy định độ cao mỗi cuốn sách khoảng 20% chiều cao canvas
    // Cuốn sách 1 (Dưới cùng)
    final book1 = Path()
      ..moveTo(w * 0.1, h * 0.85)
      ..lineTo(w * 0.9, h * 0.85)
      ..lineTo(w * 0.9, h * 0.65)
      ..lineTo(w * 0.1, h * 0.65)
      ..close();
    canvas.drawPath(book1, paint);
    // Gáy sách/vạch phân tách nhỏ
    canvas.drawLine(
      Offset(w * 0.25, h * 0.65),
      Offset(w * 0.25, h * 0.85),
      paint,
    );

    // Cuốn sách 2 (Giữa, hơi lệch sang phải một chút tạo hiệu ứng xếp chồng)
    final book2 = Path()
      ..moveTo(w * 0.15, h * 0.55)
      ..lineTo(w * 0.85, h * 0.55)
      ..lineTo(w * 0.85, h * 0.35)
      ..lineTo(w * 0.15, h * 0.35)
      ..close();
    canvas.drawPath(book2, paint);
    canvas.drawLine(
      Offset(w * 0.3, h * 0.35),
      Offset(w * 0.3, h * 0.55),
      paint,
    );

    // Cuốn sách 3 (Trên cùng, hơi nghiêng nhẹ hoặc nằm cân bằng)
    final book3 = Path()
      ..moveTo(w * 0.2, h * 0.25)
      ..lineTo(w * 0.8, h * 0.25)
      ..lineTo(w * 0.8, h * 0.05)
      ..lineTo(w * 0.2, h * 0.05)
      ..close();
    canvas.drawPath(book3, paint);
    canvas.drawLine(
      Offset(w * 0.35, h * 0.05),
      Offset(w * 0.35, h * 0.25),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
