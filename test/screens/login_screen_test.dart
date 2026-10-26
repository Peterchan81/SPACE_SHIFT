// SS002 §4~§6 — 로그인 화면: 입력 검증, 중복 요청 방지, 성공 시 MASTER 홈 이동,
// 실패/설정 누락 시 한국어 안내, 회원가입 전환. 실제 Supabase 연결 없이
// FakeAuthService만으로 검증한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/core/ss_stage.dart';
import 'package:ason_space/screens/login_screen.dart';
import 'package:ason_space/screens/signup_screen.dart';
import 'package:ason_space/services/auth_service.dart';
import 'package:ason_space/widgets/gradient_cta_button.dart';

void main() {
  Future<void> pumpLogin(
    WidgetTester tester, {
    FakeAuthService? service,
  }) async {
    final controller = AuthController(service: service ?? FakeAuthService());
    await tester.pumpWidget(
      MaterialApp(home: LoginScreen(authController: controller)),
    );
    await tester.pump();
  }

  testWidgets('이메일·비밀번호 입력창과 로그인 버튼, 회원가입 링크가 보인다', (tester) async {
    await pumpLogin(tester);

    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.byType(GradientCtaButton), findsOneWidget);
    expect(find.text('회원가입'), findsOneWidget);
  });

  testWidgets('비밀번호 보기/숨기기 아이콘이 동작한다', (tester) async {
    await pumpLogin(tester);

    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pump();
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
  });

  testWidgets('이메일·비밀번호가 비어 있으면 로그인을 진행하지 않고 안내한다', (tester) async {
    await pumpLogin(tester);

    await tester.tap(find.byType(GradientCtaButton));
    await tester.pump();

    expect(find.text('이메일과 비밀번호를 입력해주세요.'), findsOneWidget);
  });

  testWidgets('이메일 형식이 올바르지 않으면 안내하고 진행하지 않는다', (tester) async {
    await pumpLogin(tester);

    await tester.enterText(find.byType(TextField).first, 'not-an-email');
    await tester.enterText(find.byType(TextField).last, 'password1');
    await tester.tap(find.byType(GradientCtaButton));
    await tester.pump();

    expect(find.text('올바른 이메일 형식이 아닙니다.'), findsOneWidget);
  });

  testWidgets('등록된 이메일·비밀번호로 로그인하면 MASTER 홈으로 이동한다', (tester) async {
    tester.view.physicalSize = const Size(2000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final fake = FakeAuthService();
    await fake.signUp(email: 'user@example.com', password: 'password1');

    await pumpLogin(tester, service: fake);
    await tester.enterText(find.byType(TextField).first, 'user@example.com');
    await tester.enterText(find.byType(TextField).last, 'password1');
    await tester.tap(find.byType(GradientCtaButton));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byKey(const Key('ssStageTitle')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('ssStageTitle'))).data,
      SsStage.home.title,
    );
  });

  testWidgets('잘못된 비밀번호로 로그인하면 오류를 안내하고 화면에 머문다', (tester) async {
    final fake = FakeAuthService();
    await fake.signUp(email: 'user2@example.com', password: 'password1');

    await pumpLogin(tester, service: fake);
    await tester.enterText(find.byType(TextField).first, 'user2@example.com');
    await tester.enterText(find.byType(TextField).last, 'wrongpass');
    await tester.tap(find.byType(GradientCtaButton));
    await tester.pumpAndSettle();

    expect(find.text('이메일 또는 비밀번호가 올바르지 않습니다.'), findsOneWidget);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('이메일 확인이 필요한 계정은 안내하고 홈으로 이동시키지 않는다', (tester) async {
    final fake = FakeAuthService(requireEmailConfirmation: true);
    await fake.signUp(email: 'needsconfirm@example.com', password: 'password1');

    await pumpLogin(tester, service: fake);
    await tester.enterText(
      find.byType(TextField).first,
      'needsconfirm@example.com',
    );
    await tester.enterText(find.byType(TextField).last, 'password1');
    await tester.tap(find.byType(GradientCtaButton));
    await tester.pumpAndSettle();

    expect(find.text('이메일 확인이 필요합니다. 메일함을 확인해주세요.'), findsOneWidget);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('인증 설정이 없으면 로그인을 진행하지 않고 안내한다', (tester) async {
    await pumpLogin(tester, service: FakeAuthService(configured: false));

    await tester.enterText(find.byType(TextField).first, 'user@example.com');
    await tester.enterText(find.byType(TextField).last, 'password1');
    await tester.tap(find.byType(GradientCtaButton));
    await tester.pump();

    expect(find.text(kAuthNotConfiguredMessage), findsOneWidget);
  });

  testWidgets('"회원가입" 링크를 누르면 회원가입 화면으로 이동한다', (tester) async {
    await pumpLogin(tester);

    await tester.tap(find.text('회원가입'));
    await tester.pumpAndSettle();

    expect(find.byType(SignupScreen), findsOneWidget);
  });
}
