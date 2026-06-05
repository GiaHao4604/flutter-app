import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/models/chat_models.dart';
import 'package:flutter_application_1/services/chat_api_service.dart';
import 'package:flutter_application_1/services/socket_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

class ChatDetailScreen extends StatefulWidget {
  const ChatDetailScreen({
    super.key,
    required this.currentUserId,
    this.conversationId,
    required this.recipientId,
    required this.recipientName,
    this.recipientAvatarUrl,
    this.initialMessage,
  });

  final int currentUserId;
  final int? conversationId;
  final int recipientId;
  final String recipientName;
  final String? recipientAvatarUrl;
  final String? initialMessage;

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final ChatApiService _apiService = ChatApiService();
  final SocketService _socketService = SocketService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<ChatMessage> _messages = [];
  bool _isLoading = true;
  bool _isTyping = false;
  String _statusText = 'Offline';
  int? _conversationId;
  StreamSubscription<Map<String, dynamic>>? _messageSub;
  StreamSubscription<Map<String, dynamic>>? _typingSub;
  StreamSubscription<Map<String, dynamic>>? _presenceSub;

  @override
  void initState() {
    super.initState();
    _conversationId = widget.conversationId;
    if (widget.initialMessage != null && widget.initialMessage!.isNotEmpty) {
      _messageController.text = widget.initialMessage!;
    }
    _initializeChat();
    _messageController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    _typingSub?.cancel();
    _presenceSub?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initializeChat() async {
    // 1. Dò tìm cuộc hội thoại cũ nếu conversationId là null, sau đó load tin nhắn qua REST API
    try {
      if (_conversationId == null) {
        final conversationsResult = await _apiService.getConversations();
        if (conversationsResult.success && conversationsResult.data is List) {
          for (final item in conversationsResult.data) {
            if (item is Map<String, dynamic>) {
              final conversation = ChatConversation.fromJson(item);
              if (conversation.partner.id == widget.recipientId) {
                _conversationId = conversation.conversationId;
                break;
              }
            }
          }
        }
      }

      if (_conversationId != null) {
        await _loadMessages();
        await _markSeen();
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Lỗi tải API chat ban đầu: $e');
      setState(() {
        _isLoading = false;
      });
    }

    // 2. Kết nối Socket trong background (không chặn việc tải tin nhắn API)
    try {
      await _socketService.connect();
      if (_conversationId != null) {
        await _socketService.joinConversation(_conversationId!);
      }
    } catch (e) {
      debugPrint('Kết nối Socket.io thất bại: $e');
    }

    // 3. Đăng ký lắng nghe các sự kiện WebSocket
    _messageSub = _socketService.onNewMessage.listen((event) {
      final payload = event['message'];
      if (payload is Map<String, dynamic>) {
        final message = ChatMessage.fromJson(payload, widget.currentUserId);
        if (message.conversationId == _conversationId) {
          final alreadyExists = _messages.any((m) => m.id == message.id);
          if (!alreadyExists) {
            setState(() {
              _messages.add(message);
            });
            _scrollToBottom();
          }
          if (!message.isMe) {
            _markSeen();
          }
        }
      }
    });

    _typingSub = _socketService.onTyping.listen((event) {
      final conversationId = int.tryParse(event['conversation_id']?.toString() ?? '') ?? 0;
      final isTyping = event['is_typing'] == true;
      if (conversationId == _conversationId) {
        setState(() {
          _isTyping = isTyping;
        });
      }
    });

    _presenceSub = _socketService.onPresence.listen((event) {
      final eventUserId = int.tryParse(event['userId']?.toString() ?? '');
      if (eventUserId == widget.recipientId) {
        final status = event['online'] == true ? 'Online' : 'Offline';
        setState(() {
          _statusText = status;
        });
      }
      if (event['status'] == 'connected') {
        setState(() {
          _statusText = 'Online';
        });
      }
      if (event['status'] == 'disconnected') {
        setState(() {
          _statusText = 'Offline';
        });
      }
    });
  }

  Future<void> _loadMessages() async {
    if (_conversationId == null) return;
    setState(() => _isLoading = true);
    final result = await _apiService.getMessages(_conversationId!);
    if (!mounted) return;
    if (result.success && result.data is List) {
      setState(() {
        _messages = (result.data as List)
            .whereType<Map<String, dynamic>>()
            .map((item) => ChatMessage.fromJson(item, widget.currentUserId))
            .toList();
      });
      _scrollToBottom();
    }
    setState(() => _isLoading = false);
  }

  Future<void> _markSeen() async {
    if (_conversationId == null) return;
    await _apiService.markMessagesSeen(_conversationId!);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onTextChanged() {
    if (_conversationId != null) {
      // ignore: unawaited_futures
      try {
        _socketService.sendTyping(_conversationId!, _messageController.text.isNotEmpty);
      } catch (e) {
        debugPrint('Lỗi gửi sự kiện typing qua socket: $e');
      }
    }
  }

  Future<void> _sendMessage({String? imageUrl}) async {
    final text = _messageController.text.trim();
    if (text.isEmpty && (imageUrl == null || imageUrl.isEmpty)) return;

    final result = await _apiService.sendMessage(
      conversationId: _conversationId,
      recipientId: widget.recipientId,
      message: text.isNotEmpty ? text : null,
      imageUrl: imageUrl,
    );

    if (!mounted) return;
    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
      return;
    }

    final data = result.data;
    if (data is Map<String, dynamic>) {
      final conversationId = int.tryParse(data['conversation_id']?.toString() ?? '') ?? 0;
      if (conversationId > 0 && _conversationId == null) {
        _conversationId = conversationId;
        // ignore: unawaited_futures
        try {
          _socketService.joinConversation(conversationId);
        } catch (e) {
          debugPrint('Lỗi join room socket khi gửi tin nhắn đầu tiên: $e');
        }
      }
      final messageData = data['message'];
      if (messageData is Map<String, dynamic>) {
        final message = ChatMessage.fromJson(messageData, widget.currentUserId);
        final alreadyExists = _messages.any((m) => m.id == message.id);
        if (!alreadyExists) {
          setState(() {
            _messages.add(message);
          });
          _scrollToBottom();
        }
        _messageController.clear();
      }
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (picked == null) return;
    final file = File(picked.path);
    final uploadResult = await _apiService.uploadImage(file);
    if (!mounted) return;
    if (!uploadResult.success) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(uploadResult.message)));
      return;
    }
    final imageUrl = uploadResult.data?['image_url']?.toString();
    if (imageUrl != null && imageUrl.isNotEmpty) {
      await _sendMessage(imageUrl: imageUrl);
    }
  }

  void _showEmojiSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111111),
      builder: (_) {
        final emojis = ['😀', '😍', '😘', '😁', '😂', '🥰', '🤔', '🙏', '🔥', '❤️'];
        return SizedBox(
          height: 180,
          child: GridView.count(
            crossAxisCount: 5,
            padding: const EdgeInsets.all(16),
            children: emojis.map((emoji) {
              return GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  _messageController.text = '${_messageController.text}$emoji';
                  _messageController.selection = TextSelection.fromPosition(
                    TextPosition(offset: _messageController.text.length),
                  );
                },
                child: Center(
                  child: Text(
                    emoji,
                    style: const TextStyle(fontSize: 30),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildBubble(ChatMessage message) {
    final isMe = message.isMe;
    final bubbleColor = isMe ? const Color(0xFF5B4BFF) : const Color(0xFF1D1D1D);
    final textColor = Colors.white;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isMe ? 18 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message.imageUrl != null && message.imageUrl!.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.network(
                    message.imageUrl!,
                    fit: BoxFit.cover,
                    cacheWidth: 800,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            value: loadingProgress.expectedTotalBytes != null
                                ? loadingProgress.cumulativeBytesLoaded / (loadingProgress.expectedTotalBytes ?? 1)
                                : null,
                            color: Colors.white,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              if (message.imageUrl != null && message.imageUrl!.isNotEmpty)
                const SizedBox(height: 10),
              if (message.text != null && message.text!.isNotEmpty)
                Text(
                  message.text!,
                  style: GoogleFonts.manrope(color: textColor, fontSize: 15, height: 1.4),
                ),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatTime(message.createdAt),
                    style: GoogleFonts.manrope(color: Colors.white70, fontSize: 11),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 8),
                    Text(
                      message.status == 'seen' ? 'Đã xem' : 'Đã gửi',
                      style: GoogleFonts.manrope(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final localTime = dateTime.toLocal();
    final hours = localTime.hour.toString().padLeft(2, '0');
    final minutes = localTime.minute.toString().padLeft(2, '0');
    return '$hours:$minutes';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080808),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFF222222),
              backgroundImage: widget.recipientAvatarUrl != null
                  ? NetworkImage(widget.recipientAvatarUrl!)
                  : null,
              child: widget.recipientAvatarUrl == null
                  ? Text(
                      widget.recipientName.isEmpty
                          ? 'U'
                          : widget.recipientName[0].toUpperCase(),
                      style: GoogleFonts.manrope(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.recipientName,
                    style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _statusText,
                    style: GoogleFonts.manrope(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Column(
                      children: [
                        Expanded(
                          child: ListView.builder(
                            controller: _scrollController,
                            itemCount: _messages.length,
                            itemBuilder: (context, index) => _buildBubble(_messages[index]),
                          ),
                        ),
                        if (_isTyping)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Đang nhập...',
                                style: GoogleFonts.manrope(color: Colors.white54, fontSize: 13),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
          Container(
            color: const Color(0xFF111111),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
            child: Row(
              children: [
                IconButton(
                  onPressed: _showEmojiSheet,
                  icon: const Icon(Icons.emoji_emotions_outlined, color: Colors.white70),
                ),
                IconButton(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.photo, color: Colors.white70),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    minLines: 1,
                    maxLines: 4,
                    style: GoogleFonts.manrope(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Nhập tin nhắn...',
                      hintStyle: GoogleFonts.manrope(color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF1B1B1B),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => _sendMessage(),
                  child: Container(
                    height: 48,
                    width: 48,
                    decoration: const BoxDecoration(
                      color: Color(0xFF5B4BFF),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.send_rounded, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
