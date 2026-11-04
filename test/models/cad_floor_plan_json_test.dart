// SS011 — CadFloorPlan/FloorPlanScale JSON 왕복 변환이 벽/문/창/공간의 모든 편집
// 가능한 필드를 그대로 보존하는지 확인한다.
import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/models/cad_floor_plan_json.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const plan = CadFloorPlan(
    sourceWidthPx: 1000,
    sourceHeightPx: 800,
    walls: [
      CadWall(
        id: 'w1',
        start: Point2(0.1, 0.1),
        end: Point2(0.5, 0.1),
        thicknessNormalized: 0.02,
        wallType: CadWallType.exterior,
        confidence: 0.9,
        source: CadElementSource.userEdited,
        edited: true,
        heightMm: 2400,
      ),
    ],
    openings: [
      CadOpening(
        id: 'o1',
        type: OpeningType.door,
        center: Point2(0.3, 0.1),
        widthNormalized: 0.03,
        confidence: 1.0,
        wallId: 'w1',
        source: CadElementSource.userCreated,
        edited: true,
      ),
    ],
    rooms: [
      CadRoom(
        id: 'r1',
        polygon: [Point2(0.1, 0.1), Point2(0.5, 0.1), Point2(0.5, 0.5), Point2(0.1, 0.5)],
        areaNormalized: 0.16,
        confidence: 0.9,
        name: '거실',
      ),
    ],
    warnings: ['경고1'],
  );

  test('CadFloorPlan은 JSON을 거쳐도 벽/문/공간의 핵심 필드가 그대로다', () {
    final json = cadFloorPlanToJson(plan);
    final restored = cadFloorPlanFromJson(json)!;

    expect(restored.sourceWidthPx, 1000);
    expect(restored.sourceHeightPx, 800);
    expect(restored.walls.single.id, 'w1');
    expect(restored.walls.single.heightMm, 2400);
    expect(restored.walls.single.wallType, CadWallType.exterior);
    expect(restored.walls.single.source, CadElementSource.userEdited);
    expect(restored.openings.single.type, OpeningType.door);
    expect(restored.openings.single.wallId, 'w1');
    expect(restored.rooms.single.name, '거실');
    expect(restored.warnings, ['경고1']);
  });

  test('FloorPlanScale도 JSON을 거쳐도 그대로다', () {
    const scale = FloorPlanScale(
      mmPerPixel: 2.5,
      referenceStart: Point2(0, 0),
      referenceEnd: Point2(1, 0),
      referenceLengthMm: 3800,
      source: ScaleSource.measured,
    );
    final restored = floorPlanScaleFromJson(floorPlanScaleToJson(scale))!;
    expect(restored.mmPerPixel, 2.5);
    expect(restored.referenceLengthMm, 3800);
    expect(restored.source, ScaleSource.measured);
  });

  test('깨진 JSON은 null을 돌려준다(화면이 안전하게 폴백할 수 있게)', () {
    expect(cadFloorPlanFromJson({'sourceWidthPx': 'x'}), isNull);
    expect(floorPlanScaleFromJson('not a map'), isNull);
  });
}
