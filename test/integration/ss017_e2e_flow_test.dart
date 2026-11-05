import 'package:flutter_test/flutter_test.dart';
import 'package:ason_space/core/ss_project.dart';
import 'package:ason_space/core/ss_project_store.dart';
import 'package:ason_space/core/ss_stage.dart';

/// SS017 — 전체 UX 통합 검증(코드로 고정할 수 있는 부분).
///
/// 실제 화면 3장(로그인/홈/프로젝트 관리 등)은 SS002~SS016에서 이미 구현·검증됐다.
/// 이 테스트는 그 화면들이 공유하는 핵심 데이터/저장 계층([SsProject], [SsFlows],
/// [SsAutosaveController])을 통해 작업지시서가 요구하는 세 가지 E2E FLOW가 실제로
/// "처음부터 끝까지 연결"되는지, 그리고 자동저장 실패/재시도/재시작 후 복원,
/// 이전 단계 수정 시 후속 CAD/ISO stale 전파가 동작하는지를 회귀 테스트로 고정한다.
void main() {
  group('FLOW A — 평면도 업로드 (로그인 이후 전체 단계가 끝까지 연결된다)', () {
    test('floorPlanUpload → … → finalResult까지 모든 단계를 통과하고 끝에는 stale 없음', () {
      var project = SsProject.create(
        id: 'p-a',
        name: '평면도 업로드 프로젝트',
        sourceType: SsSourceType.floorPlanUpload,
      );
      expect(project.currentStage, SsStage.floorPlanUpload);

      // 평면도 업로드(원본은 한 번만).
      project = project.withSource({'fileName': 'plan.jpg'}, label: '평면도 업로드');

      // AI 공간 인식 → 사용자 보정.
      project = project.moveTo(SsStage.floorPlanReview);
      project = project.withStageData(
        SsDataSlot.recognitionData,
        {'rooms': 3},
        label: 'AI 공간 인식',
      );
      project = project.withStageData(
        SsDataSlot.userCorrections,
        {'rooms': 3, 'fixed': true},
        label: '사용자 보정',
      );

      // CAD 변환 → CAD 편집.
      project = project.moveTo(SsStage.cadConversion);
      project = project.withStageData(
        SsDataSlot.cadData,
        {'walls': 10},
        label: 'CAD 변환',
      );
      project = project.moveTo(SsStage.cadEditor);

      // ISO 생성 → ISO 디자인/정면도 편집.
      project = project.moveTo(SsStage.isoConversion);
      project = project.withStageData(
        SsDataSlot.isoData,
        {'furniture': 5},
        label: 'ISO 변환',
      );
      project = project.moveTo(SsStage.isoEditor);
      project = project.moveTo(SsStage.elevationFaceEditor);

      // 렌더링 → 최종 결과.
      project = project.moveTo(SsStage.isoRendering);
      project = project.withStageData(
        SsDataSlot.renderData,
        {'image': 'final.png'},
        label: '렌더링',
      );
      project = project.moveTo(SsStage.finalResult);

      expect(project.currentStage, SsStage.finalResult);
      expect(project.staleNotices(), isEmpty);
      expect(SsFlows.next(SsSourceType.floorPlanUpload, SsStage.finalResult), isNull);
    });

    test('이전 단계(사용자 보정) 수정 시 CAD가 stale이 되고, CAD를 다시 만들면 이번엔 ISO가 stale이 된다', () {
      var project = SsProject.create(
        id: 'p-a2',
        name: '평면도 업로드 프로젝트 — stale 전파',
        sourceType: SsSourceType.floorPlanUpload,
      );
      project = project.withSource({'fileName': 'plan.jpg'}, label: '평면도 업로드');
      project = project.withStageData(SsDataSlot.recognitionData, {'rooms': 3}, label: 'AI 공간 인식');
      project = project.withStageData(SsDataSlot.userCorrections, {'rooms': 3}, label: '사용자 보정');
      project = project.withStageData(SsDataSlot.cadData, {'walls': 10}, label: 'CAD 변환');
      project = project.withStageData(SsDataSlot.isoData, {'furniture': 5}, label: 'ISO 변환');
      expect(project.staleNotices(), isEmpty);

      // 사용자가 평면도 보정을 다시 고친다 — CAD는 낡은 보정을 기준으로 만들어졌다.
      project = project.withStageData(SsDataSlot.userCorrections, {'rooms': 4}, label: '사용자 보정(수정)');

      final staleAfterCorrection = project.staleNotices();
      expect(staleAfterCorrection, isNotEmpty);
      expect(staleAfterCorrection.single.stale, SsDataSlot.cadData);
      expect(staleAfterCorrection.single.changed, SsDataSlot.userCorrections);
      expect(staleAfterCorrection.single.message, contains('CAD'));

      // CAD를 최신 보정 기준으로 다시 만든다 — 이번엔 CAD가 더 새로워져 ISO가 낡는다.
      project = project.withStageData(SsDataSlot.cadData, {'walls': 11}, label: 'CAD 다시 변환');
      final staleAfterCad = project.staleNotices();
      expect(staleAfterCad, isNotEmpty);
      expect(staleAfterCad.any((n) => n.stale == SsDataSlot.isoData && n.changed == SsDataSlot.cadData), isTrue);
    });
  });

  group('FLOW B — 직접 그리기 (CAD FLOW와 연결되어 끝까지 간다)', () {
    test('directDrawing → CAD → ISO → finalResult까지 연결된다', () {
      var project = SsProject.create(
        id: 'p-b',
        name: '직접 그리기 프로젝트',
        sourceType: SsSourceType.directDraw,
      );
      expect(project.currentStage, SsStage.directDrawing);

      project = project.withSource({'walls': 4}, label: '직접 그리기');
      project = project.moveTo(SsStage.cadConversion);
      project = project.withStageData(SsDataSlot.cadData, {'walls': 4}, label: 'CAD 변환');
      project = project.moveTo(SsStage.cadEditor);
      project = project.moveTo(SsStage.isoConversion);
      project = project.withStageData(SsDataSlot.isoData, {'furniture': 2}, label: 'ISO 변환');
      project = project.moveTo(SsStage.isoEditor);
      project = project.moveTo(SsStage.elevationFaceEditor);
      project = project.moveTo(SsStage.isoRendering);
      project = project.withStageData(SsDataSlot.renderData, {'image': 'b.png'}, label: '렌더링');
      project = project.moveTo(SsStage.finalResult);

      expect(project.currentStage, SsStage.finalResult);
      expect(project.staleNotices(), isEmpty);
      // 직접 그리기 FLOW에는 recognitionData/userCorrections가 없다 — basedOn에는
      // 실제로 존재하는 sourceData만 기록된다(둘 다 없는 칸을 가짜로 채우지 않는다).
      expect(project[SsDataSlot.cadData]!.basedOn.containsKey(SsDataSlot.sourceData), isTrue);
      expect(project[SsDataSlot.cadData]!.basedOn.containsKey(SsDataSlot.userCorrections), isFalse);
    });

    test('화면 간 Navigation 일관성 — 다른 FLOW의 단계로는 이동할 수 없다', () {
      final project = SsProject.create(
        id: 'p-b2',
        name: '직접 그리기 프로젝트',
        sourceType: SsSourceType.directDraw,
      );
      // imageEditing은 이미지 변환 FLOW의 단계 — 직접 그리기 프로젝트는 갈 수 없다.
      expect(() => project.moveTo(SsStage.imageEditing), throwsArgumentError);
    });
  });

  group('FLOW C — 이미지 변환 (CAD/3D FLOW와 분리된 짧은 흐름도 끝까지 연결된다)', () {
    test('imageEditing → imageRendering → imageResult까지 연결된다', () {
      var project = SsProject.create(
        id: 'p-c',
        name: '이미지 변환 프로젝트',
        sourceType: SsSourceType.imageTransform,
      );
      expect(project.currentStage, SsStage.imageEditing);

      project = project.withSource({'photo': 'room.jpg'}, label: '실제 사진 업로드');
      project = project.moveTo(SsStage.imageRendering);
      project = project.withStageData(SsDataSlot.renderData, {'image': 'c.png'}, label: 'AI 렌더링');
      project = project.moveTo(SsStage.imageResult);

      expect(project.currentStage, SsStage.imageResult);
      expect(project.staleNotices(), isEmpty);
      expect(SsFlows.belongs(SsSourceType.imageTransform, SsStage.cadEditor), isFalse);
    });
  });

  group('자동저장 / 저장 실패 / 재시도 / 앱 종료 후 마지막 단계 복원', () {
    test('저장이 실패하면 상태가 failed로 바뀌고 메모리의 작업은 그대로 남으며, 재시도하면 복구된다', () async {
      final store = MemorySsProjectStore();
      final project = SsProject.create(
        id: 'p-save',
        name: '저장 검증 프로젝트',
        sourceType: SsSourceType.directDraw,
      ).withSource({'walls': 1}, label: '직접 그리기');

      final controller = SsAutosaveController(store: store, project: project);

      store.failNextSave = true;
      final firstOk = await controller.saveNow();
      expect(firstOk, isFalse);
      expect(controller.state, SsSaveState.failed);
      expect(controller.lastError, isNotNull);
      // 저장이 실패해도 메모리의 작업(project)은 잃지 않는다.
      expect(controller.project.info.id, 'p-save');

      final retryOk = await controller.retry();
      expect(retryOk, isTrue);
      expect(controller.state, SsSaveState.saved);
      expect(controller.lastError, isNull);
    });

    test('앱을 다시 연 것처럼 새 컨트롤러로 마지막 작업한 프로젝트를 이어서 연다', () async {
      final store = MemorySsProjectStore();
      var project = SsProject.create(
        id: 'p-restore',
        name: '복원 검증 프로젝트',
        sourceType: SsSourceType.floorPlanUpload,
      ).withSource({'fileName': 'plan.jpg'}, label: '평면도 업로드');
      project = project.moveTo(SsStage.floorPlanReview);

      final firstSession = SsAutosaveController(store: store, project: project);
      final saved = await firstSession.saveNow();
      expect(saved, isTrue);

      // "앱 종료" — 메모리상의 컨트롤러를 버리고, 저장소만 남는다.
      final restored = await SsAutosaveController.restoreLast(store);

      expect(restored, isNotNull);
      expect(restored!.project.info.id, 'p-restore');
      expect(restored.project.currentStage, SsStage.floorPlanReview);
      expect(restored.state, SsSaveState.saved);
    });
  });
}
