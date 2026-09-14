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
// 12. "AI 평면도 생성"을 누르면 로딩 상태가 표시된다(가짜 timer가 아니라
//     서비스 단계 콜백을 그대로 반영).
// 13. 분석이 성공하면 번호 marker와 작업 목록은 그대로 비어 있다 —
//     분석/생성 결과는 사용자 작업이 아니다.
// 14. 분석이 실패하면 안전한 실패 메시지를 보여주고, 원본 이미지와
//     빈 작업 목록은 그대로 유지된다(가짜 완료로 둔갑하지 않는다).
// 15. (2D 단순화 WO) 분석 직후 축척(문 기준 추정)/천장고(기본값)가
//     자동으로 채워져 곧바로 [3D 아이소 만들기]를 누를 수 있고, 누르면
//     실제 Space3DViewV2가 뜬다. "치수 보정"으로 실측값을 입력하면 추정
//     표시가 사라지고 그 값으로 교체된다(기존 수동 보정 기능은 보조
//     기능으로 유지 — 내부 geometry는 계속 존재하므로 이 기능은 깨지지
//     않는다).
// 16. V1 AI-IMAGE FLOW WO — 방향 수정: GPT는 좌표(SSSpatialModel)가 아니라
//     원본 배치를 유지한 "깨끗한 CAD 스타일 2D 평면도 이미지"를 새로
//     그려서 돌려준다. 그 이미지가 있으면 중앙 화면에 그대로 보여주고,
//     없으면(생성 실패/미설정) 원본 사진을 그대로 보여준다 — 좌표 기반
//     CAD 오버레이 탭 선택/"작업으로 추가"/CadStructureTab은 더 이상
//     production 흐름에 없다(코드 자체는 삭제하지 않았다).

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:ason_space/models/cad_floor_plan.dart' show CadElementSource;
import 'package:ason_space/models/floor_plan_file.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/screens/floor_plan_workspace_screen.dart';
import 'package:ason_space/screens/photo_select_screen.dart';
import 'package:ason_space/screens/settings_screen.dart';
import 'package:ason_space/services/floor_plan_analysis_service.dart';
import 'package:ason_space/services/floor_plan_upload_service.dart';
import 'package:ason_space/services/gpt_floorplan_image_service.dart';
import 'package:ason_space/services/gpt_floorplan_iso_service.dart';
import 'package:ason_space/widgets/workspace/cad_floor_plan_overlay.dart';
import 'package:ason_space/widgets/workspace/floor_plan_analysis_overlay.dart'
    show ContainFitTransform, FloorPlanAnalysisOverlay;
import 'package:ason_space/widgets/workspace/work_tab.dart';
import 'package:ason_space/widgets/workspace/workspace_canvas.dart';

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

/// 원본과 구분할 수 있도록 다른 1x1 PNG(파란 픽셀) — "GPT가 새로 그려준
/// 이미지가 실제로 화면에 보이는가"를 원본과 다른 바이트로 확실히
/// 구분해서 검증하기 위함이다.
final Uint8List _fakeGeneratedImageBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNh'
  'YPgPAAETAQQEubHGAAAAAElFTkSuQmCC',
);

/// V1 AI-IMAGE FLOW WO — 실제 네트워크 호출 없이 "GPT가 CAD 스타일
/// 평면도 이미지를 생성해 돌려준다"를 흉내내는 가짜 서비스.
class _FakeFloorPlanImageService implements FloorPlanImageGenerationService {
  const _FakeFloorPlanImageService();

  @override
  Future<Uint8List> generate(Uint8List originalImageBytes) async =>
      _fakeGeneratedImageBytes;
}

/// 항상 실패하는 가짜 서비스 — "GPT 생성이 실패하면 원본 사진을 그대로
/// 보여준다"를 검증할 때 쓴다.
class _FailingFloorPlanImageService implements FloorPlanImageGenerationService {
  const _FailingFloorPlanImageService();

  @override
  Future<Uint8List> generate(Uint8List originalImageBytes) async {
    throw Exception('AI 평면도 생성 기능이 아직 설정되지 않았습니다.');
  }
}

/// `Image.memory(bytes, cacheWidth: ...)`는 내부적으로 [MemoryImage]를
/// [ResizeImage]로 감싼다 — 이 helper로 실제 원본 provider까지 벗겨내야
/// bytes를 비교할 수 있다.
bool _imageShowsBytes(Image image, Uint8List expectedBytes) {
  var provider = image.image;
  if (provider is ResizeImage) provider = provider.imageProvider;
  return provider is MemoryImage && provider.bytes == expectedBytes;
}

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
    // V1 AI-IMAGE FLOW WO — 기본값은 "GPT 생성 성공" 경로다(실사용
    // 앱이 실제로 도달하길 기대하는 정상 흐름). 실패/미설정 폴백은
    // _FailingFloorPlanImageService를 명시적으로 넘긴 테스트에서만 확인한다.
    FloorPlanImageGenerationService floorPlanImageService =
        const _FakeFloorPlanImageService(),
    // V1 GPT CAD-STYLE 2D → GPT ISO IMAGE FLOW WO — 기존 테스트는
    // "3D 아이소 만들기"를 실제로 누르지 않으므로(네이티브 GPU 위젯
    // 제약, 위 주석 참고) 이 서비스를 호출할 일이 없다 — 실제로
    // ISO 생성 흐름을 검증하는 테스트만 [_FakeFloorPlanIsoImageService]를
    // 명시적으로 넘긴다.
    FloorPlanIsoImageGenerationService floorPlanIsoService =
        const UnavailableFloorPlanIsoImageService(),
  }) async {
    // 2D 단순화 WO — 우측 패널 상단에 "평면도 준비 완료"(공간 크기/천장
    // 높이) 카드가 새로 추가되어 세로 공간이 더 필요해졌다. 800이면
    // 그 아래 선택 안내 등이 ListView의 lazy 빌드 범위(viewport+
    // cacheExtent) 밖으로 밀려 스크롤해도 찾을 수 없는 위젯이 됐다 —
    // 테스트 스위트 전체가 공유하는 뷰포트를 넉넉하게 키워 해결한다
    // (개별 테스트마다 스크롤 로직을 추가하지 않는다).
    await tester.binding.setSurfaceSize(const Size(1280, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: FloorPlanWorkspaceScreen(
          uploadService: uploadService,
          analysisService: analysisService,
          floorPlanImageService: floorPlanImageService,
          floorPlanIsoService: floorPlanIsoService,
        ),
      ),
    );
    await tester.pump();

    // WO099 UI COMPACT MODE — 좌/우 패널이 기본은 아이콘만 보이는 레일로
    // 바뀌었다("평면도 업로드"/"작업도구" 내용은 더 이상 항상 보이지
    // 않는다). 이 아래 대부분의 테스트는 그 안쪽 내용(파일 선택 버튼/
    // AI 평면도 생성/치수 보정 등) 자체를 검증하는 것이 목적이므로,
    // 공용 helper에서 두 패널을 미리 펼쳐 실제 동작 검증에 집중한다.
    // 레일 아이콘/tooltip/펼침·접힘 토글 자체는 별도 테스트에서 확인한다.
    await tester.tap(find.byTooltip('평면도 업로드'));
    await tester.pump();
    await tester.tap(find.byTooltip('작업도구'));
    await tester.pump();
  }

  testWidgets('좌측 시작 방식 선택 3가지가 모두 보인다', (tester) async {
    await pumpScreen(tester);

    // FINAL PROFESSIONAL UI RESTRUCTURE WO §3/§10 — Supabase 스타일로
    // 레일 항목마다 아이콘 아래 짧은 메뉴명이 항상 보인다(이전 WO099
    // 시절엔 hover 시 tooltip으로만 떴다). "평면도 업로드"는 그 상시
    // 레일 캡션 하나 + pumpScreen이 미리 펼쳐 둔 카드 자체의 제목까지
    // 합쳐 2번 보인다 — 나머지 둘은 아직 펼치지 않았으니 tooltip 존재로
    // 확인한다.
    expect(find.text('평면도 업로드'), findsNWidgets(2));
    expect(find.byTooltip('직접 그리기'), findsOneWidget);
    expect(find.byTooltip('사진으로 변환'), findsOneWidget);
  });

  testWidgets(
    'FINAL PROFESSIONAL UI RESTRUCTURE WO §4 — 좌측 상단에 SPACE SHIFT 브랜드(심볼+텍스트)가 보인다',
    (tester) async {
      await pumpScreen(tester);

      expect(find.byType(Image), findsWidgets);
      expect(find.text('SPACE\nSHIFT'), findsOneWidget);
    },
  );

  testWidgets(
    'FINAL PROFESSIONAL UI RESTRUCTURE WO §3/§20 — "프로젝트" 클릭 시 Sub Menu가 열려 '
    '현재 프로젝트 이름과 준비 중 항목을 보여주고, 다른 Main Menu를 클릭하면 닫힌다',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: FloorPlanWorkspaceScreen(projectName: '내 프로젝트')),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('프로젝트'));
      await tester.pump();

      expect(find.text('내 프로젝트'), findsOneWidget);
      expect(find.text('프로젝트 목록'), findsOneWidget);
      expect(find.text('새 프로젝트'), findsOneWidget);

      await tester.tap(find.text('프로젝트 목록'));
      await tester.pump();
      expect(find.textContaining('준비 중입니다'), findsOneWidget);

      // 다른 Main Menu("작업 목록")를 클릭하면 "프로젝트" Sub Menu는
      // 닫히고 그 내용으로 교체된다.
      await tester.tap(find.byTooltip('작업 목록'));
      await tester.pump();
      expect(find.text('내 프로젝트'), findsNothing);
    },
  );

  testWidgets(
    'FINAL PROFESSIONAL UI RESTRUCTURE WO §3/§20 — 좌측 Sub Menu가 열린 상태에서 중앙 '
    'Workspace를 클릭하면 자동으로 닫힌다',
    (tester) async {
      await pumpScreen(tester);

      // pumpScreen이 이미 "평면도 업로드" Sub Menu를 펼쳐 둔 상태다.
      expect(find.text('평면도 업로드'), findsNWidgets(2));

      // 중앙에 있을 수 있는 "파일 선택" 버튼 등 실제 인터랙티브 콘텐츠를
      // 건드리지 않도록, 캔버스 좌상단 모서리 근처의 빈 자리를 탭한다.
      await tester.tapAt(
        tester.getTopLeft(find.byType(WorkspaceCanvas)) + const Offset(4, 4),
      );
      await tester.pump();

      // Sub Menu가 닫혀 카드 제목("평면도 업로드")은 사라지고, 레일
      // 캡션 하나만 남는다.
      expect(find.text('평면도 업로드'), findsOneWidget);
    },
  );

  testWidgets('"직접 그리기"를 탭하면 준비중 안내만 보여주고 이 화면에 남는다', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byTooltip('직접 그리기'));
    await tester.pump();

    expect(find.textContaining('준비 중입니다'), findsOneWidget);
    expect(find.byType(FloorPlanWorkspaceScreen), findsOneWidget);
    expect(find.byType(PhotoSelectScreen), findsNothing);
  });

  testWidgets('"사진으로 변환"을 탭하면 기존 PhotoSelectScreen이 열리고, 뒤로가기로 돌아올 수 있다', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.tap(find.byTooltip('사진으로 변환'));
    await tester.pumpAndSettle();

    expect(find.byType(PhotoSelectScreen), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byType(FloorPlanWorkspaceScreen), findsOneWidget);
    expect(find.byType(PhotoSelectScreen), findsNothing);
  });

  testWidgets('실사용 진입 시 작업 목록/선택 항목이 비어 있다(demo 데이터가 섞이지 않는다)', (tester) async {
    await pumpScreen(tester);

    expect(find.text('선택된 항목이 없습니다.\n평면도에서 작업할 영역을 선택해주세요.'), findsOneWidget);
    expect(find.text('거실 벽 (TV 벽체)'), findsNothing);

    // WO099 UI COMPACT MODE — "작업 목록"은 이제 좌측 레일의 별도
    // 패널이다(평면도 업로드 패널과 같은 자리를 공유하므로 전환해야
    // 보인다).
    await tester.tap(find.byTooltip('작업 목록'));
    await tester.pump();
    expect(find.text('아직 등록된 작업이 없습니다.'), findsOneWidget);
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
    expect(find.text('AI 평면도 생성'), findsOneWidget);
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
    expect(find.text('AI 평면도 생성'), findsOneWidget);

    await tester.tap(find.text('3D 아이소'));
    await tester.pump();

    expect(find.text('3D 공간이 아직 생성되지 않았습니다'), findsOneWidget);
    // 3D View에서는 2D 전용 도면 분석/표시 설정 섹션 대신, 3D 단계
    // 안내가 우측 패널에 보인다(WO 22번).
    expect(find.text('AI 평면도 생성'), findsNothing);

    await tester.tap(find.text('2D 평면도'));
    await tester.pump();

    // 3D를 다녀왔어도 업로드한 파일 상태 자체는 그대로 남아있다.
    expect(find.text('AI 평면도 생성'), findsOneWidget);
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

    expect(find.byTooltip('설정'), findsOneWidget);
  });

  testWidgets('"설정"을 탭하면 SettingsScreen으로 진입하고, 뒤로가기로 이 화면으로 돌아온다', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.tap(find.byTooltip('설정'));
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

    await tester.tap(find.byTooltip('설정'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    // 설정 화면을 다녀와도 workspace의 State가 그대로 유지되어, 업로드한
    // 파일과 선택했던 View(3D 아이소)가 초기화되지 않는다.
    expect(find.text('3D 공간이 아직 생성되지 않았습니다'), findsOneWidget);
    await tester.tap(find.text('2D 평면도'));
    await tester.pump();

    // WO099 UI COMPACT MODE — "설정" 탭은 다른 좌측 패널처럼 열려 있던
    // 패널을 닫는다(§ _handleLeftRailTap). 파일 상태 자체(_floorPlanFile)는
    // 화면 전환과 무관하게 유지되지만, 그걸 보여주는 "평면도 업로드"
    // 패널은 설정을 다녀오며 접혔으므로 다시 펼쳐야 확인할 수 있다.
    await tester.tap(find.byTooltip('평면도 업로드'));
    await tester.pump();
    expect(find.textContaining('floor_plan_1.png'), findsWidgets);
  });

  testWidgets('AI 평면도 생성을 누르면 실제 단계 콜백을 따라 로딩 상태가 표시된다', (tester) async {
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

    await tester.tap(find.text('AI 평면도 생성'));
    await tester.pump();

    // V1 AI-IMAGE FLOW WO §8 — 내부 엔진 단계 이름 대신 하나의 단순한
    // 문구만 사용자에게 보여준다. 이 텍스트가 1단계에서도, fake 서비스가
    // 2단계로 넘어간 뒤에도 계속 보인다는 것으로 "로딩 상태가 실제 단계
    // 콜백을 따라간다"(가짜 timer가 아니다)를 확인한다.
    expect(find.textContaining('AI 평면도를 생성하는 중입니다'), findsOneWidget);

    // fake 서비스는 테스트가 명시적으로 완료시켜주기 전까지 1단계에
    // 머물러 있는다 — 실제로 "1단계 작업이 끝났을 때"만 2단계로
    // 넘어간다는 것을 보장하기 위함이다(가짜 timer로 흉내내지 않는다).
    analysisService.proceedToSecondStep();
    await tester.pump();
    expect(find.textContaining('AI 평면도를 생성하는 중입니다'), findsOneWidget);

    analysisService.finish();
    await tester.pumpAndSettle();
  });

  /// 여러 새 테스트가 공통으로 필요로 하는 "평면도 선택 → 분석 완료"
  /// 상태까지 진행한다.
  Future<_FakeFloorPlanAnalysisService> pumpAnalyzed(
    WidgetTester tester, {
    FloorPlanIsoImageGenerationService floorPlanIsoService =
        const UnavailableFloorPlanIsoImageService(),
  }) async {
    final analysisService = _FakeFloorPlanAnalysisService(
      const FloorPlanAnalysisOutcome.success(_fakeAnalysisResult),
    );
    await pumpScreen(
      tester,
      uploadService: _FakeFloorPlanUploadService([
        _fakeImageFile('floor_plan.png'),
      ]),
      analysisService: analysisService,
      floorPlanIsoService: floorPlanIsoService,
    );

    await tester.tap(find.widgetWithText(OutlinedButton, '파일 선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AI 평면도 생성'));
    await tester.pump();
    analysisService.proceedToSecondStep();
    analysisService.finish();
    await tester.pumpAndSettle();
    return analysisService;
  }

  /// 실기 FAIL 재수정 WO(11/12번) — "치수 보정" 모드에서 벽 구간을
  /// 실제로 press+drag+release해 선택하는 것을 재현한다.
  Future<void> dragOverWall(
    WidgetTester tester,
    Point2 fromNormalized,
    Point2 toNormalized,
  ) async {
    final overlayRect = tester.getRect(find.byType(CadFloorPlanOverlay));
    final transform = ContainFitTransform.compute(
      overlayRect.size,
      const Size(800, 600),
    );
    final from = overlayRect.topLeft + transform.mapNormalized(fromNormalized);
    final to = overlayRect.topLeft + transform.mapNormalized(toNormalized);
    final gesture = await tester.startGesture(from);
    await gesture.moveTo(to);
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('분석이 성공하면 GPT가 생성한 평면도 이미지가 표시되고, 번호 marker/작업 목록은 비어 있다', (
    tester,
  ) async {
    await pumpAnalyzed(tester);

    // V1 AI-IMAGE FLOW WO — 좌표 기반 CadFloorPlanOverlay는 더 이상
    // 기본(non-calibrating) 상태에서 그려지지 않는다. 대신 GPT가 새로
    // 그려준 평면도 이미지(_fakeGeneratedImageBytes, 원본과 다른 바이트)가
    // 화면에 그려진다.
    expect(find.byType(CadFloorPlanOverlay), findsNothing);
    expect(find.byType(FloorPlanAnalysisOverlay), findsNothing);
    final images = tester.widgetList<Image>(find.byType(Image));
    expect(
      images.any((img) => _imageShowsBytes(img, _fakeGeneratedImageBytes)),
      isTrue,
      reason: 'GPT가 생성한 평면도 이미지가 화면 어딘가에 그려져 있어야 한다',
    );

    // 분석 geometry는 사용자 작업이 아니므로, 분석 직후에도 "작업 목록"은
    // 여전히 0개다(WO 1/2번) — "외벽"/"내벽" 같은 작업 이름은 사용자가
    // 실제로 작업을 만들기 전까지 작업 목록에 나타나지 않는다.
    // GPT FLOORPLAN WO §7 — "공간 1" 등 공간별 크기 목록은 V1
    // production UI에서 제거됐다(우측 "평면도 준비 완료" 카드에는 더
    // 이상 표시되지 않는다) — 존재하지 않는 것이 이제 올바른 상태다.
    // WO099 UI COMPACT MODE — "작업 목록"은 좌측 레일의 별도 패널이다.
    await tester.tap(find.byTooltip('작업 목록'));
    await tester.pump();
    expect(find.text('아직 등록된 작업이 없습니다.'), findsOneWidget);
    expect(find.text('외벽'), findsNothing);
    expect(find.text('공간 1', skipOffstage: false), findsNothing);
    // 우측 패널 상단에 도면 분석 상태/표시 설정 섹션이 추가되어, 선택
    // 안내 카드가 스크롤 영역 아래로 밀려 화면 밖에 있을 수 있다 —
    // 존재 여부만 확인하므로 skipOffstage: false로 찾는다.
    expect(
      find.text('선택된 항목이 없습니다.\n평면도에서 작업할 영역을 선택해주세요.', skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('GPT 평면도 생성이 실패해도 화면은 죽지 않고 원본 사진을 정직하게 보여준다', (tester) async {
    final analysisService = _FakeFloorPlanAnalysisService(
      const FloorPlanAnalysisOutcome.success(_fakeAnalysisResult),
    );
    await pumpScreen(
      tester,
      uploadService: _FakeFloorPlanUploadService([
        _fakeImageFile('floor_plan.png'),
      ]),
      analysisService: analysisService,
      floorPlanImageService: const _FailingFloorPlanImageService(),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, '파일 선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AI 평면도 생성'));
    await tester.pump();
    analysisService.proceedToSecondStep();
    analysisService.finish();
    await tester.pumpAndSettle();

    // 생성된 이미지는 없고(실패), 원본 사진(_fakeImageBytes)이 그대로
    // 보인다 — 가짜로 성공한 것처럼 보이지 않는다.
    final images = tester.widgetList<Image>(find.byType(Image));
    expect(
      images.any((img) => _imageShowsBytes(img, _fakeImageBytes)),
      isTrue,
      reason: '생성 실패 시 원본 사진이 그대로 보여야 한다',
    );
    expect(images.any((img) => _imageShowsBytes(img, _fakeGeneratedImageBytes)), isFalse);
    expect(find.textContaining('AI 평면도 생성에 실패해 원본 이미지를 표시하고 있습니다'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
    await tester.tap(find.text('AI 평면도 생성'));
    await tester.pump();
    analysisService.proceedToSecondStep();
    analysisService.finish();
    await tester.pumpAndSettle();

    expect(find.textContaining('평면도 구조를 충분히 인식하지 못했습니다'), findsOneWidget);
    expect(find.byType(FloorPlanAnalysisOverlay), findsNothing);
    expect(find.textContaining('floor_plan.png'), findsWidgets);
    // WO099 UI COMPACT MODE — "작업 목록"은 좌측 레일의 별도 패널이다.
    await tester.tap(find.byTooltip('작업 목록'));
    await tester.pump();
    expect(find.text('아직 등록된 작업이 없습니다.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('2D 단순화 — 분석 직후 축척(문 기준 추정)/천장고(기본값)가 자동으로 '
      '채워져 있어, 기준점을 직접 찍지 않아도 곧바로 3D 아이소 만들기 버튼을 '
      '누를 수 있다(NOMPASS V2 WO — 실제 3D 렌더링 확인은 아래 참고)', (tester) async {
    // NOMPASS V2 WO(renderer architecture 교체) — 실기 화면은 이제
    // three_js(ANGLE 네이티브 GPU 렌더러, [Space3DViewGpuV2])를 쓴다.
    // 네이티브 texture/platform channel을 실제로 여는 위젯이라
    // flutter_test의 headless 바인딩에는 그 채널을 처리할 핸들러가 없어,
    // [ThreeJS]가 초기화 중 예약하는 타이머가 테스트 종료 후에도 남아
    // "A Timer is still pending" assertion으로 테스트 자체가 깨진다 —
    // 네이티브 GPU/텍스처 기반 위젯(platform view와 동일한 부류)을
    // widget test로 직접 mount하는 것 자체가 구조적으로 불가능하다는
    // 뜻이라, 이 테스트는 "생성 준비가 정상적으로 끝난다"까지만
    // 검증한다. 실제로 3D가 올바르게 그려지는지는 (1) SpaceSceneV2
    // geometry 단위 테스트(space_scene_builder_v2_test.dart 등, mesh
    // 데이터 자체를 검증)와 (2) Windows 실기 확인으로 검증한다 — "테스트
    // 숫자만 보고 완료 처리하지 않는다"는 지침과도 일치한다.
    await pumpAnalyzed(tester);

    // CANONICAL 2D CONFIRMATION → 3D PIPELINE WO §6 — 이제 3D는 "2D 공간
    // 확정"을 누르기 전까지 절대 만들 수 없다(AI/CV가 무엇을 찾았든
    // 상관없이 사용자가 확정한 draft만 3D의 유일한 입력이 되어야 한다는
    // acceptance criterion). 분석 직후에는 아직 미확정이라 버튼이
    // 비활성 상태다.
    await tester.tap(find.text('3D 아이소'));
    await tester.pump();

    final generateButtonBeforeConfirm = find.widgetWithText(
      ElevatedButton,
      '3D 아이소 만들기',
      skipOffstage: false,
    );
    await tester.ensureVisible(generateButtonBeforeConfirm);
    await tester.pumpAndSettle();
    expect(tester.widget<ElevatedButton>(generateButtonBeforeConfirm).onPressed, isNull);

    // "2D 공간 확정"을 눌러야 비로소 3D 아이소 만들기가 활성화된다.
    await tester.tap(find.text('2D 평면도'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('구조 확인/보정'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2D 공간 확정'));
    await tester.pumpAndSettle();

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
  });

  testWidgets('실기 FAIL 재수정 WO(11~14번) — "치수 보정"에서 벽 구간을 실제로 '
      'drag해서 선택하면 즉시 현재 추정 길이가 보이고, 실제 치수를 입력해 '
      '[치수 적용]하면 그 값으로 축척이 교체되어 "추정" 문구가 사라진다', (tester) async {
    await pumpAnalyzed(tester);

    // GPT FLOORPLAN WO §7 — "공간별 크기" 카드(추정 치수 문구를 보여주던
    // 곳)가 V1 production UI에서 제거되어, 분석 직후 화면 전체에서
    // "추정" 문구를 미리 찾는 전제는 더 이상 성립하지 않는다. 이
    // 테스트의 핵심은 아래 "치수 보정" drag 흐름이므로, 그 흐름 자체가
    // 실제로 만들어내는 "m (추정)" 문구(line 아래)로 검증을 이어간다.
    final calibrationButton = find.text('치수 보정', skipOffstage: false);
    await tester.ensureVisible(calibrationButton);
    await tester.pumpAndSettle();
    await tester.tap(calibrationButton);
    await tester.pumpAndSettle();

    // wall-ext-1: (0.05,0.05)~(0.95,0.05) 위를 따라 drag한다.
    await dragOverWall(
      tester,
      const Point2(0.2, 0.05),
      const Point2(0.7, 0.05),
    );

    // drag가 끝나자마자 "선택한 벽" + 현재 추정 길이가 보인다(WO 13번).
    expect(find.text('선택한 벽', skipOffstage: false), findsOneWidget);
    final approxLength = find.textContaining('m (추정)', skipOffstage: false);
    await tester.ensureVisible(approxLength);
    await tester.pumpAndSettle();
    expect(approxLength, findsOneWidget);

    final input = find.byType(TextField, skipOffstage: false);
    await tester.ensureVisible(input);
    await tester.pumpAndSettle();
    await tester.enterText(input, '3200');
    await tester.pumpAndSettle();
    final applyButton = find.widgetWithText(
      FilledButton,
      '치수 적용',
      skipOffstage: false,
    );
    await tester.ensureVisible(applyButton);
    await tester.pumpAndSettle();
    await tester.tap(applyButton);
    await tester.pumpAndSettle();

    // 실측값으로 교체된 뒤에는 치수 보정 모드가 자동으로 종료된다.
    // GPT FLOORPLAN WO §7 — 공간 크기(㎡) 옆 "(추정)" 표시는 그 UI
    // 자체(공간별 크기 카드)가 제거되어 더 이상 존재하지 않는다.
    expect(find.textContaining('㎡ (추정)', skipOffstage: false), findsNothing);
    expect(find.text('선택한 벽', skipOffstage: false), findsNothing);
  });

  testWidgets('실기 FAIL 재수정 WO(15번) — 벽 근처가 아닌 곳을 drag하면 실제 CadWall '
      '대신 두 점 사이 직선 거리로 폴백한다("선택한 구간"으로 표시)', (tester) async {
    await pumpAnalyzed(tester);

    final calibrationButton = find.text('치수 보정', skipOffstage: false);
    await tester.ensureVisible(calibrationButton);
    await tester.pumpAndSettle();
    await tester.tap(calibrationButton);
    await tester.pumpAndSettle();

    // 벽이 없는 빈 영역(중앙 부근)을 drag한다 — wall-ext-1(y=0.05)/
    // wall-int-1(x=0.5)에서 충분히 떨어진 지점.
    await dragOverWall(tester, const Point2(0.2, 0.5), const Point2(0.35, 0.6));

    expect(find.text('선택한 구간', skipOffstage: false), findsOneWidget);
  });

  // CANONICAL 2D CONFIRMATION → 3D PIPELINE WO §4/§6/§7 검증.
  //
  // 아래 테스트들은 "구조 확인/보정" 모드에서 벽/문/창을 추가·이동하는
  // 최소 편집 도구와, "2D 공간 확정" 전에는 3D를 만들 수 없고 확정 이후
  // draft를 다시 편집하면 재확정이 필요해지는 것을 검증한다.
  //
  // 실제 pointer 드래그/탭 시뮬레이션 대신 [CadFloorPlanOverlay]가 받는
  // 콜백(onAddWallDrag/onAddOpeningTap)을 직접 호출해 판정한다 — 이
  // 콜백들은 production과 완전히 같은 [CadWorkspaceCallbacks] 인스턴스에
  // 연결된 실제 화면 메서드이므로(위젯 자체를 새로 만들지 않는다), "탭이
  // 이 메서드를 부른다"는 배선은 그대로 검증하면서, Flutter test harness
  // 특유의 중첩 GestureDetector/Overlay 경쟁으로 인한 raw pointer 시뮬레이션
  // 불안정성(이 프로젝트의 다른 raw drag 테스트도 겪는 문제와 무관하게,
  // 새 구조 확인 모드에서 유독 재현되는 현상을 실측 확인함)을 피한다.
  // 실제 raw gesture 자체가 화면에서 동작하는지는 Windows 실기로
  // 별도 확인한다(최종 E2E).

  Future<void> enterStructureEditing(WidgetTester tester, {required String tool}) async {
    final toggle = find.text('구조 확인/보정', skipOffstage: false);
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    if (tool != '선택') {
      await tester.tap(find.text(tool, skipOffstage: false));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('구조 확인/보정 — 벽 추가 도구로 드래그하면 새 벽이 draft에 추가된다', (tester) async {
    await pumpAnalyzed(tester);
    await enterStructureEditing(tester, tool: '벽 추가');

    final overlay = tester.widget<CadFloorPlanOverlay>(find.byType(CadFloorPlanOverlay));
    expect(overlay.floorPlan.walls, hasLength(2));

    overlay.onAddWallDrag!(const Point2(0.15, 0.2), const Point2(0.25, 0.8));
    await tester.pumpAndSettle();

    final after = tester.widget<CadFloorPlanOverlay>(find.byType(CadFloorPlanOverlay)).floorPlan;
    expect(after.walls, hasLength(3));
    final newWall = after.walls.last;
    expect(newWall.source, CadElementSource.userCreated);
  });

  testWidgets('구조 확인/보정 — 문 추가 도구로 기존 벽 위를 탭하면 그 벽에 문이 붙는다', (tester) async {
    await pumpAnalyzed(tester);
    await enterStructureEditing(tester, tool: '문 추가');

    final overlay = tester.widget<CadFloorPlanOverlay>(find.byType(CadFloorPlanOverlay));
    expect(overlay.floorPlan.openings, hasLength(1)); // 분석이 이미 찾은 opening-1.

    // wall-int-1(x=0.5, y: 0.05~0.95) 위의 한 점.
    overlay.onAddOpeningTap!(const Point2(0.5, 0.3), OpeningType.door);
    await tester.pumpAndSettle();

    final after = tester.widget<CadFloorPlanOverlay>(find.byType(CadFloorPlanOverlay)).floorPlan;
    expect(after.openings, hasLength(2));
    final newOpening = after.openings.last;
    expect(newOpening.type, OpeningType.door);
    expect(newOpening.wallId, 'wall-int-1');
    expect(newOpening.source, CadElementSource.userCreated);
  });

  testWidgets('구조 확인/보정 — 벽과 무관한 위치를 탭하면 근거 없는 문/창을 만들지 않는다', (tester) async {
    await pumpAnalyzed(tester);
    await enterStructureEditing(tester, tool: '창 추가');

    final overlay = tester.widget<CadFloorPlanOverlay>(find.byType(CadFloorPlanOverlay));
    final before = overlay.floorPlan;

    // wall-ext-1(y=0.05)/wall-int-1(x=0.5) 어느 쪽에서도 충분히 먼 지점.
    overlay.onAddOpeningTap!(const Point2(0.1, 0.9), OpeningType.window);
    await tester.pumpAndSettle();

    final after = tester.widget<CadFloorPlanOverlay>(find.byType(CadFloorPlanOverlay)).floorPlan;
    expect(after.openings, hasLength(before.openings.length));
  });

  testWidgets('구조 확인/보정 — 문/창을 드래그하면 host wall 위로 투영되어 이동한다', (tester) async {
    await pumpAnalyzed(tester);
    await enterStructureEditing(tester, tool: '문 추가');
    final overlay1 = tester.widget<CadFloorPlanOverlay>(find.byType(CadFloorPlanOverlay));
    // opening-1은 이미 wall-int-1(x=0.5)에 연결되어 있지 않다(분석
    // 결과의 opening-1은 wallId가 없다) — host wall이 있는, 방금 만든
    // 문으로 이동을 검증한다.
    overlay1.onAddOpeningTap!(const Point2(0.5, 0.3), OpeningType.door);
    await tester.pumpAndSettle();
    final created = tester
        .widget<CadFloorPlanOverlay>(find.byType(CadFloorPlanOverlay))
        .floorPlan
        .openings
        .last;
    expect(created.wallId, 'wall-int-1');

    final overlay2 = tester.widget<CadFloorPlanOverlay>(find.byType(CadFloorPlanOverlay));
    // wall-int-1 위 다른 위치로 "드래그"(host wall 밖의 점을 줘도 투영되어야 한다).
    overlay2.onOpeningMoved!(created.id, const Point2(0.6, 0.6));
    await tester.pumpAndSettle();

    final moved = tester
        .widget<CadFloorPlanOverlay>(find.byType(CadFloorPlanOverlay))
        .floorPlan
        .openings
        .firstWhere((o) => o.id == created.id);
    // wall-int-1은 x=0.5 고정 수직선이므로, 벽 밖의 점(0.6,0.6)을 줘도
    // 투영된 x는 항상 0.5여야 한다(허공에 뜨지 않는다).
    expect(moved.center.x, closeTo(0.5, 1e-9));
    expect(moved.center.y, closeTo(0.6, 1e-9));
    expect(moved.edited, isTrue);
  });

  testWidgets('CANONICAL 2D CONFIRMATION §7 — 확정 후 draft를 편집하면 재확정이 필요해진다', (
    tester,
  ) async {
    await pumpAnalyzed(tester);
    await enterStructureEditing(tester, tool: '선택');

    await tester.tap(find.text('2D 공간 확정', skipOffstage: false));
    await tester.pumpAndSettle();

    await tester.tap(find.text('3D 아이소'));
    await tester.pump();
    var generateButton = find.widgetWithText(ElevatedButton, '3D 아이소 만들기', skipOffstage: false);
    await tester.ensureVisible(generateButton);
    await tester.pumpAndSettle();
    expect(tester.widget<ElevatedButton>(generateButton).onPressed, isNotNull);

    // 2D로 돌아가 문을 하나 추가한다(draft 편집) — 확정은 이제 무효.
    // (이미 구조 확인/보정 모드는 켜져 있으므로 다시 토글하지 않는다 —
    // toggle 버튼은 on/off를 뒤집으므로 두 번 부르면 꺼져 버린다.)
    await tester.tap(find.text('2D 평면도'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('문 추가', skipOffstage: false));
    await tester.pumpAndSettle();
    final overlay = tester.widget<CadFloorPlanOverlay>(find.byType(CadFloorPlanOverlay));
    overlay.onAddOpeningTap!(const Point2(0.5, 0.3), OpeningType.door);
    await tester.pumpAndSettle();

    await tester.tap(find.text('3D 아이소'));
    await tester.pump();
    generateButton = find.widgetWithText(ElevatedButton, '3D 아이소 만들기', skipOffstage: false);
    await tester.ensureVisible(generateButton);
    await tester.pumpAndSettle();
    expect(tester.widget<ElevatedButton>(generateButton).onPressed, isNull);
  });

  testWidgets(
    '선택 기반 Property System WO §5/§6 — 벽을 선택해 "작업으로 추가"하면 '
    '선택 강조가 유지된 채 실제 편집 가능한 속성 패널(WorkTab)이 곧바로 보이고, '
    '같은 벽을 다시 선택하면 매번 새 작업을 만들지 않고 곧바로 그 작업으로 이동한다',
    (tester) async {
      await pumpAnalyzed(tester);
      await enterStructureEditing(tester, tool: '선택');

      var overlay = tester.widget<CadFloorPlanOverlay>(find.byType(CadFloorPlanOverlay));
      overlay.onSelect('wall-ext-1');
      await tester.pumpAndSettle();

      // 선택 직후에는 아직 사용자 작업이 아니라 "작업으로 추가" 안내다.
      expect(find.text('선택된 도면 요소', skipOffstage: false), findsOneWidget);
      expect(find.byType(WorkTab, skipOffstage: false), findsNothing);

      final addButton = find.widgetWithText(
        FilledButton,
        '작업으로 추가',
        skipOffstage: false,
      );
      await tester.ensureVisible(addButton);
      await tester.pumpAndSettle();
      await tester.tap(addButton);
      await tester.pumpAndSettle();

      // 작업으로 추가한 직후 실제 편집 가능한 속성 패널(WorkTab)이 곧바로
      // 보이고, 캔버스의 선택 강조(overlay.selectedId)는 사라지지 않는다
      // ("선택된 대상은 사용자가 즉시 알아볼 수 있어야 한다").
      expect(find.byType(WorkTab, skipOffstage: false), findsOneWidget);
      overlay = tester.widget<CadFloorPlanOverlay>(find.byType(CadFloorPlanOverlay));
      expect(overlay.selectedId, 'wall-ext-1');

      // 다른 벽으로 선택을 옮기면 그 벽은 아직 작업이 아니므로 다시
      // 안내 화면으로 돌아간다.
      overlay.onSelect('wall-int-1');
      await tester.pumpAndSettle();
      expect(find.byType(WorkTab, skipOffstage: false), findsNothing);

      // 원래 벽을 다시 선택하면, 이미 그 벽에서 만든 작업이 있으므로
      // "작업으로 추가"를 다시 누를 필요 없이 곧바로 같은 작업(WorkTab)
      // 으로 돌아간다 — 매번 새 작업이 중복 생성되지 않는다.
      overlay = tester.widget<CadFloorPlanOverlay>(find.byType(CadFloorPlanOverlay));
      overlay.onSelect('wall-ext-1');
      await tester.pumpAndSettle();
      expect(find.byType(WorkTab, skipOffstage: false), findsOneWidget);
    },
  );

  testWidgets(
    '구조 확인/보정 중 치수 보정을 켜면 두 모드가 동시에 켜지지 않고 배타적으로 전환된다',
    (tester) async {
      // 실기 E2E에서 발견: "구조 확인/보정"을 켠 뒤 "치수 보정"을 누르면
      // 기존에는 _calibrating만 세워지고 _structureEditing이 꺼지지 않아
      // 오버레이가 calibrating 분기로 넘어가며 add-wall/tap-select 제스처를
      // 조용히 가로챘다. 두 토글은 서로 배타적이어야 한다.
      await pumpAnalyzed(tester);
      await enterStructureEditing(tester, tool: '선택');

      var overlay = tester.widget<CadFloorPlanOverlay>(find.byType(CadFloorPlanOverlay));
      expect(overlay.structureEditing, isTrue);
      expect(overlay.calibrating, isFalse);

      await tester.tap(find.text('치수 보정', skipOffstage: false));
      await tester.pumpAndSettle();

      overlay = tester.widget<CadFloorPlanOverlay>(find.byType(CadFloorPlanOverlay));
      expect(overlay.calibrating, isTrue);
      expect(overlay.structureEditing, isFalse);
      expect(find.text('벽 추가', skipOffstage: false), findsNothing);
    },
  );
}
