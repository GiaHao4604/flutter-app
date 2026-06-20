import 'dart:convert';

class NotificationModel {
  final int id;
  final int userId;
  final String title;
  final String body;
  final bool isRead;
  final DateTime createdAt;
  final Map<String, dynamic>? postSnapshot;

  NotificationModel({
    required this.id,
    required this.userId,
    required this.title,
    required this.body,
    required this.isRead,
    required this.createdAt,
    this.postSnapshot,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? parsedSnapshot;
    if (json['post_snapshot'] != null) {
      if (json['post_snapshot'] is String) {
        try {
          parsedSnapshot = jsonDecode(json['post_snapshot']);
        } catch (e) {
          // parse error
        }
      } else if (json['post_snapshot'] is Map) {
        parsedSnapshot = Map<String, dynamic>.from(json['post_snapshot']);
      }
    }

    return NotificationModel(
      id: json['id'] as int? ?? 0,
      userId: json['user_id'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      isRead: (json['is_read'] == 1 || json['is_read'] == true),
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at']).toLocal() 
          : DateTime.now(),
      postSnapshot: parsedSnapshot,
    );
  }
}
