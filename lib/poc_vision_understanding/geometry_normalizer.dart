import 'dart:math' as math;

import 'floorplan_semantic_model.dart';

/// SS Geometry Engine 단계(WO 지시 4번) — "AI/Understanding은 무엇인가를
/// 판단하고, SS Geometry Engine은 정확히 어떻게 연결되는가를 확정한다."
///
/// 의미 이해 단계([FloorplanUnderstanding])가 만든 근사 좌표를 받아:
/// - 거의 같은 좌표를 하나로 snap한다(작은 좌표 오차/틈 보정).
/// - 각 폴리곤에서 불필요한 중간(직선 위) 점을 제거한다.
/// - 폴리곤이 최소 3점을 유지하는지 확인한다.
///
/// 대각/비정형 외곽은 강제로 직각화하지 않는다(WO 지시 4번 "대각벽을
/// 강제로 직각화하지 않음") — 오직 "거의 같은 값"을 정리할 뿐, 없는
/// 직각 관계를 만들어내지 않는다.
class GeometryNormalizer {
  const GeometryNormalizer({this.snapTolerance = 0.08});

  /// 이 값(미터)보다 가까운 좌표는 같은 값으로 snap한다.
  final double snapTolerance;

  FloorplanUnderstanding normalize(FloorplanUnderstanding input) {
    final snapper = _CoordinateSnapper(snapTolerance);

    // 모든 폴리곤/점을 한 번에 훑어 snap 기준점을 먼저 수집한다 —
    // Space, FloorDomain, Boundary, Opening, Object가 서로 다른 곳에서
    // 만든 좌표라도 실제로는 같은 벽 모서리를 가리키면 하나로 합친다.
    for (final space in input.spaces) {
      for (final p in space.polygon) {
        snapper.observe(p);
      }
    }
    for (final p in input.floorDomain) {
      snapper.observe(p);
    }
    for (final boundary in input.boundaries) {
      for (final p in boundary.geometry) {
        snapper.observe(p);
      }
    }

    List<Pt> normalizePolygon(List<Pt> polygon) {
      final snapped = [for (final p in polygon) snapper.snap(p)];
      return _removeCollinearAndDuplicates(snapped);
    }

    return FloorplanUnderstanding(
      source: input.source,
      scaleConfirmed: input.scaleConfirmed,
      notes: input.notes,
      floorDomain: normalizePolygon(input.floorDomain),
      spaces: [
        for (final space in input.spaces)
          SemanticSpace(
            id: space.id,
            name: space.name,
            polygon: normalizePolygon(space.polygon),
            confidence: space.confidence,
          ),
      ],
      boundaries: [
        for (final boundary in input.boundaries)
          SemanticBoundary(
            id: boundary.id,
            type: boundary.type,
            geometry: [for (final p in boundary.geometry) snapper.snap(p)],
            adjacentSpaceIds: boundary.adjacentSpaceIds,
          ),
      ],
      openings: input.openings,
      structuralObjects: input.structuralObjects,
      nonStructuralObjects: input.nonStructuralObjects,
    );
  }
}

/// 서로 [tolerance] 안에 있는 좌표를 같은 대표값으로 합친다 — 실제
/// detection/이해 단계에서 "거의 같은 선"이 미세하게 다른 좌표로
/// 나오는 흔한 오차를 흡수한다. 대표값은 그 그룹에 처음 관찰된 값을
/// 그대로 쓴다(임의로 반올림해 없는 직각을 만들지 않는다).
class _CoordinateSnapper {
  _CoordinateSnapper(this.tolerance);

  final double tolerance;
  final List<Pt> _representatives = [];

  void observe(Pt p) {
    for (final rep in _representatives) {
      if (_distance(rep, p) <= tolerance) return;
    }
    _representatives.add(p);
  }

  Pt snap(Pt p) {
    Pt? best;
    var bestDist = double.infinity;
    for (final rep in _representatives) {
      final d = _distance(rep, p);
      if (d <= tolerance && d < bestDist) {
        best = rep;
        bestDist = d;
      }
    }
    return best ?? p;
  }

  double _distance(Pt a, Pt b) {
    final dx = a.x - b.x, dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }
}

List<Pt> _removeCollinearAndDuplicates(List<Pt> polygon) {
  if (polygon.length < 3) return polygon;
  const eps = 1e-6;

  final deduped = <Pt>[];
  for (final p in polygon) {
    if (deduped.isEmpty ||
        (deduped.last.x - p.x).abs() > eps ||
        (deduped.last.y - p.y).abs() > eps) {
      deduped.add(p);
    }
  }
  if (deduped.length > 1 &&
      (deduped.first.x - deduped.last.x).abs() < eps &&
      (deduped.first.y - deduped.last.y).abs() < eps) {
    deduped.removeLast();
  }
  if (deduped.length < 3) return deduped;

  final result = <Pt>[];
  for (var i = 0; i < deduped.length; i++) {
    final prev = deduped[(i - 1 + deduped.length) % deduped.length];
    final cur = deduped[i];
    final next = deduped[(i + 1) % deduped.length];
    final cross = (cur.x - prev.x) * (next.y - prev.y) - (cur.y - prev.y) * (next.x - prev.x);
    if (cross.abs() > eps) result.add(cur);
  }
  return result.length >= 3 ? result : deduped;
}
