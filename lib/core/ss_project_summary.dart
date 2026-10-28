/// SS004 — 프로젝트 관리·생성 화면이 쓰는 계산(상태·진행률·재개 단계·검색/정렬·이름 검사).
/// 화면과 분리해 단위 테스트할 수 있게 한다.
library;

import 'package:ason_space/core/ss_project.dart';
import 'package:ason_space/core/ss_stage.dart';

/// 프로젝트 카드에 보이는 상태.
enum SsProjectStatus {
  draft('초안'),
  inProgress('진행 중'),
  needsUpdate('업데이트 필요'),
  done('완료');

  const SsProjectStatus(this.label);
  final String label;
}

/// 프로젝트 목록 정렬.
enum SsProjectSort {
  recent('최근 수정순'),
  name('이름순'),
  created('생성일순');

  const SsProjectSort(this.label);
  final String label;
}

abstract final class SsProjectSummary {
  static const int maxNameLength = 30;

  static List<SsStage> flow(SsProject p) => SsFlows.stages[p.sourceType]!;

  /// 저장된 단계가 그 FLOW에 없으면(손상) 첫 단계로 본다.
  static int stepIndex(SsProject p) {
    final i = flow(p).indexOf(p.currentStage);
    return i < 0 ? 0 : i;
  }

  static int stepCount(SsProject p) => flow(p).length;

  /// 다시 열 때 갈 단계 — 마지막 저장 단계(그 FLOW의 단계가 아니면 첫 단계).
  static SsStage resumeStage(SsProject p) => SsFlows.belongs(p.sourceType, p.currentStage) ? p.currentStage : SsFlows.firstStage(p.sourceType);

  static SsProjectStatus status(SsProject p) {
    final stage = resumeStage(p);
    if (SsFlows.next(p.sourceType, stage) == null) return SsProjectStatus.done;
    if (p.staleNotices().isNotEmpty) return SsProjectStatus.needsUpdate;
    if (p.data.isEmpty && stepIndex(p) == 0) return SsProjectStatus.draft;
    return SsProjectStatus.inProgress;
  }

  /// 0~100 진행률.
  static int percent(SsProject p) {
    if (status(p) == SsProjectStatus.done) return 100;
    return (stepIndex(p) * 100 / stepCount(p)).round();
  }

  static DateTime lastUpdated(SsProject p) => p.updatedAt ?? p.info.createdAt;

  static String formatDate(DateTime dt) => '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';

  /// 대표 이미지 경로 후보(렌더링 → 3D → 원본 순). 파일이 실제로 있는지는 화면이 확인한다.
  static String? thumbnailCandidate(SsProject p) {
    for (final slot in const [SsDataSlot.renderData, SsDataSlot.isoData, SsDataSlot.sourceData]) {
      final payload = p[slot]?.payload;
      if (payload == null) continue;
      for (final key in const ['thumbnailPath', 'imagePath']) {
        final v = payload[key];
        if (v is String && v.trim().isNotEmpty) return v;
      }
    }
    return null;
  }

  static List<SsProject> filterAndSort(List<SsProject> projects, {String query = '', SsProjectSort sort = SsProjectSort.recent}) {
    final q = query.trim().toLowerCase();
    final out = [
      for (final p in projects)
        if (q.isEmpty || p.info.name.toLowerCase().contains(q) || p.sourceType.label.contains(q)) p,
    ];
    switch (sort) {
      case SsProjectSort.recent:
        out.sort((a, b) => lastUpdated(b).compareTo(lastUpdated(a)));
      case SsProjectSort.name:
        out.sort((a, b) => a.info.name.compareTo(b.info.name));
      case SsProjectSort.created:
        out.sort((a, b) => b.info.createdAt.compareTo(a.info.createdAt));
    }
    return out;
  }

  /// 프로젝트 이름 검사 — 문제가 없으면 null.
  static String? validateName(String raw) {
    final name = raw.trim();
    if (name.isEmpty) return '프로젝트 이름을 입력하세요.';
    if (name.length > maxNameLength) return '프로젝트 이름은 $maxNameLength자 이내로 입력하세요.';
    return null;
  }

  static String newProjectId(DateTime now) => 'p${now.microsecondsSinceEpoch}';
}
