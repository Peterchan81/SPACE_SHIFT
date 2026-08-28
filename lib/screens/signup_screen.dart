import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/image_picker_service.dart';
import '../theme/space_shift_colors.dart';
import '../widgets/gradient_cta_button.dart';
import 'photo_select_screen.dart';

/// MASTER UI 1번 화면(회원가입 상태) — 이름/이메일/비밀번호와 약관 동의로
/// 신규 계정을 만드는 화면.
///
/// 실제 인증 백엔드가 없으므로 입력값 검증(필수 항목, 비밀번호 일치, 약관
/// 동의)만 수행하고, 통과하면 곧바로 앱 사용 흐름(사진 선택 화면)으로
/// 진입시킨다.
class SignupScreen extends StatefulWidget {
  const SignupScreen({
    super.key,
    this.imagePickerService = const ImagePickerService(),
  });

  final ImagePickerService imagePickerService;

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmController = TextEditingController();
  bool _agreed = false;
  Uint8List? _profileImageBytes;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    super.dispose();
  }

  Future<void> _pickProfileImage() async {
    try {
      final bytes = await widget.imagePickerService.pickGalleryImage();
      if (bytes == null || !mounted) return;
      setState(() => _profileImageBytes = bytes);
    } catch (_) {
      // 프로필 사진은 선택 항목이므로 실패해도 조용히 무시한다.
    }
  }

  String? _requiredValidator(String? value) {
    return (value == null || value.trim().isEmpty) ? '필수 항목입니다.' : null;
  }

  void _submit() {
    final formOk = _formKey.currentState?.validate() ?? false;
    if (!formOk) return;
    if (_passwordController.text != _passwordConfirmController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('비밀번호가 일치하지 않습니다.')),
      );
      return;
    }
    if (!_agreed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이용약관 및 개인정보처리방침에 동의해주세요.')),
      );
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => const PhotoSelectScreen(),
        settings: const RouteSettings(name: 'photo_select'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpaceShiftColors.background,
      appBar: AppBar(
        backgroundColor: SpaceShiftColors.background,
        foregroundColor: SpaceShiftColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text('회원가입'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: GestureDetector(
                        onTap: _pickProfileImage,
                        child: Container(
                          width: 88,
                          height: 88,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7F8FA),
                            shape: BoxShape.circle,
                            border: Border.all(color: SpaceShiftColors.border),
                          ),
                          child: _profileImageBytes == null
                              ? const Icon(
                                  Icons.camera_alt_rounded,
                                  size: 30,
                                  color: SpaceShiftColors.textSecondary,
                                )
                              : Image.memory(
                                  _profileImageBytes!,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Center(
                      child: Text(
                        '프로필 사진 (선택)',
                        style: TextStyle(
                          fontSize: 12,
                          color: SpaceShiftColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(hintText: '이름'),
                      validator: _requiredValidator,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(hintText: '이메일'),
                      validator: _requiredValidator,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(hintText: '비밀번호'),
                      validator: _requiredValidator,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _passwordConfirmController,
                      obscureText: true,
                      decoration: const InputDecoration(hintText: '비밀번호 확인'),
                      validator: _requiredValidator,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Checkbox(
                            value: _agreed,
                            activeColor: SpaceShiftColors.selectionAccent,
                            onChanged: (value) =>
                                setState(() => _agreed = value ?? false),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            '이용약관 및 개인정보처리방침에 동의합니다.',
                            style: TextStyle(
                              fontSize: 13,
                              color: SpaceShiftColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    GradientCtaButton(label: '회원가입', onPressed: _submit),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          '이미 계정이 있으신가요?',
                          style: TextStyle(
                            fontSize: 13,
                            color: SpaceShiftColors.textSecondary,
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text(
                            '로그인',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: SpaceShiftColors.selectionAccent,
                            ),
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
      ),
    );
  }
}
