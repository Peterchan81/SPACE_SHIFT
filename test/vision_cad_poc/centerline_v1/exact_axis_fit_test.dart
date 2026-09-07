// SPACE SHIFT — WO088-8C COORDINATE-BASED EXACT WALL CENTERLINE MICRO POC — 테스트.

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/vision_cad_poc/centerline_v1/centerline_model.dart';
import 'package:ason_space/vision_cad_poc/centerline_v1/exact_axis_fit.dart';

RawRunBand _band(String id, bool horizontal, double crossPx, double alongMin, double alongMax) =>
    RawRunBand(id: id, horizontal: horizontal, crossPx: crossPx, alongMinPx: alongMin, alongMaxPx: alongMax, coverageRatio: 1.0, kind: LineKind.solid);

void main() {
  group('fitExactCenterline — robust median fitting', () {
    test('§0/§3 요구사항: 흔들리는(wobbly) skeleton 점들이 하나의 정확한 Y=const 라인으로 수렴한다', () {
      // 사용자가 준 예시와 동일한 형태: (x,200),(x+1,201),(x+2,200),(x+3,201)... 패턴.
      final pair = pairWallBoundaries([_band('a', true, 199, 100, 110), _band('b', true, 201, 100, 110)]).single;
      final wobbly = <Pt>[
        (x: 100.0, y: 200.0),
        (x: 101.0, y: 201.0),
        (x: 102.0, y: 200.0),
        (x: 103.0, y: 201.0),
        (x: 104.0, y: 200.0),
        (x: 105.0, y: 201.0),
        (x: 106.0, y: 200.0),
      ];
      final fit = fitExactCenterline(pair, wobbly, id: 'w1');
      // median of {200,201,200,201,200,201,200} = 200 — 정확히 하나의 값.
      expect(fit.centerline.start.y, fit.centerline.end.y);
      expect(fit.centerline.crossPx, closeTo(200, 1e-9));
      expect(fit.quality.sampleCount, 7);
    });

    test('outlier(잘못 섞여든 evidence)가 있어도 median은 흔들리지 않는다(robust 통계)', () {
      final pair = pairWallBoundaries([_band('a', true, 100, 0, 200), _band('b', true, 110, 0, 200)]).single;
      final points = <Pt>[
        for (var x = 0.0; x < 190; x += 10) (x: x, y: 105.0),
        (x: 50.0, y: 300.0), // 명백한 outlier(다른 구조물에서 섞여든 점 가정).
      ];
      final fit = fitExactCenterline(pair, points, id: 'w2');
      expect(fit.centerline.crossPx, closeTo(105, 1e-9));
      // outlier 하나 때문에 mean은 크게 흔들리지만 median(robust)은 그대로다.
      final naiveMean = points.map((p) => p.y).reduce((a, b) => a + b) / points.length;
      expect((fit.centerline.crossPx - naiveMean).abs(), greaterThan(5));
    });

    test('§11 skeleton evidence 부족(<3개) — boundary 중점 fallback + reviewNeeded=true(확정값과 추정값을 섞지 않는다)', () {
      final pair = pairWallBoundaries([_band('a', true, 100, 0, 200), _band('b', true, 110, 0, 200)]).single;
      final fit = fitExactCenterline(pair, const [(x: 50.0, y: 105.0)], id: 'w3');
      expect(fit.centerline.reviewNeeded, isTrue);
      expect(fit.centerline.crossPx, closeTo(105, 1e-9)); // boundary 중점(100+110)/2.
      expect(fit.quality.sampleCount, 1);
    });

    test('단일 boundary(pairWallBoundaries fallback)는 skeleton evidence가 충분해도 reviewNeeded=true를 유지한다', () {
      final pair = pairWallBoundaries([_band('solo', true, 100, 0, 200)]).single;
      expect(pair.singleBoundary, isTrue);
      final points = <Pt>[for (var x = 0.0; x < 190; x += 5) (x: x, y: 100.0)];
      final fit = fitExactCenterline(pair, points, id: 'w4');
      expect(fit.centerline.reviewNeeded, isTrue);
    });

    test('수직벽(vertical) — median이 X=const로 계산되고 시작/끝 x가 동일하다', () {
      final pair = pairWallBoundaries([_band('a', false, 49, 0, 300), _band('b', false, 51, 0, 300)]).single;
      final points = <Pt>[
        (x: 49.0, y: 10.0),
        (x: 50.0, y: 11.0),
        (x: 51.0, y: 12.0),
        (x: 50.0, y: 13.0),
        (x: 49.0, y: 14.0),
      ];
      final fit = fitExactCenterline(pair, points, id: 'w5');
      expect(fit.centerline.horizontal, isFalse);
      expect(fit.centerline.start.x, fit.centerline.end.x);
      expect(fit.centerline.crossPx, closeTo(50, 1e-9));
    });

    test('residual — 정확히 축 위에 놓인 점들은 residual mean/max가 0이다', () {
      final pair = pairWallBoundaries([_band('a', true, 100, 0, 200), _band('b', true, 110, 0, 200)]).single;
      final points = <Pt>[for (var x = 0.0; x < 190; x += 5) (x: x, y: 105.0)];
      final fit = fitExactCenterline(pair, points, id: 'w6');
      expect(fit.quality.residualMean, 0);
      expect(fit.quality.residualMax, 0);
    });

    test('cross tolerance 밖의 점(다른 벽 소속)은 evidence로 섞이지 않는다', () {
      final pair = pairWallBoundaries([_band('a', true, 100, 0, 200), _band('b', true, 106, 0, 200)]).single;
      final points = <Pt>[
        (x: 10.0, y: 103.0),
        (x: 20.0, y: 103.0),
        (x: 30.0, y: 103.0),
        (x: 40.0, y: 500.0), // 완전히 다른 위치(다른 벽) — tolerance 밖.
      ];
      final fit = fitExactCenterline(pair, points, id: 'w7');
      expect(fit.quality.sampleCount, 3);
      expect(fit.centerline.crossPx, closeTo(103, 1e-9));
    });
  });

  group('buildExactCenterlines — 진입점 통합', () {
    test('여러 wall run이 각각 독립적인 exact centerline으로 변환되고 중복이 없다', () {
      final bands = [
        _band('h1', true, 100, 0, 200),
        _band('h2', true, 110, 0, 200),
        _band('v1', false, 50, 0, 300),
        _band('v2', false, 60, 0, 300),
      ];
      final skeleton = <Pt>[
        for (var x = 0.0; x < 190; x += 10) (x: x, y: 105.0),
        for (var y = 0.0; y < 290; y += 10) (x: 55.0, y: y),
      ];
      final fits = buildExactCenterlines(bands, skeleton);
      expect(fits, hasLength(2));
      final ids = fits.map((f) => f.centerline.id).toSet();
      expect(ids, hasLength(2)); // 서로 다른 id, 중복 없음.
      expect(fits.where((f) => f.centerline.horizontal).single.centerline.crossPx, closeTo(105, 1e-9));
      expect(fits.where((f) => !f.centerline.horizontal).single.centerline.crossPx, closeTo(55, 1e-9));
    });

    test('빈 입력 — 예외 없이 빈 목록을 반환한다', () {
      expect(buildExactCenterlines(const [], const []), isEmpty);
    });
  });

  group('zhangSuenSkeleton — 표준 thinning, 최종 centerline으로 취급되지 않는다', () {
    test('두꺼운 직선 mask가 1px 골격으로 얇아진다', () {
      const w = 20, h = 10;
      final mask = List<int>.filled(w * h, 0);
      for (var y = 4; y <= 6; y++) {
        for (var x = 2; x < 18; x++) {
          mask[y * w + x] = 1;
        }
      }
      final skeleton = zhangSuenSkeleton(mask, w, h);
      final points = skeletonToPoints(skeleton, w, h);
      expect(points, isNotEmpty);
      expect(points.length, lessThan(mask.where((v) => v == 1).length));
      // 골격은 원래 두꺼운 band의 세로 중앙(y=5) 근방에 있어야 한다.
      for (final p in points) {
        expect(p.y, closeTo(5, 1));
      }
    });
  });
}
