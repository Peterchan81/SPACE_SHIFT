// SS-수정002 §3~§8 — 자동 로그인: 유효 세션은 바로 홈, 만료 세션은 갱신을
// 시도해 성공하면 홈·실패하면 로그인(+저장된 세션 삭제), 세션이 없으면
// 로그인, 로그아웃은 저장된 세션 삭제 + 보호 화면 접근 차단, 실행 중
// signedOut/tokenRefreshed 이벤트가 오면 각각 로그인 화면·세션 교체로
// 반영한다. 실제 네트워크 없이 기존 FakeAuthService/MockClient 방식 그대로
// 검증한다.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

import 'package:ason_space/core/ss_router.dart';
import 'package:ason_space/core/ss_stage.dart';
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

  group('자동 로그인 — AuthController.bootstrap()', () {
    test('유효한 세션이 있으면 바로 홈(인증됨)으로 시작한다', () async {
      final fake = FakeAuthService();
      await fake.signUp(email: 'valid@example.com', password: 'password1');
      final controller = AuthController(service: fake);

      await controller.bootstrap();

      expect(controller.isAuthenticated, isTrue);
      expect(controller.session?.email, 'valid@example.com');
    });

    test('만료된 세션 + 갱신 성공 → 바로 홈(자동 로그인)', () async {
      final fake = FakeAuthService();
      await fake.signUp(email: 'expired-ok@example.com', password: 'password1');
      fake.sessionExpired = true;
      final controller = AuthController(service: fake);

      await controller.bootstrap();

      expect(controller.isAuthenticated, isTrue);
      expect(controller.session?.email, 'expired-ok@example.com');
    });

    test('만료된 세션 + 갱신 실패(무효한 refresh token) → 로그인 화면(비인증) + 저장된 세션 삭제', () async {
      final fake = FakeAuthService();
      await fake.signUp(email: 'expired-fail@example.com', password: 'password1');
      fake.sessionExpired = true;
      fake.refreshSucceeds = false;
      final controller = AuthController(service: fake);

      await controller.bootstrap();

      expect(controller.isAuthenticated, isFalse);
      expect(await fake.restoreSession(), isNull, reason: '저장된 세션이 지워졌다');
    });

    test('만료된 세션 + 네트워크 오류로 갱신을 확인하지 못함 → 로그인 화면 + 안내', () async {
      final fake = FakeAuthService();
      await fake.signUp(email: 'expired-net@example.com', password: 'password1');
      fake.sessionExpired = true;
      fake.refreshNetworkError = true;
      final controller = AuthController(service: fake);

      await controller.bootstrap();

      expect(controller.isAuthenticated, isFalse);
      expect(controller.consumeBootstrapMessage(), '네트워크 연결을 확인해주세요.');
    });

    test('저장된 세션이 없으면 로그인 화면(비인증)으로 시작한다', () async {
      final controller = AuthController(service: FakeAuthService());

      await controller.bootstrap();

      expect(controller.isAuthenticated, isFalse);
      expect(controller.consumeBootstrapMessage(), isNull);
    });
  });

  group('로그아웃 — 저장된 세션 삭제 + 보호 화면 접근 차단', () {
    test('로그아웃하면 세션이 지워지고, 보호된 화면(홈) Route는 로그인으로 돌려보낸다', () async {
      final fake = FakeAuthService();
      await fake.signUp(email: 'logout-route@example.com', password: 'password1');
      final original = AuthController.instance;
      addTearDown(() => AuthController.instance = original);
      final controller = AuthController(service: fake);
      AuthController.instance = controller;

      await controller.bootstrap();
      expect(controller.isAuthenticated, isTrue);

      await controller.signOut();

      expect(controller.isAuthenticated, isFalse);
      expect(await fake.restoreSession(), isNull);

      final route = SsRouter.onGenerateRoute(RouteSettings(name: SsStage.home.routeName));
      expect(route?.settings.name, SsStage.login.routeName);
    });
  });

  group('실행 중 세션 변화 — AuthController.attachAuthStateListener', () {
    test('signedOut 이벤트가 오면 세션이 지워지고 강제 로그아웃 콜백이 불린다(보호 화면에 머물지 않음)', () async {
      final client = _testClient((request) async {
        if (request.url.path.endsWith('/logout')) {
          return http.Response('', 204);
        }
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

      var forcedCalled = false;
      controller.onForcedSignOut = () => forcedCalled = true;

      await client.auth.signOut();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.isAuthenticated, isFalse);
      expect(forcedCalled, isTrue);
    });

    test('tokenRefreshed 이벤트가 오면 세션이 새 값으로 바뀐다', () async {
      var call = 0;
      final client = _testClient((request) async {
        call++;
        return http.Response(
          jsonEncode(_sessionJson(accessToken: 'at-$call', refreshToken: 'rt-$call', userId: 'u-refresh', email: 'refresh@example.com')),
          200,
        );
      });
      final controller = AuthController(service: SupabaseAuthService(client: client));
      controller.attachAuthStateListener(client.auth);

      await client.auth.signInWithPassword(email: 'refresh@example.com', password: 'password1');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.session?.accessToken, 'at-1');

      await client.auth.refreshSession();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.session?.accessToken, 'at-2');
      expect(controller.isAuthenticated, isTrue);
    });
  });

  test('AuthSession.toJson에는 비밀번호 필드가 없다 — 세션에는 비밀번호를 담지 않는다', () {
    final session = AuthSession(
      userId: 'u1',
      email: 'a@b.com',
      accessToken: 'tok',
      refreshToken: 'ref',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    final json = session.toJson();
    expect(json.containsKey('password'), isFalse);
    expect(json.values, isNot(contains('password1')));
  });
}
