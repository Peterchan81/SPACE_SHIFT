/// SS003 — 홈 화면(및 이후 화면)이 함께 쓰는 프로젝트 저장소 하나.
///
/// 실제 앱은 기기 문서 폴더 아래 `space_shift_projects`에 저장하는
/// [FileSsProjectStore]를 쓴다(lib/core/ss_project_store.dart §6 주석대로,
/// path_provider로 그 폴더를 찾아 넘긴다). 폴더를 찾는 비동기 작업은 한 번만
/// 하고, 그 뒤로는 같은 [SsProjectStore] 인스턴스를 앱 전체가 공유한다.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/ss_project_store.dart';

class SsProjectStoreProvider {
  SsProjectStoreProvider._();

  static SsProjectStoreProvider instance = SsProjectStoreProvider._();

  /// 테스트에서 공유 상태를 초기화할 때 쓴다(화면은 보통 HomeScreen.projectStore로
  /// 가짜 저장소를 직접 주입하므로 이 provider 자체를 거치지 않는다).
  @visibleForTesting
  static void resetForTesting() => instance = SsProjectStoreProvider._();

  SsProjectStore? _store;
  Future<SsProjectStore>? _pending;

  /// 저장소 하나 — 처음 부르면 기기 문서 폴더 아래 `space_shift_projects`로 만든다.
  Future<SsProjectStore> store() {
    final cached = _store;
    if (cached != null) return Future.value(cached);
    return _pending ??= _create().then((s) {
      _store = s;
      return s;
    });
  }

  Future<SsProjectStore> _create() async {
    // 플랫폼 채널(path_provider)이 응답하지 않는 환경(예: flutter_test — 네이티브
    // 쪽이 없어 getApplicationDocumentsDirectory()의 Future가 영원히 끝나지
    // 않는다)에서 홈 화면 로딩이 멈춘 것처럼 보이는 것을 막는다. 짧게
    // 기다려도 응답이 없으면 TimeoutException으로 실패시켜, 호출자
    // (HomeScreen._load 등)의 기존 일반 오류 처리로 넘긴다 — 실기기에서는
    // 보통 즉시 응답하므로 동작에 영향이 없다.
    final docs = await getApplicationDocumentsDirectory().timeout(const Duration(seconds: 3));
    return FileSsProjectStore(Directory('${docs.path}${Platform.pathSeparator}space_shift_projects'));
  }
}
