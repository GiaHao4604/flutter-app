import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class AuthApiResult {
  const AuthApiResult({
    required this.success,
    required this.message,
    required this.statusCode,
    this.data,
  });

  final bool success;
  final String message;
  final int statusCode;
  final Map<String, dynamic>? data;
}

class AuthApiService {
  static final String _baseUrl = _resolveBaseUrl();
  static const String _lanBaseUrl = 'http://192.168.1.240:3000/api/auth';
  static const String _androidEmulatorBaseUrl = 'http://10.0.2.2:3000/api/auth';
  static String? _activeBaseUrl;
  static List<String> _lastTriedBaseUrls = <String>[];

  static String _resolveBaseUrl() {
    const configuredBaseUrl = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: '',
    );

    if (configuredBaseUrl.isNotEmpty) {
      return configuredBaseUrl;
    }

    if (kIsWeb) {
      return 'http://localhost:3000/api/auth';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _lanBaseUrl;
      case TargetPlatform.iOS:
        return _lanBaseUrl;
      default:
        return 'http://localhost:3000/api/auth';
    }
  }

  Future<AuthApiResult> register({
    required String name,
    required String email,
    required String password,
  }) {
    return _post(
      path: '/register',
      body: {'name': name, 'email': email, 'password': password},
    );
  }

  Future<AuthApiResult> login({
    required String email,
    required String password,
  }) {
    return _post(path: '/login', body: {'email': email, 'password': password});
  }

  Future<AuthApiResult> getMe({required String token}) async {
    try {
      final response = await _runWithBaseUrlFallback(
        (baseUrl) => http
            .get(
              Uri.parse('$baseUrl/me'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
            )
            .timeout(const Duration(seconds: 10)),
      );

      final decoded = _decodeJson(response.body);
      final success = decoded['success'] == true;
      final message = _buildHttpMessage(
        success: success,
        decoded: decoded,
        statusCode: response.statusCode,
        rawBody: response.body,
        fallbackFailMessage: 'Yêu cầu thất bại khi tải thông tin tài khoản',
      );
      
        // Chống lỗi null dữ liệu thông tin cá nhân
        final data = decoded['data'] is Map<String, dynamic>
          ? decoded['data'] as Map<String, dynamic>
          : decoded;

      return AuthApiResult(
        success: success,
        message: message,
        statusCode: response.statusCode,
        data: data,
      );
    } catch (error) {
      return AuthApiResult(
        success: false,
        message: _buildLocalServerErrorMessage(
          error,
          action: 'tải thông tin tài khoản',
        ),
        statusCode: 0,
      );
    }
  }
  
  Future<AuthApiResult> uploadAvatar({
    required File imageFile,
    required String token,
  }) async {
    try {
      final streamedResponse = await _runWithBaseUrlFallback((baseUrl) async {
        final uri = Uri.parse('$baseUrl/upload-avatar');
        final request = http.MultipartRequest('POST', uri);
        request.headers['Authorization'] = 'Bearer $token';
        request.files.add(
          await http.MultipartFile.fromPath('avatar', imageFile.path),
        );

        return request.send().timeout(const Duration(seconds: 15));
      });

      final response = await http.Response.fromStream(streamedResponse);

      final decoded = _decodeJson(response.body);
      final success = decoded['success'] == true;
      final message = _buildHttpMessage(
        success: success,
        decoded: decoded,
        statusCode: response.statusCode,
        rawBody: response.body,
        fallbackFailMessage: 'Yêu cầu thất bại khi tải ảnh đại diện',
      );
      
      final data = <String, dynamic>{
        'avatarUrl': decoded['avatarUrl'] as String?,
      };

      return AuthApiResult(
        success: success,
        message: message,
        statusCode: response.statusCode,
        data: data,
      );
    } catch (error) {
      return AuthApiResult(
        success: false,
        message: _buildLocalServerErrorMessage(
          error,
          action: 'tải ảnh đại diện',
        ),
        statusCode: 0,
      );
    }
  }

  Future<AuthApiResult> updateProfile({
    required String token,
    String? name,
  }) async {
    try {
      final payload = <String, dynamic>{};
      if (name != null) payload['name'] = name;

      final response = await _runWithBaseUrlFallback(
        (baseUrl) => http
            .put(
              Uri.parse('$baseUrl/me'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 10)),
      );

      final decoded = _decodeJson(response.body);
      final success = decoded['success'] == true;
      final message = _buildHttpMessage(
        success: success,
        decoded: decoded,
        statusCode: response.statusCode,
        rawBody: response.body,
        fallbackFailMessage: 'Yêu cầu thất bại khi cập nhật hồ sơ',
      );

      final data = decoded['data'] is Map<String, dynamic>
          ? decoded['data'] as Map<String, dynamic>
          : <String, dynamic>{};

      return AuthApiResult(
        success: success,
        message: message,
        statusCode: response.statusCode,
        data: data,
      );
    } catch (error) {
      return AuthApiResult(
        success: false,
        message: _buildLocalServerErrorMessage(
          error,
          action: 'cập nhật hồ sơ',
        ),
        statusCode: 0,
      );
    }
  }

  Future<AuthApiResult> changePassword({
    required String token,
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    try {
      final response = await _runWithBaseUrlFallback(
        (baseUrl) => http
            .patch(
              Uri.parse('$baseUrl/me/password'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: jsonEncode({
                'currentPassword': currentPassword,
                'newPassword': newPassword,
                'confirmPassword': confirmPassword,
              }),
            )
            .timeout(const Duration(seconds: 10)),
      );

      final decoded = _decodeJson(response.body);
      final success = decoded['success'] == true;
      final message = _buildHttpMessage(
        success: success,
        decoded: decoded,
        statusCode: response.statusCode,
        rawBody: response.body,
        fallbackFailMessage: 'Yêu cầu thất bại khi đổi mật khẩu',
      );

      final data = decoded['data'] is Map<String, dynamic>
          ? decoded['data'] as Map<String, dynamic>
          : <String, dynamic>{};

      return AuthApiResult(
        success: success,
        message: message,
        statusCode: response.statusCode,
        data: data,
      );
    } catch (error) {
      return AuthApiResult(
        success: false,
        message: _buildLocalServerErrorMessage(
          error,
          action: 'đổi mật khẩu',
        ),
        statusCode: 0,
      );
    }
  }

  Future<AuthApiResult> _post({
    required String path,
    required Map<String, dynamic> body,
  }) async {
    try {
      final response = await _runWithBaseUrlFallback(
        (baseUrl) => http
            .post(
              Uri.parse('$baseUrl$path'),
              headers: const {'Content-Type': 'application/json'},
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 10)),
      );

      final decoded = _decodeJson(response.body);
      final success = decoded['success'] == true;
      final message = _buildHttpMessage(
        success: success,
        decoded: decoded,
        statusCode: response.statusCode,
        rawBody: response.body,
        fallbackFailMessage: 'Yêu cầu thất bại',
      );
      
      // 🧠 ĐOẠN FIX CHIẾN THUẬT: Tự động gom Token bọc vào Map data nếu backend trả kiểu phẳng
      Map<String, dynamic> data = {};
      if (decoded['data'] is Map<String, dynamic>) {
        data = Map<String, dynamic>.from(decoded['data'] as Map);
      } else {
        data = Map<String, dynamic>.from(decoded);
      }

      // Đảm bảo token luôn tồn tại trong trường data nếu server có trả về
      if (decoded['token'] != null && data['token'] == null) {
        data['token'] = decoded['token'];
      }

      return AuthApiResult(
        success: success,
        message: message,
        statusCode: response.statusCode,
        data: data,
      );
    } catch (error) {
      return AuthApiResult(
        success: false,
        message: _buildLocalServerErrorMessage(
          error,
          action: 'gửi yêu cầu đăng nhập/đăng ký',
        ),
        statusCode: 0,
      );
    }
  }

  String _buildLocalServerErrorMessage(
    Object error, {
    required String action,
  }) {
    final activeBaseUrl = _activeBaseUrl ?? _baseUrl;
    final attempts = _lastTriedBaseUrls.isEmpty
        ? activeBaseUrl
        : _lastTriedBaseUrls.join(', ');

    if (error is SocketException) {
      final details = error.osError?.message ?? error.message;
      return 'Không kết nối được server cục bộ khi $action. Da thu: $attempts. Chi tiết: $details';
    }

    if (error is TimeoutException) {
      return 'Server cục bộ phản hồi quá chậm khi $action. Da thu: $attempts.';
    }

    if (error is FileSystemException) {
      return 'Không đọc được file ảnh để upload: ${error.message}';
    }

    if (error is http.ClientException) {
      return 'Lỗi client HTTP khi $action: ${error.message}';
    }

    return 'Lỗi khi kết nối server cục bộ ($activeBaseUrl) lúc $action: $error';
  }

  Future<T> _runWithBaseUrlFallback<T>(
    Future<T> Function(String baseUrl) request,
  ) async {
    Object? lastError;
    final tried = <String>[];

    for (final baseUrl in _candidateBaseUrls()) {
      tried.add(baseUrl);
      _lastTriedBaseUrls = List<String>.from(tried);
      try {
        final result = await request(baseUrl);
        _activeBaseUrl = baseUrl;
        return result;
      } on SocketException catch (error) {
        lastError = error;
      } on TimeoutException catch (error) {
        lastError = error;
      } on http.ClientException catch (error) {
        lastError = error;
      }
    }

    if (lastError != null) {
      throw lastError;
    }

    return request(_baseUrl);
  }

  List<String> _candidateBaseUrls() {
    final result = <String>[];
    final seen = <String>{};

    void add(String value) {
      final normalized = value.trim();
      if (normalized.isEmpty || seen.contains(normalized)) {
        return;
      }
      seen.add(normalized);
      result.add(normalized);
    }

    if (_activeBaseUrl != null) {
      add(_activeBaseUrl!);
    }

    add(_baseUrl);

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      add(_androidEmulatorBaseUrl);
    }

    return result;
  }

  String _buildHttpMessage({
    required bool success,
    required Map<String, dynamic> decoded,
    required int statusCode,
    required String rawBody,
    required String fallbackFailMessage,
  }) {
    final apiMessage = (decoded['message'] as String?)?.trim();
    if (apiMessage != null && apiMessage.isNotEmpty) {
      return apiMessage;
    }

    if (success) {
      return 'Thành công';
    }

    final compactBody = rawBody.trim().replaceAll(RegExp(r'\s+'), ' ');
    final preview = compactBody.length > 120
        ? '${compactBody.substring(0, 120)}...'
        : compactBody;

    if (preview.isNotEmpty) {
      return 'Lỗi server cục bộ (HTTP $statusCode): $preview';
    }

    return 'Lỗi server cục bộ (HTTP $statusCode): $fallbackFailMessage';
  }

  Map<String, dynamic> _decodeJson(String raw) {
    try {
      final parsed = jsonDecode(raw);
      if (parsed is Map<String, dynamic>) {
        return parsed;
      }
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }
}