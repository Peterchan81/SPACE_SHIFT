import 'package:flutter/material.dart';

import '../core/ss_router.dart';
import '../core/ss_stage.dart';
import '../services/auth_service.dart';
import '../theme/ss_master_theme.dart';
import '../widgets/gradient_cta_button.dart';
import 'signup_screen.dart';

/// MASTER UI 1번 화면 — 로그인 / 자동로그인.
///
/// 2026-09-28 확정 MASTER UI 1번 기준(SS002 §1): Dark Navy 배경 위에 SPACE
/// SHIFT 브랜드 사진(assets/images/ss_login_background.jpg)을 깔고, 무지개
/// SS 로고 + "SPACE SHIFT" 타이틀, 흰색 반투명 카드 안에 이메일·비밀번호
/// 입력과 로그인/회원가입 버튼을 둔다. lib/theme/ss_master_theme.dart의
/// 기존 MASTER 테마를 재사용하며, 화면 전체를 임의로 재설계하지 않는다.
///
/// 인증은 [AuthService] 인터페이스(§2) 뒤에서 [AuthController]가 담당한다.
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

  /// SS002 §4 — 실제 Supabase Auth 이메일·비밀번호 로그인. 인증 없이 바로
  /// 작업 화면으로 들어가던 기존 _enterApp 우회 경로는 없다 — 반드시
  /// [AuthController.signIn] 성공을 거쳐야만 홈으로 이동한다.
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
    Navigator.of(context).push(MaterialPageRoute(builder: (context) => const SignupScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SsMasterTheme.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // MASTER UI 1번 배경 사진(사용자 승인 디자인 자산) — 새로 그리거나
          // 다른 그림으로 바꾸지 않고 그대로 쓴다.
          Image.asset('assets/images/ss_login_background.jpg', fit: BoxFit.cover),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  SsMasterTheme.background.withValues(alpha: 0.30),
                  SsMasterTheme.background.withValues(alpha: 0.10),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 96,
                        height: 96,
                        child: Image.asset('assets/icons/space_shift_symbol.png', fit: BoxFit.contain),
                      ),
                      const SizedBox(height: 14),
                      ShaderMask(
                        shaderCallback: (bounds) => SsMasterTheme.rainbow.createShader(bounds),
                        child: const Text(
                          'SPACE SHIFT',
                          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        '공간의 변화를 만드는\n새로운 가능성, SPACE SHIFT',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white, height: 1.3),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'AI와 함께, 당신의 공간을 새롭게 디자인하세요.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: Color(0xFFCBD5E1)),
                      ),
                      const SizedBox(height: 26),
                      Container(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.97),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 24, offset: const Offset(0, 12)),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                hintText: '이메일 주소',
                                prefixIcon: Icon(Icons.mail_outline_rounded),
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
                                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                  icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            GradientCtaButton(label: '로그인', onPressed: _submitting ? null : _login),
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                const Expanded(child: Divider(color: Color(0xFFE2E8F0))),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: Text('또는', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                                ),
                                const Expanded(child: Divider(color: Color(0xFFE2E8F0))),
                              ],
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              height: 52,
                              child: OutlinedButton(
                                onPressed: _goToSignup,
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                                child: const Text(
                                  '회원가입',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF6D28D9)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
