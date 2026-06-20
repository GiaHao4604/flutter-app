import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_application_1/services/auth_api_service.dart';
import 'package:flutter_application_1/services/auth_session_service.dart';

// Cleaned up old theme tokens

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
      final role = meResult.data?['role'] ?? 'user';
      await _sessionService.saveUserRole(role);
      if (!mounted) {
        return;
      }
      if (role == 'admin' || role == 'director_admin') {
        Navigator.pushReplacementNamed(context, '/admin_home');
      } else {
        Navigator.pushReplacementNamed(context, '/home');
      }
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
      final loginRole = (result.data?['role'] as String?)?.trim() ?? 'user';

      if (token.isNotEmpty) {
        await _sessionService.saveToken(token);
        await _sessionService.saveUserRole(loginRole);
        final meResult = await _authApiService.getMe(token: token);
        if (meResult.success) {
          final name = (meResult.data?['name'] as String?)?.trim() ?? '';
          final email = (meResult.data?['email'] as String?)?.trim() ?? '';
          final roleFromMe = (meResult.data?['role'] as String?)?.trim() ?? loginRole;
          if (email.isNotEmpty) {
            await _sessionService.saveCurrentUserEmail(email);
          }
          await _sessionService.saveUserRole(roleFromMe);
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

    _showLoginResult(
      success: result.success, 
      message: dialogMessage, 
      role: (result.data?['role'] as String?)?.trim() ?? 'user'
    );
  }

  Future<void> _showLoginResult({required bool success, String? message, String role = 'user'}) {
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
                  width: 46,
                  height: 46,
                  decoration: const BoxDecoration(
                    color: Colors.black,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    success ? Icons.check : Icons.error_outline,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  success ? 'Thành công' : 'Đăng nhập không thành công',
                  style: const TextStyle(
                    fontSize: 22,
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
                  height: 40,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      
                      if (success && mainContext.mounted) {
                        if (role == 'admin' || role == 'director_admin') {
                          Navigator.pushReplacementNamed(mainContext, '/admin_home');
                        } else {
                          Navigator.pushReplacementNamed(mainContext, '/home');
                        }
                      }
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Colors.black, width: 1.5),
                      ),
                    ),
                    child: Text(
                      success ? 'OK' : 'Thử lại',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
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
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black, // Nền gốc màu đen để lộ ra khi cắt góc trắng
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      // Phần Đen (Tự động co giãn theo chiều cao màn hình)
                      SizedBox(
                        height: size.height * 0.30, // Chiếm 30% màn hình
                        child: _buildTopBlackSection(),
                      ),
                      
                      // Phần Trắng (Form)
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(80), // Cắt góc trên bên trái, tạo cảm giác đen bo xuống
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 28.0),
                            child: Column(
                              children: [
                                _buildFormSection(),
                                const Spacer(),
                                _buildBottomSignUp(),
                                const SizedBox(height: 48), // Tăng khoảng trống đáy
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTopBlackSection() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(40),
          child: Image.asset(
            'assets/logo.jpg',
            width: 80, // Thu nhỏ logo một xíu cho gọn gàng
            height: 80,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Image.asset(
                'assets/logo.png',
                width: 80,
                height: 80,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.person_outline,
                  size: 60,
                  color: Colors.white,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'MoneyLife',
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildFormSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const Center(
          child: Text(
            'Đăng nhập',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: Colors.black,
            ),
          ),
        ),
        const SizedBox(height: 28),
        const Text(
          'Email',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 6),
        _buildInputField(
          controller: _emailController,
          hintText: 'Hãy nhập email',
          keyboardType: TextInputType.emailAddress,
          hasError: _showValidation && _emailError != null,
        ),
        if (_showValidation && _emailError != null) _buildErrorText(_emailError!),
        
        const SizedBox(height: 16),
        const Text(
          'Mật khẩu',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 6),
        _buildInputField(
          controller: _passwordController,
          hintText: '••••••••',
          obscureText: !_isPasswordVisible,
          hasError: _showValidation && _passwordError != null,
          suffix: IconButton(
            splashRadius: 20,
            onPressed: () {
              setState(() => _isPasswordVisible = !_isPasswordVisible);
            },
            icon: Icon(
              _isPasswordVisible ? Icons.visibility_off : Icons.visibility,
              size: 20,
              color: const Color(0xFF9E9E9E),
            ),
          ),
        ),
        if (_showValidation && _passwordError != null) _buildErrorText(_passwordError!),
        
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _showForgotPasswordSheet,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Quên mật khẩu?',
              style: TextStyle(
                color: Color(0xFFB0B0B0),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: _isSubmitting ? null : _onLoginPressed,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(
              _isSubmitting ? 'Đang xử lý...' : 'Đăng nhập',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomSignUp() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          "Chưa có tài khoản? ",
          style: TextStyle(
            color: Color(0xFF555555),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        GestureDetector(
          onTap: () => Navigator.pushReplacementNamed(context, '/register'),
          child: const Text(
            'Đăng ký',
            style: TextStyle(
              color: Colors.black,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  // Phần giao diện cũ (_buildBrand, _buildFormCard) đã được thay thế hoàn toàn

  void _showForgotPasswordSheet() {
    String step = 'email'; // 'email' hoặc 'otp'
    final fpEmailController = TextEditingController();
    final fpOtpController = TextEditingController();
    final fpPasswordController = TextEditingController();
    bool isProcessing = false;
    String? errorMessage;
    String? successMessage;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> submitEmail() async {
              final email = fpEmailController.text.trim();
              if (email.isEmpty || !email.contains('@')) {
                setSheetState(() => errorMessage = 'Email không hợp lệ');
                return;
              }
              setSheetState(() {
                isProcessing = true;
                errorMessage = null;
              });

              final result = await _authApiService.forgotPassword(email: email);
              
              setSheetState(() {
                isProcessing = false;
                if (result.success) {
                  step = 'otp';
                  successMessage = result.message;
                } else {
                  errorMessage = result.message;
                }
              });
            }

            Future<void> submitReset() async {
              final email = fpEmailController.text.trim();
              final otp = fpOtpController.text.trim();
              final newPass = fpPasswordController.text;

              if (otp.isEmpty || newPass.length < 6) {
                setSheetState(() => errorMessage = 'OTP trống hoặc mật khẩu < 6 ký tự');
                return;
              }

              setSheetState(() {
                isProcessing = true;
                errorMessage = null;
              });

              final result = await _authApiService.resetPassword(
                email: email,
                otpCode: otp,
                newPassword: newPass,
              );

              setSheetState(() {
                isProcessing = false;
              });

              if (result.success) {
                if (!sheetContext.mounted) return;
                Navigator.pop(sheetContext);
                _showLoginResult(success: true, message: result.message);
              } else {
                setSheetState(() => errorMessage = result.message);
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 20,
                right: 20,
                top: 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Quên mật khẩu',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF2A2A2A),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  if (successMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(color: const Color(0xFFE3F7ED), borderRadius: BorderRadius.circular(8)),
                      child: Text(successMessage!, style: const TextStyle(color: Color(0xFF1E9D5B), fontSize: 13)),
                    ),
                  if (errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(color: const Color(0xFFFDE7E7), borderRadius: BorderRadius.circular(8)),
                      child: Text(errorMessage!, style: const TextStyle(color: Color(0xFFFF3B3B), fontSize: 13)),
                    ),
                  if (step == 'email') ...[
                    const Text('Nhập email của bạn để nhận mã OTP khôi phục.', style: TextStyle(color: Color(0xFF61636F), fontSize: 13)),
                    const SizedBox(height: 16),
                    _buildInputField(
                      controller: fpEmailController,
                      hintText: 'Email của bạn',
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: isProcessing ? null : submitEmail,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF4A46DE),
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text(isProcessing ? 'Đang gửi...' : 'Nhận mã OTP'),
                    ),
                  ] else ...[
                    _buildInputField(
                      controller: fpOtpController,
                      hintText: 'Mã OTP (6 số)',
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    _buildInputField(
                      controller: fpPasswordController,
                      hintText: 'Mật khẩu mới (ít nhất 6 ký tự)',
                      obscureText: true,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: isProcessing ? null : submitReset,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF4A46DE),
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text(isProcessing ? 'Đang xử lý...' : 'Đặt lại mật khẩu'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: isProcessing ? null : submitEmail,
                      child: Text(
                        isProcessing ? 'Đang gửi lại...' : 'Chưa nhận được mã? Gửi lại',
                        style: const TextStyle(color: Color(0xFF4A46DE), fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                ],
              ),
            );
          },
        );
      },
    );
  }


  Widget _buildInputField({
    required TextEditingController controller,
    required String hintText,
    Widget? suffix,
    bool obscureText = false,
    TextInputType? keyboardType,
    bool hasError = false,
  }) {
    final borderColor = hasError ? const Color(0xFFFF3B3B) : const Color(0xFFEBEBEB);

    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: Colors.black,
      ),
      decoration: InputDecoration(
        isDense: true,
        hintText: hintText,
        hintStyle: const TextStyle(
          color: Color(0xFF9E9E9E),
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        filled: true,
        fillColor: const Color(0xFFFFFFFF),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        suffixIcon: suffix,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: borderColor, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.black, width: 1.5),
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
  // TabItem was removed
}