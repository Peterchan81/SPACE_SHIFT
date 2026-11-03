// SS011 — CAD 편집 컨트롤러: 벽 생성/삭제, 문/창 추가, 가구 추가·이동·회전·복사,
// 치수(property) 수정, Calibration, 거리 측정, Undo/Redo가 모두 SsHistory 하나로
// 묶여 되돌려지는지 확인한다.
import 'package:ason_space/core/ss_cad_editor_controller.dart';
import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/ss_cad_scene.dart';
import 'package:flutter_test/flutter_test.dart';

CadFloorPlan _planWithOneWall() => const CadFloorPlan(
  sourceWidthPx: 1000,
  sourceHeightPx: 1000,
  walls: [
    CadWall(id: 'w1', start: Point2(0.1, 0.1), end: Point2(0.6, 0.1), thicknessNormalized: 0.02, wallType: CadWallType.interior, confidence: 1.0),
  ],
  openings: [],
  rooms: [],
  warnings: [],
);

const _scale = FloorPlanScale(mmPerPixel: 2.0, referenceStart: Point2(0, 0), referenceEnd: Point2(1, 0), referenceLengthMm: 2000, source: ScaleSource.measured);

void main() {
  test('벽을 선택하면 길이/두께 mm가 축척 기준으로 계산된다', () {
    final c = SsCadEditorController(initialScene: SsCadScene(plan: _planWithOneWall(), scale: _scale));
    c.selectWall('w1');
    expect(c.selection.objectType, '벽');
    expect((c.selection.properties['lengthMm'] as double), closeTo(1000, 0.01));
  });

  test('벽체 생성 → 벽체 삭제 → Undo로 복원된다', () {
    final c = SsCadEditorController(initialScene: const SsCadScene(plan: CadFloorPlan(sourceWidthPx: 1000, sourceHeightPx: 1000, walls: [], openings: [], rooms: [], warnings: [])));
    c.addDefaultWall();
    expect(c.plan.walls.length, 1);
    final id = c.plan.walls.single.id;
    c.selectWall(id);
    c.deleteSelected();
    expect(c.plan.walls, isEmpty);
    c.undo();
    expect(c.plan.walls.length, 1);
    c.redo();
    expect(c.plan.walls, isEmpty);
  });

  test('선택된 벽에 문을 추가하면 그 벽에 붙는다', () {
    final c = SsCadEditorController(initialScene: SsCadScene(plan: _planWithOneWall(), scale: _scale));
    c.selectWall('w1');
    c.addOpeningOnSelectedWall(OpeningType.door);
    expect(c.plan.openings.single.wallId, 'w1');
    expect(c.selection.objectType, '문');
  });

  test('벽을 삭제하면 그 벽에 붙은 문/창도 함께 사라진다', () {
    final c = SsCadEditorController(initialScene: SsCadScene(plan: _planWithOneWall(), scale: _scale));
    c.selectWall('w1');
    c.addOpeningOnSelectedWall(OpeningType.door);
    c.selectWall('w1');
    c.deleteSelected();
    expect(c.plan.walls, isEmpty);
    expect(c.plan.openings, isEmpty);
  });

  test('가구를 추가·이동·회전·복사·삭제할 수 있다', () {
    final c = SsCadEditorController(initialScene: SsCadScene(plan: _planWithOneWall(), scale: _scale));
    c.addFurniture(SsCadFurnitureKind.sofa);
    expect(c.scene.furniture.length, 1);
    final id = c.scene.furniture.single.id;

    c.moveSelectedFurniture(const Point2(0.8, 0.8));
    expect(c.scene.furniture.single.center.x, closeTo(0.8, 0.001));

    c.rotateSelectedFurniture(90);
    expect(c.scene.furniture.single.rotationDegrees, 90);

    c.duplicateSelectedFurniture();
    expect(c.scene.furniture.length, 2);

    c.selectFurniture(id);
    c.deleteSelected();
    expect(c.scene.furniture.length, 1);
  });

  test('Calibration — 드래그로 벽을 고르고 실측 mm를 입력하면 축척이 갱신된다', () {
    final c = SsCadEditorController(initialScene: const SsCadScene(plan: CadFloorPlan(sourceWidthPx: 1000, sourceHeightPx: 1000, walls: [
      CadWall(id: 'w1', start: Point2(0.0, 0.0), end: Point2(0.5, 0.0), thicknessNormalized: 0.02, wallType: CadWallType.interior, confidence: 1.0),
    ], openings: [], rooms: [], warnings: [])));
    expect(c.scale, isNull);
    c.startCalibrationDrag(const Point2(0.01, 0.0), const Point2(0.49, 0.0));
    expect(c.calibrationWallId, 'w1');
    c.applyCalibrationLengthMm(5000);
    expect(c.scale, isNotNull);
    expect(c.scale!.mmPerPixel, closeTo(10.0, 0.001));
  });

  test('거리 측정 — 두 점을 찍으면 축척 기준 mm 거리가 나온다', () {
    final c = SsCadEditorController(initialScene: SsCadScene(plan: _planWithOneWall(), scale: _scale));
    c.measureTapAt(const Point2(0.0, 0.0));
    c.measureTapAt(const Point2(1.0, 0.0));
    expect(c.measureDistanceMm, closeTo(2000, 0.01));
  });
}
