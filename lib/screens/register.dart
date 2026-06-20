import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_application_1/services/auth_api_service.dart';
import 'package:flutter_application_1/services/auth_session_service.dart';

class Register extends StatefulWidget {
  const Register({super.key});

  @override
  State<Register> createState() => _RegisterState();
}

class _RegisterState extends State<Register> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _showValidation = false;
  bool _isSubmitting = false;

  final AuthApiService _authApiService = AuthApiService();
  final AuthSessionService _sessionService = AuthSessionService();

  String? _nameError;
  String? _emailError;
  String? _passwordError;
  String? _confirmPasswordError;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _onRegisterPressed() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

    final nameError = name.isNotEmpty ? null : 'Vui lòng nhập tên';
    final emailError = emailPattern.hasMatch(email) ? null : 'Email không hợp lệ';
    final passwordError = password.length >= 6 ? null : 'Mật khẩu phải từ 6 ký tự';
    final confirmPasswordError = confirmPassword == password ? null : 'Mật khẩu không khớp';

    setState(() {
      _showValidation = true;
      _nameError = nameError;
      _emailError = emailError;
      _passwordError = passwordError;
      _confirmPasswordError = confirmPasswordError;
    });

    if (nameError != null || emailError != null || passwordError != null || confirmPasswordError != null) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    // 1. Gọi API gửi mã OTP trước
    final otpResult = await _authApiService.sendRegisterOtp(email: email);

    if (!mounted) return;

    setState(() {
      _isSubmitting = false;
    });

    if (otpResult.success) {
      // 2. Mở BottomSheet để nhập OTP nếu gửi thành công
      _showOtpSheet();
    } else {
      // 3. Hiển thị lỗi nếu gửi OTP thất bại
      _showRegisterResult(
        success: false, 
        message: otpResult.message,
      );
    }
  }

  void _showOtpSheet() {
    final TextEditingController otpController = TextEditingController();
    bool isVerifying = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEBEBEB),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Xác thực Email',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Mã OTP (6 số) đã được gửi đến hòm thư:\n${_emailController.text}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF8C8C8C),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildInputField(
                      controller: otpController,
                      hintText: 'Nhập mã OTP',
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: isVerifying
                            ? null
                            : () async {
                                final otp = otpController.text.trim();
                                if (otp.isEmpty) return;

                                setSheetState(() => isVerifying = true);

                                final result = await _authApiService.register(
                                  name: _nameController.text.trim(),
                                  email: _emailController.text.trim(),
                                  password: _passwordController.text,
                                  otpCode: otp,
                                );

                                setSheetState(() => isVerifying = false);

                                if (result.success) {
                                  if (sheetContext.mounted) {
                                    Navigator.pop(sheetContext); // Đóng BottomSheet
                                  }
                                  
                                  // Xử lý lưu session
                                  final token = (result.data?['token'] as String?)?.trim() ?? '';
                                  var dialogMessage = result.message;
                                  if (token.isNotEmpty) {
                                    await _sessionService.saveToken(token);
                                    final meResult = await _authApiService.getMe(token: token);
                                    if (meResult.success) {
                                      final returnedName = (meResult.data?['name'] as String?)?.trim() ?? '';
                                      final returnedEmail = (meResult.data?['email'] as String?)?.trim() ?? '';
                                      if (returnedEmail.isNotEmpty) {
                                        await _sessionService.saveCurrentUserEmail(returnedEmail);
                                      }
                                      if (returnedName.isNotEmpty) {
                                        dialogMessage = 'Đăng ký thành công. Xin chào $returnedName';
                                      }
                                    }
                                  }

                                  if (mounted) {
                                    _showRegisterResult(
                                      success: true, 
                                      message: dialogMessage, 
                                      role: (result.data?['role'] as String?)?.trim() ?? 'user'
                                    );
                                  }
                                } else {
                                  // Hiển thị lỗi OTP sai
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(result.message),
                                        backgroundColor: const Color(0xFFFF3B3B),
                                      ),
                                    );
                                  }
                                }
                              },
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          isVerifying ? 'Đang kiểm tra...' : 'Xác nhận & Đăng ký',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showRegisterResult({required bool success, String? message, String role = 'user'}) {
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
                  success ? 'Thành công' : 'Đăng ký không thành công',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF212121),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  success ? 'Đăng ký thành công' : (message ?? 'Email có thể đã tồn tại'),
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
      backgroundColor: Colors.black,
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
                      // Phần Đen
                      SizedBox(
                        height: size.height * 0.15, // Thu nhỏ phần đen lại một chút
                        child: _buildTopBlackSection(),
                      ),
                      
                      // Phần Trắng (Form)
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.only(
                              topRight: Radius.circular(80), // Bo tròn bên phải theo mẫu ảnh
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 28.0),
                            child: Column(
                              children: [
                                _buildFormSection(),
                                const Spacer(),
                                _buildBottomLogin(),
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
    return Padding(
      padding: const EdgeInsets.only(left: 32.0, right: 32.0, top: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'MoneyLife',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const Center(
          child: Text(
            'Đăng ký',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: Colors.black,
            ),
          ),
        ),
        const SizedBox(height: 24),
        
        // --- NAME ---
        const Text(
          'Họ và tên',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 6),
        _buildInputField(
          controller: _nameController,
          hintText: 'Nhập họ và tên',
          hasError: _showValidation && _nameError != null,
        ),
        if (_showValidation && _nameError != null) _buildErrorText(_nameError!),
        const SizedBox(height: 16),

        // --- EMAIL ---
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

        // --- PASSWORD ---
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
        
        const SizedBox(height: 16),

        // --- CONFIRM PASSWORD ---
        const Text(
          'Xác nhận mật khẩu',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 6),
        _buildInputField(
          controller: _confirmPasswordController,
          hintText: '••••••••',
          obscureText: !_isConfirmPasswordVisible,
          hasError: _showValidation && _confirmPasswordError != null,
          suffix: IconButton(
            splashRadius: 20,
            onPressed: () {
              setState(() => _isConfirmPasswordVisible = !_isConfirmPasswordVisible);
            },
            icon: Icon(
              _isConfirmPasswordVisible ? Icons.visibility_off : Icons.visibility,
              size: 20,
              color: const Color(0xFF9E9E9E),
            ),
          ),
        ),
        if (_showValidation && _confirmPasswordError != null) _buildErrorText(_confirmPasswordError!),
        
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: _isSubmitting ? null : _onRegisterPressed,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(
              _isSubmitting ? 'Đang xử lý...' : 'Đăng ký',
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

  Widget _buildBottomLogin() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          "Đã có tài khoản? ",
          style: TextStyle(
            color: Color(0xFF555555),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        GestureDetector(
          onTap: () => Navigator.pushReplacementNamed(context, '/login'),
          child: const Text(
            'Đăng nhập',
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
}
