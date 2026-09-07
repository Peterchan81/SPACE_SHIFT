// SPACE SHIFT — WO088-7 §8 CENTERLINE JUNCTION BY LINE GEOMETRY.
//
// WO088-6과의 핵심 차이: endpoint를 모아 평균내지 않는다. 두 centerline이
// 수평/수직이면 그 "무한 직선"의 교점(수평선의 y, 수직선의 x로 즉시
// 계산되는 (x,y))을 evidence로 우선 사용하고, 그 교점이 각 line의 실제
// extent 안(또는 아주 작은 허용오차 안)에 있는지만 확인한다. 두 extent
// 모두의 "끝"에 걸리면 L, 한쪽만 끝이면 T, 둘 다 중간이면 X로 판정한다.
// 교점이 어느 한쪽 extent를 벗어나면(즉 그 방향으로 더 연장해야만
// 만나면) 억지로 연결하지 않고 reviewNeeded로 남긴다(§9).

import 'dart:math' as math;

import 'centerline_model.dart';

enum JunctionKind { lJunction, tJunction, xJunction, straightContinuation, endpoint, reviewNeeded }

class CenterlineJunction {
  const CenterlineJunction({required this.id, required this.point, required this.kind, required this.memberIds});
  final String id;
  final Pt point;
  final JunctionKind kind;

  /// 이 junction에 관여하는 centerline id들(±끝점 구분 없이, 어떤
  /// centerline이 이 접점을 참조하는지만 기록).
  final List<String> memberIds;
}

/// §8 — line 끝점 근처("애매하게 가깝다"는 근거만으로 자동 연결하지
/// 않기 위한, 순수 evidence 판정용) 허용오차. 픽셀 추출 자체의 위치
/// 오차(anti-alias/두께 중심 오차) 규모에 맞춘 일반 상수 — 이미지별
/// 튜닝값이 아니다.
const double _cornerEvidenceTolerancePx = 4.0;

/// §9 — 이 거리보다 멀면 "가까워 보여도" 절대 자동 연결하지 않는다.
const double _reviewBandPx = 15.0;

(double, double)? _lineIntersection(Centerline h, Centerline v) {
  if (!h.horizontal || v.horizontal) return null;
  // h: y = h.crossPx, x in [h.alongMin, h.alongMax]. v: x = v.crossPx, y in [...].
  return (v.crossPx, h.crossPx);
}

bool _nearEnd(double value, double a, double b, double tol) => (value - a).abs() <= tol || (value - b).abs() <= tol;

bool _withinExtent(double value, double min, double max, double tol) => value >= min - tol && value <= max + tol;

/// [lines]의 모든 수평×수직 쌍에 대해 교점 evidence를 계산해 junction을
/// 만든다. 같은 방향끼리는(수평-수평, 수직-수직) collinear 연속(§8
/// straight continuation)만 검사한다.
List<CenterlineJunction> buildCenterlineJunctions(List<Centerline> lines) {
  final junctions = <CenterlineJunction>[];
  var counter = 0;
  // centerline id -> 이미 확정 junction에 배정된 "위치"(중복 방지용).
  final assignedPoints = <String, List<(double x, double y, String jid)>>{};

  void assignTo(String lineId, double x, double y, String jid) {
    assignedPoints.putIfAbsent(lineId, () => []).add((x, y, jid));
  }

  final horizontals = lines.where((l) => l.horizontal).toList();
  final verticals = lines.where((l) => !l.horizontal).toList();

  for (final h in horizontals) {
    for (final v in verticals) {
      final inter = _lineIntersection(h, v);
      if (inter == null) continue;
      final (ix, iy) = inter;
      final hOk = _withinExtent(ix, h.alongMinPx, h.alongMaxPx, _reviewBandPx);
      final vOk = _withinExtent(iy, v.alongMinPx, v.alongMaxPx, _reviewBandPx);
      if (!hOk || !vOk) continue; // 교점이 두 line 근처에도 없음 — 무관.

      final hConfident = _withinExtent(ix, h.alongMinPx, h.alongMaxPx, _cornerEvidenceTolerancePx);
      final vConfident = _withinExtent(iy, v.alongMinPx, v.alongMaxPx, _cornerEvidenceTolerancePx);

      JunctionKind kind;
      if (!hConfident || !vConfident) {
        // 근처이긴 하지만 실제로 닿는다고 확신할 evidence(§ tolerance)가 부족.
        kind = JunctionKind.reviewNeeded;
      } else {
        final hEnd = _nearEnd(ix, h.alongMinPx, h.alongMaxPx, _cornerEvidenceTolerancePx);
        final vEnd = _nearEnd(iy, v.alongMinPx, v.alongMaxPx, _cornerEvidenceTolerancePx);
        if (hEnd && vEnd) {
          kind = JunctionKind.lJunction;
        } else if (hEnd || vEnd) {
          kind = JunctionKind.tJunction;
        } else {
          kind = JunctionKind.xJunction;
        }
      }

      final id = 'jx-${counter++}';
      junctions.add(CenterlineJunction(id: id, point: (x: ix, y: iy), kind: kind, memberIds: [h.id, v.id]));
      assignTo(h.id, ix, iy, id);
      assignTo(v.id, ix, iy, id);
    }
  }

  // 같은 방향끼리 — collinear 연속(§8 straight continuation)만 확인.
  void checkCollinear(List<Centerline> group, bool horizontal) {
    for (var i = 0; i < group.length; i++) {
      for (var j = i + 1; j < group.length; j++) {
        final a = group[i], b = group[j];
        if ((a.crossPx - b.crossPx).abs() > _cornerEvidenceTolerancePx) continue;
        final gap = horizontal
            ? math.max(a.alongMinPx, b.alongMinPx) - math.min(a.alongMaxPx, b.alongMaxPx)
            : math.max(a.alongMinPx, b.alongMinPx) - math.min(a.alongMaxPx, b.alongMaxPx);
        if (gap.abs() > _reviewBandPx) continue;
        final kind = gap.abs() <= _cornerEvidenceTolerancePx ? JunctionKind.straightContinuation : JunctionKind.reviewNeeded;
        final px = horizontal ? (a.alongMaxPx < b.alongMinPx ? a.alongMaxPx : b.alongMaxPx) : a.crossPx;
        final py = horizontal ? a.crossPx : (a.alongMaxPx < b.alongMinPx ? a.alongMaxPx : b.alongMaxPx);
        final id = 'jx-${counter++}';
        junctions.add(CenterlineJunction(id: id, point: (x: px, y: py), kind: kind, memberIds: [a.id, b.id]));
        assignTo(a.id, px, py, id);
        assignTo(b.id, px, py, id);
      }
    }
  }

  checkCollinear(horizontals, true);
  checkCollinear(verticals, false);

  // 어느 junction에도 배정되지 못한 endpoint는 endpoint로 남긴다.
  for (final l in lines) {
    final assigned = assignedPoints[l.id] ?? const [];
    final hasStart = assigned.any((p) => (p.$1 - l.start.x).abs() <= _cornerEvidenceTolerancePx && (p.$2 - l.start.y).abs() <= _cornerEvidenceTolerancePx);
    final hasEnd = assigned.any((p) => (p.$1 - l.end.x).abs() <= _cornerEvidenceTolerancePx && (p.$2 - l.end.y).abs() <= _cornerEvidenceTolerancePx);
    if (!hasStart) {
      junctions.add(CenterlineJunction(id: 'jx-${counter++}', point: l.start, kind: JunctionKind.endpoint, memberIds: [l.id]));
    }
    if (!hasEnd) {
      junctions.add(CenterlineJunction(id: 'jx-${counter++}', point: l.end, kind: JunctionKind.endpoint, memberIds: [l.id]));
    }
  }

  return junctions;
}
