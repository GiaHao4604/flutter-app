import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_application_1/services/auth_api_service.dart';
import 'package:flutter_application_1/services/auth_session_service.dart';
import 'package:flutter_application_1/widgets/camera_preview_widget.dart';
import 'package:flutter_application_1/screens/calendar.dart';
import 'package:flutter_application_1/widgets/camera_action_button.dart';
import 'package:flutter_application_1/screens/post_feed_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_application_1/screens/profile.dart'; 

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
  String _userInitials = 'U';
  String? _userAvatarUrl; // Lưu giữ link ảnh mạng (Ví dụ: http://...)
  
  // DỮ LIỆU TÀI KHOẢN THỰC TẾ LẤY TỪ API
  String _userName = 'Người Dùng';
  String _userEmail = 'user@gmail.com';

  final GlobalKey<CameraPreviewWidgetState> _cameraKey = GlobalKey<CameraPreviewWidgetState>();
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedTab);
    _loadProfile();
  }

  @override
  void dispose() {
    _pageController.dispose();
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
        // SỬA: Thay vì lập tức đá về login làm nghẽn app, ta hiển thị SnackBar thông báo lỗi cho dev/user biết
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể tải thông tin: ${result.message}')),
        );
        setState(() {
          _isLoading = false; // Vẫn tắt loading để user dùng được các tính năng offline/camera
        });
        return;
      }

      final name = (result.data?['name'] as String?)?.trim() ?? 'User';
      final email = (result.data?['email'] as String?)?.trim() ?? 'user@gmail.com';
      final avatar = result.data?['avatar_url'] as String?;
      await _sessionService.saveCurrentUserEmail(email);
      
      setState(() {
        _isLoading = false;
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
    setState(() {
      _selectedTab = index;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  void _openPostFeed() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PostFeedScreen()),
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

    return Scaffold(
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
                child: const CalendarScreen(), 
              ),
              _buildCameraPage(),
              _buildChatPage(),
            ],
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: systemBottomPadding > 0 ? systemBottomPadding : 16, 
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _selectedTab == 1 ? 1.0 : 0.0,
                    child: GestureDetector(
                      onTap: _openPostFeed,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Colors.white.withValues(alpha: 0.8),
                        size: 30,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _BottomPill(
                    selectedIndex: _selectedTab,
                    onTap: _handleNavTap,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 120),
      child: Center(
        child: Text(
          'Giao diện Chat đang phát triển',
          style: GoogleFonts.manrope(color: Colors.white, fontSize: 18),
        ),
      ),
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
          colors: [Color(0xFF5A5555), Color(0xFF161313), Color(0xFF080808)],
          stops: [0.0, 0.35, 1.0],
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
    final hasAvatar = userAvatarUrl != null && userAvatarUrl!.trim().isNotEmpty;

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
                      image: NetworkImage(userAvatarUrl!), 
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
  const _BottomPill({required this.selectedIndex, required this.onTap});
  final int selectedIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24), 
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
        child: Container(
          width: 184,
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
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _NavIcon(icon: Icons.calendar_month_rounded, selected: selectedIndex == 0, onTap: () => onTap(0)),
              _NavIcon(icon: Icons.home_outlined, selected: selectedIndex == 1, onTap: () => onTap(1)),
              _ChatNavIcon(selected: selectedIndex == 2, onTap: () => onTap(2)),
            ],
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
  const _ChatNavIcon({required this.selected, required this.onTap});
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
            Icons.forum_rounded,
            size: 26, 
            color: selected ? const Color(0xFFFFFFFF) : const Color(0xFFDDDDDD),
          ),
        ),
      ),
    );
  }
}