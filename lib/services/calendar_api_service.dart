import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class CalendarApiResult {
  const CalendarApiResult({
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

class CalendarApiService {
  static final String _baseUrl = _resolveBaseUrl();
  static const String _lanBaseUrl = 'http://192.168.1.240:3000/api/calendar';
  static const String _androidEmulatorBaseUrl = 'http://10.0.2.2:3000/api/calendar';
  static String? _activeBaseUrl;
  static List<String> _lastTriedBaseUrls = <String>[];

  static String _resolveBaseUrl() {
    const configuredBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '');

    if (configuredBaseUrl.isNotEmpty) {
      return configuredBaseUrl;
    }

    if (kIsWeb) {
      return 'http://localhost:3000/api/calendar';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _lanBaseUrl;
      case TargetPlatform.iOS:
        return _lanBaseUrl;
      default:
        return 'http://localhost:3000/api/calendar';
    }
  }

  Future<CalendarApiResult> getMonth({
    required String token,
    DateTime? month,
  }) async {
    try {
      final target = month ?? DateTime.now();
      final response = await _runWithBaseUrlFallback(
        (baseUrl) => http
            .get(
              Uri.parse(
                '$baseUrl/month?year=${target.year}&month=${target.month}',
              ),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
            )
            .timeout(const Duration(seconds: 10)),
      );

      final decoded = _decodeJson(response.body);
      final success = decoded['success'] == true;
      return CalendarApiResult(
        success: success,
        message: _buildHttpMessage(
          success: success,
          decoded: decoded,
          statusCode: response.statusCode,
          rawBody: response.body,
          fallbackFailMessage: 'Không tải được dữ liệu calendar',
        ),
        statusCode: response.statusCode,
        data: decoded['data'] is Map<String, dynamic>
            ? Map<String, dynamic>.from(decoded['data'] as Map)
            : decoded,
      );
    } catch (error) {
      return CalendarApiResult(
        success: false,
        message: _buildLocalServerErrorMessage(error, action: 'tải calendar'),
        statusCode: 0,
      );
    }
  }

  Future<CalendarApiResult> createEntry({
    required String token,
    required File imageFile,
    required int amount,
    required bool isExpense,
    required String dateKey,
    required String date,
    String? clientLocalId,
    int? categoryId,
    String? categoryKey,
    String? slug,
    String? note,
  }) async {
    try {
      final streamedResponse = await _runWithBaseUrlFallback((baseUrl) async {
        final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/entries'));
        request.headers['Authorization'] = 'Bearer $token';
        request.fields['amount'] = amount.toString();
        if (clientLocalId != null && clientLocalId.trim().isNotEmpty) {
          request.fields['clientLocalId'] = clientLocalId.trim();
        }
        request.fields['isExpense'] = isExpense.toString();
        request.fields['dateKey'] = dateKey;
        request.fields['date'] = date;
        if (categoryId != null && categoryId > 0) {
          request.fields['categoryId'] = categoryId.toString();
        }
        final normalizedCategoryKey = categoryKey?.trim();
        if (normalizedCategoryKey != null && normalizedCategoryKey.isNotEmpty) {
          request.fields['categoryKey'] = normalizedCategoryKey;
        }
        final normalizedSlug = slug?.trim();
        if (normalizedSlug != null && normalizedSlug.isNotEmpty) {
          request.fields['slug'] = normalizedSlug;
        }
        if (note != null && note.trim().isNotEmpty) {
          request.fields['note'] = note.trim();
        }
        request.files.add(await http.MultipartFile.fromPath('image', imageFile.path));
        return request.send().timeout(const Duration(seconds: 20));
      });

      final response = await http.Response.fromStream(streamedResponse);
      final decoded = _decodeJson(response.body);
      final success = decoded['success'] == true;
      return CalendarApiResult(
        success: success,
        message: _buildHttpMessage(
          success: success,
          decoded: decoded,
          statusCode: response.statusCode,
          rawBody: response.body,
          fallbackFailMessage: 'Không lưu được calendar entry',
        ),
        statusCode: response.statusCode,
        data: decoded['data'] is Map<String, dynamic>
            ? Map<String, dynamic>.from(decoded['data'] as Map)
            : decoded,
      );
    } catch (error) {
      return CalendarApiResult(
        success: false,
        message: _buildLocalServerErrorMessage(error, action: 'lưu calendar'),
        statusCode: 0,
      );
    }
  }

  Future<T> _runWithBaseUrlFallback<T>(Future<T> Function(String baseUrl) request) async {
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
    final preview = compactBody.length > 120 ? '${compactBody.substring(0, 120)}...' : compactBody;

    if (preview.isNotEmpty) {
      return 'Lỗi server cục bộ (HTTP $statusCode): $preview';
    }

    return 'Lỗi server cục bộ (HTTP $statusCode): $fallbackFailMessage';
  }

  String _buildLocalServerErrorMessage(Object error, {required String action}) {
    final activeBaseUrl = _activeBaseUrl ?? _baseUrl;
    final attempts = _lastTriedBaseUrls.isEmpty ? activeBaseUrl : _lastTriedBaseUrls.join(', ');

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

  /// Resolve an asset path returned by the API into a full absolute URL.
  /// If [path] already contains a scheme (http/https) it is returned unchanged.
  /// If it's a relative path (e.g. '/uploads/...') this will prefix the API origin.
  static String resolveAssetUrl(String path) {
    final s = path.trim();
    if (s.isEmpty) return '';
    if (s.startsWith('http://') || s.startsWith('https://')) return s;

    // Only convert known server asset paths. Absolute local file paths like
    // /data/user/... must stay local and must not become HTTP URLs.
    final isServerAssetPath = s.startsWith('/uploads/') || s.startsWith('uploads/');
    if (!isServerAssetPath) {
      return s;
    }

    try {
      final origin = Uri.parse(_baseUrl).origin; // e.g. http://host:port
      if (s.startsWith('/')) return '$origin$s';
      return '$origin/$s';
    } catch (_) {
      return s;
    }
  }
}