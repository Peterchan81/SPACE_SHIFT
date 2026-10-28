import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

import 'core/ss_router.dart';
import 'core/ss_stage.dart';
import 'screens/login_screen.dart';
import 'services/app_update_store.dart';
import 'services/auth_service.dart';
import 'theme/space_shift_colors.dart';

/// SS002 §2 — 빌드 설정(`--dart-define`)으로만 읽는다. lib/services/auth_service.dart
/// 의 SupabaseAuthService가 읽는 값과 같은 dart-define 키라서 항상 같은 값이다.
const String _supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
const String _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // SS002 §2·§5 — 작업지시서가 이름으로 지정한 supabase_flutter를 실제로
  // 쓴다: 설정값(SUPABASE_URL/SUPABASE_ANON_KEY)이 모두 있을 때만 앱이 뜨기
  // 전에 Supabase.initialize()를 한 번 끝내 둔다. 이 호출이 supabase_flutter의
  // 기본 로컬 저장소에 저장된 세션을 복원하므로, 이후 AuthController.bootstrap()
  // 은 Supabase.instance.client.auth.currentSession만 읽으면 된다(자동 로그인).
  // 설정이 없으면 호출하지 않는다 — §2 "인증 설정이 없습니다" 안내가 그대로 동작한다.
  if (_supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty) {
    // SS002 §2(2026-10-28 #2 후속 지시) — anonKey는 설치된 supabase_flutter가
    // deprecated 안내하는 이름이다. 같은 SUPABASE_ANON_KEY 빌드 설정 값을
    // publishableKey로 넘긴다(빌드 설정 키 이름은 그대로).
    await supa.Supabase.initialize(url: _supabaseUrl, publishableKey: _supabaseAnonKey);
    // SS002 §5 — 이메일 인증 메일의 콜백 링크(딥링크)가 PKCE 코드 교환까지
    // 끝내 세션을 만들면(signedIn) AuthController가 그 신호를 받아 홈으로
    // 이동할 수 있게, 전역 Supabase 클라이언트의 인증 상태 스트림을 구독해
    // 둔다(설정이 없는 빌드에는 영향 없음).
    AuthController.instance.attachAuthStateListener();
  }

  // 인터넷 기반 무선 업데이트 확인은 Android에서만, 앱이 뜰 때 한 번
  // 배경으로 실행해 결과를 공유 싱글턴(AppUpdateStore.instance)에
  // 반영한다. 첫 프레임을 막지 않도록 await하지 않으며, 실패해도 예외를
  // 던지지 않는 AppUpdateService.checkForUpdate()를 그대로 재사용한다.
  if (!kIsWeb && Platform.isAndroid) {
    unawaited(AppUpdateStore.instance.checkForUpdate());
  }

  runApp(const AsonSpaceApp());
}

/// SPACE SHIFT 앱의 루트 위젯.
///
/// Material 3 테마를 사용하며, SS_V1_UI_MASTER.png 기준 화이트 + spectrum
/// 컬러 아이덴티티를 전역 테마로 적용한다. 첫 화면은 [_AuthGate]다 — SS002
/// §5 "자동 로그인": 앱 실행 시 [AuthController]로 저장된 Supabase 인증
/// 세션을 복원해, 유효하면 MASTER 홈([SsStage.home])으로, 없으면 MASTER UI
/// 1번 로그인 화면([LoginScreen])으로 바로 보낸다.
class AsonSpaceApp extends StatelessWidget {
  const AsonSpaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SPACE SHIFT',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: SpaceShiftColors.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: SpaceShiftColors.blue,
          secondary: SpaceShiftColors.purple,
        ),
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: SpaceShiftColors.textPrimary,
          displayColor: SpaceShiftColors.textPrimary,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: SpaceShiftColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: SpaceShiftColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: SpaceShiftColors.selectionAccent,
              width: 1.5,
            ),
          ),
        ),
      ),
      home: const _AuthGate(),
      // SS001 — 단계 이름으로 화면을 연다(core/ss_stage.dart). 기존 연결은 그대로, 이름으로 여는 경로만 더한다.
      onGenerateRoute: SsRouter.onGenerateRoute,
    );
  }
}

/// SS002 §5 — 앱이 뜰 때 가장 먼저 [AuthController.bootstrap]으로 저장된
/// 인증 세션을 복원하고, 그 결과에 따라 MASTER 홈 또는 로그인 화면을 보여준다.
/// 복원하는 짧은 동안에는 Dark Navy 배경에 로딩 표시만 두어(§6 3초 법칙 —
/// 화면이 멈춘 것처럼 보이지 않게) 화면이 비어 보이지 않게 한다.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  @override
  void initState() {
    super.initState();
    AuthController.instance.addListener(_onAuthChanged);
    unawaited(AuthController.instance.bootstrap());
  }

  @override
  void dispose() {
    AuthController.instance.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = AuthController.instance;
    if (!controller.initialized) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A1830),
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }
    return controller.isAuthenticated
        ? const SsStageScreen(stage: SsStage.home)
        : const LoginScreen();
  }
}
