// SS012 — CadEditorScreen(SS011)에 추가된 "3D ISO 변환하기" 이동 버튼과, CAD가 바뀌어 3D 모델이
// 낡았을 때의 "3D 모델 업데이트 필요" 안내 배지를 확인한다. 화면의 기존 동작(cad_editor_screen_test.dart)
// 은 건드리지 않는다 — 새 동작만 새 테스트 파일에서 검증한다.
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
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: CadEditorScreen(projectId: projectId, projectStore: store)),
      onGenerateRoute: (settings) {
        if (settings.name == SsStage.isoConversion.routeName) {
          return MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('ISO_CONVERSION', key: Key('ssFakeIsoConversionScreen'))), settings: settings);
        }
        return null;
      },
    ),
  );
}

void main() {
  testWidgets('3D ISO 변환하기 버튼을 누르면 3D ISO 변환 화면으로 이동한다', (tester) async {
    final store = MemorySsProjectStore();
    var project = SsProject.create(id: 'p1', name: 'CAD 편집', sourceType: SsSourceType.floorPlanUpload, now: DateTime(2026, 1, 1));
    project = project.withStageData(SsDataSlot.cadData, {'model': ssSpatialModelToJson(_sampleModel)}, label: 'CAD 변환 결과');
    project = project.moveTo(SsStage.cadEditor);
    await store.save(project);

    await _pump(tester, store);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ssCadGoToIsoButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ssFakeIsoConversionScreen')), findsOneWidget);
  });

  testWidgets('3D 모델이 CAD보다 낡으면 업데이트 필요 안내를 보여준다', (tester) async {
    final store = MemorySsProjectStore();
    var project = SsProject.create(id: 'p2', name: 'CAD 재편집', sourceType: SsSourceType.floorPlanUpload, now: DateTime(2026, 1, 1));
    final cadPayload = {'model': ssSpatialModelToJson(_sampleModel)};
    project = project.withStageData(SsDataSlot.cadData, cadPayload, label: 'CAD 변환 결과');
    project = project.withStageData(SsDataSlot.isoData, {'kind': 'ssIsoScene'}, label: '3D ISO 변환 결과');
    project = project.withStageData(SsDataSlot.cadData, cadPayload, label: 'CAD 재편집');
    project = project.moveTo(SsStage.cadEditor);
    await store.save(project);

    await _pump(tester, store, projectId: 'p2');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ssCadIsoStaleNotice')), findsOneWidget);
  });
}
