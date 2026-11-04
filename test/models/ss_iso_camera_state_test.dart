// SS012 — SsIsoCameraState: JSON 왕복이 값을 보존하는지, 알아볼 수 없는 값은 지어내지 않고 null을
// 돌려주는지, scene 기준 기본값(빈 scene/실제 scene)을 올바르게 계산하는지 확인한다.
import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/space_scene_v2.dart';
import 'package:ason_space/models/ss_iso_camera_state.dart';
import 'package:ason_space/services/space_scene_builder_v2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  test('toJson/tryFromJson 왕복이 값을 그대로 보존한다', () {
    const camera = SsIsoCameraState(targetXMm: 100, targetYMm: 200, targetZMm: 300, distanceMm: 4000, azimuthRadians: 0.5, polarRadians: 0.9);
    final restored = SsIsoCameraState.tryFromJson(camera.toJson());
    expect(restored, isNotNull);
    expect(restored!.targetXMm, camera.targetXMm);
    expect(restored.targetYMm, camera.targetYMm);
    expect(restored.targetZMm, camera.targetZMm);
    expect(restored.distanceMm, camera.distanceMm);
    expect(restored.azimuthRadians, camera.azimuthRadians);
    expect(restored.polarRadians, camera.polarRadians);
  });

  test('알아볼 수 없는 값이면 지어내지 않고 null을 돌려준다', () {
    expect(SsIsoCameraState.tryFromJson({'targetXMm': 1}), isNull);
    expect(SsIsoCameraState.tryFromJson('not a map'), isNull);
    expect(SsIsoCameraState.tryFromJson(null), isNull);
  });

  test('빈 scene이면 원점 기준 고정값을 돌려준다', () {
    final camera = SsIsoCameraState.defaultForScene(
      SpaceSceneV2(wallMeshes: const [], floorMeshes: const [], openings: const [], minBounds: Vector3.zero(), maxBounds: Vector3.zero(), warnings: const []),
    );
    expect(camera.targetXMm, 0);
    expect(camera.targetYMm, 0);
    expect(camera.targetZMm, 0);
    expect(camera.distanceMm, greaterThan(0));
  });

  test('실제 scene이 있으면 중심/크기 기준 Orbit 시점을 계산한다', () {
    const scale = FloorPlanScale(mmPerPixel: 5.0, referenceStart: Point2(0, 0), referenceEnd: Point2(1, 0), referenceLengthMm: 5000, source: ScaleSource.measured);
    const corners = [Point2(0.1, 0.1), Point2(0.9, 0.1), Point2(0.9, 0.9), Point2(0.1, 0.9)];
    final plan = CadFloorPlan(
      sourceWidthPx: 1000,
      sourceHeightPx: 1000,
      walls: [
        CadWall(id: 'n', start: const Point2(0.1, 0.1), end: const Point2(0.9, 0.1), thicknessNormalized: 0.02, wallType: CadWallType.exterior, confidence: 0.9),
        CadWall(id: 's', start: const Point2(0.1, 0.9), end: const Point2(0.9, 0.9), thicknessNormalized: 0.02, wallType: CadWallType.exterior, confidence: 0.9),
        CadWall(id: 'w', start: const Point2(0.1, 0.1), end: const Point2(0.1, 0.9), thicknessNormalized: 0.02, wallType: CadWallType.exterior, confidence: 0.9),
        CadWall(id: 'e', start: const Point2(0.9, 0.1), end: const Point2(0.9, 0.9), thicknessNormalized: 0.02, wallType: CadWallType.exterior, confidence: 0.9),
      ],
      openings: const [],
      rooms: const [CadRoom(id: 'room-0', polygon: corners, areaNormalized: 0.64, confidence: 0.9)],
      warnings: const [],
    );
    final scene = buildSpaceSceneV2(plan: plan, scale: scale, ceilingHeightMm: 2400);
    final camera = SsIsoCameraState.defaultForScene(scene);
    expect(camera.targetXMm, closeTo(scene.center.x, 1e-6));
    expect(camera.targetYMm, closeTo(scene.center.y, 1e-6));
    expect(camera.targetZMm, closeTo(scene.center.z, 1e-6));
    expect(camera.distanceMm, greaterThan(0));
  });
}
