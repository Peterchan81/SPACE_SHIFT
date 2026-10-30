// SS008 — MASTER UI 5(평면도 업로드·AI 공간 인식) 위젯 테스트.
//
// 1. 초기 상태 — 업로드 안내·선택 버튼이 보이고, "수정하기"는 비활성.
// 2. 이미지를 올리면(가짜 업로드/분석 서비스) 좌측에 미리보기, 우측에 레이어별
//    개수·오버레이가 표시되고, 신뢰도가 낮은 요소만 "확인이 필요한 요소"에 나온다.
// 3. 레이어 체크박스로 표시를 끄고 켤 수 있다.
// 4. "수정하기"는 곧바로 평면도 확인·보정 단계(SS009)로 이동한다.
// 5. "CAD 파일로 변환"은 확인 창을 거쳐야만 다음 단계로 이동한다(취소하면 그대로 머무른다).
// 6. 프로젝트와 함께 열었을 때, 분석 결과를 AI 인식 데이터 칸에 구조화된 공간모델로 저장한다.
import 'dart:convert';
import 'dart:typed_data';

import 'package:ason_space/core/ss_project.dart';
import 'package:ason_space/core/ss_project_store.dart';
import 'package:ason_space/core/ss_router.dart';
import 'package:ason_space/core/ss_stage.dart';
import 'package:ason_space/models/floor_plan_file.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/ss_spatial_model.dart';
import 'package:ason_space/screens/floor_plan_upload_screen.dart';
import 'package:ason_space/services/floor_plan_analysis_service.dart';
import 'package:ason_space/services/floor_plan_upload_service.dart';
import 'package:ason_space/services/ss_spatial_model_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final Uint8List _fakeImageBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
  '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

FloorPlanFile _fakeImageFile() => FloorPlanFile(
  fileName: 'plan.png',
  extension: 'png',
  kind: FloorPlanFileKind.image,
  sizeBytes: _fakeImageBytes.length,
  bytes: _fakeImageBytes,
);

const _fakeAnalysisResult = FloorPlanAnalysisResult(
  sourceWidthPx: 800,
  sourceHeightPx: 600,
  walls: [],
  openings: [],
  rooms: [],
  warnings: [],
  debugStats: FloorPlanAnalysisDebugStats(
    sourceWidthPx: 800,
    sourceHeightPx: 600,
    analysisWidthPx: 800,
    analysisHeightPx: 600,
    rawHorizontalRuns: 0,
    rawVerticalRuns: 0,
    mergedWallCount: 0,
    roomCandidateCount: 0,
    openingCandidateCount: 0,
    durationMs: 1,
  ),
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

class _FakeUploadService extends FloorPlanUploadService {
  _FakeUploadService(this._results);
  final List<FloorPlanFile?> _results;
  int _i = 0;

  @override
  Future<FloorPlanFile?> pickFloorPlanFile() async {
    final r = _i < _results.length ? _results[_i] : null;
    _i++;
    return r;
  }
}

class _FakeAnalysisService extends FloorPlanAnalysisService {
  const _FakeAnalysisService(this._outcome);
  final FloorPlanAnalysisOutcome _outcome;

  @override
  Future<FloorPlanAnalysisOutcome> analyze(FloorPlanFile file, {void Function(FloorPlanAnalysisStep step)? onStep}) async => _outcome;
}

class _FixedModelBuilder extends SSSpatialModelBuilder {
  const _FixedModelBuilder(this._model);
  final SSSpatialModel _model;

  @override
  SSSpatialModel build(FloorPlanAnalysisResult result) => _model;
}

class _RecordingObserver extends NavigatorObserver {
  final List<String?> pushed = [];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushed.add(route.settings.name);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpScreen(
    WidgetTester tester, {
    String? projectId,
    SsProjectStore? projectStore,
    required FloorPlanUploadService uploadService,
    required FloorPlanAnalysisService analysisService,
    SSSpatialModelBuilder spatialModelBuilder = const SSSpatialModelBuilder(),
    NavigatorObserver? observer,
  }) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: observer == null ? const [] : [observer],
        onGenerateRoute: SsRouter.onGenerateRoute,
        home: FloorPlanUploadScreen(
          projectId: projectId,
          projectStore: projectStore,
          uploadService: uploadService,
          analysisService: analysisService,
          spatialModelBuilder: spatialModelBuilder,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('초기 상태 — 업로드 안내가 보이고 "수정하기"는 비활성', (tester) async {
    await pumpScreen(tester, uploadService: _FakeUploadService([null]), analysisService: const FloorPlanAnalysisService());
    expect(find.byKey(const Key('ssUploadEmptyState')), findsOneWidget);
    expect(find.byKey(const Key('ssRecognitionEmptyState')), findsOneWidget);
    expect(find.byKey(const Key('ssUploadPickButton')), findsOneWidget);
    final editButton = tester.widget<OutlinedButton>(find.byKey(const Key('ssUploadEditButton')));
    expect(editButton.onPressed, isNull);
  });

  testWidgets('이미지를 업로드하면 AI 인식 결과가 표시되고 신뢰도 낮은 요소만 확인 목록에 나온다', (tester) async {
    await pumpScreen(
      tester,
      uploadService: _FakeUploadService([_fakeImageFile()]),
      analysisService: const _FakeAnalysisService(FloorPlanAnalysisOutcome.success(_fakeAnalysisResult)),
      spatialModelBuilder: const _FixedModelBuilder(_fixedModel),
    );
    await tester.tap(find.byKey(const Key('ssUploadPickButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ssUploadedImage')), findsOneWidget);
    expect(find.text('인식된 요소 (총 5개)'), findsOneWidget);
    expect(find.byKey(const Key('ssReviewBanner')), findsOneWidget);
    expect(find.byKey(const Key('ssReviewItem_wall-2')), findsOneWidget);
    expect(find.byKey(const Key('ssReviewItem_space-1')), findsNothing);

    final convertButton = tester.widget<ElevatedButton>(find.byKey(const Key('ssUploadConvertButton')));
    expect(convertButton.onPressed, isNotNull);
    final editButton = tester.widget<OutlinedButton>(find.byKey(const Key('ssUploadEditButton')));
    expect(editButton.onPressed, isNotNull);
  });

  testWidgets('레이어 체크박스로 표시 여부를 끄고 켤 수 있다', (tester) async {
    await pumpScreen(
      tester,
      uploadService: _FakeUploadService([_fakeImageFile()]),
      analysisService: const _FakeAnalysisService(FloorPlanAnalysisOutcome.success(_fakeAnalysisResult)),
      spatialModelBuilder: const _FixedModelBuilder(_fixedModel),
    );
    await tester.tap(find.byKey(const Key('ssUploadPickButton')));
    await tester.pumpAndSettle();

    final checkbox = find.byKey(const Key('ssLayerCheckbox_wall'));
    expect(tester.widget<Checkbox>(checkbox).value, isTrue);
    await tester.tap(checkbox);
    await tester.pump();
    expect(tester.widget<Checkbox>(checkbox).value, isFalse);
  });

  testWidgets('"수정하기"를 누르면 평면도 확인·보정 단계(SS009)로 이동한다', (tester) async {
    final observer = _RecordingObserver();
    await pumpScreen(
      tester,
      uploadService: _FakeUploadService([_fakeImageFile()]),
      analysisService: const _FakeAnalysisService(FloorPlanAnalysisOutcome.success(_fakeAnalysisResult)),
      spatialModelBuilder: const _FixedModelBuilder(_fixedModel),
      observer: observer,
    );
    await tester.tap(find.byKey(const Key('ssUploadPickButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ssUploadEditButton')));
    await tester.pump();
    expect(observer.pushed, contains(SsStage.floorPlanReview.routeName));
  });

  testWidgets('"CAD 파일로 변환"은 확인 창을 거친 뒤에만 다음 단계로 이동한다(취소하면 머무른다)', (tester) async {
    final observer = _RecordingObserver();
    await pumpScreen(
      tester,
      uploadService: _FakeUploadService([_fakeImageFile()]),
      analysisService: const _FakeAnalysisService(FloorPlanAnalysisOutcome.success(_fakeAnalysisResult)),
      spatialModelBuilder: const _FixedModelBuilder(_fixedModel),
      observer: observer,
    );
    await tester.tap(find.byKey(const Key('ssUploadPickButton')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ssUploadConvertButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ssConvertConfirmDialog')), findsOneWidget);
    expect(observer.pushed, isNot(contains(SsStage.floorPlanReview.routeName)));

    await tester.tap(find.byKey(const Key('ssConvertCancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ssConvertConfirmDialog')), findsNothing);
    expect(observer.pushed, isNot(contains(SsStage.floorPlanReview.routeName)));

    await tester.tap(find.byKey(const Key('ssUploadConvertButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ssConvertConfirm')));
    await tester.pump();
    expect(observer.pushed, contains(SsStage.floorPlanReview.routeName));
  });

  testWidgets('분석 결과를 프로젝트의 AI 인식 데이터 칸에 구조화된 공간모델로 저장한다', (tester) async {
    final store = MemorySsProjectStore();
    final project = SsProject.create(id: 'p1', name: '테스트 프로젝트', sourceType: SsSourceType.floorPlanUpload, now: DateTime(2026, 1, 1));
    await store.save(project);

    await pumpScreen(
      tester,
      projectId: 'p1',
      projectStore: store,
      uploadService: _FakeUploadService([_fakeImageFile()]),
      analysisService: const _FakeAnalysisService(FloorPlanAnalysisOutcome.success(_fakeAnalysisResult)),
      spatialModelBuilder: const _FixedModelBuilder(_fixedModel),
    );
    await tester.tap(find.byKey(const Key('ssUploadPickButton')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 900));

    final saved = await store.load('p1');
    expect(saved, isNotNull);
    expect(saved!.data[SsDataSlot.sourceData], isNotNull);
    expect(saved.data[SsDataSlot.recognitionData], isNotNull);
    expect(saved.data[SsDataSlot.recognitionData]!.payload['kind'], 'ssSpatialModel');
  });
}
