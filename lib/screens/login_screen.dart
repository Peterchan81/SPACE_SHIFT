import 'package:flutter/material.dart';

import '../core/ss_router.dart';
import '../core/ss_stage.dart';
import '../services/auth_service.dart';
import '../theme/space_shift_colors.dart';
import '../widgets/gradient_cta_button.dart';
import 'signup_screen.dart';

/// MASTER UI 1번 화면 — 로그인 / 자동로그인.
///
/// 앱 실행 시 가장 먼저 보여지는 화면으로, SPACE SHIFT 로고와 아이디/비밀번호
/// 입력, 자동 로그인, 간편 로그인, 회원가입 진입을 제공한다.
///
/// 실제 인증 백엔드는 아직 준비되지 않았으므로, 이 화면은 로그인 UI와
/// 정상적인 앱 진입 흐름(신규 MASTER 메인 작업 화면[FloorPlanWorkspaceScreen]
/// 으로 이동)만 구현하고 실제 계정 검증은 하지 않는다.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.authController});

  /// 테스트에서 [FakeAuthService]를 주입할 수 있게 한다. 지정하지 않으면
  /// 앱 전체가 공유하는 [AuthController.instance]를 쓴다.
  final AuthController? authController;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _autoLogin = true;
  bool _obscurePassword = true;
  bool _submitting = false;

  AuthController get _controller => widget.authController ?? AuthController.instance;

  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showComingSoon() => _showMessage('아직 준비 중인 기능입니다.');

  /// SS002 §4 — 실제 Supabase Auth 이메일·비밀번호 로그인. 인증 없이 바로
  /// 작업 화면으로 들어가던 기존 _enterApp 우회 경로는 제거했다.
  Future<void> _login() async {
    if (_submitting) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (!_controller.isConfigured) {
      _showMessage(kAuthNotConfiguredMessage);
      return;
    }
    if (email.isEmpty || password.isEmpty) {
      _showMessage('이메일과 비밀번호를 입력해주세요.');
      return;
    }
    if (!_emailPattern.hasMatch(email)) {
      _showMessage('올바른 이메일 형식이 아닙니다.');
      return;
    }
    setState(() => _submitting = true);
    final result = await _controller.signIn(email: email, password: password);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result.isSuccess) {
      _enterApp();
    } else {
      _showMessage(result.message ?? '로그인에 실패했습니다.');
    }
  }

  /// 로그인 성공 후 MASTER 홈([SsStage.home])으로 이동한다(§4) — 기존
  /// FloorPlanWorkspaceScreen으로 직접 진입시키지 않는다.
  void _enterApp() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => const SsStageScreen(stage: SsStage.home),
        settings: RouteSettings(name: SsStage.home.routeName),
      ),
      (route) => false,
    );
  }

  void _goToSignup() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const SignupScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpaceShiftColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  const Center(child: _SpaceShiftLogoMark()),
                  const SizedBox(height: 20),
                  const Text(
                    'SPACE SHIFT',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: SpaceShiftColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '공간의 변화, 당신의 방식으로',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: SpaceShiftColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      hintText: '이메일',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      hintText: '비밀번호',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: _autoLogin,
                          activeColor: SpaceShiftColors.selectionAccent,
                          onChanged: (value) =>
                              setState(() => _autoLogin = value ?? false),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '자동 로그인',
                        style: TextStyle(
                          fontSize: 13,
                          color: SpaceShiftColors.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _showComingSoon,
                        child: const Text(
                          '비밀번호 찾기',
                          style: TextStyle(
                            fontSize: 13,
                            color: SpaceShiftColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  GradientCtaButton(label: '로그인', onPressed: _submitting ? null : _login),
                  const SizedBox(height: 28),
                  Row(
                    children: const [
                      Expanded(child: Divider(color: SpaceShiftColors.border)),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          '간편 로그인',
                          style: TextStyle(
                            fontSize: 12,
                            color: SpaceShiftColors.textSecondary,
                          ),
                        ),
                      ),
                      Expanded(child: Divider(color: SpaceShiftColors.border)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _SocialLoginButton(
                        icon: Icons.g_mobiledata_rounded,
                        background: const Color(0xFFF2F2F2),
                        foreground: const Color(0xFF1F2933),
                        onTap: _showComingSoon,
                      ),
                      const SizedBox(width: 18),
                      _SocialLoginButton(
                        icon: Icons.chat_bubble_rounded,
                        background: const Color(0xFFFEE500),
                        foreground: const Color(0xFF3C1E1E),
                        onTap: _showComingSoon,
                      ),
                      const SizedBox(width: 18),
                      _SocialLoginButton(
                        icon: Icons.apple_rounded,
                        background: const Color(0xFF1F2933),
                        foreground: Colors.white,
                        onTap: _showComingSoon,
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        '계정이 없으신가요?',
                        style: TextStyle(
                          fontSize: 13,
                          color: SpaceShiftColors.textSecondary,
                        ),
                      ),
                      TextButton(
                        onPressed: _goToSignup,
                        child: const Text(
                          '회원가입',
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
    );
  }
}

/// SPACE SHIFT 공식 심볼(assets/icons/space_shift_symbol.png)을 그대로
/// 보여준다. 원본은 공식 로고 전체 이미지(assets/icons/
/// space_shift_official_logo.png, "SPACE SHIFT" 워드마크 포함)에서 심볼
/// 영역만 잘라낸 것 — 원본 파일 자체는 수정하지 않고 보존한다.
class _SpaceShiftLogoMark extends StatelessWidget {
  const _SpaceShiftLogoMark();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 78,
      height: 80,
      child: Image.asset(
        'assets/icons/space_shift_symbol.png',
        fit: BoxFit.contain,
      ),
    );
  }
}

class _SocialLoginButton extends StatelessWidget {
  const _SocialLoginButton({
    required this.icon,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 52,
          height: 52,
          child: Icon(icon, color: foreground),
        ),
      ),
    );
  }
}
