// SpaceScene V2 — Stage E(복잡한 synthetic apartment) / Stage F(실제 CV
// pipeline proxy) 검증(WO 16번). [space_scene_real_pipeline_test.dart]
// (V1)과 같은 합성 평면도(4개 quadrant 방 + 십자형 내벽)를 실제
// detectWallsAndOpenings → detectRooms → buildCadFloorPlan →
// buildSpaceSceneV2까지 그대로 통과시켜, V2 pipeline에서도 거대
// 삼각형/비정상 geometry가 없는지 확인한다. V1 파일을 import하지 않고
// 독립적으로 존재한다(NOMPASS V2 WO — "병렬 pipeline은 서로의 테스트도
// 공유하지 않는다").
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/services/floor_plan_analysis_engine.dart';
import 'package:ason_space/services/space_scene_builder_v2.dart';

Uint8List _encodePng(img.Image image) =>
    Uint8List.fromList(img.encodePng(image));

/// 600x450 흰 배경 + 두께 10px 검은 테두리(외벽) + 십자형 내벽 — 방
/// 4개(quadrant)가 생기는 실제 다중 방 평면도([space_scene_real_pipeline_test.dart]
/// 와 동일한 합성 도면).
Uint8List _buildFourRoomFloorPlan() {
  final image = img.Image(width: 600, height: 450);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  final black = img.ColorRgb8(0, 0, 0);

  img.fillRect(image, x1: 20, y1: 20, x2: 580, y2: 30, color: black);
  img.fillRect(image, x1: 20, y1: 420, x2: 580, y2: 430, color: black);
  img.fillRect(image, x1: 20, y1: 20, x2: 30, y2: 430, color: black);
  img.fillRect(image, x1: 570, y1: 20, x2: 580, y2: 430, color: black);
  img.fillRect(image, x1: 295, y1: 20, x2: 305, y2: 430, color: black);
  img.fillRect(image, x1: 20, y1: 220, x2: 580, y2: 230, color: black);

  return _encodePng(image);
}

void main() {
  test('Stage E/F — 다중 방(4개) + 십자형 내벽 실제 파이프라인 결과에는 V2에서도 '
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
    final scene = buildSpaceSceneV2(
      plan: plan,
      scale: scale,
      ceilingHeightMm: 2400,
    );

    expect(scene.isEmpty, isFalse);
    expect(scene.wallMeshes, isNotEmpty);
    expect(scene.floorMeshes.length, greaterThanOrEqualTo(4));
    expect(
      scene.warnings.where((w) => w.contains('비정상 geometry')),
      isEmpty,
      reason:
          '실제 파이프라인 결과에서 비정상 geometry가 제외됐다면 그 자체가 여전히 남아 있는 버그다: ${scene.warnings}',
    );

    final sceneDiagonal = (scene.maxBounds - scene.minBounds).length;
    final allTriangles = scene.wallMeshes
        .expand((w) => w.triangles)
        .followedBy(scene.floorMeshes.expand((f) => f.triangles));
    for (final tri in allTriangles) {
      final ab = (tri.b - tri.a).length;
      final bc = (tri.c - tri.b).length;
      final ca = (tri.a - tri.c).length;
      final longest = [ab, bc, ca].reduce((a, b) => a > b ? a : b);
      expect(
        longest,
        lessThanOrEqualTo(sceneDiagonal * 1.01),
        reason:
            '삼각형의 변(${longest}mm)이 scene 전체 대각선(${sceneDiagonal}mm)보다 길다 — 거대 삼각형.',
      );
    }
  });
}
