// SS012 — MASTER UI 9(3D ISO 변환) 화면 위젯 테스트: 변환이 끝나면 결과를 저장하고 3D 디자인
// 화면으로 넘어가는지, 입력 자체가 문제면 재시도 없이 이전 단계로 돌아가는 안내만 보이는지, 그 외
// 일반 오류는 다시 시도할 수 있는지, 확정된 CAD 입력이 아예 없으면 안내만 보이는지, 이미 최신 3D
// 모델이 있으면 다시 변환하지 않는지, CAD가 바뀌어 낡으면 자동으로 다시 변환하면서 기존 Orbit 카메라
// 시점을 보존하는지 확인한다.
import 'package:ason_space/core/ss_iso_conversion_step.dart';
import 'package:ason_space/core/ss_project.dart';
import 'package:ason_space/core/ss_project_store.dart';
import 'package:ason_space/core/ss_stage.dart';
import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/iso_conversion_result.dart';
import 'package:ason_space/models/ss_cad_scene.dart';
import 'package:ason_space/models/ss_iso_camera_state.dart';
import 'package:ason_space/screens/iso_conversion_screen.dart';
import 'package:ason_space/services/iso_conversion_service.dart';
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

class _AlwaysInputErrorService extends IsoConversionService {
  const _AlwaysInputErrorService() : super(stepDelay: Duration.zero);

  @override
  Future<IsoConversionResult> convert(
    SsCadScene cadScene, {
    SsIsoCameraState? previousCamera,
    void Function(SsIsoConversionStep step)? onStep,
  }) async {
    onStep?.call(SsIsoConversionStep.preprocessing);
    throw const IsoConversionInputError('테스트: 3D로 변환할 CAD 데이터가 없습니다.');
  }
}

class _AlwaysFailService extends IsoConversionService {
  const _AlwaysFailService() : super(stepDelay: Duration.zero);

  @override
  Future<IsoConversionResult> convert(
    SsCadScene cadScene, {
    SsIsoCameraState? previousCamera,
    void Function(SsIsoConversionStep step)? onStep,
  }) async {
    onStep?.call(SsIsoConversionStep.preprocessing);
    throw Exception('3D ISO 변환 실패(시험)');
  }
}

void main() {
  late MemorySsProjectStore store;

  setUp(() async {
    store = MemorySsProjectStore();
    var project = SsProject.create(id: 'p1', name: '3D ISO 변환 테스트', sourceType: SsSourceType.floorPlanUpload, now: DateTime(2026, 1, 1));
    project = project.withStageData(SsDataSlot.cadData, _cadPayload(), label: 'CAD 편집');
    project = project.moveTo(SsStage.isoConversion);
    await store.save(project);
  });

  Future<void> pump(WidgetTester tester, {String projectId = 'p1', IsoConversionService conversionService = const IsoConversionService(stepDelay: Duration.zero)}) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: IsoConversionScreen(projectId: projectId, projectStore: store, conversionService: conversionService)),
        onGenerateRoute: (settings) {
          if (settings.name == SsStage.isoEditor.routeName) {
            return MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('ISO_EDITOR', key: Key('ssFakeIsoEditorScreen'))), settings: settings);
          }
          if (settings.name == SsStage.cadEditor.routeName) {
            return MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('CAD_EDITOR', key: Key('ssFakeCadEditorScreen'))), settings: settings);
          }
          return null;
        },
      ),
    );
  }

  testWidgets('변환이 끝나면 3D ISO 데이터를 저장하고 3D 디자인 화면으로 넘어간다', (tester) async {
    await pump(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ssFakeIsoEditorScreen')), findsOneWidget);

    final saved = await store.load('p1');
    expect(saved?.currentStage, SsStage.isoEditor);
    final payload = saved?.data[SsDataSlot.isoData]?.payload;
    expect(payload, isNotNull);
    expect(payload!['kind'], 'ssIsoScene');
    expect(payload['camera'], isNotNull);
    expect(saved?.data[SsDataSlot.cadData], isNotNull, reason: 'CAD 데이터는 그대로 남는다');
  });

  testWidgets('입력 자체가 문제면 재시도 없이 이전 단계로 돌아가는 안내만 보여준다', (tester) async {
    await pump(tester, conversionService: const _AlwaysInputErrorService());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ssIsoConversionBackFromFail')), findsOneWidget);
    final retryButton = tester.widget<ElevatedButton>(find.byKey(const Key('ssIsoConversionRetry')));
    expect(retryButton.onPressed, isNull);

    final saved = await store.load('p1');
    expect(saved?.data[SsDataSlot.isoData], isNull);
    expect(saved?.data[SsDataSlot.cadData], isNotNull);
  });

  testWidgets('일반 오류로 실패하면 다시 시도할 수 있고, CAD 데이터는 그대로 남는다', (tester) async {
    await pump(tester, conversionService: const _AlwaysFailService());
    await tester.pumpAndSettle();

    final retryButton = tester.widget<ElevatedButton>(find.byKey(const Key('ssIsoConversionRetry')));
    expect(retryButton.onPressed, isNotNull);

    final saved = await store.load('p1');
    expect(saved?.data[SsDataSlot.isoData], isNull);
    expect(saved?.data[SsDataSlot.cadData], isNotNull);
  });

  testWidgets('CAD 데이터가 없으면 이전 단계로 돌아가라는 안내를 보여준다', (tester) async {
    var noInputProject = SsProject.create(id: 'p2', name: '입력 없음', sourceType: SsSourceType.floorPlanUpload, now: DateTime(2026, 1, 1));
    noInputProject = noInputProject.moveTo(SsStage.isoConversion);
    await store.save(noInputProject);

    await pump(tester, projectId: 'p2');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ssIsoConversionMissingInput')), findsOneWidget);
  });

  testWidgets('이미 최신 3D 모델이 있으면 다시 변환하지 않고, 계속하기를 누르면 바로 3D 디자인으로 이동한다', (tester) async {
    var project = SsProject.create(id: 'p4', name: '최신 ISO', sourceType: SsSourceType.floorPlanUpload, now: DateTime(2026, 1, 1));
    project = project.withStageData(SsDataSlot.cadData, _cadPayload(), label: 'CAD 편집');
    project = project.withStageData(
      SsDataSlot.isoData,
      {
        'kind': 'ssIsoScene',
        'camera': const SsIsoCameraState(targetXMm: 1, targetYMm: 2, targetZMm: 3, distanceMm: 4000, azimuthRadians: 0.1, polarRadians: 0.2).toJson(),
        'warnings': <String>[],
      },
      label: '3D ISO 변환 결과',
    );
    project = project.moveTo(SsStage.isoConversion);
    await store.save(project);

    await pump(tester, projectId: 'p4');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ssIsoConversionUpToDatePanel')), findsOneWidget);
    expect(find.byKey(const Key('ssIsoConversionStatusPanel')), findsNothing);

    await tester.tap(find.byKey(const Key('ssIsoConversionContinue')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ssFakeIsoEditorScreen')), findsOneWidget);
    final saved = await store.load('p4');
    expect(saved?.currentStage, SsStage.isoEditor);
    final camera = saved?.data[SsDataSlot.isoData]?.payload['camera'] as Map?;
    expect(camera?['distanceMm'], 4000, reason: '다시 변환하지 않았으므로 camera는 원래 값 그대로다');
  });

  testWidgets('CAD가 바뀌어 3D 모델이 낡으면 자동으로 다시 변환하고, 기존 Orbit 카메라 시점은 보존한다', (tester) async {
    var project = SsProject.create(id: 'p5', name: '낡은 ISO', sourceType: SsSourceType.floorPlanUpload, now: DateTime(2026, 1, 1));
    final cadPayload = _cadPayload();
    project = project.withStageData(SsDataSlot.cadData, cadPayload, label: 'CAD 편집');
    project = project.withStageData(
      SsDataSlot.isoData,
      {
        'kind': 'ssIsoScene',
        'camera': const SsIsoCameraState(targetXMm: 9, targetYMm: 8, targetZMm: 7, distanceMm: 6000, azimuthRadians: 0.3, polarRadians: 0.4).toJson(),
        'warnings': <String>[],
      },
      label: '3D ISO 변환 결과',
    );
    project = project.withStageData(SsDataSlot.cadData, cadPayload, label: 'CAD 재편집');
    project = project.moveTo(SsStage.isoConversion);
    await store.save(project);

    await pump(tester, projectId: 'p5');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ssFakeIsoEditorScreen')), findsOneWidget);
    final saved = await store.load('p5');
    final camera = saved?.data[SsDataSlot.isoData]?.payload['camera'] as Map?;
    expect(camera?['distanceMm'], 6000, reason: '재생성해도 사용자가 이미 돌려본 Orbit 시점을 잃지 않는다');
  });
}
