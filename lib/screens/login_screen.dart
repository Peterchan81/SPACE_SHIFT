import 'package:flutter/material.dart';

import '../core/ss_router.dart';
import '../core/ss_stage.dart';
import '../services/auth_service.dart';
import '../theme/ss_master_theme.dart';
import '../widgets/gradient_cta_button.dart';
import 'home_screen.dart';
import 'signup_screen.dart';

/// MASTER UI 1번 화면 — 로그인 / 자동로그인.
///
/// 2026-09-28 확정 MASTER UI 1번 기준(SS002 §1): Dark Navy 배경 위에 SPACE
/// SHIFT 브랜드 사진(assets/images/ss_login_background.jpg)을 깔고, 무지개
/// SS 로고 + "SPACE SHIFT" 타이틀, 흰색 반투명 카드 안에 이메일·비밀번호
/// 입력과 로그인/회원가입 버튼을 둔다. lib/theme/ss_master_theme.dart의
/// 기존 MASTER 테마를 재사용하며, 화면 전체를 임의로 재설계하지 않는다.
///
/// MASTER 원본에서는 로고+카드 블록이 화면 왼쪽으로 치우쳐 배치되고, 카드가
/// 배경과 부드러운 흰 빛 번짐(halo)으로 섞인다(검토 §1 지적) — 중앙 정렬 +
/// 검은 그림자 박스 대신 좌측 치우침 Align + 흰 halo로 맞춘다.
///
/// SS-수정001(2026-11-08) — 고정 크기를 그대로 쌓은 SingleChildScrollView가
/// 창 높이가 낮으면 카드 아래쪽(구분선·회원가입 버튼)을 화면 밖으로 밀어내던
/// 문제를 고친다. [LayoutBuilder]로 받은 실제 사용 가능한 높이·너비에 맞춰
/// 로고·제목·문구·간격을 비율로 줄이고(§2), 입력창·버튼은 최소 터치 높이
/// (44px)를 지키며 세로 스크롤 없이 모두 한 창 안에 보이게 한다. MASTER 1번
/// 디자인(배경 사진 BoxFit.cover, 반투명 흰 카드+halo, 무지개 제목, 좌측·
/// 아래 치우침 Alignment(-0.35, 0.35), 색상)은 그대로 둔다 — 새 이미지·색은
/// 쓰지 않는다.
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
  void initState() {
    super.initState();
    // SS-수정002 §3 — 앱 시작 시 저장된 세션 갱신을 네트워크 오류로 확인하지
    // 못해 로그인 화면으로 왔으면, 그 이유를 한 번 보여준다
    // (consumeBootstrapMessage가 한 번 읽으면 비워져 다시 열 때는 뜨지
    // 않는다).
    final bootstrapMessage = _controller.consumeBootstrapMessage();
    if (bootstrapMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showMessage(bootstrapMessage));
    }
  }

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
        builder: (context) => const SsStageScreen(stage: SsStage.home, child: HomeScreen()),
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Align(
                  // MASTER UI 1번은 로고+카드 블록이 화면 왼쪽으로 치우쳐
                  // 배치되고, 카드는 화면 세로 중앙보다 아래쪽에 온다
                  // (2026-10-28 추가 지시) — SS-수정001에서도 그대로 둔다.
                  alignment: const Alignment(-0.35, 0.35),
                  child: _LoginCard(
                    availableHeight: constraints.maxHeight,
                    availableWidth: constraints.maxWidth,
                    emailController: _emailController,
                    passwordController: _passwordController,
                    obscurePassword: _obscurePassword,
                    onToggleObscurePassword: () => setState(() => _obscurePassword = !_obscurePassword),
                    submitting: _submitting,
                    onLogin: _login,
                    onSignup: _goToSignup,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// SS-수정001 — 로고부터 회원가입 버튼까지 세로 스크롤 없이 한 창 안에 담는
/// 카드. [availableHeight]가 기준 높이(900 — 기존 고정 레이아웃이 그대로
/// 보였던 높이 근사값)보다 낮으면 로고·제목·문구·간격을 비율로 줄인다(§2).
/// 입력창·회원가입 버튼은 최소 44px 터치 높이를 지킨다(로그인 버튼은
/// [GradientCtaButton]의 고정 56px이라 항상 만족한다). MASTER 1번 디자인
/// (배경 사진·반투명 카드+halo·무지개 제목·색상)은 바꾸지 않는다.
class _LoginCard extends StatelessWidget {
  const _LoginCard({
    required this.availableHeight,
    required this.availableWidth,
    required this.emailController,
    required this.passwordController,
    required this.obscurePassword,
    required this.onToggleObscurePassword,
    required this.submitting,
    required this.onLogin,
    required this.onSignup,
  });

  final double availableHeight;
  final double availableWidth;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final VoidCallback onToggleObscurePassword;
  final bool submitting;
  final VoidCallback onLogin;
  final VoidCallback onSignup;

  @override
  Widget build(BuildContext context) {
    // 기준 높이 — 기존 고정 레이아웃(로고 14%, 제목42, 문구22, 입력/버튼52,
    // 간격 합계 750px 이상)이 세로 스크롤 없이 그대로 보였던 창 높이
    // 근사값. 그보다 높은 창(예: 1920x1080, 800x1280)에서는 원래 크기를
    // 그대로 쓰고, 낮은 창(1280x720·1024x640·800x600)에서는 이 비율대로
    // 줄인다 — 각 요소의 최소값은 아래에서 보장한다(§2).
    const referenceHeight = 900.0;
    final heightScale = (availableHeight / referenceHeight).clamp(0.5, 1.0).toDouble();

    final cardMaxWidth = availableWidth < 48 ? availableWidth : (availableWidth - 48).clamp(0.0, 420.0).toDouble();

    final logoSize = (cardMaxWidth * 0.14 * heightScale).clamp(56.0, 220.0).toDouble();
    final titleSize = (42.0 * heightScale).clamp(24.0, 42.0).toDouble();
    final subtitleSize = (22.0 * heightScale).clamp(15.0, 22.0).toDouble();
    final captionSize = (13.0 * heightScale).clamp(11.0, 13.0).toDouble();
    final fieldVerticalPadding = (16.0 * heightScale).clamp(10.0, 16.0).toDouble();
    final signupButtonHeight = (52.0 * heightScale).clamp(44.0, 52.0).toDouble();

    final outerVerticalPadding = (16.0 * heightScale).clamp(8.0, 16.0).toDouble();
    final gapAfterLogo = (16.0 * heightScale).clamp(6.0, 16.0).toDouble();
    final gapAfterTitle = (14.0 * heightScale).clamp(6.0, 14.0).toDouble();
    final gapBeforeCaption = (6.0 * heightScale).clamp(2.0, 6.0).toDouble();
    final gapAfterCaption = (26.0 * heightScale).clamp(10.0, 26.0).toDouble();
    final cardPaddingTop = (24.0 * heightScale).clamp(14.0, 24.0).toDouble();
    final cardPaddingBottom = (20.0 * heightScale).clamp(12.0, 20.0).toDouble();
    final gapBetweenFields = (14.0 * heightScale).clamp(8.0, 14.0).toDouble();
    final gapBeforeLoginButton = (18.0 * heightScale).clamp(8.0, 18.0).toDouble();
    final gapBeforeDivider = (18.0 * heightScale).clamp(8.0, 18.0).toDouble();
    final gapAfterDivider = (18.0 * heightScale).clamp(8.0, 18.0).toDouble();

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: outerVerticalPadding),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: cardMaxWidth),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: logoSize,
              height: logoSize,
              child: Image.asset('assets/icons/space_shift_symbol.png', fit: BoxFit.contain),
            ),
            SizedBox(height: gapAfterLogo),
            ShaderMask(
              shaderCallback: (bounds) => SsMasterTheme.rainbow.createShader(bounds),
              child: Text(
                'SPACE SHIFT',
                key: const Key('loginTitle'),
                style: TextStyle(fontSize: titleSize, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1),
              ),
            ),
            SizedBox(height: gapAfterTitle),
            Text(
              '공간의 변화를 만드는',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: subtitleSize, fontWeight: FontWeight.w800, color: Colors.white, height: 1.25),
            ),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('새로운 가능성, ', style: TextStyle(fontSize: subtitleSize, fontWeight: FontWeight.w800, color: Colors.white)),
                ShaderMask(
                  shaderCallback: (bounds) => SsMasterTheme.rainbow.createShader(bounds),
                  child: Text('SPACE SHIFT', style: TextStyle(fontSize: subtitleSize, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ],
            ),
            SizedBox(height: gapBeforeCaption),
            Text(
              'AI와 함께, 당신의 공간을 새롭게 디자인하세요.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: captionSize, color: const Color(0xFFCBD5E1)),
            ),
            SizedBox(height: gapAfterCaption),
            Container(
              padding: EdgeInsets.fromLTRB(24, cardPaddingTop, 24, cardPaddingBottom),
              decoration: BoxDecoration(
                // MASTER 원본처럼 카드 배경이 완전한 불투명 흰색이
                // 아니라 뒤 배경이 살짝 비치는 반투명 흰색이다
                // (2026-10-28 추가 지시).
                color: Colors.white.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(20),
                // MASTER 원본처럼 카드 주위가 배경과 부드러운 흰 빛
                // 번짐(halo)으로 섞이도록 한다 — 검은 그림자만으로는
                // 원본과 달리 카드가 딱딱한 박스처럼 떠 보인다.
                boxShadow: [
                  BoxShadow(color: Colors.white.withValues(alpha: 0.45), blurRadius: 48, offset: const Offset(0, 0)),
                  BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 20, offset: const Offset(0, 10)),
                ],
              ),
              child: Theme(
                data: Theme.of(context).copyWith(
                  inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: fieldVerticalPadding),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        hintText: '이메일 주소',
                        prefixIcon: Icon(Icons.mail_outline_rounded),
                      ),
                    ),
                    SizedBox(height: gapBetweenFields),
                    TextField(
                      controller: passwordController,
                      obscureText: obscurePassword,
                      decoration: InputDecoration(
                        hintText: '비밀번호',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          onPressed: onToggleObscurePassword,
                          icon: Icon(obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        ),
                      ),
                    ),
                    SizedBox(height: gapBeforeLoginButton),
                    GradientCtaButton(
                      label: '로그인',
                      onPressed: submitting ? null : onLogin,
                      trailingIcon: Icons.arrow_forward_rounded,
                    ),
                    SizedBox(height: gapBeforeDivider),
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
                    SizedBox(height: gapAfterDivider),
                    SizedBox(
                      height: signupButtonHeight,
                      child: OutlinedButton(
                        onPressed: onSignup,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Text(
                              '회원가입',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF6D28D9)),
                            ),
                            SizedBox(width: 8),
                            Icon(Icons.arrow_forward_rounded, size: 18, color: Color(0xFF6D28D9)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
