// SS-수정004 — 평면도 업로드 뒤 인식 결과가 비었을 때의 안내·다시 인식·직접 수정하기,
// 비활성 CAD 변환 이유 문구 위젯 테스트.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ason_space/core/ss_project.dart';
import 'package:ason_space/core/ss_project_store.dart';
import 'package:ason_space/core/ss_stage.dart';
import 'package:ason_space/models/floor_plan_file.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/ss_spatial_model.dart';
import 'package:ason_space/models/ss_spatial_model_json.dart';
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

const _roomWarning = '공간이 완전히 닫히지 않았습니다. 벽을 직접 보정해주세요.';

const _resultWithWarning = FloorPlanAnalysisResult(
  sourceWidthPx: 800,
  sourceHeightPx: 600,
  walls: [],
  openings: [],
  rooms: [],
  warnings: [_roomWarning],
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

const _resultClean = FloorPlanAnalysisResult(
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

const _emptyModel = SSSpatialModel(sourceWidthPx: 800, sourceHeightPx: 600, spaces: [], walls: [], openings: [], objects: [], warnings: []);

const _goodModel = SSSpatialModel(
  sourceWidthPx: 800,
  sourceHeightPx: 600,
  spaces: [
    SSSpace(id: 'space-1', polygon: [Point2(0.05, 0.05), Point2(0.95, 0.05), Point2(0.95, 0.95), Point2(0.05, 0.95)], areaNormalized: 0.8, closed: true, confidence: 0.9),
  ],
  walls: [
    SSWall(id: 'wall-1', start: Point2(0, 0), end: Point2(1, 0), thicknessNormalized: 0.02, kind: SSWallKind.exterior, confidence: 0.9),
    SSWall(id: 'wall-2', start: Point2(0, 0), end: Point2(0, 1), thicknessNormalized: 0.02, kind: SSWallKind.interior, confidence: 0.9),
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

class _CountingAnalysisService extends FloorPlanAnalysisService {
  _CountingAnalysisService(this._outcome);
  final FloorPlanAnalysisOutcome _outcome;
  int calls = 0;
  Completer<void>? gate;

  @override
  Future<FloorPlanAnalysisOutcome> analyze(FloorPlanFile file, {void Function(FloorPlanAnalysisStep step)? onStep}) async {
    calls++;
    final g = gate;
    if (g != null) await g.future;
    return _outcome;
  }
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
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => Scaffold(body: Text('next ${settings.name}', key: const Key('fakeNextRoute'))),
        ),
        home: FloorPlanUploadScreen(
          projectId: projectId,
          projectStore: projectStore,
          uploadService: _FakeUploadService([_fakeImageFile()]),
          analysisService: analysisService,
          spatialModelBuilder: spatialModelBuilder,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ssUploadPickButton')));
    await tester.pumpAndSettle();
  }

  testWidgets('인식 요소가 0개면 안내 상자·서비스 경고·흐린 원본·비활성 CAD 이유가 보인다', (tester) async {
    await pumpScreen(
      tester,
      analysisService: _CountingAnalysisService(const FloorPlanAnalysisOutcome.success(_resultWithWarning)),
      spatialModelBuilder: const _FixedModelBuilder(_emptyModel),
    );

    expect(find.byKey(const Key('ssRecognitionShortfallNotice')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('ssShortfallHeadline'))).data, contains('방을 찾지 못했습니다'));
    expect(tester.widget<Text>(find.byKey(const Key('ssShortfallReason'))).data, contains('기본 인식 엔진'));
    expect(find.textContaining('공간이 완전히 닫히지 않았습니다'), findsOneWidget);
    expect(find.byKey(const Key('ssRecognitionNoElementsOverlay')), findsOneWidget);
    expect(find.byKey(const Key('ssRecognitionSourceFaded')), findsOneWidget);
    expect(find.byKey(const Key('ssRecognitionNoElementsText')), findsOneWidget);
    expect(find.byKey(const Key('ssAnalysisError')), findsNothing);

    final convert = tester.widget<ElevatedButton>(find.byKey(const Key('ssUploadConvertButton')));
    expect(convert.onPressed, isNull);
    expect(find.byKey(const Key('ssUploadConvertDisabledReason')), findsOneWidget);

    final edit = tester.widget<OutlinedButton>(find.byKey(const Key('ssUploadEditButton')));
    expect(edit.onPressed, isNotNull);
  });

  testWidgets('충분히 인식된 정상 경로에서는 안내 상자가 없고 CAD 변환이 켜져 있다', (tester) async {
    await pumpScreen(
      tester,
      analysisService: _CountingAnalysisService(const FloorPlanAnalysisOutcome.success(_resultClean)),
      spatialModelBuilder: const _FixedModelBuilder(_goodModel),
    );

    expect(find.byKey(const Key('ssRecognitionShortfallNotice')), findsNothing);
    expect(find.byKey(const Key('ssRecognitionNoElementsOverlay')), findsNothing);
    final convert = tester.widget<ElevatedButton>(find.byKey(const Key('ssUploadConvertButton')));
    expect(convert.onPressed, isNotNull);
    expect(find.byKey(const Key('ssUploadConvertDisabledReason')), findsNothing);
  });

  testWidgets('"다시 인식"은 같은 파일로 한 번 더 분석하고, 실행 중 중복 누름은 무시한다', (tester) async {
    final service = _CountingAnalysisService(const FloorPlanAnalysisOutcome.success(_resultWithWarning));
    await pumpScreen(tester, analysisService: service, spatialModelBuilder: const _FixedModelBuilder(_emptyModel));
    expect(service.calls, 1);

    final gate = Completer<void>();
    service.gate = gate;
    final retry = find.byKey(const Key('ssShortfallRetry'));
    await tester.tap(retry);
    await tester.tap(retry, warnIfMissed: false);
    expect(service.calls, 2);

    await tester.pump();
    expect(find.byKey(const Key('ssAnalyzingIndicator')), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();

    expect(service.calls, 2);
    expect(find.byKey(const Key('ssRecognitionShortfallNotice')), findsOneWidget);
  });

  testWidgets('구조를 찾지 못한 인식 실패도 업로드 오류가 아니라 안내로 보이고, "직접 수정하기"로 빈 모델과 함께 검토 화면에 간다', (tester) async {
    final store = MemorySsProjectStore();
    final project = SsProject.create(id: 'p1', name: '테스트 프로젝트', sourceType: SsSourceType.floorPlanUpload, now: DateTime(2026, 1, 1));
    await store.save(project);
    final observer = _RecordingObserver();

    await pumpScreen(
      tester,
      projectId: 'p1',
      projectStore: store,
      observer: observer,
      analysisService: _CountingAnalysisService(
        const FloorPlanAnalysisOutcome.failure(FloorPlanAnalysisFailureReason.noWallsFound, '평면도 구조를 충분히 인식하지 못했습니다.'),
      ),
    );

    expect(find.byKey(const Key('ssAnalysisError')), findsNothing);
    expect(find.byKey(const Key('ssRecognitionShortfallNotice')), findsOneWidget);
    expect(find.byKey(const Key('ssRecognitionNoElementsOverlay')), findsOneWidget);
    expect(tester.widget<ElevatedButton>(find.byKey(const Key('ssUploadConvertButton'))).onPressed, isNull);
    expect(find.byKey(const Key('ssUploadConvertDisabledReason')), findsOneWidget);

    await tester.tap(find.byKey(const Key('ssShortfallDirectEdit')));
    await tester.pumpAndSettle();

    expect(observer.pushed, contains(SsStage.floorPlanReview.routeName));
    final saved = await store.load('p1');
    final slot = saved!.data[SsDataSlot.recognitionData];
    expect(slot, isNotNull);
    final model = ssSpatialModelFromJson(slot!.payload['model']);
    expect(model, isNotNull);
    expect(model!.walls, isEmpty);
    expect(model.spaces, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('업로드 실패(파일 읽기 실패)는 지금처럼 오류 상자로 보인다', (tester) async {
    await pumpScreen(
      tester,
      analysisService: _CountingAnalysisService(
        const FloorPlanAnalysisOutcome.failure(FloorPlanAnalysisFailureReason.unreadableImage, '이미지를 읽지 못했습니다. 다른 파일로 다시 시도해주세요.'),
      ),
    );
    expect(find.byKey(const Key('ssAnalysisError')), findsOneWidget);
    expect(find.byKey(const Key('ssRecognitionShortfallNotice')), findsNothing);
  });
}
