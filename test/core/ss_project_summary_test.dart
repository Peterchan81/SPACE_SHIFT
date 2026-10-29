// SS004 — 프로젝트 상태·진행률·재개 단계·검색/정렬·이름 검사.
import 'package:ason_space/core/ss_project.dart';
import 'package:ason_space/core/ss_project_store.dart';
import 'package:ason_space/core/ss_project_summary.dart';
import 'package:ason_space/core/ss_stage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('새 프로젝트는 초안·0%이고 그 FLOW의 첫 단계에서 재개한다', () {
    for (final type in SsSourceType.values) {
      final p = SsProject.create(id: 'x', name: 'n', sourceType: type);
      expect(SsProjectSummary.status(p), SsProjectStatus.draft);
      expect(SsProjectSummary.percent(p), 0);
      expect(SsProjectSummary.resumeStage(p), SsFlows.firstStage(type));
    }
  });

  test('진행 중/완료/업데이트 필요 상태와 진행률', () {
    final mid = SsProject.create(id: 'a', name: 'a', sourceType: SsSourceType.directDraw).moveTo(SsStage.isoEditor);
    expect(SsProjectSummary.status(mid), SsProjectStatus.inProgress);
    expect(SsProjectSummary.percent(mid), 50);

    final done = SsProject.create(id: 'b', name: 'b', sourceType: SsSourceType.imageTransform).moveTo(SsStage.imageResult);
    expect(SsProjectSummary.status(done), SsProjectStatus.done);
    expect(SsProjectSummary.percent(done), 100);

    final stale = SsProject.create(id: 'c', name: 'c', sourceType: SsSourceType.floorPlanUpload)
        .withSource({'f': 1})
        .withStageData(SsDataSlot.recognitionData, {'r': 1}, label: 'AI')
        .withStageData(SsDataSlot.userCorrections, {'u': 1}, label: '수정')
        .withStageData(SsDataSlot.recognitionData, {'r': 2}, label: 'AI 다시')
        .moveTo(SsStage.floorPlanReview);
    expect(SsProjectSummary.status(stale), SsProjectStatus.needsUpdate);
  });

  test('검색과 정렬', () {
    final a = SsProject.create(id: 'a', name: '우리집 리모델링', sourceType: SsSourceType.directDraw, now: DateTime(2026, 1, 1));
    final b = SsProject.create(id: 'b', name: '상가 인테리어', sourceType: SsSourceType.imageTransform, now: DateTime(2026, 2, 1));
    final c = SsProject.create(id: 'c', name: '가게', sourceType: SsSourceType.floorPlanUpload, now: DateTime(2025, 12, 1)).moveTo(SsStage.floorPlanReview, now: DateTime(2026, 3, 1));
    final all = [a, b, c];
    expect(SsProjectSummary.filterAndSort(all).map((p) => p.info.id), ['c', 'b', 'a']);
    expect(SsProjectSummary.filterAndSort(all, sort: SsProjectSort.created).map((p) => p.info.id), ['b', 'a', 'c']);
    expect(SsProjectSummary.filterAndSort(all, sort: SsProjectSort.name).map((p) => p.info.id), ['c', 'b', 'a']);
    expect(SsProjectSummary.filterAndSort(all, query: '상가').map((p) => p.info.id), ['b']);
  });

  test('이름 검사', () {
    expect(SsProjectSummary.validateName('   '), isNotNull);
    expect(SsProjectSummary.validateName('a' * 31), isNotNull);
    expect(SsProjectSummary.validateName('우리집'), isNull);
  });

  test('메모리 저장소 삭제는 마지막 작업 기록도 지운다', () async {
    final store = MemorySsProjectStore();
    await store.save(SsProject.create(id: 'a', name: 'a', sourceType: SsSourceType.directDraw));
    await store.setLastOpened('a');
    await store.delete('a');
    expect(await store.list(), isEmpty);
    expect(await store.lastOpened(), isNull);
  });
}
