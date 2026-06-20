import 'dart:math';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/services/notification_service.dart';
import 'package:flutter_application_1/services/auth_session_service.dart';
import 'package:flutter_application_1/services/budget_storage_service.dart';
import 'package:flutter_application_1/services/calendar_storage_service.dart';
import 'package:flutter_application_1/services/calendar_refresh_notifier.dart';
import 'package:flutter_application_1/services/finance_api_service.dart';

import 'budget_history.dart';
import '../widgets/budget/budget_components.dart';
import 'budget_detail.dart';








class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
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
  
  List<Map<String, dynamic>> _rawItems = <Map<String, dynamic>>[];
  String _dashboardPeriodChoice = 'all';

  DateTimeRange get _currentDashboardRange {
    final now = DateTime.now();
    switch (_dashboardPeriodChoice) {
      case 'week':
        final monday = now.subtract(Duration(days: now.weekday - 1));
        final start = DateTime(monday.year, monday.month, monday.day);
        final end = start.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));
        return DateTimeRange(start: start, end: end);
      case 'year':
        final start = DateTime(now.year, 1, 1);
        final end = DateTime(now.year, 12, 31, 23, 59, 59);
        return DateTimeRange(start: start, end: end);
      case 'month':
      default:
        final start = DateTime(now.year, now.month, 1);
        final end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
        return DateTimeRange(start: start, end: end);
    }
  }

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

  List<BudgetPeriodChoice> _buildBudgetPeriodChoices(DateTime now) {
    final monthKey =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
    final weekStart = _startOfWeek(now);
    final weekEnd = _endOfWeek(now);
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 0);
    final quarterStart = _startOfQuarter(now);
    final quarterEnd = _endOfQuarter(now);
    final yearStart = DateTime(now.year, 1, 1);
    final yearEnd = DateTime(now.year, 12, 31, 23, 59, 59);

    return [
      BudgetPeriodChoice(
        key: 'week',
        label: 'Tuần này',
        rangeText: _formatRange(weekStart, weekEnd),
        monthKey: monthKey,
        customRange: DateTimeRange(start: weekStart, end: weekEnd),
      ),
      BudgetPeriodChoice(
        key: 'next7days',
        label: '7 ngày tới (từ hôm nay)',
        rangeText: _formatRange(now, now.add(const Duration(days: 6))),
        monthKey: monthKey,
        customRange: DateTimeRange(start: now, end: now.add(const Duration(days: 6))),
      ),
      BudgetPeriodChoice(
        key: 'month',
        label: 'Tháng này',
        rangeText: _formatRange(monthStart, monthEnd),
        monthKey: monthKey,
        customRange: DateTimeRange(start: monthStart, end: monthEnd),
      ),
      BudgetPeriodChoice(
        key: 'next30days',
        label: '30 ngày tới (từ hôm nay)',
        rangeText: _formatRange(now, now.add(const Duration(days: 29))),
        monthKey: monthKey,
        customRange: DateTimeRange(start: now, end: now.add(const Duration(days: 29))),
      ),
      BudgetPeriodChoice(
        key: 'quarter',
        label: 'Quý này',
        rangeText: _formatRange(quarterStart, quarterEnd),
        monthKey: monthKey,
        customRange: DateTimeRange(start: quarterStart, end: quarterEnd),
      ),
      BudgetPeriodChoice(
        key: 'year',
        label: 'Năm nay',
        rangeText: _formatRange(yearStart, yearEnd),
        monthKey: monthKey,
        customRange: DateTimeRange(start: yearStart, end: yearEnd),
      ),
      BudgetPeriodChoice(
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
      'kind': item['kind'] ?? item['categoryKind'] ?? category['kind'] ?? 'expense',
      'color': item['color'] ?? item['categoryColor'] ?? category['color'] ?? '#8E8E93',
      'startDate': item['startDate'] ?? item['start_date'],
      'endDate': item['endDate'] ?? item['end_date'],
      'monthKey': item['monthKey'] ?? item['month_key'],
      'isRepeat': item['isRepeat'] ?? item['is_repeat'] ?? false,
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



  int get _totalSpent =>
      _items.fold<int>(0, (sum, item) => sum + _parseAmount(item['spent']));
  int get _remaining => _monthlyBudget - _totalSpent;
  int get _daysLeft {
    final now = DateTime.now();
    final range = _currentDashboardRange;
    final endDay = DateTime(range.end.year, range.end.month, range.end.day);
    final nowDay = DateTime(now.year, now.month, now.day);
    return max(0, endDay.difference(nowDay).inDays);
  }

  double get _progress =>
      _monthlyBudget <= 0 ? 0 : (_totalSpent / _monthlyBudget).clamp(0.0, 1.0);

  /// Tiền an toàn mỗi ngày = (Còn lại) / (Số ngày còn lại trong kỳ)
  int get _dailySafeToSpend {
    final days = _daysLeft;
    if (days <= 0 || _remaining <= 0) return 0;
    return (_remaining / days).floor();
  }

  /// Màu thanh tiến độ dựa trên mức sử dụng:
  /// < 50% = xanh lá, 50-80% = vàng, 80-100% = cam, >= 100% = đỏ
  Color _progressColor(double ratio) {
    if (ratio >= 1.0) return const Color(0xFFFF3B30); // Đỏ — vượt ngân sách
    if (ratio >= 0.8) return const Color(0xFFFF9500); // Cam — cảnh báo
    if (ratio >= 0.5) return const Color(0xFFFFCC00); // Vàng — chú ý
    return const Color(0xFF34C759); // Xanh lá — an toàn
  }

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

  Future<List<Map<String, dynamic>>> _readLocalExpenseTransactionsRange(DateTimeRange range) async {
    final prefs = await SharedPreferences.getInstance();
    final storageKey = await _calendarStorageService.currentCalendarKey();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return [];

    final results = <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return results;

      for (final entry in decoded) {
        if (entry is! Map) continue;
        final post = Map<String, dynamic>.from(entry);

        final rawDate = post['date']?.toString().trim() ?? post['entryTs']?.toString().trim() ?? '';
        final parsedDate = DateTime.tryParse(rawDate)?.toLocal();
        if (parsedDate == null) continue;

        if (parsedDate.isBefore(range.start) || parsedDate.isAfter(range.end)) {
          continue; // Outside of range!
        }

        if (!_postIsExpense(post)) continue;
        post['_parsedDate'] = parsedDate;
        results.add(post);
      }
    } catch (_) {}
    return results;
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
        
        // ONLY sum pending posts that haven't been synced to the server yet
        final id = post['id']?.toString().trim() ?? '';
        if (id.isNotEmpty) continue;

        if (_monthKeyFromRawDate(post) != monthKey) continue;

        final categoryKey =
            (post['categoryKey'] ?? post['category_key'] ?? post['categoryId'])
                ?.toString()
                .trim();
        if (categoryKey == null || categoryKey.isEmpty) continue;

        final amount = _parseAmount(post['amount']);
        if (amount <= 0) continue;

        // Fix: chỉ tính expense (chi tiêu) vào budget spent; income không trừ budget
        if (!_postIsExpense(post)) continue;
        final signedAmount = amount;
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
    Map<String, int> localPendingSpentByCategory,
  ) {
    if (items.isEmpty) return items;

    return items.map((item) {
      final itemKey =
          (item['categoryKey'] ??
                  item['category_key'] ??
                  item['iconKey'] ??
                  item['key'])
              ?.toString()
              .trim();
      
      final remoteSpent = _parseAmount(item['spent']);
      
      if (itemKey == null || itemKey.isEmpty) return item;

      final localPendingSpent = localPendingSpentByCategory[itemKey] ?? 0;
      if (localPendingSpent <= 0) return item;

      final next = Map<String, dynamic>.from(item);
      next['spent'] = remoteSpent + localPendingSpent;
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
            // Build lookup maps: slug key → label AND slug key → iconKey (emoji)
            final localLabelMap = <String, String>{};
            final localIconMap = <String, String>{};
            for (final g in localGroups) {
              final k = (g['key'] ?? '').toString().trim().toLowerCase();
              final l = (g['label'] ?? '').toString();
              final icon = (g['iconKey'] ?? '').toString();
              if (k.isNotEmpty) {
                if (l.isNotEmpty) localLabelMap[k] = l;
                // Chỉ lưu nếu là emoji thực sự (unicode > 0xFF)
                if (icon.isNotEmpty &&
                    icon.runes.isNotEmpty &&
                    icon.runes.first > 0xFF) {
                  localIconMap[k] = icon;
                }
              }
            }
            items = items.map((it) {
              // Dùng categoryKey (slug) để tra icon và label
              final catKey =
                  (it['categoryKey'] ?? it['key'])?.toString().trim().toLowerCase() ?? '';
              // iconKey hiện tại từ server (có thể là slug)
              final rawIcon = (it['iconKey'] ?? '').toString().trim();
              final isRawEmoji =
                  rawIcon.isNotEmpty &&
                  rawIcon.runes.isNotEmpty &&
                  rawIcon.runes.first > 0xFF;

              if (catKey.isNotEmpty &&
                  (localLabelMap.containsKey(catKey) ||
                      localIconMap.containsKey(catKey))) {
                final next = Map<String, dynamic>.from(it);
                if (localLabelMap.containsKey(catKey)) {
                  next['name'] = localLabelMap[catKey];
                }
                // Ghi đè iconKey bằng emoji từ local nếu server chỉ trả slug
                if (!isRawEmoji && localIconMap.containsKey(catKey)) {
                  next['iconKey'] = localIconMap[catKey];
                }
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

    _rawItems = items;
    await _applyDashboardFilter();

    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });
    _notifyOverBudgetItems(items);
  }

  DateTimeRange _rangeFromMonthKey(String monthKey) {
    final parts = monthKey.split('-');
    final year = int.tryParse(parts.length == 2 ? parts[0] : '') ?? DateTime.now().year;
    final month = int.tryParse(parts.length == 2 ? parts[1] : '') ?? DateTime.now().month;
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 0, 23, 59, 59);
    return DateTimeRange(start: start, end: end);
  }

  Future<void> _applyDashboardFilter() async {
    final range = _currentDashboardRange;
    final transactions = await _readLocalExpenseTransactionsRange(range);

    int totalLimit = 0;
    List<Map<String, dynamic>> filteredItems = [];

    for (final item in _rawItems) {
      final itemStartStr = item['startDate'];
      final itemEndStr = item['endDate'];
      DateTime itemStart;
      DateTime itemEnd;
      if (itemStartStr != null && itemEndStr != null) {
        itemStart = DateTime.parse(itemStartStr).toLocal();
        itemEnd = DateTime.parse(itemEndStr).toLocal();
      } else {
        final mk = item['monthKey']?.toString() ?? _currentMonthKey();
        final r = _rangeFromMonthKey(mk);
        itemStart = r.start;
        itemEnd = r.end;
      }

      final overlapStart = itemStart.isAfter(range.start) ? itemStart : range.start;
      final overlapEnd = itemEnd.isBefore(range.end) ? itemEnd : range.end;

      if (!overlapEnd.isBefore(overlapStart)) {
        final itemTotalDays = itemEnd.difference(itemStart).inDays + 1;

        // Phân loại ngân sách: Tuần (<=7 ngày), Tháng (28-31 ngày), Năm (>=365 ngày), còn lại là Tùy chỉnh
        bool isWeeklyBudget = itemTotalDays <= 7;
        bool isMonthlyBudget = itemTotalDays >= 28 && itemTotalDays <= 31;
        bool isYearlyBudget = itemTotalDays >= 365 && itemTotalDays <= 366;
        bool isCustomBudget = !isWeeklyBudget && !isMonthlyBudget && !isYearlyBudget;

        // Chỉ hiển thị ngân sách có ngày bắt đầu NẰM TRONG khoảng thời gian của dashboard đang chọn
        // Điều này giúp ngân sách không bị "chạy lộn xộn" sang các tuần/tháng khác
        bool startsInRange = !itemStart.isBefore(range.start) && !itemStart.isAfter(range.end);
        if (_dashboardPeriodChoice != 'all' && _dashboardPeriodChoice != 'custom') {
          if (!startsInRange) continue;
        }

        // Phân loại theo tab
        if (_dashboardPeriodChoice == 'week' && !isWeeklyBudget) continue;
        if (_dashboardPeriodChoice == 'month' && !isMonthlyBudget) continue;
        if (_dashboardPeriodChoice == 'year' && !isYearlyBudget) continue;
        if (_dashboardPeriodChoice == 'custom' && !isCustomBudget) continue;

        final limit = _parseAmount(item['limit']);
        // Không chia nhỏ số tiền theo ngày nữa, hiển thị đúng 100% số tiền người dùng tạo
        final actualLimit = limit;
        totalLimit += actualLimit;

        final itemKey = (item['categoryKey'] ?? item['category_key'] ?? item['iconKey'] ?? item['key'])?.toString().trim();
        
        int localSpent = 0;
        if (itemKey != null) {
          for (final t in transactions) {
            final tDate = t['_parsedDate'] as DateTime;
            if (!tDate.isBefore(overlapStart) && !tDate.isAfter(overlapEnd)) {
              final catKey = (t['categoryKey'] ?? t['category_key'] ?? t['categoryId'])?.toString().trim();
              if (catKey == itemKey) {
                localSpent += _parseAmount(t['amount']);
              }
            }
          }
        }

        final next = Map<String, dynamic>.from(item);
        next['limit'] = actualLimit;
        next['spent'] = localSpent;
        filteredItems.add(next);

        if (actualLimit > 0) {
          final ratio = localSpent / actualLimit;
          final name = item['name']?.toString() ?? 'Hạng mục';
          if (ratio >= 1.0) {
            NotificationService().showThresholdNotification(name, 100, localSpent, actualLimit);
          } else if (ratio >= 0.8) {
            NotificationService().showThresholdNotification(name, (ratio * 100).toInt(), localSpent, actualLimit);
          }
        }
      }
    }

    filteredItems.sort((a, b) {
      final sa = (a['sortOrder'] ?? 0) as int;
      final sb = (b['sortOrder'] ?? 0) as int;
      if (sa != sb) return sa.compareTo(sb);
      final na = (a['name'] ?? '').toString();
      final nb = (b['name'] ?? '').toString();
      return na.compareTo(nb);
    });

    _items = filteredItems;

    if (!mounted) return;
    setState(() {
      _monthlyBudget = totalLimit;
      _items = filteredItems;
    });
  }

  String _buildDurationText(Map<String, dynamic> item) {
    try {
      final startStr = item['startDate'];
      final endStr = item['endDate'];
      DateTime start;
      DateTime end;
      if (startStr != null && endStr != null) {
        start = DateTime.parse(startStr).toLocal();
        end = DateTime.parse(endStr).toLocal();
      } else {
        final mk = item['monthKey']?.toString() ?? _currentMonthKey();
        final r = _rangeFromMonthKey(mk);
        start = r.start;
        end = r.end;
      }
      final s = '${start.day.toString().padLeft(2, '0')}/${start.month.toString().padLeft(2, '0')}';
      final e = '${end.day.toString().padLeft(2, '0')}/${end.month.toString().padLeft(2, '0')}';
      return '$s - $e';
    } catch (_) {
      return '';
    }
  }

  Future<List<Map<String, String>>> _loadSelectableGroups() async {
    final token = await _sessionService.getToken();
    List<Map<String, String>> existing;

    if (token != null && token.isNotEmpty) {
      final remote = await _financeApiService.getCategories(token: token);
      if (remote.success &&
          remote.data != null &&
          remote.data!['data'] is List) {
        final localGroups = await _storageService.readBudgetGroups();
        final localIconMap = <String, String>{};
        for (final g in localGroups) {
          final k = (g['key'] ?? '').toString().trim().toLowerCase();
          final icon = (g['iconKey'] ?? '').toString();
          if (k.isNotEmpty && icon.runes.isNotEmpty && icon.runes.first > 0xFF) {
            localIconMap[k] = icon;
          }
        }
        
        existing = (remote.data!['data'] as List)
            .whereType<Map>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .where(
              (item) => item['isGlobal'] != true,
            ) // only user-created categories
            .map((item) {
              final key = item['key']?.toString() ?? item['slug']?.toString() ?? item['id']?.toString() ?? '';
              final localIcon = localIconMap[key.toLowerCase()];
              return <String, String>{
                'key': key,
                'label':
                    item['label']?.toString() ?? item['name']?.toString() ?? '',
                'kind': item['kind']?.toString() ?? '',
                'iconKey': localIcon ?? item['iconKey']?.toString() ?? '',
                'color': item['color']?.toString() ?? '',
              };
            })
            .where(
              (entry) => entry['key']!.isNotEmpty && entry['label']!.isNotEmpty && entry['kind'] != 'income',
            )
            .toList();
      } else {
        existing = await _storageService.readBudgetGroups();
        existing = existing.where((g) => g['kind'] != 'income').toList();
      }
    } else {
      existing = await _storageService.readBudgetGroups();
      existing = existing.where((g) => g['kind'] != 'income').toList();
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
    if (!remote.success || remote.data == null || remote.data!['data'] is! List) {
      return null;
    }

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

  String slugifyGroupName(String value) {
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

  Future<Map<String, String>?> _showCreateGroupSheet() async {
    if (!mounted) return null;
    return showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => CreateGroupSheet(
        availableEmojis: availableEmojis,
        slugify: slugifyGroupName,
      ),
    );
  }


  Future<void> _saveNewBudgetGroup({
    required String key,
    required String label,
    required String kind,
    String? iconKey,
    String? color,
  }) async {
    final token = await _sessionService.getToken();
    if (token != null && token.isNotEmpty) {
      await _financeApiService.upsertCategory(
        token: token,
        name: label,
        kind: kind,
        iconKey: iconKey ?? key,
        color: color,
      );
    }

    final groups = await _storageService.readBudgetGroups();
    final nextGroups = <Map<String, String>>[
      ...groups.where(
        (group) =>
            (group['key'] ?? '').trim().toLowerCase() !=
            key.trim().toLowerCase(),
      ),
      {
        'key': key, 
        'label': label, 
        'kind': kind,
        'iconKey': ?iconKey,
        'color': ?color,
      },
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
    DateTimeRange? customRange,
    String? iconKey,
    String? color,
  }) async {
    final groups = await _loadSelectableGroups();
    final group = groups.firstWhere(
      (item) => item['key'] == groupKey,
      orElse: () => <String, String>{},
    );

    final label = group['label']?.toString() ?? _groupLabelForKey(groupKey);
    final kind = group['kind']?.toString() ?? 'expense';
    final remoteCategoryId = await _resolveRemoteCategoryId(groupKey, label);

    final finalIconKey = iconKey ?? group['iconKey']?.toString() ?? groupKey;
    final finalColor = color ?? group['color']?.toString();

    // Cập nhật lại cache nhóm (category) ngay lập tức nếu có thay đổi icon hoặc màu
    if (iconKey != null || color != null) {
      final updatedGroups = groups.map((g) {
        if (g['key'] == groupKey) {
          final nextGroup = Map<String, String>.from(g);
          if (iconKey != null) nextGroup['iconKey'] = iconKey;
          if (color != null) nextGroup['color'] = color;
          return nextGroup;
        }
        return g;
      }).toList();
      await _storageService.saveBudgetGroups(updatedGroups);
    }

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
        iconKey: finalIconKey,
        color: finalColor,
        isRepeat: isRepeat,
        startDate: customRange != null ? DateFormat('yyyy-MM-dd').format(customRange.start) : null,
        endDate: customRange != null ? DateFormat('yyyy-MM-dd').format(customRange.end) : null,
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
      'iconKey': iconKey,
      'monthKey': monthKey,
      'isRepeat': isRepeat,
      'createdAt': now,
      'updatedAt': now,
      if (customRange != null) 'startDate': DateFormat('yyyy-MM-dd').format(customRange.start),
      if (customRange != null) 'endDate': DateFormat('yyyy-MM-dd').format(customRange.end),
    });
    await _storageService.saveBudgetItems(items);
    await _loadData();
  }

  Future<dynamic> _showGroupPicker(List<dynamic> targetBudgets) async {
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
                            
                            final isBudgeted = targetBudgets.any((b) {
                              final bKey = (b['categoryKey'] ?? b['category_key'] ?? b['iconKey'] ?? '')?.toString().trim();
                              final bSlug = (b['categorySlug'] ?? b['category_slug'] ?? '')?.toString().trim();
                              final categoryInfo = b['category'] ?? {};
                              final catKey = categoryInfo['key']?.toString().trim() ?? '';
                              return (bKey == key || bSlug == key || catKey == key);
                            });
                            
                            final existingBudget = isBudgeted ? targetBudgets.firstWhere((b) {
                              final bKey = (b['categoryKey'] ?? b['category_key'] ?? b['iconKey'] ?? '')?.toString().trim();
                              final bSlug = (b['categorySlug'] ?? b['category_slug'] ?? '')?.toString().trim();
                              final categoryInfo = b['category'] ?? {};
                              final catKey = categoryInfo['key']?.toString().trim() ?? '';
                              return (bKey == key || bSlug == key || catKey == key);
                            }, orElse: () => <String, dynamic>{}) : null;
                            return Opacity(
                              opacity: isBudgeted ? 0.3 : 1.0,
                              child: ListTile(
                                onTap: () {
                                  if (isBudgeted) {
                                    Navigator.pop(sheetContext, {'action': 'edit', 'budget': existingBudget});
                                  } else {
                                    Navigator.pop(sheetContext, key);
                                  }
                                },
                                leading: CircleAvatar(
                                backgroundColor: Colors.white10,
                                child: buildCategoryWidget(
                                  (group['iconKey']?.toString() ?? '').isNotEmpty
                                      ? group['iconKey'].toString()
                                      : (label.isNotEmpty ? label[0] : '?'),
                                ),
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
                              trailing: isBudgeted ? null : IconButton(
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

  Future<dynamic> _showGroupPickerWithCreate(String monthKey) async {
    List<dynamic> targetBudgets = [];
    final token = await _sessionService.getToken();
    if (token != null && token.isNotEmpty) {
      try {
        final res = await _financeApiService.getBudgetDashboard(
          token: token,
          monthKey: monthKey,
        );
        if (res.success && res.data != null) {
          final rawItems = res.data!['items'];
          if (rawItems is List) {
            targetBudgets = rawItems.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
          }
        }
      } catch (_) {}
    }

    final selected = await _showGroupPicker(targetBudgets);
    if (selected == '__create_new__') {
      final created = await _showCreateGroupSheet();
      if (created == null) return null;
      await _saveNewBudgetGroup(
        key: created['key'] ?? '',
        label: created['label'] ?? '',
        kind: created['kind'] ?? 'expense',
        iconKey: created['iconKey'],
        color: created['color'],
      );
      return created['key'];
    }
    return selected;
  }

  Future<BudgetPeriodChoice?> _showBudgetPeriodPicker({
    required BudgetPeriodChoice currentSelection,
  }) async {
    final now = DateTime.now();
    final choices = _buildBudgetPeriodChoices(now);

    return showModalBottomSheet<BudgetPeriodChoice>(
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
                          final today = DateTime(now.year, now.month, now.day);
                          final pickedRange = await showDateRangePicker(
                            context: sheetContext,
                            firstDate: today,
                            lastDate: DateTime(now.year + 3, 12, 31),
                            initialDateRange: DateTimeRange(
                              start: today,
                              end: today,
                            ),
                            helpText: 'Chọn khoảng thời gian',
                            saveText: 'Chọn',
                            cancelText: 'Huỷ',
                          );
                          if (pickedRange == null) return;
                          if (!navigator.mounted) return;
                          navigator.pop(
                            BudgetPeriodChoice(
                              key: 'custom',
                              label: 'Tùy chỉnh',
                              rangeText: _formatRange(
                                pickedRange.start,
                                pickedRange.end,
                              ),
                              monthKey:
                                  '${pickedRange.start.year.toString().padLeft(4, '0')}-${pickedRange.start.month.toString().padLeft(2, '0')}',
                              customRange: pickedRange,
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
    BudgetPeriodChoice? initialPeriod,
  }) async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return SafeKeyboardPadding(
          child: BudgetFormSheet(
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
          ),
        );
      },
    );

    if (picked == null) return;
    if (picked['action'] == 'edit') {
      final budget = picked['budget'];
      if (budget is Map<String, dynamic>) {
        _showEditBudgetModal(budget);
      }
      return;
    }

    final amount = _parseAmount(picked['amount']);
    final groupKey = picked['groupKey']?.toString() ?? 'food';
    final monthKey = picked['monthKey']?.toString() ?? _currentMonthKey();
    final isRepeat = picked['isRepeat'] == true;
    final customRange = picked['customRange'] as DateTimeRange?;
    final iconKey = picked['iconKey']?.toString();
    final color = picked['color']?.toString();

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    await _saveBudgetItemFromModal(
      groupKey: groupKey,
      limitAmount: amount,
      monthKey: monthKey,
      isRepeat: isRepeat,
      customRange: customRange,
      iconKey: iconKey,
      color: color,
    );
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(content: Text('$buttonLabel thành công')));
  }

  Future<void> _showEditBudgetModal(Map<String, dynamic> existingBudget) async {
    final currentName = existingBudget['category']?['name']?.toString() ?? existingBudget['categoryName']?.toString() ?? existingBudget['name']?.toString() ?? '';
    final currentLimit = int.tryParse(existingBudget['limitAmount']?.toString() ?? existingBudget['limit']?.toString() ?? '0') ?? 0;
    
    DateTimeRange selectedPeriod;
    if (existingBudget['startDate'] != null && existingBudget['endDate'] != null) {
      selectedPeriod = DateTimeRange(
        start: DateTime.parse(existingBudget['startDate'].toString()).toLocal(),
        end: DateTime.parse(existingBudget['endDate'].toString()).toLocal(),
      );
    } else {
      selectedPeriod = _rangeFromMonthKey(existingBudget['monthKey']?.toString() ?? _currentMonthKey());
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
            initialIconKey: existingBudget['iconKey']?.toString() ?? existingBudget['category']?['iconKey']?.toString() ?? existingBudget['categoryIconKey']?.toString(),
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
    
    final idStr = existingBudget['id']?.toString() ?? '';
    if (idStr.isEmpty) return;
    
    final token = await _sessionService.getToken();
    if (token != null && token.isNotEmpty) {
      final res = await _financeApiService.upsertBudget(
        token: token,
        id: idStr,
        name: name,
        limitAmount: amount,
        monthKey: '${period.start.year.toString().padLeft(4, '0')}-${period.start.month.toString().padLeft(2, '0')}',
        startDate: DateFormat('yyyy-MM-dd').format(period.start),
        endDate: DateFormat('yyyy-MM-dd').format(period.end),
        iconKey: pickedIconKey,
      );
      if (res.success) {
        await _loadData();
      }
    }
  }

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
    BudgetPeriodChoice initialPeriod;
    if (_dashboardPeriodChoice == 'week') {
      initialPeriod = BudgetPeriodChoice(
        key: 'custom',
        label: 'Tùy chỉnh',
        rangeText: '${_currentDashboardRange.start.day.toString().padLeft(2, '0')}/${_currentDashboardRange.start.month.toString().padLeft(2, '0')} - ${_currentDashboardRange.end.day.toString().padLeft(2, '0')}/${_currentDashboardRange.end.month.toString().padLeft(2, '0')}',
        monthKey: _currentMonthKey(),
        customRange: _currentDashboardRange,
      );
    } else {
      initialPeriod = BudgetPeriodChoice(
        key: 'month',
        label: 'Tháng này',
        rangeText: _monthRangeFromKey(_currentMonthKey()),
        monthKey: _currentMonthKey(),
      );
    }

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
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _dashboardPeriodChoice,
                              icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                              dropdownColor: const Color(0xFF181818),
                              borderRadius: BorderRadius.circular(16),
                              style: GoogleFonts.manrope(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                              onChanged: (String? newValue) {
                                if (newValue != null && newValue != _dashboardPeriodChoice) {
                                  setState(() {
                                    _dashboardPeriodChoice = newValue;
                                  });
                                  _applyDashboardFilter();
                                }
                              },
                              items: const [
                                DropdownMenuItem(value: 'week', child: Text('Tuần này')),
                                DropdownMenuItem(value: 'month', child: Text('Tháng này')),
                                DropdownMenuItem(value: 'year', child: Text('Năm nay')),
                                DropdownMenuItem(value: 'custom', child: Text('Tùy chỉnh')),
                                DropdownMenuItem(value: 'all', child: Text('Tất cả')),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.history, color: Colors.white),
                            tooltip: 'Lịch sử ngân sách',
                            onPressed: () async {
                              final result = await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const BudgetHistoryScreen(),
                                ),
                              );
                              if (!mounted) return;
                              if (result is Map && result['action'] == 'reuse') {
                                final item = result['item'];
                                final limitAmount = int.tryParse(item['limitAmount']?.toString() ?? '0') ?? 0;
                                final groupKey = item['category']?['key']?.toString() 
                                              ?? item['categorySlug']?.toString() 
                                              ?? item['iconKey']?.toString()
                                              ?? 'other';
                                
                                final startDateStr = item['startDate']?.toString();
                                final endDateStr = item['endDate']?.toString();
                                BudgetPeriodChoice? reusePeriodChoice;
                                
                                if (startDateStr != null && endDateStr != null) {
                                  final start = DateTime.tryParse(startDateStr)?.toLocal();
                                  final end = DateTime.tryParse(endDateStr)?.toLocal();
                                  if (start != null && end != null) {
                                    final durationDays = end.difference(start).inDays + 1;
                                    final now = DateTime.now();
                                    final newStart = DateTime(now.year, now.month, now.day);
                                    final newEnd = newStart.add(Duration(days: durationDays - 1)).add(const Duration(hours: 23, minutes: 59, seconds: 59));
                                    final mKey = '${newStart.year.toString().padLeft(4, '0')}-${newStart.month.toString().padLeft(2, '0')}';
                                    reusePeriodChoice = BudgetPeriodChoice(
                                      key: 'custom',
                                      label: 'Tùy chỉnh',
                                      rangeText: _formatRange(newStart, newEnd),
                                      monthKey: mKey,
                                      customRange: DateTimeRange(start: newStart, end: newEnd),
                                    );
                                  }
                                }

                                _showBudgetFormDialog(
                                  title: 'Tái sử dụng ngân sách',
                                  buttonLabel: 'Lưu ngân sách',
                                  initialGroupKey: groupKey,
                                  initialAmount: limitAmount,
                                  initialMonthKey: reusePeriodChoice?.monthKey,
                                  initialPeriod: reusePeriodChoice,
                                );
                              }
                            },
                          ),
                        ],
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
                                      painter: HalfArcPainter(
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
                                        child: MiniMetric(
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
                                        child: MiniMetric(
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
                                        child: MiniMetric(
                                          value: _dashboardPeriodChoice == 'all' ? '∞' : '$_daysLeft ngày',
                                          label: _dashboardPeriodChoice == 'week' ? 'Đến cuối tuần' :
                                                 _dashboardPeriodChoice == 'year' ? 'Đến cuối năm' :
                                                 _dashboardPeriodChoice == 'all' ? 'Không giới hạn' : 'Đến cuối tháng',
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
                    const SizedBox(height: 14),

                    // ── Banner: Tiền an toàn mỗi ngày ──
                    if (_dailySafeToSpend > 0 && _dashboardPeriodChoice != 'all')
                      Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF1A2E1A),
                              const Color(0xFF102010),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFF34C759).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFF34C759).withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.tips_and_updates_rounded,
                                color: Color(0xFF34C759),
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Gợi ý chi tiêu hôm nay',
                                    style: GoogleFonts.manrope(
                                      color: const Color(0xFF34C759),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Mỗi ngày tối đa nên tiêu: ${_formatCompact(_dailySafeToSpend)}',
                                    style: GoogleFonts.manrope(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    'Còn lại ${_formatCompact(_remaining)} trong $_daysLeft ngày tới',
                                    style: GoogleFonts.manrope(
                                      color: Colors.white.withValues(alpha: 0.5),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

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
                        final iconColor = parseColor(iconKey);

                        final categoryKey =
                            (item['categoryKey'] ??
                                    item['key'])
                                ?.toString() ??
                            '';
                            
                        final isFuture = () {
                          final now = DateTime.now();
                          if (item['startDate'] != null) {
                            final startDate = DateTime.tryParse(item['startDate'].toString());
                            if (startDate != null) {
                              final startDay = DateTime(startDate.year, startDate.month, startDate.day);
                              final today = DateTime(now.year, now.month, now.day);
                              if (startDay.isAfter(today)) return true;
                            }
                          } else {
                            final mKey = item['monthKey']?.toString() ?? '';
                            final currentMKey = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
                            if (mKey.isNotEmpty && mKey.compareTo(currentMKey) > 0) return true;
                          }
                          return false;
                        }();
                        
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Opacity(
                            opacity: isFuture ? 0.4 : 1.0,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(24),
                              onTap: () async {
                                if (isFuture) {
                                  await _showEditBudgetModal(item);
                                  return;
                                }
                                final result = await Navigator.of(context)
                                  .push<bool>(
                                    MaterialPageRoute(
                                      builder: (_) => BudgetDetailScreen(
                                        item: item,
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
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: iconColor.withValues(
                                            alpha: 0.18,
                                          ),
                                          shape: BoxShape.circle,
                                        ),
                                        child: buildCategoryWidget(iconKey, size: 22),
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
                                        _progressColor(ratio),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
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
                                            const SizedBox(height: 2),
                                            Text(
                                              _buildDurationText(item),
                                              style: GoogleFonts.manrope(
                                                color: Colors.white.withValues(
                                                  alpha: 0.35,
                                                ),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w500,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        percentLabel,
                                        style: GoogleFonts.manrope(
                                          color: _progressColor(ratio),
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








// --- Budget detail view for a single category







