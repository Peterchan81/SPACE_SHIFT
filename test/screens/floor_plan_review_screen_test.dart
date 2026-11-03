// SS009 — MASTER UI 6(평면도 확인·보정) 위젯 테스트.
//
// 1. AI 인식 결과가 있으면 원본·인식 결과 패널이 함께 보이고, 신뢰도가 낮은
//    요소는 "확인이 필요한 요소" 배너에 남는다.
// 2. AI 인식 결과가 없는 프로젝트를 열면 먼저 평면도 업로드를 완료하라고 안내한다.
// 3. 벽을 선택해 삭제할 수 있다(잘못 인식된 구조요소 삭제).
// 4. 문을 선택해 창으로 바꿀 수 있다(객체 의미 수정).
// 5. "CAD 파일로 변환"은 확인 창을 거쳐야만 다음 단계(CAD 변환)로 이동한다.
import 'dart:convert';
import 'dart:typed_data';

import 'package:ason_space/core/ss_project.dart';
import 'package:ason_space/core/ss_project_store.dart';
import 'package:ason_space/core/ss_router.dart';
import 'package:ason_space/core/ss_stage.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/ss_spatial_model.dart';
import 'package:ason_space/models/ss_spatial_model_json.dart';
import 'package:ason_space/screens/floor_plan_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final Uint8List _fakeImageBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
  '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

const _fixedModel = SSSpatialModel(
  sourceWidthPx: 800,
  sourceHeightPx: 600,
  spaces: [
    SSSpace(id: 'space-1', polygon: [Point2(0.05, 0.05), Point2(0.95, 0.05), Point2(0.95, 0.95), Point2(0.05, 0.95)], areaNormalized: 0.8, closed: true, confidence: 0.9),
  ],
  walls: [
    SSWall(id: 'wall-1', start: Point2(0, 0), end: Point2(1, 0), thicknessNormalized: 0.02, kind: SSWallKind.exterior, confidence: 0.9),
    SSWall(id: 'wall-2', start: Point2(0, 0), end: Point2(0, 1), thicknessNormalized: 0.02, kind: SSWallKind.interior, confidence: 0.4),
  ],
  openings: [
    SSOpening(id: 'door-1', kind: SSOpeningKind.door, center: Point2(0.5, 0.0), widthNormalized: 0.05, confidence: 0.8),
    SSOpening(id: 'window-1', kind: SSOpeningKind.window, center: Point2(0.9, 0.5), widthNormalized: 0.05, confidence: 0.9),
  ],
  objects: [],
  warnings: [],
);

class _RecordingObserver extends NavigatorObserver {
  final List<String?> pushed = [];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushed.add(route.settings.name);
}

Future<SsProject> _seedProject(MemorySsProjectStore store, {SSSpatialModel? model}) async {
  var project = SsProject.create(id: 'p1', name: '테스트 프로젝트', sourceType: SsSourceType.floorPlanUpload, now: DateTime(2026, 1, 1))
      .withSource({'imageBase64': base64Encode(_fakeImageBytes), 'fileName': 'plan.png', 'extension': 'png'}, label: '원본 평면도');
  if (model != null) {
    project = project.withStageData(SsDataSlot.recognitionData, {'kind': 'ssSpatialModel', 'model': ssSpatialModelToJson(model)}, label: 'AI 공간 인식');
  }
  project = project.moveTo(SsStage.floorPlanReview);
  await store.save(project);
  return project;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpScreen(WidgetTester tester, {String? projectId, SsProjectStore? projectStore, NavigatorObserver? observer}) async {
    tester.view.physicalSize = const Size(1600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: observer == null ? const [] : [observer],
        onGenerateRoute: SsRouter.onGenerateRoute,
        home: FloorPlanReviewScreen(projectId: projectId, projectStore: projectStore),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('AI 인식 결과가 있으면 원본·인식 결과가 함께 보이고, 신뢰도 낮은 요소는 확인 배너에 남는다', (tester) async {
    final store = MemorySsProjectStore();
    await _seedProject(store, model: _fixedModel);
    await pumpScreen(tester, projectId: 'p1', projectStore: store);

    expect(find.byKey(const Key('ssReviewScreen')), findsOneWidget);
    expect(find.byKey(const Key('ssReviewSourceImage')), findsOneWidget);
    expect(find.byKey(const Key('ssReviewCanvas')), findsOneWidget);
    expect(find.byKey(const Key('ssReviewPendingBanner')), findsOneWidget);
  });

  testWidgets('AI 인식 결과가 없으면 먼저 평면도 업로드를 완료하라고 안내한다', (tester) async {
    final store = MemorySsProjectStore();
    await _seedProject(store);
    await pumpScreen(tester, projectId: 'p1', projectStore: store);
    expect(find.byKey(const Key('ssReviewMissingModel')), findsOneWidget);
  });

  testWidgets('벽을 선택해 삭제할 수 있다', (tester) async {
    final store = MemorySsProjectStore();
    await _seedProject(store, model: _fixedModel);
    await pumpScreen(tester, projectId: 'p1', projectStore: store);

    await tester.tap(find.byKey(const Key('ssReviewTool_select')));
    await tester.pumpAndSettle();

    final canvasFinder = find.byKey(const Key('ssReviewCanvas'));
    final topLeft = tester.getTopLeft(canvasFinder);
    final size = tester.getSize(canvasFinder);
    // wall-2: Point2(0,0)-(0,1) — 왼쪽 변 중앙 근처(x=0, y=0.5)를 누른다.
    final tapPoint = topLeft + Offset(size.width * 0.02, size.height * 0.5);
    await tester.tapAt(tapPoint);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ssReviewSelectionPanel')), findsOneWidget);
    await tester.tap(find.byKey(const Key('ssReviewDeleteSelected')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ssReviewSelectionPanel')), findsNothing);
  });

  testWidgets('문을 선택해 창으로 바꿀 수 있다(객체 의미 수정)', (tester) async {
    final store = MemorySsProjectStore();
    await _seedProject(store, model: _fixedModel);
    await pumpScreen(tester, projectId: 'p1', projectStore: store);

    await tester.tap(find.byKey(const Key('ssReviewTool_select')));
    await tester.pumpAndSettle();

    final canvasFinder = find.byKey(const Key('ssReviewCanvas'));
    final topLeft = tester.getTopLeft(canvasFinder);
    final size = tester.getSize(canvasFinder);
    // door-1: center (0.5, 0.0) — 캔버스 상단 중앙.
    final tapPoint = topLeft + Offset(size.width * 0.5, size.height * 0.02);
    await tester.tapAt(tapPoint);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ssReviewSelectionPanel')), findsOneWidget);
    expect(find.byKey(const Key('ssReviewConvertToWindow')), findsOneWidget);
    await tester.tap(find.byKey(const Key('ssReviewConvertToWindow')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ssReviewConvertToDoor')), findsOneWidget);
  });

  testWidgets('"CAD 파일로 변환"은 확인 창을 거쳐야만 다음 단계로 이동한다(취소하면 머무른다)', (tester) async {
    final store = MemorySsProjectStore();
    await _seedProject(store, model: _fixedModel);
    final observer = _RecordingObserver();
    await pumpScreen(tester, projectId: 'p1', projectStore: store, observer: observer);

    await tester.tap(find.byKey(const Key('ssReviewConvertButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ssReviewConvertDialog')), findsOneWidget);
    expect(observer.pushed, isNot(contains(SsStage.cadConversion.routeName)));

    await tester.tap(find.byKey(const Key('ssReviewConvertCancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ssReviewConvertDialog')), findsNothing);
    expect(observer.pushed, isNot(contains(SsStage.cadConversion.routeName)));

    await tester.tap(find.byKey(const Key('ssReviewConvertButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ssReviewConvertConfirm')));
    await tester.pumpAndSettle();
    expect(observer.pushed, contains(SsStage.cadConversion.routeName));
  });
}
