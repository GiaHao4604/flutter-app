import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class PostApiResult {
  const PostApiResult({
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

class PostApiService {
  static const String _lanBaseUrl = 'http://192.168.1.240:3000/api/posts';
  static const String _androidEmulatorBaseUrl = 'http://10.0.2.2:3000/api/posts';
  static String? _activeBaseUrl;
  static List<String> _lastTriedBaseUrls = <String>[];

  static String _resolveBaseUrl() {
    const configuredBaseUrl = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: '',
    );
    if (configuredBaseUrl.isNotEmpty) {
      return configuredBaseUrl.replaceFirst(
        RegExp(r'/api/[^/]+$'),
        '/api/posts',
      );
    }

    if (kIsWeb) {
      return 'http://localhost:3000/api/posts';
    }

    // Default to LAN IP on mobile devices, but allow fallback if necessary.
    return _lanBaseUrl;
  }

  // Resolved base URL for posts API (can be overridden via --dart-define)
  static final String _baseUrl = _resolveBaseUrl();

  static String resolveMediaUrl(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return '';
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return raw;
    }

    final activeBaseUrl = _activeBaseUrl ?? _baseUrl;
    final rootUrl = activeBaseUrl.replaceFirst(RegExp(r'/api/posts$'), '');
    if (raw.startsWith('/')) {
      return '$rootUrl$raw';
    }
    return '$rootUrl/$raw';
  }

  Future<PostApiResult> getPosts({
    required String token,
    int page = 1,
    int limit = 12,
    bool my = false,
  }) {
    final path = '/?page=$page&limit=$limit${my ? '&my=1' : ''}';
    return _get(token: token, path: path);
  }

  Future<PostApiResult> uploadPost({
    required String token,
    required File imageFile,
    required String caption,
    String? deviceId,
    String? cameraType,
  }) async {
    try {
      final streamResponse = await _runWithBaseUrlFallback((baseUrl) async {
        final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/upload'));
        request.headers['Authorization'] = 'Bearer $token';
        request.files.add(
          await http.MultipartFile.fromPath(
            'image',
            imageFile.path,
            contentType: MediaType('image', 'jpeg'),
          ),
        );
        request.fields['caption'] = caption;
        if (deviceId != null && deviceId.trim().isNotEmpty) {
          request.fields['device_id'] = deviceId.trim();
        }
        if (cameraType != null && cameraType.trim().isNotEmpty) {
          request.fields['camera_type'] = cameraType.trim();
        }

        return request.send().timeout(const Duration(seconds: 30));
      });

      final body = await streamResponse.stream.bytesToString();
      return _decodeResponse(streamResponse.statusCode, body);
    } catch (error) {
      return PostApiResult(
        success: false,
        message: _buildLocalServerErrorMessage(error, action: 'upload bài viết'),
        statusCode: 0,
      );
    }
  }

  Future<PostApiResult> _get({
    required String token,
    required String path,
  }) async {
    try {
      final response = await _runWithBaseUrlFallback((baseUrl) {
        return http
            .get(
              Uri.parse('$baseUrl$path'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
            )
            .timeout(const Duration(seconds: 4));
      });
      return _decodeResponse(response.statusCode, response.body);
    } catch (error) {
      return PostApiResult(
        success: false,
        message: _buildLocalServerErrorMessage(error, action: 'lấy bài viết'),
        statusCode: 0,
      );
    }
  }

  PostApiResult _decodeResponse(int statusCode, String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return PostApiResult(
          success: decoded['success'] == true,
          message: decoded['message']?.toString() ?? '',
          statusCode: statusCode,
          data: decoded,
        );
      }
    } catch (_) {}

    return PostApiResult(
      success: statusCode >= 200 && statusCode < 300,
      message: body,
      statusCode: statusCode,
    );
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
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      add(_androidEmulatorBaseUrl);
    }
    add(_baseUrl);
    add(_lanBaseUrl);

    return result;
  }

  String _buildLocalServerErrorMessage(Object error, {required String action}) {
    final activeBaseUrl = _activeBaseUrl ?? _baseUrl;
    final attempts = _lastTriedBaseUrls.isEmpty
        ? activeBaseUrl
        : _lastTriedBaseUrls.join(', ');

    if (error is SocketException) {
      final details = error.osError?.message ?? error.message;
      return 'Không kết nối được server khi $action. Đã thử: $attempts. Chi tiết: $details';
    }

    if (error is TimeoutException) {
      return 'Server phản hồi quá chậm khi $action. Đã thử: $attempts.';
    }

    if (error is http.ClientException) {
      return 'Lỗi client HTTP khi $action: ${error.message}';
    }

    return 'Lỗi khi kết nối server ($activeBaseUrl) khi $action: $error';
  }
}
