import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_application_1/screens/chat_detail_screen.dart';
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
  late PageController _pageController;
  final List<Map<String, dynamic>> _posts = <Map<String, dynamic>>[];
  final Map<String, String> _localReactions = <String, String>{};

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  String? _error;
  static const int _pageSize = 8;

  bool _showOnlyMine = false;
  int _currentPostIndex = 0;

  String _currentUserName = 'Bạn';
  String? _currentUserAvatarUrl;
  int? _currentUserId;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _pageController.addListener(_handlePageChange);
    _loadProfileAndPosts(refresh: true);
  }

  @override
  void dispose() {
    _pageController.removeListener(_handlePageChange);
    _pageController.dispose();
    super.dispose();
  }

  void _handlePageChange() {
    final newIndex = _pageController.page?.round() ?? 0;
    if (newIndex != _currentPostIndex) {
      setState(() {
        _currentPostIndex = newIndex;
      });
      // Load more posts when approaching the end
      if (newIndex >= _posts.length - 2 && _hasMore && !_isLoadingMore) {
        _loadMore();
      }
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
        _currentUserId = int.tryParse(profile.data?['id']?.toString() ?? '') ?? _currentUserId;
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
        my: _showOnlyMine,
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

  Future<void> _openChat(Map<String, dynamic> post, {String? replyMessage}) async {
    final author = post['author'] is Map ? Map<String, dynamic>.from(post['author'] as Map) : <String, dynamic>{};
    final recipientId = int.tryParse(author['id']?.toString() ?? '') ?? 0;
    final recipientName = (author['name']?.toString().trim().isNotEmpty ?? false)
        ? author['name'].toString().trim()
        : 'Người dùng';
    final recipientAvatarUrl = author['avatarUrl']?.toString();
    final initialMessage = replyMessage ?? post['caption']?.toString().trim();

    if (_currentUserId == null || _currentUserId == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không xác định được người dùng hiện tại.')));
      return;
    }
    if (recipientId == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không xác định được người nhận.')));
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatDetailScreen(
          currentUserId: _currentUserId!,
          conversationId: null,
          recipientId: recipientId,
          recipientName: recipientName,
          recipientAvatarUrl: recipientAvatarUrl,
          initialMessage: initialMessage != null && initialMessage.isNotEmpty ? initialMessage : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080808),
      body: Column(
        children: [
          // Header with toggle
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Bảng tin',
                    style: GoogleFonts.manrope(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ChoiceChip(
                        label: const Text('Tất cả'),
                        selected: !_showOnlyMine,
                        onSelected: (v) {
                          if (!_showOnlyMine) return;
                          setState(() {
                            _showOnlyMine = false;
                            _loadProfileAndPosts(refresh: true);
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Của tôi'),
                        selected: _showOnlyMine,
                        onSelected: (v) {
                          if (_showOnlyMine) return;
                          setState(() {
                            _showOnlyMine = true;
                            _loadProfileAndPosts(refresh: true);
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Main content
          Expanded(
            child: _isLoading && _posts.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                : _error != null && _posts.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.cloud_off_rounded,
                              color: Colors.white.withValues(alpha: 0.6),
                              size: 48,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Không tải được bài viết',
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
                        ),
                      )
                    : _posts.isEmpty
                        ? Center(
                            child: Text(
                              'Chưa có bài viết',
                              style: GoogleFonts.manrope(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 16,
                              ),
                            ),
                          )
                        : Stack(
                            children: [
                              PageView.builder(
                                controller: _pageController,
                                itemCount: _posts.length,
                                itemBuilder: (context, index) {
                                  final post = _posts[index];
                                  final postId = post['id']?.toString() ?? '$index';
                                  final author = post['author'] is Map
                                      ? Map<String, dynamic>.from(post['author'] as Map)
                                      : <String, dynamic>{};
                                  final authorId = int.tryParse(author['id']?.toString() ?? '');
                                  final authorName = (author['name']?.toString().trim().isNotEmpty ?? false)
                                      ? author['name'].toString().trim()
                                      : 'Người dùng';
                                  final avatarUrl = PostApiService.resolveMediaUrl(author['avatarUrl']?.toString());
                                  final caption = post['caption']?.toString().trim() ?? '';
                                  final imageUrl = PostApiService.resolveMediaUrl(post['imageUrl']?.toString());
                                  final reaction = _localReactions[postId];
                                  // Fix: so sánh bằng ID thay vì tên để tránh nhầm lẫn khi 2 user trùng tên
                                  final isMyPost = _currentUserId != null && authorId != null && authorId == _currentUserId;

                                  return _FullscreenPostCard(
                                    authorName: authorName,
                                    avatarUrl: avatarUrl,
                                    timeLabel: _formatTime(post['createdAt']?.toString()),
                                    caption: caption,
                                    imageUrl: imageUrl,
                                    reactionLabel: reaction,
                                    isMyPost: isMyPost,
                                    onMessageTap: (replyText) => _openChat(post, replyMessage: replyText),
                                    currentUserName: _currentUserName,
                                    currentUserAvatarUrl: _currentUserAvatarUrl,
                                  );

                                },
                              ),
                              // Position indicator at the top
                              if (_posts.isNotEmpty)
                                Positioned(
                                  top: 16,
                                  left: 0,
                                  right: 0,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: List.generate(
                                        _posts.length,
                                        (index) => Expanded(
                                          child: Container(
                                            height: 3,
                                            margin: const EdgeInsets.symmetric(horizontal: 4),
                                            decoration: BoxDecoration(
                                              color: index == _currentPostIndex
                                                  ? Colors.white
                                                  : Colors.white.withValues(alpha: 0.3),
                                              borderRadius: BorderRadius.circular(2),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
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

class _FullscreenPostCard extends StatefulWidget {
  const _FullscreenPostCard({
    required this.authorName,
    required this.avatarUrl,
    required this.timeLabel,
    required this.caption,
    required this.imageUrl,
    required this.reactionLabel,
    required this.isMyPost,
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
  final bool isMyPost;
  final void Function(String message) onMessageTap;
  final String currentUserName;
  final String? currentUserAvatarUrl;

  @override
  State<_FullscreenPostCard> createState() => _FullscreenPostCardState();
}

class _FullscreenPostCardState extends State<_FullscreenPostCard> {
  late TextEditingController _messageController;

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  String _initials(String value) {
    final parts = value.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) return 'U';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final hasAvatar = widget.avatarUrl.trim().isNotEmpty;

    return GestureDetector(
      onTap: () {}, // Prevent accidental taps
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background image
          if (widget.imageUrl.isNotEmpty)
            Image.network(
              widget.imageUrl,
              fit: BoxFit.cover,
              cacheWidth: 800, // Giới hạn kích thước decode ảnh để tránh tràn RAM (màn hình đen)
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: Colors.white.withValues(alpha: 0.05),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white.withValues(alpha: 0.45),
                    size: 60,
                  ),
                );
              },
            ),
          // Dark gradient overlay on top
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.7),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Dark gradient overlay on bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 300,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.98),
                    Colors.black.withValues(alpha: 0.85),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // User info at top
          Positioned(
            top: 44,
            left: 16,
            right: 16,
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hasAvatar ? Colors.transparent : Colors.white,
                    image: hasAvatar
                        ? DecorationImage(
                            image: ResizeImage(NetworkImage(widget.avatarUrl), width: 120),
                            fit: BoxFit.cover,
                          )
                        : null,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                      width: 2,
                    ),
                  ),
                  child: !hasAvatar
                      ? Center(
                          child: Text(
                            _initials(widget.authorName),
                            style: GoogleFonts.manrope(
                              color: const Color(0xFF5B4BFF),
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
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
                        widget.authorName == widget.currentUserName ? 'Bạn' : widget.authorName,
                        style: GoogleFonts.manrope(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.timeLabel,
                        style: GoogleFonts.manrope(
                          color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Caption at bottom
          if (widget.caption.isNotEmpty)
            Positioned(
              bottom: 156,
              left: 16,
              right: 16,
              child: Text(
                widget.caption,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.manrope(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
            ),
          if (!widget.isMyPost)
            Positioned(
              bottom: 100,
              left: 16,
              right: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: const [
                  Text(
                    'Nhấn gửi để trả lời',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          // Message input box at bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: widget.isMyPost
                    ? Container(
                        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(
                          mainAxisAlignment: widget.reactionLabel == null
                              ? MainAxisAlignment.center
                              : MainAxisAlignment.start,
                          children: [
                            if (widget.reactionLabel != null) ...[
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withValues(alpha: 0.15),
                                ),
                                child: const Icon(
                                  Icons.person,
                                  color: Colors.white70,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                widget.reactionLabel!,
                                style: GoogleFonts.manrope(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ] else ...[
                              Text(
                                'Chưa có hoạt động nào',
                                style: GoogleFonts.manrope(
                                  color: Colors.white.withValues(alpha: 0.75),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.15),
                                ),
                              ),
                              child: TextField(
                                controller: _messageController,
                                style: GoogleFonts.manrope(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Trả lời...',
                                  hintStyle: GoogleFonts.manrope(
                                    color: Colors.white.withValues(alpha: 0.5),
                                    fontSize: 14,
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                ),
                                cursorColor: Colors.white,
                                maxLines: 1,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: () {
                              final text = _messageController.text.trim();
                              if (text.isNotEmpty) {
                                _messageController.clear();
                                widget.onMessageTap(text);
                              }
                            },
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Icon(
                                Icons.send_rounded,
                                color: Colors.white.withValues(alpha: 0.8),
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

