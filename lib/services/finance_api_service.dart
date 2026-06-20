import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class FinanceApiResult {
  const FinanceApiResult({
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

class FinanceApiService {
  static final String _baseUrl = _resolveBaseUrl();
  static const String _lanBaseUrl = 'http://192.168.1.240:3000/api/finance';
  static const String _androidEmulatorBaseUrl =
      'http://10.0.2.2:3000/api/finance';
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
        '/api/finance',
      );
    }

    if (kIsWeb) {
      return 'http://localhost:3000/api/finance';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _lanBaseUrl;
      case TargetPlatform.iOS:
        return _lanBaseUrl;
      default:
        return 'http://localhost:3000/api/finance';
    }
  }

  Future<FinanceApiResult> getBudgetDashboard({
    required String token,
    String? monthKey,
  }) async {
    final query = monthKey == null || monthKey.isEmpty
        ? ''
        : '?monthKey=$monthKey';
    return _get(token: token, path: '/budgets$query');
  }

  Future<FinanceApiResult> getHistoryBudgets({
    required String token,
  }) async {
    return _get(token: token, path: '/budgets/history');
  }

  Future<FinanceApiResult> getSummary({
    required String token,
    String? monthKey,
  }) async {
    final query = monthKey == null || monthKey.isEmpty
        ? ''
        : '?monthKey=$monthKey';
    return _get(token: token, path: '/summary$query');
  }

  Future<FinanceApiResult> getCategories({required String token}) {
    return _get(token: token, path: '/categories');
  }

  Future<FinanceApiResult> upsertCategory({
    required String token,
    required String name,
    String? id,
    String? kind,
    String? iconKey,
    String? color,
  }) {
    final body = <String, dynamic>{'name': name};
    if (kind != null) body['kind'] = kind;
    if (iconKey != null) body['iconKey'] = iconKey;
    if (color != null) body['color'] = color;

    if (id != null && id.isNotEmpty) {
      return _patch(token: token, path: '/categories/$id', body: body);
    }
    return _post(token: token, path: '/categories', body: body);
  }

  Future<FinanceApiResult> upsertBudget({
    required String token,
    required String name,
    required int limitAmount,
    String? id,
    String? monthKey,
    int? categoryId,
    String? slug,
    String? kind,
    String? iconKey,
    String? color,
    bool isRepeat = false,
    String? startDate,
    String? endDate,
  }) {
    final body = <String, dynamic>{
      'name': name,
      'limitAmount': limitAmount,
      'isRepeat': isRepeat,
    };
    if (id != null) body['id'] = id;
    if (monthKey != null) body['monthKey'] = monthKey;
    if (categoryId != null) body['categoryId'] = categoryId;
    if (slug != null) body['slug'] = slug;
    if (kind != null) body['kind'] = kind;
    if (iconKey != null) body['iconKey'] = iconKey;
    if (color != null) body['color'] = color;
    if (startDate != null) body['startDate'] = startDate;
    if (endDate != null) body['endDate'] = endDate;

    return _post(token: token, path: '/budgets', body: body);
  }

  Future<FinanceApiResult> createTransaction({
    required String token,
    required int amount,
    required bool isExpense,
    required String transactionDate,
    int? categoryId,
    String? note,
    int? calendarEntryId,
  }) {
    final body = <String, dynamic>{
      'amount': amount,
      'isExpense': isExpense,
      'transactionDate': transactionDate,
    };
    if (categoryId != null) body['categoryId'] = categoryId;
    if (note != null && note.trim().isNotEmpty) body['note'] = note.trim();
    if (calendarEntryId != null) body['calendarEntryId'] = calendarEntryId;

    return _post(token: token, path: '/transactions', body: body);
  }

  Future<FinanceApiResult> deleteBudget({
    required String token,
    required int budgetId,
  }) {
    return _delete(token: token, path: '/budgets/$budgetId');
  }

  Future<FinanceApiResult> deleteCategory({
    required String token,
    required int categoryId,
  }) {
    return _delete(token: token, path: '/categories/$categoryId');
  }

  Future<FinanceApiResult> _get({
    required String token,
    required String path,
  }) async {
    try {
      final response = await _runWithBaseUrlFallback(
        (baseUrl) => http
            .get(
              Uri.parse('$baseUrl$path'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
            )
            .timeout(const Duration(seconds: 10)),
      );

      return _decodeResponse(response);
    } catch (error) {
      return FinanceApiResult(
        success: false,
        message: _buildLocalServerErrorMessage(
          error,
          action: 'gọi finance API',
        ),
        statusCode: 0,
      );
    }
  }

  Future<FinanceApiResult> _patch({
    required String token,
    required String path,
    required Map<String, dynamic> body,
  }) async {
    try {
      final response = await _runWithBaseUrlFallback(
        (baseUrl) => http
            .patch(
              Uri.parse('$baseUrl$path'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 10)),
      );

      return _decodeResponse(response);
    } catch (error) {
      return FinanceApiResult(
        success: false,
        message: _buildLocalServerErrorMessage(
          error,
          action: 'gọi finance API',
        ),
        statusCode: 0,
      );
    }
  }

  Future<FinanceApiResult> _post({
    required String token,
    required String path,
    required Map<String, dynamic> body,
  }) async {
    try {
      final response = await _runWithBaseUrlFallback(
        (baseUrl) => http
            .post(
              Uri.parse('$baseUrl$path'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 10)),
      );

      return _decodeResponse(response);
    } catch (error) {
      return FinanceApiResult(
        success: false,
        message: _buildLocalServerErrorMessage(
          error,
          action: 'gọi finance API',
        ),
        statusCode: 0,
      );
    }
  }

  Future<FinanceApiResult> _delete({
    required String token,
    required String path,
  }) async {
    try {
      final response = await _runWithBaseUrlFallback(
        (baseUrl) => http
            .delete(
              Uri.parse('$baseUrl$path'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
            )
            .timeout(const Duration(seconds: 10)),
      );

      return _decodeResponse(response);
    } catch (error) {
      return FinanceApiResult(
        success: false,
        message: _buildLocalServerErrorMessage(
          error,
          action: 'xoá ngân sách qua finance API',
        ),
        statusCode: 0,
      );
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

  FinanceApiResult _decodeResponse(http.Response response) {
    final decoded = _decodeJson(response.body);
    final success = decoded['success'] == true;
    final message = _buildHttpMessage(
      success: success,
      decoded: decoded,
      statusCode: response.statusCode,
      rawBody: response.body,
      fallbackFailMessage: 'Yêu cầu thất bại với finance API',
    );

    final data = decoded['data'] is Map<String, dynamic>
        ? Map<String, dynamic>.from(decoded['data'] as Map<String, dynamic>)
        : decoded['data'] is Map
        ? Map<String, dynamic>.from(decoded['data'] as Map)
        : Map<String, dynamic>.from(decoded);

    for (final key in const ['budget', 'transaction']) {
      final value = decoded[key];
      if (value is Map) {
        data[key] = Map<String, dynamic>.from(value);
      }
    }

    return FinanceApiResult(
      success: success,
      message: message,
      statusCode: response.statusCode,
      data: data,
    );
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

  String _buildLocalServerErrorMessage(Object error, {required String action}) {
    final activeBaseUrl = _activeBaseUrl ?? _baseUrl;
    final attempts = _lastTriedBaseUrls.isEmpty
        ? activeBaseUrl
        : _lastTriedBaseUrls.join(', ');

    if (error is SocketException) {
      final details = error.osError?.message ?? error.message;
      return 'Không kết nối được server cục bộ khi $action. Đã thử: $attempts. Chi tiết: $details';
    }

    if (error is TimeoutException) {
      return 'Server cục bộ phản hồi quá chậm khi $action. Đã thử: $attempts.';
    }

    if (error is http.ClientException) {
      return 'Lỗi client HTTP khi $action: ${error.message}';
    }

    return 'Lỗi khi kết nối server cục bộ ($activeBaseUrl) lúc $action: $error';
  }
}
