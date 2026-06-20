import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/models/chat_models.dart';
import 'package:flutter_application_1/services/chat_api_service.dart';
import 'package:flutter_application_1/services/post_api_service.dart';
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
    this.sharedPostId,
  });

  final int currentUserId;
  final int? conversationId;
  final int recipientId;
  final String recipientName;
  final String? recipientAvatarUrl;
  final String? initialMessage;
  final int? sharedPostId;

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final ChatApiService _apiService = ChatApiService();
  final SocketService _socketService = SocketService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  List<ChatMessage> _messages = [];
  bool _isLoading = true;
  bool _isTyping = false;
  String _statusText = 'Offline';
  int? _conversationId;
  StreamSubscription<Map<String, dynamic>>? _messageSub;
  StreamSubscription<Map<String, dynamic>>? _typingSub;
  StreamSubscription<Map<String, dynamic>>? _presenceSub;
  StreamSubscription<Map<String, dynamic>>? _messageDeletedSub;
  ChatMessage? _replyingToMessage;

  @override
  void initState() {
    super.initState();
    _conversationId = widget.conversationId;
    if (widget.initialMessage != null && widget.initialMessage!.isNotEmpty) {
      _messageController.text = widget.initialMessage!;
    }
    _initializeChat();
    _messageController.addListener(_onTextChanged);
    // Auto-gửi bài viết chia sẻ ngay khi mở chat
    if (widget.sharedPostId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _sendMessage(sharedPostId: widget.sharedPostId);
      });
    }
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    _typingSub?.cancel();
    _presenceSub?.cancel();
    _messageDeletedSub?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
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
              if (message.isMe) {
                final tempIndex = _messages.indexWhere((m) => 
                  m.isMe && 
                  m.status == 'sending' && 
                  m.text == message.text && 
                  m.imageUrl == message.imageUrl &&
                  m.replyTo?.id == message.replyTo?.id
                );
                if (tempIndex != -1) {
                  _messages.removeAt(tempIndex);
                }
              }
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

    _messageDeletedSub = _socketService.onMessageDeleted.listen((event) {
      final messageId = int.tryParse(event['message_id']?.toString() ?? '') ?? 0;
      if (messageId > 0) {
        setState(() {
          final index = _messages.indexWhere((m) => m.id == messageId);
          if (index != -1) {
            final old = _messages[index];
            _messages[index] = ChatMessage(
              id: old.id,
              conversationId: old.conversationId,
              senderId: old.senderId,
              text: null,
              imageUrl: null,
              sharedPost: null,
              isSeen: old.isSeen,
              createdAt: old.createdAt,
              isMe: old.isMe,
              status: old.status,
              isDeleted: true,
              replyTo: old.replyTo,
            );
          }
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

  Future<void> _sendMessage({String? imageUrl, int? sharedPostId, bool includeText = true}) async {
    final text = includeText ? _messageController.text.trim() : '';
    if (text.isEmpty && (imageUrl == null || imageUrl.isEmpty) && sharedPostId == null) return;

    final currentReplyTo = _replyingToMessage;
    final tempId = DateTime.now().millisecondsSinceEpoch;
    final tempMessage = ChatMessage(
      id: tempId,
      conversationId: _conversationId ?? 0,
      senderId: widget.currentUserId,
      text: text.isNotEmpty ? text : null,
      imageUrl: imageUrl,
      isSeen: false,
      createdAt: DateTime.now(),
      isMe: true,
      status: 'sending',
      replyTo: currentReplyTo != null ? ReplyToMessage(
        id: currentReplyTo.id, 
        text: currentReplyTo.previewText, 
        senderName: currentReplyTo.isMe ? 'Bạn' : widget.recipientName,
      ) : null,
    );

    setState(() {
      _messages.add(tempMessage);
      if (includeText) {
        _replyingToMessage = null;
      }
    });
    if (includeText) {
      _messageController.clear();
    }
    _scrollToBottom();

    final result = await _apiService.sendMessage(
      conversationId: _conversationId,
      recipientId: widget.recipientId,
      message: text.isNotEmpty ? text : null,
      imageUrl: imageUrl,
      sharedPostId: sharedPostId,
      replyToId: currentReplyTo?.id,
    );

    if (!mounted) return;
    if (!result.success) {
      setState(() {
        final index = _messages.indexWhere((m) => m.id == tempId);
        if (index != -1) {
          _messages[index] = ChatMessage(
            id: tempId,
            conversationId: tempMessage.conversationId,
            senderId: tempMessage.senderId,
            text: tempMessage.text,
            imageUrl: tempMessage.imageUrl,
            isSeen: tempMessage.isSeen,
            createdAt: tempMessage.createdAt,
            isMe: tempMessage.isMe,
            status: 'failed',
          );
        }
      });
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
        setState(() {
          _messages.removeWhere((m) => m.id == tempId);
          final alreadyExists = _messages.any((m) => m.id == message.id);
          if (!alreadyExists) {
            _messages.add(message);
          }
        });
        _scrollToBottom();
      }
    }
  }

  Future<void> _pickImage() async {
    FocusScope.of(context).unfocus();
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
    final data = uploadResult.data;
    String? imageUrl = (data?['image_url'] ?? data?['imageUrl'])?.toString();
    if (imageUrl == null && data?['data'] is Map) {
      final innerData = data!['data'] as Map;
      imageUrl = (innerData['image_url'] ?? innerData['imageUrl'])?.toString();
    }
    
    if (imageUrl != null && imageUrl.isNotEmpty) {
      await _sendMessage(imageUrl: imageUrl, includeText: false);
    }
  }

  void _showEmojiSheet() {
    FocusScope.of(context).unfocus();
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

  Widget _buildContextMenuItem({
    required String title, 
    required IconData icon, 
    required VoidCallback onTap, 
    bool isDestructive = false
  }) {
    final color = isDestructive ? const Color(0xFFFF3B30) : Colors.white;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: GoogleFonts.manrope(color: color, fontSize: 17)),
            Icon(icon, color: color, size: 22),
          ],
        ),
      ),
    );
  }

  void _showOverlayMenu(ChatMessage message, Rect rect, Widget bubbleWidget) {
    if (message.isDeleted) return;

    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      pageBuilder: (overlayContext, animation, secondaryAnimation) {
        final screenHeight = MediaQuery.of(context).size.height;
        final screenWidth = MediaQuery.of(context).size.width;
        // Chiều cao menu ước tính khoảng 110px
        final showAbove = rect.bottom > screenHeight - 150;

        return FadeTransition(
          opacity: animation,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
              children: [
                // 1. Lớp nền làm mờ (Blur)
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.pop(overlayContext);
                      _focusNode.unfocus();
                    },
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: Container(color: Colors.black.withOpacity(0.3)),
                    ),
                  ),
                ),
                // 2. Bong bóng chat bật ra nguyên vị trí
                Positioned(
                  top: rect.top,
                  left: rect.left,
                  width: rect.width,
                  child: Material(
                    color: Colors.transparent,
                    child: bubbleWidget,
                  ),
                ),
                // 3. Menu tuỳ chọn
                Positioned(
                  top: showAbove ? null : rect.bottom + 8,
                  bottom: showAbove ? screenHeight - rect.top + 8 : null,
                  left: message.isMe ? null : rect.left,
                  right: message.isMe ? screenWidth - rect.right : null,
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      width: 250,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildContextMenuItem(
                            title: 'Trả lời',
                            icon: Icons.reply_rounded,
                            onTap: () {
                              Navigator.pop(overlayContext);
                              setState(() {
                                _replyingToMessage = message;
                              });
                              _focusNode.requestFocus();
                            },
                          ),
                          if (message.isMe) ...[
                            const Divider(height: 1, color: Colors.white12),
                            _buildContextMenuItem(
                              title: 'Xóa',
                              icon: Icons.delete_outline_rounded,
                              isDestructive: true,
                              onTap: () async {
                                Navigator.pop(overlayContext);
                                _focusNode.unfocus();
                                final res = await _apiService.deleteMessage(message.id);
                                if (res.success) {
                                  setState(() {
                                    final index = _messages.indexWhere((m) => m.id == message.id);
                                    if (index != -1) {
                                      final old = _messages[index];
                                      _messages[index] = ChatMessage(
                                        id: old.id,
                                        conversationId: old.conversationId,
                                        senderId: old.senderId,
                                        text: null,
                                        imageUrl: null,
                                        sharedPost: null,
                                        isSeen: old.isSeen,
                                        createdAt: old.createdAt,
                                        isMe: old.isMe,
                                        status: old.status,
                                        isDeleted: true,
                                        replyTo: old.replyTo,
                                      );
                                    }
                                  });
                                } else {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.message)));
                                  }
                                }
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ));
  }

  Widget _buildBubble(ChatMessage message) {
    final isMe = message.isMe;
    final bubbleColor = message.isDeleted ? const Color(0xFF2A2A2A) : (isMe ? Colors.white : const Color(0xFF1D1D1D));
    final textColor = message.isDeleted ? Colors.white54 : (isMe ? Colors.black : Colors.white);
    final isFailed = message.status == 'failed';
    final isLastMessage = _messages.isNotEmpty && _messages.last.id == message.id;

    final hasSharedPost = !message.isDeleted && message.sharedPost != null;
    final hasText = !message.isDeleted && message.text != null && message.text!.isNotEmpty;
    final hasImage = !message.isDeleted && message.imageUrl != null && message.imageUrl!.isNotEmpty;
    final hasReply = !message.isDeleted && message.replyTo != null;

    final bubbleContent = Column(
      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
              if (hasReply) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 4, left: 8, right: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.reply_rounded, color: Colors.white54, size: 14),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          isMe 
                            ? 'Bạn đã trả lời ${message.replyTo!.senderName == 'Bạn' ? 'chính mình' : message.replyTo!.senderName}'
                            : '${widget.recipientName} đã trả lời ${message.replyTo!.senderName == widget.recipientName ? 'chính mình' : 'bạn'}',
                          style: GoogleFonts.manrope(color: Colors.white54, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(bottom: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF222222),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    message.replyTo!.text,
                    style: GoogleFonts.manrope(color: Colors.white60, fontSize: 14),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              if (hasSharedPost) ...[
              _buildSharedPostCard(message.sharedPost!, isMe, message.createdAt),
              if (hasText || hasImage) const SizedBox(height: 4),
            ],
            if (hasImage)
              Container(
                margin: const EdgeInsets.symmetric(vertical: 2),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.network(
                    PostApiService.resolveMediaUrl(message.imageUrl!),
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
              ),
            if (hasText || message.isDeleted)
              Container(
                margin: const EdgeInsets.symmetric(vertical: 2),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  border: isFailed ? Border.all(color: Colors.redAccent, width: 1.5) : null,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  message.isDeleted ? 'Tin nhắn đã thu hồi' : message.text!,
                  style: GoogleFonts.manrope(
                    color: textColor, 
                    fontSize: 15, 
                    height: 1.4,
                    fontStyle: message.isDeleted ? FontStyle.italic : null,
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(message.createdAt),
                  style: GoogleFonts.manrope(color: Colors.white70, fontSize: 11),
                ),
                if (isFailed) ...[
                  const SizedBox(width: 8),
                  Text(
                    'Gửi thất bại',
                    style: GoogleFonts.manrope(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ] else if (isMe && isLastMessage && message.status != 'sending') ...[
                  const SizedBox(width: 8),
                  Text(
                    message.status == 'seen' || message.isSeen ? 'Đã xem' : 'Đã gửi',
                    style: GoogleFonts.manrope(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ],
            ),
      ],
    );

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        child: Builder(
          builder: (context) {
            return GestureDetector(
              onLongPress: () {
                if (message.isDeleted || isFailed || message.status == 'sending') return;
                final renderBox = context.findRenderObject() as RenderBox?;
                if (renderBox != null) {
                  final offset = renderBox.localToGlobal(Offset.zero);
                  final rect = offset & renderBox.size;
                  _showOverlayMenu(message, rect, bubbleContent);
                }
              },
              child: bubbleContent,
            );
          },
        ),
      ),
    );
  }

  Widget _buildSharedPostCard(SharedPost post, bool isMe, DateTime messageCreatedAt) {
    final hasImage = post.imageUrl != null && post.imageUrl!.isNotEmpty;
    // authorId of the post vs currentUserId
    final authorName = (post.authorId == widget.currentUserId) ? "You" : (post.authorName ?? 'Người dùng');
    
    // Format date as "4 thg 6" using the post's createdAt, fallback to messageCreatedAt
    final postDate = post.createdAt ?? messageCreatedAt;
    final dateLabel = '${postDate.day} thg ${postDate.month}';
    
    return GestureDetector(
      onTap: () {},
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 120),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.1),
          ),
          child: Stack(
            children: [
              // Ảnh nền
              if (hasImage)
                AspectRatio(
                  aspectRatio: 1.0,
                  child: Image.network(
                    PostApiService.resolveMediaUrl(post.imageUrl!),
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, _, _) => Container(
                      color: Colors.white10,
                      child: const Center(child: Icon(Icons.broken_image_outlined, color: Colors.white38, size: 40)),
                    ),
                  ),
                )
              else
                Container(
                  height: 160,
                  color: Colors.white10,
                  child: const Center(child: Icon(Icons.image_not_supported_outlined, color: Colors.white38, size: 32)),
                ),
              
              // Top-Left Pill Overlay
              Positioned(
                top: 12,
                left: 12,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 10,
                            backgroundImage: (post.authorAvatar != null && post.authorAvatar!.isNotEmpty)
                                ? NetworkImage(PostApiService.resolveMediaUrl(post.authorAvatar!))
                                : null,
                            backgroundColor: Colors.white24,
                            child: (post.authorAvatar == null || post.authorAvatar!.isEmpty)
                                ? const Icon(Icons.person, size: 10, color: Colors.white70)
                                : null,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            authorName,
                            style: GoogleFonts.manrope(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            dateLabel,
                            style: GoogleFonts.manrope(
                              color: Colors.white54,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Bottom Center Caption Overlay
              if (post.caption != null && post.caption!.isNotEmpty)
                Positioned(
                  bottom: 16,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                          ),
                          child: Text(
                            post.caption!,
                            style: GoogleFonts.manrope(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final localTime = dateTime.toLocal();
    final now = DateTime.now();

    final hours = localTime.hour.toString().padLeft(2, '0');
    final minutes = localTime.minute.toString().padLeft(2, '0');

    if (localTime.year == now.year && localTime.month == now.month && localTime.day == now.day) {
      return '$hours:$minutes';
    } else {
      return '$hours:$minutes, ${localTime.day} THG ${localTime.month}';
    }
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
                  ? NetworkImage(PostApiService.resolveMediaUrl(widget.recipientAvatarUrl!))
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
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Column(
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_replyingToMessage != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B1B1B),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.reply, color: Colors.white54, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Đang trả lời ${_replyingToMessage!.isMe ? 'chính mình' : widget.recipientName}',
                                style: GoogleFonts.manrope(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _replyingToMessage!.previewText,
                                style: GoogleFonts.manrope(color: Colors.white54, fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _replyingToMessage = null;
                            });
                          },
                          child: const Icon(Icons.close, color: Colors.white54, size: 20),
                        ),
                      ],
                    ),
                  ),
                Row(
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
                    focusNode: _focusNode,
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
          ],
        ),
      ),
          ],
        ),
      ),
    );
  }
}
