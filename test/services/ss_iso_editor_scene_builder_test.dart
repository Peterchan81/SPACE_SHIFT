import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/ss_cad_scene.dart';
import 'package:ason_space/models/ss_iso_design_extras.dart';
import 'package:ason_space/services/ss_iso_editor_scene_builder.dart';
import 'package:flutter_test/flutter_test.dart';

CadWall _wall(String id, Point2 start, Point2 end) =>
    CadWall(id: id, start: start, end: end, thicknessNormalized: 0.02, wallType: CadWallType.exterior, confidence: 1);

CadFloorPlan _planWithOneWall() => CadFloorPlan(
  sourceWidthPx: 1000,
  sourceHeightPx: 1000,
  walls: [_wall('w1', const Point2(0.1, 0.1), const Point2(0.9, 0.1))],
  openings: const [],
  rooms: const [],
  warnings: const [],
);

final _scale = const FloorPlanScale(mmPerPixel: 5, referenceStart: Point2(0, 0), referenceEnd: Point2(1, 0), referenceLengthMm: 5000, source: ScaleSource.measured);

void main() {
  test('빈 CAD는 빈 3D scene을 만든다', () {
    const emptyPlan = CadFloorPlan(sourceWidthPx: 100, sourceHeightPx: 100, walls: [], openings: [], rooms: [], warnings: []);
    final scene = buildIsoEditorScene(cad: const SsCadScene(plan: emptyPlan), extras: SsIsoDesignExtras.empty, ceilingHeightMm: 2400);
    expect(scene.isEmpty, isTrue);
  });

  test('벽이 있으면 wallMeshes가 생긴다', () {
    final cad = SsCadScene(plan: _planWithOneWall(), scale: _scale);
    final scene = buildIsoEditorScene(cad: cad, extras: SsIsoDesignExtras.empty, ceilingHeightMm: 2400);
    expect(scene.wallMeshes, isNotEmpty);
  });

  test('사용자가 추가한 가구는 isoFurniture: objectId로 scene에 더해진다', () {
    final furniture = SsCadFurniture(id: 'f1', kind: SsCadFurnitureKind.sofa, center: const Point2(0.5, 0.5), widthNormalized: 0.1, depthNormalized: 0.1);
    final cad = SsCadScene(plan: _planWithOneWall(), scale: _scale, furniture: [furniture]);
    final scene = buildIsoEditorScene(cad: cad, extras: SsIsoDesignExtras.empty, ceilingHeightMm: 2400);
    final ids = scene.furnitureMeshes.map((m) => m.identity.objectId);
    expect(ids, contains('isoFurniture:f1'));
  });

  test('조명/설비는 각각 isoLight:/isoEquipment: objectId로 scene에 더해진다', () {
    const extras = SsIsoDesignExtras(
      lights: [SsIsoLight(id: 'l1', kind: SsIsoLightKind.downlight, roomId: '', xMm: 100, yMm: 2000, zMm: 100)],
      equipment: [SsIsoEquipment(id: 'e1', kind: SsIsoEquipmentKind.sink, roomId: '', xMm: 200, zMm: 200)],
    );
    final cad = SsCadScene(plan: _planWithOneWall(), scale: _scale);
    final scene = buildIsoEditorScene(cad: cad, extras: extras, ceilingHeightMm: 2400);
    final ids = scene.furnitureMeshes.map((m) => m.identity.objectId).toList();
    expect(ids, contains('isoLight:l1'));
    expect(ids, contains('isoEquipment:e1'));
  });

  test('hiddenObjectIds에 들어간 objectId는 scene에서 빠진다', () {
    final furniture = SsCadFurniture(id: 'f1', kind: SsCadFurnitureKind.sofa, center: const Point2(0.5, 0.5), widthNormalized: 0.1, depthNormalized: 0.1);
    final cad = SsCadScene(plan: _planWithOneWall(), scale: _scale, furniture: [furniture]);
    const extras = SsIsoDesignExtras(hiddenObjectIds: {'isoFurniture:f1'});
    final scene = buildIsoEditorScene(cad: cad, extras: extras, ceilingHeightMm: 2400);
    final ids = scene.furnitureMeshes.map((m) => m.identity.objectId);
    expect(ids, isNot(contains('isoFurniture:f1')));
  });
}
