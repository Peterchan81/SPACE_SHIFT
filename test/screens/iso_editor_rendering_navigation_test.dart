// SS015 — IsoEditorScreen(SS013)에 추가된 "렌더링 시작" 이동 버튼을 확인한다. 화면의 기존 동작
// (iso_editor_screen_test.dart)은 건드리지 않는다 — 새 동작만 새 테스트 파일에서 검증한다
// (cad_editor_iso_navigation_test.dart와 같은 패턴, SS012). 버튼은 CAD 데이터가 있어야 보이는
// 리본(ssIsoRibbon) 안에 있으므로(CAD가 없으면 "먼저 CAD 편집을 완료해주세요" 안내만 보인다 —
// iso_editor_screen_test.dart "CAD 데이터가 없는 프로젝트..." 참고), 이 테스트도 cad_editor_iso_navigation_test.dart와 같이 cadData를 채워 둔다.
import 'package:ason_space/core/ss_project.dart';
import 'package:ason_space/core/ss_project_store.dart';
import 'package:ason_space/core/ss_stage.dart';
import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/ss_cad_scene.dart';
import 'package:ason_space/screens/iso_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CadWall _wall(String id, Point2 start, Point2 end) => CadWall(
  id: id,
  start: start,
  end: end,
  thicknessNormalized: 0.02,
  wallType: CadWallType.exterior,
  confidence: 0.9,
);

const _corners = [Point2(0.1, 0.1), Point2(0.9, 0.1), Point2(0.9, 0.9), Point2(0.1, 0.9)];

CadFloorPlan _samplePlan() => CadFloorPlan(
  sourceWidthPx: 1000,
  sourceHeightPx: 1000,
  walls: [
    _wall('n', const Point2(0.1, 0.1), const Point2(0.9, 0.1)),
    _wall('s', const Point2(0.1, 0.9), const Point2(0.9, 0.9)),
    _wall('w', const Point2(0.1, 0.1), const Point2(0.1, 0.9)),
    _wall('e', const Point2(0.9, 0.1), const Point2(0.9, 0.9)),
  ],
  openings: const [],
  rooms: const [CadRoom(id: 'room-0', polygon: _corners, areaNormalized: 0.64, confidence: 0.9)],
  warnings: const [],
);

Future<void> _pump(WidgetTester tester, MemorySsProjectStore store, {String projectId = 'p1'}) async {
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: IsoEditorScreen(projectId: projectId, projectStore: store)),
      onGenerateRoute: (settings) {
        if (settings.name == SsStage.isoRendering.routeName) {
          return MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('ISO_RENDERING', key: Key('ssFakeIsoRenderingScreen'))), settings: settings);
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
    project = project.withStageData(SsDataSlot.cadData, {'kind': 'ssCadScene', 'scene': SsCadScene(plan: _samplePlan()).toJson()}, label: 'CAD 편집');
    project = project.moveTo(SsStage.isoEditor);
    await store.save(project);

    // IsoEditorScreen은 CAD 데이터가 있으면 three_js 기반 Space3DViewGpuV2(매 프레임 다시 그리는
    // GPU 뷰)를 그리므로 pumpAndSettle()은 절대 settle되지 않는다 — 기존 iso_editor_screen_test.dart의
    // 모든 테스트와 같이 명시적인 pump()만 쓴다.
    await _pump(tester, store);
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('ssIsoGoToRenderButton')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('ssFakeIsoRenderingScreen')), findsOneWidget);
  });
}
