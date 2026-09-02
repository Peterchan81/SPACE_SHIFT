// FloorPlanWorkspaceScreen(신규 MASTER 메인 작업 화면)의 라우팅/시작 방식
// 선택 동작 및 "① 평면도 업로드" 실제 파일 업로드 기능에 대한 위젯 테스트.
//
// 1. 로그인 이후 기본 진입점이 이 화면이며(다른 테스트에서 별도 검증),
//    좌측 "시작 방식 선택" 3가지가 모두 보이는지 확인한다.
// 2. "① 평면도 업로드"는 이미 선택된 상태로, 탭해도 화면 전환 없이 이
//    화면에 남아있는다.
// 3. "② 직접 그리기"는 아직 화면이 없어 준비중 SnackBar만 보여주고, 이
//    화면에 그대로 남아있는다.
// 4. "③ 사진으로 변환"은 기존 PhotoSelectScreen을 push로 불러오고, 뒤로
//    가기(pop)로 다시 이 화면으로 돌아올 수 있다.
// 5. 실사용 진입(demoMode: false, 기본값) 시 작업 목록/선택 항목이 비어
//    있다 — MASTER 미리보기용 demo 6개가 실사용 흐름에 섞이지 않는다.
// 6. 평면도 업로드 action(파일 선택 버튼)이 항상 노출된다.
// 7. 이미지 파일을 선택하면 중앙에 실제 preview와 상태가 반영된다.
// 8. "다시 선택"으로 다른 파일로 교체할 수 있다.
// 9. 2D → 3D → 2D 전환에도 선택한 파일 상태가 유지되고, 3D에서는 정직한
//    준비 안내만 보여준다.
// 10. 파일 선택을 취소해도(null 반환) crash 없이 업로드 이전 상태를 유지한다.
// 11. 좌측 하단 "설정" 버튼이 노출되고, 탭하면 SettingsScreen으로
//     진입하며, 뒤로가기로 이 화면으로 돌아오면 업로드한 평면도/View
//     선택 상태가 유지된다(MASTER 공통 기능, WO 2/12/13).
// 12. "평면도 분석 시작"을 누르면 실제 단계 문구와 함께 로딩 상태가
//     표시된다(가짜 timer가 아니라 서비스 단계 콜백을 그대로 반영).
// 13. 분석이 성공하면 CAD geometry 오버레이가 나타나지만, 번호 marker와
//     작업 목록은 그대로 비어 있다 — 분석 객체는 사용자 작업이 아니다.
// 14. CAD 오버레이에서 벽을 탭하면 그 geometry가 선택되어 우측 패널에
//     "도면 요소" 정보가 표시된다(사용자 작업 선택과는 별개 상태).
// 15. 분석이 실패하면 안전한 실패 메시지를 보여주고, 원본 이미지와
//     빈 작업 목록은 그대로 유지된다(가짜 완료로 둔갑하지 않는다).
// 16. 선택된 CAD 벽을 삭제하면 사라지고, 실행 취소하면 되돌아온다.
// 17. 선택된 CAD 벽을 "작업으로 추가"하면 그때 처음으로 작업 번호 ①이
//     부여되고, marker/작업 목록/우측 패널이 동일 작업으로 동기화된다.
// 18. (2D 단순화 WO) 분석 직후 축척(문 기준 추정)/천장고(기본값)가
//     자동으로 채워져 곧바로 [3D 아이소 만들기]를 누를 수 있고, 누르면
//     실제 Space3DView가 뜬다. "치수 보정"으로 실측값을 입력하면 추정
//     표시가 사라지고 그 값으로 교체된다(기존 수동 보정 기능은 보조
//     기능으로 유지).

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:ason_space/models/floor_plan_file.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/screens/floor_plan_workspace_screen.dart';
import 'package:ason_space/screens/photo_select_screen.dart';
import 'package:ason_space/screens/settings_screen.dart';
import 'package:ason_space/services/floor_plan_analysis_service.dart';
import 'package:ason_space/services/floor_plan_upload_service.dart';
import 'package:ason_space/widgets/workspace/cad_floor_plan_overlay.dart';
import 'package:ason_space/widgets/workspace/cad_structure_tab.dart';
import 'package:ason_space/widgets/workspace/floor_plan_analysis_overlay.dart'
    show ContainFitTransform, FloorPlanAnalysisOverlay;
import 'package:ason_space/widgets/workspace/selected_item_header.dart';
import 'package:ason_space/widgets/workspace/space_3d_view.dart';

/// 실제 플랫폼 파일 선택창 대신, 미리 정해진 결과를 순서대로 반환하는
/// 가짜 서비스. 취소를 흉내내려면 목록에 null을 넣으면 된다.
class _FakeFloorPlanUploadService extends FloorPlanUploadService {
  _FakeFloorPlanUploadService(this._results);

  final List<FloorPlanFile?> _results;
  int _index = 0;

  @override
  Future<FloorPlanFile?> pickFloorPlanFile() async {
    final result = _index < _results.length ? _results[_index] : null;
    _index++;
    return result;
  }
}

/// 위젯 테스트에서 Image.memory가 실제로 디코딩 가능한 1x1 PNG.
final Uint8List _fakeImageBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
  '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

FloorPlanFile _fakeImageFile(String name) => FloorPlanFile(
  fileName: name,
  extension: 'png',
  kind: FloorPlanFileKind.image,
  sizeBytes: _fakeImageBytes.length,
  bytes: _fakeImageBytes,
);

/// 실제 CV 파이프라인 대신, 미리 정해진 결과를 실제 단계 콜백과 함께
/// 돌려주는 가짜 분석 서비스. 두 단계 사이를 [proceedToSecondStep]으로
/// 테스트가 직접 통제해, 중간 단계 UI를 안정적으로 관찰할 수 있게
/// 한다(가짜 timer가 아니라, "1단계가 실제로 끝났을 때"만 2단계로
/// 넘어간다는 것을 Completer로 표현한다).
class _FakeFloorPlanAnalysisService extends FloorPlanAnalysisService {
  _FakeFloorPlanAnalysisService(this._outcome);

  final FloorPlanAnalysisOutcome _outcome;
  final Completer<void> _afterFirstStep = Completer<void>();
  final Completer<void> _afterSecondStep = Completer<void>();

  void proceedToSecondStep() {
    if (!_afterFirstStep.isCompleted) _afterFirstStep.complete();
  }

  /// 2단계 라벨이 화면에 실제로 그려질 시간을 주기 위해, 두 번째
  /// completer가 완료되기 전까지는 결과를 반환하지 않는다 — 그렇지 않으면
  /// 두 단계 전환이 microtask 한 번에 몰아서 끝나 중간 상태를 테스트에서
  /// 관찰할 수 없다.
  void finish() {
    if (!_afterSecondStep.isCompleted) _afterSecondStep.complete();
  }

  @override
  Future<FloorPlanAnalysisOutcome> analyze(
    FloorPlanFile file, {
    void Function(FloorPlanAnalysisStep step)? onStep,
  }) async {
    onStep?.call(FloorPlanAnalysisStep.preparingAndWalls);
    await _afterFirstStep.future;
    onStep?.call(FloorPlanAnalysisStep.roomsAndOpenings);
    await _afterSecondStep.future;
    return _outcome;
  }
}

const _fakeAnalysisResult = FloorPlanAnalysisResult(
  sourceWidthPx: 800,
  sourceHeightPx: 600,
  walls: [
    WallSegment(
      id: 'wall-ext-1',
      start: Point2(0.05, 0.05),
      end: Point2(0.95, 0.05),
      thicknessNormalized: 0.02,
      confidence: 0.8,
      isExterior: true,
    ),
    WallSegment(
      id: 'wall-int-1',
      start: Point2(0.5, 0.05),
      end: Point2(0.5, 0.95),
      thicknessNormalized: 0.02,
      confidence: 0.6,
    ),
  ],
  openings: [
    OpeningCandidate(
      id: 'opening-1',
      type: OpeningType.door,
      center: Point2(0.5, 0.5),
      widthNormalized: 0.05,
      confidence: 0.5,
    ),
  ],
  rooms: [
    RoomCandidate(
      id: 'room-1',
      polygon: [
        Point2(0.05, 0.05),
        Point2(0.5, 0.05),
        Point2(0.5, 0.95),
        Point2(0.05, 0.95),
      ],
      areaNormalized: 0.4,
      confidence: 0.7,
    ),
  ],
  warnings: [],
  debugStats: FloorPlanAnalysisDebugStats(
    sourceWidthPx: 800,
    sourceHeightPx: 600,
    analysisWidthPx: 800,
    analysisHeightPx: 600,
    rawHorizontalRuns: 2,
    rawVerticalRuns: 1,
    mergedWallCount: 2,
    roomCandidateCount: 1,
    openingCandidateCount: 1,
    durationMs: 10,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // SettingsScreen이 내부에서 PackageInfo.fromPlatform()을 호출하므로,
    // 좌측 하단 "설정" 진입 테스트를 위해 미리 mock 값을 채워 둔다.
    PackageInfo.setMockInitialValues(
      appName: 'SPACE SHIFT',
      packageName: 'com.example.ason_space',
      version: '1.0.0',
      buildNumber: '2016',
      buildSignature: '',
    );
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    FloorPlanUploadService uploadService = const FloorPlanUploadService(),
    FloorPlanAnalysisService analysisService = const FloorPlanAnalysisService(),
  }) async {
    // 2D 단순화 WO — 우측 패널 상단에 "평면도 준비 완료"(공간 크기/천장
    // 높이) 카드가 새로 추가되어 세로 공간이 더 필요해졌다. 800이면
    // 그 아래 CadStructureTab/선택 안내 등이 ListView의 lazy 빌드
    // 범위(viewport+cacheExtent) 밖으로 밀려 스크롤해도 찾을 수 없는
    // 위젯이 됐다 — 테스트 스위트 전체가 공유하는 뷰포트를 넉넉하게
    // 키워 해결한다(개별 테스트마다 스크롤 로직을 추가하지 않는다).
    await tester.binding.setSurfaceSize(const Size(1280, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: FloorPlanWorkspaceScreen(
          uploadService: uploadService,
          analysisService: analysisService,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('좌측 시작 방식 선택 3가지가 모두 보인다', (tester) async {
    await pumpScreen(tester);

    expect(find.text('평면도 업로드'), findsOneWidget);
    expect(find.text('직접 그리기'), findsOneWidget);
    expect(find.text('사진으로 변환'), findsOneWidget);
  });

  testWidgets('"직접 그리기"를 탭하면 준비중 안내만 보여주고 이 화면에 남는다', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('직접 그리기'));
    await tester.pump();

    expect(find.textContaining('준비 중입니다'), findsOneWidget);
    expect(find.byType(FloorPlanWorkspaceScreen), findsOneWidget);
    expect(find.byType(PhotoSelectScreen), findsNothing);
  });

  testWidgets('"사진으로 변환"을 탭하면 기존 PhotoSelectScreen이 열리고, 뒤로가기로 돌아올 수 있다', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.tap(find.text('사진으로 변환'));
    await tester.pumpAndSettle();

    expect(find.byType(PhotoSelectScreen), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byType(FloorPlanWorkspaceScreen), findsOneWidget);
    expect(find.byType(PhotoSelectScreen), findsNothing);
  });

  testWidgets('실사용 진입 시 작업 목록/선택 항목이 비어 있다(demo 데이터가 섞이지 않는다)', (tester) async {
    await pumpScreen(tester);

    expect(find.text('아직 등록된 작업이 없습니다.'), findsOneWidget);
    expect(find.text('선택된 항목이 없습니다.\n평면도에서 작업할 영역을 선택해주세요.'), findsOneWidget);
    expect(find.text('거실 벽 (TV 벽체)'), findsNothing);
  });

  testWidgets('평면도 업로드 action(파일 선택 버튼)이 노출된다', (tester) async {
    await pumpScreen(tester);

    expect(find.text('평면도를 업로드해주세요'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '파일 선택'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, '평면도 선택'), findsOneWidget);
  });

  testWidgets('이미지 파일을 선택하면 중앙에 실제 preview와 상태가 반영된다', (tester) async {
    final service = _FakeFloorPlanUploadService([
      _fakeImageFile('floor_plan_1.png'),
    ]);
    await pumpScreen(tester, uploadService: service);

    await tester.tap(find.widgetWithText(OutlinedButton, '파일 선택'));
    await tester.pumpAndSettle();

    expect(find.textContaining('floor_plan_1.png'), findsWidgets);
    // 도면 분석 상태/시작 버튼은 중앙 캔버스가 아니라 우측 "사용자 작업
    // 환경" 패널에서 보여준다 — 중앙은 평면도 자체만 크고 깨끗하게
    // 보이는 화면이다.
    expect(find.text('평면도 분석 시작'), findsOneWidget);
    expect(find.text('평면도를 업로드해주세요'), findsNothing);
  });

  testWidgets('"다시 선택"으로 다른 파일로 교체할 수 있다', (tester) async {
    final service = _FakeFloorPlanUploadService([
      _fakeImageFile('floor_plan_1.png'),
      _fakeImageFile('floor_plan_2.png'),
    ]);
    await pumpScreen(tester, uploadService: service);

    await tester.tap(find.widgetWithText(OutlinedButton, '파일 선택'));
    await tester.pumpAndSettle();
    expect(find.textContaining('floor_plan_1.png'), findsWidgets);

    await tester.tap(find.widgetWithText(OutlinedButton, '다시 선택'));
    await tester.pumpAndSettle();

    expect(find.textContaining('floor_plan_2.png'), findsWidgets);
    expect(find.textContaining('floor_plan_1.png'), findsNothing);
  });

  testWidgets('2D → 3D → 2D 전환에도 선택한 파일 상태가 유지되고, 3D에서는 준비 안내만 보여준다', (
    tester,
  ) async {
    final service = _FakeFloorPlanUploadService([
      _fakeImageFile('floor_plan_1.png'),
    ]);
    await pumpScreen(tester, uploadService: service);

    await tester.tap(find.widgetWithText(OutlinedButton, '파일 선택'));
    await tester.pumpAndSettle();
    expect(find.text('평면도 분석 시작'), findsOneWidget);

    await tester.tap(find.text('3D 아이소'));
    await tester.pump();

    expect(find.text('3D 공간이 아직 생성되지 않았습니다'), findsOneWidget);
    // 3D View에서는 2D 전용 도면 분석/표시 설정 섹션 대신, 3D 단계
    // 안내가 우측 패널에 보인다(WO 22번).
    expect(find.text('평면도 분석 시작'), findsNothing);

    await tester.tap(find.text('2D 평면도'));
    await tester.pump();

    // 3D를 다녀왔어도 업로드한 파일 상태 자체는 그대로 남아있다.
    expect(find.text('평면도 분석 시작'), findsOneWidget);
    expect(find.textContaining('floor_plan_1.png'), findsWidgets);
  });

  testWidgets('파일 선택을 취소해도 crash 없이 업로드 이전 상태를 유지한다', (tester) async {
    final service = _FakeFloorPlanUploadService([null]);
    await pumpScreen(tester, uploadService: service);

    await tester.tap(find.widgetWithText(OutlinedButton, '파일 선택'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('평면도를 업로드해주세요'), findsOneWidget);
  });

  testWidgets('좌측 하단 "설정" 버튼이 노출된다', (tester) async {
    await pumpScreen(tester);

    expect(find.text('설정'), findsOneWidget);
  });

  testWidgets('"설정"을 탭하면 SettingsScreen으로 진입하고, 뒤로가기로 이 화면으로 돌아온다', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.tap(find.text('설정'));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.byType(FloorPlanWorkspaceScreen), findsOneWidget);
  });

  testWidgets('설정 진입 후 돌아와도 업로드한 평면도와 선택한 View 상태가 유지된다', (tester) async {
    final service = _FakeFloorPlanUploadService([
      _fakeImageFile('floor_plan_1.png'),
    ]);
    await pumpScreen(tester, uploadService: service);

    await tester.tap(find.widgetWithText(OutlinedButton, '파일 선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3D 아이소'));
    await tester.pump();
    expect(find.text('3D 공간이 아직 생성되지 않았습니다'), findsOneWidget);

    await tester.tap(find.text('설정'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    // 설정 화면을 다녀와도 workspace의 State가 그대로 유지되어, 업로드한
    // 파일과 선택했던 View(3D 아이소)가 초기화되지 않는다.
    expect(find.text('3D 공간이 아직 생성되지 않았습니다'), findsOneWidget);
    await tester.tap(find.text('2D 평면도'));
    await tester.pump();
    expect(find.textContaining('floor_plan_1.png'), findsWidgets);
  });

  testWidgets('평면도 분석 시작을 누르면 실제 단계 문구와 함께 로딩 상태가 표시된다', (tester) async {
    final analysisService = _FakeFloorPlanAnalysisService(
      const FloorPlanAnalysisOutcome.success(_fakeAnalysisResult),
    );
    await pumpScreen(
      tester,
      uploadService: _FakeFloorPlanUploadService([
        _fakeImageFile('floor_plan.png'),
      ]),
      analysisService: analysisService,
    );

    await tester.tap(find.widgetWithText(OutlinedButton, '파일 선택'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('평면도 분석 시작'));
    await tester.pump();

    expect(find.textContaining('벽을 분석하는 중입니다'), findsOneWidget);

    // fake 서비스는 테스트가 명시적으로 완료시켜주기 전까지 1단계에
    // 머물러 있는다 — 실제로 "1단계 작업이 끝났을 때"만 2단계로
    // 넘어간다는 것을 보장하기 위함이다(가짜 timer로 흉내내지 않는다).
    analysisService.proceedToSecondStep();
    await tester.pump();
    expect(find.textContaining('문/창 후보를 분석하는 중입니다'), findsOneWidget);

    analysisService.finish();
    await tester.pumpAndSettle();
  });

  /// 여러 새 테스트가 공통으로 필요로 하는 "평면도 선택 → 분석 완료"
  /// 상태까지 진행한다.
  Future<_FakeFloorPlanAnalysisService> pumpAnalyzed(
    WidgetTester tester,
  ) async {
    final analysisService = _FakeFloorPlanAnalysisService(
      const FloorPlanAnalysisOutcome.success(_fakeAnalysisResult),
    );
    await pumpScreen(
      tester,
      uploadService: _FakeFloorPlanUploadService([
        _fakeImageFile('floor_plan.png'),
      ]),
      analysisService: analysisService,
    );

    await tester.tap(find.widgetWithText(OutlinedButton, '파일 선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('평면도 분석 시작'));
    await tester.pump();
    analysisService.proceedToSecondStep();
    analysisService.finish();
    await tester.pumpAndSettle();
    return analysisService;
  }

  Future<void> tapWall(WidgetTester tester, Point2 normalized) async {
    final overlayRect = tester.getRect(find.byType(CadFloorPlanOverlay));
    final transform = ContainFitTransform.compute(
      overlayRect.size,
      const Size(800, 600),
    );
    final screenPoint = transform.mapNormalized(normalized);
    await tester.tapAt(overlayRect.topLeft + screenPoint);
    await tester.pumpAndSettle();
  }

  testWidgets('분석이 성공해도 번호 marker/작업 목록은 비어 있고 CAD geometry만 표시된다', (
    tester,
  ) async {
    await pumpAnalyzed(tester);

    // 기본(non-debug) 상태에서는 CAD 오버레이만 보이고, confidence color
    // 분석 확인 오버레이는 보이지 않는다(WO 5번).
    expect(find.byType(CadFloorPlanOverlay), findsOneWidget);
    expect(find.byType(FloorPlanAnalysisOverlay), findsNothing);

    // 분석 geometry는 사용자 작업이 아니므로, 분석 직후에도 작업 목록은
    // 여전히 0개다(WO 1/2번) — "외벽"/"내벽"/"공간 1"/"문 후보" 같은
    // 이름은 사용자가 실제로 작업을 만들기 전까지 어디에도 나타나지
    // 않는다.
    expect(find.text('아직 등록된 작업이 없습니다.'), findsOneWidget);
    expect(find.text('외벽'), findsNothing);
    expect(find.text('공간 1'), findsNothing);
    // 우측 패널 상단에 도면 분석 상태/표시 설정 섹션이 추가되어, 선택
    // 안내 카드가 스크롤 영역 아래로 밀려 화면 밖에 있을 수 있다 —
    // 존재 여부만 확인하므로 skipOffstage: false로 찾는다.
    expect(
      find.text('선택된 항목이 없습니다.\n평면도에서 작업할 영역을 선택해주세요.', skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('CAD 오버레이에서 벽을 탭하면 도면 요소 정보가 우측 패널에 표시된다(작업 생성 아님)', (
    tester,
  ) async {
    await pumpAnalyzed(tester);

    // 외벽(wall-ext-1) 위의 한 점. wall-ext-1의 중점(0.5,0.05)은 내벽
    // wall-int-1의 시작점과 정확히 겹치는 T자 교차점이라 삭제 후
    // 재선택 테스트에서 다른 벽이 선택되는 혼선이 생길 수 있어, 교차점을
    // 피한 (0.2, 0.05)를 쓴다.
    await tapWall(tester, const Point2(0.2, 0.05));

    // 우측 패널 상단의 도면 분석 상태/표시 설정 섹션 때문에 CadStructureTab
    // 내용이 스크롤 영역 아래로 밀려 있을 수 있다 — 존재 여부만
    // 확인하므로 skipOffstage: false로 찾는다.
    final cadStructureTabFinder = find.byType(
      CadStructureTab,
      skipOffstage: false,
    );
    expect(cadStructureTabFinder, findsOneWidget);
    expect(find.text('wall-ext-1', skipOffstage: false), findsOneWidget);
    expect(
      find.descendant(
        of: cadStructureTabFinder,
        matching: find.text('외벽', skipOffstage: false),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    // 벽을 선택한 것만으로는 사용자 작업이 생기지 않는다.
    expect(find.text('아직 등록된 작업이 없습니다.'), findsOneWidget);
  });

  testWidgets('분석이 실패하면 안전한 메시지를 보여주고 원본 이미지/빈 작업 목록을 유지한다', (tester) async {
    final analysisService = _FakeFloorPlanAnalysisService(
      const FloorPlanAnalysisOutcome.failure(
        FloorPlanAnalysisFailureReason.noWallsFound,
        '평면도 구조를 충분히 인식하지 못했습니다.\n직접 보정할 수 있도록 원본을 유지했습니다.',
      ),
    );
    await pumpScreen(
      tester,
      uploadService: _FakeFloorPlanUploadService([
        _fakeImageFile('floor_plan.png'),
      ]),
      analysisService: analysisService,
    );

    await tester.tap(find.widgetWithText(OutlinedButton, '파일 선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('평면도 분석 시작'));
    await tester.pump();
    analysisService.proceedToSecondStep();
    analysisService.finish();
    await tester.pumpAndSettle();

    expect(find.textContaining('평면도 구조를 충분히 인식하지 못했습니다'), findsOneWidget);
    expect(find.byType(FloorPlanAnalysisOverlay), findsNothing);
    expect(find.textContaining('floor_plan.png'), findsWidgets);
    expect(find.text('아직 등록된 작업이 없습니다.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('선택된 CAD 벽을 삭제하면 사라지고, 실행 취소하면 되돌아온다', (tester) async {
    await pumpAnalyzed(tester);
    await tapWall(tester, const Point2(0.2, 0.05));
    expect(find.byType(CadStructureTab, skipOffstage: false), findsOneWidget);

    // 우측 패널 상단에 도면 분석 상태/표시 설정 섹션이 함께 있어 "도면
    // 보정" 카드가 화면 밖으로 스크롤되어 있을 수 있다.
    final deleteButton = find.widgetWithText(
      OutlinedButton,
      '삭제',
      skipOffstage: false,
    );
    await tester.ensureVisible(deleteButton);
    await tester.pumpAndSettle();
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();

    // 삭제되면 선택도 함께 풀려 빈 선택 안내로 돌아간다.
    expect(
      find.text('선택된 항목이 없습니다.\n평면도에서 작업할 영역을 선택해주세요.', skipOffstage: false),
      findsOneWidget,
    );
    // 삭제된 벽이 있던 자리를 다시 눌러도 더 이상 선택되지 않는다.
    // (0.2, 0.05)는 room-1의 상단 경계와 맞닿아 있어, 벽이 사라진 뒤
    // 그 경계 판정에 따라 room이 대신 선택될 수 있으므로 도면 어디에도
    // geometry가 없는 (0.9, 0.9)로 확인한다.
    await tapWall(tester, const Point2(0.9, 0.9));
    expect(find.byType(CadStructureTab), findsNothing);

    final undoButton = find.widgetWithText(
      OutlinedButton,
      '실행 취소',
      skipOffstage: false,
    );
    await tester.ensureVisible(undoButton);
    await tester.pumpAndSettle();
    await tester.tap(undoButton);
    await tester.pumpAndSettle();

    // 되돌린 뒤 같은 자리를 다시 누르면 벽이 실제로 복원되어 있어야 한다.
    await tapWall(tester, const Point2(0.2, 0.05));
    expect(find.byType(CadStructureTab, skipOffstage: false), findsOneWidget);
    expect(find.text('wall-ext-1', skipOffstage: false), findsOneWidget);
  });

  testWidgets('CAD 벽을 "작업으로 추가"하면 그때 처음 작업 번호가 부여되고 3곳이 동기화된다', (tester) async {
    await pumpAnalyzed(tester);
    await tapWall(tester, const Point2(0.2, 0.05));

    // 우측 패널 상단의 도면 분석 상태/표시 설정 섹션 때문에 "작업으로
    // 추가" 버튼이 화면 밖으로 스크롤되어 있을 수 있다.
    final addButton = find.widgetWithText(
      FilledButton,
      '작업으로 추가',
      skipOffstage: false,
    );
    await tester.ensureVisible(addButton);
    await tester.pumpAndSettle();
    await tester.tap(addButton);
    await tester.pumpAndSettle();

    // geometry 선택은 풀리고, 새로 만들어진 사용자 작업이 선택된 채로
    // 우측 패널(SelectedItemHeader)에 번호 1과 함께 나타난다.
    expect(find.byType(CadStructureTab), findsNothing);
    expect(
      find.descendant(
        of: find.byType(SelectedItemHeader),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(SelectedItemHeader),
        matching: find.text('외벽 작업'),
      ),
      findsOneWidget,
    );
    // 작업 목록에도 같은 작업이 반영된다 — 더 이상 0개가 아니다.
    expect(find.text('아직 등록된 작업이 없습니다.'), findsNothing);
    expect(find.text('외벽 작업'), findsWidgets);
  });

  testWidgets('2D 단순화 — 분석 직후 축척(문 기준 추정)/천장고(기본값)가 자동으로 '
      '채워져 있어, 기준점을 직접 찍지 않아도 곧바로 3D 아이소를 만들 수 '
      '있다. 실제로 눌러 만들면 정적 안내가 아니라 실제 Space3DView가 뜬다', (tester) async {
    await pumpAnalyzed(tester);

    await tester.tap(find.text('3D 아이소'));
    await tester.pump();

    final generateButton = find.widgetWithText(
      ElevatedButton,
      '3D 아이소 만들기',
      skipOffstage: false,
    );
    await tester.ensureVisible(generateButton);
    await tester.pumpAndSettle();

    expect(tester.widget<ElevatedButton>(generateButton).onPressed, isNotNull);
    expect(find.textContaining('3D 아이소 생성 준비가 완료'), findsOneWidget);

    await tester.tap(generateButton);
    await tester.pump();

    expect(find.byType(Space3DView), findsOneWidget);
    // 준비 상태 안내(정적 placeholder)는 실제 3D가 뜨면 사라진다.
    expect(find.textContaining('3D 아이소 생성 준비가 완료'), findsNothing);
  });

  testWidgets('2D 단순화 — "공간 크기" 카드가 자동 추정값임을 알리고(추정), "치수 '
      '보정"으로 실측값을 입력하면 그 값으로 교체된다(기존 수동 보정 기능 '
      '유지, WO 3/7번 — 필수 단계에서만 제거)', (tester) async {
    await pumpAnalyzed(tester);

    expect(find.textContaining('추정'), findsWidgets);

    final calibrationButton = find.text('치수 보정', skipOffstage: false);
    await tester.ensureVisible(calibrationButton);
    await tester.pumpAndSettle();
    await tester.tap(calibrationButton);
    await tester.pumpAndSettle();

    await tapWall(tester, const Point2(0.1, 0.1));
    await tapWall(tester, const Point2(0.9, 0.1));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, '3200');
    await tester.tap(find.widgetWithText(FilledButton, '축척 적용'));
    await tester.pumpAndSettle();

    // 실측값으로 교체된 뒤에는 더 이상 "추정" 문구가 공간 크기 옆에
    // 붙지 않는다.
    final areaLabel = find.textContaining('㎡', skipOffstage: false);
    await tester.ensureVisible(areaLabel);
    expect(find.textContaining('㎡ (추정)', skipOffstage: false), findsNothing);
  });
}
