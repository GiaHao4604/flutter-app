import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/notification_model.dart';
import 'api_config.dart';
import 'auth_session_service.dart';

class NotificationApiResult<T> {
  final bool success;
  final String? message;
  final T? data;

  NotificationApiResult({
    required this.success,
    this.message,
    this.data,
  });
}

class NotificationApiService {
  static Future<NotificationApiResult<List<NotificationModel>>> getNotifications() async {
    try {
      final token = await AuthSessionService().getToken();
      if (token == null) return NotificationApiResult(success: false, message: 'Chưa đăng nhập');

      final url = Uri.parse('${ApiConfig.baseOrigin}/api/notifications');
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(response.body);
        if (body['success'] == true && body['data'] != null) {
          final List<dynamic> listData = body['data'];
          final List<NotificationModel> notifications = listData
              .map((item) => NotificationModel.fromJson(item))
              .toList();
          return NotificationApiResult(success: true, data: notifications);
        }
        return NotificationApiResult(success: false, message: body['message']);
      }
      return NotificationApiResult(success: false, message: 'Lỗi server');
    } catch (e) {
      return NotificationApiResult(success: false, message: e.toString());
    }
  }

  static Future<NotificationApiResult<int>> getUnreadCount() async {
    try {
      final token = await AuthSessionService().getToken();
      if (token == null) return NotificationApiResult(success: false, message: 'Chưa đăng nhập');

      final url = Uri.parse('${ApiConfig.baseOrigin}/api/notifications/unread-count');
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(response.body);
        if (body['success'] == true && body['data'] != null) {
          final int unreadCount = body['data']['unread_count'] ?? 0;
          return NotificationApiResult(success: true, data: unreadCount);
        }
        return NotificationApiResult(success: false, message: body['message']);
      }
      return NotificationApiResult(success: false, message: 'Lỗi server');
    } catch (e) {
      return NotificationApiResult(success: false, message: e.toString());
    }
  }

  static Future<NotificationApiResult<void>> markAsRead(int id) async {
    try {
      final token = await AuthSessionService().getToken();
      if (token == null) return NotificationApiResult(success: false, message: 'Chưa đăng nhập');

      final url = Uri.parse('${ApiConfig.baseOrigin}/api/notifications/$id/read');
      final response = await http.put(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(response.body);
        if (body['success'] == true) {
          return NotificationApiResult(success: true);
        }
        return NotificationApiResult(success: false, message: body['message']);
      }
      return NotificationApiResult(success: false, message: 'Lỗi server');
    } catch (e) {
      return NotificationApiResult(success: false, message: e.toString());
    }
  }
}
