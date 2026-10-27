// SS002 §2~§6 — AuthService 구현체 검증. FakeAuthService는 화면 테스트가
// 실제 네트워크 없이 쓰는 용도이고, SupabaseAuthService는 supabase_flutter의
// SupabaseClient에 http MockClient를 주입해(Supabase.instance 전역 싱글턴은
// 거치지 않음) 회원가입/로그인/오류 안내/로그아웃을 검증한다. 세션 저장/복원
// 자체(자동 로그인 §5)는 supabase_flutter의 기본 로컬 저장소에 위임하므로,
// 이 서비스 계층이 직접 파일을 쓰고 읽는지는 더 이상 검증하지 않는다 — 대신
// 로그인 직후 같은 클라이언트에서 restoreSession()이 그 세션을 그대로
// 돌려주는지(§5 "유효 세션이면 자동 로그인")를 검증한다.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

import 'package:ason_space/services/auth_service.dart';

/// 실제 Supabase Auth REST 응답과 같은 형태의 완전한 user JSON — gotrue의
/// User 모델 파싱이 기대하는 필드를 모두 채워 MockClient 응답이 실제
/// Supabase 서버 응답과 동일하게 파싱되게 한다.
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

/// 테스트 전용 — Supabase.instance 싱글턴을 전혀 거치지 않는 순수
/// [supa.SupabaseClient]를 만든다(httpClient만 MockClient로 교체).
supa.SupabaseClient _testClient(Future<http.Response> Function(http.Request) handler) {
  return supa.SupabaseClient(
    'https://example.supabase.co',
    'anon-key',
    httpClient: MockClient(handler),
    // gotrue의 signUp()은 기본(PKCE) 플로우에서 asyncStorage가 있어야
    // code_challenge를 만들 수 있다고 assert한다. 이 테스트 클라이언트는
    // 로컬 저장소를 쓰지 않으므로, PKCE가 필요 없는 implicit 플로우로
    // 바꿔 그 assert를 피한다(실제 앱은 main.dart의 전역 클라이언트를
    // 쓰므로 영향 없음).
    authOptions: const supa.AuthClientOptions(authFlowType: supa.AuthFlowType.implicit),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FakeAuthService — 실제 네트워크 없이 이메일·비밀번호 인증을 흉내낸다', () {
    test('이메일 형식이 아니면 회원가입이 실패한다', () async {}, skip: true);

    test('이메일 형식이 아니면 회원가입이 실패한다 ', () async {
      final fake = FakeAuthService();
      final result = await fake.signUp(email: 'not-an-email', password: 'password1');
      expect(result.status, AuthStatus.failure);
      expect(result.errorKind, AuthErrorKind.invalidEmail);
    });

    test('비밀번호가 8자 미만이면 회원가입이 실패한다(§3 최소 8자)', () async {
      final fake = FakeAuthService();
      final result = await fake.signUp(email: 'a@b.com', password: 'short1');
      expect(result.status, AuthStatus.failure);
      expect(result.errorKind, AuthErrorKind.weakPassword);
    });

    test('같은 이메일로 두 번 가입하면 두 번째는 실패한다', () async {
      final fake = FakeAuthService();
      final first = await fake.signUp(email: 'dup@example.com', password: 'password1');
      expect(first.isSuccess, isTrue);
      final second = await fake.signUp(email: 'dup@example.com', password: 'password1');
      expect(second.status, AuthStatus.failure);
      expect(second.errorKind, AuthErrorKind.emailAlreadyRegistered);
    });

    test('이메일 확인이 필요하면 가입 직후 세션 없이 안내만 돌아오고, 로그인도 막힌다', () async {
      final fake = FakeAuthService(requireEmailConfirmation: true);
      final signUpResult = await fake.signUp(email: 'confirm@example.com', password: 'password1');
      expect(signUpResult.status, AuthStatus.needsEmailConfirmation);

      final loginBefore = await fake.signIn(email: 'confirm@example.com', password: 'password1');
      expect(loginBefore.status, AuthStatus.failure);
      expect(loginBefore.errorKind, AuthErrorKind.emailNotConfirmed);

      fake.confirmEmail('confirm@example.com');
      final loginAfter = await fake.signIn(email: 'confirm@example.com', password: 'password1');
      expect(loginAfter.isSuccess, isTrue);
    });

    test('설정이 없으면(§2) 회원가입/로그인 모두 안내만 하고 진행하지 않는다', () async {
      final fake = FakeAuthService(configured: false);
      final signUpResult = await fake.signUp(email: 'a@b.com', password: 'password1');
      final signInResult = await fake.signIn(email: 'a@b.com', password: 'password1');
      expect(signUpResult.message, kAuthNotConfiguredMessage);
      expect(signInResult.message, kAuthNotConfiguredMessage);
    });

    test('로그아웃 후에는 restoreSession이 세션을 돌려주지 않는다', () async {
      final fake = FakeAuthService();
      await fake.signUp(email: 'logout@example.com', password: 'password1');
      expect(await fake.restoreSession(), isNotNull);
      await fake.signOut();
      expect(await fake.restoreSession(), isNull);
    });
  });

  group('SupabaseAuthService — supabase_flutter SupabaseClient(MockClient 주입)', () {
    test('설정값이 없으면 isConfigured가 false다', () {
      final service = SupabaseAuthService(supabaseUrlOverride: '', anonKeyOverride: '');
      expect(service.isConfigured, isFalse);
    });

    test('URL/anon key가 모두 있으면 isConfigured가 true다', () {
      final service = SupabaseAuthService(
        supabaseUrlOverride: 'https://example.supabase.co',
        anonKeyOverride: 'anon-key',
      );
      expect(service.isConfigured, isTrue);
    });

    test('설정이 없으면 네트워크를 호출하지 않고 인증 설정 안내를 반환한다', () async {
      final service = SupabaseAuthService(supabaseUrlOverride: '', anonKeyOverride: '');
      final result = await service.signIn(email: 'a@b.com', password: 'password1');
      expect(result.message, kAuthNotConfiguredMessage);
      expect(result.errorKind, AuthErrorKind.notConfigured);
    });

    test('회원가입 성공 시 세션이 생기고, 같은 클라이언트에서 restoreSession으로 자동 로그인을 확인할 수 있다(§5)', () async {
      final client = _testClient((request) async {
        return http.Response(
          jsonEncode(_sessionJson(accessToken: 'at-1', refreshToken: 'rt-1', userId: 'u-1', email: 'new@example.com')),
          200,
        );
      });
      final service = SupabaseAuthService(client: client);

      final result = await service.signUp(email: 'new@example.com', password: 'password1');

      expect(result.isSuccess, isTrue);
      expect(result.session?.accessToken, 'at-1');

      final restored = await service.restoreSession();
      expect(restored?.accessToken, 'at-1');
      expect(restored?.email, 'new@example.com');
    });

    test('이메일 확인이 필요한 응답(세션 없음)은 needsEmailConfirmation으로 처리한다', () async {
      final client = _testClient((request) async {
        return http.Response(jsonEncode(_userJson(id: 'u-2', email: 'pending@example.com')), 200);
      });
      final service = SupabaseAuthService(client: client);

      final result = await service.signUp(email: 'pending@example.com', password: 'password1');

      expect(result.status, AuthStatus.needsEmailConfirmation);
    });

    test('로그인 실패(잘못된 자격 증명)는 한국어 안내로 변환된다', () async {
      final client = _testClient((request) async {
        return http.Response(
          jsonEncode({'error_code': 'invalid_credentials', 'msg': 'Invalid login credentials'}),
          400,
        );
      });
      final service = SupabaseAuthService(client: client);

      final result = await service.signIn(email: 'a@b.com', password: 'wrong');

      expect(result.status, AuthStatus.failure);
      expect(result.errorKind, AuthErrorKind.invalidCredentials);
      expect(result.message, '이메일 또는 비밀번호가 올바르지 않습니다.');
    });

    test('요청 제한(429) 응답은 한국어 재시도 안내로 변환된다', () async {
      final client = _testClient((request) async {
        return http.Response(jsonEncode({'error_code': 'over_request_rate_limit', 'msg': 'rate limit exceeded'}), 429);
      });
      final service = SupabaseAuthService(client: client);

      final result = await service.signIn(email: 'a@b.com', password: 'password1');

      expect(result.errorKind, AuthErrorKind.rateLimited);
    });

    test('이미 가입된 이메일로 회원가입하면 한국어 안내로 변환된다', () async {
      final client = _testClient((request) async {
        return http.Response(
          jsonEncode({'error_code': 'user_already_exists', 'msg': 'User already registered'}),
          400,
        );
      });
      final service = SupabaseAuthService(client: client);

      final result = await service.signUp(email: 'dup@example.com', password: 'password1');

      expect(result.errorKind, AuthErrorKind.emailAlreadyRegistered);
      expect(result.message, '이미 가입된 이메일입니다.');
    });

    test('로그인 성공 후 로그아웃하면 같은 클라이언트의 currentSession이 사라진다', () async {
      final client = _testClient((request) async {
        if (request.url.path.endsWith('/auth/v1/logout')) {
          return http.Response('', 204);
        }
        return http.Response(
          jsonEncode(_sessionJson(accessToken: 'at-logout', refreshToken: 'rt-logout', userId: 'u-4', email: 'logout@example.com')),
          200,
        );
      });
      final service = SupabaseAuthService(client: client);
      await service.signUp(email: 'logout@example.com', password: 'password1');
      expect(await service.restoreSession(), isNotNull);

      await service.signOut();

      expect(await service.restoreSession(), isNull);
    });

    test('세션이 없으면 restoreSession은 null이다', () async {
      final client = _testClient((request) async {
        return http.Response('', 404);
      });
      final service = SupabaseAuthService(client: client);

      expect(await service.restoreSession(), isNull);
    });
  });

  group('AuthController — 화면/라우터가 공유하는 인증 상태', () {
    test('bootstrap은 저장된 세션이 있으면 인증 상태로 복원한다(자동 로그인)', () async {
      final fake = FakeAuthService();
      await fake.signUp(email: 'auto@example.com', password: 'password1');
      final controller = AuthController(service: fake);

      expect(controller.initialized, isFalse);
      await controller.bootstrap();

      expect(controller.initialized, isTrue);
      expect(controller.isAuthenticated, isTrue);
      expect(controller.session?.email, 'auto@example.com');
    });

    test('signIn 성공 시 isAuthenticated가 true가 되고, 실패 시 lastError가 채워진다', () async {
      final fake = FakeAuthService();
      await fake.signUp(email: 'user@example.com', password: 'password1');
      final controller = AuthController(service: fake);

      final badResult = await controller.signIn(email: 'user@example.com', password: 'wrong');
      expect(badResult.isSuccess, isFalse);
      expect(controller.isAuthenticated, isFalse);
      expect(controller.lastError, isNotNull);

      final okResult = await controller.signIn(email: 'user@example.com', password: 'password1');
      expect(okResult.isSuccess, isTrue);
      expect(controller.isAuthenticated, isTrue);
    });

    test('처리 중에 다시 호출하면 중복 요청을 막는다', () async {
      final fake = FakeAuthService(signInDelay: const Duration(milliseconds: 30));
      await fake.signUp(email: 'dup@example.com', password: 'password1');
      final controller = AuthController(service: fake);

      final first = controller.signIn(email: 'dup@example.com', password: 'password1');
      final second = await controller.signIn(email: 'dup@example.com', password: 'password1');
      expect(second.status, AuthStatus.failure);

      final firstResult = await first;
      expect(firstResult.isSuccess, isTrue);
      expect(controller.isAuthenticated, isTrue);
    });

    test('signOut 호출 후 isAuthenticated는 false가 된다(로그아웃)', () async {
      final fake = FakeAuthService();
      await fake.signUp(email: 'logout2@example.com', password: 'password1');
      final controller = AuthController(service: fake);
      await controller.signIn(email: 'logout2@example.com', password: 'password1');
      expect(controller.isAuthenticated, isTrue);

      await controller.signOut();

      expect(controller.isAuthenticated, isFalse);
    });
  });
}
