import 'dart:math';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/services/auth_session_service.dart';
import 'package:flutter_application_1/services/budget_storage_service.dart';
import 'package:flutter_application_1/services/calendar_storage_service.dart';
import 'package:flutter_application_1/services/calendar_refresh_notifier.dart';
import 'package:flutter_application_1/services/finance_api_service.dart';

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetPeriodChoice {
  const _BudgetPeriodChoice({
    required this.key,
    required this.label,
    required this.rangeText,
    required this.monthKey,
  });

  final String key;
  final String label;
  final String rangeText;
  final String monthKey;
}

class _BudgetScreenState extends State<BudgetScreen> {
  final AuthSessionService _sessionService = AuthSessionService();
  final FinanceApiService _financeApiService = FinanceApiService();
  final BudgetStorageService _storageService = BudgetStorageService();
  final CalendarStorageService _calendarStorageService =
      CalendarStorageService();
  final Set<String> _notifiedOverBudgetKeys = <String>{};

  bool _isLoading = true;
  int _monthlyBudget = 0;
  List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];

  String _currentMonthKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
  }

  DateTime _startOfWeek(DateTime date) {
    return DateTime(
      date.year,
      date.month,
      date.day - (date.weekday - DateTime.monday),
    );
  }

  DateTime _endOfWeek(DateTime date) {
    return _startOfWeek(date).add(const Duration(days: 6));
  }

  DateTime _startOfQuarter(DateTime date) {
    final quarterStartMonth = (((date.month - 1) ~/ 3) * 3) + 1;
    return DateTime(date.year, quarterStartMonth, 1);
  }

  DateTime _endOfQuarter(DateTime date) {
    final start = _startOfQuarter(date);
    return DateTime(start.year, start.month + 3, 0);
  }

  String _formatDayMonth(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
  }

  String _formatRange(DateTime start, DateTime end) {
    return '${_formatDayMonth(start)} - ${_formatDayMonth(end)}';
  }

  String _monthRangeFromKey(String monthKey) {
    final parts = monthKey.split('-');
    if (parts.length != 2) return monthKey;
    final year = int.tryParse(parts[0]) ?? DateTime.now().year;
    final month = int.tryParse(parts[1]) ?? DateTime.now().month;
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 0);
    return _formatRange(start, end);
  }

  List<_BudgetPeriodChoice> _buildBudgetPeriodChoices(DateTime now) {
    final monthKey =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
    final weekStart = _startOfWeek(now);
    final weekEnd = _endOfWeek(now);
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 0);
    final quarterStart = _startOfQuarter(now);
    final quarterEnd = _endOfQuarter(now);
    final yearStart = DateTime(now.year, 1, 1);
    final yearEnd = DateTime(now.year, 12, 31);

    return [
      _BudgetPeriodChoice(
        key: 'week',
        label: 'Tuần này',
        rangeText: _formatRange(weekStart, weekEnd),
        monthKey: monthKey,
      ),
      _BudgetPeriodChoice(
        key: 'month',
        label: 'Tháng này',
        rangeText: _formatRange(monthStart, monthEnd),
        monthKey: monthKey,
      ),
      _BudgetPeriodChoice(
        key: 'quarter',
        label: 'Quý này',
        rangeText: _formatRange(quarterStart, quarterEnd),
        monthKey: monthKey,
      ),
      _BudgetPeriodChoice(
        key: 'year',
        label: 'Năm nay',
        rangeText: _formatRange(yearStart, yearEnd),
        monthKey: monthKey,
      ),
      _BudgetPeriodChoice(
        key: 'custom',
        label: 'Tùy chỉnh',
        rangeText: _formatRange(now, now),
        monthKey: monthKey,
      ),
    ];
  }

  int _parseAmount(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '0') ?? 0;
  }

  String _formatVnd(int value) {
    final negative = value < 0;
    final formatted = NumberFormat.decimalPattern('vi_VN').format(value.abs());
    return '${negative ? '-' : ''}$formattedđ';
  }

  String _formatCompact(int value) {
    final negative = value < 0;
    final absValue = value.abs();
    if (absValue >= 1000000000) {
      final result = absValue / 1000000000;
      final formatted = absValue % 1000000000 == 0
          ? result.toStringAsFixed(0)
          : result.toStringAsFixed(1);
      return '${negative ? '-' : ''}${formatted}T';
    }
    if (absValue >= 1000000) {
      final result = absValue / 1000000;
      final formatted = absValue % 1000000 == 0
          ? result.toStringAsFixed(0)
          : result.toStringAsFixed(1);
      return '${negative ? '-' : ''}${formatted}tr';
    }
    return _formatVnd(value);
  }

  Map<String, dynamic> _normalizeBudgetResponse(Map<String, dynamic> item) {
    final category = item['category'] is Map
        ? Map<String, dynamic>.from(item['category'] as Map)
        : <String, dynamic>{};

    return <String, dynamic>{
      'id':
          item['id']?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      'categoryId': item['categoryId'] ?? item['category_id'] ?? category['id'],
      'categoryKey':
          item['categoryKey'] ??
          item['category_key'] ??
          category['key'] ??
          category['slug'] ??
          item['slug'] ??
          item['key'],
      'name':
          item['name'] ?? category['label'] ?? category['name'] ?? 'Hạng mục',
      'limit':
          item['limitAmount'] ?? item['limit_amount'] ?? item['limit'] ?? 0,
      'spent':
          item['spentAmount'] ?? item['spent_amount'] ?? item['spent'] ?? 0,
      'iconKey':
          item['iconKey'] ??
          item['icon_key'] ??
          category['iconKey'] ??
          category['icon_key'] ??
          'other',
      'kind':
          item['kind'] ?? item['categoryKind'] ?? category['kind'] ?? 'expense',
      'color':
          item['color'] ??
          item['categoryColor'] ??
          category['color'] ??
          '#8E8E93',
      'createdAt': item['createdAt'] ?? item['created_at'],
      'updatedAt': item['updatedAt'] ?? item['updated_at'],
    };
  }

  String _groupLabelForKey(String key) {
    switch (key) {
      case 'home':
        return 'Nhà ở';
      case 'food':
        return 'Ăn uống';
      case 'car':
        return 'Di chuyển';
      case 'shop':
        return 'Mua sắm';
      case 'health':
        return 'Sức khoẻ';
      case 'salary':
        return 'Lương';
      default:
        return key;
    }
  }

  String _groupKindLabel(String? kind) {
    switch (kind) {
      case 'income':
        return 'Khoản thu';
      case 'expense':
        return 'Khoản chi';
      default:
        return 'Chưa chọn';
    }
  }

  Color _groupKindColor(String? kind) {
    switch (kind) {
      case 'income':
        return const Color(0xFF2ECC71);
      case 'expense':
        return const Color(0xFFFF4D4D);
      default:
        return const Color(0xFF8E8E93);
    }
  }

  IconData _iconForKey(String? key) {
    switch (key) {
      case 'home':
        return Icons.home_outlined;
      case 'food':
        return Icons.restaurant_outlined;
      case 'car':
        return Icons.directions_car_outlined;
      case 'shop':
        return Icons.shopping_bag_outlined;
      case 'health':
        return Icons.medical_services_outlined;
      default:
        return Icons.category_outlined;
    }
  }

  Color _iconColorForKey(String? key) {
    switch (key) {
      case 'home':
        return const Color(0xFF4E8DFF);
      case 'food':
        return const Color(0xFFFFC04D);
      case 'car':
        return const Color(0xFF5DD6FF);
      case 'shop':
        return const Color(0xFFBF5AF2);
      case 'health':
        return const Color(0xFFFF5C8A);
      default:
        return const Color(0xFF8E8E93);
    }
  }

  int get _totalSpent =>
      _items.fold<int>(0, (sum, item) => sum + _parseAmount(item['spent']));
  int get _remaining => _monthlyBudget - _totalSpent;
  int get _daysLeft {
    final now = DateTime.now();
    final lastDay = DateTime(now.year, now.month + 1, 0);
    return max(0, lastDay.day - now.day);
  }

  double get _progress =>
      _monthlyBudget <= 0 ? 0 : (_totalSpent / _monthlyBudget).clamp(0.0, 1.0);

  void _notifyOverBudgetItems(List<Map<String, dynamic>> items) {
    if (!mounted) return;
    for (final item in items) {
      final limit = _parseAmount(item['limit']);
      final spent = _parseAmount(item['spent']);
      if (limit <= 0 || spent < limit) continue;
      final key =
          item['id']?.toString() ??
          item['categoryId']?.toString() ??
          item['name']?.toString() ??
          '';
      if (key.isEmpty || _notifiedOverBudgetKeys.contains(key)) continue;
      _notifiedOverBudgetKeys.add(key);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bạn đã chi tiêu quá ngân sách mà bạn đặt ra'),
        ),
      );
      break;
    }
  }

  String _monthKeyFromRawDate(Map<String, dynamic> post) {
    final fromDateKey = post['dateKey']?.toString().trim();
    if (fromDateKey != null &&
        RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(fromDateKey)) {
      return fromDateKey.substring(0, 7);
    }

    final rawDate =
        post['date']?.toString().trim() ??
        post['entryTs']?.toString().trim() ??
        '';
    final parsed = DateTime.tryParse(rawDate);
    if (parsed == null) return _currentMonthKey();
    final local = parsed.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}';
  }

  bool _postIsExpense(Map<String, dynamic> post) {
    final value = post['isExpense'] ?? post['is_expense'];
    if (value is bool) return value;
    final normalized = value?.toString().trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') return true;
    if (normalized == 'false' || normalized == '0') return false;
    return true;
  }

  Future<Map<String, int>> _readLocalSpentByCategory(String monthKey) async {
    final prefs = await SharedPreferences.getInstance();
    final storageKey = await _calendarStorageService.currentCalendarKey();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return <String, int>{};

    final totals = <String, int>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return totals;

      for (final entry in decoded) {
        if (entry is! Map) continue;
        final post = Map<String, dynamic>.from(entry);
        if (_monthKeyFromRawDate(post) != monthKey) continue;

        final categoryKey =
            (post['categoryKey'] ?? post['category_key'] ?? post['categoryId'])
                ?.toString()
                .trim();
        if (categoryKey == null || categoryKey.isEmpty) continue;

        final amount = _parseAmount(post['amount']);
        if (amount <= 0) continue;

        final signedAmount = _postIsExpense(post) ? amount : amount;
        totals.update(
          categoryKey,
          (current) => current + signedAmount,
          ifAbsent: () => signedAmount,
        );
      }
    } catch (_) {
      return <String, int>{};
    }
    return totals;
  }

  List<Map<String, dynamic>> _mergeLocalSpentFallback(
    List<Map<String, dynamic>> items,
    Map<String, int> localSpentByCategory,
  ) {
    if (items.isEmpty || localSpentByCategory.isEmpty) return items;

    return items.map((item) {
      final itemKey =
          (item['categoryKey'] ??
                  item['category_key'] ??
                  item['iconKey'] ??
                  item['key'])
              ?.toString()
              .trim();
      if (itemKey == null || itemKey.isEmpty) return item;

      final localSpent = localSpentByCategory[itemKey] ?? 0;
      if (localSpent <= 0) return item;

      final remoteSpent = _parseAmount(item['spent']);
      if (localSpent <= remoteSpent) return item;

      final next = Map<String, dynamic>.from(item);
      next['spent'] = localSpent;
      return next;
    }).toList();
  }

  Future<void> _loadData() async {
    int monthlyBudget = await _storageService.readMonthlyBudget();
    List<Map<String, dynamic>> items = await _storageService.readBudgetItems();
    final monthKey = _currentMonthKey();

    final token = await _sessionService.getToken();
    if (token != null && token.isNotEmpty) {
      final remote = await _financeApiService.getBudgetDashboard(
        token: token,
        monthKey: monthKey,
      );
      if (remote.success && remote.data != null) {
        final data = remote.data!;
        monthlyBudget = _parseAmount(
          data['monthlyBudget'] ?? data['monthly_budget'] ?? monthlyBudget,
        );
        final rawItems = data['items'];
        if (rawItems is List) {
          items = rawItems
              .whereType<Map>()
              .map(
                (entry) =>
                    _normalizeBudgetResponse(Map<String, dynamic>.from(entry)),
              )
              .toList();

          // Keep local cache aligned with the latest server-calculated spent
          // amounts so budget cards remain consistent when app is reopened.
          // If we have local group labels (user-edited names), prefer them
          try {
            final localGroups = await _storageService.readBudgetGroups();
            final localMap = <String, String>{};
            for (final g in localGroups) {
              final k = (g['key'] ?? '').toString().trim().toLowerCase();
              final l = (g['label'] ?? '').toString();
              if (k.isNotEmpty && l.isNotEmpty) localMap[k] = l;
            }
            items = items.map((it) {
              final ik =
                  (it['iconKey'] ?? it['categoryKey'] ?? it['key'])
                      ?.toString() ??
                  '';
              final k = ik.trim().toLowerCase();
              if (k.isNotEmpty && localMap.containsKey(k)) {
                final next = Map<String, dynamic>.from(it);
                next['name'] = localMap[k];
                return next;
              }
              return it;
            }).toList();
          } catch (_) {}

          await _storageService.saveMonthlyBudget(monthlyBudget);
          await _storageService.saveBudgetItems(items);
        }
      }
    }

    final localSpentByCategory = await _readLocalSpentByCategory(monthKey);
    items = _mergeLocalSpentFallback(items, localSpentByCategory);

    if (!mounted) return;
    setState(() {
      _monthlyBudget = monthlyBudget;
      _items = items;
      _isLoading = false;
    });
    _notifyOverBudgetItems(items);
  }

  Future<List<Map<String, String>>> _loadSelectableGroups() async {
    final token = await _sessionService.getToken();
    List<Map<String, String>> existing;

    if (token != null && token.isNotEmpty) {
      final remote = await _financeApiService.getCategories(token: token);
      if (remote.success &&
          remote.data != null &&
          remote.data!['data'] is List) {
        existing = (remote.data!['data'] as List)
            .whereType<Map>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .where(
              (item) => item['isGlobal'] != true,
            ) // only user-created categories
            .map((item) {
              return <String, String>{
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
            .where(
              (entry) => entry['key']!.isNotEmpty && entry['label']!.isNotEmpty,
            )
            .toList();
      } else {
        existing = await _storageService.readBudgetGroups();
      }
    } else {
      existing = await _storageService.readBudgetGroups();
    }

    return existing;
  }

  Future<bool> _deleteSelectableGroup(Map<String, String> group) async {
    final key = (group['key'] ?? '').trim();
    if (key.isEmpty) return false;

    final label = (group['label'] ?? '').trim();
    final token = await _sessionService.getToken();
    final remoteCategoryId = await _resolveRemoteCategoryId(key, label);

    if (token != null &&
        token.isNotEmpty &&
        remoteCategoryId != null &&
        remoteCategoryId > 0) {
      final remoteResult = await _financeApiService.deleteCategory(
        token: token,
        categoryId: remoteCategoryId,
      );
      if (!remoteResult.success && remoteResult.statusCode != 404) {
        return false;
      }
    }

    final groups = await _storageService.readBudgetGroups();
    final normalizedKey = key.toLowerCase();
    final nextGroups = groups
        .where(
          (entry) => (entry['key'] ?? '').trim().toLowerCase() != normalizedKey,
        )
        .toList();
    await _storageService.saveBudgetGroups(nextGroups);

    try {
      calendarRefreshNotifier.value++;
    } catch (_) {}

    return true;
  }

  Future<int?> _resolveRemoteCategoryId(String key, String label) async {
    final token = await _sessionService.getToken();
    if (token == null || token.isEmpty) return null;

    final remote = await _financeApiService.getCategories(token: token);
    if (!remote.success || remote.data == null || remote.data!['data'] is! List)
      return null;

    for (final entry in remote.data!['data'] as List) {
      if (entry is! Map) continue;
      final item = Map<String, dynamic>.from(entry);
      final itemId = item['id']?.toString() ?? '';
      final itemKey = item['key']?.toString() ?? item['slug']?.toString() ?? '';
      final itemLabel =
          item['label']?.toString() ?? item['name']?.toString() ?? '';
      if (itemId == key || itemKey == key || itemLabel == label) {
        return int.tryParse(itemId);
      }
    }

    return null;
  }

  String _slugifyGroupName(String value) {
    final normalized = value.trim().toLowerCase();
    final buffer = StringBuffer();
    var lastWasDash = false;

    for (final codeUnit in normalized.codeUnits) {
      final char = String.fromCharCode(codeUnit);
      final isLetterOrDigit = RegExp(r'[a-z0-9]').hasMatch(char);
      if (isLetterOrDigit) {
        buffer.write(char);
        lastWasDash = false;
        continue;
      }
      if (!lastWasDash) {
        buffer.write('-');
        lastWasDash = true;
      }
    }

    final result = buffer.toString().replaceAll(RegExp(r'^-+|-+$'), '');
    return result.isEmpty ? 'nhom-moi' : result;
  }

  Future<Map<String, String>?> _showCreateGroupDialog() async {
    final nameController = TextEditingController();
    var selectedKind = 'expense';

    try {
      return await showDialog<Map<String, String>>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) {
          void closeDialog([Map<String, String>? result]) {
            FocusManager.instance.primaryFocus?.unfocus();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!dialogContext.mounted) return;
              Navigator.of(dialogContext).pop(result);
            });
          }

          return AlertDialog(
            backgroundColor: const Color(0xFF141414),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: Text(
              'Thêm hạng mục mới',
              style: GoogleFonts.manrope(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            content: StatefulBuilder(
              builder: (context, setDialogState) {
                return SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: nameController,
                        style: GoogleFonts.manrope(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Nhập tên nhóm',
                          hintStyle: GoogleFonts.manrope(
                            color: Colors.white.withValues(alpha: 0.35),
                          ),
                          filled: true,
                          fillColor: const Color(0xFF1C1C1E),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Chọn loại',
                        style: GoogleFonts.manrope(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _KindChoiceButton(
                              label: 'Khoản chi',
                              selected: selectedKind == 'expense',
                              color: const Color(0xFFFF4D4D),
                              onTap: () => setDialogState(
                                () => selectedKind = 'expense',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _KindChoiceButton(
                              label: 'Khoản thu',
                              selected: selectedKind == 'income',
                              color: const Color(0xFF2ECC71),
                              onTap: () =>
                                  setDialogState(() => selectedKind = 'income'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
            actions: [
              TextButton(
                onPressed: () => closeDialog(),
                child: const Text('Huỷ'),
              ),
              FilledButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  if (name.isEmpty) return;
                  final key = _slugifyGroupName(name);
                  closeDialog(<String, String>{
                    'key': key,
                    'label': name,
                    'kind': selectedKind,
                  });
                },
                child: const Text('Lưu'),
              ),
            ],
          );
        },
      );
    } finally {
      nameController.dispose();
    }
  }

  Future<void> _saveNewBudgetGroup({
    required String key,
    required String label,
    required String kind,
  }) async {
    final token = await _sessionService.getToken();
    if (token != null && token.isNotEmpty) {
      await _financeApiService.upsertCategory(
        token: token,
        name: label,
        kind: kind,
        iconKey: key,
      );
    }

    final groups = await _storageService.readBudgetGroups();
    final nextGroups = <Map<String, String>>[
      ...groups.where(
        (group) =>
            (group['key'] ?? '').trim().toLowerCase() !=
            key.trim().toLowerCase(),
      ),
      {'key': key, 'label': label, 'kind': kind},
    ];
    await _storageService.saveBudgetGroups(nextGroups);
    // Notify listeners so other screens (Budget list, Home) refresh
    try {
      calendarRefreshNotifier.value++;
    } catch (_) {}
  }

  Future<void> _saveBudgetItemFromModal({
    required int limitAmount,
    required String groupKey,
    required String monthKey,
    required bool isRepeat,
  }) async {
    final groups = await _loadSelectableGroups();
    final group = groups.firstWhere(
      (item) => item['key'] == groupKey,
      orElse: () => <String, String>{},
    );

    final label = group['label']?.toString() ?? _groupLabelForKey(groupKey);
    final kind = group['kind']?.toString() ?? 'expense';
    final remoteCategoryId = await _resolveRemoteCategoryId(groupKey, label);

    final token = await _sessionService.getToken();
    if (token != null && token.isNotEmpty) {
      final remoteResult = await _financeApiService.upsertBudget(
        token: token,
        name: label,
        limitAmount: limitAmount,
        monthKey: monthKey,
        categoryId: remoteCategoryId,
        slug: groupKey,
        kind: kind,
        iconKey: groupKey,
        isRepeat: isRepeat,
      );
      if (remoteResult.success) {
        await _loadData();
        return;
      }
    }

    final items = [..._items];
    final now = DateTime.now().millisecondsSinceEpoch.toString();
    items.add(<String, dynamic>{
      'id': now,
      'name': label,
      'limit': limitAmount,
      'spent': 0,
      'iconKey': groupKey,
      'monthKey': monthKey,
      'isRepeat': isRepeat,
      'createdAt': now,
      'updatedAt': now,
    });
    await _storageService.saveBudgetItems(items);
    await _loadData();
  }

  Future<String?> _showGroupPicker() async {
    final groups = await _loadSelectableGroups();
    if (!mounted) return null;

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F0F0F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final visibleGroups = List<Map<String, String>>.from(groups);

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
                          onPressed: () => Navigator.pop(sheetContext),
                          child: const Text(
                            'Huỷ',
                            style: TextStyle(color: Colors.white60),
                          ),
                        ),
                        const Text(
                          'Hạng mục đề xuất',
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
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          children: visibleGroups.map((group) {
                            final key = group['key'] ?? '';
                            final label = group['label'] ?? key;
                            final kind = group['kind'];
                            return ListTile(
                              onTap: () => Navigator.pop(sheetContext, key),
                              leading: CircleAvatar(
                                backgroundColor: Colors.white10,
                                child: Text(label.isNotEmpty ? label[0] : '?'),
                              ),
                              title: Text(
                                label,
                                style: GoogleFonts.manrope(color: Colors.white),
                              ),
                              subtitle: kind == null || kind.isEmpty
                                  ? null
                                  : Text(
                                      _groupKindLabel(kind),
                                      style: TextStyle(
                                        color: _groupKindColor(kind),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                              trailing: IconButton(
                                tooltip: 'Xóa hạng mục',
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Color(0xFFFF4D4D),
                                ),
                                onPressed: () async {
                                  final ok = await showDialog<bool>(
                                    context: sheetContext,
                                    builder: (dialogContext) => AlertDialog(
                                      title: const Text('Xác nhận'),
                                      content: const Text(
                                        'Bạn có muốn xóa hạng mục đề xuất này không?',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.of(
                                            dialogContext,
                                          ).pop(false),
                                          child: const Text('Không'),
                                        ),
                                        FilledButton(
                                          onPressed: () => Navigator.of(
                                            dialogContext,
                                          ).pop(true),
                                          child: const Text('Xóa'),
                                        ),
                                      ],
                                    ),
                                  );

                                  if (ok != true) return;

                                  final deleted = await _deleteSelectableGroup(
                                    group,
                                  );
                                  if (!sheetContext.mounted) return;

                                  if (!deleted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Không thể xóa hạng mục này',
                                        ),
                                      ),
                                    );
                                    return;
                                  }

                                  setSheetState(() {
                                    groups.removeWhere(
                                      (item) =>
                                          (item['key'] ?? '')
                                              .trim()
                                              .toLowerCase() ==
                                          key.trim().toLowerCase(),
                                    );
                                  });

                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Đã xóa hạng mục'),
                                    ),
                                  );
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () =>
                          Navigator.pop(sheetContext, '__create_new__'),
                      icon: const Icon(Icons.add_rounded, color: Colors.white),
                      label: Text(
                        'Thêm hạng mục mới',
                        style: GoogleFonts.manrope(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.16),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<String?> _showGroupPickerWithCreate() async {
    final selected = await _showGroupPicker();
    if (selected == '__create_new__') {
      final created = await _showCreateGroupDialog();
      if (created == null) return null;
      await _saveNewBudgetGroup(
        key: created['key'] ?? '',
        label: created['label'] ?? '',
        kind: created['kind'] ?? 'expense',
      );
      return created['key'];
    }
    return selected;
  }

  Future<_BudgetPeriodChoice?> _showBudgetPeriodPicker({
    required _BudgetPeriodChoice currentSelection,
  }) async {
    final now = DateTime.now();
    final choices = _buildBudgetPeriodChoices(now);

    return showModalBottomSheet<_BudgetPeriodChoice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Khoảng thời gian',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.manrope(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 18),
                ...choices.map((choice) {
                  final isSelected =
                      choice.key == currentSelection.key &&
                      choice.monthKey == currentSelection.monthKey;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(28),
                      onTap: () async {
                        if (choice.key == 'custom') {
                          final navigator = Navigator.of(sheetContext);
                          final pickedRange = await showDateRangePicker(
                            context: sheetContext,
                            firstDate: DateTime(now.year - 3, 1, 1),
                            lastDate: DateTime(now.year + 3, 12, 31),
                            initialDateRange: DateTimeRange(
                              start: now,
                              end: now,
                            ),
                            helpText: 'Chọn khoảng thời gian',
                            saveText: 'Chọn',
                            cancelText: 'Huỷ',
                          );
                          if (pickedRange == null) return;
                          if (!navigator.mounted) return;
                          navigator.pop(
                            _BudgetPeriodChoice(
                              key: 'custom',
                              label: 'Tùy chỉnh',
                              rangeText: _formatRange(
                                pickedRange.start,
                                pickedRange.end,
                              ),
                              monthKey:
                                  '${pickedRange.start.year.toString().padLeft(4, '0')}-${pickedRange.start.month.toString().padLeft(2, '0')}',
                            ),
                          );
                          return;
                        }

                        Navigator.of(sheetContext).pop(choice);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF4A403A)
                              : const Color(0xFF2A2A2E),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: isSelected
                                ? Colors.white.withValues(alpha: 0.20)
                                : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              choice.label,
                              style: GoogleFonts.manrope(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              choice.rangeText,
                              style: GoogleFonts.manrope(
                                color: Colors.white.withValues(alpha: 0.90),
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                TextButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  child: Text(
                    'Huỷ',
                    style: GoogleFonts.manrope(
                      color: Colors.white70,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showBudgetFormDialog({
    required String title,
    required String buttonLabel,
    String? initialGroupKey,
    String? initialMonthKey,
    int? initialAmount,
    bool initialRepeat = false,
    _BudgetPeriodChoice? initialPeriod,
  }) async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return _BudgetFormSheet(
          title: title,
          buttonLabel: buttonLabel,
          initialGroupKey: initialGroupKey,
          initialMonthKey: initialMonthKey,
          initialAmount: initialAmount,
          initialRepeat: initialRepeat,
          initialPeriod: initialPeriod,
          loadGroups: _loadSelectableGroups,
          pickGroup: _showGroupPickerWithCreate,
          pickPeriod: (currentSelection) =>
              _showBudgetPeriodPicker(currentSelection: currentSelection),
        );
      },
    );

    if (picked == null) return;
    final amount = _parseAmount(picked['amount']);
    final groupKey = picked['groupKey']?.toString() ?? 'food';
    final monthKey = picked['monthKey']?.toString() ?? _currentMonthKey();
    final isRepeat = picked['isRepeat'] == true;

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    await _saveBudgetItemFromModal(
      groupKey: groupKey,
      limitAmount: amount,
      monthKey: monthKey,
      isRepeat: isRepeat,
    );
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(content: Text('$buttonLabel thành công')));
  }

  // NOTE: `_showItemDialog` has been removed from the UI. The function kept
  // here previously allowed creating budget items from the UI; that flow is
  // intentionally disabled. If you want to remove this code entirely, we can
  // delete this function in a follow-up change.

  @override
  void initState() {
    super.initState();
    calendarRefreshNotifier.addListener(_handleCalendarRefresh);
    _loadData();
  }

  @override
  void dispose() {
    calendarRefreshNotifier.removeListener(_handleCalendarRefresh);
    super.dispose();
  }

  void _handleCalendarRefresh() {
    if (!mounted) return;
    _loadData();
  }

  Future<void> _showBudgetDialog() async {
    final initialPeriod = _BudgetPeriodChoice(
      key: 'month',
      label: 'Tháng này',
      rangeText: _monthRangeFromKey(_currentMonthKey()),
      monthKey: _currentMonthKey(),
    );

    await _showBudgetFormDialog(
      title: _monthlyBudget > 0 ? 'Cập nhật ngân sách' : 'Thêm ngân sách',
      buttonLabel: _monthlyBudget > 0 ? 'Cập nhật' : 'Lưu',
      initialGroupKey: null,
      initialMonthKey: _currentMonthKey(),
      initialAmount: null,
      initialRepeat: false,
      initialPeriod: initialPeriod,
    );
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _remaining;
    final gaugeColor = remaining >= 0
        ? const Color(0xFF37C95B)
        : const Color(0xFFFF4D4D);

    return Scaffold(
      backgroundColor: const Color(0xFF080808),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Ngân sách chi tiêu',
          style: GoogleFonts.manrope(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Tháng này',
                      style: GoogleFonts.manrope(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      height: 3,
                      width: 92,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.all(Radius.circular(999)),
                      ),
                    ),
                    const SizedBox(height: 34),
                    Container(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                      decoration: BoxDecoration(
                        color: const Color(0xFF181818),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            height: 240,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Positioned(
                                  top: 0,
                                  left: 0,
                                  right: 0,
                                  child: SizedBox(
                                    height: 170,
                                    child: CustomPaint(
                                      painter: _HalfArcPainter(
                                        progress: _progress,
                                        color: gaugeColor,
                                        backgroundColor: const Color(
                                          0xFF9B9B9B,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(height: 28),
                                    Text(
                                      'Số tiền bạn có thể chi',
                                      style: GoogleFonts.manrope(
                                        color: Colors.white.withValues(
                                          alpha: 0.55,
                                        ),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      _formatCompact(remaining),
                                      style: GoogleFonts.manrope(
                                        color: gaugeColor,
                                        fontSize: 34,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                                Positioned(
                                  bottom: 8,
                                  left: 0,
                                  right: 0,
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: _MiniMetric(
                                          value: _formatCompact(_monthlyBudget),
                                          label: 'Tổng ngân sách',
                                        ),
                                      ),
                                      Container(
                                        width: 1,
                                        height: 34,
                                        color: Colors.white.withValues(
                                          alpha: 0.15,
                                        ),
                                      ),
                                      Expanded(
                                        child: _MiniMetric(
                                          value: _formatCompact(_totalSpent),
                                          label: 'Tổng đã chi',
                                        ),
                                      ),
                                      Container(
                                        width: 1,
                                        height: 34,
                                        color: Colors.white.withValues(
                                          alpha: 0.15,
                                        ),
                                      ),
                                      Expanded(
                                        child: _MiniMetric(
                                          value: '$_daysLeft ngày',
                                          label: 'Đến cuối tháng',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _showBudgetDialog,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2DBC4D),
                                minimumSize: const Size.fromHeight(48),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                              child: Text(
                                _monthlyBudget > 0
                                    ? 'Cập nhật Ngân sách'
                                    : 'Tạo Ngân sách',
                                style: GoogleFonts.manrope(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Hạng mục ngân sách',
                          style: GoogleFonts.manrope(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (_items.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: const Color(0xFF131313),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Chưa có hạng mục nào',
                              style: GoogleFonts.manrope(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Hãy tạo ngân sách tổng trước, sau đó thêm từng hạng mục như thuê nhà, ăn uống, đi lại...',
                              style: GoogleFonts.manrope(
                                color: Colors.white.withValues(alpha: 0.45),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ..._items.map((item) {
                        final limit = _parseAmount(item['limit']);
                        final spent = _parseAmount(item['spent']);
                        final remainingItem = limit - spent;
                        final ratio = limit <= 0 ? 0.0 : spent / limit;
                        final progress = ratio.clamp(0.0, 1.0);
                        final percentLabel = limit <= 0
                            ? '0%'
                            : '${(ratio * 100).round()}%';
                        final isOverBudget = limit > 0 && spent >= limit;
                        final iconKey = item['iconKey']?.toString();
                        final iconColor = _iconColorForKey(iconKey);

                        final categoryKey =
                            (item['iconKey'] ??
                                    item['categoryKey'] ??
                                    item['key'])
                                ?.toString() ??
                            '';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(24),
                            onTap: () async {
                              final result = await Navigator.of(context)
                                  .push<bool>(
                                    MaterialPageRoute(
                                      builder: (_) => BudgetDetailScreen(
                                        categoryKey: categoryKey,
                                      ),
                                    ),
                                  );
                              if (result == true) {
                                // if changed in detail screen, reload list
                                await _loadData();
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: const Color(0xFF131313),
                                borderRadius: BorderRadius.circular(24),
                                border: isOverBudget
                                    ? Border.all(
                                        color: const Color(0xFFFF4D4D),
                                        width: 1.2,
                                      )
                                    : null,
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: iconColor.withValues(
                                            alpha: 0.18,
                                          ),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          _iconForKey(iconKey),
                                          color: iconColor,
                                          size: 22,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Text(
                                          item['name']?.toString() ??
                                              'Hạng mục',
                                          style: GoogleFonts.manrope(
                                            color: Colors.white,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            _formatCompact(limit),
                                            style: GoogleFonts.manrope(
                                              color: Colors.white,
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            isOverBudget
                                                ? 'Vượt ${_formatCompact(spent - limit)}'
                                                : 'Còn lại ${_formatCompact(remainingItem)}',
                                            style: GoogleFonts.manrope(
                                              color: isOverBudget
                                                  ? const Color(0xFFFF6B6B)
                                                  : Colors.white.withValues(
                                                      alpha: 0.55,
                                                    ),
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(999),
                                    child: LinearProgressIndicator(
                                      minHeight: 10,
                                      value: progress,
                                      backgroundColor: const Color(0xFF2B2B2E),
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        isOverBudget
                                            ? const Color(0xFFFF4D4D)
                                            : iconColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Text(
                                        'Đã chi ${_formatCompact(spent)} / ${_formatCompact(limit)}',
                                        style: GoogleFonts.manrope(
                                          color: Colors.white.withValues(
                                            alpha: 0.45,
                                          ),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        percentLabel,
                                        style: GoogleFonts.manrope(
                                          color: isOverBudget
                                              ? const Color(0xFFFF6B6B)
                                              : Colors.white.withValues(
                                                  alpha: 0.45,
                                                ),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
    );
  }
}

class _BudgetFormSheet extends StatefulWidget {
  const _BudgetFormSheet({
    required this.title,
    required this.buttonLabel,
    required this.loadGroups,
    required this.pickGroup,
    required this.pickPeriod,
    this.initialGroupKey,
    this.initialMonthKey,
    this.initialAmount,
    this.initialRepeat = false,
    this.initialPeriod,
  });

  final String title;
  final String buttonLabel;
  final Future<List<Map<String, String>>> Function() loadGroups;
  final Future<String?> Function() pickGroup;
  final Future<_BudgetPeriodChoice?> Function(
    _BudgetPeriodChoice currentSelection,
  )
  pickPeriod;
  final String? initialGroupKey;
  final String? initialMonthKey;
  final int? initialAmount;
  final bool initialRepeat;
  final _BudgetPeriodChoice? initialPeriod;

  @override
  State<_BudgetFormSheet> createState() => _BudgetFormSheetState();
}

class _BudgetFormSheetState extends State<_BudgetFormSheet> {
  late final TextEditingController _amountController;
  List<Map<String, String>> _groups = <Map<String, String>>[];
  String _selectedGroupKey = '';
  bool _groupTouched = false;
  bool _isFormattingAmount = false;
  _BudgetPeriodChoice? _selectedPeriod;
  bool _isRepeat = false;
  bool _isLoading = true;

  IconData _iconDataForKey(String? key) {
    switch (key) {
      case 'home':
        return Icons.home_outlined;
      case 'food':
        return Icons.restaurant_outlined;
      case 'car':
        return Icons.directions_car_outlined;
      case 'shop':
        return Icons.shopping_bag_outlined;
      case 'health':
        return Icons.medical_services_outlined;
      default:
        return Icons.category_outlined;
    }
  }

  Color _iconColorForKey(String? key) {
    switch (key) {
      case 'home':
        return const Color(0xFF4E8DFF);
      case 'food':
        return const Color(0xFFFFC04D);
      case 'car':
        return const Color(0xFF5DD6FF);
      case 'shop':
        return const Color(0xFFBF5AF2);
      case 'health':
        return const Color(0xFFFF5C8A);
      default:
        return const Color(0xFF8E8E93);
    }
  }

  String _groupKindLabel(String? kind) {
    switch (kind) {
      case 'income':
        return 'Khoản thu';
      case 'expense':
        return 'Khoản chi';
      default:
        return 'Chưa chọn';
    }
  }

  Color _groupKindColor(String? kind) {
    switch (kind) {
      case 'income':
        return const Color(0xFF2ECC71);
      case 'expense':
        return const Color(0xFFFF4D4D);
      default:
        return const Color(0xFF8E8E93);
    }
  }

  bool get _hasSelectedGroup => _selectedGroupKey.trim().isNotEmpty;

  String _amountDigitsOnly() {
    return _amountController.text.replaceAll(RegExp(r'[^0-9]'), '');
  }

  String _formatAmountText(String rawDigits) {
    if (rawDigits.isEmpty) return '';
    final value = int.tryParse(rawDigits) ?? 0;
    return NumberFormat.decimalPattern('vi_VN').format(value);
  }

  double _amountFontSize() {
    final length = _amountDigitsOnly().length;
    if (length <= 6) return 32;
    if (length <= 8) return 28;
    if (length <= 10) return 24;
    return 20;
  }

  void _handleAmountChanged() {
    if (!mounted || _isFormattingAmount) return;

    final rawDigits = _amountDigitsOnly();
    final formatted = _formatAmountText(rawDigits);
    if (_amountController.text == formatted) {
      setState(() {});
      return;
    }

    _isFormattingAmount = true;
    _amountController.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
    _isFormattingAmount = false;
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.initialAmount != null && widget.initialAmount! > 0
          ? _formatAmountText(widget.initialAmount.toString())
          : '',
    );
    _isRepeat = widget.initialRepeat;
    _selectedGroupKey = widget.initialGroupKey?.trim() ?? '';
    _groupTouched = _selectedGroupKey.isNotEmpty;
    final initialMonthKey = widget.initialMonthKey ?? DateTime.now().toString();
    _selectedPeriod =
        widget.initialPeriod ??
        _BudgetPeriodChoice(
          key: 'month',
          label: 'Tháng này',
          rangeText: _monthRangeFromKey(initialMonthKey),
          monthKey: _currentMonthKeyFromKey(initialMonthKey),
        );
    _amountController.addListener(_handleAmountChanged);
    _loadGroups();
  }

  @override
  void dispose() {
    _amountController.removeListener(_handleAmountChanged);
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadGroups() async {
    final groups = await widget.loadGroups();
    if (!mounted) return;
    setState(() {
      _groups = groups;
      if (_selectedGroupKey.trim().isEmpty && _groups.isNotEmpty) {
        _selectedGroupKey = _groups.first['key']?.trim() ?? '';
      }
      _isLoading = false;
    });
  }

  String _currentMonthKeyFromKey(String monthKey) {
    final parts = monthKey.split('-');
    if (parts.length == 2) {
      final year = int.tryParse(parts[0]) ?? DateTime.now().year;
      final month = int.tryParse(parts[1]) ?? DateTime.now().month;
      return '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';
    }
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
  }

  String _monthRangeFromKey(String monthKey) {
    final parts = monthKey.split('-');
    if (parts.length != 2) return monthKey;
    final year = int.tryParse(parts[0]) ?? DateTime.now().year;
    final month = int.tryParse(parts[1]) ?? DateTime.now().month;
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 0);
    String fmt(DateTime date) =>
        '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
    return '${fmt(start)} - ${fmt(end)}';
  }

  @override
  Widget build(BuildContext context) {
    final currentGroup = _groupTouched && _hasSelectedGroup
        ? _groups.firstWhere(
            (group) => group['key'] == _selectedGroupKey,
            orElse: () => <String, String>{
              'key': _selectedGroupKey,
              'label': _selectedGroupKey,
              'kind': 'expense',
            },
          )
        : <String, String>{};
    final groupLabel = _groupTouched && _hasSelectedGroup
        ? (currentGroup['label']?.toString().trim().isNotEmpty == true
              ? currentGroup['label']!.trim()
              : _selectedGroupKey)
        : 'Chọn hạng mục';
    final groupKind = _groupTouched && _hasSelectedGroup
        ? currentGroup['kind']?.toString() ?? 'expense'
        : 'unknown';
    final groupIcon = _groupTouched && _hasSelectedGroup
        ? _iconDataForKey(_selectedGroupKey)
        : Icons.category_outlined;
    final groupColor = _groupTouched && _hasSelectedGroup
        ? _iconColorForKey(_selectedGroupKey)
        : const Color(0xFF8E8E93);
    final period = _selectedPeriod!;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          top: 18,
          bottom: MediaQuery.of(context).viewInsets.bottom + 18,
        ),
        child: _isLoading
            ? const SizedBox(
                height: 260,
                child: Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.title,
                      style: GoogleFonts.manrope(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Chọn nhóm, nhập số tiền và thời gian áp dụng.',
                      style: GoogleFonts.manrope(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.04),
                        ),
                      ),
                      child: Column(
                        children: [
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 6,
                            ),
                            leading: Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: groupColor.withValues(alpha: 0.18),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                groupIcon,
                                color: groupColor,
                                size: 22,
                              ),
                            ),
                            title: Text(
                              groupLabel,
                              style: GoogleFonts.manrope(
                                color: _hasSelectedGroup
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.35),
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: _hasSelectedGroup
                                ? Text(
                                    _groupKindLabel(groupKind),
                                    style: GoogleFonts.manrope(
                                      color: _groupKindColor(groupKind),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  )
                                : null,
                            trailing: const Icon(
                              Icons.chevron_right_rounded,
                              color: Colors.white54,
                            ),
                            onTap: () async {
                              final pickedGroup = await widget.pickGroup();
                              if (pickedGroup == null || !mounted) return;
                              final groups = await widget.loadGroups();
                              if (!mounted) return;
                              setState(() {
                                _groups = groups;
                                _selectedGroupKey = pickedGroup;
                                _groupTouched = true;
                              });
                            },
                          ),
                          Divider(
                            height: 1,
                            color: Colors.white.withValues(alpha: 0.06),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Số tiền',
                                  style: GoogleFonts.manrope(
                                    color: Colors.white.withValues(alpha: 0.45),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: Colors.white.withValues(
                                            alpha: 0.18,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        'VND',
                                        style: GoogleFonts.manrope(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: TextField(
                                        controller: _amountController,
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                          LengthLimitingTextInputFormatter(12),
                                        ],
                                        style: GoogleFonts.manrope(
                                          color: Colors.white,
                                          fontSize: _amountFontSize(),
                                          fontWeight: FontWeight.w800,
                                        ),
                                        maxLines: 1,
                                        textAlign: TextAlign.left,
                                        textAlignVertical:
                                            TextAlignVertical.center,
                                        decoration: InputDecoration(
                                          hintText: 'Nhập giá tiền',
                                          hintStyle: GoogleFonts.manrope(
                                            color: Colors.white.withValues(
                                              alpha: 0.28,
                                            ),
                                            fontSize: 24,
                                            fontWeight: FontWeight.w700,
                                          ),
                                          suffixText: 'đ',
                                          suffixStyle: GoogleFonts.manrope(
                                            color: Colors.white.withValues(
                                              alpha: 0.70,
                                            ),
                                            fontSize: 24,
                                            fontWeight: FontWeight.w700,
                                          ),
                                          border: InputBorder.none,
                                          isDense: true,
                                          contentPadding: EdgeInsets.zero,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Divider(
                            height: 1,
                            color: Colors.white.withValues(alpha: 0.06),
                          ),
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 6,
                            ),
                            leading: const Icon(
                              Icons.calendar_month_outlined,
                              color: Colors.white,
                            ),
                            title: Text(
                              period.label,
                              style: GoogleFonts.manrope(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              period.rangeText,
                              style: GoogleFonts.manrope(
                                color: Colors.white.withValues(alpha: 0.45),
                                fontSize: 12,
                              ),
                            ),
                            trailing: const Icon(
                              Icons.chevron_right_rounded,
                              color: Colors.white54,
                            ),
                            onTap: () async {
                              final pickedPeriod = await widget.pickPeriod(
                                period,
                              );
                              if (pickedPeriod == null || !mounted) return;
                              setState(() => _selectedPeriod = pickedPeriod);
                            },
                          ),
                          Divider(
                            height: 1,
                            color: Colors.white.withValues(alpha: 0.06),
                          ),
                          SwitchListTile.adaptive(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 4,
                            ),
                            value: _isRepeat,
                            onChanged: (value) =>
                                setState(() => _isRepeat = value),
                            activeThumbColor: const Color(0xFF2DBC4D),
                            title: Text(
                              'Lặp lại ngân sách này',
                              style: GoogleFonts.manrope(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              'Ngân sách được tự động lặp lại ở kỳ hạn tiếp theo.',
                              style: GoogleFonts.manrope(
                                color: Colors.white.withValues(alpha: 0.45),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 54,
                      child: ElevatedButton(
                        onPressed: () {
                          final effectiveGroupKey =
                              _selectedGroupKey.trim().isNotEmpty
                              ? _selectedGroupKey.trim()
                              : (_groups.isNotEmpty
                                    ? _groups.first['key']?.trim() ?? ''
                                    : '');
                          final amount = int.tryParse(_amountDigitsOnly()) ?? 0;
                          if (amount <= 0 || effectiveGroupKey.isEmpty) {
                            return;
                          }
                          Navigator.of(context).pop(<String, dynamic>{
                            'groupKey': effectiveGroupKey,
                            'amount': amount,
                            'monthKey': period.monthKey,
                            'isRepeat': _isRepeat,
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2DBC4D),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        child: Text(
                          widget.buttonLabel,
                          style: GoogleFonts.manrope(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
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

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: GoogleFonts.manrope(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.manrope(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _HalfArcPainter extends CustomPainter {
  _HalfArcPainter({
    required this.progress,
    required this.color,
    required this.backgroundColor,
  });

  final double progress;
  final Color color;
  final Color backgroundColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paintBackground = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;

    final paintProgress = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromLTWH(18, 10, size.width - 36, size.height * 2 - 24);
    canvas.drawArc(rect, pi, pi, false, paintBackground);
    canvas.drawArc(rect, pi, pi * progress, false, paintProgress);
  }

  @override
  bool shouldRepaint(covariant _HalfArcPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}

class _KindChoiceButton extends StatelessWidget {
  const _KindChoiceButton({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? color.withValues(alpha: 0.18) : const Color(0xFF1C1C1E),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? color.withValues(alpha: 0.55)
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

// --- Budget detail view for a single category
class BudgetDetailScreen extends StatefulWidget {
  final String categoryKey;
  const BudgetDetailScreen({super.key, required this.categoryKey});

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await _storage.readBudgetItems();
    Map<String, dynamic>? found;
    for (final it in items) {
      final ik =
          (it['iconKey'] ?? it['categoryKey'] ?? it['key'])?.toString() ?? '';
      if (ik == widget.categoryKey) {
        found = Map<String, dynamic>.from(it);
        break;
      }
    }
    if (!mounted) return;
    setState(() {
      _item = found;
      _monthKey = found?['monthKey']?.toString() ?? _currentMonthKey();
      _loading = false;
    });
  }

  String _formatVnd(int value) =>
      NumberFormat.decimalPattern('vi_VN').format(value);

  String _currentMonthKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
  }

  String _monthRangeFromKey(String monthKey) {
    final parts = monthKey.split('-');
    if (parts.length != 2) return monthKey;
    final year = int.tryParse(parts[0]) ?? DateTime.now().year;
    final month = int.tryParse(parts[1]) ?? DateTime.now().month;
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 0);
    return '${start.day.toString().padLeft(2, '0')}/${start.month.toString().padLeft(2, '0')} - ${end.day.toString().padLeft(2, '0')}/${end.month.toString().padLeft(2, '0')}';
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
  }) async {
    final nextMonthKey =
        '${period.start.year.toString().padLeft(4, '0')}-${period.start.month.toString().padLeft(2, '0')}';
    final token = await _sessionService.getToken();
    final categoryKey = widget.categoryKey;
    final iconKey = (_item?['iconKey']?.toString().trim().isNotEmpty == true)
        ? _item!['iconKey'].toString()
        : categoryKey;
    final kind = _item?['kind']?.toString();
    final color = _item?['color']?.toString();
    final categoryId = int.tryParse(_item?['categoryId']?.toString() ?? '');
    final isRepeat = _item?['isRepeat'] == true;

    if (token != null && token.trim().isNotEmpty) {
      await _financeApiService.upsertCategory(
        token: token,
        name: name,
        kind: kind,
        iconKey: iconKey,
        color: color,
      );
      await _financeApiService.upsertBudget(
        token: token,
        name: name,
        limitAmount: limitAmount,
        monthKey: nextMonthKey,
        categoryId: categoryId,
        slug: categoryKey,
        kind: kind,
        iconKey: iconKey,
        color: color,
        isRepeat: isRepeat,
      );
    }

    final items = await _storage.readBudgetItems();
    final updatedItems = items.map((item) {
      final ik =
          (item['iconKey'] ?? item['categoryKey'] ?? item['key'])?.toString() ??
          '';
      if (ik != categoryKey) return item;
      final next = Map<String, dynamic>.from(item);
      next['name'] = name;
      next['limit'] = limitAmount;
      next['monthKey'] = nextMonthKey;
      next['updatedAt'] = DateTime.now().millisecondsSinceEpoch.toString();
      return next;
    }).toList();
    await _storage.saveBudgetItems(updatedItems);

    final groups = await _storage.readBudgetGroups();
    final updatedGroups = groups.map((group) {
      if ((group['key'] ?? '').trim().toLowerCase() !=
          categoryKey.trim().toLowerCase()) {
        return group;
      }
      return {...group, 'label': name};
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
      };
      _monthKey = nextMonthKey;
      _didChange = true;
    });
  }

  Future<void> _showEditDialog() async {
    final currentName = _item?['name']?.toString() ?? widget.categoryKey;
    final currentLimit = int.tryParse(_item?['limit']?.toString() ?? '0') ?? 0;
    var selectedPeriod = _rangeFromMonthKey(
      _monthKey.isNotEmpty ? _monthKey : _currentMonthKey(),
    );
    final nameController = TextEditingController(text: currentName);
    final amountController = TextEditingController(
      text: NumberFormat.decimalPattern('vi_VN').format(currentLimit),
    );
    var isSaving = false;
    var isFormattingAmount = false;

    void formatAmountField() {
      if (isFormattingAmount) return;
      final digits = amountController.text.replaceAll(RegExp(r'[^0-9]'), '');
      final limitedDigits = digits.length > 12
          ? digits.substring(0, 12)
          : digits;
      final formatted = limitedDigits.isEmpty
          ? ''
          : NumberFormat.decimalPattern(
              'vi_VN',
            ).format(int.parse(limitedDigits));
      if (formatted == amountController.text) return;

      isFormattingAmount = true;
      amountController.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
      isFormattingAmount = false;
    }

    amountController.addListener(formatAmountField);

    try {
      if (!mounted) return;
      final result = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF141414),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return SafeArea(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 18,
                    right: 18,
                    top: 18,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 18,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Center(
                          child: Container(
                            width: 44,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Sửa ngân sách',
                          style: GoogleFonts.manrope(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: nameController,
                          style: GoogleFonts.manrope(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Tên hạng mục',
                            labelStyle: GoogleFonts.manrope(
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                            filled: true,
                            fillColor: const Color(0xFF1C1C1E),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: amountController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(12),
                          ],
                          style: GoogleFonts.manrope(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Số tiền',
                            labelStyle: GoogleFonts.manrope(
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                            filled: true,
                            fillColor: const Color(0xFF1C1C1E),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () async {
                            final picked = await showDateRangePicker(
                              context: dialogContext,
                              firstDate: DateTime(
                                DateTime.now().year - 3,
                                1,
                                1,
                              ),
                              lastDate: DateTime(
                                DateTime.now().year + 3,
                                12,
                                31,
                              ),
                              initialDateRange: selectedPeriod,
                              helpText: 'Chọn thời gian',
                              saveText: 'Chọn',
                              cancelText: 'Huỷ',
                            );
                            if (picked == null) return;
                            setDialogState(() {
                              selectedPeriod = picked;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1C1C1E),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.calendar_month_outlined,
                                  color: Colors.white70,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Thời gian',
                                        style: GoogleFonts.manrope(
                                          color: Colors.white.withValues(
                                            alpha: 0.55,
                                          ),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${selectedPeriod.start.day.toString().padLeft(2, '0')}/${selectedPeriod.start.month.toString().padLeft(2, '0')} - ${selectedPeriod.end.day.toString().padLeft(2, '0')}/${selectedPeriod.end.month.toString().padLeft(2, '0')}',
                                        style: GoogleFonts.manrope(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  color: Colors.white54,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: isSaving
                                ? null
                                : () {
                                    final name = nameController.text.trim();
                                    final amount =
                                        int.tryParse(
                                          amountController.text.replaceAll(
                                            RegExp(r'[^0-9]'),
                                            '',
                                          ),
                                        ) ??
                                        0;
                                    if (name.isEmpty || amount <= 0) {
                                      return;
                                    }
                                    setDialogState(() {
                                      isSaving = true;
                                    });
                                    Navigator.of(
                                      dialogContext,
                                    ).pop(<String, dynamic>{
                                      'name': name,
                                      'amount': amount,
                                      'period': selectedPeriod,
                                    });
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2DBC4D),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            child: Text(
                              isSaving ? 'Đang lưu...' : 'Lưu thay đổi',
                              style: GoogleFonts.manrope(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
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
      if (name.isEmpty || amount <= 0) return;
      await _saveEditedItem(name: name, limitAmount: amount, period: period);
    } finally {
      amountController.removeListener(formatAmountField);
      nameController.dispose();
      amountController.dispose();
    }
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
      if (budgetId != null && budgetId > 0) {
        return id != budgetId.toString();
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop(_didChange);
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
            : Padding(
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
                                  color: Colors.white12,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    name.isNotEmpty ? name[0] : '?',
                                    style: const TextStyle(color: Colors.white),
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
                              valueColor: AlwaysStoppedAnimation(Colors.white),
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
                                    _monthRangeFromKey(
                                      _monthKey.isNotEmpty
                                          ? _monthKey
                                          : _currentMonthKey(),
                                    ),
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.85,
                                      ),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    'Hôm nay là ngày cuối cùng',
                                    style: TextStyle(color: Colors.white54),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1A1A1C),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                          elevation: 0,
                        ),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Text(
                            'Danh sách giao dịch',
                            style: TextStyle(
                              color: Color(0xFF2ECC71),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
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
