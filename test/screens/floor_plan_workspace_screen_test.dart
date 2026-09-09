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

/// Clean 2D 이미지와도 구분되는 세 번째 1x1 PNG(초록 픽셀) — "GPT가
/// 새로 그려준 3D 아이소 이미지가 Clean 2D와 혼동되지 않고 실제로
/// 화면에 보이는가"를 확실히 구분해서 검증하기 위함이다.
final Uint8List _fakeIsoImageBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAAXNSR0IArs4c6QAAAARnQU1B'
  'AACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAANSURBVBhXY+A6wfUfAAOYAdyk2jRL'
  'AAAAAElFTkSuQmCC',
);

/// V1 GPT CAD-STYLE 2D → GPT ISO IMAGE FLOW WO — 실제 네트워크 호출 없이
/// "GPT가 Clean 2D를 기반으로 3D 아이소 이미지를 생성해 돌려준다"를
/// 흉내내는 가짜 서비스. [_FakeFloorPlanAnalysisService]와 같은 이유로
/// Completer를 쓴다 — 진짜 delay 없이 바로 완료되면 "생성 중" 중간
/// 상태를 테스트가 관찰할 기회 자체가 없어진다(await가 낀 테스트 코드
/// 자체가 microtask를 먼저 흘려보내 버린다).
class _FakeFloorPlanIsoImageService implements FloorPlanIsoImageGenerationService {
  _FakeFloorPlanIsoImageService();

  final Completer<Uint8List> _completer = Completer<Uint8List>();

  void finish() => _completer.complete(_fakeIsoImageBytes);

  @override
  Future<Uint8List> generate(Uint8List cleanTwoDImageBytes) => _completer.future;
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

  testWidgets('V1 GPT CAD-STYLE 2D → GPT ISO IMAGE FLOW WO §7/§9 — "3D 아이소 '
      '만들기"를 누르면 생성 중 안내가 먼저 보이고, GPT가 만들어준 아이소 '
      '이미지가 그대로 화면에 표시된다(네이티브 GPU 3D 위젯은 전혀 '
      '마운트되지 않아 flutter_test에서도 끝까지 검증할 수 있다)', (tester) async {
    final isoService = _FakeFloorPlanIsoImageService();
    await pumpAnalyzed(tester, floorPlanIsoService: isoService);

    await tester.tap(find.text('3D 아이소'));
    await tester.pump();

    final generateButton = find.widgetWithText(
      ElevatedButton,
      '3D 아이소 만들기',
      skipOffstage: false,
    );
    await tester.ensureVisible(generateButton);
    await tester.pumpAndSettle();

    await tester.tap(generateButton);
    await tester.pump();
    expect(find.text('3D 아이소 생성 중입니다...'), findsOneWidget);

    // _FakeFloorPlanAnalysisService와 같은 이유로 Completer를 직접
    // 완료시켜, "생성 중" 상태가 실제로 끝나고 결과 이미지로
    // 바뀌는 전환을 결정론적으로 관찰한다(가짜 timer가 아니다).
    isoService.finish();
    await tester.pumpAndSettle();

    final generatedIsoImage = find.byWidgetPredicate(
      (widget) => widget is Image && _imageShowsBytes(widget, _fakeIsoImageBytes),
    );
    expect(generatedIsoImage, findsOneWidget);
    expect(find.text('2D 평면도로 돌아가기'), findsOneWidget);
    expect(find.text('3D 아이소 생성 중입니다...'), findsNothing);
    expect(tester.takeException(), isNull);
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
}
