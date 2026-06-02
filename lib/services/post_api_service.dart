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

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'http://10.0.2.2:3000/api/posts';
      case TargetPlatform.iOS:
        return 'http://localhost:3000/api/posts';
      default:
        return 'http://localhost:3000/api/posts';
    }
  }

  static String resolveMediaUrl(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return '';
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return raw;
    }

    final rootUrl = _resolveBaseUrl().replaceFirst(RegExp(r'/api/posts$'), '');
    if (raw.startsWith('/')) {
      return '$rootUrl$raw';
    }
    return '$rootUrl/$raw';
  }

  Future<PostApiResult> getPosts({
    required String token,
    int page = 1,
    int limit = 12,
  }) {
    return _get(token: token, path: '/?page=$page&limit=$limit');
  }

  Future<PostApiResult> uploadPost({
    required String token,
    required File imageFile,
    required String caption,
    String? deviceId,
    String? cameraType,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_resolveBaseUrl()/upload'),
      );
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

      final response = await request.send();
      final body = await response.stream.bytesToString();
      return _decodeResponse(response.statusCode, body);
    } catch (error) {
      return PostApiResult(
        success: false,
        message: error.toString(),
        statusCode: 0,
      );
    }
  }

  Future<PostApiResult> deletePost({
    required String token,
    required int postId,
  }) {
    return _delete(token: token, path: '/$postId');
  }

  Future<PostApiResult> _get({
    required String token,
    required String path,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('${_resolveBaseUrl()}$path'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      return _decodeResponse(response.statusCode, response.body);
    } catch (error) {
      return PostApiResult(
        success: false,
        message: error.toString(),
        statusCode: 0,
      );
    }
  }

  Future<PostApiResult> _delete({
    required String token,
    required String path,
  }) async {
    try {
      final response = await http.delete(
        Uri.parse('${_resolveBaseUrl()}$path'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      return _decodeResponse(response.statusCode, response.body);
    } catch (error) {
      return PostApiResult(
        success: false,
        message: error.toString(),
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
}
