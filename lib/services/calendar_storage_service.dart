import 'package:shared_preferences/shared_preferences.dart';

class CalendarStorageService {
  static const String _calendarPrefix = 'calendar_posts';
  static const String _anonymousSuffix = 'anonymous';

  Future<String> currentCalendarKey() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('current_user_email')?.trim().toLowerCase();
    if (email == null || email.isEmpty) {
      return '${_calendarPrefix}__$_anonymousSuffix';
    }

    return '${_calendarPrefix}__${_sanitize(email)}';
  }

  String _sanitize(String value) {
    final buffer = StringBuffer();
    var previousUnderscore = false;

    for (final codeUnit in value.codeUnits) {
      final char = String.fromCharCode(codeUnit);
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
    return sanitized.isEmpty ? _anonymousSuffix : sanitized;
  }
}