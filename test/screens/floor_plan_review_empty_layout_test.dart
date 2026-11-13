// SS-수정004 — 검토·수정 화면: 인식 결과 0개일 때 원본 위에 그릴 수 있는 상태·안내,
// 벽을 직접 추가하면 CAD 변환이 다시 켜짐, 1024·800·640 폭에서 도구줄이 넘치지 않음.
import 'dart:convert';
import 'dart:typed_data';

import 'package:ason_space/core/ss_project.dart';
import 'package:ason_space/core/ss_project_store.dart';
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

const _emptyModel = SSSpatialModel(sourceWidthPx: 800, sourceHeightPx: 600, spaces: [], walls: [], openings: [], objects: [], warnings: []);

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

Future<MemorySsProjectStore> _seed(SSSpatialModel model) async {
  final store = MemorySsProjectStore();
  var project = SsProject.create(id: 'p1', name: '테스트 프로젝트', sourceType: SsSourceType.floorPlanUpload, now: DateTime(2026, 1, 1))
      .withSource({'imageBase64': base64Encode(_fakeImageBytes), 'fileName': 'plan.png', 'extension': 'png'}, label: '원본 평면도');
  project = project.withStageData(SsDataSlot.recognitionData, {'kind': 'ssSpatialModel', 'model': ssSpatialModelToJson(model)}, label: 'AI 공간 인식');
  project = project.moveTo(SsStage.floorPlanReview);
  await store.save(project);
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 실제 앱의 본문 크기(창 − 좌측 메뉴 236 − 상단바 64)에 화면을 둔다.
  Future<void> pumpAt(WidgetTester tester, {required Size window, required Size body, required SsProjectStore store}) async {
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: body.width, height: body.height, child: FloorPlanReviewScreen(projectId: 'p1', projectStore: store)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('인식 결과 0개 — 원본 위 그리기 안내, CAD 비활성 이유, 벽을 추가하면 CAD 변환이 다시 켜진다', (tester) async {
    final store = await _seed(_emptyModel);
    await pumpAt(tester, window: const Size(1600, 1100), body: const Size(1600, 1100), store: store);

    expect(find.byKey(const Key('ssReviewMissingModel')), findsNothing);
    expect(find.byKey(const Key('ssReviewSourceUnderlay')), findsOneWidget);
    expect(find.byKey(const Key('ssReviewEmptyHint')), findsOneWidget);
    expect(find.byKey(const Key('ssReviewNeedsWallBanner')), findsOneWidget);
    expect(find.byKey(const Key('ssReviewAllClear')), findsNothing);
    expect(tester.widget<ElevatedButton>(find.byKey(const Key('ssReviewConvertButton'))).onPressed, isNull);
    expect(find.byKey(const Key('ssReviewConvertDisabledReason')), findsOneWidget);

    await tester.tap(find.byKey(const Key('ssReviewAddWallButton')));
    await tester.pumpAndSettle();

    final canvas = find.byKey(const Key('ssReviewCanvas'));
    final topLeft = tester.getTopLeft(canvas);
    final size = tester.getSize(canvas);
    await tester.tapAt(topLeft + Offset(size.width * 0.2, size.height * 0.3));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(topLeft + Offset(size.width * 0.8, size.height * 0.3));
    await tester.pumpAndSettle();

    expect(tester.widget<ElevatedButton>(find.byKey(const Key('ssReviewConvertButton'))).onPressed, isNotNull);
    expect(find.byKey(const Key('ssReviewConvertDisabledReason')), findsNothing);
    expect(find.byKey(const Key('ssReviewEmptyHint')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  const sizes = <(Size, Size)>[
    (Size(1024, 768), Size(788, 704)),
    (Size(800, 600), Size(564, 536)),
    (Size(640, 480), Size(404, 416)),
  ];

  for (final model in const [_fixedModel, _emptyModel]) {
    final label = identical(model, _emptyModel) ? '0개 결과' : '정상 결과';
    for (final (window, body) in sizes) {
      testWidgets('검토 화면 ${window.width.toInt()}×${window.height.toInt()} ($label) — 도구줄이 넘치거나 잘리지 않는다', (tester) async {
        final store = await _seed(model);
        await pumpAt(tester, window: window, body: body, store: store);

        expect(tester.takeException(), isNull);
        for (final key in [
          'ssReviewTool_pen',
          'ssReviewTool_highlighter',
          'ssReviewTool_eraser',
          'ssReviewTool_select',
          'ssReviewStrokeWidthSlider',
          'ssReviewUndo',
          'ssReviewRedo',
          'ssReviewAddWallButton',
          'ssReviewAddDoorButton',
          'ssReviewAddWindowButton',
          'ssReviewEditToggle',
          'ssReviewConvertButton',
        ]) {
          final finder = find.byKey(Key(key));
          expect(finder, findsOneWidget, reason: key);
          expect(tester.getRect(finder).right, lessThanOrEqualTo(body.width + 0.5), reason: key);
        }

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      });
    }
  }
}
