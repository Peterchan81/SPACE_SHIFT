/// SS-수정002 §2 — Supabase 세션을 OS 보안 저장소(flutter_secure_storage)에
/// 둔다. supabase_flutter의 [supa.LocalStorage] 인터페이스를 구현해
/// `Supabase.initialize(authOptions: FlutterAuthClientOptions(localStorage: ...))`
/// 에 넘긴다(lib/main.dart). 보안 저장소를 쓸 수 없는 플랫폼·오류에서는
/// [SecureSessionStorage.isAvailable]이 false를 돌려줘 호출자가
/// supabase_flutter 기본 저장소(SharedPreferences)로 그대로 동작하게
/// 한다 — 토큰 값은 어떤 경우에도 debugPrint하지 않는다.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

/// supabase_flutter가 `Supabase.instance.client`의 세션을 저장/조회할 때
/// 쓰는 한 개의 키-값(JSON 문자열) 저장소를 OS 보안 저장소로 구현한다.
class SecureSessionStorage extends supa.LocalStorage {
  SecureSessionStorage({FlutterSecureStorage? secureStorage}) : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;

  /// 보안 저장소 안에서 세션 전체(JSON)를 담는 키 — [supa.LocalStorage]
  /// 계약은 키 하나만 쓰므로, 다른 앱 데이터와 섞이지 않는 전용 키를 쓴다.
  static const String storageKey = 'ss_space_shift_secure_auth_session';

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async {
    try {
      return await _secureStorage.containsKey(key: storageKey);
    } catch (e, st) {
      debugPrint('SecureSessionStorage.hasAccessToken 실패(보안 저장소 사용 불가로 간주): ${e.runtimeType}\n$st');
      return false;
    }
  }

  @override
  Future<String?> accessToken() async {
    try {
      return await _secureStorage.read(key: storageKey);
    } catch (e, st) {
      debugPrint('SecureSessionStorage.accessToken 실패: ${e.runtimeType}\n$st');
      return null;
    }
  }

  @override
  Future<void> removePersistedSession() async {
    try {
      await _secureStorage.delete(key: storageKey);
    } catch (e, st) {
      debugPrint('SecureSessionStorage.removePersistedSession 실패: ${e.runtimeType}\n$st');
    }
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    try {
      await _secureStorage.write(key: storageKey, value: persistSessionString);
    } catch (e, st) {
      debugPrint('SecureSessionStorage.persistSession 실패: ${e.runtimeType}\n$st');
    }
  }

  /// 이 기기·플랫폼에서 보안 저장소를 실제로 쓸 수 있는지 한 번 확인한다
  /// (§2 "쓸 수 없는 플랫폼·오류에서는 기존 기본 저장소로 동작"). 더미
  /// 값으로 쓰기·읽기·지우기를 모두 시도해 실패하면 false — 실제 세션
  /// 토큰은 다루지 않는다.
  static Future<bool> isAvailable({FlutterSecureStorage? secureStorage}) async {
    final storage = secureStorage ?? const FlutterSecureStorage();
    const probeKey = 'ss_space_shift_secure_storage_probe';
    try {
      await storage.write(key: probeKey, value: 'ok');
      final value = await storage.read(key: probeKey);
      await storage.delete(key: probeKey);
      return value == 'ok';
    } catch (e, st) {
      debugPrint('SecureSessionStorage: 이 플랫폼에서 보안 저장소를 쓸 수 없어 기본 저장소로 동작합니다: ${e.runtimeType}\n$st');
      return false;
    }
  }
}

/// main.dart가 과거(SS-수정002 이전) `Supabase.initialize()`에 아무
/// `authOptions.localStorage`도 넘기지 않았을 때 supabase_flutter
/// 2.18.3이 내부적으로 만들어 쓰던 기본 저장소와 같은 규칙으로 키를
/// 계산한다 — `"sb-\${Uri.parse(url).host.split(".").first}-auth-token"`
/// (설치된 supabase_flutter 소스, `lib/src/supabase.dart`의
/// `Supabase.initialize()`로 확인).
supa.LocalStorage legacySharedPreferencesStorage(String supabaseUrl) {
  final host = Uri.tryParse(supabaseUrl)?.host ?? '';
  final firstLabel = host.isEmpty ? 'default' : host.split('.').first;
  return supa.SharedPreferencesLocalStorage(persistSessionKey: 'sb-$firstLabel-auth-token');
}

/// SS-수정002 §2 — [from]에 이미 저장된 세션이 있으면 [to]로 한 번 옮기고,
/// [from]의 그 키만 지운다. [supa.LocalStorage] 계약 자체가 세션 키
/// 하나만 다루므로, "다른 SharedPreferences 값과 사용자 데이터는 건드리지
/// 않는다"는 요구가 구조적으로 보장된다. [to]에 이미 세션이 있으면(이미
/// 이전했음) 아무 것도 하지 않는다(중복 이전 방지). 실패해도 예외를
/// 던지지 않고 원인만 남긴다(토큰 값은 남기지 않는다) — 이전 실패의
/// 유일한 영향은 로그인 화면이 다시 보이는 것이다.
Future<void> migrateSessionStorage({
  required supa.LocalStorage from,
  required supa.LocalStorage to,
}) async {
  try {
    if (await to.hasAccessToken()) return;
    await from.initialize();
    if (!await from.hasAccessToken()) return;
    final value = await from.accessToken();
    if (value == null || value.isEmpty) return;
    await to.persistSession(value);
    await from.removePersistedSession();
    debugPrint('SS-수정002: 기존 저장소의 세션을 보안 저장소로 한 번 이전했습니다.');
  } catch (e, st) {
    debugPrint('SS-수정002: 세션 저장소 이전 실패(무시, 토큰 값은 남기지 않음): ${e.runtimeType}\n$st');
  }
}
