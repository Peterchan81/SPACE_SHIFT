import 'dart:math' as math;

import '../models/cad_floor_plan.dart';
import '../models/floor_plan_geometry.dart';
import '../vision_cad_poc/pixel_wall_v4/pixel_wall_types.dart';
import '../vision_cad_poc/pixel_wall_v4/planar_wall_graph.dart';

/// SS CAD TEST — Hybrid Geometry Recovery WO.
///
/// GPT는 "이 벽이 있다/외벽이다/이 방은 거실이다"라는 의미만 판단하고,
/// 실제 좌표의 최종 근거(topology truth source)가 되어서는 안 된다는
/// 요구를 그대로 반영한다. 이 파일은 GPT가 준 대략적인 벽 목록을 새로운
/// geometry 검출 엔진으로 다시 만들지 않고, [pixel_wall_v4]가 이미
/// 가지고 있던 planar half-edge graph 알고리즘([buildPlanarGraph],
/// [extractFaces], [pruneDanglingEdges] — 전부 endpoint snap/T-L-X
/// junction split/중복 edge 제거를 이미 구현하고 실제 이미지로 검증된
/// 코드다, `planar_wall_graph.dart` 참고)에 GPT의 벽 목록을 입력으로
/// 그대로 통과시켜 재사용한다.
///
/// 즉 "AI 의미 → 이 좌표들이 벽이다"까지는 GPT(선행 단계, 이 파일 밖)가
/// 맡고, "이 벽들이 실제로 서로 어떻게 이어지는가"(snap/junction/닫힌
/// 방 추출)는 전부 이 파일이 pixel_wall_v4 엔진에 위임한다 — 새 topology
/// 알고리즘을 처음부터 만들지 않는다.
class HybridTopologyResult {
  const HybridTopologyResult({
    required this.cadFloorPlan,
    required this.inputWallCount,
    required this.axisNormalizedCount,
    required this.excludedNonAxisCount,
    required this.outputWallCount,
    required this.graphVertexCount,
    required this.graphEdgeCount,
    required this.tJunctionCount,
    required this.connectedComponents,
    required this.danglingEdgeCount,
    required this.innerRoomCount,
    required this.floorDomainClosed,
    this.floorDomainFailureReason,
  });

  final CadFloorPlan cadFloorPlan;

  /// 입력으로 받은 GPT 벽 개수(보정 전).
  final int inputWallCount;

  /// 거의 수평/수직이라 축으로 정규화된 벽 개수(§5-4).
  final int axisNormalizedCount;

  /// 축에 정렬할 수 없어(대각선) topology 재구성에서 제외되고 그대로
  /// 원본 좌표로 남은 벽 개수 — 조용히 버리지 않고 [cadFloorPlan.warnings]
  /// 에도 남는다.
  final int excludedNonAxisCount;

  /// junction split 이후 실제 CAD 벽으로 나온 physical edge 개수.
  final int outputWallCount;

  final int graphVertexCount;
  final int graphEdgeCount;
  final int tJunctionCount;

  /// 구조 벽이 몇 개의 분리된 성분으로 나뉘어 있는지(1이면 전부 연결됨).
  final int connectedComponents;

  /// 어느 닫힌 face에도 속하지 못한(막다른 가지) edge 개수.
  final int danglingEdgeCount;

  /// 닫힌 내부 face(=방 후보) 개수.
  final int innerRoomCount;

  final bool floorDomainClosed;
  final String? floorDomainFailureReason;
}

double _pointDistance(Point2 a, Point2 b) {
  final dx = a.x - b.x;
  final dy = a.y - b.y;
  return math.sqrt(dx * dx + dy * dy);
}

bool _pointInPolygon(Point2 p, List<Point2> polygon) {
  var inside = false;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final a = polygon[i];
    final b = polygon[j];
    final intersects = ((a.y > p.y) != (b.y > p.y)) && (p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x);
    if (intersects) inside = !inside;
  }
  return inside;
}

/// GPT가 준 대략의 벽/문/방 목록(이미 [HintedGeometryExtractor] 등으로
/// 픽셀 근거에 스냅된 상태)을 받아, 실제 endpoint 연결/junction/중복을
/// pixel_wall_v4의 planar graph 엔진으로 재구성한다.
///
/// [gptWalls]는 축(수평/수직)에서 크게 벗어나지 않아야 한다 — 실제
/// 건축 도면은 거의 항상 축 정렬이고, 이 전제가 깨지면(대각선) 그 벽은
/// topology 재구성에서 제외되고 원본 좌표 그대로 reviewNeeded로 남는다
/// (임의로 지어내지 않는다, §5-4/§5-10).
HybridTopologyResult buildHybridCadFloorPlan({
  required int sourceWidthPx,
  required int sourceHeightPx,
  required List<CadWall> gptWalls,
  required List<CadOpening> gptOpenings,
  required List<CadRoom> gptRooms,
}) {
  final w = sourceWidthPx;
  final h = sourceHeightPx;

  // --- §5-4: 거의 수평/수직인 선을 tolerance 안에서 정규화, 벗어나면 제외.
  const axisToleranceRatio = 0.03; // 정규화 좌표 기준 3% — 소형 이미지에서도 몇 px 이내.
  final candidates = <PixelWallCandidate>[];
  final excludedWalls = <CadWall>[];
  for (final wall in gptWalls) {
    final dx = (wall.end.x - wall.start.x).abs();
    final dy = (wall.end.y - wall.start.y).abs();
    final total = math.sqrt(dx * dx + dy * dy);
    if (total <= 0) {
      excludedWalls.add(wall);
      continue;
    }
    final isVertical = dx <= total * axisToleranceRatio;
    final isHorizontal = dy <= total * axisToleranceRatio;
    if (!isVertical && !isHorizontal) {
      excludedWalls.add(wall);
      continue;
    }
    // 축으로 스냅: 두 끝점의 cross-axis 좌표를 평균으로 맞춘다.
    Point2 start, end;
    PixelWallOrientation orientation;
    if (isVertical && (!isHorizontal || dx <= dy)) {
      final xAvg = (wall.start.x + wall.end.x) / 2;
      start = Point2(xAvg, wall.start.y);
      end = Point2(xAvg, wall.end.y);
      orientation = PixelWallOrientation.vertical;
    } else {
      final yAvg = (wall.start.y + wall.end.y) / 2;
      start = Point2(wall.start.x, yAvg);
      end = Point2(wall.end.x, yAvg);
      orientation = PixelWallOrientation.horizontal;
    }
    final tier = wall.confidence >= 0.8
        ? PixelWallConfidenceTier.high
        : wall.confidence >= 0.5
            ? PixelWallConfidenceTier.medium
            : PixelWallConfidenceTier.low;
    candidates.add(
      PixelWallCandidate(
        id: wall.id,
        start: start,
        end: end,
        thicknessNormalized: wall.thicknessNormalized,
        orientation: orientation,
        isExterior: wall.wallType == CadWallType.exterior,
        baseConfidence: wall.confidence,
        junctionSupport: 0,
        confidenceTier: tier,
        category: PixelWallCategory.structural,
        sourceSegmentIds: [wall.id],
      ),
    );
  }

  final graph = buildPlanarGraph(candidates: candidates, w: w, h: h);
  final pruned = pruneDanglingEdges(graph);
  final prunedEdgeIds = pruned.edges.map((e) => e.id).toSet();
  final danglingEdgeCount = graph.edges.length - pruned.edges.length;
  final connectedComponents = countConnectedComponents(graph);
  final tJunctionCount = graph.vertices.where((v) => graph.adjacency[v.id]!.length == 3).length;

  final faces = extractFaces(pruned);
  final outerFaces = findOuterFaces(faces);
  final outerFaceSet = outerFaces.toSet();
  final innerFaces = faces.where((f) => !outerFaceSet.contains(f)).toList();

  final floorDomainClosed = outerFaces.isNotEmpty && connectedComponents <= 1;
  final floorDomainFailureReason = floorDomainClosed
      ? null
      : connectedComponents > 1
          ? '구조 벽이 서로 이어지지 않는 $connectedComponents개 성분으로 나뉘어 단일 outer loop를 만들 수 없음(dangling edge $danglingEdgeCount개)'
          : '닫힌 outer face를 찾지 못함(dangling edge $danglingEdgeCount개)';

  Point2 vertexPoint(int vId) {
    final v = graph.vertices[vId];
    return Point2(v.xPx / w, v.yPx / h);
  }

  // --- 재구성된 물리 벽(가상 door bridge 제외 — 실선으로 그리지 않는다).
  final correctedWalls = <CadWall>[
    for (final e in graph.edges)
      if (!e.isVirtualBridge)
        CadWall(
          id: 'edge-${e.id}',
          start: vertexPoint(e.v1),
          end: vertexPoint(e.v2),
          thicknessNormalized: e.thicknessPx / (w > h ? w : h),
          wallType: e.wasExteriorEvidence ? CadWallType.exterior : CadWallType.interior,
          confidence: e.confidence,
          reviewNeeded: !prunedEdgeIds.contains(e.id),
          reviewReasons: !prunedEdgeIds.contains(e.id) ? const ['닫힌 방 어디에도 속하지 않는 막다른 벽(dangling edge)'] : const [],
        ),
    for (final wall in excludedWalls)
      CadWall(
        id: wall.id,
        start: wall.start,
        end: wall.end,
        thicknessNormalized: wall.thicknessNormalized,
        wallType: wall.wallType,
        confidence: wall.confidence,
        reviewNeeded: true,
        reviewReasons: const ['축(수평/수직)에서 크게 벗어나 topology 재구성 대상에서 제외됨 — 원본 GPT 좌표 그대로'],
      ),
  ];

  // --- 닫힌 내부 face = 방 후보. GPT 원본 room 이름을 centroid-in-polygon
  // 매칭으로만 이름표 삼는다(§8 "GPT = room name, SS geometry = boundary").
  String? labelFor(List<Point2> polygon) {
    if (polygon.isEmpty) return null;
    final cx = polygon.map((p) => p.x).reduce((a, b) => a + b) / polygon.length;
    final cy = polygon.map((p) => p.y).reduce((a, b) => a + b) / polygon.length;
    final centroid = Point2(cx, cy);
    for (final room in gptRooms) {
      if (room.name != null && _pointInPolygon(centroid, room.polygon)) return room.name;
    }
    return null;
  }

  final rooms = <CadRoom>[];
  for (var i = 0; i < innerFaces.length; i++) {
    final face = innerFaces[i];
    final polygon = [for (final vId in face.vertexIds) vertexPoint(vId)];
    rooms.add(
      CadRoom(
        id: 'room-$i',
        polygon: polygon,
        areaNormalized: face.signedArea.abs() / (w * h),
        confidence: 0.7,
        name: labelFor(polygon),
      ),
    );
  }

  // --- opening을 새 wall edge 중 가장 가까운 것으로 재-anchor(§5-10과
  // 동일 원칙: 원래 GPT wallId는 더 이상 존재하지 않을 수 있으므로 위치
  // 근접도로만 다시 붙인다. 실선(가상 아님) edge만 후보로 삼는다).
  final physicalEdges = [for (final e in graph.edges) if (!e.isVirtualBridge) e];
  final reanchoredOpenings = <CadOpening>[];
  for (final opening in gptOpenings) {
    String? newWallId;
    if (physicalEdges.isNotEmpty) {
      var best = physicalEdges.first;
      var bestDist = double.infinity;
      for (final e in physicalEdges) {
        final mid = Point2((vertexPoint(e.v1).x + vertexPoint(e.v2).x) / 2, (vertexPoint(e.v1).y + vertexPoint(e.v2).y) / 2);
        final d = _pointDistance(mid, opening.center);
        if (d < bestDist) {
          bestDist = d;
          best = e;
        }
      }
      newWallId = 'edge-${best.id}';
    }
    reanchoredOpenings.add(
      CadOpening(
        id: opening.id,
        type: opening.type,
        center: opening.center,
        widthNormalized: opening.widthNormalized,
        confidence: opening.confidence,
        wallId: newWallId,
        reviewNeeded: newWallId == null || opening.reviewNeeded,
        reviewReasons: newWallId == null ? const ['재구성된 벽 topology에 anchor할 물리 벽이 없음'] : opening.reviewReasons,
      ),
    );
  }

  final warnings = <String>[
    if (!floorDomainClosed) floorDomainFailureReason!,
    if (excludedWalls.isNotEmpty)
      '${excludedWalls.length}개 벽이 축(수평/수직)에서 크게 벗어나 topology 재구성 대상에서 제외되고 원본 좌표로만 남음: ${excludedWalls.map((w) => w.id).join(", ")}',
  ];

  final cadFloorPlan = CadFloorPlan(
    sourceWidthPx: sourceWidthPx,
    sourceHeightPx: sourceHeightPx,
    walls: correctedWalls,
    openings: reanchoredOpenings,
    rooms: rooms,
    warnings: warnings,
  );

  return HybridTopologyResult(
    cadFloorPlan: cadFloorPlan,
    inputWallCount: gptWalls.length,
    axisNormalizedCount: candidates.length,
    excludedNonAxisCount: excludedWalls.length,
    outputWallCount: correctedWalls.length,
    graphVertexCount: graph.vertices.length,
    graphEdgeCount: graph.edges.length,
    tJunctionCount: tJunctionCount,
    connectedComponents: connectedComponents,
    danglingEdgeCount: danglingEdgeCount,
    innerRoomCount: innerFaces.length,
    floorDomainClosed: floorDomainClosed,
    floorDomainFailureReason: floorDomainFailureReason,
  );
}
