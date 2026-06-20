import 'budget_detail.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/finance_api_service.dart';
import '../services/auth_session_service.dart';

class BudgetHistoryScreen extends StatefulWidget {
  const BudgetHistoryScreen({super.key});

  @override
  State<BudgetHistoryScreen> createState() => _BudgetHistoryScreenState();
}

class _BudgetHistoryScreenState extends State<BudgetHistoryScreen> {
  final _financeApiService = FinanceApiService();
  final _sessionService = AuthSessionService();
  bool _isLoading = true;
  List<Map<String, dynamic>> _historyItems = [];

  final List<String> _tabs = const ['Tuần', 'Tháng', 'Năm/Khác'];
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    try {
      final token = await _sessionService.getToken();
      if (token != null && token.isNotEmpty) {
        final result = await _financeApiService.getHistoryBudgets(token: token);
        if (result.success && result.data != null) {
          setState(() {
            _historyItems = List<Map<String, dynamic>>.from(result.data?['data'] ?? []);
          });
        }
      }
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int _parseAmount(dynamic val) {
    if (val == null) return 0;
    if (val is int) return val;
    if (val is double) return val.toInt();
    return int.tryParse(val.toString()) ?? 0;
  }

  String _formatCompact(int amount) {
    if (amount >= 1000000) {
      final m = amount / 1000000;
      return '${m == m.toInt() ? m.toInt() : m.toStringAsFixed(1)}tr';
    } else if (amount >= 1000) {
      final k = amount / 1000;
      return '${k == k.toInt() ? k.toInt() : k.toStringAsFixed(1)}k';
    }
    return '$amountđ';
  }

  Color _iconColorForKey(String? iconKey) {
    return const Color(0xFF8E8E93);
  }

  Widget _buildCategoryWidget(String? key, {double size = 24}) {
    if (key == null || key.isEmpty) {
      return Icon(Icons.category_outlined, size: size, color: Colors.white);
    }
    
    final runes = key.runes.toList();
    if (runes.length <= 3 && key != 'car' && key != 'home' && key != 'food' && key != 'shop') {
      return Text(
        key,
        style: TextStyle(fontSize: size * 0.85, height: 1, color: Colors.white),
        textAlign: TextAlign.center,
      );
    }

    final legacyMap = {
      'ic_food': '🍔', 'food': '🍔', 'dining': '🍔',
      'ic_car': '🚗', 'car': '🚗', 'transport': '🚗',
      'ic_shop': '🛒', 'shop': '🛒', 'shopping': '🛒',
      'ic_health': '💊', 'health': '💊',
      'ic_bill': '💰', 'bill': '💰',
      'ic_home': '🏠', 'home': '🏠',
      'ic_game': '🎮', 'entertainment': '🎮',
      'ic_flight': '✈️',
      'ic_money': '💰', 'salary': '💰', 'investment': '💰',
      'ic_gift': '🎁', 'gift': '🎁',
      'education': '📚',
    };

    if (legacyMap.containsKey(key)) {
      return Text(
        legacyMap[key]!,
        style: TextStyle(fontSize: size * 0.85, height: 1, color: Colors.white),
        textAlign: TextAlign.center,
      );
    }

    return Icon(Icons.category_outlined, size: size, color: Colors.white);
  }

  String _buildDurationText(Map<String, dynamic> item) {
    try {
      final startStr = item['startDate'];
      final endStr = item['endDate'];
      DateTime? start;
      DateTime? end;
      if (startStr != null && endStr != null) {
        start = DateTime.parse(startStr).toLocal();
        end = DateTime.parse(endStr).toLocal();
      } else if (item['monthKey'] != null) {
        final mk = item['monthKey'].toString();
        final parts = mk.split('-');
        if (parts.length == 2) {
          final year = int.tryParse(parts[0]) ?? DateTime.now().year;
          final month = int.tryParse(parts[1]) ?? DateTime.now().month;
          start = DateTime(year, month, 1);
          end = DateTime(year, month + 1, 0, 23, 59, 59);
        }
      }
      if (start == null || end == null) return '';
      final s = '${start.day.toString().padLeft(2, '0')}/${start.month.toString().padLeft(2, '0')}';
      final e = '${end.day.toString().padLeft(2, '0')}/${end.month.toString().padLeft(2, '0')}';
      return '$s - $e';
    } catch (_) {
      return '';
    }
  }

  String _getGroupTitle(Map<String, dynamic> item) {
    try {
      final startStr = item['startDate'];
      final endStr = item['endDate'];
      DateTime? start;
      DateTime? end;
      if (startStr != null && endStr != null) {
        start = DateTime.parse(startStr).toLocal();
        end = DateTime.parse(endStr).toLocal();
      } else if (item['monthKey'] != null) {
        final mk = item['monthKey'].toString();
        final parts = mk.split('-');
        if (parts.length == 2) {
          final year = int.tryParse(parts[0]) ?? DateTime.now().year;
          final month = int.tryParse(parts[1]) ?? DateTime.now().month;
          start = DateTime(year, month, 1);
          end = DateTime(year, month + 1, 0, 23, 59, 59);
        }
      }
      
      if (start == null || end == null) return 'Khác';

      final itemTotalDays = end.difference(start).inDays + 1;
      final year = end.year.toString();

      if (itemTotalDays <= 7) return 'Tuần - $year';
      if (itemTotalDays >= 28 && itemTotalDays <= 31) return 'Tháng - $year';
      if (itemTotalDays >= 365) return 'Năm - $year';
      return 'Tùy chỉnh - $year';
    } catch (_) {
      return 'Khác';
    }
  }

  List<Widget> _buildGroupedList() {
    if (_historyItems.isEmpty) {
      return [
        const SizedBox(height: 20),
        Center(
          child: Text(
            'Chưa có dữ liệu lịch sử',
            style: GoogleFonts.manrope(
              color: Colors.white.withOpacity(0.5),
              fontSize: 14,
            ),
          ),
        ),
      ];
    }

    final groups = <String, List<Map<String, dynamic>>>{};
    for (final item in _historyItems) {
      final title = _getGroupTitle(item);
      bool shouldInclude = false;
      if (_selectedTab == 0 && title.contains('Tuần')) shouldInclude = true;
      if (_selectedTab == 1 && title.contains('Tháng')) shouldInclude = true;
      if (_selectedTab == 2 && (title.contains('Năm') || title.contains('Tùy chỉnh') || title.contains('Khác'))) shouldInclude = true;
      
      if (shouldInclude) {
        groups.putIfAbsent(title, () => []).add(item);
      }
    }

    if (groups.isEmpty) {
      return [
        const SizedBox(height: 20),
        Center(
          child: Text(
            'Không có dữ liệu',
            style: GoogleFonts.manrope(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 14,
            ),
          ),
        ),
      ];
    }

    final widgets = <Widget>[];
    for (final entry in groups.entries) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            children: [
              Icon(
                entry.key.contains('Tuần')
                    ? Icons.view_week
                    : entry.key.contains('Tháng')
                        ? Icons.calendar_today
                        : entry.key.contains('Năm')
                            ? Icons.calendar_month
                            : Icons.dashboard_customize,
                color: Colors.white.withValues(alpha: 0.5),
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                entry.key,
                style: GoogleFonts.manrope(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );

      for (final item in entry.value) {
        widgets.add(_buildItem(item));
      }
    }

    return widgets;
  }

  Future<void> _confirmDeleteBudget(Map<String, dynamic> item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141414),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Xóa ngân sách?',
          style: GoogleFonts.manrope(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Bạn có chắc chắn muốn xóa ngân sách này khỏi lịch sử không?',
          style: GoogleFonts.manrope(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Hủy', style: GoogleFonts.manrope(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Xóa', style: GoogleFonts.manrope(color: const Color(0xFFFF4D4D), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final token = await _sessionService.getToken();
      if (token != null && token.isNotEmpty) {
        final result = await _financeApiService.deleteBudget(
          token: token,
          budgetId: _parseAmount(item['id']),
        );
        if (result.success) {
          await _loadHistory();
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Lỗi: ${result.message}')),
            );
            setState(() => _isLoading = false);
          }
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmReuseBudget(Map<String, dynamic> item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141414),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Tái sử dụng ngân sách?',
          style: GoogleFonts.manrope(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Khi tái sử dụng, hệ thống sẽ thiết lập lại một ngân sách hoàn toàn mới. Bạn có đồng ý không?',
          style: GoogleFonts.manrope(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Hủy', style: GoogleFonts.manrope(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Đồng ý', style: GoogleFonts.manrope(color: const Color(0xFF2DBC4D), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (mounted) {
        Navigator.of(context).pop({'action': 'reuse', 'item': item});
      }
    }
  }

  Widget _buildItem(Map<String, dynamic> item) {
    final limit = _parseAmount(item['limitAmount']);
    final spent = _parseAmount(item['spentAmount'] ?? 0);
    final remainingItem = limit - spent;
    final ratio = limit <= 0 ? 0.0 : spent / limit;
    final progress = ratio.clamp(0.0, 1.0);

    final isOverBudget = limit > 0 && spent >= limit;
    final iconKey = item['iconKey']?.toString() ?? item['category']?['iconKey']?.toString();
    final iconColor = _iconColorForKey(iconKey);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () {
          final categoryKey = (item['categoryKey'] ?? item['category']?['slug'] ?? item['key'])?.toString() ?? '';
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => BudgetDetailScreen(item: item, categoryKey: categoryKey),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF131313),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFFF4D4D), width: 1.2),
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
                    color: iconColor.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: _buildCategoryWidget(iconKey, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    item['name']?.toString() ?? 'Hạng mục',
                    style: GoogleFonts.manrope(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
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
                            : Colors.white.withOpacity(0.55),
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
                  isOverBudget ? const Color(0xFFFF4D4D) : iconColor,
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
                          color: Colors.white.withOpacity(0.45),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _buildDurationText(item),
                        style: GoogleFonts.manrope(
                          color: Colors.white.withOpacity(0.35),
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
                IconButton(
                  onPressed: () => _confirmDeleteBudget(item),
                  icon: const Icon(Icons.delete_outline, size: 20, color: Color(0xFFFF4D4D)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: () => _confirmReuseBudget(item),
                  icon: const Icon(Icons.refresh, size: 16, color: Color(0xFF2DBC4D)),
                  label: Text(
                    'Tái sử dụng',
                    style: GoogleFonts.manrope(
                      color: const Color(0xFF2DBC4D),
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    backgroundColor: const Color(0xFF2DBC4D).withOpacity(0.15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildTabButtons() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
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
                setState(() {
                  _selectedTab = index;
                });
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Lịch sử ngân sách',
          style: GoogleFonts.manrope(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
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
                    _buildTabButtons(),
                    ..._buildGroupedList(),
                  ],
                ),
              ),
            ),
    );
  }
}
