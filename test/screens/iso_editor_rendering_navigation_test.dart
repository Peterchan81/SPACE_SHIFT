// SS015 — IsoEditorScreen(SS013)에 추가된 "렌더링 시작" 이동 버튼을 확인한다. 화면의 기존 동작
// (iso_editor_screen_test.dart)은 건드리지 않는다 — 새 동작만 새 테스트 파일에서 검증한다
// (cad_editor_iso_navigation_test.dart와 같은 패턴, SS012). 버튼은 CAD 데이터가 있어야 보이는
// 리본(ssIsoRibbon) 안에 있으므로 cadData는 채워 두되, 위젯 테스트에서 geometry가 있는 GPU 3D 뷰
// (Space3DViewGpuV2, three_js 네이티브 ANGLE)를 띄우지 않도록(iso_editor_screen_test.dart 머리말의
// 규칙) 벽·개구부·공간·경고가 모두 빈 CAD 평면도를 쓴다 — 화면에는 빈 장면 안내만 보인다.
import 'package:ason_space/core/ss_project.dart';
import 'package:ason_space/core/ss_project_store.dart';
import 'package:ason_space/core/ss_stage.dart';
import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/models/ss_cad_scene.dart';
import 'package:ason_space/screens/iso_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _emptyPlan = CadFloorPlan(sourceWidthPx: 1000, sourceHeightPx: 1000, walls: [], openings: [], rooms: [], warnings: []);

Future<void> _pump(WidgetTester tester, MemorySsProjectStore store, {String projectId = 'p1'}) async {
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: IsoEditorScreen(projectId: projectId, projectStore: store)),
      onGenerateRoute: (settings) {
        if (settings.name == SsStage.isoRendering.routeName) {
          return MaterialPageRoute<void>(
            builder: (_) => Scaffold(body: Text('ISO_RENDERING ${settings.arguments}', key: const Key('ssFakeIsoRenderingScreen'))),
            settings: settings,
          );
        }
        return null;
      },
    ),
  );
}

void main() {
  testWidgets('렌더링 시작 버튼을 누르면 3D ISO 렌더링 화면으로 이동한다', (tester) async {
    final store = MemorySsProjectStore();
    var project = SsProject.create(id: 'p1', name: 'ISO 디자인', sourceType: SsSourceType.floorPlanUpload, now: DateTime(2026, 1, 1));
    project = project.withStageData(SsDataSlot.cadData, {'kind': 'ssCadScene', 'scene': const SsCadScene(plan: _emptyPlan).toJson()}, label: 'CAD 편집');
    project = project.moveTo(SsStage.isoEditor);
    await store.save(project);

    // geometry가 없으므로 GPU 3D 뷰가 마운트되지 않는다 — pumpAndSettle()을 쓸 수 있다.
    await _pump(tester, store);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ssIsoEditorEmptyScene')), findsOneWidget);
    expect(find.byKey(const Key('ssIsoGoToRenderButton')), findsOneWidget);

    await tester.tap(find.byKey(const Key('ssIsoGoToRenderButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ssFakeIsoRenderingScreen')), findsOneWidget);
    expect(find.text('ISO_RENDERING p1'), findsOneWidget);
  });
}
