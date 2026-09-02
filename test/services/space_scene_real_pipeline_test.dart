// 3D 근본 수정 WO(1/5번) — "테스트용 단순 사각형만 보지 말고, 실제
// 업로드된 CAD 결과와 동일한 복잡한 wall geometry에서 재현"하라는 지시에
// 따라, 실제 CV 파이프라인(이미지 디코드 → Otsu 이진화 → run-length 벽
// 검출 → flood-fill 방 검출) 전체를 다중 방(4개) + 십자형 내벽 교차가
// 있는 합성 평면도로 실행하고, 그 결과를 그대로 buildCadFloorPlan →
// buildSpaceScene까지 통과시켜 실제 렌더링 직전 geometry를 검증한다.
//
// 사용자가 업로드한 원본 파일은 가지고 있지 않으므로(저작권/개인정보
// 문제로 커밋 대상이 아님) 가장 현실적인 대체재로, 다중 방 + 벽 교차부
// (T자/십자) 라는 실제 복잡도를 가진 평면도를 여기서 직접 합성한다 —
// 사각형 하나짜리 테스트로는 이번 사고를 놓친다는 것이 이미 확인됐다.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/services/floor_plan_analysis_engine.dart';
import 'package:ason_space/services/space_scene_builder.dart';

Uint8List _encodePng(img.Image image) =>
    Uint8List.fromList(img.encodePng(image));

/// 600x450 흰 배경 + 두께 10px 검은 테두리(외벽) + 십자형 내벽(x=295~305,
/// y=220~230) — 방 4개(quadrant)가 생기는 실제 다중 방 평면도.
Uint8List _buildFourRoomFloorPlan() {
  final image = img.Image(width: 600, height: 450);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  final black = img.ColorRgb8(0, 0, 0);

  img.fillRect(image, x1: 20, y1: 20, x2: 580, y2: 30, color: black); // top
  img.fillRect(
    image,
    x1: 20,
    y1: 420,
    x2: 580,
    y2: 430,
    color: black,
  ); // bottom
  img.fillRect(image, x1: 20, y1: 20, x2: 30, y2: 430, color: black); // left
  img.fillRect(image, x1: 570, y1: 20, x2: 580, y2: 430, color: black); // right

  // 십자형 내벽 — 4개 quadrant 방을 만든다.
  img.fillRect(image, x1: 295, y1: 20, x2: 305, y2: 430, color: black);
  img.fillRect(image, x1: 20, y1: 220, x2: 580, y2: 230, color: black);

  return _encodePng(image);
}

void main() {
  test('Stage E 대체 — 다중 방(4개) + 십자형 내벽 실제 파이프라인 결과에는 '
      '비정상(거대) geometry가 하나도 없다', () {
    final wallStage = detectWallsAndOpenings(
      WallStageInput(_buildFourRoomFloorPlan()),
    );
    expect(wallStage.isSuccess, isTrue);
    final roomStage = detectRooms(
      RoomStageInput(
        mask: wallStage.mask!,
        width: wallStage.analysisWidthPx,
        height: wallStage.analysisHeightPx,
      ),
    );
    // 실제 4개 quadrant 방이 검출돼야 이 테스트가 의미 있는 복잡도를
    // 갖췄다고 볼 수 있다.
    expect(roomStage.rooms.length, greaterThanOrEqualTo(4));

    final result = FloorPlanAnalysisResult(
      sourceWidthPx: wallStage.sourceWidthPx,
      sourceHeightPx: wallStage.sourceHeightPx,
      walls: wallStage.walls,
      openings: wallStage.openings,
      rooms: roomStage.rooms,
      warnings: const [],
      debugStats: FloorPlanAnalysisDebugStats(
        sourceWidthPx: wallStage.sourceWidthPx,
        sourceHeightPx: wallStage.sourceHeightPx,
        analysisWidthPx: wallStage.analysisWidthPx,
        analysisHeightPx: wallStage.analysisHeightPx,
        rawHorizontalRuns: wallStage.rawHorizontalRuns,
        rawVerticalRuns: wallStage.rawVerticalRuns,
        mergedWallCount: wallStage.walls.length,
        roomCandidateCount: roomStage.rooms.length,
        openingCandidateCount: wallStage.openings.length,
        durationMs: 0,
      ),
    );

    final plan = buildCadFloorPlan(result);
    final scale = resolveAutoScale(plan, null);
    final scene = buildSpaceScene(
      plan: plan,
      scale: scale,
      ceilingHeightMm: 2400,
    );

    expect(scene.isEmpty, isFalse);
    expect(
      scene.warnings.where((w) => w.contains('비정상 geometry')),
      isEmpty,
      reason:
          '실제 파이프라인 결과에서 비정상 geometry가 제외됐다면 그 '
          '자체가 여전히 남아 있는 버그다: ${scene.warnings}',
    );

    // 벽 표면에 "거대한 삼각형"이 없다는 것을 직접 재확인 — scene의
    // 실제 최대 크기(대각선)를 기준으로, 어떤 삼각형의 변도 그
    // 대각선을 과도하게 넘지 않아야 한다.
    final sceneDiagonal = (scene.maxBounds - scene.minBounds).length;
    for (final tri in scene.triangles) {
      final ab = (tri.b - tri.a).length;
      final bc = (tri.c - tri.b).length;
      final ca = (tri.a - tri.c).length;
      final longest = [ab, bc, ca].reduce((a, b) => a > b ? a : b);
      expect(
        longest,
        lessThanOrEqualTo(sceneDiagonal * 1.01),
        reason:
            '${tri.sourceKind}:${tri.sourceId} 삼각형의 변(${longest}mm)이 '
            'scene 전체 대각선(${sceneDiagonal}mm)보다 길다 — 거대 삼각형.',
      );
    }
  });
}
