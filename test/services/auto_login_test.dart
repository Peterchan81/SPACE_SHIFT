// SS-수정002 §3·§4·§5·§6·§8 — 자동 로그인(세션 확인·만료 시 refresh),
// 실행 중 인증 상태 이벤트 반영, 로그아웃, 보호 화면 접근 차단, 비밀번호가
// 어디에도 저장되지 않음을 실제 네트워크 없이(FakeAuthService/MockClient)
// 검증한다.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

import 'package:ason_space/core/ss_router.dart';
import 'package:ason_space/core/ss_stage.dart';
import 'package:ason_space/screens/login_screen.dart';
import 'package:ason_space/services/auth_service.dart';

Map<String, Object?> _userJson({required String id, required String email}) => {
  'id': id,
  'aud': 'authenticated',
  'role': 'authenticated',
  'email': email,
  'email_confirmed_at': '2024-01-01T00:00:00Z',
  'phone': '',
  'app_metadata': {'provider': 'email', 'providers': ['email']},
  'user_metadata': <String, Object?>{},
  'identities': <Object?>[],
  'created_at': '2024-01-01T00:00:00Z',
  'updated_at': '2024-01-01T00:00:00Z',
};

Map<String, Object?> _sessionJson({required String accessToken, required String refreshToken, required String userId, required String email}) => {
  'access_token': accessToken,
  'token_type': 'bearer',
  'expires_in': 3600,
  'expires_at': DateTime.now().toUtc().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
  'refresh_token': refreshToken,
  'user': _userJson(id: userId, email: email),
};

supa.SupabaseClient _testClient(Future<http.Response> Function(http.Request) handler) {
  return supa.SupabaseClient(
    'https://example.supabase.co',
    'anon-key',
    httpClient: MockClient(handler),
    authOptions: const supa.AuthClientOptions(authFlowType: supa.AuthFlowType.implicit),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SS-수정002 §3·§8 — bootstrap(checkSession) 자동 로그인', () {
    test('유효한 세션이 저장되어 있으면 bootstrap 후 즉시 인증 상태(바로 홈)가 된다', async () async {
      final fake = FakeAuthService();
      await fake.signUp(email: 'valid@example.com', password: 'password1');
      final controller = AuthController(service: fake);

      await controller.bootstrap();

      expect(controller.isAuthenticated, isTrue);
      expect(controller.lastError, isNull);
    });

    test('access token이 만료된 세션 + refresh 성공 → 인증 상태(홈)가 된다', async () async {
      final fake = FakeAuthService();
      await fake.signUp(email: 'expired-ok@example.com', password: 'password1');
      fake.injectExpiredSession(email: 'expired-ok@example.com');
      final controller = AuthController(service: fake);

      await controller.bootstrap();

      expect(controller.isAuthenticated, isTrue);
      expect(controller.session?.email, 'expired-ok@example.com');
    });

    test('만료된 세션 + refresh 실패(만료·무효·취소된 refresh token) → 로그인 화면(저장된 세션 삭제)', async () async {
      final fake = FakeAuthService(refreshShouldSucceed: false);
      await fake.signUp(email: 'expired-fail@example.com', password: 'password1');
      fake.injectExpiredSession(email: 'expired-fail@example.com');
      final controller = AuthController(service: fake);

      await controller.bootstrap();

      expect(controller.isAuthenticated, isFalse);
      expect(await fake.restoreSession(), isNull, reason: '저장된 세션이 지워졌다');
    });

    test('세션이 전혀 없으면 → 로그인 화면', async () async {
      final fake = FakeAuthService();
      final controller = AuthController(service: fake);

      await controller.bootstrap();

      expect(controller.isAuthenticated, isFalse);
    });

    test('만료 세션을 네트워크 오류로 확인하지 못하면 → 로그인 화면 + 네트워크 안내', async () async {
      final fake = FakeAuthService();
      await fake.signUp(email: 'network@example.com', password: 'password1');
      fake.injectExpiredSession(email: 'network@example.com');
      fake.simulateNetworkError = true;
      final controller = AuthController(service: fake);

      await controller.bootstrap();

      expect(controller.isAuthenticated, isFalse);
      expect(controller.lastError, kAuthNetworkErrorMessage);
    });

    testWidgets('bootstrap이 네트워크 오류로 끝나면 로그인 화면에 안내 SnackBar가 보인다', (tester) async {
      final fake = FakeAuthService();
      await fake.signUp(email: 'network-ui@example.com', password: 'password1');
      fake.injectExpiredSession(email: 'network-ui@example.com');
      fake.simulateNetworkError = true;
      final controller = AuthController(service: fake);
      await controller.bootstrap();
      expect(controller.lastError, kAuthNetworkErrorMessage);

      await tester.pumpWidget(MaterialApp(home: LoginScreen(authController: controller)));
      await tester.pump();
      await tester.pump();

      expect(find.text(kAuthNetworkErrorMessage), findsOneWidget);
    });
  });

  group('SS-수정002 §5·§6 — 로그아웃 + 보호 화면 접근 차단', () {
    test('로그아웃 → 저장된 세션 삭제 + 로그인 화면 + 보호 화면 접근 차단', async () async {
      final fake = FakeAuthService();
      await fake.signUp(email: 'logout@example.com', password: 'password1');
      final controller = AuthController(service: fake);
      await controller.bootstrap();
      expect(controller.isAuthenticated, isTrue);

      await controller.signOut();

      expect(controller.isAuthenticated, isFalse);
      expect(await fake.restoreSession(), isNull);

      final previous = AuthController.instance;
      AuthController.instance = controller;
      addTearDown(() => AuthController.instance = previous);

      final route = SsRouter.onGenerateRoute(RouteSettings(name: SsStage.home.routeName));
      expect(route, isNotNull);
      expect(route!.settings.name, '/login');
    });
  });

  group('SS-수정002 §4·§6 — 실행 중 인증 상태 이벤트', () {
    test('실행 중 signedOut 이벤트가 오면 AuthController 세션이 지워지고, 이후 보호 화면 진입이 막힌다', async () async {
      final client = _testClient((request) async {
        if (request.url.path.endsWith('/logout')) return http.Response('', 204);
        return http.Response(
          jsonEncode(_sessionJson(accessToken: 'at-run', refreshToken: 'rt-run', userId: 'u-run', email: 'run@example.com')),
          200,
        );
      });
      final controller = AuthController(service: SupabaseAuthService(client: client));
      controller.attachAuthStateListener(client.auth);

      await client.auth.signInWithPassword(email: 'run@example.com', password: 'password1');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.isAuthenticated, isTrue);

      final previous = AuthController.instance;
      AuthController.instance = controller;
      addTearDown(() => AuthController.instance = previous);

      await client.auth.signOut();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.isAuthenticated, isFalse);

      final route = SsRouter.onGenerateRoute(RouteSettings(name: SsStage.home.routeName));
      expect(route, isNotNull);
      expect(route!.settings.name, '/login');
    });
  });

  group('SS-수정002 — 비밀번호는 세션에 담기지 않는다', () {
    test('AuthSession.toJson()에는 password 필드도, 입력한 비밀번호 값도 없다', () {
      const password = 'super-secret-password1';
      final session = AuthSession(
        userId: 'u-1',
        email: 'a@b.com',
        accessToken: 'access-token-value',
        refreshToken: 'refresh-token-value',
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      );

      final json = session.toJson();

      expect(json.containsKey('password'), isFalse);
      expect(json.values.any((v) => v == password), isFalse);
    });

    test('FakeAuthService로 로그인한 뒤에도 세션의 어떤 필드도 원래 비밀번호 값을 담지 않는다', async () async {
      const password = 'another-secret-pw1';
      final fake = FakeAuthService();
      await fake.signUp(email: 'nopass@example.com', password: password);
      final session = await fake.restoreSession();

      expect(session, isNotNull);
      final json = session!.toJson();
      expect(json.values.any((v) => v == password), isFalse);
    });
  });
}

/// `async () async { ... }`처럼 바로 async 콜백을 넘길 수 있게 돕는 아주
/// 작은 identity 헬퍼 — `test('...', () async { ... })`와 동일하게 동작
/// 하되, 이 파일의 호출부 표기를 `test('설명', async () async { ... });`
/// 형태로 통일하기 위한 것이다.
Future<void> Function() async(Future<void> Function() body) => body;
