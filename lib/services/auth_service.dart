/// SS002 §2~§6 — Supabase Auth 이메일·비밀번호 인증을 화면과 분리하는 서비스 계층.
///
/// 화면은 [AuthService] 인터페이스만 보고 호출한다. 실제 네트워크 연결은
/// [SupabaseAuthService]가 담당하고, 테스트는 실제 네트워크 없이 [FakeAuthService]를 쓴다.
///
/// 작업지시서 §2·§5·8단계가 이름으로 지정한 `supabase_flutter`(pubspec.yaml)를
/// 실제로 쓴다 — Supabase Auth REST 엔드포인트를 직접 호출하지 않고,
/// `supabase_flutter`가 공개하는 [SupabaseClient]/[GoTrueClient](signUp,
/// signInWithPassword, signOut, currentSession, AuthException)를 그대로
/// 쓴다. service_role/secret key는 앱에 전혀 포함하지 않고,
/// SUPABASE_URL/SUPABASE_ANON_KEY만 `String.fromEnvironment`로 읽는다(§2).
///
/// 세션 저장/복원(자동 로그인, §5)은 `supabase_flutter`의 기본 저장소
/// (`Supabase.initialize()`가 설정하는 로컬 저장소)를 그대로 활용한다 —
/// main.dart가 앱 시작 시 설정값이 있으면 `Supabase.initialize()`를 한 번
/// 호출해 두면, 이후 [SupabaseAuthService]는 `Supabase.instance.client`의
/// `auth.currentSession`만 읽어 자동 로그인을 구현한다. 더 이상 이 서비스가
/// 직접 세션 파일을 쓰고 읽지 않는다.
///
/// 오류 분류 규칙(2026-10-28 추가 지시) — 네트워크 오류로 안내하는 것은
/// 실제 연결 문제뿐이다: [SocketException], `http`의 `ClientException`,
/// [TimeoutException], 그리고 gotrue가 fetch 단계(연결 실패/CORS 등)에서
/// 모든 전송 오류를 감싸 던지는 [supa.AuthRetryableFetchException]. 그 밖의
/// 예외(예: gotrue 응답 파싱 실패로 발생하는 FormatException, 우리 코드의
/// 버그로 인한 StateError/TypeError 등)는 절대 네트워크 오류로 보고하지
/// 않고 [AuthErrorKind.unknown] + 일반 안내로 처리하며, 실제 예외 종류와
/// 메시지는 `debugPrint`로 남긴다(비밀번호·토큰은 남기지 않는다). catch-all
/// 이 모든 실패를 하나의 원인으로 둔갑시키지 않는다 — signUp·signIn·signOut·
/// 세션 복원 모두 같은 규칙을 따른다.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

/// `--dart-define=SUPABASE_ANON_KEY=...`. 공개 가능한 anon key — service_role/
/// secret key가 아니다. 지정하지 않으면 인증 설정이 없는 것으로 취급한다(§2).
const String _supabaseAnonKeyDefine = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: '',
);

/// `--dart-define=SUPABASE_URL=...`. lib/config/app_environment.dart는 이번
/// 작업에서 수정하지 않는 파일이므로, 인증 전용 상수를 이 파일 안에 따로
/// 둔다(같은 빌드 설정 키를 읽으므로 실제 빌드에서는 항상 같은 값이다).
const String _supabaseUrlDefine = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: '',
);

/// 로그인된 사용자의 인증 세션.
@immutable
class AuthSession {
  const AuthSession({
    required this.userId,
    required this.email,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String userId;
  final String email;
  final String accessToken;
  final String refreshToken;

  /// 액세스 토큰 만료 시각(UTC).
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt);

  Map<String, Object?> toJson() => {
    'userId': userId,
    'email': email,
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt.toIso8601String(),
  };

  static AuthSession? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final userId = j['userId'];
    final email = j['email'];
    final access = j['accessToken'];
    final refresh = j['refreshToken'];
    final expires = DateTime.tryParse('${j['expiresAt']}');
    if (userId is! String || email is! String || access is! String || refresh is! String || expires == null) {
      return null;
    }
    return AuthSession(userId: userId, email: email, accessToken: access, refreshToken: refresh, expiresAt: expires);
  }
}

/// [AuthService] 호출 한 건의 결과 상태.
enum AuthStatus {
  /// 로그인/회원가입에 성공해 바로 쓸 수 있는 세션이 생겼다.
  success,

  /// 회원가입은 접수됐지만 이메일 확인이 필요해 세션이 아직 없다(§3).
  needsEmailConfirmation,

  /// 실패 — [AuthResult.message]에 한국어 안내가 담긴다(§6).
  failure,
}

/// 오류 상황을 구분해 재시도/안내 방식을 다르게 하기 위한 분류(§6).
enum AuthErrorKind {
  none,
  invalidEmail,
  invalidCredentials,
  emailNotConfirmed,
  emailAlreadyRegistered,
  weakPassword,
  network,
  rateLimited,
  sessionExpired,
  notConfigured,
  unknown,
}

@immutable
class AuthResult {
  const AuthResult._(this.status, this.session, this.message, this.errorKind);

  const AuthResult.success(AuthSession session) : this._(AuthStatus.success, session, null, AuthErrorKind.none);

  const AuthResult.needsEmailConfirmation(String message) : this._(AuthStatus.needsEmailConfirmation, null, message, AuthErrorKind.none);

  const AuthResult.failure(String message, [AuthErrorKind kind = AuthErrorKind.unknown]) : this._(AuthStatus.failure, null, message, kind);

  final AuthStatus status;
  final AuthSession? session;
  final String? message;
  final AuthErrorKind errorKind;

  bool get isSuccess => status == AuthStatus.success;
}

/// 인증 설정이 없을 때 모든 화면이 공통으로 보여줄 안내(§2).
const String kAuthNotConfiguredMessage = '인증 설정이 없습니다.';

/// 네트워크와 무관한 예상치 못한 오류일 때 보여줄 일반 안내(§6, 2026-10-28 추가 지시).
const String kAuthUnknownErrorMessage = '알 수 없는 오류가 발생했습니다. 잠시 후 다시 시도해주세요.';

/// 화면이 바라보는 인증 인터페이스 — Supabase 구현과 테스트용 Fake가 이를 구현한다.
abstract class AuthService {
  /// SUPABASE_URL/SUPABASE_ANON_KEY가 모두 있어야 true(§2) — 없으면 회원가입/
  /// 로그인을 진행하지 않는다.
  bool get isConfigured;

  Future<AuthResult> signUp({required String email, required String password});
  Future<AuthResult> signIn({required String email, required String password});
  Future<void> signOut();

  /// 앱 시작 시 저장된 세션을 복원한다(§5) — supabase_flutter가 복원해 둔
  /// 세션이 있으면 그대로 돌려주고, 없으면 null(로그인 화면으로).
  Future<AuthSession?> restoreSession();
}

/// SS002 §2~§6 — `supabase_flutter`(package:supabase_flutter)의 [supa.SupabaseClient]
/// 를 그대로 써서 Supabase Auth 이메일·비밀번호 인증을 구현한다.
///
/// 실제 앱에서는 main.dart가 시작할 때 미리 끝낸 `Supabase.initialize()`의
/// 전역 싱글턴([supa.Supabase.instance.client])을 그대로 쓴다 —
/// supabase_flutter의 기본 세션 저장/복원(§5)이 이 전역 클라이언트에서만
/// 동작하기 때문이다. 테스트(§2 "실제 Supabase 연결 없이도 실행 가능")는
/// `client`에 httpClient를 MockClient로 바꾼 순수 [supa.SupabaseClient]를
/// 직접 주입해 `Supabase.instance`를 전혀 거치지 않는다.
class SupabaseAuthService implements AuthService {
  SupabaseAuthService({supa.SupabaseClient? client, String? supabaseUrlOverride, String? anonKeyOverride})
    : _clientOverride = client,
      _urlOverride = supabaseUrlOverride,
      _keyOverride = anonKeyOverride;

  final supa.SupabaseClient? _clientOverride;

  /// `--dart-define` 값은 컴파일 타임에 고정되어 테스트에서 런타임에 바꿀 수
  /// 없으므로(기존 [AppUpdateService]의 `supabaseUrlOverride`와 같은 관례),
  /// 테스트는 이 override로 가짜 Supabase URL/anon key를 주입한다.
  final String? _urlOverride;
  final String? _keyOverride;

  String get _url => (_urlOverride ?? _supabaseUrlDefine).trim();
  String get _key => (_keyOverride ?? _supabaseAnonKeyDefine).trim();

  @override
  bool get isConfigured => _clientOverride != null || (_url.isNotEmpty && _key.isNotEmpty);

  supa.SupabaseClient? _ownClient;

  supa.SupabaseClient get _client {
    if (_clientOverride != null) return _clientOverride;
    try {
      return supa.Supabase.instance.client;
    } catch (_) {
      // main.dart가 Supabase.initialize()를 아직 안 불렀거나(설정이 없는
      // 빌드) 거치지 않는 예외적 호출 경로 — 이번 호출에서만 쓸 임시
      // 클라이언트를 직접 만든다(세션 영속 저장은 없음).
      return _ownClient ??= supa.SupabaseClient(_url, _key);
    }
  }

  @override
  Future<AuthResult> signUp({required String email, required String password}) async {
    if (!isConfigured) return const AuthResult.failure(kAuthNotConfiguredMessage, AuthErrorKind.notConfigured);
    try {
      final res = await _client.auth.signUp(email: email, password: password).timeout(const Duration(seconds: 20));
      final session = _mapSession(res.session, fallbackEmail: email);
      if (session == null) {
        return const AuthResult.needsEmailConfirmation('확인 메일을 보냈습니다. 메일에서 확인 후 로그인해주세요.');
      }
      return AuthResult.success(session);
    } on supa.AuthException catch (e) {
      return _failureFromException(e);
    } on SocketException catch (e) {
      return _networkFailure('signUp', e);
    } on http.ClientException catch (e) {
      return _networkFailure('signUp', e);
    } on TimeoutException catch (e) {
      return _networkFailure('signUp', e);
    } catch (e, st) {
      return _unknownFailure('signUp', e, st);
    }
  }

  @override
  Future<AuthResult> signIn({required String email, required String password}) async {
    if (!isConfigured) return const AuthResult.failure(kAuthNotConfiguredMessage, AuthErrorKind.notConfigured);
    try {
      final res = await _client.auth
          .signInWithPassword(email: email, password: password)
          .timeout(const Duration(seconds: 20));
      final session = _mapSession(res.session, fallbackEmail: email);
      if (session == null) return const AuthResult.failure('로그인에 실패했습니다. 다시 시도해주세요.');
      return AuthResult.success(session);
    } on supa.AuthException catch (e) {
      return _failureFromException(e);
    } on SocketException catch (e) {
      return _networkFailure('signIn', e);
    } on http.ClientException catch (e) {
      return _networkFailure('signIn', e);
    } on TimeoutException catch (e) {
      return _networkFailure('signIn', e);
    } catch (e, st) {
      return _unknownFailure('signIn', e, st);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _client.auth.signOut().timeout(const Duration(seconds: 10));
    } catch (e, st) {
      // 로그아웃 요청이 실패해도 앱 인증 상태(AuthController)는 반드시
      // 초기화된다(§5 — 로그아웃은 사용자를 다시 로그인 화면으로 보내는
      // 것이 최우선). 로컬에 남은 세션 정리는 supabase_flutter가 맡는다.
      // 사용자에게 보여줄 메시지는 없지만(로그아웃은 항상 성공한 것처럼
      // 처리) 원인 파악을 위해 실제 예외는 남긴다(비밀번호·토큰 제외).
      debugPrint('SupabaseAuthService.signOut 실패(무시하고 로컬 상태는 초기화): ${e.runtimeType}: $e\n$st');
    }
  }

  @override
  Future<AuthSession?> restoreSession() async {
    if (!isConfigured) return null;
    try {
      return _mapSession(_client.auth.currentSession);
    } catch (e, st) {
      // 세션 복원 실패는 "세션 없음"과 동일하게 로그인 화면으로 보낸다 —
      // 여기서도 catch-all이 원인을 숨기지 않도록 실제 예외를 남긴다.
      debugPrint('SupabaseAuthService.restoreSession 실패: ${e.runtimeType}: $e\n$st');
      return null;
    }
  }

  /// 실제 연결 문제(§6 "네트워크 연결 오류")로 확인된 예외만 이 메시지를 쓴다.
  AuthResult _networkFailure(String op, Object error) {
    debugPrint('SupabaseAuthService.$op 네트워크 오류: ${error.runtimeType}: $error');
    return const AuthResult.failure('네트워크 연결을 확인해주세요.', AuthErrorKind.network);
  }

  /// 네트워크 원인으로 확인되지 않은 그 밖의 모든 예외 — 절대 네트워크
  /// 오류로 보고하지 않고 일반 오류로 안내하며, 실제 예외 종류/메시지는
  /// debugPrint로 남겨 개발자가 원인을 알 수 있게 한다(비밀번호·토큰은
  /// 담지 않는다 — error.toString()에 포함되지 않음).
  AuthResult _unknownFailure(String op, Object error, StackTrace st) {
    debugPrint('SupabaseAuthService.$op 예상치 못한 오류(네트워크 아님): ${error.runtimeType}: $error\n$st');
    return const AuthResult.failure(kAuthUnknownErrorMessage, AuthErrorKind.unknown);
  }

  AuthSession? _mapSession(supa.Session? session, {String? fallbackEmail}) {
    if (session == null) return null;
    final expiresAtSeconds = session.expiresAt;
    final expiresAt = expiresAtSeconds != null
        ? DateTime.fromMillisecondsSinceEpoch(expiresAtSeconds * 1000, isUtc: true)
        : DateTime.now().toUtc().add(const Duration(hours: 1));
    return AuthSession(
      userId: session.user.id,
      email: session.user.email ?? fallbackEmail ?? '',
      accessToken: session.accessToken,
      refreshToken: session.refreshToken ?? '',
      expiresAt: expiresAt,
    );
  }

  AuthResult _failureFromException(supa.AuthException e) {
    // AuthRetryableFetchException — gotrue가 fetch 단계(연결 실패/CORS 등
    // 전송 오류)에서 원래 예외 종류와 무관하게 공통으로 던지는 "재시도
    // 가능" 예외다(2026-10-28 추가 지시) — 메시지 키워드와 무관하게 항상
    // 네트워크 오류로 안내한다.
    if (e is supa.AuthRetryableFetchException) {
      debugPrint('SupabaseAuthService 네트워크 오류(AuthRetryableFetchException): ${e.message}');
      return const AuthResult.failure('네트워크 연결을 확인해주세요.', AuthErrorKind.network);
    }
    final msg = e.message.toLowerCase();
    final statusCode = int.tryParse(e.statusCode ?? '') ?? 0;
    AuthErrorKind kind;
    String korean;
    if (statusCode == 429 || msg.contains('rate limit') || msg.contains('too many requests')) {
      kind = AuthErrorKind.rateLimited;
      korean = '요청이 너무 많습니다. 잠시 후 다시 시도해주세요.';
    } else if (msg.contains('not confirmed') || msg.contains('confirm')) {
      kind = AuthErrorKind.emailNotConfirmed;
      korean = '이메일 확인이 필요합니다. 메일함을 확인해주세요.';
    } else if (msg.contains('already registered') || msg.contains('already exists')) {
      kind = AuthErrorKind.emailAlreadyRegistered;
      korean = '이미 가입된 이메일입니다.';
    } else if (msg.contains('password') && (msg.contains('short') || msg.contains('weak') || msg.contains('least') || msg.contains('character'))) {
      kind = AuthErrorKind.weakPassword;
      korean = '비밀번호가 보안 정책에 맞지 않습니다(최소 8자 이상).';
    } else if (msg.contains('invalid login') || msg.contains('invalid email or password') || msg.contains('invalid credentials')) {
      kind = AuthErrorKind.invalidCredentials;
      korean = '이메일 또는 비밀번호가 올바르지 않습니다.';
    } else if (msg.contains('invalid') && msg.contains('email')) {
      kind = AuthErrorKind.invalidEmail;
      korean = '올바른 이메일 형식이 아닙니다.';
    } else {
      kind = AuthErrorKind.unknown;
      korean = '요청을 처리하지 못했습니다. 잠시 후 다시 시도해주세요.';
      debugPrint('SupabaseAuthService 분류되지 않은 AuthException: statusCode=${e.statusCode} message=${e.message}');
    }
    return AuthResult.failure(korean, kind);
  }
}

/// 테스트용 Fake — 실제 네트워크 없이 메모리에서 이메일·비밀번호를 흉내낸다.
///
/// 비밀번호 정책(최소 8자, §3), 이메일 형식 검증, 중복 가입, 이메일 확인
/// 필요 여부, 네트워크 오류 시뮬레이션 등을 생성자 플래그로 조절할 수 있다.
class FakeAuthService implements AuthService {
  FakeAuthService({this.configured = true, this.requireEmailConfirmation = false, this.simulateNetworkError = false, this.signInDelay = Duration.zero});

  final bool configured;
  final bool requireEmailConfirmation;
  bool simulateNetworkError;
  final Duration signInDelay;

  final Map<String, String> _users = {};
  final Map<String, bool> _confirmed = {};
  AuthSession? _session;
  int _idSeq = 0;

  @override
  bool get isConfigured => configured;

  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  Future<AuthResult> signUp({required String email, required String password}) async {
    if (!isConfigured) return const AuthResult.failure(kAuthNotConfiguredMessage, AuthErrorKind.notConfigured);
    if (signInDelay > Duration.zero) await Future<void>.delayed(signInDelay);
    if (simulateNetworkError) return const AuthResult.failure('네트워크 연결을 확인해주세요.', AuthErrorKind.network);
    if (!_emailPattern.hasMatch(email)) {
      return const AuthResult.failure('올바른 이메일 형식이 아닙니다.', AuthErrorKind.invalidEmail);
    }
    if (password.length < 8) {
      return const AuthResult.failure('비밀번호가 보안 정책에 맞지 않습니다(최소 8자 이상).', AuthErrorKind.weakPassword);
    }
    if (_users.containsKey(email)) {
      return const AuthResult.failure('이미 가입된 이메일입니다.', AuthErrorKind.emailAlreadyRegistered);
    }
    _users[email] = password;
    _idSeq++;
    if (requireEmailConfirmation) {
      _confirmed[email] = false;
      return const AuthResult.needsEmailConfirmation('확인 메일을 보냈습니다. 메일에서 확인 후 로그인해주세요.');
    }
    _confirmed[email] = true;
    final session = _newSession(email);
    _session = session;
    return AuthResult.success(session);
  }

  @override
  Future<AuthResult> signIn({required String email, required String password}) async {
    if (!isConfigured) return const AuthResult.failure(kAuthNotConfiguredMessage, AuthErrorKind.notConfigured);
    if (signInDelay > Duration.zero) await Future<void>.delayed(signInDelay);
    if (simulateNetworkError) return const AuthResult.failure('네트워크 연결을 확인해주세요.', AuthErrorKind.network);
    final stored = _users[email];
    if (stored == null || stored != password) {
      return const AuthResult.failure('이메일 또는 비밀번호가 올바르지 않습니다.', AuthErrorKind.invalidCredentials);
    }
    if (_confirmed[email] == false) {
      return const AuthResult.failure('이메일 확인이 필요합니다. 메일함을 확인해주세요.', AuthErrorKind.emailNotConfirmed);
    }
    final session = _newSession(email);
    _session = session;
    return AuthResult.success(session);
  }

  @override
  Future<void> signOut() async {
    _session = null;
  }

  @override
  Future<AuthSession?> restoreSession() async => _session;

  AuthSession _newSession(String email) => AuthSession(
    userId: 'fake-user-$_idSeq',
    email: email,
    accessToken: 'fake-access-$_idSeq',
    refreshToken: 'fake-refresh-$_idSeq',
    expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
  );

  /// 테스트 편의 — 이메일 확인을 완료 처리한다(§3 "이메일 확인 후 정상 로그인").
  void confirmEmail(String email) => _confirmed[email] = true;
}

/// 화면/라우터가 공유하는 인증 상태 — 로그인/회원가입/로그아웃 호출과 앱
/// 시작 시 세션 복원을 한 곳에서 관리한다(§5).
///
/// 기본 인스턴스([instance])는 실제 Supabase 구현을 쓰고, 테스트는
/// `AuthController(service: FakeAuthService())`처럼 직접 만들어 화면에 주입한다.
class AuthController extends ChangeNotifier {
  AuthController({AuthService? service}) : service = service ?? SupabaseAuthService();

  /// 앱 전체가 공유하는 싱글턴 — main.dart가 시작할 때 [bootstrap]을 부른다.
  static AuthController instance = AuthController();

  final AuthService service;

  bool _initialized = false;
  bool get initialized => _initialized;

  AuthSession? _session;
  AuthSession? get session => _session;
  bool get isAuthenticated => _session != null;

  bool _busy = false;
  bool get busy => _busy;

  String? _lastError;
  String? get lastError => _lastError;

  /// 인증 설정 자체가 없는가(§2) — 있으면 로그인/회원가입 화면은 항상 이
  /// 안내만 보여주고 더 진행하지 않는다.
  bool get isConfigured => service.isConfigured;

  /// 앱 시작 시 한 번 — 저장된 세션을 복원한다(§5 자동 로그인). 여러 번
  /// 불려도 한 번만 동작한다.
  Future<void> bootstrap() async {
    if (_initialized) return;
    if (service.isConfigured) {
      _session = await service.restoreSession();
    }
    _initialized = true;
    notifyListeners();
  }

  Future<AuthResult> signIn({required String email, required String password}) async {
    if (_busy) return const AuthResult.failure('처리 중입니다. 잠시만 기다려주세요.');
    _busy = true;
    _lastError = null;
    notifyListeners();
    final result = await service.signIn(email: email, password: password);
    if (result.isSuccess) {
      _session = result.session;
      _initialized = true;
    } else {
      _lastError = result.message;
    }
    _busy = false;
    notifyListeners();
    return result;
  }

  Future<AuthResult> signUp({required String email, required String password}) async {
    if (_busy) return const AuthResult.failure('처리 중입니다. 잠시만 기다려주세요.');
    _busy = true;
    _lastError = null;
    notifyListeners();
    final result = await service.signUp(email: email, password: password);
    if (result.isSuccess) {
      _session = result.session;
      _initialized = true;
    } else if (result.status == AuthStatus.failure) {
      _lastError = result.message;
    }
    _busy = false;
    notifyListeners();
    return result;
  }

  /// SS002 §5 — 로그아웃: Supabase 세션 종료 + 앱 인증 상태 초기화. 호출 뒤
  /// [isAuthenticated]는 항상 false이므로, 보호된 화면은 다시 열 수 없다.
  Future<void> signOut() async {
    _busy = true;
    notifyListeners();
    await service.signOut();
    _session = null;
    _busy = false;
    notifyListeners();
  }
}
