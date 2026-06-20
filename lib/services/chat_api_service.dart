import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_application_1/services/auth_session_service.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class ChatApiResult {
  const ChatApiResult({
    required this.success,
    required this.message,
    required this.statusCode,
    this.data,
  });

  final bool success;
  final String message;
  final int statusCode;
  final dynamic data;
}

class ChatApiService {
  static const String _lanBaseUrl = 'http://192.168.1.240:3000/api/chat';
  static const String _androidEmulatorBaseUrl = 'http://10.0.2.2:3000/api/chat';
  static String? _activeBaseUrl;
  static List<String> _lastTriedBaseUrls = <String>[];
  static final String _basePath = _resolveBaseUrl();
  final AuthSessionService _sessionService = AuthSessionService();

  static String get activeOrigin {
    final activeUrl = _activeBaseUrl ?? _basePath;
    final uri = Uri.tryParse(activeUrl);
    if (uri != null) {
      final portPart = uri.hasPort ? ':${uri.port}' : '';
      return '${uri.scheme}://${uri.host}$portPart';
    }
    return 'http://localhost:3000';
  }

  static String _resolveBaseUrl() {
    const configuredBaseUrl = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: '',
    );
    if (configuredBaseUrl.isNotEmpty) {
      return configuredBaseUrl.replaceFirst(
        RegExp(r'/api/[^/]+$'),
        '/api/chat',
      );
    }

    if (kIsWeb) {
      return 'http://localhost:3000/api/chat';
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'http://10.0.2.2:3000/api/chat';
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return 'http://localhost:3000/api/chat';
      default:
        return 'http://localhost:3000/api/chat';
    }
  }

  Future<String?> _getToken() async {
    return _sessionService.getToken();
  }

  Future<ChatApiResult> _request(
    Future<http.Response> Function(String token, String baseUrl) fn,
  ) async {
    try {
      final token = await _getToken();
      if (token == null) {
        return const ChatApiResult(success: false, message: 'Chưa đăng nhập', statusCode: 401);
      }
      final response = await _runWithBaseUrlFallback((baseUrl) {
        return fn(token, baseUrl);
      }).timeout(const Duration(seconds: 10));
      final decoded = _decodeJson(response.body);
      final success = decoded['success'] == true;
      final message = decoded['message']?.toString() ?? '';
      return ChatApiResult(success: success, message: message, statusCode: response.statusCode, data: decoded['data']);
    } catch (error) {
      return ChatApiResult(success: false, message: _buildErrorMessage(error), statusCode: 0);
    }
  }

  Future<ChatApiResult> getConversations() {
    return _request((token, baseUrl) => http.get(
          Uri.parse('$baseUrl/conversations'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        ));
  }

  Future<ChatApiResult> getMessages(int conversationId) {
    return _request((token, baseUrl) => http.get(
          Uri.parse('$baseUrl/messages/$conversationId'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        ));
  }

  Future<ChatApiResult> sendMessage({
    int? conversationId,
    int? recipientId,
    String? message,
    String? imageUrl,
    int? sharedPostId,
    int? replyToId,
  }) {
    final payload = <String, dynamic>{};

    if (conversationId != null) {
      payload['conversation_id'] = conversationId;
    }
    if (recipientId != null) {
      payload['recipient_id'] = recipientId;
    }
    if (message != null) {
      payload['message'] = message;
    }
    if (imageUrl != null) {
      payload['image_url'] = imageUrl;
    }
    if (sharedPostId != null) {
      payload['shared_post_id'] = sharedPostId;
    }
    if (replyToId != null) {
      payload['reply_to_id'] = replyToId;
    }

    return _request((token, baseUrl) => http.post(
          Uri.parse('$baseUrl/messages'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(payload),
        ));
  }

  Future<ChatApiResult> deleteMessage(int messageId) {
    return _request((token, baseUrl) => http.delete(
          Uri.parse('$baseUrl/messages/$messageId'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        ));
  }

  Future<ChatApiResult> markMessagesSeen(int conversationId) {
    return _request((token, baseUrl) => http.put(
          Uri.parse('$baseUrl/messages/seen'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'conversation_id': conversationId,
          }),
        ));
  }

  Future<ChatApiResult> searchUsers(String query) {
    final encoded = Uri.encodeQueryComponent(query);
    return _request((token, baseUrl) => http.get(
          Uri.parse('$baseUrl/users/search?q=$encoded'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        ));
  }

  Future<ChatApiResult> uploadImage(File imageFile) async {
    try {
      final token = await _getToken();
      if (token == null) {
        return const ChatApiResult(success: false, message: 'Chưa đăng nhập', statusCode: 401);
      }
      final streamedResponse = await _runWithBaseUrlFallback((baseUrl) async {
        final uri = Uri.parse('$baseUrl/messages/image');
        final request = http.MultipartRequest('POST', uri);
        request.headers['Authorization'] = 'Bearer $token';
        request.files.add(await http.MultipartFile.fromPath(
          'image', 
          imageFile.path,
          contentType: MediaType('image', 'jpeg'),
        ));
        return request.send().timeout(const Duration(seconds: 30));
      });
      final response = await http.Response.fromStream(streamedResponse);
      final decoded = _decodeJson(response.body);
      final success = decoded['success'] == true;
      final message = decoded['message']?.toString() ?? '';
      return ChatApiResult(success: success, message: message, statusCode: response.statusCode, data: decoded);
    } catch (error) {
      return ChatApiResult(success: false, message: _buildErrorMessage(error), statusCode: 0);
    }
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

    return request(_basePath);
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
    add(_lanBaseUrl);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      add(_androidEmulatorBaseUrl);
    }
    add(_basePath);

    return result;
  }

  Map<String, dynamic> _decodeJson(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  String _buildErrorMessage(Object error) {
    final attempts = _lastTriedBaseUrls.isEmpty ? _basePath : _lastTriedBaseUrls.join(', ');
    if (error is TimeoutException) {
      return 'Yêu cầu quá thời gian chờ';
    }
    return 'Lỗi kết nối khi truy cập $_basePath (đã thử: $attempts): ${error.toString()}';
  }
}
