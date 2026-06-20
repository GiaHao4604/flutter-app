import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../services/calendar_api_service.dart';
import '../../services/auth_session_service.dart';


// ============================================================
// Shared helpers (dùng chung bởi budget.dart & budget_detail.dart)
// ============================================================
Color parseColor(String? colorHex, {String? fallbackKey}) {
  if (colorHex != null && colorHex.startsWith('#') && colorHex.length == 7) {
    try {
      return Color(int.parse(colorHex.substring(1), radix: 16) + 0xFF000000);
    } catch (_) {}
  }
  final key = fallbackKey ?? colorHex;
  switch (key) {
    case 'home': return const Color(0xFF4E8DFF);
    case 'food': return const Color(0xFFFFC04D);
    case 'car': return const Color(0xFF5DD6FF);
    case 'shop': return const Color(0xFFBF5AF2);
    case 'health': return const Color(0xFFFF5C8A);
    default: return const Color(0xFF8E8E93);
  }
}

Widget buildCategoryWidget(String? key, {double size = 24}) {
  if (key == null || key.isEmpty) {
    return Icon(Icons.category_outlined, size: size, color: Colors.white);
  }
  final runes = key.runes.toList();
  final isEmoji = runes.isNotEmpty && runes.first > 0xFF;
  if (isEmoji) {
    return Text(key, style: TextStyle(fontSize: size * 0.85, height: 1), textAlign: TextAlign.center);
  }
  const legacyMap = {
    'ic_food': '🍔', 'food': '🍔',
    'ic_car': '🚗', 'car': '🚗',
    'ic_shop': '🛒', 'shop': '🛒',
    'ic_health': '💊', 'health': '💊',
    'ic_bill': '💰',
    'ic_home': '🏠', 'home': '🏠',
    'ic_game': '🎮',
    'ic_flight': '✈️',
    'ic_money': '💰',
    'ic_gift': '🎁',
  };
  if (legacyMap.containsKey(key)) {
    return Text(legacyMap[key]!, style: TextStyle(fontSize: size * 0.85, height: 1, color: Colors.white), textAlign: TextAlign.center);
  }
  return Icon(Icons.category_outlined, size: size, color: Colors.white);
}

class BudgetPeriodChoice {
  const BudgetPeriodChoice({
    required this.key,
    required this.label,
    required this.rangeText,
    required this.monthKey,
    this.customRange,
  });
  final String key;
  final String label;
  final String rangeText;
  final String monthKey;
  final DateTimeRange? customRange;
}


const availableEmojis = [
  '🍔', '🚗', '💊', '🛒', '🏠', '🎮', '✈️', '💰', '🎁', '☕', 
  '👕', '🏥', '🎬', '📚', '🐶', '🔧', '⛽', '💄'
];

class SafeKeyboardPadding extends StatefulWidget {
  final Widget child;
  const SafeKeyboardPadding({super.key, required this.child});
  @override
  State<SafeKeyboardPadding> createState() => _SafeKeyboardPaddingState();
}

class _SafeKeyboardPaddingState extends State<SafeKeyboardPadding> with WidgetsBindingObserver {
  double _bottom = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updateBottom();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    _updateBottom();
  }

  void _updateBottom() {
    if (!mounted) return;
    try {
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      final bottom = view.viewInsets.bottom / view.devicePixelRatio;
      if (_bottom != bottom) {
        setState(() { _bottom = bottom; });
      }
    } catch (e) {
      // safe fallback
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: _bottom),
      child: widget.child,
    );
  }
}

class BudgetFormSheet extends StatefulWidget {
  const BudgetFormSheet({super.key, 
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
  final Future<dynamic> Function(String monthKey) pickGroup;
  final Future<BudgetPeriodChoice?> Function(
    BudgetPeriodChoice currentSelection,
  )
  pickPeriod;
  final String? initialGroupKey;
  final String? initialMonthKey;
  final int? initialAmount;
  final bool initialRepeat;
  final BudgetPeriodChoice? initialPeriod;

  @override
  State<BudgetFormSheet> createState() => BudgetFormSheetState();
}

class BudgetFormSheetState extends State<BudgetFormSheet> {
  late final TextEditingController _amountController;
  List<Map<String, String>> _groups = <Map<String, String>>[];
  String _selectedGroupKey = '';
  bool _groupTouched = false;
  bool _isFormattingAmount = false;
  BudgetPeriodChoice? _selectedPeriod;
  bool _isRepeat = false;
  bool _isLoading = true;





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
        BudgetPeriodChoice(
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
    final groupIconKey = _groupTouched && _hasSelectedGroup
        ? (currentGroup['iconKey']?.toString() ?? currentGroup['key']?.toString() ?? _selectedGroupKey)
        : null;
    final groupColor = _groupTouched && _hasSelectedGroup
        ? parseColor(_selectedGroupKey)
        : const Color(0xFF8E8E93);
    final period = _selectedPeriod!;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(
          left: 18,
          right: 18,
          top: 18,
          bottom: 18,
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
                          color: Colors.white.withValues(alpha: 0.05),
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
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: groupColor.withValues(alpha: 0.18),
                                shape: BoxShape.circle,
                              ),
                              child: buildCategoryWidget(groupIconKey, size: 22),
                            ),
                            title: Text(
                              groupLabel,
                              style: GoogleFonts.manrope(
                                color: _hasSelectedGroup
                                    ? Colors.white
                                    : Colors.white38,
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
                              final now = DateTime.now();
                              final currentMonthKey = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
                              final pickedGroupResult = await widget.pickGroup(_selectedPeriod?.monthKey ?? currentMonthKey);
                              if (pickedGroupResult == null || !context.mounted) return;
                              
                              if (pickedGroupResult is Map && pickedGroupResult['action'] == 'edit') {
                                Navigator.pop(context, pickedGroupResult);
                                return;
                              }
                              
                              final pickedGroup = pickedGroupResult as String?;
                              final groups = await widget.loadGroups();
                              if (!mounted) return;
                              setState(() {
                                _groups = groups;
                                if (pickedGroup != null) {
                                  _selectedGroupKey = pickedGroup;
                                }
                                _groupTouched = true;
                              });
                            },
                          ),
                          Divider(
                            height: 1,
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Số tiền',
                                  style: GoogleFonts.manrope(
                                    color: Colors.white54,
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
                                          color: Colors.white12,
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
                                            color: Colors.white38,
                                            fontSize: 24,
                                            fontWeight: FontWeight.w700,
                                          ),
                                          suffixText: 'đ',
                                          suffixStyle: GoogleFonts.manrope(
                                            color: Colors.white54,
                                            fontSize: 20,
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
                          final currentGroup = _groups.firstWhere(
                              (g) => g['key'] == effectiveGroupKey,
                              orElse: () => <String, String>{});
                          Navigator.of(context).pop(<String, dynamic>{
                            'groupKey': effectiveGroupKey,
                            'amount': amount,
                            'monthKey': period.monthKey,
                            'customRange': period.customRange,
                            'isRepeat': _isRepeat,
                            'iconKey': currentGroup['iconKey'],
                            'color': currentGroup['color'],
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

class BudgetEditSheet extends StatefulWidget {
  const BudgetEditSheet({super.key, 
    required this.initialName,
    required this.initialAmount,
    required this.initialPeriod,
    this.initialIconKey,
  });

  final String initialName;
  final int initialAmount;
  final DateTimeRange initialPeriod;
  final String? initialIconKey;

  @override
  State<BudgetEditSheet> createState() => BudgetEditSheetState();
}

class BudgetEditSheetState extends State<BudgetEditSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _amountController;
  late DateTimeRange _selectedPeriod;
  late String _selectedIconKey;
  bool _isSaving = false;
  bool _isFormattingAmount = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _amountController = TextEditingController(
      text: widget.initialAmount > 0
          ? NumberFormat.decimalPattern('vi_VN')
              .format(widget.initialAmount)
          : '',
    );
    _selectedPeriod = widget.initialPeriod;
    _selectedIconKey = (widget.initialIconKey != null &&
            widget.initialIconKey!.isNotEmpty &&
            widget.initialIconKey!.runes.isNotEmpty &&
            widget.initialIconKey!.runes.first > 0xFF)
        ? widget.initialIconKey!
        : availableEmojis.first;
    _amountController.addListener(_formatAmountValue);
  }

  @override
  void dispose() {
    _amountController.removeListener(_formatAmountValue);
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _formatAmountValue() {
    if (_isFormattingAmount) return;
    final digits = _amountController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final formatted = digits.isEmpty
        ? ''
        : NumberFormat.decimalPattern('vi_VN').format(int.parse(digits));
    if (_amountController.text == formatted) return;

    _isFormattingAmount = true;
    _amountController.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
    _isFormattingAmount = false;
  }

  Future<void> _pickPeriod() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(DateTime.now().year - 3, 1, 1),
      lastDate: DateTime(DateTime.now().year + 3, 12, 31),
      initialDateRange: _selectedPeriod,
      helpText: 'Chọn thời gian',
      saveText: 'Chọn',
      cancelText: 'Huỷ',
    );
    if (picked == null) return;
    if (!mounted) return;
    setState(() {
      _selectedPeriod = picked;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 0,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(
            left: 18,
            right: 18,
            top: 18,
            bottom: 18,
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
                // Removed old Row icon picker here. It will be put inside TextField prefixIcon instead.
                TextField(
                  controller: _nameController,
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
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(left: 12, right: 12, top: 8, bottom: 8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(23),
                        onTap: () async {
                          final result = await showModalBottomSheet<Map<String, dynamic>>(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (ctx) => EmojiPickerSheet(
                              initialIconKey: _selectedIconKey,
                            ),
                          );
                          if (result != null && result['iconKey'] != null) {
                            setState(() {
                              _selectedIconKey = result['iconKey'].toString();
                            });
                          }
                        },
                        child: Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: Colors.white10,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            _selectedIconKey,
                            style: const TextStyle(fontSize: 22),
                          ),
                        ),
                      ),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _amountController,
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
                  onTap: _pickPeriod,
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
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Thời gian',
                                style: GoogleFonts.manrope(
                                  color: Colors.white.withValues(alpha: 0.55),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_selectedPeriod.start.day.toString().padLeft(2, '0')}/${_selectedPeriod.start.month.toString().padLeft(2, '0')} - ${_selectedPeriod.end.day.toString().padLeft(2, '0')}/${_selectedPeriod.end.month.toString().padLeft(2, '0')}',
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
                    onPressed: _isSaving
                        ? null
                        : () {
                            final name = _nameController.text.trim();
                            final amount = int.tryParse(
                                  _amountController.text.replaceAll(
                                    RegExp(r'[^0-9]'),
                                    '',
                                  ),
                                ) ??
                                0;
                            if (name.isEmpty || amount <= 0) return;
                            setState(() => _isSaving = true);
                            Navigator.of(context).pop(<String, dynamic>{
                              'name': name,
                              'amount': amount,
                              'period': _selectedPeriod,
                              'iconKey': _selectedIconKey,
                            });
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2DBC4D),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    child: Text(
                      _isSaving ? 'Đang lưu...' : 'Lưu thay đổi',
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
      ),
    );
  }
}

class MiniMetric extends StatelessWidget {
  const MiniMetric({super.key, required this.value, required this.label});

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

class HalfArcPainter extends CustomPainter {
  HalfArcPainter({
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
  bool shouldRepaint(covariant HalfArcPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}

class KindChoiceButton extends StatelessWidget {
  const KindChoiceButton({super.key, 
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

class EmojiPickerSheet extends StatefulWidget {
  final String? initialIconKey;
  final String? initialColorHex;

  const EmojiPickerSheet({super.key, 
    this.initialIconKey,
    this.initialColorHex,
  });

  @override
  State<EmojiPickerSheet> createState() => EmojiPickerSheetState();
}

class EmojiPickerSheetState extends State<EmojiPickerSheet> {
  late String _selectedIconKey;

  @override
  void initState() {
    super.initState();
    _selectedIconKey = widget.initialIconKey ?? availableEmojis.first;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 24, bottom: 32),
      decoration: const BoxDecoration(
        color: Color(0xFF141414),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Chọn Biểu tượng',
            style: GoogleFonts.manrope(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 24),
          
          // Preview
          Container(
            width: 80,
            height: 80,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF8E8E93).withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: buildCategoryWidget(_selectedIconKey, size: 40),
          ),
          const SizedBox(height: 24),


          
          // Emoji Grid
          SizedBox(
            height: 200,
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
              ),
              itemCount: availableEmojis.length,
              itemBuilder: (context, index) {
                final emoji = availableEmojis[index];
                final isSelected = _selectedIconKey == emoji;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedIconKey = emoji;
                    });
                  },
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.white.withValues(alpha: 0.15) : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      emoji,
                      style: const TextStyle(fontSize: 28, height: 1),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 32),
          
          // Done Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: FilledButton(
              onPressed: () {
                Navigator.of(context).pop({
                  'iconKey': _selectedIconKey,
                  'color': '#8E8E93', // Luôn trả về màu xám để Thống kê tự động đổi màu
                });
              },
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                backgroundColor: const Color(0xFF2ECC71),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                'Lưu',
                style: GoogleFonts.manrope(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BudgetTransactionGallerySheet extends StatefulWidget {
  final String budgetKey;
  final String budgetName;
  final String monthKey;

  const BudgetTransactionGallerySheet({
    super.key,
    required this.budgetKey,
    required this.budgetName,
    required this.monthKey,
  });

  @override
  State<BudgetTransactionGallerySheet> createState() => BudgetTransactionGallerySheetState();
}

class BudgetTransactionGallerySheetState extends State<BudgetTransactionGallerySheet> {
  final CalendarApiService _apiService = CalendarApiService();
  List<Map<String, dynamic>> _posts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final token = await AuthSessionService().getToken();
    if (token == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final parts = widget.monthKey.split('-');
    final year = int.tryParse(parts[0]) ?? DateTime.now().year;
    final month = int.tryParse(parts.length > 1 ? parts[1] : '') ?? DateTime.now().month;
    final targetMonth = DateTime(year, month, 1);

    try {
      final remote = await _apiService.getMonth(token: token, month: targetMonth);
      if (remote.success && remote.data != null && remote.data is Map<String, dynamic>) {
        final server = Map<String, dynamic>.from(remote.data!);
        final entries = (server['entries'] is List) ? List.from(server['entries']) : null;
        if (entries != null) {
          final List<Map<String, dynamic>> loaded = [];
          for (final e in entries) {
            if (e is Map) {
              final m = Map<String, dynamic>.from(e);
              final categoryKey = m['categoryKey']?.toString() ?? m['slug']?.toString();
              if (categoryKey == widget.budgetKey) {
                final imagePath = m['imageUrl'] ?? m['image_url'] ?? m['imagePath'];
                if (imagePath != null && imagePath.toString().trim().isNotEmpty) {
                  loaded.add({
                    'id': m['id']?.toString(),
                    'imageUrl': imagePath,
                    'amount': m['amount'],
                    'isExpense': m['isExpense'] ?? true,
                    'note': m['note']?.toString(),
                    'entryTs': m['entryTs']?.toString(),
                    'date': m['date']?.toString(),
                    'categoryLabel': widget.budgetName,
                  });
                }
              }
            }
          }
          if (mounted) {
            setState(() {
              _posts = loaded;
              _isLoading = false;
            });
          }
          return;
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() => _isLoading = false);
    }
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
    final path = post['imageUrl']?.toString().trim();
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
                                    widget.budgetName,
                                    style: GoogleFonts.manrope(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    '${selectedIndex + 1}/${_posts.length}',
                                    style: GoogleFonts.manrope(
                                      color: const Color(0xFFCFC8C3),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 48), // balance header
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: Center(
                            child: PageView.builder(
                              controller: pageController,
                              itemCount: _posts.length,
                              onPageChanged: (index) => setState(() {
                                selectedIndex = index;
                              }),
                              itemBuilder: (context, index) {
                                final post = _posts[index];
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
                                            widget.budgetName,
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
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF131313),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 48,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Ảnh giao dịch',
              style: GoogleFonts.manrope(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.budgetName,
              style: GoogleFonts.manrope(
                color: Colors.white54,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF2ECC71)))
                  : _posts.isEmpty
                      ? Center(
                          child: Text(
                            'Chưa có ảnh nào.',
                            style: GoogleFonts.manrope(color: Colors.white54, fontSize: 16),
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                            childAspectRatio: 1.0,
                          ),
                          itemCount: _posts.length,
                          itemBuilder: (context, index) {
                            final post = _posts[index];
                            final prov = _resizedImageProviderForPost(context, post, 300);
                            return GestureDetector(
                              onTap: () => _openGalleryPreview(context, index),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  color: const Color(0xFF2C2C2E),
                                  child: prov != null
                                      ? Image(image: prov, fit: BoxFit.cover)
                                      : const Icon(Icons.image, color: Colors.white24),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class CreateGroupSheet extends StatefulWidget {
  final List<String> availableEmojis;
  final String Function(String) slugify;

  const CreateGroupSheet({super.key, 
    required this.availableEmojis,
    required this.slugify,
  });

  @override
  State<CreateGroupSheet> createState() => CreateGroupSheetState();
}

class CreateGroupSheetState extends State<CreateGroupSheet> {
  final TextEditingController _nameController = TextEditingController();
  String _selectedKind = 'expense';
  late String _selectedIconKey;

  @override
  void initState() {
    super.initState();
    _selectedIconKey = widget.availableEmojis.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final key = widget.slugify(name);
    FocusManager.instance.primaryFocus?.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pop(<String, String>{
        'key': key,
        'label': name,
        'kind': _selectedKind,
        'iconKey': _selectedIconKey,
        'color': '#8E8E93',
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final keyboardBottom = WidgetsBinding.instance.platformDispatcher.views.first.viewInsets.bottom /
        WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;

    return Container(
      padding: EdgeInsets.only(
        top: 12,
        bottom: keyboardBottom + 24,
        left: 24,
        right: 24,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF141414),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Title
            Text(
              'Tạo hạng mục mới',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 32),
            // Icon & Name row
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () async {
                    final result = await showModalBottomSheet<Map<String, dynamic>>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (ctx) => EmojiPickerSheet(
                        initialIconKey: _selectedIconKey,
                      ),
                    );
                    if (!mounted) return;
                    if (result != null && result['iconKey'] != null) {
                      setState(() {
                        _selectedIconKey = result['iconKey'].toString();
                      });
                    }
                  },
                  child: Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF242426),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Text(
                      _selectedIconKey,
                      style: const TextStyle(fontSize: 32, height: 1),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Container(
                    height: 64,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1E),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Center(
                      child: TextField(
                        controller: _nameController,
                        autofocus: false,
                        style: GoogleFonts.manrope(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Nhập tên hạng mục',
                          hintStyle: GoogleFonts.manrope(
                            color: Colors.white.withValues(alpha: 0.3),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          border: InputBorder.none,
                          isCollapsed: true,
                        ),
                        onSubmitted: (_) => _save(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Kind label
            Text(
              'Loại ngân sách',
              style: GoogleFonts.manrope(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            // Kind selector
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedKind = 'expense'),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: _selectedKind == 'expense'
                            ? const Color(0xFFFF4D4D).withValues(alpha: 0.15)
                            : const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _selectedKind == 'expense'
                              ? const Color(0xFFFF4D4D)
                              : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        'Khoản chi',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.manrope(
                          color: _selectedKind == 'expense'
                              ? const Color(0xFFFF4D4D)
                              : Colors.white54,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedKind = 'income'),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: _selectedKind == 'income'
                            ? const Color(0xFF2ECC71).withValues(alpha: 0.15)
                            : const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _selectedKind == 'income'
                              ? const Color(0xFF2ECC71)
                              : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        'Khoản thu',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.manrope(
                          color: _selectedKind == 'income'
                              ? const Color(0xFF2ECC71)
                              : Colors.white54,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            // Save button
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF37C95B),
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                'Lưu hạng mục',
                style: GoogleFonts.manrope(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
