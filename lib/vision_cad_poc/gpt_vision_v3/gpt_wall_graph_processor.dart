import 'dart:math' as math;
import 'dart:typed_data';

import '../../models/floor_plan_geometry.dart';
import '../../models/ss_spatial_model.dart';
import '../../models/vision_understanding.dart' show NormalizedPoint, VisionConfidence;
import '../../services/hinted_geometry_extractor.dart';
import '../../services/topology_validator.dart';
import '../gpt_vision_v1/gpt_cad_schema.dart' as v1;
import '../gpt_vision_v1/gpt_wall_topology_solver.dart';
import 'gpt_graph_schema.dart';

/// SPACE SHIFT — Canonical Wall Graph First POC.
///
/// 순서: local pixel refinement(기존 [HintedGeometryExtractor] 재사용)
/// → 기하학적 wall 중복 제거(GPT가 shared id를 완벽히 재사용하지
/// 못했을 경우의 안전망) → axis alignment(직전 POC에서 빠졌던 단계 —
/// diagonal 왜곡의 근본 원인) → adjacency 개수로 exterior/interior
/// 재분류(GPT의 개별 kind 태그보다 신뢰도 높음) → space loop 유도
/// (기존 [GptWallTopologySolver] 재사용, 재구현하지 않음) → FloorDomain
/// 유도(같은 solver를 exterior wall만 모은 가상 space에 재사용) → 기존
/// [TopologyValidator] 재사용.
class ProcessedWall {
  ProcessedWall({
    required this.id,
    required this.start,
    required this.end,
    required this.confidence,
    required this.mergedFromIds,
  });

  final String id;
  Point2 start;
  Point2 end;
  double confidence;
  final Set<String> mergedFromIds;

  double? refinedDeltaPx;
  VisionConfidence? geometryConfidence;
  bool isExterior = false;
  final Set<String> adjacentSpaceIds = {};
  bool suspectDiagonal = false;
}

class GptWallGraphResult {
  const GptWallGraphResult({
    required this.model,
    required this.spaceLoopResults,
    required this.floorDomainClosed,
    required this.floorDomainFailureReason,
    required this.gptWallCount,
    required this.canonicalWalls,
    required this.duplicatesRemoved,
  });

  final SSSpatialModel model;
  final Map<String, SpaceLoopResult> spaceLoopResults;
  final bool floorDomainClosed;
  final String? floorDomainFailureReason;
  final int gptWallCount;
  final List<ProcessedWall> canonicalWalls;
  final int duplicatesRemoved;

  int get closedLoopCount => spaceLoopResults.values.where((r) => r.closed).length;
}

class GptWallGraphProcessor {
  const GptWallGraphProcessor({
    this.dedupTolerancePx = 14,
    this.axisAlignAngleDeg = 8,
    this.diagonalFlagAngleDeg = 20,
    this.solver = const GptWallTopologySolver(),
    this.validator = const TopologyValidator(),
  });

  final double dedupTolerancePx;
  final double axisAlignAngleDeg;
  final double diagonalFlagAngleDeg;
  final GptWallTopologySolver solver;
  final TopologyValidator validator;

  GptWallGraphResult process({
    required GptWallGraphResponse graph,
    required int imageWidthPx,
    required int imageHeightPx,
    required Uint8List imageBytes,
  }) {
    final cornersById = {for (final c in graph.corners) c.id: c};

    // 1) Local pixel refinement — 기존 HintedGeometryExtractor 재사용.
    final extractor = HintedGeometryExtractor(imageBytes);
    final refinedStartEnd = <String, (Point2, Point2, double?, VisionConfidence?)>{};
    for (final wall in graph.walls) {
      final c1 = cornersById[wall.startCornerId];
      final c2 = cornersById[wall.endCornerId];
      if (c1 == null || c2 == null) continue;
      final start = Point2(c1.x, c1.y);
      final end = Point2(c2.x, c2.y);
      final startNorm = NormalizedPoint(c1.x / imageWidthPx, c1.y / imageHeightPx);
      final endNorm = NormalizedPoint(c2.x / imageWidthPx, c2.y / imageHeightPx);
      final candidate = extractor.refineBoundary(startNorm, endNorm);
      if (candidate == null) {
        refinedStartEnd[wall.id] = (start, end, null, null);
        continue;
      }
      final pts = candidate.geometry.allPoints;
      final refinedStart = Point2(pts.first.x * imageWidthPx, pts.first.y * imageHeightPx);
      final refinedEnd = Point2(pts.last.x * imageWidthPx, pts.last.y * imageHeightPx);
      final dx = start.x - refinedStart.x, dy = start.y - refinedStart.y;
      refinedStartEnd[wall.id] = (refinedStart, refinedEnd, math.sqrt(dx * dx + dy * dy), candidate.confidence);
    }

    // 2) 기하학적 중복 제거(안전망) — refine된 좌표 기준으로 끝점이
    // 가까우면(순서 무관) 같은 물리적 벽으로 본다.
    final processed = <ProcessedWall>[];
    final gptIdToCanonical = <String, String>{};
    var canonicalCounter = 0;

    for (final wall in graph.walls) {
      final refined = refinedStartEnd[wall.id];
      if (refined == null) continue;
      final (start, end, delta, geomConf) = refined;

      ProcessedWall? match;
      for (final existing in processed) {
        final sameOrder = _dist(existing.start, start) <= dedupTolerancePx && _dist(existing.end, end) <= dedupTolerancePx;
        final reversed = _dist(existing.start, end) <= dedupTolerancePx && _dist(existing.end, start) <= dedupTolerancePx;
        if (sameOrder || reversed) {
          match = existing;
          break;
        }
      }

      if (match != null) {
        match.mergedFromIds.add(wall.id);
        match.confidence = math.max(match.confidence, wall.confidence);
        match.adjacentSpaceIds.addAll(wall.adjacentSpaceIds);
        gptIdToCanonical[wall.id] = match.id;
      } else {
        final canonical = ProcessedWall(
          id: 'CW${canonicalCounter++}',
          start: start,
          end: end,
          confidence: wall.confidence,
          mergedFromIds: {wall.id},
        )
          ..refinedDeltaPx = delta
          ..geometryConfidence = geomConf
          ..adjacentSpaceIds.addAll(wall.adjacentSpaceIds)
          ..isExterior = wall.type == GptWallType.exterior;
        processed.add(canonical);
        gptIdToCanonical[wall.id] = canonical.id;
      }
    }
    final duplicatesRemoved = graph.walls.length - processed.length;

    // 3) Axis alignment — 직전 POC에서 빠졌던 단계. 거의 수평/수직인
    // 벽만 강제로 곧게 편다 — 실제로 뚜렷하게 기울어진 벽은 건드리지
    // 않는다(설계 17번 — diagonal을 무조건 금지하지 않는다).
    for (final wall in processed) {
      final dx = wall.end.x - wall.start.x;
      final dy = wall.end.y - wall.start.y;
      final angle = math.atan2(dy.abs(), dx.abs()) * 180 / math.pi; // 0=수평, 90=수직
      if (angle <= axisAlignAngleDeg) {
        final avgY = (wall.start.y + wall.end.y) / 2;
        wall.start = Point2(wall.start.x, avgY);
        wall.end = Point2(wall.end.x, avgY);
      } else if (angle >= 90 - axisAlignAngleDeg) {
        final avgX = (wall.start.x + wall.end.x) / 2;
        wall.start = Point2(avgX, wall.start.y);
        wall.end = Point2(avgX, wall.end.y);
      } else if (angle > diagonalFlagAngleDeg && angle < 90 - diagonalFlagAngleDeg) {
        // 뚜렷한 대각선 — 실제 pixel evidence가 강할 때만 그대로 유지,
        // 아니면 review 표시(삭제는 하지 않는다).
        if (wall.geometryConfidence != VisionConfidence.high) {
          wall.suspectDiagonal = true;
        }
      }
    }

    // 4) Exterior/interior 재분류 — GPT의 개별 kind 태그보다 adjacency
    // 개수(실제로 몇 개 space가 이 벽을 참조하는가)가 더 신뢰도 높다
    // (설계 §0 root cause 분석 — FloorDomain 실패 원인).
    final adjacencyCount = <String, int>{};
    for (final space in graph.spaces) {
      for (final wallId in space.boundaryWallIds) {
        final canonicalId = gptIdToCanonical[wallId];
        if (canonicalId == null) continue;
        adjacencyCount[canonicalId] = (adjacencyCount[canonicalId] ?? 0) + 1;
      }
    }
    for (final wall in processed) {
      final count = adjacencyCount[wall.id] ?? 0;
      wall.isExterior = count <= 1;
    }

    // 5) Space loop 유도 — 기존 GptWallTopologySolver 재사용(재구현 안 함).
    // solver는 cornerIds로 연결성을 판단하므로, canonical wall의
    // 실제 좌표가 같은 corner를 공유하면 같은 corner id를 부여해야
    // 한다. 격자 반올림은 경계값(예: 3px 차이가 서로 다른 칸에 걸침)
    // 에서 깨지므로, 거리 기반 클러스터링으로 corner를 통합한다.
    final allEndpoints = <Point2>[for (final w in processed) ...[w.start, w.end]];
    final cornerClusters = <List<Point2>>[];
    for (final p in allEndpoints) {
      var placed = false;
      for (final cluster in cornerClusters) {
        if (_dist(cluster.first, p) <= dedupTolerancePx) {
          cluster.add(p);
          placed = true;
          break;
        }
      }
      if (!placed) cornerClusters.add([p]);
    }
    final cornerIdByPoint = <Point2, String>{};
    for (var i = 0; i < cornerClusters.length; i++) {
      for (final p in cornerClusters[i]) {
        cornerIdByPoint[p] = 'GC$i';
      }
    }
    String cornerIdFor(Point2 p) {
      final exact = cornerIdByPoint[p];
      if (exact != null) return exact;
      for (final entry in cornerIdByPoint.entries) {
        if (_dist(entry.key, p) <= 1e-6) return entry.value;
      }
      throw StateError('corner id lookup failed for point ($p) — should be unreachable');
    }

    final v1WallsWithSharedCorners = [
      for (final w in processed)
        v1.GptWall(id: w.id, type: v1.GptWallType.interior, cornerIds: [cornerIdFor(w.start), cornerIdFor(w.end)], confidence: w.confidence),
    ];

    final spaceLoopResults = <String, SpaceLoopResult>{};
    for (final space in graph.spaces) {
      final canonicalWallIds = [
        for (final wid in space.boundaryWallIds)
          if (gptIdToCanonical[wid] != null) gptIdToCanonical[wid]!,
      ];
      final v1Space = v1.GptSpace(
        id: space.id,
        label: space.label,
        semanticType: space.semanticType,
        boundaryWallIds: canonicalWallIds,
        confidence: space.confidence,
      );
      spaceLoopResults[space.id] = solver.deriveSpaceLoop(v1Space, v1WallsWithSharedCorners);
    }

    // 6) FloorDomain 유도 — exterior로 재분류된 wall만 모아 같은
    // solver로 폐곡선을 구한다(가상의 "exterior space" 취급).
    final exteriorWallIds = [for (final w in processed) if (w.isExterior) w.id];
    final syntheticExteriorSpace = v1.GptSpace(
      id: '__floorDomain__',
      label: 'FloorDomain',
      semanticType: 'floorDomain',
      boundaryWallIds: exteriorWallIds,
      confidence: 1.0,
    );
    final floorDomainLoop = solver.deriveSpaceLoop(syntheticExteriorSpace, v1WallsWithSharedCorners);
    final pointByCornerId = <String, Point2>{
      for (var i = 0; i < cornerClusters.length; i++)
        'GC$i': Point2(
          cornerClusters[i].map((p) => p.x).reduce((a, b) => a + b) / cornerClusters[i].length,
          cornerClusters[i].map((p) => p.y).reduce((a, b) => a + b) / cornerClusters[i].length,
        ),
    };
    final floorDomainPolygon = floorDomainLoop.closed
        ? [for (final cid in floorDomainLoop.orderedCornerIds) pointByCornerId[cid]!]
        : null;

    // 7) Canonical SSSpatialModel 구성 + 기존 TopologyValidator 재사용.
    final normalizedWalls = <SSWall>[
      for (final w in processed)
        SSWall(
          id: w.id,
          start: Point2(w.start.x / imageWidthPx, w.start.y / imageHeightPx),
          end: Point2(w.end.x / imageWidthPx, w.end.y / imageHeightPx),
          thicknessNormalized: 8 / imageWidthPx,
          kind: w.isExterior ? SSWallKind.exterior : SSWallKind.interior,
          confidence: w.geometryConfidence == null ? w.confidence : _confToDouble(w.geometryConfidence!),
          separatesSpaceIds: w.adjacentSpaceIds.toList(),
          source: SSEntitySource.vision,
          reviewNeeded: w.suspectDiagonal || w.geometryConfidence == null || w.geometryConfidence == VisionConfidence.low,
          reviewReasons: [
            if (w.suspectDiagonal) 'suspect diagonal without strong pixel evidence',
            if (w.geometryConfidence == null) 'no local pixel evidence found near this wall',
            if (w.geometryConfidence == VisionConfidence.low) 'local pixel evidence weak',
          ],
        ),
    ];

    final spaces = <SSSpace>[
      for (final space in graph.spaces)
        SSSpace(
          id: space.id,
          polygon: !spaceLoopResults[space.id]!.closed
              ? const []
              : [
                  for (final cid in spaceLoopResults[space.id]!.orderedCornerIds)
                    Point2(pointByCornerId[cid]!.x / imageWidthPx, pointByCornerId[cid]!.y / imageHeightPx),
                ],
          areaNormalized: !spaceLoopResults[space.id]!.closed
              ? 0
              : _polygonArea([
                  for (final cid in spaceLoopResults[space.id]!.orderedCornerIds) pointByCornerId[cid]!,
                ], imageWidthPx, imageHeightPx),
          closed: spaceLoopResults[space.id]!.closed,
          confidence: space.confidence,
          spaceConfidence: spaceLoopResults[space.id]!.closed ? SSSpaceConfidence.high : SSSpaceConfidence.low,
          label: space.label,
          source: SSEntitySource.vision,
          reviewNeeded: !spaceLoopResults[space.id]!.closed,
          reviewReasons: spaceLoopResults[space.id]!.closed ? const [] : [spaceLoopResults[space.id]!.failureReason!],
        ),
    ];

    final model = SSSpatialModel(
      sourceWidthPx: imageWidthPx,
      sourceHeightPx: imageHeightPx,
      spaces: spaces,
      walls: normalizedWalls,
      openings: const [],
      objects: const [],
      warnings: [
        ?floorDomainLoop.closed ? null : 'FloorDomain: ${floorDomainLoop.failureReason}',
      ],
      floorDomain: floorDomainPolygon == null
          ? null
          : [for (final p in floorDomainPolygon) Point2(p.x / imageWidthPx, p.y / imageHeightPx)],
    );

    final validated = validator.validate(model);

    return GptWallGraphResult(
      model: validated,
      spaceLoopResults: spaceLoopResults,
      floorDomainClosed: floorDomainLoop.closed,
      floorDomainFailureReason: floorDomainLoop.closed ? null : floorDomainLoop.failureReason,
      gptWallCount: graph.walls.length,
      canonicalWalls: processed,
      duplicatesRemoved: duplicatesRemoved,
    );
  }

  double _confToDouble(VisionConfidence c) => switch (c) {
        VisionConfidence.high => 1.0,
        VisionConfidence.medium => 0.7,
        VisionConfidence.low => 0.4,
        VisionConfidence.unknown => 0.0,
      };

  double _polygonArea(List<Point2> polygonPx, int w, int h) {
    final polygon = [for (final p in polygonPx) Point2(p.x / w, p.y / h)];
    if (polygon.length < 3) return 0;
    var sum = 0.0;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      sum += polygon[j].x * polygon[i].y - polygon[i].x * polygon[j].y;
    }
    return sum.abs() / 2;
  }

  double _dist(Point2 a, Point2 b) {
    final dx = a.x - b.x, dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }
}
