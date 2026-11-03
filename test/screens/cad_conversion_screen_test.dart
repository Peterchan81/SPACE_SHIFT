// SS010 — MASTER UI 7(평면도 CAD변환) 화면 위젯 테스트: 변환이 끝나면 결과를 저장하고 CAD 편집
// 화면으로 넘어가는지, 입력 자체가 문제면 재시도 없이 이전 단계로 돌아가는 안내만 보이는지, 그 외
// 일반 오류는 다시 시도할 수 있는지, 확정된 입력이 아예 없으면 안내만 보이는지 확인한다. 어느
// 경우에도 SS009가 저장한 확정 데이터(userCorrections)는 그대로 남는다.
import 'package:ason_space/core/ss_cad_conversion_step.dart';
import 'package:ason_space/core/ss_project.dart';
import 'package:ason_space/core/ss_project_store.dart';
import 'package:ason_space/core/ss_stage.dart';
import 'package:ason_space/models/cad_conversion_result.dart';
import 'package:ason_space/models/cad_floor_plan.dart' show FloorPlanScale;
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/ss_spatial_model.dart';
import 'package:ason_space/models/ss_spatial_model_json.dart';
import 'package:ason_space/screens/cad_conversion_screen.dart';
import 'package:ason_space/services/cad_conversion_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const SSSpatialModel _sampleModel = SSSpatialModel(
  sourceWidthPx: 800,
  sourceHeightPx: 600,
  spaces: [
    SSSpace(
      id: 's1',
      polygon: [Point2(0.1, 0.1), Point2(0.5, 0.1), Point2(0.5, 0.5), Point2(0.1, 0.5)],
      areaNormalized: 0.16,
      closed: true,
      confidence: 0.9,
    ),
  ],
  walls: [
    SSWall(id: 'w1', start: Point2(0.1, 0.1), end: Point2(0.5, 0.1), thicknessNormalized: 0.02, kind: SSWallKind.exterior, confidence: 0.9),
  ],
  openings: [],
  objects: [],
  warnings: [],
);

class _AlwaysInputErrorService extends CadConversionService {
  const _AlwaysInputErrorService() : super(stepDelay: Duration.zero);

  @override
  Future<CadConversionResult> convert(
    SSSpatialModel model, {
    FloorPlanScale? knownScale,
    void Function(SsCadConversionStep step)? onStep,
  }) async {
    onStep?.call(SsCadConversionStep.preprocessing);
    throw const CadConversionInputError('테스트: 변환할 벽/공간이 없습니다.');
  }
}

class _AlwaysFailService extends CadConversionService {
  const _AlwaysFailService() : super(stepDelay: Duration.zero);

  @override
  Future<CadConversionResult> convert(
    SSSpatialModel model, {
    FloorPlanScale? knownScale,
    void Function(SsCadConversionStep step)? onStep,
  }) async {
    onStep?.call(SsCadConversionStep.preprocessing);
    throw Exception('CAD 변환 실패(시험)');
  }
}

void main() {
  late MemorySsProjectStore store;

  setUp(() async {
    store = MemorySsProjectStore();
    var project = SsProject.create(id: 'p1', name: 'CAD 변환 테스트', sourceType: SsSourceType.floorPlanUpload, now: DateTime(2026, 1, 1));
    project = project.withSource({'imageBase64': 'x'}, label: '원본');
    project = project.withStageData(SsDataSlot.recognitionData, {'model': ssSpatialModelToJson(_sampleModel)}, label: 'AI 인식');
    project = project.withStageData(
      SsDataSlot.userCorrections,
      {'kind': 'ssSpatialModel', 'model': ssSpatialModelToJson(_sampleModel)},
      label: '평면도 최종 확정',
    );
    project = project.moveTo(SsStage.cadConversion);
    await store.save(project);
  });

  Future<void> pump(WidgetTester tester, {CadConversionService conversionService = const CadConversionService(stepDelay: Duration.zero)}) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CadConversionScreen(projectId: 'p1', projectStore: store, conversionService: conversionService)),
        onGenerateRoute: (settings) {
          if (settings.name == SsStage.cadEditor.routeName) {
            return MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('CAD_EDITOR', key: Key('ssFakeCadEditorScreen'))), settings: settings);
          }
          if (settings.name == SsStage.floorPlanReview.routeName) {
            return MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('REVIEW', key: Key('ssFakeReviewScreen'))), settings: settings);
          }
          return null;
        },
      ),
    );
  }

  testWidgets('변환이 끝나면 CAD 데이터를 저장하고 CAD 편집 화면으로 넘어간다', (tester) async {
    await pump(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ssFakeCadEditorScreen')), findsOneWidget);

    final saved = await store.load('p1');
    expect(saved?.currentStage, SsStage.cadEditor);
    final payload = saved?.data[SsDataSlot.cadData]?.payload;
    expect(payload, isNotNull);
    expect(payload!['dxfContent'], contains('SS-EXTERIOR-WALL'));
  });

  testWidgets('입력 자체가 문제면 재시도 없이 이전 단계로 돌아가는 안내만 보여준다', (tester) async {
    await pump(tester, conversionService: const _AlwaysInputErrorService());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ssCadConversionBackFromFail')), findsOneWidget);
    final retryButton = tester.widget<ElevatedButton>(find.byKey(const Key('ssCadConversionRetry')));
    expect(retryButton.onPressed, isNull);

    final saved = await store.load('p1');
    expect(saved?.data[SsDataSlot.cadData], isNull);
    expect(saved?.data[SsDataSlot.userCorrections], isNotNull);
  });

  testWidgets('일반 오류로 실패하면 다시 시도할 수 있고, 확정 데이터는 그대로 남는다', (tester) async {
    await pump(tester, conversionService: const _AlwaysFailService());
    await tester.pumpAndSettle();

    final retryButton = tester.widget<ElevatedButton>(find.byKey(const Key('ssCadConversionRetry')));
    expect(retryButton.onPressed, isNotNull);

    final saved = await store.load('p1');
    expect(saved?.data[SsDataSlot.cadData], isNull);
    expect(saved?.data[SsDataSlot.userCorrections], isNotNull);
  });

  testWidgets('확정된 입력이 없으면 이전 단계로 돌아가라는 안내를 보여준다', (tester) async {
    var noInputProject = SsProject.create(id: 'p2', name: '입력 없음', sourceType: SsSourceType.floorPlanUpload, now: DateTime(2026, 1, 1));
    noInputProject = noInputProject.moveTo(SsStage.cadConversion);
    await store.save(noInputProject);

    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: CadConversionScreen(projectId: 'p2', projectStore: store))),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ssCadConversionMissingInput')), findsOneWidget);
  });
}
