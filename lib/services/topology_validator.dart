import 'dart:math' as math;

import '../models/floor_plan_geometry.dart';
import '../models/ss_spatial_model.dart';

/// Vision Guided CAD POC — Topology Validator(설계 6번).
///
/// [SSSpatialModel]이 "그림으로는 그럴듯해 보이지만 건축적으로 말이 안
/// 되는" 상태가 아닌지 11가지 규칙으로 검증한다. 어떤 규칙이 실패해도
/// geometry를 임의로 고쳐서 통과시키지 않는다 — 항상 해당 entity의
/// confidence를 낮추고 reviewNeeded=true + 이유를 남긴 채 그대로
/// 돌려준다(정직한 불확실성 보존 원칙).
///
/// [floorDomain]이 없는 모델(기존 space-first/envelope-first 경로)에서는
/// floorDomain에 의존하는 규칙(1/4)을 건너뛴다 — 이 검증기는 새 경로만
/// 강제하지 않고 두 경로 모두에 안전하게 적용할 수 있어야 한다.
class TopologyValidator {
  const TopologyValidator();

  SSSpatialModel validate(SSSpatialModel model) {
    final warnings = <String>[...model.warnings];

    // 1. FloorDomain closure
    warnings.addAll(_checkFloorDomainClosure(model));

    // 2. exterior boundary connectivity
    warnings.addAll(_checkExteriorBoundaryConnectivity(model));

    // 3 & 4는 공간별로 처리(space 목록을 재구성해야 하므로 아래에서 함께 처리).
    final objectPolygons = [for (final o in model.objects) o.polygon];

    final spaces = <SSSpace>[];
    for (final space in model.spaces) {
      final reasons = <String>[];

      if (_polygonSelfIntersects(space.polygon)) {
        reasons.add('rule 3 (self-intersection rejection): space polygon self-intersects');
      }
      if (model.floorDomain != null) {
        final outside = space.polygon.where((p) => !_pointInOrOnPolygon(p, model.floorDomain!));
        if (outside.isNotEmpty) {
          reasons.add(
            'rule 4 (space must not exit FloorDomain): '
            '${outside.length} vertex(es) fall outside the building envelope',
          );
        }
      }

      if (reasons.isEmpty) {
        spaces.add(space);
      } else {
        spaces.add(
          space.copyWith(
            reviewNeeded: true,
            reviewReasons: [...space.reviewReasons, ...reasons],
          ),
        );
      }
    }

    // 5 & 6: 벽이 가구 위에 세워지거나, 가구 안에서 끝나지 않는지.
    final walls = <SSWall>[];
    for (final wall in model.walls) {
      final reasons = <String>[];
      for (final obj in objectPolygons) {
        if (_pointInPolygon(wall.start, obj) && _pointInPolygon(wall.end, obj)) {
          reasons.add(
            'rule 5 (furniture must not create a space boundary): '
            'wall segment lies entirely inside a detected furniture/equipment footprint',
          );
        } else if (_pointInPolygon(wall.start, obj) || _pointInPolygon(wall.end, obj)) {
          reasons.add(
            'rule 6 (interior wall must not terminate inside furniture): '
            'a wall endpoint falls inside a detected furniture/equipment footprint',
          );
        }
      }
      if (reasons.isEmpty) {
        walls.add(wall);
      } else {
        walls.add(
          SSWall(
            id: wall.id,
            start: wall.start,
            end: wall.end,
            thicknessNormalized: wall.thicknessNormalized,
            kind: wall.kind,
            confidence: wall.confidence * 0.5,
            separatesSpaceIds: wall.separatesSpaceIds,
            source: wall.source,
            reviewNeeded: true,
            reviewReasons: [...wall.reviewReasons, ...reasons],
          ),
        );
      }
    }

    // 7, 8, 9, 11: opening 관련 규칙.
    final spaceIds = model.spaces.map((s) => s.id).toSet();
    final wallById = {for (final w in walls) w.id: w};
    final openings = <SSOpening>[];
    for (final opening in model.openings) {
      final reasons = <String>[];

      final attachedWall = opening.wallId == null ? null : wallById[opening.wallId];
      final nearAnyWall = attachedWall != null || walls.any((w) {
        return _pointToSegmentDistance(opening.center, w.start, w.end) <=
            math.max(opening.widthNormalized, 0.01);
      });
      if (!nearAnyWall) {
        reasons.add(
          'rule 7 (door must attach to a boundary): opening is not attached to '
          'and does not lie near any known wall segment',
        );
      }

      final unknownRefs = opening.connectsSpaceIds.where((id) => !spaceIds.contains(id)).toList();
      if (unknownRefs.isNotEmpty) {
        reasons.add(
          'rule 8 (opening must match real adjacent spaces): connects to unknown '
          'space id(s) $unknownRefs',
        );
      }

      if (opening.kind == SSOpeningKind.window && opening.connectsSpaceIds.length >= 2) {
        reasons.add(
          'rule 9 (window must not be a traversable connection): a window opening '
          'connects two interior spaces like a door/passage',
        );
      }

      if (attachedWall != null) {
        final t = _projectParameter(opening.center, attachedWall.start, attachedWall.end);
        final wallLen = attachedWall.start.distanceTo(attachedWall.end);
        final stub = wallLen > 0 ? (opening.widthNormalized / 2) / wallLen : 1.0;
        if (t <= stub || t >= 1 - stub) {
          reasons.add(
            'rule 11 (opening must not break wall connectivity): opening sits at '
            'or beyond the wall endpoint, leaving no valid wall stub on one side',
          );
        }
      }

      if (reasons.isEmpty) {
        openings.add(opening);
      } else {
        openings.add(
          SSOpening(
            id: opening.id,
            kind: opening.kind,
            center: opening.center,
            widthNormalized: opening.widthNormalized,
            confidence: opening.confidence * 0.5,
            wallId: opening.wallId,
            connectsSpaceIds: opening.connectsSpaceIds,
            source: opening.source,
            reviewNeeded: true,
            reviewReasons: [...opening.reviewReasons, ...reasons],
          ),
        );
      }
    }

    // 10. no-abnormal-room-overlap.
    final overlapReasons = <String, List<String>>{};
    for (var i = 0; i < spaces.length; i++) {
      for (var j = i + 1; j < spaces.length; j++) {
        final ratio = _overlapAreaRatio(spaces[i].polygon, spaces[j].polygon);
        if (ratio > 0.15) {
          final reason =
              'rule 10 (no abnormal room overlap): overlaps with space '
              '${spaces[j].id} by an estimated ${(ratio * 100).round()}% of its area';
          overlapReasons.putIfAbsent(spaces[i].id, () => []).add(reason);
          overlapReasons
              .putIfAbsent(spaces[j].id, () => [])
              .add(
                'rule 10 (no abnormal room overlap): overlaps with space '
                '${spaces[i].id} by an estimated ${(ratio * 100).round()}% of its area',
              );
        }
      }
    }
    final finalSpaces = [
      for (final s in spaces)
        if (overlapReasons.containsKey(s.id))
          s.copyWith(reviewNeeded: true, reviewReasons: [...s.reviewReasons, ...overlapReasons[s.id]!])
        else
          s,
    ];

    return SSSpatialModel(
      sourceWidthPx: model.sourceWidthPx,
      sourceHeightPx: model.sourceHeightPx,
      spaces: finalSpaces,
      walls: walls,
      openings: openings,
      objects: model.objects,
      warnings: warnings,
      boundaries: model.boundaries,
      structuralElements: model.structuralElements,
      dimensions: model.dimensions,
      floorDomain: model.floorDomain,
    );
  }

  List<String> _checkFloorDomainClosure(SSSpatialModel model) {
    final domain = model.floorDomain;
    if (domain == null) return const [];
    if (domain.length < 3) {
      return ['rule 1 (FloorDomain closure): outline has fewer than 3 points'];
    }
    for (var i = 0; i < domain.length; i++) {
      final a = domain[i];
      final b = domain[(i + 1) % domain.length];
      if ((a.x - b.x).abs() < 1e-9 && (a.y - b.y).abs() < 1e-9) {
        return ['rule 1 (FloorDomain closure): outline has a zero-length edge at index $i'];
      }
    }
    if (_polygonSelfIntersects(domain)) {
      return ['rule 1 (FloorDomain closure): outline self-intersects'];
    }
    return const [];
  }

  List<String> _checkExteriorBoundaryConnectivity(SSSpatialModel model) {
    final exterior = model.boundaries.where((b) => b.isExterior).toList();
    if (exterior.isEmpty) return const [];

    const tolerance = 0.01;
    String key(Point2 p) =>
        '${(p.x / tolerance).round()}:${(p.y / tolerance).round()}';

    final degree = <String, int>{};
    for (final b in exterior) {
      degree[key(b.start)] = (degree[key(b.start)] ?? 0) + 1;
      degree[key(b.end)] = (degree[key(b.end)] ?? 0) + 1;
    }
    final dangling = degree.entries.where((e) => e.value < 2).length;
    if (dangling > 0) {
      return [
        'rule 2 (exterior boundary connectivity): $dangling exterior boundary '
            'endpoint(s) do not connect to another exterior segment — the outline '
            'may not form a closed loop',
      ];
    }
    return const [];
  }

  double _projectParameter(Point2 p, Point2 a, Point2 b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final lenSq = dx * dx + dy * dy;
    if (lenSq == 0) return 0;
    return ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq;
  }

  double _pointToSegmentDistance(Point2 p, Point2 a, Point2 b) {
    final t = _projectParameter(p, a, b).clamp(0.0, 1.0);
    final projX = a.x + t * (b.x - a.x);
    final projY = a.y + t * (b.y - a.y);
    final dx = p.x - projX;
    final dy = p.y - projY;
    return math.sqrt(dx * dx + dy * dy);
  }

  bool _pointInPolygon(Point2 p, List<Point2> polygon) {
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final a = polygon[i];
      final b = polygon[j];
      final intersects =
          ((a.y > p.y) != (b.y > p.y)) &&
          (p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x);
      if (intersects) inside = !inside;
    }
    return inside;
  }

  bool _pointInOrOnPolygon(Point2 p, List<Point2> polygon) {
    if (_pointInPolygon(p, polygon)) return true;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      if (_pointToSegmentDistance(p, polygon[j], polygon[i]) < 1e-6) return true;
    }
    return false;
  }

  bool _segmentsProperlyIntersect(Point2 p1, Point2 p2, Point2 p3, Point2 p4) {
    double cross(Point2 o, Point2 a, Point2 b) => (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
    final d1 = cross(p3, p4, p1);
    final d2 = cross(p3, p4, p2);
    final d3 = cross(p1, p2, p3);
    final d4 = cross(p1, p2, p4);
    return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
  }

  bool _polygonSelfIntersects(List<Point2> polygon) {
    final n = polygon.length;
    if (n < 4) return false;
    for (var i = 0; i < n; i++) {
      final a1 = polygon[i];
      final a2 = polygon[(i + 1) % n];
      for (var j = i + 1; j < n; j++) {
        if (j == i || j == (i + 1) % n || (j + 1) % n == i) continue;
        final b1 = polygon[j];
        final b2 = polygon[(j + 1) % n];
        if (_segmentsProperlyIntersect(a1, a2, b1, b2)) return true;
      }
    }
    return false;
  }

  double _polygonArea(List<Point2> polygon) {
    var sum = 0.0;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      sum += polygon[j].x * polygon[i].y - polygon[i].x * polygon[j].y;
    }
    return sum.abs() / 2;
  }

  /// 두 폴리곤이 겹치는 비율을 정밀한 클리핑 없이 격자 샘플링으로
  /// 추정한다 — POC 범위에서는 충분히 정직한 근사치다(임의로 "겹치지
  /// 않는다"고 단정하지 않는다).
  double _overlapAreaRatio(List<Point2> a, List<Point2> b) {
    // 폴리곤 유도에 실패한 공간(설계상 bbox로 대체하지 않고 빈
    // polygon으로 남긴다)은 겹침을 계산할 수 없다 — 0으로 처리한다.
    if (a.length < 3 || b.length < 3) return 0;
    final minAx = a.map((p) => p.x).reduce(math.min);
    final maxAx = a.map((p) => p.x).reduce(math.max);
    final minAy = a.map((p) => p.y).reduce(math.min);
    final maxAy = a.map((p) => p.y).reduce(math.max);
    final minBx = b.map((p) => p.x).reduce(math.min);
    final maxBx = b.map((p) => p.x).reduce(math.max);
    final minBy = b.map((p) => p.y).reduce(math.min);
    final maxBy = b.map((p) => p.y).reduce(math.max);

    final minX = math.max(minAx, minBx);
    final maxX = math.min(maxAx, maxBx);
    final minY = math.max(minAy, minBy);
    final maxY = math.min(maxAy, maxBy);
    if (minX >= maxX || minY >= maxY) return 0;

    const gridSize = 16;
    var insideBoth = 0;
    for (var gy = 0; gy < gridSize; gy++) {
      for (var gx = 0; gx < gridSize; gx++) {
        final px = minX + (maxX - minX) * (gx + 0.5) / gridSize;
        final py = minY + (maxY - minY) * (gy + 0.5) / gridSize;
        final p = Point2(px, py);
        if (_pointInPolygon(p, a) && _pointInPolygon(p, b)) insideBoth++;
      }
    }
    final overlapArea = insideBoth / (gridSize * gridSize) * (maxX - minX) * (maxY - minY);
    final smallerArea = math.min(_polygonArea(a), _polygonArea(b));
    if (smallerArea <= 0) return 0;
    return overlapArea / smallerArea;
  }
}
