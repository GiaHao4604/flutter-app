import 'dart:convert';
import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/services/auth_session_service.dart';
import 'package:flutter_application_1/services/budget_storage_service.dart';
import 'package:flutter_application_1/services/calendar_storage_service.dart';
import 'package:flutter_application_1/services/finance_api_service.dart';

// Bảng màu cho các hạng mục
const List<Color> _kPaletteExpense = [
  Color(0xFFFF6B6B),
  Color(0xFFFF9F43),
  Color(0xFFFFD166),
  Color(0xFFFF6FB2),
  Color(0xFFA66CFF),
  Color(0xFF5E60CE),
  Color(0xFF48CAE4),
  Color(0xFF52B788),
  Color(0xFFFF8C00),
  Color(0xFFEF5777),
];
const List<Color> _kPaletteIncome = [
  Color(0xFF52B788),
  Color(0xFF43AA8B),
  Color(0xFF48CAE4),
  Color(0xFF90BE6D),
  Color(0xFF74C69D),
  Color(0xFF26A96C),
  Color(0xFF2A9D8F),
  Color(0xFF4CC9F0),
  Color(0xFF38B000),
  Color(0xFF52CC4E),
];

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  final AuthSessionService _sessionService = AuthSessionService();
  final FinanceApiService _financeApiService = FinanceApiService();
  final CalendarStorageService _storageService = CalendarStorageService();
  final BudgetStorageService _budgetStorageService = BudgetStorageService();

  final List<String> _tabs = const ['Tuần', 'Tháng', 'Năm', 'Tất cả'];
  int _selectedTab = 1; // mặc định Tháng
  bool _showExpense = true;
  int _touchedIndex = -1;
  bool _showBarChart = false; // false = pie, true = bar

  // Period offset: 0 = hiện tại, -1 = kỳ trước, +1 = kỳ sau
  int _periodOffset = 0;

  bool _isLoading = true;
  int _totalExpense = 0;
  int _totalIncome = 0;
  List<Map<String, dynamic>> _allRecords = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _categoryRows = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _barRows = <Map<String, dynamic>>[];

  // icon & màu từ ngân sách
  Map<String, String> _categoryIcons = {};
  Map<String, String> _categoryLabels = {};
  Map<String, Color> _categoryColors = {};

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    // Tải thông tin hạng mục từ ngân sách (icon, màu)
    try {
      final groups = await _budgetStorageService.readBudgetGroups();
      final icons = <String, String>{};
      final labels = <String, String>{};
      final colors = <String, Color>{};
      for (final g in groups) {
        final k = (g['key'] ?? '').toString().trim();
        if (k.isEmpty) continue;
        final icon = g['iconKey']?.toString().trim() ?? '';
        final label = g['label']?.toString().trim() ?? '';
        final colorHex = g['color']?.toString().trim() ?? '';
        if (icon.isNotEmpty) icons[k] = icon;
        if (label.isNotEmpty) labels[k] = label;
        // Bỏ qua màu xám mặc định (#8E8E93) để biểu đồ hiển thị màu sắc sinh động (vibrant) từ palette
        if (colorHex.isNotEmpty && colorHex.toUpperCase() != '#8E8E93') {
          try {
            final c = Color(int.parse(colorHex.replaceAll('#', '0xFF')));
            colors[k] = c;
          } catch (_) {}
        }
      }
      _categoryIcons = icons;
      _categoryLabels = labels;
      _categoryColors = colors;
    } catch (_) {}

    // Server records (toàn bộ lịch sử)
    final serverRecords = <Map<String, dynamic>>[];
    final localOnlyRecords = <Map<String, dynamic>>[];

    final token = await _sessionService.getToken();
    if (token != null && token.isNotEmpty) {
      final remote = await _financeApiService.getSummary(token: token);

      if (remote.success && remote.data != null) {
        final data = remote.data!;
        final transactions = data['transactions'];
        if (transactions is List) {
          for (final item in transactions) {
            if (item is Map) {
              serverRecords.add(
                _normalizeRecord(Map<String, dynamic>.from(item)),
              );
            }
          }
        }
      }
    }

    // IDs đã có trên server
    final serverIds = serverRecords
        .map((r) => r['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();

    final prefs = await SharedPreferences.getInstance();
    final key = await _storageService.currentCalendarKey();
    final raw = prefs.getString(key);

    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              final record = _normalizeRecord(Map<String, dynamic>.from(item));
              final id = record['id']?.toString() ?? '';
              final localId = item['localId']?.toString() ?? '';
              if (id.isNotEmpty && id != localId) continue;
              if (id.isNotEmpty && serverIds.contains(id)) continue;
              localOnlyRecords.add(record);
            }
          }
        }
      } catch (_) {}
    }

    final allRecords = [...serverRecords, ...localOnlyRecords];

    // Dedup
    final dedup = <String, Map<String, dynamic>>{};
    for (final record in allRecords) {
      final k = [
        record['id']?.toString() ?? '',
        record['dateKey']?.toString() ?? '',
        record['amount']?.toString() ?? '0',
        record['isExpense'] == true ? '1' : '0',
        record['categoryKey']?.toString() ?? '',
      ].join('|');
      dedup[k] = record;
    }
    final mergedRecords = dedup.values.toList();
    final stats = _computeStats(mergedRecords);
    final bars = _computeBarRows(mergedRecords);

    if (!mounted) return;
    setState(() {
      _allRecords = mergedRecords;
      _totalExpense = stats['totalExpense'] as int;
      _totalIncome = stats['totalIncome'] as int;
      _categoryRows = List<Map<String, dynamic>>.from(
        stats['categoryRows'] as List,
      );
      _barRows = bars;
      _isLoading = false;
    });
  }

  int _parseAmount(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '0') ?? 0;
  }

  Map<String, dynamic> _normalizeRecord(Map<String, dynamic> raw) {
    final categoryMap = raw['category'] is Map
        ? Map<String, dynamic>.from(raw['category'] as Map)
        : <String, dynamic>{};

    final k =
        raw['categoryKey']?.toString() ??
        raw['category_key']?.toString() ??
        categoryMap['key']?.toString() ??
        'other';

    final label =
        raw['categoryLabel']?.toString() ??
        raw['category_label']?.toString() ??
        categoryMap['label']?.toString() ??
        categoryMap['name']?.toString() ??
        _categoryLabels[k] ??
        k;

    final isoDate =
        raw['transactionDate']?.toString() ??
        raw['transaction_date']?.toString() ??
        raw['dateKey']?.toString() ??
        raw['date_key']?.toString() ??
        raw['date']?.toString() ??
        raw['entryTs']?.toString() ??
        '';

    final parsedDate = DateTime.tryParse(isoDate);

    return <String, dynamic>{
      'id': raw['id'],
      'amount': _parseAmount(raw['amount']),
      'isExpense': raw['isExpense'] == true || raw['is_expense'] == true,
      'categoryKey': k,
      'categoryLabel': k == 'other' ? 'Khác' : label,
      'date': parsedDate,
      'dateKey': parsedDate != null
          ? '${parsedDate.year.toString().padLeft(4, '0')}-${parsedDate.month.toString().padLeft(2, '0')}-${parsedDate.day.toString().padLeft(2, '0')}'
          : isoDate,
    };
  }

  // Trả về khoảng thời gian hiện tại dựa trên tab & offset
  (DateTime, DateTime) _getPeriodRange() {
    final now = DateTime.now();
    if (_selectedTab == 0) {
      // Tuần: offset tính theo tuần
      final weekStart = now.subtract(Duration(days: now.weekday - 1));
      final start = DateTime(weekStart.year, weekStart.month, weekStart.day)
          .add(Duration(days: 7 * _periodOffset));
      final end = start.add(const Duration(days: 7));
      return (start, end);
    }
    if (_selectedTab == 1) {
      // Tháng: offset tính theo tháng
      var month = now.month + _periodOffset;
      var year = now.year;
      while (month <= 0) { month += 12; year--; }
      while (month > 12) { month -= 12; year++; }
      final start = DateTime(year, month, 1);
      final end = DateTime(year, month + 1, 1);
      return (start, end);
    }
    if (_selectedTab == 2) {
      // Năm: offset tính theo năm
      final year = now.year + _periodOffset;
      return (DateTime(year, 1, 1), DateTime(year + 1, 1, 1));
    }
    // Tất cả: không có giới hạn
    return (DateTime(2000), DateTime(2100));
  }

  String _getPeriodLabel() {
    final now = DateTime.now();
    if (_selectedTab == 0) {
      final (start, end) = _getPeriodRange();
      final endDisplay = end.subtract(const Duration(days: 1));
      return '${start.day}/${start.month} - ${endDisplay.day}/${endDisplay.month}';
    }
    if (_selectedTab == 1) {
      var month = now.month + _periodOffset;
      var year = now.year;
      while (month <= 0) { month += 12; year--; }
      while (month > 12) { month -= 12; year++; }
      return 'Tháng $month/$year';
    }
    if (_selectedTab == 2) {
      return 'Năm ${now.year + _periodOffset}';
    }
    return 'Tất cả';
  }

  bool _matchesSelectedTab(DateTime date) {
    if (_selectedTab == 3) return true; // Tất cả
    final localDate = date.toLocal();
    final (start, end) = _getPeriodRange();
    final checkDay = DateTime(localDate.year, localDate.month, localDate.day);
    return !checkDay.isBefore(start) && checkDay.isBefore(end);
  }

  Map<String, dynamic> _computeStats(List<Map<String, dynamic>> source) {
    var totalExpense = 0;
    var totalIncome = 0;
    final categoryAgg = <String, Map<String, dynamic>>{};

    for (final item in source) {
      final date = item['date'];
      if (date is! DateTime) continue;
      if (!_matchesSelectedTab(date)) continue;

      final amount = _parseAmount(item['amount']);
      final isExpense = item['isExpense'] == true;

      if (isExpense) {
        totalExpense += amount;
      } else {
        totalIncome += amount;
      }

      final categoryKey = item['categoryKey']?.toString() ?? 'other';
      final categoryLabel = item['categoryLabel']?.toString() ?? categoryKey;
      final bucket = categoryAgg[categoryKey] ??
          <String, dynamic>{
            'key': categoryKey,
            'label': categoryLabel,
            'expenseAmount': 0,
            'incomeAmount': 0,
          };

      if (isExpense) {
        bucket['expenseAmount'] = _parseAmount(bucket['expenseAmount']) + amount;
      } else {
        bucket['incomeAmount'] = _parseAmount(bucket['incomeAmount']) + amount;
      }
      categoryAgg[categoryKey] = bucket;
    }

    final selectedTotal = _showExpense ? totalExpense : totalIncome;
    final rows = categoryAgg.values
        .map((row) {
          final selectedAmount = _showExpense
              ? _parseAmount(row['expenseAmount'])
              : _parseAmount(row['incomeAmount']);
          final percent = selectedTotal <= 0
              ? 0.0
              : min(1.0, selectedAmount / selectedTotal);
          return <String, dynamic>{
            'key': row['key'],
            'label': row['label'],
            'amount': selectedAmount,
            'percent': percent,
          };
        })
        .where((row) => _parseAmount(row['amount']) > 0)
        .toList()
      ..sort((a, b) => _parseAmount(b['amount']) - _parseAmount(a['amount']));

    return <String, dynamic>{
      'totalExpense': totalExpense,
      'totalIncome': totalIncome,
      'categoryRows': rows,
    };
  }

  // Tính dữ liệu cho biểu đồ cột theo từng ngày/tuần/tháng
  List<Map<String, dynamic>> _computeBarRows(List<Map<String, dynamic>> source) {
    final (periodStart, periodEnd) = _getPeriodRange();
    final aggregated = <String, int>{};

    for (final item in source) {
      final date = item['date'];
      if (date is! DateTime) continue;
      final localDate = date.toLocal();
      final checkDay = DateTime(localDate.year, localDate.month, localDate.day);
      if (checkDay.isBefore(periodStart) || !checkDay.isBefore(periodEnd)) continue;
      final isExpense = item['isExpense'] == true;
      if (_showExpense != isExpense) continue;

      String bucketKey;
      if (_selectedTab == 0) {
        // Tuần → mỗi ngày 1 cột
        bucketKey = '${localDate.day}/${localDate.month}';
      } else if (_selectedTab == 1) {
        // Tháng → mỗi ngày 1 cột
        bucketKey = '${localDate.day}';
      } else {
        // Năm / Tất cả → mỗi tháng 1 cột
        bucketKey = 'T${localDate.month}/${localDate.year}';
      }
      aggregated[bucketKey] = (aggregated[bucketKey] ?? 0) + _parseAmount(item['amount']);
    }

    // Sắp xếp theo thứ tự thời gian
    final entries = aggregated.entries.toList();
    final maxVal = entries.isEmpty ? 1 : entries.map((e) => e.value).reduce(max);
    return entries.map((e) => <String, dynamic>{
      'label': e.key,
      'amount': e.value,
      'ratio': maxVal > 0 ? e.value / maxVal : 0.0,
    }).toList();
  }

  void _recompute() {
    final stats = _computeStats(_allRecords);
    final bars = _computeBarRows(_allRecords);
    setState(() {
      _touchedIndex = -1;
      _totalExpense = stats['totalExpense'] as int;
      _totalIncome = stats['totalIncome'] as int;
      _categoryRows = List<Map<String, dynamic>>.from(
        stats['categoryRows'] as List,
      );
      _barRows = bars;
    });
  }

  // Trả về màu cho từng hạng mục
  Color _colorForIndex(String key, int index) {
    if (_categoryColors.containsKey(key)) return _categoryColors[key]!;
    final palette = _showExpense ? _kPaletteExpense : _kPaletteIncome;
    return palette[index % palette.length];
  }

  String _formatVnd(int value) {
    final negative = value < 0;
    final absValue = value.abs().toString();
    final buffer = StringBuffer();
    var count = 0;
    for (var i = absValue.length - 1; i >= 0; i--) {
      buffer.write(absValue[i]);
      count++;
      if (count == 3 && i != 0) {
        buffer.write('.');
        count = 0;
      }
    }
    final formatted = buffer.toString().split('').reversed.join();
    return '${negative ? '-' : ''}$formatted\u0111';
  }

  String _formatCompact(int value) {
    final negative = value < 0;
    final absValue = value.abs();
    if (absValue >= 1000000000) {
      final doubleVal = absValue / 1000000000;
      final formatted = (absValue % 1000000000 == 0)
          ? doubleVal.toStringAsFixed(0)
          : doubleVal.toStringAsFixed(1);
      return '${negative ? '-' : ''}${formatted}T';
    }
    if (absValue >= 1000000) {
      final doubleVal = absValue / 1000000;
      final formatted = (absValue % 1000000 == 0)
          ? doubleVal.toStringAsFixed(0)
          : doubleVal.toStringAsFixed(1);
      return '${negative ? '-' : ''}${formatted}tr';
    }
    return _formatVnd(value);
  }

  int get _selectedNetTotal => _totalIncome - _totalExpense;

  @override
  Widget build(BuildContext context) {
    final selectedTotal = _showExpense ? _totalExpense : _totalIncome;
    final signedTotal = _showExpense ? -selectedTotal : selectedTotal;

    return Scaffold(
      backgroundColor: const Color(0xFF080808),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Thống kê',
          style: GoogleFonts.manrope(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _showBarChart ? Icons.pie_chart_rounded : Icons.bar_chart_rounded,
              color: Colors.white70,
            ),
            tooltip: _showBarChart ? 'Biểu đồ tròn' : 'Biểu đồ cột',
            onPressed: () => setState(() => _showBarChart = !_showBarChart),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Tab Tuần / Tháng / Năm / Tất cả ──
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111111),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.07),
                        ),
                      ),
                      child: Row(
                        children: List.generate(_tabs.length, (index) {
                          final selected = index == _selectedTab;
                          return Expanded(
                            child: GestureDetector(
                              onTap: () {
                                _selectedTab = index;
                                _periodOffset = 0;
                                _recompute();
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeInOut,
                                padding: const EdgeInsets.symmetric(vertical: 11),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? const Color(0xFF2A2A2A)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Center(
                                  child: Text(
                                    _tabs[index],
                                    style: GoogleFonts.manrope(
                                      color: selected
                                          ? Colors.white
                                          : Colors.white.withValues(alpha: 0.35),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── Điều hướng kỳ (Tuần/Tháng/Năm) ──
                    if (_selectedTab != 3)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          GestureDetector(
                            onTap: () {
                              _periodOffset--;
                              _recompute();
                            },
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1B1B1B),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white12),
                              ),
                              child: const Icon(Icons.chevron_left_rounded,
                                  color: Colors.white70, size: 22),
                            ),
                          ),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Text(
                              _getPeriodLabel(),
                              key: ValueKey(_getPeriodLabel()),
                              style: GoogleFonts.manrope(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: _periodOffset < 0
                                ? () {
                                    _periodOffset++;
                                    _recompute();
                                  }
                                : null,
                            child: AnimatedOpacity(
                              opacity: _periodOffset < 0 ? 1.0 : 0.3,
                              duration: const Duration(milliseconds: 200),
                              child: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1B1B1B),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: const Icon(Icons.chevron_right_rounded,
                                    color: Colors.white70, size: 22),
                              ),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 20),

                    // ── 3 thẻ tổng quan ──
                    Row(
                      children: [
                        _StatCard(
                          title: 'Tổng chi',
                          value: '-${_formatCompact(_totalExpense)}',
                          accent: const Color(0xFFFF4D4D),
                          icon: Icons.north_east_rounded,
                        ),
                        const SizedBox(width: 10),
                        _StatCard(
                          title: 'Tổng thu',
                          value: '+${_formatCompact(_totalIncome)}',
                          accent: const Color(0xFF37C95B),
                          icon: Icons.south_west_rounded,
                        ),
                        const SizedBox(width: 10),
                        _StatCard(
                          title: 'Còn lại',
                          value: _formatCompact(_selectedNetTotal),
                          accent: const Color(0xFF43B4FF),
                          icon: Icons.account_balance_wallet_outlined,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // ── Khung biểu đồ + danh sách ──
                    Container(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
                      decoration: BoxDecoration(
                        color: const Color(0xFF131313),
                        borderRadius: BorderRadius.circular(26),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Toggle Chi tiêu / Thu nhập
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0B0B0B),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.08),
                              ),
                            ),
                            child: Row(
                              children: [
                                _ToggleBtn(
                                  label: 'Chi tiêu',
                                  icon: Icons.north_east_rounded,
                                  active: _showExpense,
                                  activeColor: const Color(0xFFFF5050),
                                  onTap: () {
                                    _showExpense = true;
                                    _recompute();
                                  },
                                ),
                                _ToggleBtn(
                                  label: 'Thu nhập',
                                  icon: Icons.south_west_rounded,
                                  active: !_showExpense,
                                  activeColor: const Color(0xFF37C95B),
                                  onTap: () {
                                    _showExpense = false;
                                    _recompute();
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 28),

                          // ── BIỂU ĐỒ TRÒN hoặc BIỂU ĐỒ CỘT ──
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child: _showBarChart
                                ? _buildBarChart()
                                : _buildPieChart(signedTotal),
                          ),
                          const SizedBox(height: 26),

                          // ── Danh sách hạng mục ──
                          Row(
                            children: [
                              Text(
                                'Hạng mục',
                                style: GoogleFonts.manrope(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          if (_categoryRows.isEmpty)
                            Text(
                              'Chưa có dữ liệu',
                              style: GoogleFonts.manrope(
                                color: Colors.white.withValues(alpha: 0.45),
                                fontSize: 14,
                              ),
                            )
                          else
                            ..._categoryRows.asMap().entries.map((entry) {
                              final i = entry.key;
                              final row = entry.value;
                              final key = row['key']?.toString() ?? 'other';
                              final label = row['label']?.toString() ?? 'Hạng mục';
                              final amount = _parseAmount(row['amount']);
                              final pct = ((row['percent'] as double) * 100).round();
                              final color = _colorForIndex(key, i);
                              final icon = _categoryIcons[key] ?? '';
                              final isTouched = i == _touchedIndex;

                              return GestureDetector(
                                onTap: () => setState(() {
                                  _touchedIndex = isTouched ? -1 : i;
                                }),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: isTouched
                                        ? color.withValues(alpha: 0.13)
                                        : Colors.white.withValues(alpha: 0.04),
                                    borderRadius: BorderRadius.circular(16),
                                    border: isTouched
                                        ? Border.all(color: color.withValues(alpha: 0.5), width: 1.5)
                                        : null,
                                  ),
                                  child: Row(
                                    children: [
                                      // Chấm màu
                                      Container(
                                        width: 12,
                                        height: 12,
                                        decoration: BoxDecoration(
                                          color: color,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      // Icon + Tên hạng mục
                                      Expanded(
                                        child: Row(
                                          children: [
                                            if (icon.isNotEmpty) ...[
                                              Text(icon,
                                                  style: const TextStyle(fontSize: 16)),
                                              const SizedBox(width: 6),
                                            ],
                                            Flexible(
                                              child: Text(
                                                label == 'other' ? 'Khác' : label,
                                                style: GoogleFonts.manrope(
                                                  color: Colors.white,
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Phần trăm
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: color.withValues(alpha: 0.18),
                                          borderRadius: BorderRadius.circular(99),
                                        ),
                                        child: Text(
                                          '$pct%',
                                          style: GoogleFonts.manrope(
                                            color: color,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      // Số tiền
                                      Text(
                                        '${_showExpense ? '-' : '+'}${_formatCompact(amount)}',
                                        style: GoogleFonts.manrope(
                                          color: Colors.white.withValues(alpha: 0.85),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildBarChart() {
    if (_barRows.isEmpty) {
      return SizedBox(
        key: const ValueKey('bar_empty'),
        height: 200,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bar_chart_rounded,
                  size: 56, color: Colors.white.withValues(alpha: 0.2)),
              const SizedBox(height: 12),
              Text(
                'Chưa có dữ liệu\ncho bộ lọc này',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final accent = _showExpense ? const Color(0xFFFF4D4D) : const Color(0xFF37C95B);
    final barWidth = _barRows.length > 15 ? 12.0 : 20.0;

    return SizedBox(
      key: const ValueKey('bar_chart'),
      height: 200,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: _barRows.map((row) {
            final ratio = (row['ratio'] as double).clamp(0.0, 1.0);
            final amount = _parseAmount(row['amount']);
            final label = row['label']?.toString() ?? '';
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    _formatCompact(amount),
                    style: GoogleFonts.manrope(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                    width: barWidth,
                    height: max(6.0, ratio * 140),
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.35),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    style: GoogleFonts.manrope(
                      color: Colors.white54,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildPieChart(int signedTotal) {
    if (_categoryRows.isEmpty) {
      return SizedBox(
        key: const ValueKey('pie_empty'),
        height: 220,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.pie_chart_outline_rounded,
                  size: 56,
                  color: Colors.white.withValues(alpha: 0.2)),
              const SizedBox(height: 12),
              Text(
                'Chưa có dữ liệu\ncho bộ lọc này',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return SizedBox(
      key: const ValueKey('pie_chart'),
      height: 250,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              pieTouchData: PieTouchData(
                touchCallback: (FlTouchEvent event, pieTouchResponse) {
                  setState(() {
                    if (!event.isInterestedForInteractions ||
                        pieTouchResponse == null ||
                        pieTouchResponse.touchedSection == null) {
                      _touchedIndex = -1;
                      return;
                    }
                    _touchedIndex = pieTouchResponse
                        .touchedSection!.touchedSectionIndex;
                  });
                },
              ),
              borderData: FlBorderData(show: false),
              sectionsSpace: 3,
              centerSpaceRadius: 68,
              sections: List.generate(_categoryRows.length, (i) {
                final row = _categoryRows[i];
                final key = row['key']?.toString() ?? '';
                final pct = ((row['percent'] as double) * 100).round();
                final isTouched = i == _touchedIndex;
                final color = _colorForIndex(key, i);
                return PieChartSectionData(
                  color: color,
                  value: (row['percent'] as double) * 100,
                  title: '$pct%',
                  radius: isTouched ? 68 : 56,
                  titleStyle: GoogleFonts.manrope(
                    fontSize: isTouched ? 15 : 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    shadows: const [
                      Shadow(color: Colors.black54, blurRadius: 4),
                    ],
                  ),
                  badgePositionPercentageOffset: 0.98,
                );
              }),
            ),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          ),
          _touchedIndex >= 0 && _touchedIndex < _categoryRows.length
              ? _buildCenterTouched(_touchedIndex)
              : _buildCenterDefault(signedTotal),
        ],
      ),
    );
  }

  Widget _buildCenterDefault(int signedTotal) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _showExpense ? 'Tổng chi' : 'Tổng thu',
          style: GoogleFonts.manrope(
            color: Colors.white.withValues(alpha: 0.65),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _formatCompact(signedTotal.abs()),
          style: GoogleFonts.manrope(
            color: _showExpense ? const Color(0xFFFF4D4D) : const Color(0xFF37C95B),
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _buildCenterTouched(int index) {
    final row = _categoryRows[index];
    final key = row['key']?.toString() ?? '';
    final label = row['label']?.toString() ?? '';
    final amount = _parseAmount(row['amount']);
    final pct = ((row['percent'] as double) * 100).round();
    final color = _colorForIndex(key, index);
    final icon = _categoryIcons[key] ?? '';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon.isNotEmpty)
          Text(icon, style: const TextStyle(fontSize: 22)),
        const SizedBox(height: 2),
        Text(
          label == 'other' ? 'Khác' : label,
          textAlign: TextAlign.center,
          style: GoogleFonts.manrope(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '$pct%',
          style: GoogleFonts.manrope(
            color: color,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          _formatCompact(amount),
          style: GoogleFonts.manrope(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ── Widget phụ ──

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.accent,
    required this.icon,
  });

  final String title;
  final String value;
  final Color accent;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF171717),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: accent, size: 18),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: GoogleFonts.manrope(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: GoogleFonts.manrope(
                color: accent,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleBtn extends StatelessWidget {
  const _ToggleBtn({
    required this.label,
    required this.icon,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: active ? activeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: active ? Colors.white : Colors.white.withValues(alpha: 0.45),
                size: 17,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: GoogleFonts.manrope(
                  color: active ? Colors.white : Colors.white.withValues(alpha: 0.45),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
