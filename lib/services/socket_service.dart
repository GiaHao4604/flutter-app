import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_application_1/services/auth_session_service.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class _SocketNotConnectedException implements Exception {
  _SocketNotConnectedException(this.message);
  final String message;
  @override
  String toString() => message;
}

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

  Stream<Map<String, dynamic>> get onNewMessage => _newMessageController.stream;
  Stream<Map<String, dynamic>> get onTyping => _typingController.stream;
  Stream<Map<String, dynamic>> get onPresence => _presenceController.stream;
  Stream<Map<String, dynamic>> get onSeen => _seenController.stream;

  bool get isConnected => _socket?.connected == true;

  String _resolveSocketUrl() {
    if (kIsWeb) {
      return 'http://localhost:3000';
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'http://10.0.2.2:3000';
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return 'http://localhost:3000';
      default:
        return 'http://localhost:3000';
    }
  }

  Future<void> connect() async {
    if (isConnected) {
      return;
    }

    if (_connectCompleter != null) {
      return _connectCompleter!.future;
    }

    _connectCompleter = Completer<void>();

    final token = await AuthSessionService().getToken();
    if (token == null || token.isEmpty) {
      _connectCompleter?.completeError(_SocketNotConnectedException('No token available'));
      _connectCompleter = null;
      return;
    }

    _socket = io.io(
      _resolveSocketUrl(),
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
