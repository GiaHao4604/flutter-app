import 'package:flutter/material.dart';
import 'package:flutter_application_1/services/auth_api_service.dart';

// Inlined theme tokens from lib/theme/registertheme.dart (merged per request)
const Color darkgray = Color(0xFF9E9E9E);
const Color ghostwhite = Color(0xFFEEEEF4);
const Color gray = Color(0xFF01010F);
const Color mediumslateblue100 = Color(0xFF4E46DD);
const Color mediumslateblue200 = Color(0xFF5E4DED);
const Color white = Color(0xFFFFFFFF);
const Color whitesmoke = Color(0xFFF9F9F9);

const double br11 = 11;
const double fs15 = 15;
const double fs24 = 24;
const double height14 = 14;
const double height24 = 24;
const double height50 = 50;
const double padding0 = 0;
const double padding14 = 14;
const double padding15 = 15;
const double padding24 = 24;
const double width24 = 24;
const double width300 = 300;
const double width324 = 324;
const double width357 = 357;

const List<BoxShadow> shadowDrop = [
  BoxShadow(
    color: Color(0x40000000),
    blurRadius: 4,
    spreadRadius: 0,
    offset: Offset(0, 4),
  ),
];

class Register extends StatefulWidget {
  const Register({super.key});

  @override
  State<Register> createState() => _RegisterState();
}

class _RegisterState extends State<Register> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _showValidation = false;
  bool _isSubmitting = false;

  final AuthApiService _authApiService = AuthApiService();

  String? _nameError;
  String? _emailError;
  String? _passwordError;
  String? _confirmPasswordError;

  Future<void> _validateForm() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

    setState(() {
      _showValidation = true;
      _nameError = name.isEmpty ? 'Vui lòng nhập họ tên' : null;
      _emailError = emailPattern.hasMatch(email) ? null : 'Email không hợp lệ';
      _passwordError = password.length >= 6
          ? null
          : 'Mật khẩu tối thiểu 6 kí tự';
      _confirmPasswordError = confirmPassword == password
          ? null
          : 'Mật khẩu nhập lại không khớp';
    });

    if (_nameError != null ||
        _emailError != null ||
        _passwordError != null ||
        _confirmPasswordError != null) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final result = await _authApiService.register(
      name: name,
      email: email,
      password: password,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isSubmitting = false;
    });

    if (result.success) {
      await _showRegisterSuccess();
      return;
    }

    await _showRegisterFailed(message: result.message);
  }

  Future<void> _showRegisterSuccess() {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
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
                  decoration: const BoxDecoration(
                    color: Color(0xFFE3F7ED),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    color: Color(0xFF36B37E),
                    size: 26,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'thành công',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF212121),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Đăng ký thành công, hãy đăng nhập',
                  style: TextStyle(
                    fontSize: 16,
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
                      Navigator.of(context).pop();
                      Navigator.pushReplacementNamed(context, '/login');
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF36B37E),
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('OK'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showRegisterFailed({required String message}) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
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
                  decoration: const BoxDecoration(
                    color: Color(0xFFFCE7E7),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.info_outline,
                    color: Color(0xFFD13B33),
                    size: 26,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Đăng ký không thành công',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF212121),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 16,
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
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFD13B33),
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Thử lại'),
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
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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
    );
  }

  Widget _buildBrand() {
    return Column(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
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
        SizedBox(height: 12),
        Text(
          'Kỹ Năng Sống 4.0',
          style: TextStyle(
            color: white,
            fontSize: 32,
            fontWeight: FontWeight.w800,
            shadows: shadowDrop,
          ),
        ),
        SizedBox(height: 6),
        Text(
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
              Expanded(
                child: _TabItem(
                  text: 'Đăng nhập',
                  isActive: false,
                  onTap: () =>
                      Navigator.pushReplacementNamed(context, '/login'),
                ),
              ),
              const SizedBox(width: 18),
              const Expanded(child: _TabItem(text: 'Đăng ký', isActive: true)),
            ],
          ),
          const SizedBox(height: 10),
          _buildInputField(
            controller: _nameController,
            hintText: 'Họ và tên',
            prefixIcon: Icons.person_outline,
            keyboardType: TextInputType.name,
            hasError: _showValidation && _nameError != null,
            iconColor: _showValidation && _nameError != null
                ? const Color(0xFFFF3B3B)
                : null,
          ),
          if (_showValidation && _nameError != null)
            _buildErrorText(_nameError!),
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
            hintText: 'Mật khẩu (tối đa 6 kí tự)',
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
          const SizedBox(height: 8),
          _buildInputField(
            controller: _confirmPasswordController,
            hintText: 'Nhập lại mật khẩu',
            prefixIcon: Icons.lock_outline,
            obscureText: !_isConfirmPasswordVisible,
            hasError: _showValidation && _confirmPasswordError != null,
            iconColor: _showValidation && _confirmPasswordError != null
                ? const Color(0xFFFF3B3B)
                : null,
            suffix: IconButton(
              splashRadius: 18,
              onPressed: () {
                setState(
                  () => _isConfirmPasswordVisible = !_isConfirmPasswordVisible,
                );
              },
              icon: Icon(
                _isConfirmPasswordVisible
                    ? Icons.visibility_off
                    : Icons.visibility,
                size: 18,
                color: _showValidation && _confirmPasswordError != null
                    ? const Color(0xFFFF3B3B)
                    : const Color(0xFF5E606A),
              ),
            ),
          ),
          if (_showValidation && _confirmPasswordError != null)
            _buildErrorText(_confirmPasswordError!),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton(
              onPressed: _isSubmitting ? null : _validateForm,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF4A46DE),
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                _isSubmitting ? 'Đang xử lý...' : 'Tạo tài khoản',
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
