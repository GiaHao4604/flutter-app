import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/services/auth_api_service.dart';
import 'package:flutter_application_1/services/auth_session_service.dart';
import 'package:flutter_application_1/services/notification_api_service.dart';
import 'package:flutter_application_1/screens/budget.dart';
import 'package:flutter_application_1/screens/statistics.dart';
import 'package:flutter_application_1/screens/inbox_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

class Profile extends StatefulWidget {
  final String userInitials;
  final VoidCallback onLogoutTap;
  final String? currentImageUrl; // ĐÃ SỬA: Chuyển từ File? thành String? để nhận link từ Internet
  final ValueChanged<String?> onImageChanged; // ĐÃ SỬA: Trả link ảnh mạng mới về lại HomeScreen
  final ValueChanged<String> onNameChanged;
  final String userName;    // Nhận tên thật từ HomeScreen
  final String userEmail;   // Nhận email thật từ HomeScreen
  final VoidCallback? onBack;

  const Profile({
    super.key,
    required this.userInitials,
    required this.onLogoutTap,
    required this.currentImageUrl,
    required this.onImageChanged,
    required this.onNameChanged,
    required this.userName,
    required this.userEmail,
    this.onBack,
  });

  @override
  State<Profile> createState() => _ProfileState();
}

class _ProfileState extends State<Profile> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  String? _avatarUrl; // Lưu link ảnh mạng hiện tại để hiển thị trên giao diện
  String _displayName = '';
  bool _isUploading = false; // Trạng thái hiển thị vòng xoay chờ khi đang upload ảnh
  int _unreadCount = 0;
  
  final ImagePicker _picker = ImagePicker();
  final AuthApiService _authApiService = AuthApiService();
  final AuthSessionService _sessionService = AuthSessionService();

  @override
  void initState() {
    super.initState();
    _avatarUrl = widget.currentImageUrl; // Khởi tạo bằng link ảnh hiện có từ server
    _displayName = widget.userName;
    _fetchUnreadCount();
  }

  Future<void> _fetchUnreadCount() async {
    final result = await NotificationApiService.getUnreadCount();
    if (result.success && result.data != null && mounted) {
      setState(() {
        _unreadCount = result.data!;
      });
    }
  }

  void _showImageSourceActionSheet(BuildContext context) {
    if (_isUploading) return; // Nếu đang upload thì khóa không cho bấm tiếp
    
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161313),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: Colors.white),
              title: Text('Chọn ảnh từ Thư viện', style: GoogleFonts.manrope(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined, color: Colors.white),
              title: Text('Chụp ảnh mới', style: GoogleFonts.manrope(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showComingSoon(String feature) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '🚀 Sắp ra mắt',
          style: GoogleFonts.manrope(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Tính năng "$feature" đang được phát triển và sẽ có trong phiên bản tiếp theo.',
          style: GoogleFonts.manrope(color: Colors.white70, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Đã hiểu', style: GoogleFonts.manrope(color: const Color(0xFF5B4BFF), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _sendFeedback() async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'support@example.com',
      query: 'subject=Phản hồi ứng dụng&body=',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _showComingSoon('Gửi phản hồi');
    }
  }

  Future<void> _rateApp() async {
    _showComingSoon('Đánh giá ứng dụng');
  }

  Future<void> _shareApp() async {
    _showComingSoon('Chia sẻ ứng dụng');
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 500,
        maxHeight: 500,
        imageQuality: 80,
      );
      
      if (pickedFile == null) return;

      setState(() {
        _isUploading = true; // Bật vòng xoay chờ đợi xử lý file
      });

      // 1. Lấy Token xác thực đang lưu trong máy ra
      final token = await _sessionService.getToken();
      if (token == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Phiên đăng nhập hết hạn, vui lòng đăng nhập lại.')),
          );
        }
        return;
      }

      // 2. Gọi hàm API gửi file ảnh vật lý lên máy chủ Node.js
      final result = await _authApiService.uploadAvatar(
        imageFile: File(pickedFile.path),
        token: token,
      );

      if (!mounted) return;

      // 3. Kiểm tra kết quả trả về từ Backend
      if (result.success && result.data?['avatarUrl'] != null) {
        final newUrl = result.data!['avatarUrl'] as String;
        
        setState(() {
          _avatarUrl = newUrl; // Cập nhật lại ảnh mới trên màn hình Profile
        });
        
        widget.onImageChanged(newUrl); // Phát tín hiệu báo cho HomeScreen biết để cập nhật đồng bộ luôn
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cập nhật ảnh đại diện thành công! 🎉')),
        );
      } else {
        // Show thông báo lỗi cụ thể từ server nếu có
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message)),
        );
      }
    } catch (e) {
      debugPrint('Lỗi hệ thống khi tải ảnh: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể tải ảnh lên. Vui lòng kiểm tra lại kết nối mạng.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false; // Tắt vòng xoay chờ kể cả khi thành công hay thất bại
        });
      }
    }
  }

  Future<void> _saveProfileName(String newName) async {
    final token = await _sessionService.getToken();
    if (token == null || token.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phiên đăng nhập hết hạn, vui lòng đăng nhập lại.')),
      );
      return;
    }

    final result = await _authApiService.updateProfile(token: token, name: newName);
    if (!mounted) return;

    if (result.success) {
      setState(() {
        _displayName = newName.trim();
      });
      widget.onNameChanged(newName.trim());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã đổi tên thành công')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    }
  }

  Future<void> _changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    final token = await _sessionService.getToken();
    if (token == null || token.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phiên đăng nhập hết hạn, vui lòng đăng nhập lại.')),
      );
      return;
    }

    final result = await _authApiService.changePassword(
      token: token,
      currentPassword: currentPassword,
      newPassword: newPassword,
      confirmPassword: confirmPassword,
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
  }

  Future<void> _showRenameDialog() async {
    if (!mounted) return;

    final newName = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (dialogContext) {
        return const _RenameNameDialog();
      },
    );

    if (newName != null && newName.trim().isNotEmpty) {
      await _saveProfileName(newName);
    }
  }

  Future<void> _showChangePasswordDialog() async {
    if (!mounted) return;

    final result = await showModalBottomSheet<Map<String, String>?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => const _ChangePasswordDialog(),
    );

    if (result == null) return;

    final current = result['current'] ?? '';
    final next = result['next'] ?? '';
    final confirm = result['confirm'] ?? '';

    if (current.isEmpty || next.isEmpty || confirm.isEmpty) return;

    await _changePassword(
      currentPassword: current,
      newPassword: next,
      confirmPassword: confirm,
    );
  }

  Future<void> _showSettingsMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.35,
          minChildSize: 0.2,
          maxChildSize: 0.8,
          builder: (_, controller) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              child: Column(
                children: [
                  Container(
                    width: 48,
                    height: 6,
                    margin: const EdgeInsets.only(top: 6, bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      controller: controller,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Text('Cài đặt tài khoản', style: GoogleFonts.manrope(color: Colors.black, fontSize: 16, fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(height: 6),
                        ListTile(
                          leading: CircleAvatar(
                            radius: 20,
                            backgroundColor: Colors.black,
                            child: const Icon(Icons.badge_outlined, color: Colors.white),
                          ),
                          title: Text('Đổi tên', style: GoogleFonts.manrope(color: Colors.black, fontWeight: FontWeight.w600)),
          
                          trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.black26, size: 16),
                          onTap: () {
                            Navigator.pop(sheetContext, 'rename');
                          },
                        ),
                        const Divider(color: Colors.black12, height: 0),
                        ListTile(
                          leading: CircleAvatar(
                            radius: 20,
                            backgroundColor: Colors.black,
                            child: const Icon(Icons.lock_outline_rounded, color: Colors.white),
                          ),
                          title: Text('Đổi mật khẩu', style: GoogleFonts.manrope(color: Colors.black, fontWeight: FontWeight.w600)),
                          subtitle: Text('Bảo mật tài khoản của bạn', style: GoogleFonts.manrope(color: Colors.black54, fontSize: 12)),
                          trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.black26, size: 16),
                          onTap: () {
                            Navigator.pop(sheetContext, 'password');
                          },
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (!mounted) return;

    if (action == 'rename') {
      await _showRenameDialog();
    } else if (action == 'password') {
      await _showChangePasswordDialog();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final hasAvatar = _avatarUrl != null && _avatarUrl!.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: widget.onBack != null ? IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: widget.onBack, 
        ) : null,
        title: Text(
          'Cài đặt',
          style: GoogleFonts.manrope(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _showSettingsMenu,
            icon: const Icon(Icons.settings_rounded, color: Colors.white),
            tooltip: 'Cài đặt',
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Center(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 3),
                    child: GestureDetector(
                      onTap: () => _showImageSourceActionSheet(context),
                    child: Stack(
                      children: [
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: hasAvatar ? Colors.transparent : const Color(0xFF5B4BFF),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF5B4BFF).withValues(alpha: 0.3),
                                blurRadius: 15,
                                offset: const Offset(0, 8),
                              )
                            ],
                            image: hasAvatar
                                ? DecorationImage(
                                    image: NetworkImage(_avatarUrl!), // Tải ảnh mạng trực tiếp từ link Node.js trả về
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: !hasAvatar && !_isUploading
                              ? Center(
                                  child: Text(
                                    widget.userInitials,
                                    style: GoogleFonts.manrope(
                                      fontSize: 32,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                )
                              : _isUploading 
                                  ? const Center(
                                      child: CircularProgressIndicator(color: Colors.white), // Hiển thị vòng xoay khi đang upload
                                    )
                                  : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.camera_alt_rounded,
                              color: Color(0xFF080808),
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                  const SizedBox(height: 16),
                  
                  // ĐÃ SỬA: Hiển thị đúng tên động lấy từ Widget nhận từ HomeScreen
                  Text(
                    _displayName,
                    style: GoogleFonts.manrope(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  
                  // ĐÃ SỬA: Hiển thị đúng email động lấy từ Widget nhận từ HomeScreen
                  Text(
                    widget.userEmail,
                    style: GoogleFonts.manrope(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 35),
            _buildMenuSection(
              children: [
                _buildMenuItem(
                  icon: Icons.bar_chart,
                  iconColor: Colors.white,
                  title: 'Thống kê',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const StatisticsScreen(),
                      ),
                    );
                  },
                ),
                _buildMenuItem(
                  icon: Icons.account_balance_wallet_outlined,
                  iconColor: Colors.white,
                  title: 'Ngân sách chi tiêu',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const BudgetScreen(),
                      ),
                    );
                  },
                ),
                _buildMenuItem(
                  icon: Icons.inbox_rounded,
                  iconColor: Colors.white,
                  title: 'Hộp thư hệ thống',
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const InboxScreen(),
                      ),
                    );
                    _fetchUnreadCount(); // Refresh count when coming back
                  },
                  trailingWidget: _unreadCount > 0 
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _unreadCount > 99 ? '99+' : '$_unreadCount',
                            style: GoogleFonts.manrope(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        )
                      : null,
                ),
                _buildMenuItem(icon: Icons.g_translate_rounded, iconColor: Colors.white, title: 'Ngôn ngữ hiển thị', trailingText: 'Tiếng Việt', onTap: () => _showComingSoon('Chọn ngôn ngữ')),
                _buildMenuItem(icon: Icons.dark_mode_outlined, iconColor: Colors.white, title: 'Giao diện', trailingText: 'Tối', onTap: () => _showComingSoon('Cài đặt giao diện')),
                _buildMenuItem(icon: Icons.monetization_on_outlined, iconColor: Colors.white, title: 'Tiền tệ hiển thị', trailingText: 'VND', onTap: () => _showComingSoon('Chọn tiền tệ')),
              ],
            ),
            const SizedBox(height: 16),
            _buildMenuSection(
              children: [
                _buildMenuItem(icon: Icons.mail_outline_rounded, iconColor: Colors.white, title: 'Gửi phản hồi', onTap: _sendFeedback),
                _buildMenuItem(icon: Icons.star_outline_rounded, iconColor: Colors.white, title: 'Đánh giá ứng dụng', onTap: _rateApp),
                _buildMenuItem(icon: Icons.share_outlined, iconColor: Colors.white, title: 'Chia sẻ ứng dụng', onTap: _shareApp),
                _buildMenuItem(icon: Icons.description_outlined, iconColor: Colors.white, title: 'Điều khoản dịch vụ', onTap: () => _showComingSoon('Điều khoản dịch vụ')),
                _buildMenuItem(icon: Icons.security_outlined, iconColor: Colors.white, title: 'Chính sách bảo mật', onTap: () => _showComingSoon('Chính sách bảo mật')),
              ],
            ),
            const SizedBox(height: 24),
            InkWell(
              onTap: () {
                Navigator.pop(context);
                widget.onLogoutTap();
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: double.infinity,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.2), width: 1),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      'Đăng xuất tài khoản',
                      style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.redAccent),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuSection({required List<Widget> children}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05), width: 1),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? trailingText,
    Widget? trailingWidget,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: Colors.black.withValues(alpha: 0.9), size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.manrope(color: Colors.black.withValues(alpha: 0.9), fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            if (trailingText != null) ...[
              Text(
                trailingText,
                style: GoogleFonts.manrope(color: Colors.black.withValues(alpha: 0.35), fontSize: 14, fontWeight: FontWeight.w500),
              ),
              const SizedBox(width: 8),
            ],
            if (trailingWidget != null) ...[
              trailingWidget,
              const SizedBox(width: 8),
            ],
            Icon(Icons.arrow_forward_ios_rounded, color: Colors.black.withValues(alpha: 0.15), size: 14),
          ],
        ),
      ),
    );
  }
}

class _RenameNameDialog extends StatefulWidget {
  const _RenameNameDialog();

  @override
  State<_RenameNameDialog> createState() => _RenameNameDialogState();
}

class _RenameNameDialogState extends State<_RenameNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.78,
          ),
          child: Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Color(0xFF171717),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFF5B4BFF).withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.badge_outlined, color: Color(0xFF5B4BFF)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Đổi tên', style: GoogleFonts.manrope(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text('Nhập tên mới để cập nhật hiển thị trên tài khoản của bạn.', style: GoogleFonts.manrope(color: Colors.white54, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _controller,
                    autofocus: false,
                    style: GoogleFonts.manrope(color: Colors.white),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.04),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      hintText: 'Nhập tên mới',
                      hintStyle: const TextStyle(color: Colors.white38),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white12),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: () async {
                            final navigator = Navigator.of(context);
                            FocusManager.instance.primaryFocus?.unfocus();
                            await Future<void>.delayed(const Duration(milliseconds: 80));
                            if (!mounted) return;
                            navigator.pop();
                          },
                          child: const Text('Hủy'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF5B4BFF),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: () {
                            final value = _controller.text.trim();
                            if (value.isEmpty) return;
                            FocusManager.instance.primaryFocus?.unfocus();
                            Navigator.of(context).pop(value);
                          },
                          child: const Text('Lưu', style: TextStyle(color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  late final TextEditingController _currentController;
  late final TextEditingController _newController;
  late final TextEditingController _confirmController;

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  String? _currentPasswordError;
  String? _newPasswordError;
  String? _confirmPasswordError;

  @override
  void initState() {
    super.initState();
    _currentController = TextEditingController();
    _newController = TextEditingController();
    _confirmController = TextEditingController();
  }

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _validateAndSubmit() {
    final current = _currentController.text.trim();
    final next = _newController.text.trim();
    final confirm = _confirmController.text.trim();

    setState(() {
      _currentPasswordError = current.isEmpty ? 'Vui lòng nhập mật khẩu hiện tại' : null;
      _newPasswordError = next.isEmpty || next.length < 6 ? 'Mật khẩu tối thiểu 6 kí tự' : null;
      _confirmPasswordError = confirm.isEmpty ? 'Vui lòng xác nhận mật khẩu mới' : (confirm != next ? 'Mật khẩu xác nhận không khớp' : null);
    });

    if (_currentPasswordError != null || _newPasswordError != null || _confirmPasswordError != null) {
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop(<String, String>{
      'current': current,
      'next': next,
      'confirm': confirm,
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.86,
          ),
          child: Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Color(0xFF171717),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFF00C896).withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.lock_outline_rounded, color: Color(0xFF00C896)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Đổi mật khẩu', style: GoogleFonts.manrope(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text('Nhập mật khẩu hiện tại và mật khẩu mới để cập nhật.', style: GoogleFonts.manrope(color: Colors.white54, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _currentController,
                    obscureText: _obscureCurrent,
                    style: GoogleFonts.manrope(color: Colors.white),
                    onChanged: (_) {
                      if (_currentPasswordError != null) {
                        setState(() => _currentPasswordError = null);
                      }
                    },
                    decoration: InputDecoration(
                      hintText: 'Mật khẩu hiện tại',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.04),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: _currentPasswordError != null ? Colors.redAccent : Colors.transparent, width: 1.2),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: _currentPasswordError != null ? Colors.redAccent : const Color(0xFF00C896), width: 1.6),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Colors.redAccent, width: 1.6),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Colors.redAccent, width: 1.8),
                      ),
                      errorText: _currentPasswordError,
                      errorStyle: const TextStyle(color: Colors.redAccent),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent),
                        icon: Icon(_obscureCurrent ? Icons.visibility_off : Icons.visibility, color: Colors.white54),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _newController,
                    obscureText: _obscureNew,
                    style: GoogleFonts.manrope(color: Colors.white),
                    onChanged: (_) {
                      if (_newPasswordError != null) {
                        setState(() => _newPasswordError = null);
                      }
                    },
                    decoration: InputDecoration(
                      hintText: 'Mật khẩu mới',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.04),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: _newPasswordError != null ? Colors.redAccent : Colors.transparent, width: 1.2),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: _newPasswordError != null ? Colors.redAccent : const Color(0xFF00C896), width: 1.6),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Colors.redAccent, width: 1.6),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Colors.redAccent, width: 1.8),
                      ),
                      errorText: _newPasswordError,
                      errorStyle: const TextStyle(color: Colors.redAccent),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscureNew = !_obscureNew),
                        icon: Icon(_obscureNew ? Icons.visibility_off : Icons.visibility, color: Colors.white54),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirmController,
                    obscureText: _obscureConfirm,
                    style: GoogleFonts.manrope(color: Colors.white),
                    onChanged: (_) {
                      if (_confirmPasswordError != null) setState(() => _confirmPasswordError = null);
                    },
                    decoration: InputDecoration(
                      hintText: 'Xác nhận mật khẩu mới',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.04),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: _confirmPasswordError != null ? Colors.redAccent : Colors.transparent, width: 1.2),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: _confirmPasswordError != null ? Colors.redAccent : const Color(0xFF00C896), width: 1.6),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Colors.redAccent, width: 1.6),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Colors.redAccent, width: 1.8),
                      ),
                      errorText: _confirmPasswordError,
                      errorStyle: const TextStyle(color: Colors.redAccent),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                        icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility, color: Colors.white54),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white12),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: () async {
                            final navigator = Navigator.of(context);
                            FocusManager.instance.primaryFocus?.unfocus();
                            await Future<void>.delayed(const Duration(milliseconds: 80));
                            if (!mounted) return;
                            navigator.pop(null);
                          },
                          child: const Text('Hủy'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: const Color(0xFF00C896),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: _validateAndSubmit,
                          child: const Text('Lưu', style: TextStyle(color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}