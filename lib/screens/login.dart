import 'package:flutter/material.dart';
import 'package:flutter_application_1/services/auth_api_service.dart';
import 'package:flutter_application_1/services/auth_session_service.dart';

// Inlined theme tokens from lib/theme/logintheme.dart (merged per request)
const Color black = Color(0xFF000000);
const Color blackTransparent = Color(0xB3000000);
const Color darkgray = Color(0xFF9E9E9E);
const Color firebrick = Color(0xFFC23F37);
const Color ghostwhite = Color(0xFFEEEEF4);
const Color gray = Color(0xFF01010F);
const Color grayMedium = Color(0xFF757575);
const Color labelColorLightPrimary = Color(0xFF000000);
const Color mediumseagreen = Color(0xFF55B685);
const Color mediumslateblue100 = Color(0xFF4E46DD);
const Color mediumslateblue200 = Color(0xFF5E4DED);
const Color mintcream = Color(0xFFE6F5F0);
const Color mistyrose = Color(0xFFF7E7E6);
const Color red = Color(0xFFFF0505);
const Color systemBackgroundLightPrimary = Color(0xFFFFFFFF);
const Color white = Color(0xFFFFFFFF);
const Color whitesmoke = Color(0xFFF9F9F9);

const double fs12 = 12;
const double fs14 = 14;
const double fs24 = 24;

const double height16 = 16;
const double height22 = 22;
const double height24 = 24;
const double height50 = 50;
const double height60 = 60;
const double height72 = 72;
const double width16 = 16;
const double width24 = 24;
const double width300 = 300;
const double width357 = 357;

const double padding1 = 1;
const double padding14 = 14;
const double padding28 = 28;
const double br11 = 11;

const List<BoxShadow> shadowDrop = [
  BoxShadow(
    color: Color(0x40000000),
    blurRadius: 4,
    spreadRadius: 0,
    offset: Offset(0, 4),
  ),
];

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _showValidation = false;
  bool _isSubmitting = false;

  final AuthApiService _authApiService = AuthApiService();
  final AuthSessionService _sessionService = AuthSessionService();

  String? _emailError;
  String? _passwordError;

  @override
  void initState() {
    super.initState();
    _tryAutoLogin();
  }

  Future<void> _tryAutoLogin() async {
    final token = await _sessionService.getToken();

    if (token == null || token.trim().isEmpty) {
      return;
    }

    final meResult = await _authApiService.getMe(token: token);

    if (!mounted) {
      return;
    }

    if (meResult.success) {
      Navigator.pushReplacementNamed(context, '/home');
      return;
    }

    await _sessionService.clearToken();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _onLoginPressed() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    final emailError = emailPattern.hasMatch(email)
        ? null
        : 'Email không hợp lệ';
    final passwordError = password.isNotEmpty ? null : 'Vui lòng nhập mật khẩu';

    setState(() {
      _showValidation = true;
      _emailError = emailError;
      _passwordError = passwordError;
    });

    if (emailError != null || passwordError != null) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final result = await _authApiService.login(
      email: email,
      password: password,
    );

    var dialogMessage = result.message;

    if (result.success) {
      final token = (result.data?['token'] as String?)?.trim() ?? '';

      if (token.isNotEmpty) {
        await _sessionService.saveToken(token);
        final meResult = await _authApiService.getMe(token: token);
        if (meResult.success) {
          final name = (meResult.data?['name'] as String?)?.trim() ?? '';
          final email = (meResult.data?['email'] as String?)?.trim() ?? '';
          if (email.isNotEmpty) {
            await _sessionService.saveCurrentUserEmail(email);
          }
          if (name.isNotEmpty) {
            dialogMessage = 'Đăng nhập thành công. Xin chào $name';
          }
        }
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isSubmitting = false;
    });

    _showLoginResult(success: result.success, message: dialogMessage);
  }

  Future<void> _showLoginResult({required bool success, String? message}) {
    // 💡 GIẢI PHÁP: Lưu lại BuildContext của màn hình Login trước khi build Dialog
    final mainContext = context;

    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 292,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 24,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: success
                        ? const Color(0xFFE3F7ED)
                        : const Color(0xFFFCE7E7),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    success ? Icons.check : Icons.info_outline,
                    color: success
                        ? const Color(0xFF36B37E)
                        : const Color(0xFFD13B33),
                    size: 26,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  success ? 'Thành công' : 'Đăng nhập không thành công',
                  style: const TextStyle(
                    fontSize: 22, // Sửa lại kích thước một chút cho đỡ tràn chữ tiếng Việt
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF212121),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  success
                      ? 'Đăng nhập thành công'
                      : (message ?? 'Email hoặc mật khẩu không đúng'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF8C8C8C),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 32,
                  child: FilledButton(
                    onPressed: () {
                      // 1. Tắt Dialog thông qua context của chính nó
                      Navigator.of(dialogContext).pop();
                      
                      // 2. Chuyển màn hình thông qua mainContext của màn hình Login lớn bên dưới
                      if (success && mainContext.mounted) {
                        Navigator.pushReplacementNamed(mainContext, '/home');
                      }
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: success
                          ? const Color(0xFF36B37E)
                          : const Color(0xFFD13B33),
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(success ? 'OK' : 'Thử lại'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold( // Đưa về Scaffold gốc chuẩn tắc thay vì Container để tránh lỗi vỡ layout bàn phím
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF5C4DE1), Color(0xFF7A3CF0)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 32,
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 40),
                      _buildBrand(),
                      const SizedBox(height: 18),
                      _buildFormCard(),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBrand() {
    return Column(
      children: [
        DecoratedBox(
          decoration: const BoxDecoration(
            color: white,
            borderRadius: BorderRadius.all(Radius.circular(13)),
          ),
          child: SizedBox(
            width: 42,
            height: 42,
            child: Center(
              child: Text(
                'KNS',
                style: TextStyle(
                  color: mediumslateblue100,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Kỹ Năng Sống 4.0',
          style: TextStyle(
            color: white,
            fontSize: 32,
            fontWeight: FontWeight.w800,
            shadows: shadowDrop,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Cùng đồng hành với con trong hành trình\nrèn luyện kỹ năng mỗi ngày',
          style: TextStyle(
            color: white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildFormCard() {
    return Container(
      width: 390,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 2),
          Row(
            children: [
              const Expanded(
                child: _TabItem(text: 'Đăng nhập', isActive: true),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: _TabItem(
                  text: 'Đăng ký',
                  isActive: false,
                  onTap: () =>
                      Navigator.pushReplacementNamed(context, '/register'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildInputField(
            controller: _emailController,
            hintText: 'Email',
            prefixIcon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            hasError: _showValidation && _emailError != null,
            iconColor: _showValidation && _emailError != null
                ? const Color(0xFFFF3B3B)
                : null,
          ),
          if (_showValidation && _emailError != null)
            _buildErrorText(_emailError!),
          const SizedBox(height: 8),
          _buildInputField(
            controller: _passwordController,
            hintText: 'Mật khẩu',
            prefixIcon: Icons.lock_outline,
            obscureText: !_isPasswordVisible,
            hasError: _showValidation && _passwordError != null,
            iconColor: _showValidation && _passwordError != null
                ? const Color(0xFFFF3B3B)
                : null,
            suffix: IconButton(
              splashRadius: 18,
              onPressed: () {
                setState(() => _isPasswordVisible = !_isPasswordVisible);
              },
              icon: Icon(
                _isPasswordVisible ? Icons.visibility_off : Icons.visibility,
                size: 18,
                color: _showValidation && _passwordError != null
                    ? const Color(0xFFFF3B3B)
                    : const Color(0xFF5E606A),
              ),
            ),
          ),
          if (_showValidation && _passwordError != null)
            _buildErrorText(_passwordError!),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton(
              onPressed: _isSubmitting ? null : _onLoginPressed,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF4A46DE),
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                _isSubmitting ? 'Đang xử lý...' : 'Đăng nhập',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 2),
        ],
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hintText,
    required IconData prefixIcon,
    Widget? suffix,
    bool obscureText = false,
    TextInputType? keyboardType,
    bool hasError = false,
    Color? iconColor,
  }) {
    final borderColor = hasError
        ? const Color(0xFFFF3B3B)
        : const Color(0xFF9A9AAF);

    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: Color(0xFF2A2A2A),
      ),
      decoration: InputDecoration(
        isDense: true,
        hintText: hintText,
        hintStyle: const TextStyle(
          color: Color(0xFF868686),
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        filled: true,
        fillColor: const Color(0xFFF5F5F8),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        prefixIcon: Icon(
          prefixIcon,
          size: 18,
          color: iconColor ?? const Color(0xFF61636F),
        ),
        suffixIcon: suffix,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: BorderSide(color: borderColor, width: 1.1),
        ),
      ),
    );
  }

  Widget _buildErrorText(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: const TextStyle(
            color: Color(0xFFFF3B3B),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({required this.text, required this.isActive, this.onTap});

  final String text;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive
                  ? const Color(0xFF4A46DE)
                  : const Color(0xFFE2E2EA),
              width: 2,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Text(
            text,
            style: TextStyle(
              color: isActive
                  ? const Color(0xFF4A46DE)
                  : const Color(0xFFA2A2AA),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}