// SS CAD TEST WorkOrder(1차 CAD/DXF E2E) §9 — "DXF 내보내기 전에 CAD
// 상태를 사용자에게 명확히 보여준다." GPT 구조 분석 성공 후 실제 화면에
// "DXF 내보내기 전 CAD 상태" 요약(구조/실측 축척 여부/확인 필요 요소)이
// 나타나는지 확인한다.

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

class _FakeFloorPlanUploadService extends FloorPlanUploadService {
  _FakeFloorPlanUploadService(this._file);
  final FloorPlanFile _file;

  @override
  Future<FloorPlanFile?> pickFloorPlanFile() async => _file;
}

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
  testWidgets('GPT 구조 분석 성공 후 DXF 내보내기 전 CAD 상태 요약이 실제로 보인다', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final imageBytes = buildImage2Png();
    final floorPlanFile = FloorPlanFile(
      fileName: 'image2.png',
      extension: 'png',
      kind: FloorPlanFileKind.image,
      sizeBytes: imageBytes.length,
      bytes: imageBytes,
    );

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

    await tester.tap(find.widgetWithText(OutlinedButton, '파일 선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AI 평면도 생성'));
    await tester.pumpAndSettle();

    // "AI 평면도 생성"(기준 픽셀 엔진, 이 테스트에서는 벽 0개) 직후에도
    // CadFloorPlan 자체는 이미 존재하므로 요약이 보이지만, 아직 구조
    // 분석 전이라 "벽 0개"여야 한다.
    expect(find.text('DXF 내보내기 전 CAD 상태'), findsOneWidget);
    expect(find.textContaining('구조: 벽 0개'), findsOneWidget);

    await tester.tap(find.text('GPT 구조 분석 실행'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('DXF 내보내기 전 CAD 상태'), findsOneWidget);
    expect(
      find.textContaining('구조: 벽 0개'),
      findsNothing,
      reason: 'GPT 구조 분석 성공 후에는 pixel_wall_v4가 검출한 실제 벽 개수로 바뀌어야 한다',
    );
    expect(
      find.textContaining('실측 축척 미확정'),
      findsOneWidget,
      reason: '치수 보정을 하지 않았으므로 축척은 아직 미확정 상태여야 한다',
    );
  });
}
