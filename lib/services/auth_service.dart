/// SS002 §2~§6 — Supabase Auth 이메일·비밀번호 인증을 화면과 분리하는 서비스 계층.
///
/// 화면은 [AuthService] 인터페이스만 보고 호출한다. 실제 네트워크 연결은
/// [SupabaseAuthService](Supabase Auth REST API, http 패키지로 직접 호출)가
/// 담당하고, 테스트는 실제 네트워크 없이 [FakeAuthService]를 쓴다.
///
/// 이 저장소의 pubspec.yaml 의존성은 바꾸지 않는다 — `supabase_flutter`를
/// 새로 추가하는 대신, Supabase Auth가 공개하는 REST 엔드포인트
/// (`/auth/v1/signup`, `/auth/v1/token`, `/auth/v1/logout`)를 이미 의존성에
/// 있는 [http] 패키지로 직접 호출해 같은 이메일·비밀번호 인증(B안)을
/// 구현한다. service_role/secret key는 앱에 전혀 포함하지 않고,
/// SUPABASE_URL/SUPABASE_ANON_KEY만 `String.fromEnvironment`로 읽는다(§2).
///
/// 세션 저장/복원(자동 로그인, §5)은 `supabase_flutter`의 기본 저장소 대신
/// 기존 [FileSsProjectStore](lib/core/ss_project_store.dart)와 같은 "임시
/// 파일에 쓰고 바꿔 넣기" 방식을 그대로 재사용해, 앱이 중간에 꺼져도 세션
/// 파일이 깨지지 않게 한다.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

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

/// 화면이 바라보는 인증 인터페이스 — Supabase 구현과 테스트용 Fake가 이를 구현한다.
abstract class AuthService {
  /// SUPABASE_URL/SUPABASE_ANON_KEY가 모두 있어야 true(§2) — 없으면 회원가입/
  /// 로그인을 진행하지 않는다.
  bool get isConfigured;

  Future<AuthResult> signUp({required String email, required String password});
  Future<AuthResult> signIn({required String email, required String password});
  Future<void> signOut();

  /// 앱 시작 시 저장된 세션을 복원한다(§5) — 만료됐으면 refresh token으로
  /// 갱신을 시도하고, 그래도 안 되면 null(로그인 화면으로).
  Future<AuthSession?> restoreSession();
}

/// SS002 §2~§6 — Supabase Auth REST API(이메일·비밀번호)를 직접 호출하는 구현.
///
/// 세션은 앱 문서 폴더의 `space_shift_auth_session.json`에 저장해, 기존
/// [FileSsProjectStore](lib/core/ss_project_store.dart)와 같은 "임시 파일에
/// 쓰고 바꿔 넣기" 방식으로 앱이 중간에 꺼져도 깨지지 않게 한다(§5 자동 로그인).
class SupabaseAuthService implements AuthService {
  SupabaseAuthService({http.Client? client, Directory? sessionDir, String? supabaseUrlOverride, String? anonKeyOverride})
    : _client = client ?? http.Client(),
      _sessionDirOverride = sessionDir,
      _urlOverride = supabaseUrlOverride,
      _keyOverride = anonKeyOverride;

  final http.Client _client;
  final Directory? _sessionDirOverride;

  /// `--dart-define` 값은 컴파일 타임에 고정되어 테스트에서 런타임에 바꿀 수
  /// 없으므로(기존 [AppUpdateService]의 `supabaseUrlOverride`와 같은 관례),
  /// 테스트는 이 override로 가짜 Supabase URL/anon key를 주입한다.
  final String? _urlOverride;
  final String? _keyOverride;

  String get _url => (_urlOverride ?? _supabaseUrlDefine).trim();
  String get _key => (_keyOverride ?? _supabaseAnonKeyDefine).trim();

  @override
  bool get isConfigured => _url.isNotEmpty && _key.isNotEmpty;

  Uri _authUri(String path, [Map<String, String>? query]) => Uri.parse('$_url/auth/v1/$path').replace(queryParameters: query);

  Map<String, String> get _headers => {'Content-Type': 'application/json', 'apikey': _key};

  @override
  Future<AuthResult> signUp({required String email, required String password}) async {
    if (!isConfigured) return const AuthResult.failure(kAuthNotConfiguredMessage, AuthErrorKind.notConfigured);
    try {
      final res = await _client
          .post(_authUri('signup'), headers: _headers, body: jsonEncode({'email': email, 'password': password}))
          .timeout(const Duration(seconds: 20));
      final body = _tryDecode(res.body);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final session = _sessionFromTokenResponse(body, fallbackEmail: email);
        if (session == null) {
          return const AuthResult.needsEmailConfirmation('확인 메일을 보냈습니다. 메일에서 확인 후 로그인해주세요.');
        }
        await _saveSession(session);
        return AuthResult.success(session);
      }
      return _failureFrom(res.statusCode, body);
    } on TimeoutException {
      return const AuthResult.failure('네트워크 연결을 확인해주세요.', AuthErrorKind.network);
    } on http.ClientException {
      return const AuthResult.failure('네트워크 연결을 확인해주세요.', AuthErrorKind.network);
    } catch (_) {
      return const AuthResult.failure('네트워크 연결을 확인해주세요.', AuthErrorKind.network);
    }
  }

  @override
  Future<AuthResult> signIn({required String email, required String password}) async {
    if (!isConfigured) return const AuthResult.failure(kAuthNotConfiguredMessage, AuthErrorKind.notConfigured);
    try {
      final res = await _client
          .post(_authUri('token', {'grant_type': 'password'}), headers: _headers, body: jsonEncode({'email': email, 'password': password}))
          .timeout(const Duration(seconds: 20));
      final body = _tryDecode(res.body);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final session = _sessionFromTokenResponse(body, fallbackEmail: email);
        if (session == null) return const AuthResult.failure('로그인에 실패했습니다. 다시 시도해주세요.');
        await _saveSession(session);
        return AuthResult.success(session);
      }
      return _failureFrom(res.statusCode, body);
    } on TimeoutException {
      return const AuthResult.failure('네트워크 연결을 확인해주세요.', AuthErrorKind.network);
    } on http.ClientException {
      return const AuthResult.failure('네트워크 연결을 확인해주세요.', AuthErrorKind.network);
    } catch (_) {
      return const AuthResult.failure('네트워크 연결을 확인해주세요.', AuthErrorKind.network);
    }
  }

  @override
  Future<void> signOut() async {
    final session = await _readSavedSession();
    if (isConfigured && session != null) {
      try {
        await _client
            .post(_authUri('logout'), headers: {..._headers, 'Authorization': 'Bearer ${session.accessToken}'})
            .timeout(const Duration(seconds: 10));
      } catch (_) {
        // 로그아웃 요청이 실패해도 로컬 세션은 반드시 지운다(§5 — 로그아웃은
        // 사용자를 다시 로그인 화면으로 보내는 것이 최우선).
      }
    }
    await _clearSession();
  }

  @override
  Future<AuthSession?> restoreSession() async {
    final saved = await _readSavedSession();
    if (saved == null) return null;
    if (!saved.isExpired) return saved;
    if (!isConfigured) return null;
    // 만료된 세션 — refresh token으로 재확인(§5).
    try {
      final res = await _client
          .post(_authUri('token', {'grant_type': 'refresh_token'}), headers: _headers, body: jsonEncode({'refresh_token': saved.refreshToken}))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final session = _sessionFromTokenResponse(_tryDecode(res.body), fallbackEmail: saved.email);
        if (session != null) {
          await _saveSession(session);
          return session;
        }
      }
    } catch (_) {
      // 네트워크 오류로 갱신 실패 — 세션 없음으로 취급(로그인 화면에서 다시 시도).
    }
    await _clearSession();
    return null;
  }

  AuthSession? _sessionFromTokenResponse(Object? body, {required String fallbackEmail}) {
    if (body is! Map) return null;
    final access = body['access_token'];
    final refresh = body['refresh_token'];
    final expiresIn = body['expires_in'];
    final user = body['user'];
    if (access is! String || refresh is! String) return null;
    final seconds = expiresIn is int ? expiresIn : (expiresIn is num ? expiresIn.toInt() : 3600);
    String userId = '';
    String email = fallbackEmail;
    if (user is Map) {
      userId = '${user['id'] ?? ''}';
      email = '${user['email'] ?? fallbackEmail}';
    }
    return AuthSession(
      userId: userId,
      email: email,
      accessToken: access,
      refreshToken: refresh,
      expiresAt: DateTime.now().toUtc().add(Duration(seconds: seconds)),
    );
  }

  AuthResult _failureFrom(int statusCode, Object? body) {
    String code = '';
    String msg = '';
    if (body is Map) {
      code = '${body['error_code'] ?? body['code'] ?? ''}'.toLowerCase();
      msg = '${body['msg'] ?? body['error_description'] ?? body['message'] ?? ''}'.toLowerCase();
    }
    AuthErrorKind kind;
    String korean;
    if (statusCode == 429 || code.contains('rate') || msg.contains('rate limit')) {
      kind = AuthErrorKind.rateLimited;
      korean = '요청이 너무 많습니다. 잠시 후 다시 시도해주세요.';
    } else if (code.contains('email_not_confirmed') || msg.contains('not confirmed') || msg.contains('confirm')) {
      kind = AuthErrorKind.emailNotConfirmed;
      korean = '이메일 확인이 필요합니다. 메일함을 확인해주세요.';
    } else if (code.contains('user_already_registered') || msg.contains('already registered') || msg.contains('already exists')) {
      kind = AuthErrorKind.emailAlreadyRegistered;
      korean = '이미 가입된 이메일입니다.';
    } else if (code.contains('weak_password') || (msg.contains('password') && (msg.contains('short') || msg.contains('weak') || msg.contains('least')))) {
      kind = AuthErrorKind.weakPassword;
      korean = '비밀번호가 보안 정책에 맞지 않습니다(최소 8자 이상).';
    } else if (code.contains('invalid_credentials') || msg.contains('invalid login') || msg.contains('invalid email or password')) {
      kind = AuthErrorKind.invalidCredentials;
      korean = '이메일 또는 비밀번호가 올바르지 않습니다.';
    } else if (msg.contains('invalid') && msg.contains('email')) {
      kind = AuthErrorKind.invalidEmail;
      korean = '올바른 이메일 형식이 아닙니다.';
    } else {
      kind = AuthErrorKind.unknown;
      korean = '요청을 처리하지 못했습니다. 잠시 후 다시 시도해주세요.';
    }
    return AuthResult.failure(korean, kind);
  }

  Object? _tryDecode(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  Future<Directory> _resolveSessionDir() async => _sessionDirOverride ?? await getApplicationDocumentsDirectory();

  Future<File> _sessionFile() async {
    final dir = await _resolveSessionDir();
    return File('${dir.path}${Platform.pathSeparator}space_shift_auth_session.json');
  }

  Future<void> _saveSession(AuthSession session) async {
    final f = await _sessionFile();
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(session.toJson()), flush: true);
    if (await f.exists()) await f.delete();
    await tmp.rename(f.path);
  }

  Future<AuthSession?> _readSavedSession() async {
    try {
      final f = await _sessionFile();
      if (!await f.exists()) return null;
      return AuthSession.tryFromJson(jsonDecode(await f.readAsString()));
    } catch (_) {
      return null;
    }
  }

  Future<void> _clearSession() async {
    try {
      final f = await _sessionFile();
      if (await f.exists()) await f.delete();
    } catch (_) {
      // 삭제 실패해도 앱 인증 상태(메모리)는 이미 초기화됨.
    }
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
