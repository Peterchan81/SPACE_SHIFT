// SPACE SHIFT — WO088-6 REAL MM GRID.

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/vision_cad_poc/drafting_v1/drafting_model.dart';
import 'package:ason_space/vision_cad_poc/drafting_v1/real_mm_grid.dart';
import 'package:ason_space/vision_cad_poc/drafting_v1/structural_layer.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/virtual_cad_scale.dart';

DraftingModel _modelWithOneWall(Pt start, Pt end) {
  final line = RawStructuralLine(id: 'w1', start: start, end: end, thicknessPx: 2, method: 'axisAligned');
  return buildDraftingModel([line], originPixel: (x: 0, y: 0));
}

void main() {
  group('calibrateDraftScaleFromAnchor + buildRealMmDraft', () {
    test('scale 미확정이면(§3) buildRealMmDraft가 null을 반환한다 — mm를 거짓 표기하지 않는다', () {
      final model = _modelWithOneWall((x: 0, y: 0), (x: 100, y: 0));
      final result = buildRealMmDraft(model, const RealWorldScale.unknown());
      expect(result, isNull);
    });

    test('anchor 확정 후 wall raw mm 길이가 정확히 계산된다', () {
      final model = _modelWithOneWall((x: 0, y: 0), (x: 200, y: 0));
      // anchor: 같은 100px 거리를 900mm로 지정 -> 9mm/px.
      final scale = calibrateDraftScaleFromAnchor(a: (x: 0, y: 0), b: (x: 100, y: 0), realWorldMm: 900);
      final mmDraft = buildRealMmDraft(model, scale)!;
      expect(mmDraft.walls.single.rawLengthMm, closeTo(1800, 1e-6)); // 200px * 9mm/px.
    });

    test('원점(Origin)이 이미 (0,0)이므로 mm 변환 후에도 원점은 그대로 (0,0)이다', () {
      final model = _modelWithOneWall((x: 0, y: 0), (x: 50, y: 0));
      final scale = calibrateDraftScaleFromAnchor(a: (x: 0, y: 0), b: (x: 10, y: 0), realWorldMm: 90);
      final mmDraft = buildRealMmDraft(model, scale)!;
      expect(mmDraft.walls.single.rawStart.xMm, closeTo(0, 1e-9));
      expect(mmDraft.walls.single.rawStart.yMm, closeTo(0, 1e-9));
    });
  });
}
