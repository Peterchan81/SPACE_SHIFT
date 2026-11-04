// SS015 — IsoEditorScreen(SS013)에 추가된 "렌더링 시작" 이동 버튼을 확인한다. 화면의 기존 동작
// (iso_editor_screen_test.dart)은 건드리지 않는다 — 새 동작만 새 테스트 파일에서 검증한다
// (cad_editor_iso_navigation_test.dart와 같은 패턴, SS012).
import 'package:ason_space/core/ss_project.dart';
import 'package:ason_space/core/ss_project_store.dart';
import 'package:ason_space/core/ss_stage.dart';
import 'package:ason_space/screens/iso_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
    project = project.moveTo(SsStage.isoEditor);
    await store.save(project);

    await _pump(tester, store);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ssIsoGoToRenderButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ssFakeIsoRenderingScreen')), findsOneWidget);
  });
}
