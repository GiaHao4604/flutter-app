class ChatUser {
  const ChatUser({
    required this.id,
    required this.name,
    this.avatarUrl,
  });

  final int id;
  final String name;
  final String? avatarUrl;

  factory ChatUser.fromJson(Map<String, dynamic> json) {
    return ChatUser(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      name: json['partner_name']?.toString() ?? json['name']?.toString() ?? 'Người dùng',
      avatarUrl: json['partner_avatar']?.toString() ?? json['avatar_url']?.toString(),
    );
  }
}

class ChatConversation {
  const ChatConversation({
    required this.conversationId,
    required this.partner,
    required this.lastMessage,
    required this.lastMessageTime,
    required this.unreadCount,
    required this.hasImage,
  });

  factory ChatConversation.fromJson(Map<String, dynamic> json) {
    final lastMessage = json['last_message']?.toString() ?? '';
    final lastImage = json['last_image_url']?.toString();
    final preview = lastImage != null && lastImage.isNotEmpty ? '📷 Ảnh' : lastMessage;

    return ChatConversation(
      conversationId: int.tryParse(json['conversation_id']?.toString() ?? '') ?? 0,
      partner: ChatUser.fromJson(json),
      lastMessage: preview,
      lastMessageTime: json['last_message_at']?.toString() ?? '',
      unreadCount: int.tryParse(json['unread_count']?.toString() ?? '0') ?? 0,
      hasImage: lastImage != null && lastImage.isNotEmpty,
    );
  }

  final int conversationId;
  final ChatUser partner;
  final String lastMessage;
  final String lastMessageTime;
  final int unreadCount;
  final bool hasImage;
}

class SharedPost {
  const SharedPost({
    required this.id,
    this.imageUrl,
    this.caption,
    this.authorId,
    this.authorName,
    this.authorAvatar,
    this.createdAt,
  });

  final int id;
  final String? imageUrl;
  final String? caption;
  final int? authorId;
  final String? authorName;
  final String? authorAvatar;
  final DateTime? createdAt;

  factory SharedPost.fromJson(Map<String, dynamic> json) {
    return SharedPost(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      imageUrl: json['image_url']?.toString(),
      caption: json['caption']?.toString(),
      authorId: int.tryParse(json['author_id']?.toString() ?? ''),
      authorName: json['author_name']?.toString(),
      authorAvatar: json['author_avatar']?.toString(),
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString())?.toLocal() : null,
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    this.text,
    this.imageUrl,
    this.sharedPost,
    required this.isSeen,
    required this.createdAt,
    required this.isMe,
    this.status,
    this.isDeleted = false,
    this.replyTo,
  });

  final int id;
  final int conversationId;
  final int senderId;
  final String? text;
  final String? imageUrl;
  final SharedPost? sharedPost;
  final bool isSeen;
  final DateTime createdAt;
  final bool isMe;
  final String? status;
  final bool isDeleted;
  final ReplyToMessage? replyTo;

  factory ChatMessage.fromJson(Map<String, dynamic> json, int currentUserId) {
    final imageUrl = json['image_url']?.toString();
    final sharedPostData = json['shared_post'];
    return ChatMessage(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      conversationId: int.tryParse(json['conversation_id']?.toString() ?? '') ?? 0,
      senderId: int.tryParse(json['sender_id']?.toString() ?? '') ?? 0,
      text: json['text']?.toString() ?? json['message']?.toString(),
      imageUrl: imageUrl != null && imageUrl.isNotEmpty ? imageUrl : null,
      sharedPost: sharedPostData is Map<String, dynamic> ? SharedPost.fromJson(sharedPostData) : null,
      isSeen: json['is_seen'] == 1 || json['is_seen'] == true,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      isMe: int.tryParse(json['sender_id']?.toString() ?? '') == currentUserId,
      status: json['status']?.toString(),
      isDeleted: json['is_deleted'] == 1 || json['is_deleted'] == true,
      replyTo: json['reply_to'] != null ? ReplyToMessage.fromJson(json['reply_to']) : null,
    );
  }

  String get previewText {
    if (isDeleted) {
      return 'Tin nhắn đã thu hồi';
    }
    if (sharedPost != null) {
      return '📸 Đã chia sẻ một bài viết';
    }
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return '📷 Ảnh';
    }
    return text?.trim().isEmpty == true ? '...' : text ?? '';
  }
}

class ReplyToMessage {
  const ReplyToMessage({
    required this.id,
    required this.text,
    required this.senderName,
  });

  final int id;
  final String text;
  final String senderName;

  factory ReplyToMessage.fromJson(Map<String, dynamic> json) {
    return ReplyToMessage(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      text: json['text']?.toString() ?? '',
      senderName: json['sender_name']?.toString() ?? 'Người dùng',
    );
  }
}
