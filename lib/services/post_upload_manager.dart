import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/services/auth_session_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/services/calendar_api_service.dart';
import 'package:flutter_application_1/services/finance_api_service.dart';
import 'package:flutter_application_1/services/post_api_service.dart';
import 'package:flutter_application_1/services/calendar_storage_service.dart';
import 'package:flutter_application_1/services/calendar_refresh_notifier.dart';
import 'package:flutter_application_1/main.dart';

class PostUploadManager {
  static final PostUploadManager _instance = PostUploadManager._internal();
  static PostUploadManager get instance => _instance;

  PostUploadManager._internal();

  final ValueNotifier<List<Map<String, dynamic>>> pendingUploads = ValueNotifier([]);
  bool _isProcessing = false;
  bool _isInitialized = false;

  final AuthSessionService _sessionService = AuthSessionService();
  final CalendarApiService _calendarApiService = CalendarApiService();
  final FinanceApiService _financeApiService = FinanceApiService();
  final PostApiService _postApiService = PostApiService();

  static const String _queueKey = 'post_upload_queue';

  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;
    await _loadQueue();
    _processQueue();
  }

  Future<void> _loadQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_queueKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final List decoded = jsonDecode(raw);
        pendingUploads.value = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (e) {
        debugPrint('Error decoding upload queue: $e');
      }
    }
  }

  Future<void> _saveQueue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_queueKey, jsonEncode(pendingUploads.value));
  }

  Future<void> enqueue({
    required String localId,
    required String imagePath,
    required int amount,
    required bool isExpense,
    required String dateKey,
    required String dateIso,
    required int? categoryId,
    required String? categoryKey,
    required String caption,
    String? categoryLabel,
  }) async {
    final newItem = {
      'localId': localId,
      'imagePath': imagePath,
      'amount': amount,
      'isExpense': isExpense,
      'dateKey': dateKey,
      'dateIso': dateIso,
      'categoryId': categoryId,
      'categoryKey': categoryKey,
      'categoryLabel': categoryLabel,
      'caption': caption,
      'status': 'pending', // pending, uploading, error
      'errorMessage': '',
    };

    final currentQueue = List<Map<String, dynamic>>.from(pendingUploads.value);
    currentQueue.insert(0, newItem); // add to top
    pendingUploads.value = currentQueue;
    await _saveQueue();

    _processQueue();
  }

  void _updateItemStatus(String localId, String status, {String errorMessage = ''}) {
    final currentQueue = List<Map<String, dynamic>>.from(pendingUploads.value);
    final index = currentQueue.indexWhere((e) => e['localId'] == localId);
    if (index != -1) {
      currentQueue[index]['status'] = status;
      currentQueue[index]['errorMessage'] = errorMessage;
      pendingUploads.value = currentQueue;
      _saveQueue();
    }
  }

  Future<void> _removeItem(String localId) async {
    final currentQueue = List<Map<String, dynamic>>.from(pendingUploads.value);
    currentQueue.removeWhere((e) => e['localId'] == localId);
    pendingUploads.value = currentQueue;
    await _saveQueue();
  }

  Future<void> retryAll() async {
    final currentQueue = List<Map<String, dynamic>>.from(pendingUploads.value);
    bool changed = false;
    for (var item in currentQueue) {
      if (item['status'] == 'error') {
        item['status'] = 'pending';
        changed = true;
      }
    }
    if (changed) {
      pendingUploads.value = currentQueue;
      await _saveQueue();
      _processQueue();
    }
  }
  
  Future<void> _removeLocalCalendarPost(String localId) async {
    final calendarStorageService = CalendarStorageService();
    final storageKey = await calendarStorageService.currentCalendarKey();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final List decoded = jsonDecode(raw);
        final posts = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
        posts.removeWhere((e) => e['clientLocalId'] == localId || e['localId'] == localId);
        await prefs.setString(storageKey, jsonEncode(posts));
      } catch (e) {
        debugPrint('Error deleting local post: $e');
      }
    }
  }

  Future<void> deleteFailedUpload(String localId) async {
    final item = pendingUploads.value.firstWhere((e) => e['localId'] == localId, orElse: () => {});
    if (item.isEmpty) return;
    
    // Xóa khỏi queue
    await _removeItem(localId);

    // Xóa khỏi local storage để hoàn tiền
    await _removeLocalCalendarPost(localId);
      
    // Báo UI (Calendar, Budget) cập nhật lại tiền
    try {
      calendarRefreshNotifier.value++;
    } catch (_) {}
  }

  Future<void> _processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      while (true) {
        final pendingItems = pendingUploads.value.where((e) => e['status'] == 'pending').toList();
        if (pendingItems.isEmpty) break;

        final item = pendingItems.first;
        final localId = item['localId'];

        _updateItemStatus(localId, 'uploading');

        final token = await _sessionService.getToken();
        if (token == null || token.trim().isEmpty) {
          _updateItemStatus(localId, 'error', errorMessage: 'Chưa đăng nhập');
          _showErrorSnackbar('Chưa đăng nhập');
          continue;
        }

        final file = File(item['imagePath']);
        if (!file.existsSync()) {
          // Lỗi mất file cục bộ, không thể up ảnh
          _updateItemStatus(localId, 'error', errorMessage: 'Không tìm thấy file ảnh gốc');
          _showErrorSnackbar('Không tìm thấy file ảnh gốc');
          continue;
        }

        // 0. Resolve Category ID (If needed)
        int? finalCategoryId = item['categoryId'];
        if (finalCategoryId == null && item['categoryKey'] != null) {
           finalCategoryId = await _resolveRemoteCategoryId(token, item['categoryKey'], item['categoryLabel']);
        }

        // 1. Upload lên Calendar API trước để lấy ID
        final calendarRes = await _calendarApiService.createEntry(
          token: token,
          imageFile: file,
          amount: item['amount'],
          isExpense: item['isExpense'],
          dateKey: item['dateKey'],
          date: item['dateIso'],
          clientLocalId: localId,
          categoryId: finalCategoryId,
          categoryKey: item['categoryKey'],
          slug: item['categoryKey'],
          note: item['caption'],
        );

        if (!calendarRes.success) {
          _updateItemStatus(localId, 'error', errorMessage: calendarRes.message);
          _showErrorSnackbar(calendarRes.message);
          continue;
        }

        // Lấy ID vừa tạo của calendar entry
        int? calendarEntryId;
        if (calendarRes.data != null) {
          calendarEntryId = int.tryParse(calendarRes.data!['id']?.toString() ?? '');
        }

        // 2. Upload bài đăng lên Social API kèm theo calendarEntryId
        final socialRes = await _postApiService.uploadPost(
          token: token,
          imageFile: file,
          caption: item['caption'],
          calendarEntryId: calendarEntryId,
        );

        if (!socialRes.success) {
          _updateItemStatus(localId, 'error', errorMessage: socialRes.message);
          _showErrorSnackbar(socialRes.message);
          continue;
        }

        // 2. Upload lên Finance API (Sync ngân sách) sau khi Calendar đã tạo xong
        if (calendarRes.data != null && calendarRes.data is Map<String, dynamic>) {
          final serverData = Map<String, dynamic>.from(calendarRes.data!);
          final calendarEntryId = int.tryParse(serverData['id']?.toString() ?? '');
          
          if (calendarEntryId != null && item['amount'] > 0 && finalCategoryId != null) {
            await _financeApiService.createTransaction(
              token: token,
              amount: item['amount'],
              isExpense: item['isExpense'],
              transactionDate: item['dateKey'],
              categoryId: finalCategoryId,
              note: item['caption'],
              calendarEntryId: calendarEntryId,
            );
          }
        }

        // Thành công tất cả
        await _removeItem(localId);
        await _removeLocalCalendarPost(localId);
        
        scaffoldMessengerKey.currentState?.hideCurrentSnackBar();
        scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text('Đã đăng bài thành công'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        
        // Notify reload bảng tin (nếu đang ở trang đó)
        try {
          calendarRefreshNotifier.value++;
        } catch (_) {}
      }
    } finally {
      _isProcessing = false;
    }
  }

  Future<int?> _resolveRemoteCategoryId(String token, String? key, String? label) async {
    if (key == null || key.trim().isEmpty) return null;
    final remote = await _financeApiService.getCategories(token: token);
    if (!remote.success || remote.data == null || remote.data!['data'] is! List) {
      return null;
    }
    for (final entry in remote.data!['data'] as List) {
      if (entry is! Map) continue;
      final item = Map<String, dynamic>.from(entry);
      final itemId = item['id']?.toString() ?? '';
      final itemKey = item['key']?.toString() ?? item['slug']?.toString() ?? '';
      final itemLabel = item['label']?.toString() ?? item['name']?.toString() ?? '';
      if (itemId == key || itemKey == key || (label != null && itemLabel == label)) {
        return int.tryParse(itemId);
      }
    }
    return null;
  }

  void _showErrorSnackbar(String message) {
    scaffoldMessengerKey.currentState?.hideCurrentSnackBar();
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text('Lỗi tải lên: $message'),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
