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
    // 쪽이 없어 getApplicationDocumentsDirectory() 호출이 곧바로 실패할 수 있다)
    // 에서도 실제 Timer를 두지 않는다 — flutter_test는 가짜 시간(FakeAsync) 위에서
    // 실행되므로, pumpAndSettle()이 흘려보내지 않는 실제 시간만큼의 Timer를 두면
    // 위젯 트리가 사라진 뒤에도 Timer가 "pending" 상태로 남아 테스트가 실패한다.
    // 그래서 그냥 호출만 하고, 실패하면(실기기에서는 거의 없는 경우) 호출자
    // (HomeScreen._load 등)의 기존 일반 오류 처리로 넘긴다.
    final docs = await getApplicationDocumentsDirectory();
    return FileSsProjectStore(Directory('${docs.path}${Platform.pathSeparator}space_shift_projects'));
  }
}
