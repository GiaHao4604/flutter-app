import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_application_1/screens/chat_detail_screen.dart';
import 'package:flutter_application_1/services/auth_api_service.dart';
import 'package:flutter_application_1/services/auth_session_service.dart';
import 'package:flutter_application_1/services/post_api_service.dart';
import 'package:flutter_application_1/services/post_upload_manager.dart';
import 'package:flutter_application_1/services/calendar_refresh_notifier.dart';

class PostFeedScreen extends StatefulWidget {
  const PostFeedScreen({super.key, this.verticalPageController, this.onScrollDirectionChanged});
  final PageController? verticalPageController;
  final ValueChanged<bool>? onScrollDirectionChanged;

  @override
  State<PostFeedScreen> createState() => _PostFeedScreenState();
}

class _PostFeedScreenState extends State<PostFeedScreen> {
  final AuthSessionService _sessionService = AuthSessionService();
  final AuthApiService _authApiService = AuthApiService();
  final PostApiService _postApiService = PostApiService();
  late ScrollController _scrollController;
  bool _showHeader = true;
  double _lastScrollOffset = 0.0;
  final List<Map<String, dynamic>> _posts = <Map<String, dynamic>>[];

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  String? _error;
  static const int _pageSize = 8;

  bool _showOnlyMine = false;

  String _currentUserName = 'Bạn';
  String? _currentUserRole;
  String? _currentUserAvatarUrl;
  int? _currentUserId;

  @override
  void initState() {
    super.initState();
    PostUploadManager.instance.init();
    _scrollController = ScrollController();
    _scrollController.addListener(_scrollListener);
    _loadProfileAndPosts(refresh: true);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollListener() {
    final currentOffset = _scrollController.offset;
    
    // Drag down significantly at the top of the feed to return to Home/Camera
    if (currentOffset < -50 && widget.verticalPageController != null) {
      if (widget.verticalPageController!.hasClients && widget.verticalPageController!.page == 1) {
        widget.verticalPageController!.animateToPage(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    }
    
    // Hide/show header logic on scroll direction change
    if (currentOffset <= 0) {
      if (!_showHeader) {
        setState(() {
          _showHeader = true;
        });
        widget.onScrollDirectionChanged?.call(true);
      }
    } else if (currentOffset - _lastScrollOffset > 15 && _showHeader) {
      setState(() {
        _showHeader = false;
      });
      widget.onScrollDirectionChanged?.call(false);
    } else if (_lastScrollOffset - currentOffset > 15 && !_showHeader) {
      setState(() {
        _showHeader = true;
      });
      widget.onScrollDirectionChanged?.call(true);
    }
    _lastScrollOffset = currentOffset;

    // Load more when reaching near the bottom of ListView
    if (_scrollController.position.maxScrollExtent > 0) {
      final threshold = _scrollController.position.maxScrollExtent - 400;
      if (currentOffset >= threshold && _hasMore && !_isLoadingMore) {
        _loadMore();
      }
    }
  }

  String _getDateKey(String? value) {
    final dateTime = DateTime.tryParse(value ?? '');
    if (dateTime == null) return 'unknown';
    final local = dateTime.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  String _formatDateLabel(String? value) {
    final dateTime = DateTime.tryParse(value ?? '');
    if (dateTime == null) return 'vừa xong';
    final local = dateTime.toLocal();
    final now = DateTime.now();
    
    if (local.year == now.year && local.month == now.month && local.day == now.day) {
      return 'Hôm nay';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (local.year == yesterday.year && local.month == yesterday.month && local.day == yesterday.day) {
      return 'Hôm qua';
    }
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
  }

  List<Map<String, dynamic>> _groupPosts(List<Map<String, dynamic>> rawPosts) {
    final List<Map<String, dynamic>> grouped = [];
    
    for (final post in rawPosts) {
      final author = post['author'] is Map ? Map<String, dynamic>.from(post['author'] as Map) : <String, dynamic>{};
      final authorId = author['id']?.toString() ?? 'unknown';
      final dateKey = _getDateKey(post['createdAt']?.toString());
      
      Map<String, dynamic>? targetGroup;
      for (final g in grouped) {
        if (g['authorId'] == authorId && g['dateKey'] == dateKey) {
          targetGroup = g;
          break;
        }
      }
      
      if (targetGroup != null) {
        (targetGroup['posts'] as List<Map<String, dynamic>>).add(post);
      } else {
        grouped.add({
          'authorId': authorId,
          'authorName': (author['name']?.toString().trim().isNotEmpty ?? false)
              ? author['name'].toString().trim()
              : 'Người dùng',
          'avatarUrl': PostApiService.resolveMediaUrl(author['avatarUrl']?.toString()),
          'dateKey': dateKey,
          'timeLabel': _formatDateLabel(post['createdAt']?.toString()),
          'posts': <Map<String, dynamic>>[post],
        });
      }
    }
    return grouped;
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

    await Future.wait([
      _authApiService.getMe(token: token).then((profile) {
        if (profile.success) {
          if (!mounted) return;
          setState(() {
            _currentUserName = profile.data?['name']?.toString().trim() ?? _currentUserName;
            _currentUserAvatarUrl = profile.data?['avatar_url']?.toString();
            _currentUserId = int.tryParse(profile.data?['id']?.toString() ?? '') ?? _currentUserId;
            _currentUserRole = profile.data?['role']?.toString();
          });
        }
      }).catchError((_) {}),
      _loadPosts(token: token, refresh: refresh),
    ]);
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


  Future<void> _openChat(Map<String, dynamic> post, {String? replyMessage}) async {
    final author = post['author'] is Map ? Map<String, dynamic>.from(post['author'] as Map) : <String, dynamic>{};
    final recipientId = int.tryParse(author['id']?.toString() ?? '') ?? 0;
    final recipientName = (author['name']?.toString().trim().isNotEmpty ?? false)
        ? author['name'].toString().trim()
        : 'Người dùng';
    final recipientAvatarUrl = author['avatarUrl']?.toString();
    final initialMessage = replyMessage ?? '';
    final postId = int.tryParse(post['id']?.toString() ?? '') ?? 0;

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
          initialMessage: initialMessage.isNotEmpty ? initialMessage : null,
          sharedPostId: postId > 0 ? postId : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080808),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (widget.verticalPageController != null && widget.verticalPageController!.hasClients) {
            widget.verticalPageController!.animateToPage(
              0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          }
        },
        child: Stack(
          children: [
          // 1. Main scrollable content
          Positioned.fill(
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
                        : ValueListenableBuilder<List<Map<String, dynamic>>>(
                            valueListenable: PostUploadManager.instance.pendingUploads,
                            builder: (context, pending, child) {
                              final List<Map<String, dynamic>> allUnified = [];

                              // Add pending uploads
                              for (final ghost in pending) {
                                allUnified.add({
                                  'id': null,
                                  'caption': ghost['caption']?.toString() ?? '',
                                  'imageUrl': '',
                                  'localImagePath': ghost['imagePath']?.toString() ?? '',
                                  'createdAt': DateTime.now().toUtc().toIso8601String(),
                                  'author': {
                                    'id': _currentUserId,
                                    'name': _currentUserName,
                                    'avatarUrl': _currentUserAvatarUrl,
                                  },
                                  'syncStatus': ghost['status']?.toString() ?? 'pending',
                                  'errorMessage': ghost['errorMessage']?.toString(),
                                  'localId': ghost['localId'],
                                });
                              }

                              // Add real posts
                              allUnified.addAll(_posts);

                              final groupedList = _groupPosts(allUnified);

                              if (groupedList.isEmpty) {
                                return Center(
                                  child: Text(
                                    'Chưa có bài viết',
                                    style: GoogleFonts.manrope(
                                      color: Colors.white.withValues(alpha: 0.6),
                                      fontSize: 16,
                                    ),
                                  ),
                                );
                              }

                              return CustomScrollView(
                                controller: _scrollController,
                                physics: const BouncingScrollPhysics(),
                                slivers: [
                                  SliverAppBar(
                                    floating: true,
                                    snap: true,
                                    backgroundColor: const Color(0xFF080808).withValues(alpha: 0.85),
                                    elevation: 0,
                                    flexibleSpace: ClipRect(
                                      child: BackdropFilter(
                                        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                                        child: Container(color: Colors.transparent),
                                      ),
                                    ),
                                    title: Text(
                                      'MoneyLife',
                                      style: GoogleFonts.outfit(
                                        color: Colors.white,
                                        fontSize: 24,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    actions: [
                                      Theme(
                                        data: Theme.of(context).copyWith(
                                          cardColor: const Color(0xFF1E1E1E),
                                        ),
                                        child: PopupMenuButton<bool>(
                                          initialValue: _showOnlyMine,
                                          onSelected: (bool mine) {
                                            if (mine == _showOnlyMine) return;
                                            setState(() {
                                              _showOnlyMine = mine;
                                              _loadProfileAndPosts(refresh: true);
                                            });
                                          },
                                          offset: const Offset(0, 40),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(16),
                                            side: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 1),
                                          ),
                                          itemBuilder: (context) => [
                                            PopupMenuItem<bool>(
                                              value: false,
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.all_inclusive_rounded,
                                                    color: !_showOnlyMine ? const Color(0xFF9B51E0) : Colors.white70,
                                                    size: 20,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    'Tất cả bài viết',
                                                    style: GoogleFonts.manrope(
                                                      color: !_showOnlyMine ? const Color(0xFF9B51E0) : Colors.white,
                                                      fontWeight: !_showOnlyMine ? FontWeight.bold : FontWeight.normal,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            PopupMenuItem<bool>(
                                              value: true,
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.person_rounded,
                                                    color: _showOnlyMine ? const Color(0xFF9B51E0) : Colors.white70,
                                                    size: 20,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    'Bài viết của tôi',
                                                    style: GoogleFonts.manrope(
                                                      color: _showOnlyMine ? const Color(0xFF9B51E0) : Colors.white,
                                                      fontWeight: _showOnlyMine ? FontWeight.bold : FontWeight.normal,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(alpha: 0.08),
                                              borderRadius: BorderRadius.circular(20),
                                              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  _showOnlyMine ? 'Của tôi' : 'Tất cả',
                                                  style: GoogleFonts.manrope(
                                                    color: Colors.white,
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                Icon(
                                                  Icons.keyboard_arrow_down_rounded,
                                                  color: Colors.white.withValues(alpha: 0.8),
                                                  size: 18,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                    ],
                                  ),
                                  SliverPadding(
                                    padding: const EdgeInsets.only(
                                      top: 0,
                                      bottom: 90, // Safe padding for Bottom Bar
                                    ),
                                    sliver: SliverList(
                                      delegate: SliverChildBuilderDelegate(
                                        (context, index) {
                                          final group = groupedList[index];
                                          final groupPosts = List<Map<String, dynamic>>.from(group['posts']);
                                          
                                          return Padding(
                                            padding: const EdgeInsets.only(bottom: 24),
                                            child: _FullscreenPostCard(
                                              authorName: group['authorName'],
                                              avatarUrl: group['avatarUrl'],
                                              timeLabel: group['timeLabel'],
                                              posts: groupPosts,
                                              currentUserName: _currentUserName,
                                              currentUserAvatarUrl: _currentUserAvatarUrl,
                                              currentUserRole: _currentUserRole,
                                              isMyPostsTab: _showOnlyMine,
                                              onPostDeleted: () {
                                                _loadProfileAndPosts(refresh: true);
                                              },
                                              onMessageTap: (subPost, replyText) => _openChat(subPost, replyMessage: replyText),
                                              onRetry: () {
                                                PostUploadManager.instance.retryAll();
                                              },
                                              onDelete: (localId) {
                                                PostUploadManager.instance.deleteFailedUpload(localId);
                                              },
                                            ),
                                          );
                                        },
                                        childCount: groupedList.length,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
          ),
          
          
          ],
        ),
      ),
    );
  }
}

class _FullscreenPostCard extends StatefulWidget {
  const _FullscreenPostCard({
    required this.authorName,
    required this.avatarUrl,
    required this.timeLabel,
    required this.posts,
    required this.currentUserName,
    required this.currentUserAvatarUrl,
    this.currentUserRole,
    this.onPostDeleted,
    this.onMessageTap,
    this.onRetry,
    this.onDelete,
    this.isMyPostsTab = false,
  });

  final String authorName;
  final String avatarUrl;
  final String timeLabel;
  final List<Map<String, dynamic>> posts;
  final String currentUserName;
  final String? currentUserAvatarUrl;
  final String? currentUserRole;
  final VoidCallback? onPostDeleted;
  final void Function(Map<String, dynamic> post, String message)? onMessageTap;
  final VoidCallback? onRetry;
  final void Function(String localId)? onDelete;
  final bool isMyPostsTab;

  @override
  State<_FullscreenPostCard> createState() => _FullscreenPostCardState();
}

class _FullscreenPostCardState extends State<_FullscreenPostCard> {
  late TextEditingController _messageController;
  late PageController _pageController;
  int _currentSubIndex = 0;
  final AuthSessionService _sessionService = AuthSessionService();
  final PostApiService _postApiService = PostApiService();
  Timer? _timeRefreshTimer;

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController();
    _pageController = PageController();
    _pageController.addListener(_handlePageChange);
    // Refresh time label every minute
    _timeRefreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timeRefreshTimer?.cancel();
    _messageController.dispose();
    _pageController.removeListener(_handlePageChange);
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _FullscreenPostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.posts.length != oldWidget.posts.length) {
      final newIndex = _currentSubIndex.clamp(0, widget.posts.length - 1);
      if (newIndex != _currentSubIndex) {
        setState(() {
          _currentSubIndex = newIndex;
        });
      }
    }
  }

  void _handlePageChange() {
    if (!_pageController.hasClients) return;
    final idx = _pageController.page?.round() ?? 0;
    if (idx != _currentSubIndex) {
      setState(() {
        _currentSubIndex = idx;
      });
    }
  }

  String _formatTimeAgo(String? value) {
    final dateTime = DateTime.tryParse(value ?? '');
    if (dateTime == null) return widget.timeLabel;
    final local = dateTime.toLocal();
    final now = DateTime.now();
    final difference = now.difference(local);

    if (difference.isNegative || difference.inSeconds < 60) {
      return 'vừa xong';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} phút trước';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} giờ trước';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} ngày trước';
    } else {
      return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year} lúc ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }
  }

  void _showPostActionMenu(BuildContext context, Map<String, dynamic> currentPost) {
    final postId = currentPost['id'] is int ? currentPost['id'] as int : int.tryParse(currentPost['id']?.toString() ?? '');
    final isMyPost = widget.authorName == widget.currentUserName;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (modalContext) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E1E),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                if (isMyPost || widget.currentUserRole == 'admin' || widget.currentUserRole == 'director_admin')
                  ListTile(
                    leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    title: Text(
                      'Xóa bài viết',
                      style: GoogleFonts.manrope(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(modalContext);
                      _confirmDelete(context, postId);
                    },
                  )
                else
                  ListTile(
                    leading: const Icon(Icons.outlined_flag, color: Colors.orangeAccent),
                    title: Text(
                      'Báo cáo bài viết',
                      style: GoogleFonts.manrope(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(modalContext);
                      _showReportDialog(context, postId);
                    },
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context, int? postId) async {
    if (postId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: Text(
            'Xóa bài viết?',
            style: GoogleFonts.manrope(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Bạn có chắc chắn muốn xóa bài viết này không? Mọi thông tin lịch chi tiêu, thống kê và ngân sách liên quan đến ảnh này cũng sẽ bị xóa.',
            style: GoogleFonts.manrope(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text('Hủy', style: GoogleFonts.manrope(color: Colors.white38)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text('Xóa', style: GoogleFonts.manrope(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đang xóa bài viết...'),
          duration: Duration(days: 365),
        ),
      );

      final token = await _sessionService.getToken();
      if (token == null || token.trim().isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vui lòng đăng nhập lại để thực hiện')),
        );
        return;
      }

      final res = await _postApiService.deletePost(token: token, postId: postId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (res.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã xóa bài viết thành công')),
        );
        
        try {
          calendarRefreshNotifier.value++;
        } catch (_) {}

        if (widget.onPostDeleted != null) {
          widget.onPostDeleted!();
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi xóa bài viết: ${res.message}')),
        );
      }
    }
  }

  Future<void> _showReportDialog(BuildContext context, int? postId) async {
    if (postId == null) return;
    final reasonController = TextEditingController(text: 'Nội dung không phù hợp');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: Text(
            'Báo cáo bài viết',
            style: GoogleFonts.manrope(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Nhập lý do báo cáo bài viết này:',
                style: GoogleFonts.manrope(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                style: GoogleFonts.manrope(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Lý do báo cáo...',
                  hintStyle: GoogleFonts.manrope(color: Colors.white38),
                  enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white70),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text('Hủy', style: GoogleFonts.manrope(color: Colors.white38)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text('Báo cáo', style: GoogleFonts.manrope(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      final reason = reasonController.text.trim();
      if (reason.isEmpty) return;

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đang gửi báo cáo...'),
          duration: Duration(days: 365),
        ),
      );

      final token = await _sessionService.getToken();
      if (token == null || token.trim().isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vui lòng đăng nhập để thực hiện')),
        );
        return;
      }

      final res = await _postApiService.reportPost(
        token: token,
        postId: postId,
        reason: reason,
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (res.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cảm ơn bạn đã báo cáo. Admin sẽ kiểm duyệt bài viết này.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi báo cáo: ${res.message}')),
        );
      }
    }
  }

  String _initials(String value) {
    final parts = value.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) return 'U';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  Widget _buildCategoryIconWidget(String? key, {double size = 20}) {
    if (key == null || key.isEmpty) {
      return Icon(Icons.category_outlined, size: size, color: Colors.white70);
    }
    final runes = key.runes.toList();
    final isEmoji = runes.isNotEmpty && runes.first > 0xFF;
    if (isEmoji) {
      return Text(
        key,
        style: TextStyle(fontSize: size * 0.85, height: 1),
        textAlign: TextAlign.center,
      );
    }

    final legacyMap = {
      'ic_food': '🍔', 'food': '🍔',
      'ic_car': '🚗', 'car': '🚗',
      'ic_shop': '🛒', 'shop': '🛒',
      'ic_health': '💊', 'health': '💊',
      'ic_bill': '💰', 
      'ic_home': '🏠', 'home': '🏠',
      'ic_game': '🎮',
      'ic_flight': '✈️',
      'ic_money': '💰',
      'ic_gift': '🎁',
    };

    final emoji = legacyMap[key];
    if (emoji != null) {
      return Text(
        emoji,
        style: TextStyle(fontSize: size * 0.85, height: 1),
        textAlign: TextAlign.center,
      );
    }

    IconData iconData = Icons.category_outlined;
    if (key.contains('food')) {
      iconData = Icons.restaurant_rounded;
    } else if (key.contains('car') || key.contains('transport')) {
      iconData = Icons.directions_car_rounded;
    } else if (key.contains('shop')) {
      iconData = Icons.shopping_bag_rounded;
    } else if (key.contains('health') || key.contains('medical')) {
      iconData = Icons.medical_services_rounded;
    } else if (key.contains('home') || key.contains('house')) {
      iconData = Icons.home_rounded;
    } else if (key.contains('salary') || key.contains('income')) {
      iconData = Icons.monetization_on_rounded;
    }

    return Icon(iconData, size: size, color: Colors.white);
  }

  String _formatCurrency(double amount) {
    final parts = amount.round().toString().split('');
    final result = [];
    for (int i = 0; i < parts.length; i++) {
      if (i > 0 && (parts.length - i) % 3 == 0) {
        result.add('.');
      }
      result.add(parts[i]);
    }
    return '${result.join('')}đ';
  }

  Future<void> _handleReactionToggle(int? postId, String emoji) async {
    if (postId == null) return;
    final token = await _sessionService.getToken();
    if (token == null || token.isEmpty) return;

    final index = widget.posts.indexWhere((p) => p['id'] == postId || p['id']?.toString() == postId.toString());
    if (index == -1) return;

    // Lạc quan cập nhật UI trước (Optimistic UI Update) giúp phản hồi mượt như Instagram
    final currentPost = widget.posts[index];
    final oldReaction = currentPost['myReaction'];
    final oldLatest = currentPost['latestReaction'];
    
    setState(() {
      if (oldReaction == emoji) {
        currentPost['myReaction'] = null;
      } else {
        currentPost['myReaction'] = emoji;
        currentPost['latestReaction'] = {
          'reactorName': widget.currentUserName,
          'reactorAvatarUrl': widget.currentUserAvatarUrl,
          'reactionIcon': emoji,
        };
      }
    });
    
    final res = await _postApiService.reactPost(
      token: token,
      postId: postId,
      reactionIcon: emoji,
    );
    
    if (!res.success) {
      // Nếu API lỗi, khôi phục lại trạng thái cũ
      if (mounted) {
        setState(() {
          currentPost['myReaction'] = oldReaction;
          currentPost['latestReaction'] = oldLatest;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: ${res.message}')),
        );
      }
    }
  }

  Future<void> _showReactionsList(int postId) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return FutureBuilder<PostApiResult>(
          future: _sessionService.getToken().then((token) =>
              _postApiService.getPostReactions(token: token ?? '', postId: postId)),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator(color: Color(0xFF9B51E0))),
              );
            }
            if (!snapshot.hasData || !snapshot.data!.success) {
              return const SizedBox(
                height: 200,
                child: Center(child: Text('Không thể tải danh sách', style: TextStyle(color: Colors.white54))),
              );
            }
            final decodedMap = snapshot.data!.data;
            final data = (decodedMap?['data'] as List<dynamic>?) ?? [];
            if (data.isEmpty) {
              return const SizedBox(
                height: 200,
                child: Center(child: Text('Chưa có cảm xúc nào', style: TextStyle(color: Colors.white54))),
              );
            }
            
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Lượt cảm xúc',
                  style: GoogleFonts.manrope(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.builder(
                    itemCount: data.length,
                    itemBuilder: (context, index) {
                      final item = data[index];
                      final name = item['reactorName']?.toString() ?? 'Người dùng';
                      final avatarUrl = PostApiService.resolveMediaUrl(item['reactorAvatarUrl']?.toString());
                      final icon = item['reactionIcon']?.toString() ?? '❤️';
                      
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.white24,
                          backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                          child: avatarUrl.isEmpty
                              ? Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                                  style: const TextStyle(color: Colors.white),
                                )
                              : null,
                        ),
                        title: Text(
                          name,
                          style: GoogleFonts.manrope(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        trailing: Text(
                          icon,
                          style: const TextStyle(fontSize: 20),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDotsIndicator(int count, int currentIndex) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        count,
        (index) => AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: index == currentIndex ? 8 : 6,
          height: index == currentIndex ? 8 : 6,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: index == currentIndex
                ? const Color(0xFF9B51E0) // Purple
                : const Color(0xFF9B51E0).withValues(alpha: 0.3), // Translucent Purple
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.posts.isEmpty) return const SizedBox.shrink();

    final safeSubIndex = _currentSubIndex.clamp(0, widget.posts.length - 1);
    final currentPost = widget.posts[safeSubIndex];

    final postId = currentPost['id'] is int ? currentPost['id'] as int : int.tryParse(currentPost['id']?.toString() ?? '');
    final isMyPost = widget.authorName == widget.currentUserName;

    // Financial
    final categoryName = currentPost['categoryName']?.toString();
    final categoryIconKey = currentPost['categoryIconKey']?.toString();
    final transactionAmount = currentPost['transactionAmount'] != null ? (currentPost['transactionAmount'] as num).toDouble() : null;
    final transactionIsExpense = currentPost['transactionIsExpense'];

    // Reaction details
    final myReaction = currentPost['myReaction']?.toString();
    final reactorName = currentPost['latestReaction']?['reactorName']?.toString();
    final reactorAvatarUrl = PostApiService.resolveMediaUrl(currentPost['latestReaction']?['reactorAvatarUrl']?.toString());
    final reactionIcon = currentPost['latestReaction']?['reactionIcon']?.toString();
    final secondReactorName = currentPost['secondReaction']?['reactorName']?.toString();
    final secondReactorAvatarUrl = PostApiService.resolveMediaUrl(currentPost['secondReaction']?['reactorAvatarUrl']?.toString());
    final secondReactionIcon = currentPost['secondReaction']?['reactionIcon']?.toString() ?? '❤️';

    final hasAvatar = widget.avatarUrl.trim().isNotEmpty;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Photo card with height ~580 and PageView inside
          Stack(
            children: [
              Container(
                height: 490,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                ),
                clipBehavior: Clip.antiAlias,
                  child: PageView.builder(
                    controller: _pageController,
                    physics: widget.posts.length > 1
                        ? const BouncingScrollPhysics()
                        : const NeverScrollableScrollPhysics(),
                    itemCount: widget.posts.length,
                    itemBuilder: (context, subIndex) {
                      final subPost = widget.posts[subIndex];
                      
                      final subImageUrl = PostApiService.resolveMediaUrl(subPost['imageUrl']?.toString());
                      final subLocalImagePath = subPost['localImagePath']?.toString() ?? subPost['imagePath']?.toString();
                      final subCaption = subPost['caption']?.toString().trim() ?? '';
                      final subSyncStatus = subPost['syncStatus']?.toString() ?? subPost['status']?.toString();
                      final subErrorMessage = subPost['errorMessage']?.toString();

                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          if (subLocalImagePath != null && subLocalImagePath.isNotEmpty)
                            Image.file(
                              File(subLocalImagePath),
                              fit: BoxFit.cover,
                            )
                          else if (subImageUrl.isNotEmpty)
                            Image.network(
                              subImageUrl,
                              fit: BoxFit.cover,
                              cacheWidth: 800,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  alignment: Alignment.center,
                                  child: Icon(
                                    Icons.broken_image_outlined,
                                    color: Colors.white.withValues(alpha: 0.45),
                                    size: 50,
                                  ),
                                );
                              },
                            )
                          else
                            Container(
                              color: Colors.white.withValues(alpha: 0.05),
                              alignment: Alignment.center,
                              child: const CircularProgressIndicator(color: Colors.white),
                            ),
                          
                          // Caption Capsule Overlay
                          if (subCaption.isNotEmpty)
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: BackdropFilter(
                                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.5),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Flexible(
                                            child: Text(
                                              subCaption,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.manrope(
                                                color: Colors.white70,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          
                          // Ghost Post upload overlay
                          if (subSyncStatus != null)
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                ),
                                child: Center(
                                  child: subSyncStatus == 'error'
                                      ? Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.cloud_off_rounded,
                                              color: Colors.redAccent,
                                              size: 48,
                                            ),
                                            const SizedBox(height: 12),
                                            Text(
                                              'Lỗi tải lên bài viết',
                                              style: GoogleFonts.manrope(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            if (subErrorMessage != null && subErrorMessage.isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(top: 8, left: 16, right: 16),
                                                child: Text(
                                                  subErrorMessage,
                                                  textAlign: TextAlign.center,
                                                  style: GoogleFonts.manrope(
                                                    color: Colors.white70,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ),
                                            const SizedBox(height: 24),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                TextButton.icon(
                                                  onPressed: () {
                                                    widget.onDelete?.call(subPost['localId']?.toString() ?? '');
                                                  },
                                                  icon: const Icon(Icons.delete_outline, color: Colors.white70),
                                                  label: const Text('Hủy', style: TextStyle(color: Colors.white70)),
                                                  style: TextButton.styleFrom(
                                                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                                                  ),
                                                ),
                                                const SizedBox(width: 16),
                                                ElevatedButton.icon(
                                                  onPressed: widget.onRetry,
                                                  icon: const Icon(Icons.refresh),
                                                  label: const Text('Thử lại'),
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: const Color(0xFF5B4BFF),
                                                    foregroundColor: Colors.white,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        )
                                      : Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const CircularProgressIndicator(
                                              color: Colors.white,
                                            ),
                                            const SizedBox(height: 16),
                                            Text(
                                              'Đang tải lên...',
                                              style: GoogleFonts.manrope(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                
                // 3. Top shadow gradient for author info readability
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 90,
                  child: IgnorePointer(
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black54,
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // 4. Author info overlay inside the photo at the top
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
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
                              color: Colors.white.withValues(alpha: 0.2),
                              width: 1.5,
                            ),
                          ),
                          child: !hasAvatar
                              ? Center(
                                  child: Text(
                                    _initials(widget.authorName),
                                    style: GoogleFonts.manrope(
                                      color: const Color(0xFF5B4BFF),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
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
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  shadows: [
                                    const Shadow(
                                      offset: Offset(0, 1),
                                      blurRadius: 3,
                                      color: Colors.black45,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _formatTimeAgo(currentPost['createdAt']?.toString()),
                                style: GoogleFonts.manrope(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 11,
                                  shadows: [
                                    const Shadow(
                                      offset: Offset(0, 1),
                                      blurRadius: 2,
                                      color: Colors.black45,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (postId != null)
                          IconButton(
                            icon: const Icon(Icons.more_horiz, color: Colors.white, size: 22),
                            onPressed: () => _showPostActionMenu(context, currentPost),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            
            // Dots indicator (Only if more than 1 post in group)
            if (widget.posts.length > 1) ...[
              const SizedBox(height: 12),
              _buildDotsIndicator(widget.posts.length, safeSubIndex),
            ],
            
            // 3. Category & Price display (For post owner only AND only in "My Posts" tab)
            if (isMyPost && widget.isMyPostsTab && (categoryName != null || transactionAmount != null))
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF9B51E0).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF9B51E0).withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildCategoryIconWidget(categoryIconKey),
                          const SizedBox(width: 8),
                          Text(
                            categoryName ?? 'Hạng mục khác',
                            style: GoogleFonts.manrope(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (transactionAmount != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              width: 1,
                              height: 12,
                              color: Colors.white24,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _formatCurrency(transactionAmount),
                              style: GoogleFonts.manrope(
                                color: transactionIsExpense == true ? Colors.redAccent : Colors.greenAccent,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
            // 4. Reactions display or message input box
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: isMyPost
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (reactorName != null && reactionIcon != null)
                          GestureDetector(
                            onTap: () {
                              if (postId != null) _showReactionsList(postId);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2C2520),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                const Icon(
                                  Icons.auto_awesome,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Cảm xúc',
                                  style: GoogleFonts.manrope(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                if (secondReactorName != null)
                                  SizedBox(
                                    width: 48,
                                    height: 30,
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        // First avatar (left - reactor 1)
                                        Positioned(
                                          left: 0,
                                          top: 0,
                                          child: Stack(
                                            clipBehavior: Clip.none,
                                            children: [
                                              Container(
                                                width: 30,
                                                height: 30,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: reactorAvatarUrl.isNotEmpty
                                                      ? Colors.transparent
                                                      : Colors.white24,
                                                  border: Border.all(
                                                    color: const Color(0xFF2C2520),
                                                    width: 1.5,
                                                  ),
                                                  image: reactorAvatarUrl.isNotEmpty
                                                      ? DecorationImage(
                                                          image: NetworkImage(reactorAvatarUrl),
                                                          fit: BoxFit.cover,
                                                        )
                                                      : null,
                                                ),
                                                child: reactorAvatarUrl.isEmpty
                                                    ? Center(
                                                        child: Text(
                                                          _initials(reactorName),
                                                          style: GoogleFonts.manrope(
                                                            color: const Color(0xFF5B4BFF),
                                                            fontWeight: FontWeight.w800,
                                                            fontSize: 10,
                                                          ),
                                                        ),
                                                      )
                                                    : null,
                                              ),
                                              Positioned(
                                                bottom: -4,
                                                right: -4,
                                                child: Text(
                                                  reactionIcon,
                                                  style: const TextStyle(fontSize: 12),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Second avatar (right - reactor 2)
                                        Positioned(
                                          left: 16,
                                          top: 0,
                                          child: Stack(
                                            clipBehavior: Clip.none,
                                            children: [
                                              Container(
                                                width: 30,
                                                height: 30,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: secondReactorAvatarUrl.isNotEmpty
                                                      ? Colors.transparent
                                                      : Colors.white24,
                                                  border: Border.all(
                                                    color: const Color(0xFF2C2520),
                                                    width: 1.5,
                                                  ),
                                                  image: secondReactorAvatarUrl.isNotEmpty
                                                      ? DecorationImage(
                                                          image: NetworkImage(secondReactorAvatarUrl),
                                                          fit: BoxFit.cover,
                                                        )
                                                      : null,
                                                ),
                                                child: secondReactorAvatarUrl.isEmpty
                                                    ? Center(
                                                        child: Text(
                                                          _initials(secondReactorName),
                                                          style: GoogleFonts.manrope(
                                                            color: const Color(0xFF5B4BFF),
                                                            fontWeight: FontWeight.w800,
                                                            fontSize: 10,
                                                          ),
                                                        ),
                                                      )
                                                    : null,
                                              ),
                                              Positioned(
                                                bottom: -4,
                                                right: -4,
                                                child: Text(
                                                  secondReactionIcon,
                                                  style: const TextStyle(fontSize: 12),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      Container(
                                        width: 30,
                                        height: 30,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: reactorAvatarUrl.isNotEmpty
                                              ? Colors.transparent
                                              : Colors.white24,
                                          border: Border.all(
                                            color: const Color(0xFF2C2520),
                                            width: 1.5,
                                          ),
                                          image: reactorAvatarUrl.isNotEmpty
                                              ? DecorationImage(
                                                  image: NetworkImage(reactorAvatarUrl),
                                                  fit: BoxFit.cover,
                                                )
                                              : null,
                                        ),
                                        child: reactorAvatarUrl.isEmpty
                                            ? Center(
                                                child: Text(
                                                  _initials(reactorName),
                                                  style: GoogleFonts.manrope(
                                                    color: const Color(0xFF5B4BFF),
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 10,
                                                  ),
                                                ),
                                              )
                                            : null,
                                      ),
                                      Positioned(
                                        bottom: -4,
                                        right: -4,
                                        child: Text(
                                          reactionIcon,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),  // closes Container
                        )  // closes GestureDetector
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.08),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.auto_awesome,
                                  color: Colors.white.withValues(alpha: 0.3),
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Chưa có hoạt động nào',
                                  style: GoogleFonts.manrope(
                                    color: Colors.white.withValues(alpha: 0.4),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    )
                  : Row(
                      children: [
                        // Reaction Button next to message input
                        GestureDetector(
                          onTap: () {
                            if (postId != null) {
                              _handleReactionToggle(postId, '❤️');
                            }
                          },
                          child: AnimatedScale(
                            duration: const Duration(milliseconds: 150),
                            scale: (myReaction == '❤️') ? 1.2 : 1.0,
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: (myReaction == '❤️') 
                                    ? Colors.redAccent.withValues(alpha: 0.15) 
                                    : Colors.white.withValues(alpha: 0.08),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: (myReaction == '❤️') 
                                      ? Colors.redAccent.withValues(alpha: 0.5) 
                                      : Colors.white.withValues(alpha: 0.15),
                                ),
                              ),
                              child: Icon(
                                (myReaction == '❤️') 
                                    ? Icons.favorite_rounded 
                                    : Icons.favorite_border_rounded,
                                color: (myReaction == '❤️') 
                                    ? Colors.redAccent 
                                    : Colors.white70,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12),
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
                                  color: Colors.white.withValues(alpha: 0.45),
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
                              widget.onMessageTap?.call(currentPost, text);
                            }
                          },
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.2),
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
          ],
        ),
      );
  }
}
