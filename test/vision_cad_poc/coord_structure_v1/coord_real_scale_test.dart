// SPACE SHIFT — WO088-2 SEMANTIC → COORDINATE → REAL SCALE ARCHITECTURE POC.
//
// buildMetricCoordStructure()/calibrateCoordScaleFromAnchor()가
// virtual_cad_scale.dart(WO082)/metric_cad.dart(WO083)가 이미 검증한
// 축척 산술을 coord_structure_v1(WO088-1)의 CoordStructureModel에
// 정확히 연결하는지 검증한다 — 새 산술을 재발명하지 않는다는 원칙 자체를
// 수치로 증명한다(§9).

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/vision_cad_poc/coord_structure_v1/coord_real_scale.dart';
import 'package:ason_space/vision_cad_poc/coord_structure_v1/coord_structure_model.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/metric_cad.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/virtual_cad_scale.dart';

CoordWallSegment _wall(
  String id,
  Point2 start,
  Point2 end, {
  bool reviewNeeded = false,
  bool isExterior = true,
  List<String> reviewReasons = const [],
}) => CoordWallSegment(
  id: id,
  start: start,
  end: end,
  thicknessNormalized: 0.02,
  isExterior: isExterior,
  confidence: 0.9,
  reviewNeeded: reviewNeeded,
  source: CoordEvidenceSource.pixelWall,
  reviewReasons: reviewReasons,
);

CoordStructureModel _modelOf(List<CoordWallSegment> walls) =>
    CoordStructureModel(walls: walls, openings: const [], regions: const [], corners: const []);

void main() {
  group('calibrateCoordScaleFromAnchor + buildMetricCoordStructure — normalized -> mm', () {
    test('anchor로 계산한 축척이 다른 벽의 실제 길이를 정확히 mm로 변환한다', () {
      const w = 1000, h = 500;
      // anchor: (0.1,0.5)-(0.2,0.5) = 정규화 0.1 => virtual 100px(w=1000).
      final scale = calibrateCoordScaleFromAnchor(
        a: const Point2(0.1, 0.5),
        b: const Point2(0.2, 0.5),
        realWorldMm: 900,
        sourceWidthPx: w,
        sourceHeightPx: h,
      );
      expect(scale.isCalibrated, isTrue);
      expect(scale.confidence, ScaleConfidence.userAnchored);
      // 100 virtual px = 900mm => 9mm/unit.
      expect(scale.mmPerVirtualUnit, closeTo(9.0, 1e-9));

      // 다른 벽: 정규화 0.5 => virtual 500px => 4500mm.
      final other = _wall('w1', const Point2(0.0, 0.0), const Point2(0.5, 0.0));
      final metric = buildMetricCoordStructure(_modelOf([other]), scale, sourceWidthPx: w, sourceHeightPx: h);
      expect(metric.walls, hasLength(1));
      expect(metric.walls.single.lengthMm, closeTo(4500.0, 1e-6));
    });

    test('mm -> normalized round-trip', () {
      const w = 800, h = 600;
      final scale = calibrateCoordScaleFromAnchor(a: const Point2(0, 0), b: const Point2(1, 0), realWorldMm: 8000, sourceWidthPx: w, sourceHeightPx: h);
      const original = Point2(0.37, 0.62);
      final mm = toMetricCadPoint(original, scale, sourceWidthPx: w, sourceHeightPx: h)!;
      final back = metricCoordPointToNormalized(mm, scale, sourceWidthPx: w, sourceHeightPx: h)!;
      expect(back.x, closeTo(original.x, 1e-9));
      expect(back.y, closeTo(original.y, 1e-9));
    });

    test('이미지 해상도가 균일하게 달라져도(resize) 같은 anchor 실제 mm면 다른 좌표의 결과가 동일하다', () {
      const anchorA = Point2(0.1, 0.5);
      const anchorB = Point2(0.3, 0.5);
      const target = Point2(0.6, 0.9);

      double lengthFor(int w, int h) {
        final scale = calibrateCoordScaleFromAnchor(a: anchorA, b: anchorB, realWorldMm: 4200, sourceWidthPx: w, sourceHeightPx: h);
        final wall = _wall('t', const Point2(0, 0), target);
        final metric = buildMetricCoordStructure(_modelOf([wall]), scale, sourceWidthPx: w, sourceHeightPx: h);
        return metric.walls.single.lengthMm;
      }

      final small = lengthFor(400, 300);
      final large = lengthFor(4000, 3000); // 동일 비율로 10배 확대된 해상도.
      expect(large, closeTo(small, 1e-6), reason: '이미지 해상도가 달라도 동일한 실제 geometry가 나와야 한다');
    });

    test('Anchor 900mm 적용', () {
      final scale = calibrateCoordScaleFromAnchor(a: const Point2(0, 0), b: const Point2(0.1, 0), realWorldMm: 900, sourceWidthPx: 1000, sourceHeightPx: 1000);
      expect(scale.isCalibrated, isTrue);
      expect(scale.mmPerVirtualUnit, closeTo(9.0, 1e-9)); // 100 virtual px = 900mm.
    });

    test('Anchor 1000mm 적용', () {
      final scale = calibrateCoordScaleFromAnchor(a: const Point2(0, 0), b: const Point2(0.1, 0), realWorldMm: 1000, sourceWidthPx: 1000, sourceHeightPx: 1000);
      expect(scale.isCalibrated, isTrue);
      expect(scale.mmPerVirtualUnit, closeTo(10.0, 1e-9));
    });

    test('사용자 직접 입력(예: 벽 전체 길이 4200mm) 적용', () {
      final scale = calibrateCoordScaleFromAnchor(
        a: const Point2(0, 0),
        b: const Point2(1, 0),
        realWorldMm: 4200,
        sourceWidthPx: 300,
        sourceHeightPx: 200,
        anchorDescription: '왼쪽 벽 전체 = 4200mm',
      );
      expect(scale.isCalibrated, isTrue);
      expect(scale.anchorDescription, '왼쪽 벽 전체 = 4200mm');
      expect(scale.mmPerVirtualUnit, closeTo(4200 / 300, 1e-9));
    });

    test('anchor 실제 길이 값이 바뀌면 전체 geometry가 비례적으로만 변환된다(벽 사이 비율은 불변)', () {
      final wallA = _wall('a', const Point2(0, 0), const Point2(0.2, 0));
      final wallB = _wall('b', const Point2(0, 0), const Point2(0.5, 0));
      final model = _modelOf([wallA, wallB]);
      const w = 500, h = 500;

      final scale900 = calibrateCoordScaleFromAnchor(a: const Point2(0, 0), b: const Point2(1, 0), realWorldMm: 900, sourceWidthPx: w, sourceHeightPx: h);
      final scale1800 = calibrateCoordScaleFromAnchor(a: const Point2(0, 0), b: const Point2(1, 0), realWorldMm: 1800, sourceWidthPx: w, sourceHeightPx: h);

      final metric900 = buildMetricCoordStructure(model, scale900, sourceWidthPx: w, sourceHeightPx: h);
      final metric1800 = buildMetricCoordStructure(model, scale1800, sourceWidthPx: w, sourceHeightPx: h);

      final ratio900 = metric900.walls[0].lengthMm / metric900.walls[1].lengthMm;
      final ratio1800 = metric1800.walls[0].lengthMm / metric1800.walls[1].lengthMm;
      expect(ratio900, closeTo(ratio1800, 1e-9));
      expect(metric1800.walls[0].lengthMm, closeTo(metric900.walls[0].lengthMm * 2, 1e-6));
    });

    test('reviewNeeded/reviewReasons가 있는 wall도 mm 변환에서 조용히 삭제되지 않는다', () {
      final wall = _wall('rn', const Point2(0.1, 0.1), const Point2(0.4, 0.1), reviewNeeded: true, reviewReasons: const ['possibleFurnitureInterference: test']);
      final scale = calibrateCoordScaleFromAnchor(a: const Point2(0, 0), b: const Point2(1, 0), realWorldMm: 5000, sourceWidthPx: 100, sourceHeightPx: 100);
      final metric = buildMetricCoordStructure(_modelOf([wall]), scale, sourceWidthPx: 100, sourceHeightPx: 100);
      expect(metric.walls, hasLength(1));
      expect(metric.walls.single.reviewNeeded, isTrue);
      expect(metric.walls.single.reviewReasons, contains('possibleFurnitureInterference: test'));
    });

    test('scale이 미확정(unknown)이면 모든 목록이 빈 상태로 정직하게 남는다', () {
      final wall = _wall('w', const Point2(0, 0), const Point2(1, 1));
      final metric = buildMetricCoordStructure(_modelOf([wall]), const RealWorldScale.unknown(), sourceWidthPx: 100, sourceHeightPx: 100);
      expect(metric.walls, isEmpty);
      expect(metric.openings, isEmpty);
      expect(metric.regions, isEmpty);
      expect(metric.corners, isEmpty);
      expect(metric.scale.isCalibrated, isFalse);
    });

    test('같은 점을 두 번 찍거나(0 거리) 0/음수 mm를 입력하면 안전하게 unknown으로 남는다', () {
      final samePoint = calibrateCoordScaleFromAnchor(a: const Point2(0.5, 0.5), b: const Point2(0.5, 0.5), realWorldMm: 900, sourceWidthPx: 100, sourceHeightPx: 100);
      expect(samePoint.isCalibrated, isFalse);

      final zeroMm = calibrateCoordScaleFromAnchor(a: const Point2(0, 0), b: const Point2(1, 0), realWorldMm: 0, sourceWidthPx: 100, sourceHeightPx: 100);
      expect(zeroMm.isCalibrated, isFalse);

      final negativeMm = calibrateCoordScaleFromAnchor(a: const Point2(0, 0), b: const Point2(1, 0), realWorldMm: -900, sourceWidthPx: 100, sourceHeightPx: 100);
      expect(negativeMm.isCalibrated, isFalse);
    });
  });
}
