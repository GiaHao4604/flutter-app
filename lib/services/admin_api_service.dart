import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_application_1/services/auth_session_service.dart';
import 'api_config.dart';

class AdminApiResult {
  final bool success;
  final String message;
  final dynamic data;
  final int statusCode;

  AdminApiResult({
    required this.success,
    required this.message,
    this.data,
    this.statusCode = 200,
  });
}

class AdminApiService {
  static final String baseUrl = ApiConfig.apiUrl('admin');
  final AuthSessionService _sessionService = AuthSessionService();

  Future<Map<String, String>> _getHeaders() async {
    final token = await _sessionService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Future<AdminApiResult> _get(String path) async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(Uri.parse('$baseUrl$path'), headers: headers);
      return _processResponse(response);
    } catch (e) {
      return AdminApiResult(success: false, message: 'Lỗi mạng: $e', statusCode: 500);
    }
  }

  Future<AdminApiResult> _put(String path) async {
    try {
      final headers = await _getHeaders();
      final response = await http.put(Uri.parse('$baseUrl$path'), headers: headers);
      return _processResponse(response);
    } catch (e) {
      return AdminApiResult(success: false, message: 'Lỗi mạng: $e', statusCode: 500);
    }
  }

  Future<AdminApiResult> _delete(String path) async {
    try {
      final headers = await _getHeaders();
      final response = await http.delete(Uri.parse('$baseUrl$path'), headers: headers);
      return _processResponse(response);
    } catch (e) {
      return AdminApiResult(success: false, message: 'Lỗi mạng: $e', statusCode: 500);
    }
  }

  Future<AdminApiResult> _post(String path) async {
    try {
      final headers = await _getHeaders();
      final response = await http.post(Uri.parse('$baseUrl$path'), headers: headers);
      return _processResponse(response);
    } catch (e) {
      return AdminApiResult(success: false, message: 'Lỗi mạng: $e', statusCode: 500);
    }
  }

  AdminApiResult _processResponse(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      return AdminApiResult(
        success: body['success'] ?? false,
        message: body['message'] ?? '',
        data: body['data'],
        statusCode: response.statusCode,
      );
    } catch (_) {
      return AdminApiResult(
        success: response.statusCode >= 200 && response.statusCode < 300,
        message: response.statusCode == 403 ? 'Forbidden' : 'Unknown error',
        statusCode: response.statusCode,
      );
    }
  }

  Future<AdminApiResult> getDashboardUsersChart() => _get('/dashboard/users-chart');
  Future<AdminApiResult> getAllUsers() => _get('/users');
  Future<AdminApiResult> toggleUserRole(int userId) => _put('/users/$userId/role');
  Future<AdminApiResult> toggleUserBan(int userId) => _put('/users/$userId/ban');
  Future<AdminApiResult> deleteUser(int userId) => _delete('/users/$userId');
  Future<AdminApiResult> getReportedPosts() => _get('/reports');
  Future<AdminApiResult> resolveReport(int reportId) => _put('/reports/$reportId/resolve');
  Future<AdminApiResult> deletePost(int postId) => _delete('/posts/$postId');
  Future<AdminApiResult> transferDirectorAdmin(int userId) => _post('/users/$userId/transfer');
}
