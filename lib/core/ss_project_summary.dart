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

/// MASTER UI 3 — 프로젝트 카드의 5단계 진행 점(업로드 · 분석 · 생성 · 수정 · 완료).
enum SsProjectPhase {
  upload('업로드'),
  analysis('분석'),
  generate('생성'),
  edit('수정'),
  done('완료');

  const SsProjectPhase(this.label);
  final String label;
}

/// 5단계 점 하나의 상태 — 지난 단계(체크), 현재 단계(강조한 빈 원), 남은 단계(빈 원).
enum SsPhaseState { completed, current, upcoming }

abstract final class SsProjectSummary {
  static const int maxNameLength = 30;

  /// 실제 작업 단계를 5개 묶음으로 나눈다. 세 FLOW 모두 흐름 순서대로 묶음이 줄지 않는다.
  static SsProjectPhase phaseOfStage(SsStage stage) => switch (stage) {
    SsStage.floorPlanReview || SsStage.cadConversion => SsProjectPhase.analysis,
    SsStage.cadEditor || SsStage.isoConversion || SsStage.imageRendering => SsProjectPhase.generate,
    SsStage.isoEditor || SsStage.elevationFaceEditor || SsStage.isoRendering => SsProjectPhase.edit,
    SsStage.finalResult || SsStage.imageResult => SsProjectPhase.done,
    _ => SsProjectPhase.upload,
  };

  /// 프로젝트의 지금 묶음(저장된 단계가 그 FLOW에 없으면 첫 단계 기준).
  static SsProjectPhase phase(SsProject p) => phaseOfStage(flow(p)[stepIndex(p)]);

  /// 5개 점 각각의 상태. 완료된 프로젝트는 모두 지난 단계(체크)로 본다.
  static List<SsPhaseState> phaseStates(SsProject p) {
    final complete = status(p) == SsProjectStatus.done;
    final cur = phase(p).index;
    return [
      for (final ph in SsProjectPhase.values)
        if (complete || ph.index < cur)
          SsPhaseState.completed
        else if (ph.index == cur)
          SsPhaseState.current
        else
          SsPhaseState.upcoming,
    ];
  }

  /// 자세한 단계 문구(툴팁) — "n/m 단계 · 다음: …".
  static String stepDetail(SsProject p) {
    final next = SsFlows.next(p.sourceType, resumeStage(p));
    return '${stepIndex(p) + 1}/${stepCount(p)} 단계 · ${next == null ? '완료' : '다음: ${next.title}'}';
  }

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
