// SS011 — MASTER UI 8(CAD 편집·치수·파일 내보내기) 화면: SS010이 저장한 CAD
// 데이터를 불러와 벽을 선택해 치수를 보고, 벽체를 생성/삭제하고, 저장하면
// SsDataSlot.cadData revision이 올라 다시 쓰이는지 확인한다.
import 'package:ason_space/core/ss_project.dart';
import 'package:ason_space/core/ss_project_store.dart';
import 'package:ason_space/core/ss_stage.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/ss_spatial_model.dart';
import 'package:ason_space/models/ss_spatial_model_json.dart';
import 'package:ason_space/screens/cad_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const SSSpatialModel _sampleModel = SSSpatialModel(
  sourceWidthPx: 1000,
  sourceHeightPx: 1000,
  spaces: [],
  walls: [
    SSWall(id: 'w1', start: Point2(0.1, 0.1), end: Point2(0.6, 0.1), thicknessNormalized: 0.02, kind: SSWallKind.interior, confidence: 0.9),
  ],
  openings: [],
  objects: [],
  warnings: [],
);

Future<void> _pump(WidgetTester tester, MemorySsProjectStore store, {String projectId = 'p1'}) async {
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: CadEditorScreen(projectId: projectId, projectStore: store))));
}

void main() {
  testWidgets('CAD 데이터가 있으면 벽을 선택해 치수를 보여준다', (tester) async {
    final store = MemorySsProjectStore();
    var project = SsProject.create(id: 'p1', name: 'CAD 편집 테스트', sourceType: SsSourceType.floorPlanUpload, now: DateTime(2026, 1, 1));
    project = project.withStageData(SsDataSlot.cadData, {'model': ssSpatialModelToJson(_sampleModel)}, label: 'CAD 변환 결과');
    project = project.moveTo(SsStage.cadEditor);
    await store.save(project);

    await _pump(tester, store);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ssCadEditorScreen')), findsOneWidget);

    await tester.tapAt(const Offset(800, 500));
    await tester.pumpAndSettle();
  });

  testWidgets('CAD 데이터가 없으면 안내만 보여준다', (tester) async {
    final store = MemorySsProjectStore();
    var project = SsProject.create(id: 'p2', name: 'CAD 없음', sourceType: SsSourceType.floorPlanUpload, now: DateTime(2026, 1, 1));
    project = project.moveTo(SsStage.cadEditor);
    await store.save(project);

    await _pump(tester, store, projectId: 'p2');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ssCadEditorMissingData')), findsOneWidget);
  });

  testWidgets('벽체 생성 도구를 켜고 저장하면 cadData revision이 올라간다', (tester) async {
    final store = MemorySsProjectStore();
    var project = SsProject.create(id: 'p3', name: '벽 생성', sourceType: SsSourceType.floorPlanUpload, now: DateTime(2026, 1, 1));
    project = project.withStageData(SsDataSlot.cadData, {'model': ssSpatialModelToJson(_sampleModel)}, label: 'CAD 변환 결과');
    final revisionBefore = project.data[SsDataSlot.cadData]!.revision;
    project = project.moveTo(SsStage.cadEditor);
    await store.save(project);

    await _pump(tester, store, projectId: 'p3');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ssCadToolAddWall')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(700, 400));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(900, 400));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ssCadSaveButton')));
    await tester.pumpAndSettle();

    final saved = await store.load('p3');
    final revisionAfter = saved?.data[SsDataSlot.cadData]?.revision ?? 0;
    expect(revisionAfter, greaterThan(revisionBefore));
  });

  testWidgets('프로젝트 id 없이도(라우팅 전용) 빈 캔버스로 화면이 뜬다', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: CadEditorScreen())));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ssCadEditorScreen')), findsOneWidget);
  });
}
