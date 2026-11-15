/// SS-BUG-011 — 좌측 메뉴 "진행 중인 프로젝트"와 상단 알림 패널이 함께 쓰는, 실제 프로젝트 저장소의
/// 프로젝트를 최근 수정순으로 읽는 도우미(가짜 데이터를 만들지 않는다).
library;

import 'ss_project.dart';
import 'ss_project_store.dart';
import 'ss_project_summary.dart';

abstract final class SsRecentProjects {
  /// 저장소의 모든 프로젝트를 읽어 최근 수정순으로 돌려준다(읽지 못한 프로젝트는 건너뛴다).
  static Future<List<SsProject>> load(SsProjectStore store) async {
    final ids = await store.list();
    final out = <SsProject>[];
    for (final id in ids) {
      final p = await store.load(id);
      if (p != null) out.add(p);
    }
    out.sort((a, b) => SsProjectSummary.lastUpdated(b).compareTo(SsProjectSummary.lastUpdated(a)));
    return out;
  }
}
