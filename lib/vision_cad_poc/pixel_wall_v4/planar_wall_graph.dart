// SPACE SHIFT — PC1 FINALIZE: PLANAR HALF-EDGE GRAPH.
//
// 근본 원칙 전환: 이전까지는 각 wall candidate에 "isExterior" 태그를
// 개별적으로 매기고, 그 태그가 맞은 candidate들만 골라 체인으로 이어
// FloorDomain을 만들었다 — 이 방식은 endpoint-to-endpoint만 인식해서
// T-junction(한 벽의 끝점이 다른 벽의 "중간"에 닿는 흔한 구조)을 매번
// 놓쳤고, 그렇다고 "확정 exterior 두 점을 잇는 벽은 승격"이라는 위상
// 규칙을 시도하면 평범한 내부 파티션까지 승격시키는 회귀가 발생했다
// (§3 — 이 규칙은 폐기됨).
//
// 이번에는 개별 벽에 "외벽이다/아니다"를 미리 매기지 않는다. 대신
// 구조 벽 전체(내벽 포함)로 실제 planar graph를 만들고, 그 그래프가
// 스스로 만들어내는 face(닫힌 면) 중 "바깥쪽(경계 없는) face"를
// 위상학적으로 찾아낸다 — 그 face의 경계가 곧 건물의 진짜 외곽이다.
// 이 방법은 "이 벽이 외벽처럼 보이는가"를 전혀 묻지 않고, 순수하게
// "이 벽들이 실제로 어떻게 이어져 있는가"만으로 답을 낸다 — 그래서
// 위 회귀(내부 파티션 오승격)가 구조적으로 발생할 수 없다: 내부
// 파티션은 두 개의 "안쪽" face를 나누는 경계일 뿐, 바깥쪽 face의
// 경계에 놓일 수 없다.

import 'dart:math' as math;

import 'pixel_wall_types.dart';
import 'wall_system.dart';

class PlanarVertex {
  PlanarVertex({required this.id, required this.xPx, required this.yPx});
  final int id;
  final double xPx;
  final double yPx;
}

/// 원본 [PixelWallCandidate] 하나가 junction에서 여러 조각으로 split된
/// 경우에도 provenance(어느 원본 벽에서 왔는지)와 evidence(두께/
/// confidence/원래 face-contact 판정)를 그대로 유지한다.
class PlanarEdge {
  PlanarEdge({
    required this.id,
    required this.v1,
    required this.v2,
    required this.thicknessPx,
    required this.confidence,
    required this.sourceCandidateId,
    required this.wasExteriorEvidence,
    this.isVirtualBridge = false,
    this.virtualBridgeReason,
  });
  final int id;
  final int v1;
  final int v2;
  final double thicknessPx;
  final double confidence;
  final String sourceCandidateId;

  /// face-contact 방식이 이 원본 벽에 대해 매겼던 판정(참고 evidence로만
  /// 쓴다 — outer face 판정 자체는 이 값에 의존하지 않는다).
  final bool wasExteriorEvidence;

  /// 실제 픽셀로 이어진 edge가 아니라, 같은 축 위 두 조각 사이의 문/
  /// 작은 끊김(door/imageBreak) gap을 논리적으로 이은 가상 edge인지 —
  /// canonical CAD에는 실선으로 그리지 않아야 한다(§9 TEMP EXTERIOR
  /// MASK vs CANONICAL GEOMETRY 구분과 동일한 원칙).
  final bool isVirtualBridge;

  /// [isVirtualBridge]인 경우에만 채워지는 원래 gap 분류(door/imageBreak)
  /// — production FloorDomain 소비 경로가 이 provenance를 다시 계산하지
  /// 않고 그대로 재사용할 수 있도록 보존한다.
  final GapKind? virtualBridgeReason;

  PlanarEdge withVirtual(bool value) => PlanarEdge(
    id: id,
    v1: v1,
    v2: v2,
    thicknessPx: thicknessPx,
    confidence: confidence,
    sourceCandidateId: sourceCandidateId,
    wasExteriorEvidence: wasExteriorEvidence,
    isVirtualBridge: value,
    virtualBridgeReason: virtualBridgeReason,
  );
}

class PlanarGraph {
  PlanarGraph({required this.vertices, required this.edges, required this.adjacency});
  final List<PlanarVertex> vertices;
  final List<PlanarEdge> edges;

  /// vertexId -> 그 vertex에 닿아 있는 edge id 목록.
  final Map<int, List<int>> adjacency;
}

class PlanarFace {
  PlanarFace({required this.vertexIds, required this.edgeIds, required this.signedArea});
  final List<int> vertexIds;
  final List<int> edgeIds;
  final double signedArea;
}

const double _defaultJunctionTolerancePx = 10.0;

/// 두 endpoint가 같은 canonical vertex로 묶일 허용 오차 — 실측 벽
/// 두께(6~18px)에 맞춘 값. 좌표 하드코딩이 아니라 이미지 전체에
/// 동일하게 적용되는 값이다.
PlanarGraph buildPlanarGraph({
  required List<PixelWallCandidate> candidates,
  required int w,
  required int h,
  double tolerancePx = _defaultJunctionTolerancePx,
}) {
  final structural = candidates.where((c) => c.category == PixelWallCategory.structural).toList();

  // --- 1) 각 segment마다 "잘릴 지점"(자기 자신의 두 끝점 + 다른 segment의
  // 끝점이 이 segment의 body에 닿는 지점)을 모은다.
  final cutPositions = <int, List<double>>{}; // index into structural -> along-positions(px)로 저장.

  double alongMin(PixelWallCandidate c) =>
      c.orientation == PixelWallOrientation.horizontal ? math.min(c.start.x, c.end.x) * w : math.min(c.start.y, c.end.y) * h;
  double alongMax(PixelWallCandidate c) =>
      c.orientation == PixelWallOrientation.horizontal ? math.max(c.start.x, c.end.x) * w : math.max(c.start.y, c.end.y) * h;
  double crossOf(PixelWallCandidate c) => c.orientation == PixelWallOrientation.horizontal ? c.start.y * h : c.start.x * w;
  double thicknessPxOf(PixelWallCandidate c) => c.thicknessNormalized * (c.orientation == PixelWallOrientation.horizontal ? h : w);

  for (var i = 0; i < structural.length; i++) {
    cutPositions[i] = [alongMin(structural[i]), alongMax(structural[i])];
  }

  // 두 벽 사이 허용 오차는 고정값이 아니라 실제 벽 두께에서 유도한다
  // (§10 원칙과 동일 — floor_domain_builder.dart의 cornerToleranceFor와
  // 같은 근거: 두께가 클수록 centerline 끝점이 실제 접합부에서 더 크게
  // 벗어날 수 있다). 최소 8px, 1.5배, 상한 24px.
  double dynamicTolerance(PixelWallCandidate a, PixelWallCandidate b) =>
      (math.max(thicknessPxOf(a), thicknessPxOf(b)) * 1.5).clamp(8.0, math.max(24.0, tolerancePx));

  // endpoint-to-body: i의 끝점이 j의 body에 닿는지 검사(T-junction).
  for (var i = 0; i < structural.length; i++) {
    final segI = structural[i];
    final iPointsPx = [
      (segI.start.x * w, segI.start.y * h),
      (segI.end.x * w, segI.end.y * h),
    ];
    for (var j = 0; j < structural.length; j++) {
      if (i == j) continue;
      final segJ = structural[j];
      if (segJ.orientation == segI.orientation) continue; // 수직 벽끼리는 endpoint-to-body가 없다(둘 다 axis-aligned 직교 관계에서만 T-junction 발생).
      final tol = dynamicTolerance(segI, segJ);
      final crossJ = crossOf(segJ);
      final jMin = alongMin(segJ);
      final jMax = alongMax(segJ);
      for (final p in iPointsPx) {
        // segJ가 horizontal이면 p.y가 crossJ 근처, p.x가 [jMin,jMax] 근처인지 확인.
        final double alongVal;
        final double crossVal;
        if (segJ.orientation == PixelWallOrientation.horizontal) {
          alongVal = p.$1;
          crossVal = p.$2;
        } else {
          alongVal = p.$2;
          crossVal = p.$1;
        }
        if ((crossVal - crossJ).abs() > tol) continue;
        if (alongVal < jMin - tol || alongVal > jMax + tol) continue;
        final clamped = alongVal.clamp(jMin, jMax);
        cutPositions[j]!.add(clamped);
      }
    }
  }

  // body-to-body(X-junction): 두 직교 segment가 서로의 끝점이 아니라
  // 중간에서 실제로 교차하는 경우(둘 다 끝점이 아님) — 교차점을 양쪽
  // 모두의 cut position으로 추가한다.
  for (var i = 0; i < structural.length; i++) {
    final segI = structural[i];
    if (segI.orientation != PixelWallOrientation.horizontal) continue;
    final iCross = crossOf(segI); // y.
    final iMin = alongMin(segI);
    final iMax = alongMax(segI);
    for (var j = 0; j < structural.length; j++) {
      final segJ = structural[j];
      if (segJ.orientation != PixelWallOrientation.vertical) continue;
      final jCross = crossOf(segJ); // x.
      final jMin = alongMin(segJ);
      final jMax = alongMax(segJ);
      // 교차점 후보: (x=jCross, y=iCross). i의 along범위(x)에 jCross가
      // 있고, j의 along범위(y)에 iCross가 있어야 진짜 교차.
      if (jCross < iMin - tolerancePx || jCross > iMax + tolerancePx) continue;
      if (iCross < jMin - tolerancePx || iCross > jMax + tolerancePx) continue;
      cutPositions[i]!.add(jCross.clamp(iMin, iMax));
      cutPositions[j]!.add(iCross.clamp(jMin, jMax));
    }
  }

  // --- 2) 각 segment를 cut position 기준으로 sub-edge로 쪼갠다.
  final rawVertices = <(double x, double y)>[]; // 아직 canonicalize 전.
  final rawEdges = <(int v1Idx, int v2Idx, double thickness, double confidence, String sourceId, bool wasExt)>[];

  int addRawVertex(double x, double y) {
    rawVertices.add((x, y));
    return rawVertices.length - 1;
  }

  for (var i = 0; i < structural.length; i++) {
    final seg = structural[i];
    final positions = cutPositions[i]!.toSet().toList()..sort();
    if (positions.length < 2) continue;
    final cross = crossOf(seg);
    final thickness = thicknessPxOf(seg);
    for (var k = 0; k < positions.length - 1; k++) {
      final a = positions[k];
      final b = positions[k + 1];
      if (b - a < 1.0) continue; // 무의미하게 짧은(중복) 조각 skip.
      final (ax, ay) = seg.orientation == PixelWallOrientation.horizontal ? (a, cross) : (cross, a);
      final (bx, by) = seg.orientation == PixelWallOrientation.horizontal ? (b, cross) : (cross, b);
      final v1 = addRawVertex(ax, ay);
      final v2 = addRawVertex(bx, by);
      rawEdges.add((v1, v2, thickness, seg.baseConfidence, seg.id, seg.isExterior));
    }
  }

  // --- 3) canonical vertex로 묶는다(가까운 점은 하나의 vertex).
  final canonicalId = List<int>.filled(rawVertices.length, -1);
  final canonicalPoints = <(double x, double y)>[];
  for (var i = 0; i < rawVertices.length; i++) {
    if (canonicalId[i] != -1) continue;
    final (x, y) = rawVertices[i];
    var sumX = x, sumY = y, count = 1;
    canonicalId[i] = canonicalPoints.length;
    for (var j = i + 1; j < rawVertices.length; j++) {
      if (canonicalId[j] != -1) continue;
      final (ox, oy) = rawVertices[j];
      if (math.sqrt((ox - x) * (ox - x) + (oy - y) * (oy - y)) <= tolerancePx) {
        canonicalId[j] = canonicalPoints.length;
        sumX += ox;
        sumY += oy;
        count++;
      }
    }
    canonicalPoints.add((sumX / count, sumY / count));
  }

  final vertices = [
    for (var i = 0; i < canonicalPoints.length; i++) PlanarVertex(id: i, xPx: canonicalPoints[i].$1, yPx: canonicalPoints[i].$2),
  ];

  final edges = <PlanarEdge>[];
  final adjacency = <int, List<int>>{for (final v in vertices) v.id: []};
  var edgeId = 0;
  final seenPairs = <String>{};
  for (final (v1Idx, v2Idx, thickness, confidence, sourceId, wasExt) in rawEdges) {
    final cv1 = canonicalId[v1Idx];
    final cv2 = canonicalId[v2Idx];
    if (cv1 == cv2) continue; // 같은 vertex로 뭉개진 zero-length edge 제거.
    final key = cv1 < cv2 ? '$cv1-$cv2' : '$cv2-$cv1';
    if (!seenPairs.add(key)) continue; // 중복 edge 제거.
    edges.add(PlanarEdge(id: edgeId, v1: cv1, v2: cv2, thicknessPx: thickness, confidence: confidence, sourceCandidateId: sourceId, wasExteriorEvidence: wasExt));
    adjacency[cv1]!.add(edgeId);
    adjacency[cv2]!.add(edgeId);
    edgeId++;
  }

  // --- 4) 문/작은 끊김(door/imageBreak) 가상 연결 — 같은 축 위 두
  // 조각이 실제 픽셀로는 안 닿아 있지만(문이 있으니 당연히 벽이
  // 끊겨 있다) 그 사이가 진짜 출입구 크기 gap이면 논리적으로 이어야
  // FloorDomain이 문 때문에 매번 끊기지 않는다(§6 기존 원칙 재사용,
  // wall_system.dart의 gap 분류를 그대로 쓴다). 문 범위를 넘는 gap은
  // 여기서도 절대 잇지 않는다.
  final wallSystems = buildWallSystems(candidates: structural, w: w, h: h);
  int nearestCanonicalVertex(double px, double py) {
    var bestIdx = -1;
    var bestDist = double.infinity;
    for (var i = 0; i < vertices.length; i++) {
      final d = math.sqrt((vertices[i].xPx - px) * (vertices[i].xPx - px) + (vertices[i].yPx - py) * (vertices[i].yPx - py));
      if (d < bestDist) {
        bestDist = d;
        bestIdx = i;
      }
    }
    return bestIdx;
  }

  for (final system in wallSystems) {
    for (var i = 0; i < system.gaps.length; i++) {
      final gap = system.gaps[i];
      if (gap.kind != GapKind.doorOpening && gap.kind != GapKind.imageBreak) continue;
      final a = system.segments[i];
      final b = system.segments[i + 1];
      final (aFaceX, aFaceY) = a.orientation == PixelWallOrientation.horizontal
          ? (math.max(a.start.x, a.end.x) * w, system.axisPx)
          : (system.axisPx, math.max(a.start.y, a.end.y) * h);
      final (bFaceX, bFaceY) = b.orientation == PixelWallOrientation.horizontal
          ? (math.min(b.start.x, b.end.x) * w, system.axisPx)
          : (system.axisPx, math.min(b.start.y, b.end.y) * h);
      final v1 = nearestCanonicalVertex(aFaceX, aFaceY);
      final v2 = nearestCanonicalVertex(bFaceX, bFaceY);
      if (v1 == -1 || v2 == -1 || v1 == v2) continue;
      final key = v1 < v2 ? '$v1-$v2' : '$v2-$v1';
      if (!seenPairs.add(key)) continue;
      edges.add(
        PlanarEdge(
          id: edgeId,
          v1: v1,
          v2: v2,
          thicknessPx: math.max(thicknessPxOf(a), thicknessPxOf(b)),
          confidence: math.min(a.baseConfidence, b.baseConfidence),
          sourceCandidateId: '${a.id}~door~${b.id}',
          wasExteriorEvidence: a.isExterior || b.isExterior,
          isVirtualBridge: true,
          virtualBridgeReason: gap.kind,
        ),
      );
      adjacency[v1]!.add(edgeId);
      adjacency[v2]!.add(edgeId);
      edgeId++;
    }
  }

  return PlanarGraph(vertices: vertices, edges: edges, adjacency: adjacency);
}

/// degree-1(막다른 가지) vertex를 반복 제거한 사본을 만든다 — "죽은
/// 가지"는 정의상 어떤 닫힌 face에도 속할 수 없어(한쪽만 열린 벽은
/// 항상 그 면의 "바깥"과 "안"이 같은 face다), face 추적 알고리즘이
/// 이 가지로 잘못 들어가 진짜 바깥 loop를 못 찾게 방해할 수 있다.
/// vertex/edge 자체를 지우지 않고 "이 loop 추적에서만 무시할 edge
/// 목록"을 만드는 방식이라 원본 [PlanarGraph](evidence 전체 보존)는
/// 그대로 둔다 — 순수하게 face 추적용 사본이다.
PlanarGraph pruneDanglingEdges(PlanarGraph graph) {
  final degree = <int, int>{for (final v in graph.vertices) v.id: graph.adjacency[v.id]!.length};
  final removedEdge = List<bool>.filled(graph.edges.length, false);

  var changed = true;
  while (changed) {
    changed = false;
    for (final v in graph.vertices) {
      if (degree[v.id] != 1) continue;
      final remainingEdgeId = graph.adjacency[v.id]!.firstWhere((eId) => !removedEdge[eId], orElse: () => -1);
      if (remainingEdgeId == -1) continue;
      removedEdge[remainingEdgeId] = true;
      final e = graph.edges[remainingEdgeId];
      final other = e.v1 == v.id ? e.v2 : e.v1;
      degree[v.id] = 0;
      degree[other] = (degree[other] ?? 0) - 1;
      changed = true;
    }
  }

  final keptEdges = <PlanarEdge>[];
  final adjacency = <int, List<int>>{for (final v in graph.vertices) v.id: []};
  for (var i = 0; i < graph.edges.length; i++) {
    if (removedEdge[i]) continue;
    final e = graph.edges[i];
    keptEdges.add(e);
    adjacency[e.v1]!.add(e.id);
    adjacency[e.v2]!.add(e.id);
  }
  return PlanarGraph(vertices: graph.vertices, edges: keptEdges, adjacency: adjacency);
}

/// 각 vertex에서 나가는 방향(라디안, 이미지 좌표계 — y가 아래로 증가)
/// 기준으로 half-edge를 정렬해 face를 추출한다(DCEL 표준 기법). 모든
/// edge는 axis-aligned라 각도가 항상 0/90/180/270도 중 하나다.
List<PlanarFace> extractFaces(PlanarGraph graph) {
  // (fromVertex, edgeId) 형태의 directed half-edge.
  final halfEdges = <(int from, int to, int edgeId)>[];
  for (final e in graph.edges) {
    halfEdges.add((e.v1, e.v2, e.id));
    halfEdges.add((e.v2, e.v1, e.id));
  }

  double angleOf(int from, int to) {
    final a = graph.vertices[from];
    final b = graph.vertices[to];
    return math.atan2(b.yPx - a.yPx, b.xPx - a.xPx);
  }

  // vertex별로 나가는 half-edge를 각도 오름차순 정렬.
  final outgoingSorted = <int, List<(int to, int edgeId)>>{};
  for (final v in graph.vertices) {
    final outs = halfEdges.where((he) => he.$1 == v.id).map((he) => (he.$2, he.$3)).toList();
    outs.sort((a, b) => angleOf(v.id, a.$1).compareTo(angleOf(v.id, b.$1)));
    outgoingSorted[v.id] = outs;
  }

  int indexOfHalfEdge(int from, int to, int edgeId) {
    final list = outgoingSorted[from]!;
    for (var i = 0; i < list.length; i++) {
      if (list[i].$2 == edgeId && list[i].$1 == to) return i;
    }
    return -1;
  }

  final visited = <String>{};
  final faces = <PlanarFace>[];

  for (final start in halfEdges) {
    final startKey = '${start.$1}->${start.$2}:${start.$3}';
    if (visited.contains(startKey)) continue;

    final faceVertexIds = <int>[];
    final faceEdgeIds = <int>[];
    var current = start;
    var guard = 0;
    final maxSteps = halfEdges.length + 4;
    while (guard++ < maxSteps) {
      final key = '${current.$1}->${current.$2}:${current.$3}';
      if (!visited.add(key)) break;
      faceVertexIds.add(current.$1);
      faceEdgeIds.add(current.$3);

      // 반대 half-edge(current.to -> current.from)에서, 그 vertex(current.to)의
      // 정렬된 목록상 "다음" half-edge로 넘어간다 — 표준 face-tracing 규칙.
      final twinIdx = indexOfHalfEdge(current.$2, current.$1, current.$3);
      final list = outgoingSorted[current.$2]!;
      if (list.isEmpty || twinIdx == -1) break;
      final nextIdx = (twinIdx + 1) % list.length;
      final next = list[nextIdx];
      current = (current.$2, next.$1, next.$2);

      if (current.$1 == start.$1 && current.$2 == start.$2 && current.$3 == start.$3) break;
    }

    if (faceVertexIds.length < 3) continue;
    // dangling edge(한쪽 끝이 다른 곳에 안 이어진 가지)는 face 추적이
    // 그 edge를 "갔다가 되돌아오는" 형태로 두 번 지나간다 — 진짜 닫힌
    // face는 자기 edge를 두 번 쓰지 않으므로, 같은 edge id가 반복되면
    // 가짜(열린 경계) face로 보고 제외한다(§9 — 열린 경계를 억지로
    // 닫힌 것처럼 만들지 않는다).
    if (faceEdgeIds.toSet().length != faceEdgeIds.length) continue;
    faces.add(PlanarFace(vertexIds: faceVertexIds, edgeIds: faceEdgeIds, signedArea: _shoelaceSigned(faceVertexIds, graph)));
  }

  return faces;
}

double _shoelaceSigned(List<int> vertexIds, PlanarGraph graph) {
  var sum = 0.0;
  for (var i = 0; i < vertexIds.length; i++) {
    final a = graph.vertices[vertexIds[i]];
    final b = graph.vertices[vertexIds[(i + 1) % vertexIds.length]];
    sum += a.xPx * b.yPx - b.xPx * a.yPx;
  }
  return sum / 2;
}

/// 그래프의 연결 성분(connected component) 개수 — edge가 하나도 없는
/// 고립 vertex는 세지 않는다(구조 벽 자체가 없는 vertex이므로 "분리된
/// 건물 조각"이 아니다). 여러 개면 구조 벽 evidence가 여러 조각으로
/// 끊겨 있다는 뜻 — production FloorDomain 경로가 이걸로
/// SOURCE_EVIDENCE_LIMITED 여부를 판정한다.
int countConnectedComponents(PlanarGraph graph) {
  final visited = <int>{};
  var count = 0;
  for (final v in graph.vertices) {
    if (visited.contains(v.id)) continue;
    if (graph.adjacency[v.id]!.isEmpty) continue;
    count++;
    final stack = [v.id];
    visited.add(v.id);
    while (stack.isNotEmpty) {
      final cur = stack.removeLast();
      for (final eId in graph.adjacency[cur]!) {
        final e = graph.edges[eId];
        final other = e.v1 == cur ? e.v2 : e.v1;
        if (visited.add(other)) stack.add(other);
      }
    }
  }
  return count;
}

/// 여러 face 중 "바깥쪽(경계 없는) face"를 찾는다 — 표준 결과: 같은
/// 연결 성분 안에서 안쪽 face들은 signed area 부호가 서로 같고, 바깥쪽
/// face 하나만 반대 부호를 갖는다(면적 절댓값도 보통 가장 크다 — 다른
/// 모든 face를 감싸므로). 부호가 소수인 쪽을 바깥쪽으로 판정한다.
List<PlanarFace> findOuterFaces(List<PlanarFace> faces) {
  if (faces.isEmpty) return const [];
  final positive = faces.where((f) => f.signedArea > 0).toList();
  final negative = faces.where((f) => f.signedArea < 0).toList();
  if (positive.isEmpty) return negative;
  if (negative.isEmpty) return positive;
  return positive.length <= negative.length ? positive : negative;
}
