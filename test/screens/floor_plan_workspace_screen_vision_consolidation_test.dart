// SS CAD TEST — "GPT 구조 분석 실행" 버튼의 실제 화면 동작 회귀 테스트.
//
// 배경: 실제 Windows 앱에서 이 버튼을 누르면 "GPT 구조 분석에 실패했습니다.
// 잠시 후 다시 시도해주세요."만 보이고, 그 뒤에 어떤 실제 예외가 있었는지
// 알 방법이 없었다. 원인을 추적해보면 --dart-define=GPT_FLOORPLAN_EDGE_
// FUNCTION_URL 없이 실행하면 (안전한 설계상) 항상 즉시 실패하도록 되어
// 있는데, 이 실패 자체는 정상 동작이지만 그 원인이 무엇이든(설정 누락,
// 네트워크 오류, 서버 오류) 화면에서 절대 구분할 수 없었고, 이 버튼의
// "성공" 경로는 위젯 테스트로 단 한 번도 검증된 적이 없었다 — 실사용
// 경로가 이 화면 안에서 직접 값을 생성해, 테스트가 주입할 지점이 아예
// 없었기 때문이다.
//
// SS CAD TEST WorkOrder(1차 CAD/DXF E2E) §4/§5 — 실사용 구현이
// VisionGuidedSpatialModelBuilder(HintedGeometryExtractor)에서
// pixel_wall_v4 + LiveSemanticProvider("AI=의미, SS=좌표검증")로 바뀌었다.
// 이 파일은 그 주입 지점(FloorPlanWorkspaceScreen.gptStructureAnalysis —
// 이미지 바이트를 받아 CadFloorPlan을 돌려주는 함수 하나)을 사용해 두
// 경로를 모두 실제 화면(버튼 tap)으로 검증한다:
//   A. 실패해도 기존 안내 메시지 SnackBar는 그대로 보여야 한다(회귀 방지).
//   B. 성공하면 실제로 CadFloorPlan이 채워져 "DXF 내보내기" 버튼이
//      눌러지는 상태가 되어야 한다(이 버튼이 실제로 사용자에게 CAD
//      결과를 만들어 주는지 검증).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/models/floor_plan_file.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/screens/floor_plan_workspace_screen.dart';
import 'package:ason_space/services/floor_plan_analysis_service.dart';
import 'package:ason_space/services/floor_plan_upload_service.dart';
import 'package:ason_space/services/mock_vision_interpretation_service.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/live_semantic_provider.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_pipeline.dart';
import 'package:ason_space/vision_cad_poc/sample_image2_fixture.dart';
import 'package:ason_space/widgets/workspace/cad_floor_plan_overlay.dart';

/// 실제 플랫폼 파일 선택창 대신, 이미 준비된 평면도 파일을 즉시 돌려준다.
class _FakeFloorPlanUploadService extends FloorPlanUploadService {
  _FakeFloorPlanUploadService(this._file);
  final FloorPlanFile _file;

  @override
  Future<FloorPlanFile?> pickFloorPlanFile() async => _file;
}

/// "GPT 구조 분석 실행" 버튼은 "① 평면도 업로드"만으로는 나타나지 않고,
/// [FloorPlanAnalysisPhase.completed]에 도달한 뒤에야 나타난다(실제 화면도
/// 마찬가지 — "AI 평면도 생성"을 먼저 거쳐야 한다). 이 테스트는 그 첫
/// 단계의 실제 결과 내용과는 무관하므로, 실제 CV 파이프라인 대신 즉시
/// completed로 넘어가는 최소한의 가짜 결과를 돌려준다.
class _ImmediateFloorPlanAnalysisService extends FloorPlanAnalysisService {
  const _ImmediateFloorPlanAnalysisService();

  @override
  Future<FloorPlanAnalysisOutcome> analyze(
    FloorPlanFile file, {
    void Function(FloorPlanAnalysisStep step)? onStep,
  }) async {
    return const FloorPlanAnalysisOutcome.success(
      FloorPlanAnalysisResult(
        sourceWidthPx: kImage2Width,
        sourceHeightPx: kImage2Height,
        walls: [],
        openings: [],
        rooms: [],
        warnings: [],
        debugStats: FloorPlanAnalysisDebugStats(
          sourceWidthPx: kImage2Width,
          sourceHeightPx: kImage2Height,
          analysisWidthPx: kImage2Width,
          analysisHeightPx: kImage2Height,
          rawHorizontalRuns: 0,
          rawVerticalRuns: 0,
          mergedWallCount: 0,
          roomCandidateCount: 0,
          openingCandidateCount: 0,
          durationMs: 1,
        ),
      ),
    );
  }
}

void main() {
  final imageBytes = buildImage2Png();
  final floorPlanFile = FloorPlanFile(
    fileName: 'image2.png',
    extension: 'png',
    kind: FloorPlanFileKind.image,
    sizeBytes: imageBytes.length,
    bytes: imageBytes,
  );

  /// "① 평면도 업로드" -> "AI 평면도 생성"까지 실제로 눌러
  /// [FloorPlanAnalysisPhase.completed]에 도달한다 — "GPT 구조 분석 실행"
  /// 버튼은 이 상태에서만 화면에 나타난다(실제 앱과 동일한 순서).
  Future<void> uploadFloorPlanAndCompleteFirstAnalysis(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(OutlinedButton, '파일 선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AI 평면도 생성'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'GPT 구조 분석이 실패하면(설정 누락/네트워크 오류 등) 기존 안내 메시지를 보여주고 CAD는 비어 있는 채로 남는다',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: FloorPlanWorkspaceScreen(
            uploadService: _FakeFloorPlanUploadService(floorPlanFile),
            analysisService: const _ImmediateFloorPlanAnalysisService(),
            gptStructureAnalysis: (bytes) async {
              throw Exception('GPT 평면도 분석 기능이 아직 설정되지 않았습니다.');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await uploadFloorPlanAndCompleteFirstAnalysis(tester);

      expect(find.text('GPT 구조 분석 실행'), findsOneWidget);
      // 기준 픽셀 분석([_ImmediateFloorPlanAnalysisService])이 벽 0개를
      // 돌려주므로, GPT 구조 분석 전에는 화면에 CAD 초안이 그려지지
      // 않는다.
      expect(find.byType(CadFloorPlanOverlay), findsNothing);

      await tester.tap(find.text('GPT 구조 분석 실행'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(
        find.text('GPT 구조 분석에 실패했습니다. 잠시 후 다시 시도해주세요.'),
        findsOneWidget,
        reason: '실패 원인이 무엇이든 사용자에게는 기존과 동일한 안내가 보여야 한다(회귀 방지)',
      );
      expect(
        find.byType(CadFloorPlanOverlay),
        findsNothing,
        reason: '실패했으면 화면에 CAD 초안이 새로 나타나면 안 된다(이전 상태 그대로 유지)',
      );
    },
  );

  testWidgets(
    'GPT 구조 분석이 성공하면 실제로 구조화된 CAD 결과가 생성되어 DXF 내보내기가 가능해진다',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: FloorPlanWorkspaceScreen(
            uploadService: _FakeFloorPlanUploadService(floorPlanFile),
            analysisService: const _ImmediateFloorPlanAnalysisService(),
            gptStructureAnalysis: (bytes) async {
              final pipelineResult = await runPixelWallPipelineWithSemanticProvider(
                imageBytes: bytes,
                provider: const LiveSemanticProvider(MockVisionInterpretationService()),
              );
              return buildCadFloorPlanFromSpatialModel(pipelineResult.model);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await uploadFloorPlanAndCompleteFirstAnalysis(tester);

      await tester.tap(find.text('GPT 구조 분석 실행'));
      // 3회 통합 호출이 전부 끝날 때까지 실제로 await한다(가짜 timer가
      // 아니라 buildConsolidatedVisionCadFloorPlan이 실제로 3번 실행되는
      // 진짜 비동기 작업이다).
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      expect(
        find.text('GPT 구조 분석에 실패했습니다. 잠시 후 다시 시도해주세요.'),
        findsNothing,
        reason: '성공했으면 실패 SnackBar가 보이면 안 된다',
      );
      final exportButtonAfter = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'DXF 내보내기'),
      );
      expect(exportButtonAfter.onPressed, isNotNull);
      expect(
        tester.widget<CadFloorPlanOverlay>(find.byType(CadFloorPlanOverlay)).floorPlan.walls,
        isNotEmpty,
        reason:
            'GPT 구조 분석 성공 -> 실제 pixel_wall_v4 geometry + LiveSemanticProvider'
            '(MockVisionInterpretationService)를 거친 CadFloorPlan이 화면에 반영되어야 한다',
      );
    },
  );
}
