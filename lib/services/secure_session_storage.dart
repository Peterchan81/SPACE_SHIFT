/// SS-수정002 §2 — Supabase 세션(access/refresh token)을 OS 보안 저장소
/// (flutter_secure_storage — Android Keystore, iOS/macOS Keychain, Windows
/// DPAPI, Linux libsecret)에 저장하는 supabase_flutter [supa.LocalStorage] 구현.
///
/// 비밀번호는 이 클래스가 전혀 다루지 않는다 — Supabase 세션에는 비밀번호가
/// 없다(access/refresh token만 저장한다. "비밀번호는 어디에도 저장하지
/// 않는다" 요구는 바뀌지 않는다).
///
/// 기존 SharedPreferences 저장소([supa.SharedPreferencesLocalStorage], 이
/// 앱이 지금까지 써 온 supabase_flutter 기본값)에 세션이 남아 있으면
/// [initialize]가 한 번 보안 저장소로 옮기고, 그 SharedPreferences 키만
/// 지운다(다른 SharedPreferences 값·사용자 데이터는 건드리지 않는다).
///
/// 보안 저장소를 쓸 수 없는 플랫폼이거나 호출이 실패하면 기존
/// SharedPreferences 저장소로 자동으로 동작하고, 이유를 debugPrint로 남긴다
/// (토큰 값은 남기지 않는다).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

/// [FlutterSecureStorage]에서 이 클래스가 실제로 쓰는 부분만 뽑은 좁은
/// 인터페이스 — 테스트에서 "보안 저장소를 쓸 수 없는 경우"를 쉽게 흉내낼 수
/// 있게 한다(패키지 클래스를 직접 서브클래싱하지 않는다).
abstract class SecureKeyValueStore {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String? value});
  Future<bool> containsKey({required String key});
  Future<void> delete({required String key});
}

class _FlutterSecureKeyValueStore implements SecureKeyValueStore {
  const _FlutterSecureKeyValueStore(this._storage);
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String? value}) => _storage.write(key: key, value: value);

  @override
  Future<bool> containsKey({required String key}) => _storage.containsKey(key: key);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);
}

/// supabase_flutter의 [supa.LocalStorage]를 OS 보안 저장소로 구현한다.
/// `Supabase.initialize(authOptions: FlutterAuthClientOptions(localStorage: ...))`
/// 에 넘겨 쓴다.
class SecureSessionStorage extends supa.LocalStorage {
  SecureSessionStorage({required String persistSessionKey, SecureKeyValueStore? secureStore, supa.LocalStorage? legacyStorage})
    : _key = persistSessionKey,
      _secure = secureStore ?? const _FlutterSecureKeyValueStore(FlutterSecureStorage()),
      _legacy = legacyStorage ?? supa.SharedPreferencesLocalStorage(persistSessionKey: persistSessionKey);

  final String _key;
  final SecureKeyValueStore _secure;
  final supa.LocalStorage _legacy;

  bool _secureAvailable = true;

  @override
  Future<void> initialize() async {
    try {
      await _legacy.initialize();
    } catch (e, st) {
      debugPrint('SecureSessionStorage: 기존 저장소 초기화 실패(무시): ${e.runtimeType}\n$st');
    }
    try {
      await _secure.containsKey(key: _key);
    } catch (e, st) {
      _secureAvailable = false;
      debugPrint('SecureSessionStorage: 보안 저장소를 쓸 수 없어 기존 저장소로 동작합니다: ${e.runtimeType}\n$st');
    }
    if (_secureAvailable) {
      await _migrateFromLegacyIfNeeded();
    }
  }

  /// §2 "기존 SharedPreferences에 저장된 세션이 있으면 한 번 보안 저장소로
  /// 옮기고 원래 키만 지운다" — [_legacy]는 이 persistSessionKey 하나만
  /// 다루므로, 지우는 것도 그 키 하나뿐이다(다른 SharedPreferences 값·
  /// 사용자 데이터는 건드리지 않는다). 보안 저장소에 이미 값이 있으면(이미
  /// 이전됐거나 그 사이 새로 로그인한 경우) 덮어쓰지 않는다 — 그래도 기존
  /// 키는 정리한다.
  Future<void> _migrateFromLegacyIfNeeded() async {
    try {
      final hasLegacy = await _legacy.hasAccessToken();
      if (!hasLegacy) return;
      final alreadyMigrated = await _secure.containsKey(key: _key);
      if (!alreadyMigrated) {
        final value = await _legacy.accessToken();
        if (value != null) {
          await _secure.write(key: _key, value: value);
        }
      }
      await _legacy.removePersistedSession();
    } catch (e, st) {
      debugPrint('SecureSessionStorage: 기존 세션 이전 실패(무시, 토큰 값은 남기지 않음): ${e.runtimeType}\n$st');
    }
  }

  @override
  Future<bool> hasAccessToken() async {
    if (_secureAvailable) {
      try {
        return await _secure.containsKey(key: _key);
      } catch (e, st) {
        _onSecureFailure(e, st);
      }
    }
    return _legacy.hasAccessToken();
  }

  @override
  Future<String?> accessToken() async {
    if (_secureAvailable) {
      try {
        return await _secure.read(key: _key);
      } catch (e, st) {
        _onSecureFailure(e, st);
      }
    }
    return _legacy.accessToken();
  }

  @override
  Future<void> removePersistedSession() async {
    if (_secureAvailable) {
      try {
        await _secure.delete(key: _key);
      } catch (e, st) {
        _onSecureFailure(e, st);
      }
    }
    await _legacy.removePersistedSession();
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    if (_secureAvailable) {
      try {
        await _secure.write(key: _key, value: persistSessionString);
        return;
      } catch (e, st) {
        _onSecureFailure(e, st);
      }
    }
    await _legacy.persistSession(persistSessionString);
  }

  void _onSecureFailure(Object error, StackTrace stackTrace) {
    _secureAvailable = false;
    debugPrint(
      'SecureSessionStorage: 보안 저장소 오류로 기존 저장소를 씁니다(토큰 값은 남기지 않음): '
      '${error.runtimeType}\n$stackTrace',
    );
  }
}
