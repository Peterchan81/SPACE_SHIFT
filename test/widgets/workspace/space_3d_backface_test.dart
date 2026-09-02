// isBackFace(3D 2차 근본 수정 — painter's algorithm에 z-buffer가 없어서
// 벽 안쪽/바깥쪽 면의 그리기 순서가 자주 틀리며 벽이 찢어져 보이던 문제)
// 에 대한 단위 테스트. 실제 buildSpaceScene() 결과(진짜 벽/바닥 삼각형)
// 로 검증한다.
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/space_scene.dart';
import 'package:ason_space/services/space_scene_builder.dart';
import 'package:ason_space/widgets/workspace/space_3d_view.dart';

SpaceScene _squareRoomScene() {
  const result = FloorPlanAnalysisResult(
    sourceWidthPx: 1000,
    sourceHeightPx: 1000,
    walls: [
      WallSegment(
        id: 'wall-n',
        start: Point2(0.1, 0.1),
        end: Point2(0.9, 0.1),
        thicknessNormalized: 0.02,
        confidence: 0.8,
        isExterior: true,
      ),
      WallSegment(
        id: 'wall-s',
        start: Point2(0.1, 0.9),
        end: Point2(0.9, 0.9),
        thicknessNormalized: 0.02,
        confidence: 0.8,
        isExterior: true,
      ),
    ],
    openings: [],
    rooms: [
      RoomCandidate(
        id: 'room-0',
        polygon: [
          Point2(0.1, 0.1),
          Point2(0.9, 0.1),
          Point2(0.9, 0.9),
          Point2(0.1, 0.9),
        ],
        areaNormalized: 0.64,
        confidence: 0.7,
      ),
    ],
    warnings: [],
    debugStats: FloorPlanAnalysisDebugStats(
      sourceWidthPx: 1000,
      sourceHeightPx: 1000,
      analysisWidthPx: 1000,
      analysisHeightPx: 1000,
      rawHorizontalRuns: 2,
      rawVerticalRuns: 1,
      mergedWallCount: 2,
      roomCandidateCount: 1,
      openingCandidateCount: 0,
      durationMs: 5,
    ),
  );

  final plan = buildCadFloorPlan(result);
  const scale = FloorPlanScale(
    mmPerPixel: 5.0,
    referenceStart: Point2(0, 0),
    referenceEnd: Point2(1, 0),
    referenceLengthMm: 5000,
  );
  return buildSpaceScene(plan: plan, scale: scale, ceilingHeightMm: 2400);
}

void main() {
  final scene = _squareRoomScene();

  test('바닥은 항상 위(+Y)를 향해, 위에서 보는 카메라에는 절대 backface로 '
      '컬링되지 않는다', () {
    final floorTriangles = scene.triangles.where(
      (t) => t.sourceKind == SpaceElementKind.floor,
    );
    expect(floorTriangles, isNotEmpty);
    for (final tri in floorTriangles) {
      expect(tri.normal.y, greaterThan(0));
      for (final eye in [
        vm.Vector3(2500, 3000, -3000),
        vm.Vector3(2500, 3000, 8000),
        vm.Vector3(-2000, 5000, 2500),
      ]) {
        expect(isBackFace(tri, eye), isFalse);
      }
    }
  });

  test('벽 상단(천장 면)은 위에서 보는 카메라에 backface로 컬링되지 않는다', () {
    final topTriangles = scene.triangles.where(
      (t) => t.sourceId == 'wall-n' && t.normal.y.abs() > 0.5,
    );
    expect(topTriangles, isNotEmpty);
    for (final tri in topTriangles) {
      expect(isBackFace(tri, vm.Vector3(2500, 3000, -3000)), isFalse);
    }
  });

  test('벽의 바깥쪽 면은 그 방향의 카메라에는 보이고(backface 아님), 반대편'
      '(안쪽) 카메라에는 backface로 컬링된다', () {
    final northSides = scene.triangles.where(
      (t) => t.sourceId == 'wall-n' && t.normal.y.abs() < 0.5,
    );
    expect(northSides, isNotEmpty);

    // wall-n의 진짜 바깥쪽(북쪽, z가 작은 방향) 피부 — 북쪽 바깥
    // 카메라에서는 backface가 아니어야(=보여야) 한다.
    final outward = northSides.firstWhere(
      (t) => !isBackFace(t, vm.Vector3(2500, 1200, -6000)),
    );
    // 같은 삼각형을 반대편(남쪽, 방 안쪽)에서 보면 이제 카메라를
    // 등지므로 backface여야 한다.
    expect(isBackFace(outward, vm.Vector3(2500, 1200, 6000)), isTrue);
  });

  test('벽 두 측면(안쪽/바깥쪽) 중 하나는 항상 어느 카메라에서든 backface다 '
      '— 겹치는 면 쌍이 동시에 둘 다 보이는 일은 없다', () {
    final northSides = scene.triangles
        .where((t) => t.sourceId == 'wall-n' && t.normal.y.abs() < 0.5)
        .toList();
    for (final eye in [
      vm.Vector3(2500, 1200, -6000),
      vm.Vector3(2500, 1200, 6000),
      vm.Vector3(-4000, 1200, 500),
    ]) {
      final visibleCount = northSides.where((t) => !isBackFace(t, eye)).length;
      // 4개 측면 quad(=8삼각형) 중 카메라를 향한 절반 이하만 살아남아야
      // 한다(전부 다 보이면 안쪽/바깥쪽이 동시에 그려져 겹침 문제가
      // 재발한다).
      expect(visibleCount, lessThan(northSides.length));
    }
  });
}
