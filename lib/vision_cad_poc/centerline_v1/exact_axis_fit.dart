// SPACE SHIFT — WO088-8C COORDINATE-BASED EXACT WALL CENTERLINE MICRO POC.
//
// §0/§3 핵심 원칙: 픽셀(skeleton)은 evidence로만 쓴다. 최종 [Centerline]
// 은 skeleton pixel path를 그대로 따라가지 않고, 각 wall run마다
// robust(median) 통계로 얻은 "하나의 정확한 축 값"(수평벽 Y=const,
// 수직벽 X=const)으로 구성한다.
//
// §18 코드 보호: WO088-7의 [pairWallBoundaries](wall run 분할/extent
// 판정, 이미 검증됨)는 그대로 재사용한다 — "선을 먼저 정확히 맞춘 뒤
// junction을 만든다"는 §7 순서 자체는 WO088-7과 동일하기 때문이다.
// 다만 WO088-7이 쓰던 "두 boundary의 단순 중점"은 이번 WO의 robust
// median 방식으로 대체한다(§5). WO088-6의 mm/snap/평균-junction
// 코드는 이 파일 어디에서도 참조하지 않는다.
//
// junction은 WO088-7의 [buildCenterlineJunctions](line-line 교점 기반,
// endpoint 평균 아님)를 그대로 재사용한다 — 이 함수가 만드는 [Centerline]
// 객체가 이번 WO의 robust-fit 결과이기만 하면, 그 이후 로직(교점 계산)은
// 이미 이번 WO의 §7-10 요구사항과 정확히 일치한다.

import 'dart:math' as math;

import 'centerline_model.dart';

/// 표준 Zhang-Suen thinning(medial-axis 골격화, WO088-8B와 동일한 고정
/// 알고리즘 — Image 4 전용 튜닝 없음). 결과는 "벽 중심 위치 후보점
/// 집합"으로만 쓰인다(§1) — 이 자체를 최종 centerline으로 반환하지 않는다.
List<int> zhangSuenSkeleton(List<int> mask, int w, int h) {
  var current = List<int>.from(mask);
  int at(List<int> m, int x, int y) => (x < 0 || y < 0 || x >= w || y >= h) ? 0 : m[y * w + x];

  var changed = true;
  while (changed) {
    changed = false;
    for (final step in [1, 2]) {
      final toRemove = <int>[];
      for (var y = 1; y < h - 1; y++) {
        for (var x = 1; x < w - 1; x++) {
          if (at(current, x, y) != 1) continue;
          final p2 = at(current, x, y - 1);
          final p3 = at(current, x + 1, y - 1);
          final p4 = at(current, x + 1, y);
          final p5 = at(current, x + 1, y + 1);
          final p6 = at(current, x, y + 1);
          final p7 = at(current, x - 1, y + 1);
          final p8 = at(current, x - 1, y);
          final p9 = at(current, x - 1, y - 1);
          final neighbors = [p2, p3, p4, p5, p6, p7, p8, p9];
          final b = neighbors.fold(0, (s, v) => s + v);
          if (b < 2 || b > 6) continue;
          var a = 0;
          for (var i = 0; i < 8; i++) {
            if (neighbors[i] == 0 && neighbors[(i + 1) % 8] == 1) a++;
          }
          if (a != 1) continue;
          if (step == 1) {
            if (p2 * p4 * p6 != 0) continue;
            if (p4 * p6 * p8 != 0) continue;
          } else {
            if (p2 * p4 * p8 != 0) continue;
            if (p2 * p6 * p8 != 0) continue;
          }
          toRemove.add(y * w + x);
        }
      }
      if (toRemove.isNotEmpty) {
        changed = true;
        final next = List<int>.from(current);
        for (final idx in toRemove) {
          next[idx] = 0;
        }
        current = next;
      }
    }
  }
  return current;
}

List<Pt> skeletonToPoints(List<int> skeleton, int w, int h) {
  final out = <Pt>[];
  for (var i = 0; i < skeleton.length; i++) {
    if (skeleton[i] == 1) out.add((x: (i % w).toDouble(), y: (i ~/ w).toDouble()));
  }
  return out;
}

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final n = sorted.length;
  if (n.isOdd) return sorted[n ~/ 2];
  return (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
}

/// §15 fitting 품질 — pixel/evidence residual이지 mm 정확도가 아니다.
class AxisFitQuality {
  const AxisFitQuality({required this.sampleCount, required this.residualMean, required this.residualMax});
  final int sampleCount;
  final double residualMean;
  final double residualMax;
}

class ExactCenterlineFit {
  const ExactCenterlineFit({required this.centerline, required this.quality, required this.pairSingleBoundary});
  final Centerline centerline;
  final AxisFitQuality quality;
  final bool pairSingleBoundary;
}

/// §5 — [pair](WO088-7 boundary pairing, extent/along-span 판정에만 재사용)
/// 범위 안의 skeleton 후보점을 모아 robust(median) center axis를 계산한다.
/// §11 — skeleton 후보가 부족하면(<3개) pair의 boundary 중점으로
/// fallback하되 reviewNeeded=true로 정직하게 남긴다(추정값과 확정값을
/// 섞지 않는다).
ExactCenterlineFit fitExactCenterline(
  WallBoundaryPair pair,
  List<Pt> skeletonPoints, {
  required String id,
  double crossToleranceMarginPx = 6,
}) {
  final crossTolerance = math.max((pair.spacingPx ?? 10.0), 10.0) / 2 + crossToleranceMarginPx;
  final candidates = skeletonPoints.where((p) {
    final along = pair.horizontal ? p.x : p.y;
    final cross = pair.horizontal ? p.y : p.x;
    if (along < pair.alongMinPx - 2 || along > pair.alongMaxPx + 2) return false;
    if ((cross - pair.centerCrossPx).abs() > crossTolerance) return false;
    return true;
  }).toList();

  double robustCross;
  List<double> residuals = const [];
  final enoughEvidence = candidates.length >= 3;
  if (enoughEvidence) {
    final crosses = candidates.map((p) => pair.horizontal ? p.y : p.x).toList();
    robustCross = _median(crosses);
    residuals = crosses.map((c) => (c - robustCross).abs()).toList();
  } else {
    // skeleton evidence 부족 — WO088-7이 이미 계산해 둔 boundary 중점을
    // "추정 fallback"으로만 쓰고 reviewNeeded로 표시한다(§11).
    robustCross = pair.centerCrossPx;
  }

  final start = pair.horizontal ? (x: pair.alongMinPx, y: robustCross) : (x: robustCross, y: pair.alongMinPx);
  final end = pair.horizontal ? (x: pair.alongMaxPx, y: robustCross) : (x: robustCross, y: pair.alongMaxPx);
  final reviewNeeded = pair.singleBoundary || !enoughEvidence;

  final centerline = Centerline(
    id: id,
    start: start,
    end: end,
    horizontal: pair.horizontal,
    sourceBoundaryIds: [pair.boundaryAId, if (pair.boundaryBId != null) pair.boundaryBId!],
    confidence: reviewNeeded ? 0.5 : 0.95,
    reviewNeeded: reviewNeeded,
    evidence: enoughEvidence
        ? 'robust median of ${candidates.length} skeleton evidence points(±${crossTolerance.toStringAsFixed(1)}px band)'
        : 'skeleton evidence 부족(${candidates.length}개) — boundary 중점 fallback(review 필요)',
  );

  return ExactCenterlineFit(
    centerline: centerline,
    quality: AxisFitQuality(
      sampleCount: candidates.length,
      residualMean: residuals.isEmpty ? 0 : residuals.reduce((a, b) => a + b) / residuals.length,
      residualMax: residuals.isEmpty ? 0 : residuals.reduce(math.max),
    ),
    pairSingleBoundary: pair.singleBoundary,
  );
}

/// §7 진입점 — solid wall band evidence + skeleton 후보점에서 시작해
/// (1) wall run 분할/extent(WO088-7 pairWallBoundaries 재사용) →
/// (2) 각 run의 robust exact axis fitting(이 파일의 신규 로직) 순서로
/// [ExactCenterlineFit] 목록을 만든다. Junction은 여기서 만들지 않는다
/// (§7 "선이 먼저 정확해야 한다" — 호출자가 결과 `Centerline` 목록을
/// `buildCenterlineJunctions`에 넘겨 별도로 계산한다).
List<ExactCenterlineFit> buildExactCenterlines(List<RawRunBand> solidBands, List<Pt> skeletonPoints) {
  final pairs = pairWallBoundaries(solidBands);
  return [for (var i = 0; i < pairs.length; i++) fitExactCenterline(pairs[i], skeletonPoints, id: 'exact-$i')];
}
