import 'package:flutter/material.dart';

import '../core/ss_router.dart';
import '../core/ss_stage.dart';
import '../services/auth_service.dart';
import '../theme/space_shift_colors.dart';
import '../widgets/gradient_cta_button.dart';
import 'login_screen.dart';

/// SS002 §3·§6(2026-10-28 #2 후속 지시) — 회원가입 직후 이메일 확인이
/// 필요할 때(AuthStatus.needsEmailConfirmation) 보여주는 안내 화면.
///
/// - 「인증 메일 다시 보내기」: [AuthController.resendConfirmation] 호출(§6
///   "요청 제한 및 이메일 발송 한도" 안내는 그 결과 메시지를 그대로 보여준다).
/// - 「인증을 마쳤어요」: 앱이 다시 앞으로 올 때 세션이 이미 생겼으면(이메일
///   링크의 딥링크 콜백이 먼저 처리된 경우, [AuthController.attachAuthStateListener])
///   바로 홈으로 보내고, 아니면 이 화면이 들고 있는 이메일·비밀번호로 로그인을
///   시도한다. 아직 인증 전이면 홈으로 보내지 않고 안내만 한다.
/// - 비밀번호는 메모리에만 있고 파일·로그·저장소 어디에도 쓰지 않으며, 이
///   화면을 떠나면([dispose]) 즉시 비운다.
class EmailConfirmationScreen extends StatefulWidget {
  const EmailConfirmationScreen({super.key, required this.email, required String password, this.authController}) : _password = password;

  final String email;
  final String _password;
  final AuthController? authController;

  @override
  State<EmailConfirmationScreen> createState() => _EmailConfirmationScreenState();
}

class _EmailConfirmationScreenState extends State<EmailConfirmationScreen> {
  String? _password;
  bool _submitting = false;
  String? _notice;

  AuthController get _controller => widget.authController ?? AuthController.instance;

  @override
  void initState() {
    super.initState();
    _password = widget._password;
    _controller.addListener(_onAuthChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onAuthChanged);
    // 비밀번호는 이 화면을 떠나는 즉시 메모리에서 지운다(파일·로그·저장소에
    // 남기지 않는다는 작업지시서 규칙).
    _password = null;
    super.dispose();
  }

  void _onAuthChanged() {
    if (!mounted) return;
    if (_controller.isAuthenticated) {
      _goHome();
      return;
    }
    final linkError = _controller.emailLinkError;
    if (linkError != null) {
      setState(() => _notice = linkError);
      _controller.clearEmailLinkError();
    }
  }

  void _goHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const SsStageScreen(stage: SsStage.home), settings: RouteSettings(name: SsStage.home.routeName)),
      (route) => false,
    );
  }

  void _goToLogin() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen(), settings: const RouteSettings(name: '/login')),
      (route) => false,
    );
  }

  Future<void> _resend() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final result = await _controller.resendConfirmation(email: widget.email);
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _notice = result.message;
    });
  }

  Future<void> _iVerified() async {
    if (_submitting) return;
    if (_controller.isAuthenticated) {
      _goHome();
      return;
    }
    final password = _password;
    if (password == null) return;
    setState(() => _submitting = true);
    final result = await _controller.signIn(email: widget.email, password: password);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result.isSuccess) {
      _goHome();
    } else if (result.errorKind == AuthErrorKind.emailNotConfirmed) {
      setState(() => _notice = '아직 이메일 인증이 확인되지 않았습니다.');
    } else {
      setState(() => _notice = result.message ?? '다시 시도해주세요.');
    }
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
        title: const Text('이메일 확인'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.mark_email_unread_outlined, size: 56, color: SpaceShiftColors.selectionAccent),
                  const SizedBox(height: 16),
                  Text(
                    '${widget.email}로 확인 메일을 보냈습니다.',
                    key: const Key('emailConfirmationMessage'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: SpaceShiftColors.textPrimary),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '메일의 링크를 눌러 이메일 인증을 완료해주세요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: SpaceShiftColors.textSecondary),
                  ),
                  if (_notice != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _notice!,
                      key: const Key('emailConfirmationNotice'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.redAccent),
                    ),
                  ],
                  const SizedBox(height: 28),
                  GradientCtaButton(label: '인증을 마쳤어요', onPressed: _submitting ? null : _iVerified),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      key: const Key('resendConfirmationButton'),
                      onPressed: _submitting ? null : _resend,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: SpaceShiftColors.border),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('인증 메일 다시 보내기'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextButton(
                    onPressed: _goToLogin,
                    child: const Text('로그인 화면으로', style: TextStyle(color: SpaceShiftColors.selectionAccent, fontWeight: FontWeight.bold)),
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
