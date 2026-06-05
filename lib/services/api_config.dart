import 'package:flutter/foundation.dart';

/// Cấu hình API tập trung cho toàn app.
/// Tất cả các service nên dùng class này thay vì hardcode IP riêng lẻ.
class ApiConfig {
  ApiConfig._();

  // ============================================================
  // Cấu hình địa chỉ server
  // Thay đổi IP này khi chạy trên mạng LAN khác
  // ============================================================
  static const String _lanIp = '192.168.1.240';
  static const int _port = 3000;

  /// URL gốc của server (không có /api/...)
  static String get baseOrigin {
    const envUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    if (envUrl.isNotEmpty) {
      // Lấy origin từ env URL: vd "http://host:3000/api/auth" -> "http://host:3000"
      final uri = Uri.tryParse(envUrl);
      if (uri != null) {
        final portPart = uri.hasPort ? ':${uri.port}' : '';
        return '${uri.scheme}://${uri.host}$portPart';
      }
      return envUrl;
    }

    if (kIsWeb) return 'http://localhost:$_port';

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'http://$_lanIp:$_port';
      case TargetPlatform.iOS:
        return 'http://$_lanIp:$_port';
      default:
        return 'http://localhost:$_port';
    }
  }

  /// URL gốc của emulator Android (10.0.2.2 maps về localhost của máy dev)
  static String get androidEmulatorOrigin => 'http://10.0.2.2:$_port';

  /// URL gốc LAN
  static String get lanOrigin => 'http://$_lanIp:$_port';

  // ============================================================
  // Các base URL theo từng module
  // ============================================================
  static String apiUrl(String module) => '$baseOrigin/api/$module';
  static String lanApiUrl(String module) => '$lanOrigin/api/$module';
  static String emulatorApiUrl(String module) => '$androidEmulatorOrigin/api/$module';

  // Shorthand cho từng module
  static String get authBaseUrl => apiUrl('auth');
  static String get chatBaseUrl => apiUrl('chat');
  static String get financeBaseUrl => apiUrl('finance');
  static String get calendarBaseUrl => apiUrl('calendar');
  static String get profileBaseUrl => apiUrl('profile');
  static String get postsBaseUrl => apiUrl('posts');
  static String get cameraBaseUrl => apiUrl('camera');
}
