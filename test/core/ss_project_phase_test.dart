// SS-수정003 3차 — 실제 작업 단계를 MASTER 03 5단계(업로드·분석·생성·수정·완료)로 묶는 함수.
import 'package:ason_space/core/ss_project.dart';
import 'package:ason_space/core/ss_project_summary.dart';
import 'package:ason_space/core/ss_stage.dart';
import 'package:flutter_test/flutter_test.dart';

const _c = SsPhaseState.completed;
const _cur = SsPhaseState.current;
const _u = SsPhaseState.upcoming;

SsProject _p(SsSourceType t, [SsStage? stage]) {
  final p = SsProject.create(id: 'x', name: 'x', sourceType: t, now: DateTime(2026, 1, 1));
  return stage == null ? p : p.moveTo(stage, now: DateTime(2026, 1, 2));
}

void main() {
  test('각 FLOW에서 단계 순서대로 묶음이 줄지 않고, 첫 단계는 업로드·마지막 단계는 완료', () {
    for (final entry in SsFlows.stages.entries) {
      final phases = [for (final s in entry.value) SsProjectSummary.phaseOfStage(s).index];
      for (var i = 1; i < phases.length; i++) {
        expect(phases[i] >= phases[i - 1], isTrue, reason: '${entry.key} $i');
      }
      expect(phases.first, SsProjectPhase.upload.index);
      expect(phases.last, SsProjectPhase.done.index);
    }
  });

  test('평면도 업로드 흐름 — 처음·중간·완료', () {
    expect(SsProjectSummary.phaseStates(_p(SsSourceType.floorPlanUpload)), [_cur, _u, _u, _u, _u]);
    expect(SsProjectSummary.phase(_p(SsSourceType.floorPlanUpload, SsStage.floorPlanReview)), SsProjectPhase.analysis);
    expect(SsProjectSummary.phaseStates(_p(SsSourceType.floorPlanUpload, SsStage.cadEditor)), [_c, _c, _cur, _u, _u]);
    expect(SsProjectSummary.phaseStates(_p(SsSourceType.floorPlanUpload, SsStage.finalResult)), [_c, _c, _c, _c, _c]);
  });

  test('직접 그리기 흐름 — 처음·중간·완료', () {
    expect(SsProjectSummary.phaseStates(_p(SsSourceType.directDraw)), [_cur, _u, _u, _u, _u]);
    expect(SsProjectSummary.phaseStates(_p(SsSourceType.directDraw, SsStage.cadConversion)), [_c, _cur, _u, _u, _u]);
    expect(SsProjectSummary.phaseStates(_p(SsSourceType.directDraw, SsStage.isoEditor)), [_c, _c, _c, _cur, _u]);
    expect(SsProjectSummary.phaseStates(_p(SsSourceType.directDraw, SsStage.finalResult)), [_c, _c, _c, _c, _c]);
  });

  test('이미지 변환 흐름 — 처음·중간·완료', () {
    expect(SsProjectSummary.phaseStates(_p(SsSourceType.imageTransform)), [_cur, _u, _u, _u, _u]);
    expect(SsProjectSummary.phaseStates(_p(SsSourceType.imageTransform, SsStage.imageRendering)), [_c, _c, _cur, _u, _u]);
    expect(SsProjectSummary.phaseStates(_p(SsSourceType.imageTransform, SsStage.imageResult)), [_c, _c, _c, _c, _c]);
  });

  test('자세한 단계 문구(툴팁)', () {
    expect(SsProjectSummary.stepDetail(_p(SsSourceType.imageTransform)), '1/3 단계 · 다음: ${SsStage.imageRendering.title}');
    expect(SsProjectSummary.stepDetail(_p(SsSourceType.imageTransform, SsStage.imageResult)), '3/3 단계 · 완료');
  });
}
