// SS-수정002 §2·§8 — 기존 저장소에 있는 세션을 새 저장소로 한 번 옮기고,
// 원래 저장소의 그 키만 지우는지 검증한다. 실제 flutter_secure_storage
// 플랫폼 채널(OS 보안 저장소)에는 의존하지 않도록, LocalStorage 계약만
// 구현한 가짜 저장소로 migrateSessionStorage의 로직을 검증한다 — 실제
// 보안 저장소 자체의 동작(Windows Credential Locker 등)은 사람이 실기에서
// 확인한다(실기 미검증).
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

import 'package:ason_space/services/secure_session_storage.dart';

class _InMemoryLocalStorage extends supa.LocalStorage {
  String? session;
  bool initializeCalled = false;

  @override
  Future<void> initialize() async {
    initializeCalled = true;
  }

  @override
  Future<bool> hasAccessToken() async => session != null;

  @override
  Future<String?> accessToken() async => session;

  @override
  Future<void> removePersistedSession() async {
    session = null;
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    session = persistSessionString;
  }
}

void main() {
  group('migrateSessionStorage — 기존 저장소 → 새 저장소로 한 번 이전(§2·§8)', () {
    test('기존 저장소에 세션이 있으면 새 저장소로 옮기고 원래 키만 지운다', async () async {
      final legacy = _InMemoryLocalStorage()..session = 'session-json-value';
      final secure = _InMemoryLocalStorage();

      await migrateSessionStorage(from: legacy, to: secure);

      expect(await secure.accessToken(), 'session-json-value');
      expect(await legacy.hasAccessToken(), isFalse, reason: '기존 저장소의 세션 키는 지워진다');
      expect(legacy.initializeCalled, isTrue);
    });

    test('기존 저장소에 세션이 없으면 아무 것도 하지 않는다', async () async {
      final legacy = _InMemoryLocalStorage();
      final secure = _InMemoryLocalStorage();

      await migrateSessionStorage(from: legacy, to: secure);

      expect(await secure.hasAccessToken(), isFalse);
    });

    test('새 저장소에 이미 세션이 있으면(이미 이전됨) 다시 옮기지 않고 기존 저장소도 건드리지 않는다', async () async {
      final legacy = _InMemoryLocalStorage()..session = 'old-session';
      final secure = _InMemoryLocalStorage()..session = 'already-migrated';

      await migrateSessionStorage(from: legacy, to: secure);

      expect(await secure.accessToken(), 'already-migrated');
      expect(await legacy.accessToken(), 'old-session', reason: '이미 이전된 경우 원래 저장소를 건드리지 않는다');
    });

    test('legacySharedPreferencesStorage — URL의 호스트 첫 조각으로 supabase_flutter 기본 키와 같은 규칙의 키를 만든다', () {
      final storage = legacySharedPreferencesStorage('https://abcdefgh.supabase.co');

      expect(storage, isA<supa.SharedPreferencesLocalStorage>());
      expect((storage as supa.SharedPreferencesLocalStorage).persistSessionKey, 'sb-abcdefgh-auth-token');
    });
  });

  group('SecureSessionStorage — 보안 저장소를 쓸 수 없는 환경(테스트)에서도 안전하게 동작', () {
    test('isAvailable()은 플랫폼 채널이 없는 테스트 환경에서도 예외 없이 완료된다', async () async {
      await expectLater(SecureSessionStorage.isAvailable(), completes);
    });

    test('각 메서드는 보안 저장소를 쓸 수 없어도 예외를 던지지 않고 완료된다(토큰 없음으로 처리)', async () async {
      final storage = SecureSessionStorage();

      await expectLater(storage.initialize(), completes);
      await expectLater(storage.hasAccessToken(), completes);
      await expectLater(storage.accessToken(), completes);
      await expectLater(storage.removePersistedSession(), completes);
      await expectLater(storage.persistSession('x'), completes);
    });
  });
}

/// `test('설명', async () async { ... });` 표기를 쓰기 위한 아주 작은
/// identity 헬퍼.
Future<void> Function() async(Future<void> Function() body) => body;
