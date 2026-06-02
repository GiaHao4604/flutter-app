import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class BudgetStorageService {
  static const String _budgetPrefix = 'budget_items';
  static const String _monthBudgetPrefix = 'monthly_budget';

  Future<String> currentBudgetItemsKey() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('current_user_email')?.trim().toLowerCase();
    final accountKey = _accountKey(email);
    return '${_budgetPrefix}__${_sanitize(accountKey)}';
  }

  Future<String> currentMonthlyBudgetKey() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('current_user_email')?.trim().toLowerCase();
    final accountKey = _accountKey(email);
    return '${_monthBudgetPrefix}__${_sanitize(accountKey)}';
  }

  Future<int> readMonthlyBudget() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await currentMonthlyBudgetKey();
    return prefs.getInt(key) ?? 0;
  }

  Future<void> saveMonthlyBudget(int amount) async {
    final prefs = await SharedPreferences.getInstance();
    final key = await currentMonthlyBudgetKey();
    await prefs.setInt(key, amount);
  }

  Future<List<Map<String, dynamic>>> readBudgetItems() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await currentBudgetItemsKey();
    final raw = prefs.getString(key);
    final items = <Map<String, dynamic>>[];

    if (raw == null || raw.isEmpty) {
      return items;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final item in decoded) {
          if (item is Map) {
            items.add(Map<String, dynamic>.from(item));
          }
        }
      }
    } catch (_) {}

    return items;
  }

  Future<void> saveBudgetItems(List<Map<String, dynamic>> items) async {
    final prefs = await SharedPreferences.getInstance();
    final key = await currentBudgetItemsKey();
    await prefs.setString(key, jsonEncode(items));
  }

  String _accountKey(String? email) {
    if (email == null || email.isEmpty) return 'anonymous';
    return email;
  }

  String _sanitize(String value) {
    final buffer = StringBuffer();
    var previousUnderscore = false;

    for (final codeUnit in value.codeUnits) {
      final char = String.fromCharCode(codeUnit).toLowerCase();
      final isAllowed = RegExp(r'[a-z0-9]').hasMatch(char);
      if (isAllowed) {
        buffer.write(char);
        previousUnderscore = false;
        continue;
      }

      if (!previousUnderscore) {
        buffer.write('_');
        previousUnderscore = true;
      }
    }

    final sanitized = buffer.toString().replaceAll(RegExp(r'^_+|_+$'), '');
    return sanitized.isEmpty ? 'anonymous' : sanitized;
  }

  // Groups persistence for budget categories
  static const String _groupsPrefix = 'budget_groups';

  Future<String> _currentGroupsKey() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('current_user_email')?.trim().toLowerCase();
    final accountKey = _accountKey(email);
    return '${_groupsPrefix}__${_sanitize(accountKey)}';
  }

  Future<List<Map<String, String>>> readBudgetGroups() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _currentGroupsKey();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<Map>().map((m) {
          return m.map((k, v) => MapEntry(k.toString(), v.toString()));
        }).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> saveBudgetGroups(List<Map<String, String>> groups) async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _currentGroupsKey();
    await prefs.setString(key, jsonEncode(groups));
  }
}