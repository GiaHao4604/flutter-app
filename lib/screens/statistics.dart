import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/services/auth_session_service.dart';
import 'package:flutter_application_1/services/finance_api_service.dart';
import 'package:flutter_application_1/services/calendar_storage_service.dart';

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  final AuthSessionService _sessionService = AuthSessionService();
  final FinanceApiService _financeApiService = FinanceApiService();
  final CalendarStorageService _storageService = CalendarStorageService();

  final List<String> _tabs = const ['Tuần', 'Tháng', 'Năm', 'Tất cả'];
  int _selectedTab = 3;
  bool _showExpense = true;

  bool _isLoading = true;
  int _totalExpense = 0;
  int _totalIncome = 0;
  List<Map<String, dynamic>> _allRecords = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _categoryRows = <Map<String, dynamic>>[];

  String _currentMonthKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    // Server records (từ finance API) - nguồn tin cậy chính
    final serverRecords = <Map<String, dynamic>>[];
    // Local-only records (chưa sync lên server)
    final localOnlyRecords = <Map<String, dynamic>>[];

    final token = await _sessionService.getToken();
    if (token != null && token.isNotEmpty) {
      final remote = await _financeApiService.getSummary(
        token: token,
        monthKey: _currentMonthKey(),
      );

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

    // Lấy IDs đã có trên server để tránh cộng đôi local records
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
              // Bỏ qua local record nếu đã có trên server (tránh cộng đôi)
              if (id.isNotEmpty && serverIds.contains(id)) continue;
              localOnlyRecords.add(record);
            }
          }
        }
      } catch (_) {}
    }

    // Gộp: server records + local records chưa sync
    final allRecords = [...serverRecords, ...localOnlyRecords];

    // Dedup lần cuối theo key tổng hợp (phòng hờ)
    final dedup = <String, Map<String, dynamic>>{};
    for (final record in allRecords) {
      final key = [
        record['id']?.toString() ?? '',
        record['dateKey']?.toString() ?? '',
        record['amount']?.toString() ?? '0',
        record['isExpense'] == true ? '1' : '0',
        record['categoryKey']?.toString() ?? '',
      ].join('|');
      dedup[key] = record;
    }
    final mergedRecords = dedup.values.toList();

    final stats = _computeStats(mergedRecords);

    if (!mounted) return;
    setState(() {
      _allRecords = mergedRecords;
      _totalExpense = stats['totalExpense'] as int;
      _totalIncome = stats['totalIncome'] as int;
      _categoryRows = List<Map<String, dynamic>>.from(
        stats['categoryRows'] as List,
      );
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

    final key =
        raw['categoryKey']?.toString() ??
        raw['category_key']?.toString() ??
        categoryMap['key']?.toString() ??
        'other';

    final label =
        raw['categoryLabel']?.toString() ??
        raw['category_label']?.toString() ??
        categoryMap['label']?.toString() ??
        categoryMap['name']?.toString() ??
        key;

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
      'categoryKey': key,
      'categoryLabel': key == 'other' ? 'Khác' : label,
      'date': parsedDate,
      'dateKey': parsedDate != null
          ? '${parsedDate.year.toString().padLeft(4, '0')}-${parsedDate.month.toString().padLeft(2, '0')}-${parsedDate.day.toString().padLeft(2, '0')}'
          : isoDate,
    };
  }

  bool _matchesSelectedTab(DateTime date) {
    final now = DateTime.now();
    final localDate = date.toLocal();

    if (_selectedTab == 0) {
      final start = now.subtract(Duration(days: now.weekday - 1));
      final startDay = DateTime(start.year, start.month, start.day);
      final endDay = startDay.add(const Duration(days: 7));
      final checkDay = DateTime(localDate.year, localDate.month, localDate.day);
      return !checkDay.isBefore(startDay) && checkDay.isBefore(endDay);
    }

    if (_selectedTab == 1) {
      return localDate.year == now.year && localDate.month == now.month;
    }

    if (_selectedTab == 2) {
      return localDate.year == now.year;
    }

    return true;
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
    return '${negative ? '-' : ''}$formattedđ';
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

  Color _categoryColor(String key) {
    if (key == 'other') {
      return const Color(0xFF9A9A9A);
    }
    return _showExpense ? const Color(0xFFFF4D4D) : const Color(0xFF37C95B);
  }

  int get _selectedNetTotal => _totalIncome - _totalExpense;

  double get _donutValue {
    final base = _totalExpense + _totalIncome;
    final total = _showExpense ? _totalExpense : _totalIncome;
    if (base <= 0 || total <= 0) return 0;
    return min(1.0, total / base);
  }

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
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
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
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(_tabs.length, (index) {
                        final selected = index == _selectedTab;
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedTab = index;
                                  final stats = _computeStats(_allRecords);
                                  _totalExpense = stats['totalExpense'] as int;
                                  _totalIncome = stats['totalIncome'] as int;
                                  _categoryRows = List<Map<String, dynamic>>.from(
                                    stats['categoryRows'] as List,
                                  );
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? const Color(0xFF1E1E1E)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(22),
                                ),
                                child: Center(
                                  child: Text(
                                    _tabs[index],
                                    style: GoogleFonts.manrope(
                                      color: selected
                                          ? Colors.white
                                          : Colors.white.withValues(
                                              alpha: 0.25,
                                            ),
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 26),
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
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF131313),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        children: [
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
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () =>
                                        setState(() {
                                          _showExpense = true;
                                          final stats = _computeStats(_allRecords);
                                          _totalExpense = stats['totalExpense'] as int;
                                          _totalIncome = stats['totalIncome'] as int;
                                          _categoryRows = List<Map<String, dynamic>>.from(
                                            stats['categoryRows'] as List,
                                          );
                                        }),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _showExpense
                                            ? const Color(0xFFFF5050)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.north_east_rounded,
                                            color: _showExpense
                                                ? Colors.white
                                                : Colors.white.withValues(
                                                    alpha: 0.55,
                                                  ),
                                            size: 18,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Chi tiêu',
                                            style: GoogleFonts.manrope(
                                              color: _showExpense
                                                  ? Colors.white
                                                  : Colors.white.withValues(
                                                      alpha: 0.55,
                                                    ),
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () =>
                                        setState(() {
                                          _showExpense = false;
                                          final stats = _computeStats(_allRecords);
                                          _totalExpense = stats['totalExpense'] as int;
                                          _totalIncome = stats['totalIncome'] as int;
                                          _categoryRows = List<Map<String, dynamic>>.from(
                                            stats['categoryRows'] as List,
                                          );
                                        }),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      decoration: BoxDecoration(
                                        color: !_showExpense
                                            ? const Color(0xFF262626)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.south_west_rounded,
                                            color: !_showExpense
                                                ? Colors.white
                                                : Colors.white.withValues(
                                                    alpha: 0.55,
                                                  ),
                                            size: 18,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Thu nhập',
                                            style: GoogleFonts.manrope(
                                              color: !_showExpense
                                                  ? Colors.white
                                                  : Colors.white.withValues(
                                                      alpha: 0.55,
                                                    ),
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
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
                          const SizedBox(height: 28),
                          SizedBox(
                            width: 250,
                            height: 250,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                SizedBox(
                                  width: 250,
                                  height: 250,
                                  child: CircularProgressIndicator(
                                    value: _donutValue,
                                    strokeWidth: 28,
                                    backgroundColor: const Color(0xFFB7B7B7),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      _showExpense
                                          ? const Color(0xFFFF4D4D)
                                          : const Color(0xFF37C95B),
                                    ),
                                  ),
                                ),
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _showExpense
                                          ? 'Tổng chi tiêu:'
                                          : 'Tổng thu nhập:',
                                      style: GoogleFonts.manrope(
                                        color: Colors.white.withValues(
                                          alpha: 0.85,
                                        ),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _formatCompact(signedTotal),
                                      style: GoogleFonts.manrope(
                                        color: _showExpense
                                            ? const Color(0xFFFF4D4D)
                                            : const Color(0xFF37C95B),
                                        fontSize: 24,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 28),
                          Row(
                            children: [
                              Text(
                                'Hạng mục nổi bật',
                                style: GoogleFonts.manrope(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          if (_categoryRows.isEmpty)
                            Text(
                              'Chưa có dữ liệu cho bộ lọc này',
                              style: GoogleFonts.manrope(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          else
                            ..._categoryRows.take(5).map((row) {
                              final amount = _parseAmount(row['amount']);
                              final percent = ((row['percent'] as double) * 100).round();
                              final categoryKey = row['key']?.toString() ?? 'other';
                              final categoryLabel = row['label']?.toString() ?? 'Hạng mục';
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: _categoryColor(categoryKey),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        categoryLabel == 'other' ? 'Khác' : categoryLabel,
                                        style: GoogleFonts.manrope(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '$percent%',
                                      style: GoogleFonts.manrope(
                                        color: Colors.white.withValues(alpha: 0.65),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
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
}

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
            const SizedBox(height: 12),
            Text(
              title,
              style: GoogleFonts.manrope(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
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
