import 'package:ason_space/core/ss_iso_editor_controller.dart';
import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/ss_cad_scene.dart';
import 'package:ason_space/models/ss_iso_design_extras.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

const _emptyPlan = CadFloorPlan(sourceWidthPx: 1000, sourceHeightPx: 1000, walls: [], openings: [], rooms: [], warnings: []);

const _scale = FloorPlanScale(mmPerPixel: 5, referenceStart: Point2(0, 0), referenceEnd: Point2(1, 0), referenceLengthMm: 5000, source: ScaleSource.measured);

SsIsoEditorController _controller({SsCadScene? cad}) =>
    SsIsoEditorController(initialState: SsIsoEditorState(cad: cad ?? const SsCadScene(plan: _emptyPlan, scale: _scale)));

void main() {
  group('구조 — 벽', () {
    test('벽체 생성 후 선택되고 undo로 되돌릴 수 있다', () {
      final c = _controller();
      expect(c.plan.walls, isEmpty);
      c.addDefaultWall();
      expect(c.plan.walls, hasLength(1));
      expect(c.selection.objectType, '벽');
      expect(c.canUndo, isTrue);
      c.undo();
      expect(c.plan.walls, isEmpty);
      expect(c.canRedo, isTrue);
      c.redo();
      expect(c.plan.walls, hasLength(1));
    });

    test('선택된 벽의 길이/두께/높이를 바꿀 수 있다', () {
      final c = _controller();
      c.addDefaultWall();
      final wallId = c.selection.objectId;
      c.setSelectedWallLengthMm(3000);
      c.setSelectedWallThicknessMm(150);
      c.setSelectedWallHeightMm(2400);
      final wall = c.plan.walls.firstWhere((w) => w.id == wallId);
      expect(wall.heightMm, 2400);
    });

    test('벽을 철거하면 선택이 비워지고 벽이 사라진다', () {
      final c = _controller();
      c.addDefaultWall();
      c.deleteSelectedWall();
      expect(c.plan.walls, isEmpty);
      expect(c.selection.isEmpty, isTrue);
    });

    test('선택된 벽에 문/창을 추가할 수 있다', () {
      final c = _controller();
      c.addDefaultWall();
      c.addOpeningOnSelectedWall(OpeningType.door);
      expect(c.plan.openings, hasLength(1));
      expect(c.plan.openings.single.type, OpeningType.door);
    });
  });

  group('마감재/색상', () {
    test('벽 마감재를 바꾸면 materialOverride와 라벨이 함께 저장된다', () {
      final c = _controller();
      c.addDefaultWall();
      final wallId = c.selection.objectId;
      c.setSelectedWallMaterial('타일', const Color(0xFFD9DADC));
      final wall = c.plan.walls.firstWhere((w) => w.id == wallId);
      expect(wall.materialOverride, const Color(0xFFD9DADC));
      expect(c.extras.materialLabels['wall:$wallId'], '타일');
      expect(c.selection.properties['materialLabel'], '타일');
    });
  });

  group('가구', () {
    test('가구를 추가/이동/회전/삭제할 수 있다', () {
      final c = _controller();
      c.addFurniture(SsCadFurnitureKind.sofa);
      expect(c.cad.furniture, hasLength(1));
      expect(c.selection.objectType, '가구');
      c.moveSelectedFurnitureByMm(500, 0);
      c.rotateSelectedFurniture(90);
      final f = c.cad.furniture.single;
      expect(f.rotationDegrees, 90);
      c.deleteSelectedFurniture();
      expect(c.cad.furniture, isEmpty);
    });
  });

  group('조명/설비', () {
    test('조명을 추가/이동/삭제할 수 있다', () {
      final c = _controller();
      c.addLight(SsIsoLightKind.pendant);
      expect(c.extras.lights, hasLength(1));
      c.moveSelectedLightByMm(100, 0);
      expect(c.extras.lights.single.xMm, 100);
      c.deleteSelectedLight();
      expect(c.extras.lights, isEmpty);
    });

    test('설비를 추가/삭제할 수 있다', () {
      final c = _controller();
      c.addEquipment(SsIsoEquipmentKind.sink);
      expect(c.extras.equipment, hasLength(1));
      c.deleteSelectedEquipment();
      expect(c.extras.equipment, isEmpty);
    });

    test('공용 deleteSelected가 선택 종류에 맞게 지운다', () {
      final c = _controller();
      c.addEquipment(SsIsoEquipmentKind.vanity);
      expect(c.selection.objectType, '설비');
      c.deleteSelected();
      expect(c.extras.equipment, isEmpty);
    });
  });

  group('SS014 연결', () {
    test('벽을 선택하면 selectedWallIdForElevationHandoff가 그 벽 id를 돌려준다', () {
      final c = _controller();
      c.addDefaultWall();
      expect(c.selectedWallIdForElevationHandoff, c.selection.objectId);
    });

    test('벽이 아닌 선택에서는 null이다', () {
      final c = _controller();
      c.addFurniture(SsCadFurnitureKind.table);
      expect(c.selectedWallIdForElevationHandoff, isNull);
    });
  });

  test('scene3d는 geometry가 없으면 비어 있다', () {
    final c = _controller();
    expect(c.scene3d.isEmpty, isTrue);
    c.addDefaultWall();
    expect(c.scene3d.isEmpty, isFalse);
  });
}
