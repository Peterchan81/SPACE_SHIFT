import 'dart:math' as math;

import '../models/floor_plan_geometry.dart';
import '../models/ss_spatial_model.dart';
import '../models/vision_understanding.dart';
import 'topology_validator.dart';

/// SPACE SHIFT — Image 2 AI → Real CAD End-to-End POC. "SS Geometry
/// Solver"(설계 2번).
///
/// Vision Proposal(의미 + 대략적인 geometry 초안)을 받아 건축 CAD에
/// 적합한 [SSSpatialModel](Canonical CAD Model)로 정리한다. Vision의
/// 의미(공간 종류/인접관계/문·창 연결)는 그대로 보존하고, 오직 geometry
/// 정밀도만 다음 순서로 정리한다:
///
/// 1. 가까운 vertex 병합(스냅) — 여러 변이 공유해야 할 점이 근사치라
///    조금씩 어긋나 있는 것을 하나로 합친다.
/// 2. 거의 같은 X/Y 정렬(축 정렬) — 스냅된 좌표를 바탕으로 벽을 수평/
///    수직으로 강제해 직각을 만든다.
/// 3. Collinear segment 병합 — 같은 축 위에서 이어지는 벽 조각을
///    하나로 합친다(중복 벽 제거도 이 과정에서 자연히 처리된다).
/// 4. Wall junction 연결 — 다른 벽의 끝점이 이 벽의 중간에 닿아 있으면
///    그 지점에서 벽을 분할해 실제 T-junction을 만든다.
///
/// 그 다음, 이미 만들어져 있는 [TopologyValidator](self-intersection/
/// FloorDomain 폐합/영역 이탈/문-벽 부착/창-통로 오인/공간 overlap 등
/// 11개 규칙)를 그대로 재사용해 검증한다 — 이 규칙들을 다시 구현하지
/// 않는다.
///
/// Solver는 Vision이 말한 의미를 임의로 바꾸지 않는다 — 불확실하면
/// (Vision confidence가 low/unknown이면) 해당 entity에 reviewNeeded를
/// 세워 정직하게 남긴다.
class SSGeometrySolverResult {
  const SSGeometrySolverResult({required this.model, required this.normalizationLog});

  final SSSpatialModel model;

  /// 이번 정리 과정에서 실제로 무엇을 했는지(스냅/정렬/병합/분할 횟수 등).
  final List<String> normalizationLog;
}

class SSGeometrySolver {
  const SSGeometrySolver({this.vertexSnapTolerance = 0.015, this.axisTolerance = 0.02, this.validator = const TopologyValidator()});

  /// 정규화 좌표 기준 vertex 병합 허용 오차.
  final double vertexSnapTolerance;

  /// 벽을 수평/수직으로 스냅할 각도 허용 오차(dx, dy 비율 기준).
  final double axisTolerance;

  final TopologyValidator validator;

  SSGeometrySolverResult solve(VisionUnderstanding proposal) {
    final log = <String>[];

    // --- 1) 모든 vertex를 모아 스냅 클러스터를 만든다. ---
    final allPoints = <Point2>[];
    final floorDomainRaw = proposal.floorDomain.geometryHint?.points
            .map((p) => Point2(p.x, p.y))
            .toList() ??
        const <Point2>[];
    allPoints.addAll(floorDomainRaw);
    for (final space in proposal.spaces) {
      final hint = space.geometryHint;
      if (hint != null) {
        allPoints.addAll(hint.allPoints.map((p) => Point2(p.x, p.y)));
      }
    }
    for (final boundary in proposal.boundaries) {
      final hint = boundary.geometryHint;
      if (hint != null) {
        allPoints.addAll(hint.allPoints.map((p) => Point2(p.x, p.y)));
      }
    }

    final snapMap = _buildSnapMap(allPoints, vertexSnapTolerance);
    log.add('vertex snap: ${allPoints.length}개 좌표를 ${snapMap.values.toSet().length}개 클러스터로 병합');

    Point2 snap(Point2 pIn) => _lookupSnap(pIn, snapMap, vertexSnapTolerance);

    // --- 2) FloorDomain, Space polygon 스냅 적용. ---
    final floorDomain = floorDomainRaw.map(snap).toList();

    final spaces = <SSSpace>[];
    for (final space in proposal.spaces) {
      final hint = space.geometryHint;
      final polygon = hint == null
          ? const <Point2>[]
          : hint.allPoints.map((p) => snap(Point2(p.x, p.y))).toList();
      final reviewNeeded = space.confidence == VisionConfidence.low || space.confidence == VisionConfidence.unknown;
      spaces.add(
        SSSpace(
          id: space.id,
          polygon: polygon,
          areaNormalized: _polygonArea(polygon),
          closed: true,
          confidence: _confidenceToDouble(space.confidence),
          spaceConfidence: _toSpaceConfidence(space.confidence),
          adjacentSpaceIds: space.adjacentSpaceIds,
          label: space.label,
          source: SSEntitySource.vision,
          reviewNeeded: reviewNeeded,
          reviewReasons: reviewNeeded ? ['vision confidence was ${space.confidence.name} for this space'] : const [],
        ),
      );
    }

    // --- 3) 벽: 스냅 → 축 정렬. ---
    var walls = <SSWall>[];
    final boundaryKind = <String, bool>{}; // id -> isExterior
    for (final boundary in proposal.boundaries) {
      final hint = boundary.geometryHint;
      if (hint == null || hint.kind != GeometryHintKind.segment) continue;
      var start = snap(Point2(hint.start.x, hint.start.y));
      var end = snap(Point2(hint.end.x, hint.end.y));
      final aligned = _axisAlign(start, end, axisTolerance);
      start = aligned.$1;
      end = aligned.$2;
      boundaryKind[boundary.id] = boundary.boundaryType == VisionBoundaryType.exteriorWall;

      final reviewNeeded = boundary.confidence == VisionConfidence.low || boundary.confidence == VisionConfidence.unknown;
      walls.add(
        SSWall(
          id: boundary.id,
          start: start,
          end: end,
          thicknessNormalized: 0.01,
          kind: boundary.boundaryType == VisionBoundaryType.exteriorWall ? SSWallKind.exterior : SSWallKind.interior,
          confidence: _confidenceToDouble(boundary.confidence),
          source: SSEntitySource.vision,
          reviewNeeded: reviewNeeded,
          reviewReasons: reviewNeeded ? ['vision confidence was ${boundary.confidence.name} for this wall'] : const [],
        ),
      );
    }
    final beforeCollinear = walls.length;

    // --- 4) Collinear 병합 + 중복 제거. ---
    walls = _mergeCollinearAndDedupe(walls, axisTolerance);
    log.add('collinear 병합/중복 제거: $beforeCollinear개 → ${walls.length}개 벽');

    // --- 5) Junction 분할: 다른 벽의 끝점이 이 벽 중간에 닿아 있으면 분할. ---
    final beforeSplit = walls.length;
    walls = _splitAtJunctions(walls, vertexSnapTolerance);
    log.add('junction 분할: ${walls.length - beforeSplit}개 벽이 T-junction에서 추가로 나뉨');

    // --- 6) Boundary 목록(문/창 부착 대상)도 최종 wall 좌표로 재구성. ---
    final boundaries = <SSBoundary>[];
    for (final wall in walls) {
      boundaries.add(
        SSBoundary(
          id: wall.id,
          spaceId: '',
          start: wall.start,
          end: wall.end,
          type: SSBoundaryType.wall,
          confidence: wall.confidence,
          isExterior: wall.kind == SSWallKind.exterior,
          wallId: wall.id,
          source: wall.source,
          reviewNeeded: wall.reviewNeeded,
          reviewReasons: wall.reviewReasons,
        ),
      );
    }

    // --- 7) Openings: 최종 wall 좌표 기준으로 위치를 유지, 부착 벽 확인. ---
    // 벽 junction 분할로 원래 boundary id가 여러 조각(-partN)으로 나뉠 수
    // 있으므로, opening은 id 매칭이 아니라 "가장 가까운 벽"으로 부착
    // 대상을 다시 찾는다(TopologyValidator의 규칙 7과 같은 원리).
    final openings = <SSOpening>[];
    for (final opening in proposal.openings) {
      final hint = opening.geometryHint;
      if (hint == null) continue;
      final center = snap(Point2(hint.point.x, hint.point.y));
      final nearestWall = _findNearestWall(walls, center);
      final attachedExists = nearestWall != null && nearestWall.$2 <= 0.03;
      final reviewNeeded = !attachedExists ||
          opening.confidence == VisionConfidence.low ||
          opening.confidence == VisionConfidence.unknown;
      openings.add(
        SSOpening(
          id: opening.id,
          kind: switch (opening.openingType) {
            VisionOpeningType.door => SSOpeningKind.door,
            VisionOpeningType.window => SSOpeningKind.window,
            VisionOpeningType.openPassage => SSOpeningKind.openPassage,
          },
          center: center,
          widthNormalized: 0.02,
          confidence: _confidenceToDouble(opening.confidence),
          wallId: attachedExists ? nearestWall.$1.id : null,
          connectsSpaceIds: opening.connectedSpaceIds,
          source: SSEntitySource.vision,
          reviewNeeded: reviewNeeded,
          reviewReasons: [
            if (!attachedExists) 'no solved wall found close enough to attach this opening to',
            if (opening.confidence == VisionConfidence.low || opening.confidence == VisionConfidence.unknown)
              'vision confidence was ${opening.confidence.name} for this opening',
          ],
        ),
      );
    }

    // --- 8) Objects: 벽/공간 경계로 오인되지 않도록 별도 목록 유지. ---
    final objects = <SSObjectCandidate>[];
    for (final object in proposal.objects) {
      final hint = object.geometryHint;
      if (hint == null || hint.boundingBox == null) continue;
      final box = hint.boundingBox!;
      final reviewNeeded = object.confidence == VisionConfidence.low || object.confidence == VisionConfidence.unknown;
      objects.add(
        SSObjectCandidate(
          id: object.id,
          polygon: [
            snap(Point2(box.minX, box.minY)),
            snap(Point2(box.maxX, box.minY)),
            snap(Point2(box.maxX, box.maxY)),
            snap(Point2(box.minX, box.maxY)),
          ],
          kind: switch (object.objectType) {
            VisionObjectType.bed => SSObjectKind.bed,
            VisionObjectType.sofa => SSObjectKind.sofa,
            VisionObjectType.cabinet => SSObjectKind.cabinet,
            VisionObjectType.sink => SSObjectKind.sink,
            VisionObjectType.toilet => SSObjectKind.toilet,
            VisionObjectType.bathtub => SSObjectKind.bathtub,
            VisionObjectType.equipment => SSObjectKind.equipment,
            VisionObjectType.unknown => SSObjectKind.unknown,
          },
          containingSpaceId: object.containingSpaceId,
          source: SSEntitySource.vision,
          reviewNeeded: reviewNeeded,
          reviewReasons: reviewNeeded ? ['vision confidence was ${object.confidence.name} for this object'] : const [],
        ),
      );
    }

    final draft = SSSpatialModel(
      sourceWidthPx: 1000,
      sourceHeightPx: 1000,
      spaces: spaces,
      walls: walls,
      openings: openings,
      objects: objects,
      warnings: [...proposal.notes],
      boundaries: boundaries,
      floorDomain: floorDomain,
    );

    // --- 9) 기존 TopologyValidator 재사용 — 여기서 다시 구현하지 않는다. ---
    final validated = validator.validate(draft);
    return SSGeometrySolverResult(model: validated, normalizationLog: log);
  }

  Map<Point2, Point2> _buildSnapMap(List<Point2> points, double tolerance) {
    final clusters = <List<Point2>>[];
    for (final point in points) {
      var placed = false;
      for (final cluster in clusters) {
        final rep = cluster.first;
        if ((rep.x - point.x).abs() <= tolerance && (rep.y - point.y).abs() <= tolerance) {
          cluster.add(point);
          placed = true;
          break;
        }
      }
      if (!placed) clusters.add([point]);
    }
    final map = <Point2, Point2>{};
    for (final cluster in clusters) {
      final cx = cluster.map((p) => p.x).reduce((a, b) => a + b) / cluster.length;
      final cy = cluster.map((p) => p.y).reduce((a, b) => a + b) / cluster.length;
      final centroid = Point2(cx, cy);
      for (final point in cluster) {
        map[point] = centroid;
      }
    }
    return map;
  }

  Point2 _lookupSnap(Point2 point, Map<Point2, Point2> map, double tolerance) {
    final exact = map[point];
    if (exact != null) return exact;
    // 부동소수점 정확 일치가 안 되는 경우를 위한 폴백(허용 오차 내 탐색).
    for (final entry in map.entries) {
      if ((entry.key.x - point.x).abs() <= 1e-9 && (entry.key.y - point.y).abs() <= 1e-9) {
        return entry.value;
      }
    }
    return point;
  }

  (Point2, Point2) _axisAlign(Point2 start, Point2 end, double tolerance) {
    final dx = (end.x - start.x).abs();
    final dy = (end.y - start.y).abs();
    if (dx == 0 && dy == 0) return (start, end);
    if (dy <= dx * tolerance) {
      final avgY = (start.y + end.y) / 2;
      return (Point2(start.x, avgY), Point2(end.x, avgY));
    }
    if (dx <= dy * tolerance) {
      final avgX = (start.x + end.x) / 2;
      return (Point2(avgX, start.y), Point2(avgX, end.y));
    }
    return (start, end);
  }

  List<SSWall> _mergeCollinearAndDedupe(List<SSWall> walls, double tolerance) {
    final horizontalGroups = <double, List<SSWall>>{};
    final verticalGroups = <double, List<SSWall>>{};
    final other = <SSWall>[];

    for (final wall in walls) {
      final isHorizontal = (wall.start.y - wall.end.y).abs() <= tolerance && wall.start.x != wall.end.x;
      final isVertical = (wall.start.x - wall.end.x).abs() <= tolerance && wall.start.y != wall.end.y;
      if (isHorizontal) {
        final key = _roundKey((wall.start.y + wall.end.y) / 2, tolerance);
        horizontalGroups.putIfAbsent(key, () => []).add(wall);
      } else if (isVertical) {
        final key = _roundKey((wall.start.x + wall.end.x) / 2, tolerance);
        verticalGroups.putIfAbsent(key, () => []).add(wall);
      } else {
        other.add(wall);
      }
    }

    final result = <SSWall>[...other];
    for (final group in horizontalGroups.values) {
      result.addAll(_mergeGroup(group, alongOf: (w) => (w.start.x, w.end.x), rebuildWall: (w, aMin, aMax) {
        final y = (w.start.y + w.end.y) / 2;
        return _copyWall(w, Point2(aMin, y), Point2(aMax, y));
      }));
    }
    for (final group in verticalGroups.values) {
      result.addAll(_mergeGroup(group, alongOf: (w) => (w.start.y, w.end.y), rebuildWall: (w, aMin, aMax) {
        final x = (w.start.x + w.end.x) / 2;
        return _copyWall(w, Point2(x, aMin), Point2(x, aMax));
      }));
    }
    return result;
  }

  List<SSWall> _mergeGroup(
    List<SSWall> group, {
    required (double, double) Function(SSWall) alongOf,
    required SSWall Function(SSWall representative, double alongMin, double alongMax) rebuildWall,
  }) {
    final withRange = group.map((w) {
      final (a, b) = alongOf(w);
      return (wall: w, min: math.min(a, b), max: math.max(a, b));
    }).toList()
      ..sort((a, b) => a.min.compareTo(b.min));

    final merged = <SSWall>[];
    var current = withRange.first;
    for (var i = 1; i < withRange.length; i++) {
      final next = withRange[i];
      if (next.min <= current.max + 0.005) {
        current = (wall: current.wall, min: current.min, max: math.max(current.max, next.max));
      } else {
        merged.add(rebuildWall(current.wall, current.min, current.max));
        current = next;
      }
    }
    merged.add(rebuildWall(current.wall, current.min, current.max));
    return merged;
  }

  SSWall _copyWall(SSWall w, Point2 start, Point2 end) => SSWall(
        id: w.id,
        start: start,
        end: end,
        thicknessNormalized: w.thicknessNormalized,
        kind: w.kind,
        confidence: w.confidence,
        separatesSpaceIds: w.separatesSpaceIds,
        source: w.source,
        reviewNeeded: w.reviewNeeded,
        reviewReasons: w.reviewReasons,
      );

  double _roundKey(double v, double tolerance) => (v / tolerance).round() * tolerance;

  (SSWall, double)? _findNearestWall(List<SSWall> walls, Point2 point) {
    SSWall? best;
    var bestDist = double.infinity;
    for (final wall in walls) {
      final dx = wall.end.x - wall.start.x;
      final dy = wall.end.y - wall.start.y;
      final lenSq = dx * dx + dy * dy;
      final t = lenSq == 0 ? 0.0 : (((point.x - wall.start.x) * dx + (point.y - wall.start.y) * dy) / lenSq).clamp(0.0, 1.0);
      final projX = wall.start.x + t * dx;
      final projY = wall.start.y + t * dy;
      final dist = math.sqrt((point.x - projX) * (point.x - projX) + (point.y - projY) * (point.y - projY));
      if (dist < bestDist) {
        bestDist = dist;
        best = wall;
      }
    }
    if (best == null) return null;
    return (best, bestDist);
  }

  List<SSWall> _splitAtJunctions(List<SSWall> walls, double tolerance) {
    final endpoints = <Point2>[];
    for (final w in walls) {
      endpoints.add(w.start);
      endpoints.add(w.end);
    }

    final result = <SSWall>[];
    for (final wall in walls) {
      final splitPoints = <double>[]; // along-parameter t in (0,1)
      final dx = wall.end.x - wall.start.x;
      final dy = wall.end.y - wall.start.y;
      final lenSq = dx * dx + dy * dy;
      if (lenSq == 0) {
        result.add(wall);
        continue;
      }
      for (final ep in endpoints) {
        if (ep == wall.start || ep == wall.end) continue;
        final t = ((ep.x - wall.start.x) * dx + (ep.y - wall.start.y) * dy) / lenSq;
        if (t <= 0.02 || t >= 0.98) continue;
        final projX = wall.start.x + t * dx;
        final projY = wall.start.y + t * dy;
        final distSq = (ep.x - projX) * (ep.x - projX) + (ep.y - projY) * (ep.y - projY);
        if (distSq <= tolerance * tolerance) {
          splitPoints.add(t);
        }
      }
      if (splitPoints.isEmpty) {
        result.add(wall);
        continue;
      }
      splitPoints.sort();
      var prevT = 0.0;
      var segIndex = 0;
      for (final t in splitPoints) {
        result.add(_copyWallWithId(
          wall,
          '${wall.id}-part${segIndex++}',
          Point2(wall.start.x + prevT * dx, wall.start.y + prevT * dy),
          Point2(wall.start.x + t * dx, wall.start.y + t * dy),
        ));
        prevT = t;
      }
      result.add(_copyWallWithId(
        wall,
        '${wall.id}-part${segIndex++}',
        Point2(wall.start.x + prevT * dx, wall.start.y + prevT * dy),
        wall.end,
      ));
    }
    return result;
  }

  SSWall _copyWallWithId(SSWall w, String id, Point2 start, Point2 end) => SSWall(
        id: id,
        start: start,
        end: end,
        thicknessNormalized: w.thicknessNormalized,
        kind: w.kind,
        confidence: w.confidence,
        separatesSpaceIds: w.separatesSpaceIds,
        source: w.source,
        reviewNeeded: w.reviewNeeded,
        reviewReasons: w.reviewReasons,
      );

  SSSpaceConfidence _toSpaceConfidence(VisionConfidence c) => switch (c) {
        VisionConfidence.high => SSSpaceConfidence.high,
        VisionConfidence.medium => SSSpaceConfidence.medium,
        VisionConfidence.low => SSSpaceConfidence.low,
        VisionConfidence.unknown => SSSpaceConfidence.unknown,
      };

  double _confidenceToDouble(VisionConfidence c) => switch (c) {
        VisionConfidence.high => 1.0,
        VisionConfidence.medium => 0.7,
        VisionConfidence.low => 0.4,
        VisionConfidence.unknown => 0.0,
      };

  double _polygonArea(List<Point2> polygon) {
    if (polygon.length < 3) return 0;
    var sum = 0.0;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      sum += polygon[j].x * polygon[i].y - polygon[i].x * polygon[j].y;
    }
    return sum.abs() / 2;
  }
}
