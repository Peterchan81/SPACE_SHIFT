// SS015 — MASTER UI 11(3D 아이소 랜더링) 화면 위젯 테스트: 렌더링이 끝나면 결과를 저장하고 최종
// 결과 화면으로 넘어가는지, 입력 자체가 문제면 재시도 없이 이전 단계로 돌아가는 안내만 보이는지,
// 그 외 일반 오류는 다시 시도할 수 있는지, 완성된 ISO 디자인이 아예 없으면 안내만 보이는지, 이미
// 최신 렌더링 결과가 있으면 다시 렌더링하지 않는지, 3D 디자인이 바뀌어 낡으면 자동으로 다시
// 렌더링하면서 기존 Orbit 카메라 시점을 보존하는지 확인한다.
import 'package:ason_space/core/ss_iso_render_step.dart';
import 'package:ason_space/core/ss_project.dart';
import 'package:ason_space/core/ss_project_store.dart';
import 'package:ason_space/core/ss_stage.dart';
import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/iso_render_result.dart';
import 'package:ason_space/models/ss_cad_scene.dart';
import 'package:ason_space/models/ss_iso_camera_state.dart';
import 'package:ason_space/models/ss_iso_design_extras.dart';
import 'package:ason_space/screens/iso_rendering_screen.dart';
import 'package:ason_space/services/iso_render_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _scale = FloorPlanScale(
  mmPerPixel: 5.0,
  referenceStart: Point2(0, 0),
  referenceEnd: Point2(1, 0),
  referenceLengthMm: 5000,
  source: ScaleSource.measured,
);

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

Map<String, Object?> _cadPayload() => {'kind': 'ssCadScene', 'scene': SsCadScene(plan: _samplePlan(), scale: _scale).toJson()};

class _AlwaysInputErrorService extends IsoRenderService {
  const _AlwaysInputErrorService() : super(stepDelay: Duration.zero);

  @override
  Future<IsoRenderResult> render(
    SsCadScene cad, {
    SsIsoDesignExtras extras = SsIsoDesignExtras.empty,
    SsIsoCameraState? previousCamera,
    SsIsoRenderQuality quality = SsIsoRenderQuality.full,
    void Function(SsIsoRenderStep step)? onStep,
  }) async {
    onStep?.call(SsIsoRenderStep.imageQualityProcessing);
    throw const IsoRenderInputError('테스트: 렌더링할 3D ISO 디자인이 없습니다.');
  }
}

class _AlwaysFailService extends IsoRenderService {
  const _AlwaysFailService() : super(stepDelay: Duration.zero);

  @override
  Future<IsoRenderResult> render(
    SsCadScene cad, {
    SsIsoDesignExtras extras = SsIsoDesignExtras.empty,
    SsIsoCameraState? previousCamera,
    SsIsoRenderQuality quality = SsIsoRenderQuality.full,
    void Function(SsIsoRenderStep step)? onStep,
  }) async {
    onStep?.call(SsIsoRenderStep.imageQualityProcessing);
    throw Exception('3D ISO 렌더링 실패(시험)');
  }
}

void main() {
  late MemorySsProjectStore store;

  setUp(() async {
    store = MemorySsProjectStore();
    var project = SsProject.create(id: 'p1', name: '3D ISO 렌더링 테스트', sourceType: SsSourceType.floorPlanUpload, now: DateTime(2026, 1, 1));
    project = project.withStageData(SsDataSlot.cadData, _cadPayload(), label: 'CAD 편집');
    project = project.moveTo(SsStage.isoRendering);
    await store.save(project);
  });

  Future<void> pump(WidgetTester tester, {String projectId = 'p1', IsoRenderService renderService = const IsoRenderService(stepDelay: Duration.zero)}) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: IsoRenderingScreen(projectId: projectId, projectStore: store, renderService: renderService)),
        onGenerateRoute: (settings) {
          if (settings.name == SsStage.finalResult.routeName) {
            return MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('FINAL_RESULT', key: Key('ssFakeFinalResultScreen'))), settings: settings);
          }
          if (settings.name == SsStage.elevationFaceEditor.routeName) {
            return MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('ELEVATION_EDITOR', key: Key('ssFakeElevationEditorScreen'))), settings: settings);
          }
          return null;
        },
      ),
    );
  }

  testWidgets('렌더링이 끝나면 renderData를 저장하고 최종 결과 화면으로 넘어간다', (tester) async {
    await pump(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ssFakeFinalResultScreen')), findsOneWidget);

    final saved = await store.load('p1');
    expect(saved?.currentStage, SsStage.finalResult);
    final payload = saved?.data[SsDataSlot.renderData]?.payload;
    expect(payload, isNotNull);
    expect(payload!['kind'], 'ssIsoRender');
    expect(payload['camera'], isNotNull);
    expect(saved?.data[SsDataSlot.cadData], isNotNull, reason: 'CAD 데이터는 그대로 남는다');
  });

  testWidgets('입력 자체가 문제면 재시도 없이 이전 단계로 돌아가는 안내만 보여준다', (tester) async {
    await pump(tester, renderService: const _AlwaysInputErrorService());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ssIsoRenderBackFromFail')), findsOneWidget);
    final retryButton = tester.widget<ElevatedButton>(find.byKey(const Key('ssIsoRenderRetry')));
    expect(retryButton.onPressed, isNull);

    final saved = await store.load('p1');
    expect(saved?.data[SsDataSlot.renderData], isNull);
    expect(saved?.data[SsDataSlot.cadData], isNotNull);
  });

  testWidgets('일반 오류로 실패하면 다시 시도할 수 있고, CAD/ISO 데이터는 그대로 남는다', (tester) async {
    await pump(tester, renderService: const _AlwaysFailService());
    await tester.pumpAndSettle();

    final retryButton = tester.widget<ElevatedButton>(find.byKey(const Key('ssIsoRenderRetry')));
    expect(retryButton.onPressed, isNotNull);

    final saved = await store.load('p1');
    expect(saved?.data[SsDataSlot.renderData], isNull);
    expect(saved?.data[SsDataSlot.cadData], isNotNull);
  });

  testWidgets('완성된 3D ISO 디자인이 없으면 이전 단계로 돌아가라는 안내를 보여준다', (tester) async {
    var noInputProject = SsProject.create(id: 'p2', name: '입력 없음', sourceType: SsSourceType.floorPlanUpload, now: DateTime(2026, 1, 1));
    noInputProject = noInputProject.moveTo(SsStage.isoRendering);
    await store.save(noInputProject);

    await pump(tester, projectId: 'p2');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ssIsoRenderMissingInput')), findsOneWidget);
  });

  testWidgets('이미 최신 렌더링 결과가 있으면 다시 렌더링하지 않고, 계속하기를 누르면 바로 최종 결과로 이동한다', (tester) async {
    var project = SsProject.create(id: 'p4', name: '최신 렌더링', sourceType: SsSourceType.floorPlanUpload, now: DateTime(2026, 1, 1));
    project = project.withStageData(SsDataSlot.cadData, _cadPayload(), label: 'CAD 편집');
    project = project.withStageData(
      SsDataSlot.isoData,
      {
        'kind': 'ssIsoScene',
        'camera': const SsIsoCameraState(targetXMm: 1, targetYMm: 2, targetZMm: 3, distanceMm: 4000, azimuthRadians: 0.1, polarRadians: 0.2).toJson(),
        'warnings': <String>[],
      },
      label: '3D ISO 디자인 결과',
    );
    project = project.withStageData(
      SsDataSlot.renderData,
      {
        'kind': 'ssIsoRender',
        'camera': const SsIsoCameraState(targetXMm: 1, targetYMm: 2, targetZMm: 3, distanceMm: 4000, azimuthRadians: 0.1, polarRadians: 0.2).toJson(),
        'warnings': <String>[],
      },
      label: '3D ISO 렌더링 결과',
    );
    project = project.moveTo(SsStage.isoRendering);
    await store.save(project);

    await pump(tester, projectId: 'p4');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ssIsoRenderUpToDatePanel')), findsOneWidget);
    expect(find.byKey(const Key('ssIsoRenderStatusPanel')), findsNothing);

    await tester.tap(find.byKey(const Key('ssIsoRenderContinue')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ssFakeFinalResultScreen')), findsOneWidget);
    final saved = await store.load('p4');
    expect(saved?.currentStage, SsStage.finalResult);
    final camera = saved?.data[SsDataSlot.renderData]?.payload['camera'] as Map?;
    expect(camera?['distanceMm'], 4000, reason: '다시 렌더링하지 않았으므로 camera는 원래 값 그대로다');
  });

  testWidgets('3D 디자인이 바뀌어 렌더링 결과가 낡으면 자동으로 다시 렌더링하고, 기존 Orbit 카메라 시점은 보존한다', (tester) async {
    var project = SsProject.create(id: 'p5', name: '낡은 렌더링', sourceType: SsSourceType.floorPlanUpload, now: DateTime(2026, 1, 1));
    final cadPayload = _cadPayload();
    project = project.withStageData(SsDataSlot.cadData, cadPayload, label: 'CAD 편집');
    project = project.withStageData(
      SsDataSlot.isoData,
      {
        'kind': 'ssIsoScene',
        'camera': const SsIsoCameraState(targetXMm: 9, targetYMm: 8, targetZMm: 7, distanceMm: 6000, azimuthRadians: 0.3, polarRadians: 0.4).toJson(),
        'warnings': <String>[],
      },
      label: '3D ISO 디자인 결과',
    );
    project = project.withStageData(
      SsDataSlot.renderData,
      {'kind': 'ssIsoRender', 'camera': const SsIsoCameraState(targetXMm: 0, targetYMm: 0, targetZMm: 0, distanceMm: 1000, azimuthRadians: 0, polarRadians: 0).toJson(), 'warnings': <String>[]},
      label: '3D ISO 렌더링 결과',
    );
    project = project.withStageData(
      SsDataSlot.isoData,
      {
        'kind': 'ssIsoScene',
        'camera': const SsIsoCameraState(targetXMm: 9, targetYMm: 8, targetZMm: 7, distanceMm: 6000, azimuthRadians: 0.3, polarRadians: 0.4).toJson(),
        'warnings': <String>[],
      },
      label: '3D ISO 재디자인',
    );
    project = project.moveTo(SsStage.isoRendering);
    await store.save(project);

    await pump(tester, projectId: 'p5');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ssFakeFinalResultScreen')), findsOneWidget);
    final saved = await store.load('p5');
    final camera = saved?.data[SsDataSlot.renderData]?.payload['camera'] as Map?;
    expect(camera?['distanceMm'], 6000, reason: '재생성해도 사용자가 이미 돌려본 Orbit 시점을 잃지 않는다');
  });

  testWidgets('뒤로가기를 누르면 정면도·측면도 편집 화면으로 돌아간다(Map 인자로)', (tester) async {
    await pump(tester);
    await tester.pump();

    await tester.tap(find.byKey(const Key('ssIsoRenderBack')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ssFakeElevationEditorScreen')), findsOneWidget);
  });
}
