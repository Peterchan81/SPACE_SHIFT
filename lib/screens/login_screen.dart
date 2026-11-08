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
/// SS-수정001 §1·§2 — 창 높이가 낮아도(예: 1024x640, 800x600) 카드 아래쪽
/// ("또는" 구분선·회원가입 버튼)이 잘리지 않도록, 고정 크기를 쌓던 기존
/// SingleChildScrollView 레이아웃을 걷어내고 [LayoutBuilder]로 실제 쓸 수
/// 있는 높이·너비를 보고 로고·제목·문구·간격을 비율로 줄이는 레이아웃으로
/// 바꿨다(세로 스크롤 없음). 이메일·비밀번호 입력과 로그인/회원가입 버튼은
/// 항상 최소 터치 높이(44px) 이상을 지킨다 — 줄어드는 건 로고·제목·문구·
/// 설명·간격뿐이다. MASTER 1번 디자인(배경 사진, 반투명 카드+halo, 무지개
/// 제목, 좌측·아래 치우침 Alignment)은 그대로 둔다.
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
    // SS-수정002 §3 — 앱 시작 시 세션 확인(AuthController.bootstrap)이
    // 네트워크 오류로 자동 로그인 여부를 확인하지 못한 경우에만 이 시점에
    // 이미 lastError가 채워져 있다(로그인 실패는 _login()이 직접 호출해야
    // 설정되므로 화면이 막 열린 시점엔 비어 있다) — 있으면 한 번만 보여준다.
    final bootstrapError = _controller.lastError;
    if (bootstrapError != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showMessage(bootstrapError);
      });
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
            child: Align(
              // MASTER UI 1번은 로고+카드 블록이 화면 왼쪽으로 치우쳐 배치되고,
              // 카드는 화면 세로 중앙보다 아래쪽(약 55~89% 높이)에 온다
              // (2026-10-28 추가 지시) — 왼쪽 치우침은 유지하고 아래쪽으로도
              // 치우치게 한다.
              alignment: const Alignment(-0.35, 0.35),
              child: LayoutBuilder(
                builder: (context, constraints) => _buildContent(constraints),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// SS-수정001 §1·§2 — 세로 스크롤 없이 한 창 안에 로고·제목·문구 2줄+설명
  /// 1줄·이메일/비밀번호 입력·로그인 버튼·"또는"·회원가입 버튼을 모두
  /// 보여준다. 실제 쓸 수 있는 높이([constraints.maxHeight])를 기준으로
  /// 0(가장 작은 창)~1(MASTER 원본 전체 크기) 비율 [t]를 계산해 로고·제목·
  /// 문구·설명·간격·카드 패딩만 선형 보간으로 줄인다. 이메일·비밀번호
  /// 입력(SizedBox로 44~52px 고정)과 로그인 버튼([GradientCtaButton], 고정
  /// 56px)·회원가입 버튼(44~52px)은 항상 최소 터치 높이(44px) 이상을 지켜
  /// 서로 겹치지 않는다 — 아주 작은 창에서는 설명 줄·로고부터 먼저 줄고,
  /// 입력·버튼은 마지막까지 유지된다.
  Widget _buildContent(BoxConstraints constraints) {
    final double availableHeight = constraints.maxHeight.isFinite ? constraints.maxHeight : 900.0;
    final double availableWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : 420.0;

    // t==0: 최소 크기(가장 작은 창에서도 겹치지 않고 다 보이는 크기),
    // t==1: MASTER 원본 전체 크기(2026-10-28 확정 치수).
    const double fullHeightBudget = 820.0;
    const double minHeightBudget = 460.0;
    final double t = ((availableHeight - minHeightBudget) / (fullHeightBudget - minHeightBudget)).clamp(0.0, 1.0);
    double lerp(double full, double min) => min + (full - min) * t;

    final double fullLogo = (availableWidth * 0.14).clamp(110.0, 220.0);
    final double logoSize = lerp(fullLogo, 48.0);
    final double titleFontSize = lerp(42.0, 20.0);
    final double subtitleFontSize = lerp(22.0, 14.0);
    final double descriptionFontSize = lerp(13.0, 10.0);
    final double outerPad = lerp(32.0, 10.0);
    final double logoTitleGap = lerp(16.0, 6.0);
    final double titleSubtitleGap = lerp(14.0, 4.0);
    final double subtitleDescGap = lerp(6.0, 2.0);
    final double descCardGap = lerp(26.0, 10.0);
    final double cardPadTop = lerp(24.0, 12.0);
    final double cardPadBottom = lerp(20.0, 10.0);
    final double cardPadHorizontal = lerp(24.0, 16.0);
    // 입력창·버튼의 최소 터치 높이(44px) 보장 — 줄어드는 하한이 44다.
    final double fieldHeight = lerp(52.0, 44.0);
    final double fieldVerticalPadding = ((fieldHeight - 24.0) / 2).clamp(4.0, 16.0);
    final double emailPasswordGap = lerp(14.0, 8.0);
    final double passwordButtonGap = lerp(18.0, 10.0);
    final double buttonDividerGap = lerp(18.0, 8.0);
    final double dividerSignupGap = lerp(18.0, 8.0);
    final double signupHeight = lerp(52.0, 44.0);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: outerPad),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: logoSize,
              height: logoSize,
              child: Image.asset('assets/icons/space_shift_symbol.png', fit: BoxFit.contain),
            ),
            SizedBox(height: logoTitleGap),
            ShaderMask(
              shaderCallback: (bounds) => SsMasterTheme.rainbow.createShader(bounds),
              child: Text(
                'SPACE SHIFT',
                key: const Key('loginTitle'),
                style: TextStyle(fontSize: titleFontSize, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1),
              ),
            ),
            SizedBox(height: titleSubtitleGap),
            Text(
              '공간의 변화를 만드는',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: subtitleFontSize, fontWeight: FontWeight.w800, color: Colors.white, height: 1.3),
            ),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '새로운 가능성, ',
                  style: TextStyle(fontSize: subtitleFontSize, fontWeight: FontWeight.w800, color: Colors.white),
                ),
                ShaderMask(
                  shaderCallback: (bounds) => SsMasterTheme.rainbow.createShader(bounds),
                  child: Text(
                    'SPACE SHIFT',
                    style: TextStyle(fontSize: subtitleFontSize, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ),
              ],
            ),
            SizedBox(height: subtitleDescGap),
            Text(
              'AI와 함께, 당신의 공간을 새롭게 디자인하세요.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: descriptionFontSize, color: const Color(0xFFCBD5E1)),
            ),
            SizedBox(height: descCardGap),
            Container(
              padding: EdgeInsets.fromLTRB(cardPadHorizontal, cardPadTop, cardPadHorizontal, cardPadBottom),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: fieldHeight,
                    child: TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        hintText: '이메일 주소',
                        prefixIcon: const Icon(Icons.mail_outline_rounded),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: fieldVerticalPadding),
                      ),
                    ),
                  ),
                  SizedBox(height: emailPasswordGap),
                  SizedBox(
                    height: fieldHeight,
                    child: TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        hintText: '비밀번호',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: fieldVerticalPadding),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: passwordButtonGap),
                  GradientCtaButton(
                    label: '로그인',
                    onPressed: _submitting ? null : _login,
                    trailingIcon: Icons.arrow_forward_rounded,
                  ),
                  SizedBox(height: buttonDividerGap),
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
                  SizedBox(height: dividerSignupGap),
                  SizedBox(
                    height: signupHeight,
                    child: OutlinedButton(
                      onPressed: _goToSignup,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
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
          ],
        ),
      ),
    );
  }
}
