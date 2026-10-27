// SS002 §2~§6 — AuthService 구현체 검증. FakeAuthService는 화면 테스트가
// 실제 네트워크 없이 쓰는 용도이고, SupabaseAuthService는 http MockClient로
// Supabase Auth REST API 호출/응답 파싱/오류 안내/세션 저장-복원을 검증한다.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ason_space/services/auth_service.dart';

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

  group('SupabaseAuthService — Supabase Auth REST API 호출(MockClient)', () {
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

    test('회원가입 성공 시 /auth/v1/signup으로 요청하고 세션을 저장한다', () async {
      final dir = Directory.systemTemp.createTempSync('ss002_auth_signup');
      addTearDown(() => dir.deleteSync(recursive: true));
      Uri? requestedUri;
      final client = MockClient((request) async {
        requestedUri = request.url;
        return http.Response(
          jsonEncode({
            'access_token': 'at-1',
            'refresh_token': 'rt-1',
            'expires_in': 3600,
            'user': {'id': 'u-1', 'email': 'new@example.com'},
          }),
          200,
        );
      });
      final service = SupabaseAuthService(
        client: client,
        sessionDir: dir,
        supabaseUrlOverride: 'https://example.supabase.co',
        anonKeyOverride: 'anon-key',
      );

      final result = await service.signUp(email: 'new@example.com', password: 'password1');

      expect(result.isSuccess, isTrue);
      expect(result.session?.accessToken, 'at-1');
      expect(requestedUri?.toString(), 'https://example.supabase.co/auth/v1/signup');

      final restored = await SupabaseAuthService(
        client: client,
        sessionDir: dir,
        supabaseUrlOverride: 'https://example.supabase.co',
        anonKeyOverride: 'anon-key',
      ).restoreSession();
      expect(restored?.accessToken, 'at-1');
    });

    test('이메일 확인이 필요한 응답(세션 없음)은 needsEmailConfirmation으로 처리한다', () async {
      final dir = Directory.systemTemp.createTempSync('ss002_auth_needs_confirm');
      addTearDown(() => dir.deleteSync(recursive: true));
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'id': 'u-2', 'email': 'pending@example.com'}),
          200,
        );
      });
      final service = SupabaseAuthService(
        client: client,
        sessionDir: dir,
        supabaseUrlOverride: 'https://example.supabase.co',
        anonKeyOverride: 'anon-key',
      );

      final result = await service.signUp(email: 'pending@example.com', password: 'password1');

      expect(result.status, AuthStatus.needsEmailConfirmation);
    });

    test('로그인 실패(잘못된 자격 증명)는 한국어 안내로 변환된다', () async {
      final dir = Directory.systemTemp.createTempSync('ss002_auth_invalid');
      addTearDown(() => dir.deleteSync(recursive: true));
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'error_code': 'invalid_credentials', 'msg': 'Invalid login credentials'}),
          400,
        );
      });
      final service = SupabaseAuthService(
        client: client,
        sessionDir: dir,
        supabaseUrlOverride: 'https://example.supabase.co',
        anonKeyOverride: 'anon-key',
      );

      final result = await service.signIn(email: 'a@b.com', password: 'wrong');

      expect(result.status, AuthStatus.failure);
      expect(result.errorKind, AuthErrorKind.invalidCredentials);
      expect(result.message, '이메일 또는 비밀번호가 올바르지 않습니다.');
    });

    test('요청 제한(429) 응답은 한국어 재시도 안내로 변환된다', () async {
      final dir = Directory.systemTemp.createTempSync('ss002_auth_rate');
      addTearDown(() => dir.deleteSync(recursive: true));
      final client = MockClient((request) async {
        return http.Response(jsonEncode({'msg': 'rate limit exceeded'}), 429);
      });
      final service = SupabaseAuthService(
        client: client,
        sessionDir: dir,
        supabaseUrlOverride: 'https://example.supabase.co',
        anonKeyOverride: 'anon-key',
      );

      final result = await service.signIn(email: 'a@b.com', password: 'password1');

      expect(result.errorKind, AuthErrorKind.rateLimited);
    });

    test('저장된 세션이 만료되면 refresh_token으로 갱신한다', () async {
      final dir = Directory.systemTemp.createTempSync('ss002_auth_refresh');
      addTearDown(() => dir.deleteSync(recursive: true));
      final sessionFile = File('${dir.path}${Platform.pathSeparator}space_shift_auth_session.json');
      await sessionFile.writeAsString(jsonEncode({
        'userId': 'u-3',
        'email': 'old@example.com',
        'accessToken': 'expired-token',
        'refreshToken': 'refresh-3',
        'expiresAt': DateTime.now().toUtc().subtract(const Duration(hours: 1)).toIso8601String(),
      }));

      String? grantType;
      final client = MockClient((request) async {
        grantType = request.url.queryParameters['grant_type'];
        return http.Response(
          jsonEncode({
            'access_token': 'at-new',
            'refresh_token': 'rt-new',
            'expires_in': 3600,
            'user': {'id': 'u-3', 'email': 'old@example.com'},
          }),
          200,
        );
      });
      final service = SupabaseAuthService(
        client: client,
        sessionDir: dir,
        supabaseUrlOverride: 'https://example.supabase.co',
        anonKeyOverride: 'anon-key',
      );

      final restored = await service.restoreSession();

      expect(grantType, 'refresh_token');
      expect(restored?.accessToken, 'at-new');
    });

    test('세션이 저장되어 있지 않으면 restoreSession은 null이다', () async {
      final dir = Directory.systemTemp.createTempSync('ss002_auth_empty');
      addTearDown(() => dir.deleteSync(recursive: true));
      final service = SupabaseAuthService(
        sessionDir: dir,
        supabaseUrlOverride: 'https://example.supabase.co',
        anonKeyOverride: 'anon-key',
      );

      expect(await service.restoreSession(), isNull);
    });

    test('로그아웃하면 로컬 세션 파일이 삭제되고 이후 restoreSession은 null이다', () async {
      final dir = Directory.systemTemp.createTempSync('ss002_auth_logout');
      addTearDown(() => dir.deleteSync(recursive: true));
      String? authHeader;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/auth/v1/signup')) {
          return http.Response(
            jsonEncode({
              'access_token': 'at-logout',
              'refresh_token': 'rt-logout',
              'expires_in': 3600,
              'user': {'id': 'u-4', 'email': 'logout@example.com'},
            }),
            200,
          );
        }
        authHeader = request.headers['Authorization'];
        return http.Response('', 204);
      });
      final service = SupabaseAuthService(
        client: client,
        sessionDir: dir,
        supabaseUrlOverride: 'https://example.supabase.co',
        anonKeyOverride: 'anon-key',
      );
      await service.signUp(email: 'logout@example.com', password: 'password1');

      await service.signOut();

      expect(authHeader, 'Bearer at-logout');
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
