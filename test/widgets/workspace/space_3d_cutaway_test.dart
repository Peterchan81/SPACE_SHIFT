// isCutawayHidden(실기 FAIL 재수정 WO 8/20번 — "내부가 보이는 아이소")
// 에 대한 단위 테스트. 실제 buildSpaceScene() 결과(진짜 벽 side 삼각형)
// 로 검증한다 — 손으로 만든 임의 좌표가 아니라 실제 렌더링 파이프라인이
// 만드는 geometry를 그대로 쓴다.
//
// A. 바닥/내벽은 카메라 위치와 무관하게 절대 숨겨지지 않는다.
// B. 외벽의 상단(천장과 맞닿는 면)은 카메라가 정면이어도 숨기지 않는다.
// C. 외벽 측면은 카메라가 그 벽을 정면으로 바라볼 때만(바깥쪽 법선이
//    카메라 방향을 향할 때) 숨겨진다.
// D. 반대편에서 보면(그 벽의 법선이 카메라에서 먼 쪽) 숨겨지지 않는다.
// E. 카메라를 회전시키면(반대편 벽으로 시점 이동) 숨겨지는 벽도 함께
//    바뀐다 — 정적으로 고정되지 않는다.

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
      WallSegment(
        id: 'wall-w',
        start: Point2(0.1, 0.1),
        end: Point2(0.1, 0.9),
        thicknessNormalized: 0.02,
        confidence: 0.8,
        isExterior: true,
      ),
      WallSegment(
        id: 'wall-e',
        start: Point2(0.9, 0.1),
        end: Point2(0.9, 0.9),
        thicknessNormalized: 0.02,
        confidence: 0.8,
        isExterior: true,
      ),
      WallSegment(
        id: 'wall-mid',
        start: Point2(0.5, 0.1),
        end: Point2(0.5, 0.9),
        thicknessNormalized: 0.02,
        confidence: 0.6,
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
      rawVerticalRuns: 3,
      mergedWallCount: 5,
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
  final center = scene.center;

  Iterable<SpaceTriangle> wallSideTriangles(String id) =>
      scene.triangles.where((t) => t.sourceId == id && t.normal.y.abs() < 0.5);

  test('실기 재현 전제 — north/south 외벽과 내벽(mid)이 실제로 존재한다', () {
    expect(wallSideTriangles('wall-n'), isNotEmpty);
    expect(wallSideTriangles('wall-s'), isNotEmpty);
    final midTriangles = scene.triangles.where((t) => t.sourceId == 'wall-mid');
    expect(midTriangles, isNotEmpty);
    expect(midTriangles.every((t) => !t.isExteriorWall), isTrue);
  });

  test('A — 바닥은 카메라 위치와 무관하게 절대 숨겨지지 않는다', () {
    final floorTriangles = scene.triangles.where(
      (t) => t.sourceKind == SpaceElementKind.floor,
    );
    expect(floorTriangles, isNotEmpty);
    for (final tri in floorTriangles) {
      // 바닥 중심을 정면으로 내려다보는 카메라를 포함해 여러 방향에서
      // 확인한다.
      for (final eye in [
        vm.Vector3(2000, 3000, -5000),
        vm.Vector3(2000, 3000, 9000),
        vm.Vector3(-4000, 3000, 2000),
      ]) {
        expect(isCutawayHidden(tri, eye, center), isFalse);
      }
    }
  });

  test('A — 내벽(wall-mid)은 카메라 위치와 무관하게 절대 숨겨지지 않는다', () {
    final midTriangles = scene.triangles.where((t) => t.sourceId == 'wall-mid');
    for (final tri in midTriangles) {
      for (final eye in [
        vm.Vector3(2500, 1200, -5000),
        vm.Vector3(2500, 1200, 9000),
      ]) {
        expect(isCutawayHidden(tri, eye, center), isFalse);
      }
    }
  });

  test('B — 외벽 상단(천장과 맞닿는 면)은 카메라가 정면이어도 숨기지 않는다', () {
    final topTriangles = scene.triangles.where(
      (t) => t.sourceId == 'wall-n' && t.normal.y.abs() > 0.5,
    );
    expect(topTriangles, isNotEmpty);
    // wall-n 정면(북쪽 바깥, -Z 방향)에서 바라보는 카메라.
    final eyeFacingNorth = vm.Vector3(2500, 1200, -6000);
    for (final tri in topTriangles) {
      expect(isCutawayHidden(tri, eyeFacingNorth, center), isFalse);
    }
  });

  test('C/D — 외벽 측면은 카메라가 정면일 때만 숨겨지고, 반대편에서 보면 '
      '숨겨지지 않는다', () {
    final northSides = wallSideTriangles('wall-n').toList();
    expect(northSides, isNotEmpty);

    // wall-n은 room 북쪽(정규화 y=0.1)에 있다 — 이 room의 좌표계에서
    // z가 작을수록(이미지 y가 작을수록) "북쪽"이다. 북쪽 바깥에서
    // 안쪽을 들여다보는 카메라(=z가 더 작은 곳)에는 이 벽의 진짜
    // 바깥쪽 피부(안쪽 면·마구리 면 제외)가 정면으로 막아선다.
    final eyeFromOutsideNorth = vm.Vector3(2500, 1200, -6000);
    final hiddenFromOutside = northSides
        .map((t) => isCutawayHidden(t, eyeFromOutsideNorth, center))
        .toList();
    expect(
      hiddenFromOutside.any((hidden) => hidden),
      isTrue,
      reason: '북쪽 바깥에서 보면 wall-n의 진짜 바깥쪽 피부는 숨겨져야 한다',
    );

    // 반대편(남쪽, z가 큰 곳)에서 보면 wall-n은 이제 뒷벽(배경)이다 —
    // 실내쪽 면이 카메라를 정면으로 향하더라도, 건물 중심 기준
    // "바깥쪽"이 아니므로 숨겨지면 안 된다(뒷벽이 사라지는 버그
    // 재발 방지).
    final eyeFromOutsideSouth = vm.Vector3(2500, 1200, 12000);
    for (final tri in northSides) {
      expect(isCutawayHidden(tri, eyeFromOutsideSouth, center), isFalse);
    }
  });

  test('E — 카메라를 반대편으로 옮기면 숨겨지는 벽도 wall-n에서 wall-s로 바뀐다', () {
    final northSides = wallSideTriangles('wall-n').toList();
    final southSides = wallSideTriangles('wall-s').toList();

    final eyeFromNorth = vm.Vector3(2500, 1200, -6000);
    expect(
      northSides.any((t) => isCutawayHidden(t, eyeFromNorth, center)),
      isTrue,
    );
    expect(
      southSides.every((t) => !isCutawayHidden(t, eyeFromNorth, center)),
      isTrue,
    );

    final eyeFromSouth = vm.Vector3(2500, 1200, 12000);
    expect(
      southSides.any((t) => isCutawayHidden(t, eyeFromSouth, center)),
      isTrue,
    );
    expect(
      northSides.every((t) => !isCutawayHidden(t, eyeFromSouth, center)),
      isTrue,
    );
  });
}
