// SPACE SHIFT — WO082 EVIDENCE/PROVENANCE + VIRTUAL CAD FOUNDATION.
//
// Virtual CAD Coordinate 왕복 변환 + User Anchor scale calibration의
// 정확성/안전성(0·NaN·음수 거부)을 검증한다. 어떤 곳도 임의 mm 값을
// 확정하지 않는다는 원칙(§3B/§14)이 핵심이다.

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/virtual_cad_scale.dart';

void main() {
  group('VirtualCadPoint — Normalized <-> Virtual CAD 왕복 변환', () {
    test('정규화 좌표 -> Virtual CAD -> 다시 정규화 좌표로 왕복하면 원래 값과 같다', () {
      const original = Point2(0.37, 0.82);
      const w = 913;
      const h = 617;
      final virtual = VirtualCadPoint.fromNormalized(original, w: w, h: h);
      expect(virtual.x, closeTo(0.37 * w, 1e-9));
      expect(virtual.y, closeTo(0.82 * h, 1e-9));
      final roundTrip = virtual.toNormalized(w: w, h: h);
      expect(roundTrip.x, closeTo(original.x, 1e-9));
      expect(roundTrip.y, closeTo(original.y, 1e-9));
    });

    test('distanceTo는 실제 유클리드 거리를 Virtual CAD 단위로 계산한다', () {
      const a = VirtualCadPoint(0, 0);
      const b = VirtualCadPoint(3, 4);
      expect(a.distanceTo(b), closeTo(5, 1e-9));
    });
  });

  group('RealWorldScale — unknown 기본값 + 임의 확정 금지', () {
    test('RealWorldScale.unknown()은 항상 isCalibrated=false, mmPerVirtualUnit=null이다', () {
      const scale = RealWorldScale.unknown();
      expect(scale.confidence, ScaleConfidence.unknown);
      expect(scale.isCalibrated, isFalse);
      expect(scale.mmPerVirtualUnit, isNull);
      expect(scale.toMm(100), isNull, reason: 'calibrate되지 않은 축척으로 임의 mm 값을 만들면 안 된다');
    });
  });

  group('calibrateScaleFromUserAnchor — §3C User Anchor', () {
    test('두 점의 virtual distance와 실제 mm 입력으로 정확히 scale = mm / Dv를 계산한다', () {
      const a = VirtualCadPoint(0, 0);
      const b = VirtualCadPoint(100, 0); // virtual distance = 100.
      final scale = calibrateScaleFromUserAnchor(a: a, b: b, realWorldMm: 4200, anchorDescription: '왼쪽 벽 전체 길이');
      expect(scale.confidence, ScaleConfidence.userAnchored);
      expect(scale.isCalibrated, isTrue);
      expect(scale.mmPerVirtualUnit, closeTo(42.0, 1e-9)); // 4200 / 100.
      expect(scale.anchorDescription, '왼쪽 벽 전체 길이');
    });

    test('calibrate된 scale로 다른 virtual distance를 mm로 정확히 변환할 수 있다', () {
      const a = VirtualCadPoint(0, 0);
      const b = VirtualCadPoint(100, 0);
      final scale = calibrateScaleFromUserAnchor(a: a, b: b, realWorldMm: 4200);
      expect(scale.toMm(50), closeTo(2100, 1e-9));
      expect(scale.toMm(200), closeTo(8400, 1e-9));
    });

    test('toMmPoint는 원점 기준 상대 mm 좌표를 반환한다', () {
      const a = VirtualCadPoint(0, 0);
      const b = VirtualCadPoint(10, 0);
      final scale = calibrateScaleFromUserAnchor(a: a, b: b, realWorldMm: 1000); // 1 virtual unit = 100mm.
      final p = scale.toMmPoint(const VirtualCadPoint(5, 3));
      expect(p, isNotNull);
      expect(p!.xMm, closeTo(500, 1e-9));
      expect(p.yMm, closeTo(300, 1e-9));
    });

    test('두 점이 같아 virtual distance가 0이면 임의 scale을 만들지 않고 unknown으로 남는다', () {
      const a = VirtualCadPoint(50, 50);
      final scale = calibrateScaleFromUserAnchor(a: a, b: a, realWorldMm: 4200);
      expect(scale.confidence, ScaleConfidence.unknown);
      expect(scale.isCalibrated, isFalse);
    });

    test('실제 mm 입력이 0 또는 음수면 임의 scale을 만들지 않고 unknown으로 남는다', () {
      const a = VirtualCadPoint(0, 0);
      const b = VirtualCadPoint(100, 0);
      expect(calibrateScaleFromUserAnchor(a: a, b: b, realWorldMm: 0).isCalibrated, isFalse);
      expect(calibrateScaleFromUserAnchor(a: a, b: b, realWorldMm: -50).isCalibrated, isFalse);
    });
  });
}
