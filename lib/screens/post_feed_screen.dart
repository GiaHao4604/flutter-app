import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_application_1/screens/chat_screen.dart';
import 'package:flutter_application_1/services/auth_api_service.dart';
import 'package:flutter_application_1/services/auth_session_service.dart';
import 'package:flutter_application_1/services/post_api_service.dart';

class PostFeedScreen extends StatefulWidget {
  const PostFeedScreen({super.key});

  @override
  State<PostFeedScreen> createState() => _PostFeedScreenState();
}

class _PostFeedScreenState extends State<PostFeedScreen> {
  final AuthSessionService _sessionService = AuthSessionService();
  final AuthApiService _authApiService = AuthApiService();
  final PostApiService _postApiService = PostApiService();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _posts = <Map<String, dynamic>>[];
  final Map<String, String> _localReactions = <String, String>{};

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  String? _error;
  static const int _pageSize = 8;

  String _currentUserName = 'Bạn';
  String? _currentUserAvatarUrl;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _loadProfileAndPosts(refresh: true);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients || _isLoadingMore || !_hasMore) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 360) {
      _loadMore();
    }
  }

  Future<void> _loadProfileAndPosts({bool refresh = false}) async {
    final token = await _sessionService.getToken();
    if (token == null || token.trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        _error = 'Bạn cần đăng nhập để xem bài viết.';
        _isLoading = false;
      });
      return;
    }

    try {
      final profile = await _authApiService.getMe(token: token);
      if (profile.success) {
        _currentUserName = profile.data?['name']?.toString().trim() ?? _currentUserName;
        _currentUserAvatarUrl = profile.data?['avatar_url']?.toString();
      }
    } catch (_) {}

    await _loadPosts(token: token, refresh: refresh);
  }

  Future<void> _loadMore() async {
    final token = await _sessionService.getToken();
    if (token == null || token.trim().isEmpty) return;
    await _loadPosts(token: token, refresh: false);
  }

  Future<void> _loadPosts({required String token, required bool refresh}) async {
    if (refresh) {
      if (!mounted) return;
      setState(() {
        _isLoading = true;
        _error = null;
        _page = 1;
        _hasMore = true;
        _posts.clear();
      });
    } else {
      if (_isLoading || _isLoadingMore || !_hasMore) return;
      if (!mounted) return;
      setState(() {
        _isLoadingMore = true;
      });
    }

    try {
      final result = await _postApiService.getPosts(
        token: token,
        page: _page,
        limit: _pageSize,
      );

      if (!mounted) return;

      if (!result.success) {
        setState(() {
          _error = result.message;
          _isLoading = false;
          _isLoadingMore = false;
        });
        return;
      }

      final rawData = result.data?['data'];
      final newPosts = rawData is List
          ? rawData.whereType<Map>().map((entry) => Map<String, dynamic>.from(entry)).toList()
          : <Map<String, dynamic>>[];

      setState(() {
        _posts.addAll(newPosts);
        _page += 1;
        _hasMore = newPosts.length >= _pageSize;
        _isLoading = false;
        _isLoadingMore = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  String _formatTime(String? value) {
    final dateTime = DateTime.tryParse(value ?? '');
    if (dateTime == null) return 'vừa xong';
    final diff = DateTime.now().difference(dateTime.toLocal());
    if (diff.inMinutes < 1) return 'vừa xong';
    if (diff.inHours < 1) return '${diff.inMinutes} phút trước';
    if (diff.inDays < 1) return '${diff.inHours} giờ trước';
    if (diff.inDays < 7) return '${diff.inDays} ngày trước';
    return '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.year}';
  }

  Future<void> _openChat(Map<String, dynamic> post) async {
    final user = post['user'] is Map ? Map<String, dynamic>.from(post['user'] as Map) : <String, dynamic>{};
    final recipientName = (user['name']?.toString().trim().isNotEmpty ?? false)
        ? user['name'].toString().trim()
        : 'Người dùng';
    final recipientAvatarUrl = user['avatarUrl']?.toString();
    final initialMessage = post['caption']?.toString().trim();

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          recipientName: recipientName,
          recipientAvatarUrl: recipientAvatarUrl,
          initialMessage: initialMessage != null && initialMessage.isNotEmpty ? initialMessage : null,
        ),
      ),
    );
  }

  Future<String?> _showReactions() {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        const reactions = <Map<String, String>>[
          {'emoji': '❤️', 'label': 'Yêu thích'},
          {'emoji': '😂', 'label': 'Vui vẻ'},
          {'emoji': '😍', 'label': 'Thích'},
          {'emoji': '😮', 'label': 'Bất ngờ'},
          {'emoji': '😢', 'label': 'Buồn'},
        ];

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Wrap(
              runSpacing: 12,
              spacing: 12,
              children: reactions.map((reactionItem) {
                return InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => Navigator.pop(sheetContext, reactionItem['emoji']),
                  child: Container(
                    width: 96,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF202020),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(reactionItem['emoji']!, style: const TextStyle(fontSize: 28)),
                        const SizedBox(height: 8),
                        Text(
                          reactionItem['label']!,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.manrope(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080808),
      appBar: AppBar(
        backgroundColor: const Color(0xFF080808),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Bài viết',
          style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadProfileAndPosts(refresh: true),
        child: _isLoading && _posts.isEmpty
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : _error != null && _posts.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(24),
                    children: [
                      const SizedBox(height: 80),
                      Icon(
                        Icons.cloud_off_rounded,
                        color: Colors.white.withValues(alpha: 0.6),
                        size: 48,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Không tải được bài viết',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.manrope(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.manrope(
                          color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => _loadProfileAndPosts(refresh: true),
                        child: const Text('Thử lại'),
                      ),
                    ],
                  )
                : ListView.builder(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: _posts.length + 1,
                    itemBuilder: (context, index) {
                      if (index == _posts.length) {
                        if (_isLoadingMore) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: Colors.white.withValues(alpha: 0.7),
                              ),
                            ),
                          );
                        }

                        if (!_hasMore && _posts.isNotEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            child: Center(
                              child: Text(
                                'Đã xem hết bài viết',
                                style: GoogleFonts.manrope(
                                  color: Colors.white.withValues(alpha: 0.45),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          );
                        }

                        return const SizedBox(height: 12);
                      }

                      final post = _posts[index];
                      final postId = post['id']?.toString() ?? '$index';
                      final user = post['user'] is Map ? Map<String, dynamic>.from(post['user'] as Map) : <String, dynamic>{};
                      final authorName = user['name']?.toString().trim().isNotEmpty == true
                          ? user['name'].toString().trim()
                          : 'Người dùng';
                      final avatarUrl = PostApiService.resolveMediaUrl(user['avatarUrl']?.toString());
                      final caption = post['caption']?.toString().trim() ?? '';
                      final imageUrl = PostApiService.resolveMediaUrl(post['imageUrl']?.toString());
                      final reaction = _localReactions[postId];

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _PostCard(
                          authorName: authorName,
                          avatarUrl: avatarUrl,
                          timeLabel: _formatTime(post['createdAt']?.toString()),
                          caption: caption,
                          imageUrl: imageUrl,
                          reactionLabel: reaction,
                          onReactTap: () async {
                            final selected = await _showReactions();
                            if (!mounted || selected == null) return;
                            setState(() {
                              _localReactions[postId] = selected;
                            });
                          },
                          onMessageTap: () => _openChat(post),
                          currentUserName: _currentUserName,
                          currentUserAvatarUrl: _currentUserAvatarUrl,
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({
    required this.authorName,
    required this.avatarUrl,
    required this.timeLabel,
    required this.caption,
    required this.imageUrl,
    required this.reactionLabel,
    required this.onReactTap,
    required this.onMessageTap,
    required this.currentUserName,
    required this.currentUserAvatarUrl,
  });

  final String authorName;
  final String avatarUrl;
  final String timeLabel;
  final String caption;
  final String imageUrl;
  final String? reactionLabel;
  final VoidCallback onReactTap;
  final VoidCallback onMessageTap;
  final String currentUserName;
  final String? currentUserAvatarUrl;

  String _initials(String value) {
    final parts = value.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) return 'U';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final hasAvatar = avatarUrl.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hasAvatar ? Colors.transparent : Colors.white,
                    image: hasAvatar
                        ? DecorationImage(
                            image: NetworkImage(avatarUrl),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: !hasAvatar
                      ? Center(
                          child: Text(
                            _initials(authorName),
                            style: GoogleFonts.manrope(
                              color: const Color(0xFF5B4BFF),
                              fontWeight: FontWeight.w800,
                            ),
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
                        authorName == currentUserName ? 'Bạn' : authorName,
                        style: GoogleFonts.manrope(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        timeLabel,
                        style: GoogleFonts.manrope(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onMessageTap,
                  icon: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white),
                ),
              ],
            ),
          ),
          if (imageUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: AspectRatio(
                aspectRatio: 1,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.white.withValues(alpha: 0.05),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white.withValues(alpha: 0.45),
                        size: 40,
                      ),
                    );
                  },
                ),
              ),
            ),
          if (caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 2),
              child: Text(
                caption,
                style: GoogleFonts.manrope(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontSize: 14,
                  height: 1.35,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: onReactTap,
                  icon: Text(
                    reactionLabel ?? '🤍',
                    style: const TextStyle(fontSize: 18),
                  ),
                  label: Text(
                    reactionLabel == null ? 'Thả cảm xúc' : reactionLabel!,
                    style: GoogleFonts.manrope(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: onMessageTap,
                  icon: const Icon(Icons.send_outlined, color: Colors.white),
                ),
                IconButton(
                  onPressed: onMessageTap,
                  icon: const Icon(Icons.message_outlined, color: Colors.white),
                ),
                const Spacer(),
                Text(
                  'Gửi tin',
                  style: GoogleFonts.manrope(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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
