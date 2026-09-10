// WO095-B 재설계 — "3D 아이소 Architectural Dollhouse 표현"의 핵심 순수
// geometry 계산(computeIsoSectionCut/computeIsoSectionCutFraction) 단위
// 테스트.
//
// WO093~WO095-A는 모두 "벽 하나하나에 대해 무엇을 할지" 판정하는
// 방식이었다 — 실측(평면도.PNG, 벽 86개)에서 벽이 조밀하게 몰린 구석이
// 있으면 그 구석 전체가 "덩어리"처럼 남는 문제를 반복 재현했다(WO095-A
// 재현: "뒤쪽"으로 뽑힌 9개 벽이 전부 건물 외곽이 아니라 한 구석에 몰린
// 작은 방 클러스터였다). WO095-B는 벽 단위 판정을 버리고, 건물 전체
// bounding box + 카메라 방향으로 계산한 단일 절단면(clip plane) 위치만
// 계산한다 — 실제 GPU clipping(three_js Material.clipping +
// renderer.clippingPlanes)은 위젯에서 적용하고, 여기서는 그 절단면이
// "어디"에 와야 하는지 순수 스칼라 계산만 검증한다.
import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/services/iso_cutaway.dart';

void main() {
  group('computeIsoSectionCutFraction — 확대할수록 절단 비율이 줄어든다', () {
    test('카메라가 기준 거리(referenceDistance)와 같으면 baseFraction 그대로', () {
      expect(
        computeIsoSectionCutFraction(orbitDistance: 5000, referenceDistance: 5000),
        closeTo(0.3, 1e-9),
      );
    });

    test('카메라가 거의 0까지 확대하면 minFraction에 가까워진다', () {
      expect(
        computeIsoSectionCutFraction(orbitDistance: 0, referenceDistance: 5000),
        closeTo(0.08, 1e-9),
      );
    });

    test('기준 거리의 절반이면 baseFraction과 minFraction의 정확히 중간값', () {
      // ratio=0.5 -> 0.08 + (0.3-0.08)*0.5 = 0.19
      expect(
        computeIsoSectionCutFraction(orbitDistance: 2500, referenceDistance: 5000),
        closeTo(0.19, 1e-9),
      );
    });

    test('카메라가 기준 거리보다 더 멀어져도(축소) baseFraction을 넘지 않는다', () {
      expect(
        computeIsoSectionCutFraction(orbitDistance: 20000, referenceDistance: 5000),
        closeTo(0.3, 1e-9),
      );
    });

    test('referenceDistance가 0 이하이면 안전하게 baseFraction을 그대로 돌려준다', () {
      expect(
        computeIsoSectionCutFraction(orbitDistance: 1000, referenceDistance: 0),
        closeTo(0.3, 1e-9),
      );
    });

    test('baseFraction/minFraction을 직접 지정할 수 있다(하드코딩된 값에 의존하지 않음)', () {
      expect(
        computeIsoSectionCutFraction(
          orbitDistance: 0,
          referenceDistance: 1000,
          baseFraction: 0.5,
          minFraction: 0.2,
        ),
        closeTo(0.2, 1e-9),
      );
    });
  });

  group('computeIsoSectionCut — 건물 bounding box + 카메라 방향으로 절단 위치 계산', () {
    // 원점 중심 20x20 정사각형(x:-10~10, z:-10~10), 카메라는 원점에서
    // +X 방향을 바라본다(dir=(1,0)). 각 모서리를 +X 축에 투영하면
    // x좌표 그대로(-10 또는 10)가 depth가 된다.
    const squareCorners = [(-10.0, -10.0), (10.0, -10.0), (10.0, 10.0), (-10.0, 10.0)];

    test('깊이 범위(min/max)를 정확히 계산한다', () {
      final result = computeIsoSectionCut(
        cameraX: 0,
        cameraZ: 0,
        dirX: 1,
        dirZ: 0,
        boundingCornersXZ: squareCorners,
        cutFraction: 0.3,
      );
      expect(result.minDepth, closeTo(-10, 1e-9));
      expect(result.maxDepth, closeTo(10, 1e-9));
    });

    test('cutFraction 0.3이면 깊이 범위의 30% 지점(-10+20*0.3=-4)이 절단 위치', () {
      final result = computeIsoSectionCut(
        cameraX: 0,
        cameraZ: 0,
        dirX: 1,
        dirZ: 0,
        boundingCornersXZ: squareCorners,
        cutFraction: 0.3,
      );
      expect(result.cutDepth, closeTo(-4, 1e-9));
    });

    test('cutFraction 0이면 가장 가까운(카메라 쪽) 모서리 지점이 절단 위치', () {
      final result = computeIsoSectionCut(
        cameraX: 0,
        cameraZ: 0,
        dirX: 1,
        dirZ: 0,
        boundingCornersXZ: squareCorners,
        cutFraction: 0,
      );
      expect(result.cutDepth, closeTo(-10, 1e-9));
    });

    test('카메라가 건물 밖 멀리 있어도 같은 비율로 정확히 계산된다(카메라 상대 좌표)', () {
      final result = computeIsoSectionCut(
        cameraX: -100,
        cameraZ: 0,
        dirX: 1,
        dirZ: 0,
        boundingCornersXZ: squareCorners,
        cutFraction: 0.3,
      );
      // 카메라가 (-100,0)이므로 각 모서리까지의 투영 depth는 x-(-100)=x+100.
      // min=(-10+100)=90, max=(10+100)=110, cut=90+20*0.3=96.
      expect(result.minDepth, closeTo(90, 1e-9));
      expect(result.maxDepth, closeTo(110, 1e-9));
      expect(result.cutDepth, closeTo(96, 1e-9));
    });

    test('회전해서 반대 방향(-X)을 바라보면 depth 부호가 뒤집혀 절단 위치도 반대가 된다', () {
      final result = computeIsoSectionCut(
        cameraX: 0,
        cameraZ: 0,
        dirX: -1,
        dirZ: 0,
        boundingCornersXZ: squareCorners,
        cutFraction: 0.3,
      );
      // dir=(-1,0)이면 depth = -x이므로 모서리 x=-10 -> depth=10,
      // x=10 -> depth=-10. min=-10, max=10(동일 범위지만 절단 위치는
      // 이제 이전과 반대편 근처).
      expect(result.cutDepth, closeTo(-4, 1e-9));
    });

    test('bounding 모서리가 비어 있으면(퇴화 케이스) 안전하게 0을 돌려준다', () {
      final result = computeIsoSectionCut(
        cameraX: 0,
        cameraZ: 0,
        dirX: 1,
        dirZ: 0,
        boundingCornersXZ: const [],
        cutFraction: 0.3,
      );
      expect(result.cutDepth, 0);
      expect(result.minDepth, 0);
      expect(result.maxDepth, 0);
    });
  });
}
