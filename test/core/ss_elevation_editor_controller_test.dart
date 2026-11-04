// SS014 — SsElevationEditorController(정면도 layout 계산/측면 후보/문·창 선택)를 확인한다. 실제
// 편집/Undo/Redo는 SsIsoEditorController(SS013, ss_iso_editor_controller_test.dart)가 이미 검증했다.
import 'package:ason_space/core/ss_elevation_editor_controller.dart';
import 'package:ason_space/core/ss_iso_editor_controller.dart';
import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/ss_cad_scene.dart';
import 'package:flutter_test/flutter_test.dart';

const _emptyPlan = CadFloorPlan(sourceWidthPx: 1000, sourceHeightPx: 1000, walls: [], openings: [], rooms: [], warnings: []);

const _scale = FloorPlanScale(mmPerPixel: 5, referenceStart: Point2(0, 0), referenceEnd: Point2(1, 0), referenceLengthMm: 5000, source: ScaleSource.measured);

SsIsoEditorController _iso() => SsIsoEditorController(initialState: SsIsoEditorState(cad: const SsCadScene(plan: _emptyPlan, scale: _scale)));

void main() {
  group('SsElevationEditorController', () {
    test('focusedWall/layout은 선택된 벽의 길이/높이를 보여준다', () {
      final iso = _iso();
      iso.addDefaultWall();
      iso.setSelectedWallLengthMm(3000);
      iso.setSelectedWallHeightMm(2400);
      final wallId = iso.selection.objectId;
      final c = SsElevationEditorController(iso: iso, initialWallId: wallId);
      expect(c.focusedWall?.id, wallId);
      expect(c.layout?.lengthMm, closeTo(3000, 0.5));
      expect(c.layout?.heightMm, 2400);
    });

    test('문을 추가하면 layout.openings에 나타나고 탭으로 선택할 수 있다', () {
      final iso = _iso();
      iso.addDefaultWall();
      iso.setSelectedWallLengthMm(3000);
      final wallId = iso.selection.objectId;
      iso.addOpeningOnSelectedWall(OpeningType.door);
      final c = SsElevationEditorController(iso: iso, initialWallId: wallId);
      final opening = c.layout!.openings.single;
      expect(opening.type, OpeningType.door);
      c.selectOpeningAtAlongMm((opening.startMm + opening.endMm) / 2);
      expect(iso.selection.objectType, '문');
    });

    test('선택된 문을 벽을 따라 옮길 수 있다', () {
      final iso = _iso();
      iso.addDefaultWall();
      iso.setSelectedWallLengthMm(3000);
      final wallId = iso.selection.objectId;
      iso.addOpeningOnSelectedWall(OpeningType.door);
      final c = SsElevationEditorController(iso: iso, initialWallId: wallId);
      final openingId = c.layout!.openings.single.openingId;
      iso.selectOpening(openingId);
      final before = c.layout!.openings.single.startMm;
      iso.moveSelectedOpeningAlongWallByMm(200);
      final after = c.layout!.openings.single.startMm;
      expect(after, greaterThan(before));
    });

    test('빈 평면에서는 layout이 null이다', () {
      final iso = _iso();
      final c = SsElevationEditorController(iso: iso, initialWallId: 'nope');
      expect(c.layout, isNull);
    });

    test('수직인 벽만 측면도 후보로 보여준다', () {
      final iso = _iso();
      iso.addDefaultWall();
      final horizontalId = iso.selection.objectId;
      iso.setSelectedWallLengthMm(3000);
      iso.addDefaultWall();
      iso.setSelectedWallLengthMm(2000);
      final c = SsElevationEditorController(iso: iso, initialWallId: horizontalId);
      // addDefaultWall은 항상 같은(수평) 방향 기본 벽을 놓으므로, 서로 평행한 두 벽은 후보가 아니다.
      expect(c.sideWallCandidates, isEmpty);
    });
  });
}
