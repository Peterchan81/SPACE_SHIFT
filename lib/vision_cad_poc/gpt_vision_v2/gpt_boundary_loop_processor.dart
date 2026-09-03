import 'dart:math' as math;
import 'dart:typed_data';

import '../../models/floor_plan_geometry.dart';
import '../../models/ss_spatial_model.dart';
import '../../models/vision_understanding.dart' show NormalizedPoint, VisionConfidence;
import '../../services/hinted_geometry_extractor.dart';
import '../../services/topology_validator.dart';
import 'gpt_pass_b_schema.dart';

/// SPACE SHIFT — GPT Space Boundary Loop Recovery POC.
///
/// PASS B가 준, "각 공간이 자기 자신의 순서 있는 경계를 독립적으로
/// 기술한" 결과를 canonical CAD로 만든다:
///
/// 1. 공간별 self-chain — GPT가 준 segment 순서를 그대로 믿지 않고,
///    가까운 끝점끼리 이어 붙여 실제로 닫히는지 독립 재검증한다.
/// 2. Cross-space corner snap — 여러 공간이 각자 설명한 같은 물리적
///    지점을 하나의 canonical corner로 합친다.
/// 3. Canonical wall merge — snap 후 끝점이 같아진 segment들을 하나의
///    canonical wall로 합친다(중복 wall 제거).
/// 4. Local pixel refinement — 기존 [HintedGeometryExtractor] 재사용.
/// 5. FloorDomain 재구성 — exterior로 표시된 canonical wall만 모아
///    독립적으로 체인해 하나의 폐곡선을 만든다(GPT의 orderedCornerIds를
///    맹신하지 않는다).
/// 6. 기존 [TopologyValidator] 재사용해 최종 검증.
class SpaceLoopBuildResult {
  const SpaceLoopBuildResult({
    required this.spaceId,
    required this.closed,
    this.polygon = const [],
    this.canonicalWallIds = const [],
    this.failureReason,
  });

  final String spaceId;
  final bool closed;
  final List<Point2> polygon;
  final List<String> canonicalWallIds;
  final String? failureReason;
}

class CanonicalWall {
  CanonicalWall({
    required this.id,
    required this.start,
    required this.end,
    required this.isExterior,
    required this.confidence,
    required this.spaceIds,
  });

  final String id;
  Point2 start;
  Point2 end;
  bool isExterior;
  double confidence;
  final Set<String> spaceIds;

  double? refinedDeltaPx;
  VisionConfidence? geometryConfidence;
}

class GptBoundaryLoopResult {
  const GptBoundaryLoopResult({
    required this.model,
    required this.spaceLoops,
    required this.canonicalWalls,
    required this.floorDomainClosed,
    required this.floorDomainFailureReason,
  });

  final SSSpatialModel model;
  final List<SpaceLoopBuildResult> spaceLoops;
  final List<CanonicalWall> canonicalWalls;
  final bool floorDomainClosed;
  final String? floorDomainFailureReason;

  int get closedLoopCount => spaceLoops.where((s) => s.closed).length;
}

class _RawSeg {
  const _RawSeg(this.start, this.end, this.kind, this.confidence, this.spaceId);
  final Point2 start;
  final Point2 end;
  final GptSegmentKind kind;
  final double confidence;
  final String spaceId;
}

class GptBoundaryLoopProcessor {
  const GptBoundaryLoopProcessor({
    this.perSpaceChainTolerancePx = 18,
    this.crossSpaceSnapTolerancePx = 22,
    this.validator = const TopologyValidator(),
  });

  final double perSpaceChainTolerancePx;
  final double crossSpaceSnapTolerancePx;
  final TopologyValidator validator;

  GptBoundaryLoopResult process({
    required GptPassBResponse passB,
    required int imageWidthPx,
    required int imageHeightPx,
    required Uint8List imageBytes,
  }) {
    // 1) 공간별 self-chain.
    final spaceLoops = <SpaceLoopBuildResult>[];
    final chainedSegsBySpace = <String, List<_RawSeg>>{};

    for (final loop in passB.spaceBoundaryLoops) {
      final rawSegs = [
        for (final s in loop.segments)
          _RawSeg(
            Point2(s.start.x, s.start.y),
            Point2(s.end.x, s.end.y),
            s.kind,
            s.confidence,
            loop.spaceId,
          ),
      ];
      final chain = _chainSegments(rawSegs, perSpaceChainTolerancePx);
      if (chain == null) {
        spaceLoops.add(SpaceLoopBuildResult(
          spaceId: loop.spaceId,
          closed: false,
          failureReason:
              'PASS B segments for "${loop.spaceId}" do not form a closed loop within '
              '${perSpaceChainTolerancePx}px tolerance (${rawSegs.length} segment(s) given)',
        ));
        continue;
      }
      chainedSegsBySpace[loop.spaceId] = chain;
      spaceLoops.add(SpaceLoopBuildResult(spaceId: loop.spaceId, closed: true));
    }

    // 2) Cross-space corner snap — 모든 성공적으로 체인된 공간의 모든
    // endpoint를 모아 클러스터링.
    final allPoints = <Point2>[];
    for (final segs in chainedSegsBySpace.values) {
      for (final s in segs) {
        allPoints.add(s.start);
        allPoints.add(s.end);
      }
    }
    final snapMap = _buildSnapMap(allPoints, crossSpaceSnapTolerancePx);
    Point2 snap(Point2 p) => _lookupSnap(p, snapMap, crossSpaceSnapTolerancePx);

    // 3) Canonical wall merge — snap 후 끝점 쌍이 같아진 segment를 병합.
    final canonicalByKey = <String, CanonicalWall>{};
    var wallCounter = 0;
    String keyOf(Point2 a, Point2 b) {
      final k1 = '${a.x.toStringAsFixed(1)},${a.y.toStringAsFixed(1)}';
      final k2 = '${b.x.toStringAsFixed(1)},${b.y.toStringAsFixed(1)}';
      return k1.compareTo(k2) <= 0 ? '$k1|$k2' : '$k2|$k1';
    }

    final spacePolygons = <String, List<Point2>>{};
    final spaceWallIds = <String, List<String>>{};

    for (final entry in chainedSegsBySpace.entries) {
      final spaceId = entry.key;
      final segs = entry.value;
      final polygon = <Point2>[];
      final wallIds = <String>[];
      for (final seg in segs) {
        final a = snap(seg.start);
        final b = snap(seg.end);
        polygon.add(a);
        final key = keyOf(a, b);
        final existing = canonicalByKey[key];
        if (existing != null) {
          existing.spaceIds.add(spaceId);
          existing.isExterior = existing.isExterior || seg.kind == GptSegmentKind.exterior;
          existing.confidence = math.max(existing.confidence, seg.confidence);
          wallIds.add(existing.id);
        } else {
          final wall = CanonicalWall(
            id: 'CW${wallCounter++}',
            start: a,
            end: b,
            isExterior: seg.kind == GptSegmentKind.exterior,
            confidence: seg.confidence,
            spaceIds: {spaceId},
          );
          canonicalByKey[key] = wall;
          wallIds.add(wall.id);
        }
      }
      spacePolygons[spaceId] = polygon;
      spaceWallIds[spaceId] = wallIds;
    }

    final canonicalWalls = canonicalByKey.values.toList();

    // 4) Local pixel refinement (기존 HintedGeometryExtractor 재사용).
    final extractor = HintedGeometryExtractor(imageBytes);
    for (final wall in canonicalWalls) {
      final startNorm = NormalizedPoint(wall.start.x / imageWidthPx, wall.start.y / imageHeightPx);
      final endNorm = NormalizedPoint(wall.end.x / imageWidthPx, wall.end.y / imageHeightPx);
      final candidate = extractor.refineBoundary(startNorm, endNorm);
      if (candidate == null) continue;
      final pts = candidate.geometry.allPoints;
      final refinedStart = Point2(pts.first.x * imageWidthPx, pts.first.y * imageHeightPx);
      final refinedEnd = Point2(pts.last.x * imageWidthPx, pts.last.y * imageHeightPx);
      final dx = wall.start.x - refinedStart.x;
      final dy = wall.start.y - refinedStart.y;
      wall.refinedDeltaPx = math.sqrt(dx * dx + dy * dy);
      wall.geometryConfidence = candidate.confidence;
      wall.start = refinedStart;
      wall.end = refinedEnd;
    }
    // canonical wall id -> refined position lookup으로 space polygon도 갱신.
    final wallById = {for (final w in canonicalWalls) w.id: w};
    for (final spaceId in spacePolygons.keys.toList()) {
      final wallIds = spaceWallIds[spaceId]!;
      final refinedPolygon = <Point2>[];
      for (var i = 0; i < wallIds.length; i++) {
        final wall = wallById[wallIds[i]]!;
        // wall.start/end 순서가 이 공간의 진행 방향과 반대일 수 있으므로
        // 원래 polygon점(snap 후, refine 전)과 더 가까운 쪽을 채택한다.
        final original = spacePolygons[spaceId]![i];
        final dStart = _dist(original, wall.start);
        final dEnd = _dist(original, wall.end);
        refinedPolygon.add(dStart <= dEnd ? wall.start : wall.end);
      }
      spacePolygons[spaceId] = refinedPolygon;
    }

    // 최종 spaceLoops에 polygon/canonicalWallIds 반영.
    final finalSpaceLoops = [
      for (final s in spaceLoops)
        if (s.closed)
          SpaceLoopBuildResult(
            spaceId: s.spaceId,
            closed: true,
            polygon: spacePolygons[s.spaceId]!,
            canonicalWallIds: spaceWallIds[s.spaceId]!,
          )
        else
          s,
    ];

    // 5) FloorDomain 재구성 — exterior 표시된 canonical wall만 체인.
    final exteriorSegs = [
      for (final w in canonicalWalls)
        if (w.isExterior) _RawSeg(w.start, w.end, GptSegmentKind.exterior, w.confidence, ''),
    ];
    final floorChain = _chainSegments(exteriorSegs, crossSpaceSnapTolerancePx * 1.5);
    final floorDomain = floorChain?.map((s) => s.start).toList();
    final floorDomainFailureReason = floorChain == null
        ? 'exterior-tagged canonical walls (${exteriorSegs.length}) do not form a single closed loop'
        : null;

    // 6) SSSpatialModel 구성 + 기존 TopologyValidator 재사용. 좌표는
    // 정규화(0..1) 단위로 한 번만 변환한다(중간에 픽셀 단위로 다시
    // 만들지 않는다).
    final normalizedWalls = <SSWall>[
      for (final w in canonicalWalls)
        SSWall(
          id: w.id,
          start: Point2(w.start.x / imageWidthPx, w.start.y / imageHeightPx),
          end: Point2(w.end.x / imageWidthPx, w.end.y / imageHeightPx),
          thicknessNormalized: 8 / imageWidthPx,
          kind: w.isExterior ? SSWallKind.exterior : SSWallKind.interior,
          confidence: w.geometryConfidence == null ? w.confidence : _confToDouble(w.geometryConfidence!),
          separatesSpaceIds: w.spaceIds.toList(),
          source: SSEntitySource.vision,
          reviewNeeded: w.geometryConfidence == VisionConfidence.low || w.geometryConfidence == null,
          reviewReasons: w.geometryConfidence == null
              ? const ['no local pixel evidence found near this wall']
              : w.geometryConfidence == VisionConfidence.low
                  ? const ['local pixel evidence weak']
                  : const [],
        ),
    ];

    // 실패한(닫히지 않은) 공간은 bbox나 임의 도형으로 대체하지 않는다
    // — 빈 polygon으로 남겨 두고 reviewNeeded로만 표시한다(설계 10번
    // "bbox fallback 금지"를 문자 그대로 지킨다).
    final spaces = <SSSpace>[
      for (final s in finalSpaceLoops)
        SSSpace(
          id: s.spaceId,
          polygon: [for (final p in s.polygon) Point2(p.x / imageWidthPx, p.y / imageHeightPx)],
          areaNormalized: s.polygon.isEmpty ? 0 : _polygonArea(s.polygon, imageWidthPx, imageHeightPx),
          closed: s.closed,
          confidence: s.closed ? 1.0 : 0.0,
          spaceConfidence: s.closed ? SSSpaceConfidence.high : SSSpaceConfidence.low,
          source: SSEntitySource.vision,
          reviewNeeded: !s.closed,
          reviewReasons: s.failureReason == null ? const [] : [s.failureReason!],
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
        ?floorDomainFailureReason,
      ],
      floorDomain: floorDomain == null
          ? null
          : [for (final p in floorDomain) Point2(p.x / imageWidthPx, p.y / imageHeightPx)],
    );

    final validated = validator.validate(model);

    return GptBoundaryLoopResult(
      model: validated,
      spaceLoops: finalSpaceLoops,
      canonicalWalls: canonicalWalls,
      floorDomainClosed: floorChain != null,
      floorDomainFailureReason: floorDomainFailureReason,
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

  /// 주어진 segment들을 가까운 끝점끼리 그리디하게 이어 붙여 닫힌
  /// 루프를 만든다. GPT가 준 순서를 그대로 믿지 않고 실제 좌표
  /// 근접성만으로 재구성한다 — 순서가 뒤섞이거나 방향이 반대여도
  /// 복구 가능하다. 닫히지 않으면 null.
  List<_RawSeg>? _chainSegments(List<_RawSeg> segs, double tolerancePx) {
    if (segs.isEmpty) return null;
    final used = List<bool>.filled(segs.length, false);
    used[0] = true;
    final chain = <_RawSeg>[segs[0]];
    final startPoint = segs[0].start;
    var currentEnd = segs[0].end;

    while (chain.length < segs.length) {
      int? bestIdx;
      var bestReversed = false;
      var bestDist = double.infinity;
      for (var i = 0; i < segs.length; i++) {
        if (used[i]) continue;
        final dStart = _dist(currentEnd, segs[i].start);
        final dEnd = _dist(currentEnd, segs[i].end);
        if (dStart < bestDist) {
          bestDist = dStart;
          bestIdx = i;
          bestReversed = false;
        }
        if (dEnd < bestDist) {
          bestDist = dEnd;
          bestIdx = i;
          bestReversed = true;
        }
      }
      if (bestIdx == null || bestDist > tolerancePx) return null;
      used[bestIdx] = true;
      final seg = segs[bestIdx];
      final oriented = bestReversed ? _RawSeg(seg.end, seg.start, seg.kind, seg.confidence, seg.spaceId) : seg;
      chain.add(oriented);
      currentEnd = oriented.end;
    }

    if (_dist(currentEnd, startPoint) > tolerancePx) return null;
    return chain;
  }

  Map<Point2, Point2> _buildSnapMap(List<Point2> points, double tolerance) {
    final clusters = <List<Point2>>[];
    for (final point in points) {
      var placed = false;
      for (final cluster in clusters) {
        final rep = cluster.first;
        if (_dist(rep, point) <= tolerance) {
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
    for (final entry in map.entries) {
      if (_dist(entry.key, point) <= 1e-6) return entry.value;
    }
    return point;
  }
}
