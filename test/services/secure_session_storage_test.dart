// SS-수정002 §2·§8 — 세션을 OS 보안 저장소(flutter_secure_storage)에 두고,
// 기존 SharedPreferences 세션은 한 번 보안 저장소로 이전한 뒤 그 키만
// 지운다(다른 SharedPreferences 값은 건드리지 않는다). 보안 저장소를 쓸 수
// 없으면 기존 저장소로 자동 동작한다.
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ason_space/services/secure_session_storage.dart';

class _ThrowingSecureStore implements SecureKeyValueStore {
  @override
  Future<bool> containsKey({required String key}) async {
    throw UnsupportedError('이 테스트 환경에는 보안 저장소가 없다');
  }

  @override
  Future<String?> read({required String key}) async {
    throw UnsupportedError('이 테스트 환경에는 보안 저장소가 없다');
  }

  @override
  Future<void> write({required String key, required String? value}) async {
    throw UnsupportedError('이 테스트 환경에는 보안 저장소가 없다');
  }

  @override
  Future<void> delete({required String key}) async {
    throw UnsupportedError('이 테스트 환경에는 보안 저장소가 없다');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test('보안 저장소에 바로 쓰고 읽고 지울 수 있다', () async {
    final storage = SecureSessionStorage(persistSessionKey: 'sb-case1-auth-token');
    await storage.initialize();

    expect(await storage.hasAccessToken(), isFalse);

    await storage.persistSession('session-value-1');
    expect(await storage.hasAccessToken(), isTrue);
    expect(await storage.accessToken(), 'session-value-1');

    await storage.removePersistedSession();
    expect(await storage.hasAccessToken(), isFalse);
  });

  test('persistSession에 넘긴 값만 그대로 저장된다 — 비밀번호 필드는 전혀 쓰이지 않는다', () async {
    final storage = SecureSessionStorage(persistSessionKey: 'sb-case2-auth-token');
    await storage.initialize();

    const sessionJson = '{"access_token":"tok","refresh_token":"ref","user":{"id":"u1"}}';
    await storage.persistSession(sessionJson);

    final stored = await storage.accessToken();
    expect(stored, sessionJson);
    expect(stored, isNot(contains('password')));
  });

  test('기존 SharedPreferences 세션이 있으면 초기화 시 보안 저장소로 한 번 이전하고, 원래 키만 지운다', () async {
    const key = 'sb-migrate-auth-token';
    SharedPreferences.setMockInitialValues({
      key: 'legacy-session-value',
      'other_user_pref': 'keep-me',
    });

    final storage = SecureSessionStorage(persistSessionKey: key);
    await storage.initialize();

    expect(await storage.hasAccessToken(), isTrue);
    expect(await storage.accessToken(), 'legacy-session-value');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(key), isFalse, reason: '기존 SharedPreferences의 세션 키는 지운다');
    expect(prefs.getString('other_user_pref'), 'keep-me', reason: '다른 SharedPreferences 값은 건드리지 않는다');
  });

  test('보안 저장소에 이미 세션이 있으면 기존(SharedPreferences) 값으로 덮어쓰지 않는다(그래도 기존 키는 정리한다)', () async {
    const key = 'sb-already-migrated-auth-token';
    FlutterSecureStorage.setMockInitialValues({key: 'secure-current-value'});
    SharedPreferences.setMockInitialValues({key: 'legacy-stale-value'});

    final storage = SecureSessionStorage(persistSessionKey: key);
    await storage.initialize();

    expect(await storage.accessToken(), 'secure-current-value');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(key), isFalse, reason: '이전 완료 여부와 관계없이 기존 키는 정리한다');
  });

  test('보안 저장소를 쓸 수 없으면 기존 저장소로 동작한다(이유는 debugPrint로만 남긴다)', () async {
    final storage = SecureSessionStorage(
      persistSessionKey: 'sb-fallback-auth-token',
      secureStore: _ThrowingSecureStore(),
    );
    await storage.initialize();

    expect(await storage.hasAccessToken(), isFalse);
    await storage.persistSession('fallback-session-value');
    expect(await storage.accessToken(), 'fallback-session-value');
    expect(await storage.hasAccessToken(), isTrue);

    await storage.removePersistedSession();
    expect(await storage.hasAccessToken(), isFalse);
  });
}
