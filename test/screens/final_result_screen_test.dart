// SS016 — MASTER UI 12(최종 ISO·투시도·결과 확인·내보내기) 화면 위젯 테스트: 최종 결과를 불러와
// 뷰 모드/공간 목록/선택 요소 패널을 보여주는지, 수정·재렌더링 화면으로 돌아갈 수 있는지, 내보내기
// 성공/실패가 네트워크 오류로 오분류되지 않는지, 저장이 되는지, 입력이 없으면 안내만 보이는지 확인한다.
//
// WO098/iso_editor_screen_test.dart의 선례("실제 geometry가 있는 Space3DViewGpuV2를 flutter_test
// 안에서 마운트하면 네이티브 GPU 초기화가 끝나지 않아 테스트가 불안정해진다")를 그대로 따른다 —
// 이 파일의 CAD 데이터는 벽이 없고 방 폴리곤도 2점(삼각분할 실패)이라 scene이 항상 비어 있어 그 GPU
// 위젯이 아예 마운트되지 않는다(플레이스홀더만). 공간 목록/선택 패널/내보내기(순수 Flutter 위젯
// 캡처이므로 안전)는 scene이 비어 있어도 독립적으로 동작하므로 이 상태로도 충분히 검증된다.
import 'dart:typed_data';

import 'package:ason_space/core/ss_editing.dart';
import 'package:ason_space/core/ss_project.dart';
import 'package:ason_space/core/ss_project_store.dart';
import 'package:ason_space/core/ss_stage.dart';
import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/ss_cad_scene.dart';
import 'package:ason_space/screens/final_result_screen.dart';
import 'package:ason_space/services/ss_image_export_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _scale = FloorPlanScale(
  mmPerPixel: 5.0,
  referenceStart: Point2(0, 0),
  referenceEnd: Point2(1, 0),
  referenceLengthMm: 5000,
  source: ScaleSource.measured,
);

// 벽 없음 + 2점짜리 방 폴리곤(삼각분할 실패) — scene.isEmpty가 항상 true라 네이티브 GPU 3D 위젯이
// 마운트되지 않으면서도, 방 목록에는 그대로 나타난다(공간 목록은 scene이 아니라 plan.rooms를 쓴다).
CadFloorPlan _samplePlan() => const CadFloorPlan(
  sourceWidthPx: 1000,
  sourceHeightPx: 1000,
  walls: [],
  openings: [],
  rooms: [CadRoom(id: 'room-0', polygon: [Point2(0.1, 0.1), Point2(0.2, 0.1)], areaNormalized: 0.01, confidence: 0.9, name: '거실')],
  warnings: [],
);

Map<String, Object?> _cadPayload() => {'kind': 'ssCadScene', 'scene': SsCadScene(plan: _samplePlan(), scale: _scale).toJson()};

class _FakeExportService extends SsImageExportService {
  const _FakeExportService({this.fail = false});
  final bool fail;

  @override
  Future<String?> save(Uint8List pngBytes, SsExportJob job, {int jpgQuality = 90, bool chooseLocation = false}) async {
    if (fail) throw Exception('저장 실패(시험)');
    return '/fake/path/${job.fullName}';
  }
}

void main() {
  late MemorySsProjectStore store;

  setUp(() async {
    store = MemorySsProjectStore();
    var project = SsProject.create(id: 'p1', name: '최종 결과 테스트', sourceType: SsSourceType.floorPlanUpload, now: DateTime(2026, 1, 1));
    project = project.withStageData(SsDataSlot.cadData, _cadPayload(), label: 'CAD 편집');
    project = project.withStageData(
      SsDataSlot.renderData,
      {'kind': 'ssIsoRender', 'warnings': ['문/창이 아직 벽에 반영되지 않았습니다']},
      label: '3D ISO 렌더링 결과',
    );
    project = project.moveTo(SsStage.finalResult);
    await store.save(project);
  });

  Future<void> pump(
    WidgetTester tester, {
    String projectId = 'p1',
    SsImageExportService exportService = const SsImageExportService(),
  }) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FinalResultScreen(projectId: projectId, projectStore: store, exportService: exportService)),
        onGenerateRoute: (settings) {
          if (settings.name == SsStage.isoEditor.routeName) {
            return MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('ISO_EDITOR', key: Key('ssFakeIsoEditorScreen'))), settings: settings);
          }
          if (settings.name == SsStage.isoRendering.routeName) {
            return MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('ISO_RENDERING', key: Key('ssFakeIsoRenderingScreen'))), settings: settings);
          }
          return null;
        },
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('정상적으로 불러오면 뷰 모드 바·경고 문구·공간 목록이 보인다', (tester) async {
    await pump(tester);

    expect(find.byKey(const Key('ssFinalResultScreen')), findsOneWidget);
    expect(find.byKey(const Key('ssFinalResultViewModeBar')), findsOneWidget);
    expect(find.byKey(const Key('ssFinalResultEmptyScene')), findsOneWidget);
    expect(find.byKey(const Key('ssFinalResultSpace3D')), findsNothing);
    expect(find.byKey(const Key('ssFinalResultWarnings')), findsOneWidget);
    expect(find.byKey(const Key('ssFinalResultSpace_room-0')), findsOneWidget);
    expect(find.byKey(const Key('ssFinalResultNoSelection')), findsOneWidget);
  });

  testWidgets('뷰 모드 칩을 누르면 선택 상태가 바뀐다', (tester) async {
    await pump(tester);

    final planChip = tester.widget<ChoiceChip>(find.byKey(const Key('ssFinalResultView_plan')));
    expect(planChip.selected, isFalse);

    await tester.tap(find.byKey(const Key('ssFinalResultView_plan')));
    await tester.pumpAndSettle();

    final updated = tester.widget<ChoiceChip>(find.byKey(const Key('ssFinalResultView_plan')));
    expect(updated.selected, isTrue);
  });

  testWidgets('공간을 선택하면 선택 요소 패널에 바닥 종류와 수정하러 가기 버튼이 보인다', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(const Key('ssFinalResultSpace_room-0')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ssFinalResultNoSelection')), findsNothing);
    final kindText = tester.widget<Text>(find.byKey(const Key('ssFinalResultSelectedKind')));
    expect(kindText.data, '바닥');
    expect(find.byKey(const Key('ssFinalResultEditSelected')), findsOneWidget);
  });

  testWidgets('수정하러 가기를 누르면 3D 디자인 화면으로 이동한다', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(const Key('ssFinalResultSpace_room-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ssFinalResultEditSelected')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ssFakeIsoEditorScreen')), findsOneWidget);
  });

  testWidgets('다시 렌더링을 누르면 3D 렌더링 화면으로 이동한다', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(const Key('ssFinalResultRerenderButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ssFakeIsoRenderingScreen')), findsOneWidget);
  });

  testWidgets('이전 단계로 돌아가기를 누르면 3D 렌더링 화면으로 이동한다', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(const Key('ssFinalResultBack')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ssFakeIsoRenderingScreen')), findsOneWidget);
  });

  testWidgets('내보내기를 누르면 성공 상태가 표시된다', (tester) async {
    await pump(tester, exportService: const _FakeExportService());

    // RenderRepaintBoundary.toImage()는 실제 엔진 콜백으로 완료되는 진짜 비동기라, 기본 testWidgets()의
    // FakeAsync 안에서는 그 Future가 끝까지 끝나지 않는다 — tester.runAsync로 짧게 실제 이벤트 루프를
    // 돌려 _export()가 캡처~저장까지 실제로 끝나게 한다.
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('ssFinalResultExportButton')));
      await tester.pumpAndSettle();
    });

    expect(find.byKey(const Key('ssFinalResultExportStatus')), findsOneWidget);
  });

  testWidgets('내보내기가 실패해도 네트워크 오류로 표시하지 않고 다시 시도할 수 있다', (tester) async {
    await pump(tester, exportService: const _FakeExportService(fail: true));

    // RenderRepaintBoundary.toImage()는 실제 엔진 콜백으로 완료되는 진짜 비동기라, 기본 testWidgets()의
    // FakeAsync 안에서는 그 Future가 끝까지 끝나지 않아 _exporting이 true로 멈춰 버린다 — tester.runAsync로
    // 짧게 실제 이벤트 루프를 돌려 캡처~저장 실패~catch까지 실제로 끝나게 한다.
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('ssFinalResultExportButton')));
      await tester.pumpAndSettle();
    });
    // runAsync 블록이 '더 이상 예약된 프레임이 없다'고 보고 반환한 바로 그 경계에서 실제 비동기(toImage
    // 콜백~저장 실패~catch의 setState)가 막 끝났을 수 있어, 그 리빌드가 아직 위젯 트리에 반영되지 않은
    // 채로 다음 단언이 실행될 수 있다 — runAsync 밖에서 한 번 더 pumpAndSettle해 그 막판 리빌드를 확실히 반영한다.
    await tester.pumpAndSettle();

    final statusText = tester.widget<Text>(find.descendant(of: find.byKey(const Key('ssFinalResultExportStatus')), matching: find.byType(Text)));
    expect(statusText.data, isNot(contains('네트워크')));

    final button = tester.widget<ElevatedButton>(find.byKey(const Key('ssFinalResultExportButton')));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('최종 저장을 누르면 저장 완료 스낵바가 보인다', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(const Key('ssFinalResultSaveButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ssFinalResultSaveSnackbar')), findsOneWidget);
  });

  testWidgets('CAD 데이터가 없으면 안내만 보여준다', (tester) async {
    var noInputProject = SsProject.create(id: 'p2', name: '입력 없음', sourceType: SsSourceType.floorPlanUpload, now: DateTime(2026, 1, 1));
    noInputProject = noInputProject.moveTo(SsStage.finalResult);
    await store.save(noInputProject);

    await pump(tester, projectId: 'p2');

    expect(find.byKey(const Key('ssFinalResultMissingInput')), findsOneWidget);
  });

  testWidgets('존재하지 않는 프로젝트를 열면 오류 안내가 보인다', (tester) async {
    await pump(tester, projectId: 'missing');

    expect(find.byKey(const Key('ssFinalResultLoadError')), findsOneWidget);
  });
}
