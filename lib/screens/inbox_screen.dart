import 'package:flutter/gestures.dart';
import 'package:flutter_application_1/services/api_config.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

import '../models/notification_model.dart';
import '../services/notification_api_service.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  List<NotificationModel> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchNotifications();
  }

  Future<void> _fetchNotifications() async {
    setState(() => _isLoading = true);
    final result = await NotificationApiService.getNotifications();
    if (result.success && result.data != null) {
      setState(() {
        _notifications = result.data!;
      });
    }
    setState(() => _isLoading = false);
  }

  Future<void> _markAsRead(NotificationModel notif) async {
    if (notif.isRead) return;
    final result = await NotificationApiService.markAsRead(notif.id);
    if (result.success) {
      setState(() {
        final index = _notifications.indexWhere((n) => n.id == notif.id);
        if (index != -1) {
          _notifications[index] = NotificationModel(
            id: notif.id,
            userId: notif.userId,
            title: notif.title,
            body: notif.body,
            isRead: true,
            createdAt: notif.createdAt,
          );
        }
      });
    }
  }

  void _showPostSnapshotDialog(Map<String, dynamic> snapshot) {
    final formatVnd = NumberFormat.decimalPattern('vi_VN');
    final amount = snapshot['amount'] != null ? int.tryParse(snapshot['amount'].toString()) ?? 0 : 0;
    
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (snapshot['image_url'] != null && snapshot['image_url'].toString().isNotEmpty)
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    child: Image.network(
                      '${ApiConfig.baseOrigin}${snapshot['image_url']}',
                      height: 200,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        height: 100,
                        color: Colors.white10,
                        child: const Center(child: Icon(Icons.broken_image, color: Colors.white30, size: 40)),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Chi tiết bài viết vi phạm',
                        style: GoogleFonts.manrope(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      if (snapshot['caption'] != null && snapshot['caption'].toString().isNotEmpty) ...[
                        Text('Nội dung:', style: GoogleFonts.manrope(color: Colors.white54, fontSize: 14)),
                        const SizedBox(height: 4),
                        Text(
                          snapshot['caption'].toString(),
                          style: GoogleFonts.manrope(color: Colors.white, fontSize: 15),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (snapshot['category_name'] != null) ...[
                        Text('Hạng mục:', style: GoogleFonts.manrope(color: Colors.white54, fontSize: 14)),
                        const SizedBox(height: 4),
                        Text(
                          snapshot['category_name'].toString(),
                          style: GoogleFonts.manrope(color: Colors.white, fontSize: 15),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (amount > 0) ...[
                        Text('Số tiền:', style: GoogleFonts.manrope(color: Colors.white54, fontSize: 14)),
                        const SizedBox(height: 4),
                        Text(
                          '${formatVnd.format(amount)} VND',
                          style: GoogleFonts.manrope(color: Colors.redAccent, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white10,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text('Đóng', style: GoogleFonts.manrope(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _onEmailTap(String email) async {
    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: email,
      query: 'subject=Hỗ trợ báo cáo bài viết&body=Xin chào đội ngũ hỗ trợ,\n\n',
    );

    try {
      if (await canLaunchUrl(emailLaunchUri)) {
        await launchUrl(emailLaunchUri);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Không thể mở ứng dụng gửi mail trên máy bạn.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: ${e.toString()}')),
        );
      }
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat('dd/MM/yyyy HH:mm').format(date);
  }

  List<TextSpan> _buildBodyTextSpans(String text) {
    // Basic parser to find emails and make them tappable
    final RegExp emailRegex = RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}');
    final matches = emailRegex.allMatches(text);
    
    if (matches.isEmpty) {
      return [TextSpan(text: text, style: const TextStyle(color: Colors.white70))];
    }

    final List<TextSpan> spans = [];
    int lastMatchEnd = 0;

    for (final match in matches) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(
          text: text.substring(lastMatchEnd, match.start),
          style: const TextStyle(color: Colors.white70),
        ));
      }
      
      final email = match.group(0)!;
      spans.add(TextSpan(
        text: email,
        style: const TextStyle(color: Colors.blueAccent, decoration: TextDecoration.underline),
        recognizer: TapGestureRecognizer()..onTap = () => _onEmailTap(email),
      ));

      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastMatchEnd),
        style: const TextStyle(color: Colors.white70),
      ));
    }

    return spans;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Hộp thư hệ thống',
          style: GoogleFonts.manrope(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox_rounded, size: 80, color: Colors.white.withValues(alpha: 0.2)),
                      const SizedBox(height: 16),
                      Text(
                        'Hộp thư trống',
                        style: GoogleFonts.manrope(color: Colors.white54, fontSize: 16),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  physics: const BouncingScrollPhysics(),
                  itemCount: _notifications.length,
                  itemBuilder: (context, index) {
                    final notif = _notifications[index];
                    return GestureDetector(
                      onTap: () => _markAsRead(notif),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: notif.isRead 
                              ? Colors.white.withValues(alpha: 0.05) 
                              : const Color(0xFF1E1E1E),
                          borderRadius: BorderRadius.circular(16),
                          border: notif.isRead 
                              ? null 
                              : Border.all(color: Colors.white.withValues(alpha: 0.15)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  notif.isRead ? Icons.mark_email_read_rounded : Icons.mark_email_unread_rounded,
                                  color: notif.isRead ? Colors.white30 : Colors.redAccent,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    notif.title,
                                    style: GoogleFonts.manrope(
                                      color: notif.isRead ? Colors.white54 : Colors.white,
                                      fontSize: 16,
                                      fontWeight: notif.isRead ? FontWeight.w500 : FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Text(
                                  _formatDate(notif.createdAt),
                                  style: GoogleFonts.manrope(
                                    color: Colors.white30,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            RichText(
                              text: TextSpan(
                                style: GoogleFonts.manrope(fontSize: 14, height: 1.5),
                                children: _buildBodyTextSpans(notif.body),
                              ),
                            ),
                            if (notif.postSnapshot != null) ...[
                              const SizedBox(height: 16),
                              Align(
                                alignment: Alignment.centerRight,
                                child: InkWell(
                                  onTap: () {
                                    _markAsRead(notif);
                                    _showPostSnapshotDialog(notif.postSnapshot!);
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.white24),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.info_outline_rounded, color: Colors.white, size: 16),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Xem chi tiết',
                                          style: GoogleFonts.manrope(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
