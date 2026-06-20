import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'api_config.dart';
import 'package:flutter_application_1/services/auth_session_service.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class SocketService {
  SocketService._internal();

  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;

  io.Socket? _socket;
  Completer<void>? _connectCompleter;
  final _newMessageController = StreamController<Map<String, dynamic>>.broadcast();
  final _typingController = StreamController<Map<String, dynamic>>.broadcast();
  final _presenceController = StreamController<Map<String, dynamic>>.broadcast();
  final _seenController = StreamController<Map<String, dynamic>>.broadcast();
  final _systemNotificationController = StreamController<Map<String, dynamic>>.broadcast();
  final _messageDeletedController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get onNewMessage => _newMessageController.stream;
  Stream<Map<String, dynamic>> get onTyping => _typingController.stream;
  Stream<Map<String, dynamic>> get onPresence => _presenceController.stream;
  Stream<Map<String, dynamic>> get onSeen => _seenController.stream;
  Stream<Map<String, dynamic>> get onSystemNotification => _systemNotificationController.stream;
  Stream<Map<String, dynamic>> get onMessageDeleted => _messageDeletedController.stream;

  bool get isConnected => _socket?.connected == true;

  // Danh sách URL ưu tiên - thử lần lượt đến khi nào kết nối được
  List<String> _candidateSocketUrls() {
    return [ApiConfig.lanOrigin, ApiConfig.androidEmulatorOrigin];
  }

  // Kiểm tra TCP xem server có thể kết nối không (timeout 2 giây)
  Future<String?> _findReachableUrl() async {
    for (final url in _candidateSocketUrls()) {
      try {
        final uri = Uri.parse(url);
        final sock = await Socket.connect(
          uri.host,
          uri.port,
          timeout: const Duration(seconds: 2),
        );
        sock.destroy();
        return url;
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  Future<void> connect() async {
    if (isConnected) return;

    if (_connectCompleter != null) {
      return _connectCompleter!.future;
    }

    _connectCompleter = Completer<void>();

    final token = await AuthSessionService().getToken();
    if (token == null || token.isEmpty) {
      _connectCompleter?.completeError(Exception('Socket: No token'));
      _connectCompleter = null;
      return;
    }

    // Tự động tìm địa chỉ server khả dụng (LAN hoặc Emulator)
    final reachableUrl = await _findReachableUrl();
    if (reachableUrl == null) {
      debugPrint('Socket: Không tìm được server nào trong mạng LAN');
      _connectCompleter?.completeError(Exception('timeout'));
      _connectCompleter = null;
      return;
    }

    debugPrint('Socket: Kết nối tới $reachableUrl');

    _socket = io.io(
      reachableUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setExtraHeaders({'Authorization': 'Bearer $token'})
          .setAuth({'token': token})
          .build(),
    );

    _socket?.on('connect', (_) {
      _presenceController.add({'status': 'connected'});
      _connectCompleter?.complete();
      _connectCompleter = null;
    });

    _socket?.on('disconnect', (_) {
      _presenceController.add({'status': 'disconnected'});
    });

    _socket?.on('new_message', (data) {
      if (data is Map<String, dynamic>) {
        _newMessageController.add(data);
      }
    });

    _socket?.on('typing', (data) {
      if (data is Map<String, dynamic>) {
        _typingController.add(data);
      }
    });

    _socket?.on('system_notification', (data) {
      if (data is Map<String, dynamic>) {
        _systemNotificationController.add(data);
      }
    });

    _socket?.on('user_presence', (data) {
      if (data is Map<String, dynamic>) {
        _presenceController.add(data);
      }
    });

    _socket?.on('messages_seen', (data) {
      if (data is Map<String, dynamic>) {
        _seenController.add(data);
      }
    });

    _socket?.on('message_deleted', (data) {
      if (data is Map<String, dynamic>) {
        _messageDeletedController.add(data);
      }
    });

    _socket?.on('connect_error', (error) {
      _presenceController.add({'status': 'error', 'error': error.toString()});
      _connectCompleter?.completeError(error);
      _connectCompleter = null;
    });

    _socket?.connect();
    final completer = _connectCompleter;
    if (completer != null) {
      await completer.future;
    }
  }

  Future<void> joinConversation(int conversationId) async {
    await connect();
    _socket?.emit('join_conversation', conversationId);
  }

  Future<void> leaveConversation(int conversationId) async {
    await connect();
    _socket?.emit('leave_conversation', conversationId);
  }

  Future<void> sendTyping(int conversationId, bool isTyping) async {
    await connect();
    _socket?.emit('typing', {
      'conversation_id': conversationId,
      'is_typing': isTyping,
    });
  }

  void dispose() {
    _newMessageController.close();
    _typingController.close();
    _presenceController.close();
    _seenController.close();
    _socket?.disconnect();
    _socket = null;
  }
}
