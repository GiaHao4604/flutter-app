import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_application_1/services/auth_api_service.dart';
import 'package:flutter_application_1/services/auth_session_service.dart';
import 'package:flutter_application_1/widgets/camera_preview_widget.dart';
import 'package:flutter_application_1/screens/calendar.dart';
import 'package:flutter_application_1/widgets/camera_action_button.dart';
import 'package:flutter_application_1/screens/post_feed_screen.dart';
import 'package:flutter_application_1/screens/chat_list_screen.dart';
import 'package:flutter_application_1/services/chat_api_service.dart';
import 'package:flutter_application_1/models/chat_models.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_application_1/screens/profile.dart'; 
import 'package:flutter_application_1/services/post_api_service.dart';
import 'package:flutter_application_1/services/socket_service.dart';
import 'package:flutter_application_1/services/notification_service.dart';
import 'package:flutter_application_1/services/notification_api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AuthApiService _authApiService = AuthApiService();
  final AuthSessionService _sessionService = AuthSessionService();

  bool _isLoading = true;
  int _selectedTab = 1; // Mặc định ở giữa (Trang 1 - Home/Camera)
  int? _userId;
  String _userInitials = 'U';
  String? _userAvatarUrl; // Lưu giữ link ảnh mạng (Ví dụ: http://...)
  
  // DỮ LIỆU TÀI KHOẢN THỰC TẾ LẤY TỪ API
  String _userName = 'Người Dùng';
  String _userEmail = 'user@gmail.com';

  final GlobalKey<CameraPreviewWidgetState> _cameraKey = GlobalKey<CameraPreviewWidgetState>();
  late PageController _pageController;
  late PageController _verticalPageController;
  int _verticalPage = 0;
  bool _showBottomBar = true;
  int _unreadCount = 0;
  final ChatApiService _chatApiService = ChatApiService();
  StreamSubscription? _systemNotifSub;


  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedTab);
    _verticalPageController = PageController(initialPage: 0);
    _loadProfile();
    _loadUnreadCount();
    _setupSocket();
    _checkMissedNotifications();
  }

  Future<void> _checkMissedNotifications() async {
    try {
      final result = await NotificationApiService.getNotifications();
      if (result.success && result.data != null) {
        final unreadNotifs = result.data!.where((n) => !n.isRead).toList();
        final prefs = await SharedPreferences.getInstance();
        
        for (final notif in unreadNotifs) {
          final key = 'notified_system_${notif.id}';
          if (prefs.getBool(key) != true) {
            NotificationService().showSystemNotification(notif.title, notif.body);
            await prefs.setBool(key, true);
          }
        }
      }
    } catch (e) {
      debugPrint('Lỗi kiểm tra thông báo lỡ: $e');
    }
  }

  Future<void> _setupSocket() async {
    final socketService = SocketService();
    try {
      await socketService.connect();
      _systemNotifSub = socketService.onSystemNotification.listen((data) {
        final title = data['title'] ?? 'Hộp thư hệ thống';
        final body = data['body'] ?? '';
        NotificationService().showSystemNotification(title.toString(), body.toString());
      });
    } catch (e) {
      debugPrint('Lỗi kết nối socket ở HomeScreen: $e');
    }
  }

  @override
  void dispose() {
    _systemNotifSub?.cancel();
    _pageController.dispose();
    _verticalPageController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final token = await _sessionService.getToken();

      if (token == null || token.trim().isEmpty) {
        if (!mounted) return;
        debugPrint("🔴 Không tìm thấy Token, chuyển hướng về Login");
        Navigator.pushReplacementNamed(context, '/login');
        return;
      }

      final result = await _authApiService.getMe(token: token);

      if (!mounted) return;

      if (!result.success) {
        debugPrint("🔴 API getMe thất bại: ${result.message}");
        // Nếu lỗi 401/403 (token hết hạn), redirect về login
        if (result.statusCode == 401 || result.statusCode == 403) {
          await _sessionService.clearToken();
          if (!mounted) return;
          Navigator.pushReplacementNamed(context, '/login');
          return;
        }
        // Lỗi mạng/server tạm thời — cho phép dùng offline
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Không thể tải thông tin: ${result.message}')),
          );
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      final name = (result.data?['name'] as String?)?.trim() ?? 'User';
      final email = (result.data?['email'] as String?)?.trim() ?? 'user@gmail.com';
      final avatar = result.data?['avatar_url'] as String?;
      final userId = int.tryParse(result.data?['id']?.toString() ?? '') ?? 0;
      await _sessionService.saveCurrentUserEmail(email);
      
      setState(() {
        _isLoading = false;
        _userId = userId > 0 ? userId : null;
        _userName = name;
        _userEmail = email;
        _userInitials = _buildInitials(name);
        _userAvatarUrl = avatar; // Nhận link ảnh đại diện từ database MySQL
      });
    } catch (e) {
      debugPrint("🔴 Lỗi hệ thống tại _loadProfile: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _buildInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'U';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  Future<void> _logout() async {
    await _sessionService.clearToken();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  Future<void> _loadUnreadCount() async {
    try {
      final result = await _chatApiService.getConversations();
      if (!mounted) return;
      if (result.success && result.data is List) {
        int total = 0;
        for (final item in result.data as List) {
          if (item is Map<String, dynamic>) {
            final conv = ChatConversation.fromJson(item);
            total += conv.unreadCount;
          }
        }
        if (mounted) {
          setState(() {
            _unreadCount = total;
          });
        }
      }
    } catch (_) {}
  }

  void _openProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Profile(
          userInitials: _userInitials,
          userName: _userName,
          userEmail: _userEmail,
          currentImageUrl: _userAvatarUrl, // Truyền link ảnh mạng sang bên trang Profile hiển thị
          onNameChanged: (newName) {
            setState(() {
              _userName = newName;
              _userInitials = _buildInitials(newName);
            });
          },
          onImageChanged: (newImageUrl) { 
            setState(() {
              _userAvatarUrl = newImageUrl; // Nhận lại link ảnh mới sau khi bên Profile upload xong
            });
          },
          onLogoutTap: _logout,
        ),
      ),
    );
  }

  void _handleNavTap(int index) {
    if (_verticalPage == 1) {
      setState(() {
        _selectedTab = index;
      });
      // Try to jump instantly if attached
      if (_pageController.hasClients) {
        _pageController.jumpToPage(index);
      }
      
      _verticalPageController.animateToPage(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      ).then((_) {
        // Ensure we end up on the correct tab if it wasn't attached earlier
        if (_pageController.hasClients && _pageController.page?.round() != index) {
          _pageController.jumpToPage(index);
        }
      });
    } else {
      setState(() {
        _selectedTab = index;
      });
      if (_pageController.hasClients) {
        _pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    }
    // Refresh unread count when tapping chat
    if (index == 2) {
      _loadUnreadCount();
    }
  }

  void _showFeed() {
    _verticalPageController.animateToPage(
      1,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF080808),
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    final systemBottomPadding = MediaQuery.viewPaddingOf(context).bottom;

    return Stack(
      children: [
        PageView(
          controller: _verticalPageController,
          scrollDirection: Axis.vertical,
          physics: (_selectedTab == 1 || _verticalPage == 1) 
              ? const BouncingScrollPhysics() 
              : const NeverScrollableScrollPhysics(),
          onPageChanged: (index) {
            setState(() {
              _verticalPage = index;
              if (index == 0) {
                _showBottomBar = true;
              }
            });
          },
          children: [
            Scaffold(
              extendBody: true,
              backgroundColor: const Color(0xFF080808),
              body: Stack(
                children: [
                  const _DarkBackground(),
                  PageView(
                    controller: _pageController,
                    onPageChanged: (index) {
                      setState(() {
                        _selectedTab = index;
                      });
                    },
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 120),
                        child: CalendarScreen(onBack: () => _handleNavTap(1)),
                      ),
                      _buildCameraPage(),
                      _buildChatPage(),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 120),
                        child: Profile(
                          userInitials: _userInitials,
                          userName: _userName,
                          userEmail: _userEmail,
                          currentImageUrl: _userAvatarUrl,
                          onNameChanged: (newName) {
                            setState(() {
                              _userName = newName;
                              _userInitials = _buildInitials(newName);
                            });
                          },
                          onImageChanged: (newImageUrl) { 
                            setState(() {
                              _userAvatarUrl = newImageUrl;
                            });
                          },
                          onLogoutTap: _logout,
                          onBack: () => _handleNavTap(2),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            PostFeedScreen(
              verticalPageController: _verticalPageController,
              onScrollDirectionChanged: (show) {
                if (_showBottomBar != show) {
                  setState(() {
                    _showBottomBar = show;
                  });
                }
              },
            ),
          ],
        ),
        // Persistent Navigation Bar & Arrow overlaying everything
        Align(
          alignment: Alignment.bottomCenter,
          child: AnimatedSlide(
            offset: Offset.zero,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: systemBottomPadding > 0 ? systemBottomPadding : 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _verticalPage == 0 ? 1.0 : 0.0,
                    child: IgnorePointer(
                      ignoring: _verticalPage != 0,
                      child: GestureDetector(
                        onTap: _showFeed,
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Colors.white.withValues(alpha: 0.8),
                          size: 30,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _BottomPill(
                    selectedIndex: _selectedTab,
                    onTap: _handleNavTap,
                    unreadCount: _unreadCount,
                    showAvatar: _verticalPage == 1 || _selectedTab == 0 || _selectedTab == 2,
                    userAvatarUrl: _userAvatarUrl,
                    userInitials: _userInitials,
                    onAvatarTap: _openProfile,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCameraPage() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 120),
        child: Column(
          children: [
            _TopBar(
              userInitials: _userInitials,
              userAvatarUrl: _userAvatarUrl, 
              onAvatarTap: _openProfile, 
            ).animate().fadeIn(duration: 250.ms).slideY(begin: -0.1, end: 0),

            const SizedBox(height: 22),

            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final previewHeight = constraints.maxHeight * 0.70;

                  return Column(
                    children: [
                      SizedBox(
                        width: MediaQuery.of(context).size.width,
                        child: CameraPreviewWidget(
                          key: _cameraKey,
                          height: previewHeight,
                        ),
                      ).animate().fadeIn(duration: 300.ms).scale(
                            begin: const Offset(0.96, 0.96),
                            end: const Offset(1, 1),
                          ),

                      const SizedBox(height: 30),

                      _ActionRow(
                        onGallery: () async {
                          await _cameraKey.currentState?.pickFromGallery();
                        },
                        onCapture: () => _cameraKey.currentState?.takePicture(),
                        onRefresh: () => _cameraKey.currentState?.switchCamera(),
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

  Widget _buildChatPage() {
    // Nếu vẫn đang loading thì hiển thị indicator
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 120),
        child: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    // Đã load xong nhưng không lấy được userId — hiển thị thông báo lỗi
    if (_userId == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 120),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_off_rounded, color: Colors.white38, size: 48),
              const SizedBox(height: 12),
              const Text(
                'Không thể tải thông tin người dùng',
                style: TextStyle(color: Colors.white54, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _loadProfile,
                child: const Text('Thử lại', style: TextStyle(color: Colors.white70)),
              ),
            ],
          ),
        ),
      );
    }

    return ChatListScreen(
      currentUserId: _userId!,
      onBack: () => _handleNavTap(1),
    );
  }
}

class _DarkBackground extends StatelessWidget {
  const _DarkBackground();
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF8C8C8C), // Bạc (Trắng xám)
            Color(0xFF1F1F1F), // Đen xám nhạt
            Color(0xFF000000), // Đen tuyền
          ],
          stops: [0.0, 0.4, 1.0],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.userInitials, 
    required this.userAvatarUrl, 
    required this.onAvatarTap
  });
  
  final String userInitials;
  final String? userAvatarUrl; 
  final VoidCallback onAvatarTap;

  @override
  Widget build(BuildContext context) {
    final resolvedUrl = (userAvatarUrl != null && userAvatarUrl!.trim().isNotEmpty)
        ? PostApiService.resolveMediaUrl(userAvatarUrl)
        : '';
    final hasAvatar = resolvedUrl.isNotEmpty;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          child: Icon(Icons.account_balance_wallet_outlined, color: Colors.white.withValues(alpha: 0.9), size: 26),
        ),
        GestureDetector(
          onTap: onAvatarTap,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hasAvatar ? Colors.transparent : Colors.white,
              boxShadow: [BoxShadow(color: Colors.white.withValues(alpha: 0.2), blurRadius: 10)],
              image: hasAvatar 
                  ? DecorationImage(
                      image: NetworkImage(resolvedUrl), 
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: !hasAvatar 
                ? Center(
                    child: Text(
                      userInitials,
                      style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w800, color: const Color(0xFF5B4BFF)),
                    ),
                  )
                : null, 
          ),
        ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.onGallery, required this.onCapture, required this.onRefresh});
  final VoidCallback onGallery;
  final VoidCallback onCapture;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CameraActionButton(icon: Icons.photo_library_outlined, onTap: onGallery),
        const SizedBox(width: 28),
        GestureDetector(
          onTap: onCapture,
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 4),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.36), blurRadius: 12, offset: const Offset(0, 8))],
            ),
            child: Center(
              child: Container(width: 68, height: 68, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white)),
            ),
          ),
        ),
        const SizedBox(width: 28),
        CameraActionButton(icon: Icons.cameraswitch_rounded, onTap: onRefresh),
      ],
    );
  }
}

class _BottomPill extends StatelessWidget {
  const _BottomPill({
    required this.selectedIndex,
    required this.onTap,
    required this.unreadCount,
    this.showAvatar = false,
    this.userAvatarUrl,
    this.userInitials = '',
    this.onAvatarTap,
  });

  final int selectedIndex;
  final ValueChanged<int> onTap;
  final String? userAvatarUrl;
  final String userInitials;
  final VoidCallback? onAvatarTap;
  final bool showAvatar;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    // Pill widens when avatar is visible
    final hasBadge = unreadCount > 0;
    double pillWidth = showAvatar ? 210 : 160;
    if (hasBadge) pillWidth += 10;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          width: pillWidth,
          height: 48,
          decoration: BoxDecoration(
            color: const Color.fromARGB(255, 70, 69, 69).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color.fromARGB(255, 70, 69, 69).withValues(alpha: 0.15),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.max,
            children: [
              _NavIcon(icon: Icons.calendar_month_rounded, selected: selectedIndex == 0, onTap: () => onTap(0)),
              const SizedBox(width: 14),
              _NavIcon(icon: Icons.home_outlined, selected: selectedIndex == 1, onTap: () => onTap(1)),
              const SizedBox(width: 12),
              _ChatNavIcon(selected: selectedIndex == 2, onTap: () => onTap(2), unreadCount: unreadCount),
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                child: SizedBox(
                  width: showAvatar ? 48 : 0, // 14 for spacing + 34 for avatar width
                  height: 34,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(width: 14),
                      Expanded(
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: showAvatar ? 1.0 : 0.0,
                          child: showAvatar
                              ? _AvatarNavIcon(
                                  avatarUrl: userAvatarUrl,
                                  userInitials: userInitials,
                                  onTap: onAvatarTap ?? () {},
                                  selected: selectedIndex == 3,
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AvatarNavIcon extends StatelessWidget {
  const _AvatarNavIcon({
    required this.avatarUrl,
    required this.userInitials,
    required this.onTap,
    required this.selected,
  });

  final String? avatarUrl;
  final String userInitials;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final resolvedUrl = (avatarUrl != null && avatarUrl!.trim().isNotEmpty)
        ? PostApiService.resolveMediaUrl(avatarUrl)
        : '';
    final hasAvatar = resolvedUrl.isNotEmpty;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 180),
        scale: selected ? 1.12 : 1.0,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? const Color(0xFFFFFFFF).withValues(alpha: 0.2) : Colors.transparent,
          ),
          alignment: Alignment.center,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hasAvatar ? Colors.transparent : Colors.white,
              border: Border.all(
                color: selected ? Colors.white : Colors.white.withValues(alpha: 0.3),
                width: 1.5,
              ),
              image: hasAvatar
                  ? DecorationImage(
                      image: NetworkImage(resolvedUrl),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: !hasAvatar
                ? Center(
                    child: Text(
                      userInitials,
                      style: GoogleFonts.manrope(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF5B4BFF),
                      ),
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

class _NavIcon extends StatelessWidget {
  const _NavIcon({required this.icon, required this.selected, required this.onTap});
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        duration: 180.ms,
        scale: selected ? 1.12 : 1.0,
        child: AnimatedContainer(
          duration: 180.ms,
          width: 34,  
          height: 34, 
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? const Color(0xFFFFFFFF).withValues(alpha: 0.2) : Colors.transparent,
          ),
          child: Icon(
            icon,
            size: 26, 
            color: selected ? const Color(0xFFFFFFFF) : const Color(0xFFDDDDDD),
          ),
        ),
      ),
    );
  }
}

class _ChatNavIcon extends StatelessWidget {
  const _ChatNavIcon({
    required this.selected,
    required this.onTap,
    required this.unreadCount,
  });
  final bool selected;
  final VoidCallback onTap;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final badgeLabel = unreadCount > 99 ? '99+' : unreadCount.toString();
    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        duration: 180.ms,
        scale: selected ? 1.12 : 1.0,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: AnimatedContainer(
                  duration: 180.ms,
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? const Color(0xFFFFFFFF).withValues(alpha: 0.2) : Colors.transparent,
                  ),
                  child: Icon(
                    Icons.forum_rounded,
                    size: 22,
                    color: selected ? const Color(0xFFFFFFFF) : const Color(0xFFDDDDDD),
                  ),
                ),
              ),
              if (unreadCount > 0)
                Positioned(
                  top: 0,
                  right: 0,
                  child: AnimatedScale(
                    duration: 200.ms,
                    scale: unreadCount > 0 ? 1.0 : 0.0,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFC700),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF111111), width: 1.5),
                      ),
                      child: Text(
                        badgeLabel,
                        style: GoogleFonts.manrope(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: Colors.black,
                          height: 1.2,
                        ),
                        textAlign: TextAlign.center,
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
}