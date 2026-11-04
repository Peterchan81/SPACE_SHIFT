// SS014 — ElevationFaceEditorScreen(ISO에서 벽 하나를 선택해 정면도로 전환해 편집)의 핵심 동작을
// 확인한다. 3D GPU 위젯(Space3DViewGpuV2)과 달리 이 화면의 캔버스는 순수 CustomPaint라 위젯
// 테스트로 실제 편집→저장까지 검증할 수 있다.
import 'dart:math' as math;

import 'package:ason_space/core/ss_project.dart';
import 'package:ason_space/core/ss_project_store.dart';
import 'package:ason_space/core/ss_router.dart';
import 'package:ason_space/core/ss_stage.dart';
import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/ss_cad_scene.dart';
import 'package:ason_space/screens/elevation_face_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _wall = CadWall(
  id: 'w1',
  start: Point2(0.1, 0.5),
  end: Point2(0.9, 0.5),
  thicknessNormalized: 0.02,
  wallType: CadWallType.interior,
  confidence: 1,
);

const _scale = FloorPlanScale(mmPerPixel: 5, referenceStart: Point2(0, 0), referenceEnd: Point2(1, 0), referenceLengthMm: 5000, source: ScaleSource.measured);

const _plan = CadFloorPlan(sourceWidthPx: 1000, sourceHeightPx: 1000, walls: [_wall], openings: [], rooms: [], warnings: []);

Future<void> _pump(WidgetTester tester, MemorySsProjectStore store, {String projectId = 'p1', String? wallId = 'w1'}) async {
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: ElevationFaceEditorScreen(projectId: projectId, wallId: wallId, projectStore: store))));
}

void main() {
  testWidgets('선택한 벽의 정면도가 보이고, 문을 추가하면 같은 프로젝트 cadData/isoData에 저장된다', (tester) async {
    final store = MemorySsProjectStore();
    var project = SsProject.create(id: 'p1', name: '정면도 편집', sourceType: SsSourceType.floorPlanUpload, now: DateTime(2026, 1, 1));
    project = project.withStageData(SsDataSlot.cadData, {'kind': 'ssCadScene', 'scene': const SsCadScene(plan: _plan, scale: _scale).toJson()}, label: 'CAD');
    await store.save(project);

    await _pump(tester, store);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ssElevationFrontView')), findsOneWidget);

    await tester.tap(find.byKey(const Key('ssElevationAddDoor')));
    await tester.pump(const Duration(milliseconds: 900));

    final saved = await store.load('p1');
    final cadPayload = saved!.data[SsDataSlot.cadData]!.payload;
    final scene = SsCadScene.tryFromJson(cadPayload['scene'])!;
    expect(scene.plan.openings, hasLength(1));
    expect(scene.plan.openings.single.type, OpeningType.door);

    final isoPayload = saved.data[SsDataSlot.isoData]!.payload;
    expect(isoPayload['kind'], 'ssIsoScene');
  });

  testWidgets('정면도에서 문을 탭하면 선택되어 폭이 표시된다', (tester) async {
    final store = MemorySsProjectStore();
    var project = SsProject.create(id: 'p2', name: '정면도 편집', sourceType: SsSourceType.floorPlanUpload, now: DateTime(2026, 1, 1));
    final openedPlan = CadFloorPlan(
      sourceWidthPx: _plan.sourceWidthPx,
      sourceHeightPx: _plan.sourceHeightPx,
      walls: _plan.walls,
      openings: const [CadOpening(id: 'o1', type: OpeningType.door, center: Point2(0.5, 0.5), widthNormalized: 0.05, confidence: 1, wallId: 'w1')],
      rooms: const [],
      warnings: const [],
    );
    project = project.withStageData(SsDataSlot.cadData, {'kind': 'ssCadScene', 'scene': SsCadScene(plan: openedPlan, scale: _scale).toJson()}, label: 'CAD');
    await store.save(project);

    await _pump(tester, store, projectId: 'p2');
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byKey(const Key('ssElevationFrontView')));
    const lengthMm = 4000.0;
    const heightMm = 2400.0; // ceilingHeightMm 기본값(wall.heightMm 미지정)
    const margin = 36.0;
    final availableW = rect.width - margin * 2;
    final availableH = rect.height - margin * 2;
    final scale = math.min(availableW / lengthMm, availableH / heightMm);
    final wallWpx = lengthMm * scale;
    final wallHpx = heightMm * scale;
    final left = margin + (availableW - wallWpx) / 2;
    final top = margin + (availableH - wallHpx) / 2;
    final tapLocal = Offset(left + 2000 * scale, top + 1400 * scale);

    await tester.tapAt(rect.topLeft + tapLocal);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ssElevationOpeningWidth')), findsOneWidget);
  });

  testWidgets('벽이 없는 프로젝트는 안내만 보여준다', (tester) async {
    final store = MemorySsProjectStore();
    var project = SsProject.create(id: 'p3', name: '빈 CAD', sourceType: SsSourceType.floorPlanUpload, now: DateTime(2026, 1, 1));
    const emptyPlan = CadFloorPlan(sourceWidthPx: 1000, sourceHeightPx: 1000, walls: [], openings: [], rooms: [], warnings: []);
    project = project.withStageData(SsDataSlot.cadData, {'kind': 'ssCadScene', 'scene': const SsCadScene(plan: emptyPlan).toJson()}, label: 'CAD');
    await store.save(project);

    await _pump(tester, store, projectId: 'p3', wallId: null);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ssElevationMissingWall')), findsOneWidget);
  });

  testWidgets('SsRouter가 elevationFaceEditor 단계를 ElevationFaceEditorScreen으로 연결한다', (tester) async {
    tester.view.physicalSize = const Size(2000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        onGenerateRoute: SsRouter.onGenerateRoute,
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.of(context).pushNamed(SsStage.elevationFaceEditor.routeName, arguments: const {'projectId': null, 'wallId': null}),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ssElevationMissingWall')), findsOneWidget);
  });
}
