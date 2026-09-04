// SPACE SHIFT — PC1 CONTINUE: FLOOR DOMAIN FIRST.
//
// §6 핵심 목표 — FloorDomain은 semantic space에서 만들지 않고, 실제
// outer structural wall network(WallSystem)에서만 만든다. 문/작은 끊김
// gap은 VirtualBoundary로 이어 닫되(§6 "필요한 연결은 pixel evidence +
// same axis + exterior continuity + junction evidence로 복원"), 문
// 범위를 넘는 넓은 gap은 절대 조용히 잇지 않고 root cause로 보고한다
// (공간 수를 맞추려는 fabricated exterior line 생성 금지).

import 'dart:math' as math;

import '../../models/floor_plan_geometry.dart';
import 'pixel_wall_types.dart';
import 'planar_wall_graph.dart';
import 'wall_system.dart';

class FloorDomainResult {
  const FloorDomainResult({
    required this.loop,
    required this.failureReason,
    required this.virtualBoundaries,
    required this.unresolvedGaps,
    this.graphVertexCount = 0,
    this.graphEdgeCount = 0,
    this.graphFaceCount = 0,
    this.tJunctionCount = 0,
    this.sourceEvidenceLimited = false,
  });

  /// 닫혔으면 외곽 loop, 아니면 null(§ "fake exterior line 생성 금지").
  final List<Point2>? loop;
  final String? failureReason;
  final List<VirtualBoundary> virtualBoundaries;

  /// 문 범위를 넘겨 조용히 잇지 않은 gap들 — root cause 보고용
  /// (위치 + gap 크기 + 왜 못 이었는지).
  final List<WallGap> unresolvedGaps;

  /// PlanarGraph 기반 경로(§ PC2 PRODUCTION INTEGRATION)에서만 채워지는
  /// 진단 통계 — 옛 chain walker 경로는 기본값(0/false)을 그대로 쓴다.
  final int graphVertexCount;
  final int graphEdgeCount;
  final int graphFaceCount;
  final int tJunctionCount;

  /// true면: PlanarGraph 자체는 유효(구조 벽 edge가 존재)하지만, 실제
  /// source image의 pixel evidence가 끊겨 있어 단일 outer loop로 닫히지
  /// 못했다는 뜻(§9 SOURCE_EVIDENCE_LIMITED) — bbox/convex hull로 억지
  /// 폐합하지 않고 정직하게 이 상태로 남긴다.
  final bool sourceEvidenceLimited;

  bool get isValid => loop != null;
}

/// 한 축(system) 안에서 notConnected/openPlan gap을 경계로 "실제로 하나로
/// 이어지는 구간(run)"만 잘라낸다 — doorOpening/imageBreak gap은
/// VirtualBoundary로 이어 하나의 run으로 취급한다.
class _WallRun {
  _WallRun({required this.orientation, required this.axisPx, required this.startAlongPx, required this.endAlongPx, required this.thicknessPx});
  final PixelWallOrientation orientation;
  final double axisPx;
  final double startAlongPx;
  final double endAlongPx;

  /// 이 run을 이루는 segment들의 최대 두께(px) — corner snap 허용
  /// 오차를 "고정 큰 값"이 아니라 실제 벽 두께에서 유도하기 위해
  /// 필요하다(§10).
  final double thicknessPx;

  Point2 startPoint(int w, int h) => orientation == PixelWallOrientation.horizontal
      ? Point2(startAlongPx / w, axisPx / h)
      : Point2(axisPx / w, startAlongPx / h);
  Point2 endPoint(int w, int h) => orientation == PixelWallOrientation.horizontal
      ? Point2(endAlongPx / w, axisPx / h)
      : Point2(axisPx / w, endAlongPx / h);
}

double _distPx(Point2 a, Point2 b, int w, int h) {
  final dx = (a.x - b.x) * w;
  final dy = (a.y - b.y) * h;
  return math.sqrt(dx * dx + dy * dy);
}

FloorDomainResult buildFloorDomain({
  required List<WallSystem> wallSystems,
  required int w,
  required int h,
}) {
  double alongOf(PixelWallCandidate c, PixelWallOrientation o, bool isMin) {
    final a = o == PixelWallOrientation.horizontal ? c.start.x * w : c.start.y * h;
    final b = o == PixelWallOrientation.horizontal ? c.end.x * w : c.end.y * h;
    return isMin ? math.min(a, b) : math.max(a, b);
  }

  double thicknessPxOf(PixelWallCandidate c, PixelWallOrientation o) =>
      c.thicknessNormalized * (o == PixelWallOrientation.horizontal ? h : w);

  // 실기 FAIL 재조사(PC1 CONTINUE §10 진단: "B. exterior classification
  // 오류") — WallSystem.isExterior는 클러스터 내 다수결이라, 진짜 외벽
  // 1개 + 진짜 내벽 1개가 같은 축 근처에 우연히 묶이면 동률(1:1)로
  // 시스템 전체가 잘못 "외벽"이 돼 버렸다(실측: 두 gap 모두 이 패턴).
  // 시스템 단위가 아니라 "그 시스템에 속한 개별 segment 중 실제로
  // isExterior=true인 것"만 걸러 사용한다 — 다수결로 다른 segment의
  // 개별 판정을 덮어쓰지 않는다.
  final exteriorSegmentsBySystem = <(PixelWallOrientation orientation, double axisPx, List<PixelWallCandidate> segs)>[];
  for (final system in wallSystems) {
    final segs = system.segments.where((s) => s.isExterior).toList()
      ..sort((a, b) => alongOf(a, system.orientation, true).compareTo(alongOf(b, system.orientation, true)));
    if (segs.isNotEmpty) {
      exteriorSegmentsBySystem.add((system.orientation, system.axisPx, segs));
    }
  }
  if (exteriorSegmentsBySystem.isEmpty) {
    return const FloorDomainResult(
      loop: null,
      failureReason: '외벽으로 분류된 wall system이 없음',
      virtualBoundaries: [],
      unresolvedGaps: [],
    );
  }

  final runs = <_WallRun>[];
  final virtualBoundaries = <VirtualBoundary>[];
  final unresolvedGaps = <WallGap>[];

  for (final entry in exteriorSegmentsBySystem) {
    final (orientation, axisPx, segs) = entry;
    var runStartAlong = alongOf(segs.first, orientation, true);
    var runEndAlong = alongOf(segs.first, orientation, false);
    var runMaxThickness = thicknessPxOf(segs.first, orientation);

    void flushRun() {
      runs.add(_WallRun(orientation: orientation, axisPx: axisPx, startAlongPx: runStartAlong, endAlongPx: runEndAlong, thicknessPx: runMaxThickness));
    }

    for (var i = 0; i < segs.length - 1; i++) {
      final cur = segs[i];
      final next = segs[i + 1];
      final gapPx = alongOf(next, orientation, true) - alongOf(cur, orientation, false);
      if (gapPx <= 0) {
        // 겹침(이미 병합됐어야 함) — 방어적으로 이어붙인다.
        runEndAlong = alongOf(next, orientation, false);
        runMaxThickness = math.max(runMaxThickness, thicknessPxOf(next, orientation));
        continue;
      }
      final kind = classifyGap(gapPx, isExterior: true);
      if (kind == GapKind.imageBreak || kind == GapKind.doorOpening) {
        final bridgeStart = orientation == PixelWallOrientation.horizontal
            ? Point2(alongOf(cur, orientation, false) / w, axisPx / h)
            : Point2(axisPx / w, alongOf(cur, orientation, false) / h);
        final bridgeEnd = orientation == PixelWallOrientation.horizontal
            ? Point2(alongOf(next, orientation, true) / w, axisPx / h)
            : Point2(axisPx / w, alongOf(next, orientation, true) / h);
        virtualBoundaries.add(VirtualBoundary(start: bridgeStart, end: bridgeEnd, reason: kind));
        runEndAlong = alongOf(next, orientation, false);
        runMaxThickness = math.max(runMaxThickness, thicknessPxOf(next, orientation));
      } else {
        flushRun();
        final centerAlong = (alongOf(cur, orientation, false) + alongOf(next, orientation, true)) / 2;
        final center = orientation == PixelWallOrientation.horizontal ? (x: centerAlong, y: axisPx) : (x: axisPx, y: centerAlong);
        unresolvedGaps.add(WallGap(gapPx: gapPx, kind: kind, centerPx: center));
        runStartAlong = alongOf(next, orientation, true);
        runEndAlong = alongOf(next, orientation, false);
        runMaxThickness = thicknessPxOf(next, orientation);
      }
    }
    flushRun();
  }

  if (runs.isEmpty) {
    return const FloorDomainResult(
      loop: null,
      failureReason: '외벽 run이 하나도 만들어지지 않음',
      virtualBoundaries: [],
      unresolvedGaps: [],
    );
  }

  // PC1 CONTINUE §10 — corner snap 허용 오차는 고정된 큰 값이 아니라
  // 두 run의 실제 벽 두께에서 유도한다(두께가 클수록 centerline 끝점이
  // 코너에서 더 크게 벗어날 수 있다는 현실적 근거). 최소 8px(가장 얇은
  // 실측 벽 두께보다 약간 크게), 배율 1.5배, 상한 24px(임의로 큰 값을
  // 피하기 위한 안전판 — 이보다 멀면 "실제로 안 이어짐"으로 본다).
  double cornerToleranceFor(_WallRun a, _WallRun b) {
    final base = math.max(a.thicknessPx, b.thicknessPx) * 1.5;
    return base.clamp(8.0, 24.0);
  }

  // 실기 FAIL 재조사(PC1 CONTINUE §22 카테고리 E: OUTER CYCLE EXTRACTION
  // 실패) — 이전 구현은 임의로 고른 첫 run의 "끝" 방향으로만 한쪽으로
  // 걸어갔다. 그 run의 "시작" 쪽에 실제로 이어지는 run이 있어도 반대
  // 방향은 전혀 확인하지 않아, 3개 run이 실제로 순서대로 다 이어지는
  // 성분(component)인데도 2개만 연결된 것으로 잘못 보고하는 경우가
  // 실측으로 확인됐다. 정방향(끝→다음 시작/끝)과 역방향(시작→다른
  // run의 시작/끝)을 모두 걸어 같은 성분에 속한 run을 놓치지 않는다.
  final remaining = [...runs];
  final first = remaining.removeAt(0);
  final loopPoints = <Point2>[first.startPoint(w, h), first.endPoint(w, h)];

  var forwardCurrent = first.endPoint(w, h);
  var forwardRun = first;
  while (remaining.isNotEmpty) {
    _WallRun? best;
    var useStart = true;
    var bestDist = double.infinity;
    for (final run in remaining) {
      final tolerance = cornerToleranceFor(forwardRun, run);
      final dStart = _distPx(forwardCurrent, run.startPoint(w, h), w, h);
      final dEnd = _distPx(forwardCurrent, run.endPoint(w, h), w, h);
      if (dStart <= tolerance && dStart < bestDist) {
        bestDist = dStart;
        best = run;
        useStart = true;
      }
      if (dEnd <= tolerance && dEnd < bestDist) {
        bestDist = dEnd;
        best = run;
        useStart = false;
      }
    }
    if (best == null) break;
    remaining.remove(best);
    final next = useStart ? best.endPoint(w, h) : best.startPoint(w, h);
    loopPoints.add(next);
    forwardCurrent = next;
    forwardRun = best;
  }

  var backwardCurrent = first.startPoint(w, h);
  var backwardRun = first;
  while (remaining.isNotEmpty) {
    _WallRun? best;
    var useEnd = true;
    var bestDist = double.infinity;
    for (final run in remaining) {
      final tolerance = cornerToleranceFor(backwardRun, run);
      final dStart = _distPx(backwardCurrent, run.startPoint(w, h), w, h);
      final dEnd = _distPx(backwardCurrent, run.endPoint(w, h), w, h);
      if (dEnd <= tolerance && dEnd < bestDist) {
        bestDist = dEnd;
        best = run;
        useEnd = true;
      }
      if (dStart <= tolerance && dStart < bestDist) {
        bestDist = dStart;
        best = run;
        useEnd = false;
      }
    }
    if (best == null) break;
    remaining.remove(best);
    final prev = useEnd ? best.startPoint(w, h) : best.endPoint(w, h);
    loopPoints.insert(0, prev);
    backwardCurrent = useEnd ? best.startPoint(w, h) : best.endPoint(w, h);
    backwardRun = best;
  }

  final current = forwardCurrent;
  final currentRun = forwardRun;

  if (remaining.isNotEmpty) {
    return FloorDomainResult(
      loop: null,
      failureReason: '외벽 run ${remaining.length}개가 인접 run과 코너에서 연결되지 않음(두께 기반 허용오차 내 후보 없음)',
      virtualBoundaries: virtualBoundaries,
      unresolvedGaps: unresolvedGaps,
    );
  }
  final closureTolerance = cornerToleranceFor(currentRun, backwardRun);
  final closureDist = _distPx(current, backwardCurrent, w, h);
  if (closureDist > closureTolerance) {
    return FloorDomainResult(
      loop: null,
      failureReason: '외벽 loop가 시작점으로 닫히지 않음(닫힘 거리 ${closureDist.toStringAsFixed(1)}px, 허용오차 ${closureTolerance.toStringAsFixed(1)}px)',
      virtualBoundaries: virtualBoundaries,
      unresolvedGaps: unresolvedGaps,
    );
  }

  return FloorDomainResult(loop: loopPoints, failureReason: null, virtualBoundaries: virtualBoundaries, unresolvedGaps: unresolvedGaps);
}

/// PC2 PLANAR GRAPH → PRODUCTION FLOOR DOMAIN INTEGRATION.
///
/// [buildFloorDomain]（위 함수, 이제 production 경로에서 더 이상 primary로
/// 쓰이지 않는다 — 자체 테스트를 위해 그대로 남겨둔다）는 각 candidate에
/// 미리 매긴 isExterior로 endpoint-to-endpoint 체인을 걷는다. 이 함수는
/// 대신 [buildPlanarGraph]가 만드는 위상 그래프(T/L/X-junction split +
/// half-edge/DCEL face 추출 포함)에서 "바깥쪽(경계 없는) face"를 그대로
/// FloorDomain 경계로 쓴다 — 개별 벽의 isExterior 판정은 더 이상 경계를
/// 결정하는 authority가 아니다(§ 근본 원칙, planar_wall_graph.dart 문서
/// 주석과 동일).
///
/// 면적이 가장 큰 face를 무조건 고르지 않는다: [findOuterFaces]가 이미
/// signed-area 부호로 "안쪽/바깥쪽"을 위상학적으로 구분한 뒤에만, 그
/// 바깥쪽 후보들 중에서 크기를 고른다. 구조 벽이 여러 연결 성분으로
/// 나뉘어 있으면(실제 source image에 evidence가 없는 gap) 억지로 하나의
/// loop로 잇지 않고 GRAPH_VALID + SOURCE_EVIDENCE_LIMITED로 정직하게
/// 보고한다(bbox/convex hull 폐합 금지).
FloorDomainResult buildFloorDomainFromPlanarGraph({
  required List<PixelWallCandidate> candidates,
  required int w,
  required int h,
}) {
  final graph = buildPlanarGraph(candidates: candidates, w: w, h: h);

  if (graph.edges.isEmpty) {
    return const FloorDomainResult(
      loop: null,
      failureReason: 'PlanarGraph: 구조 벽에서 edge가 하나도 생성되지 않음',
      virtualBoundaries: [],
      unresolvedGaps: [],
    );
  }

  final tJunctionCount = graph.vertices.where((v) => graph.adjacency[v.id]!.length == 3).length;

  Point2 vertexPoint(int vId) {
    final v = graph.vertices[vId];
    return Point2(v.xPx / w, v.yPx / h);
  }

  final virtualBoundaries = [
    for (final e in graph.edges)
      if (e.isVirtualBridge)
        VirtualBoundary(start: vertexPoint(e.v1), end: vertexPoint(e.v2), reason: e.virtualBridgeReason ?? GapKind.doorOpening),
  ];

  final pruned = pruneDanglingEdges(graph);
  final prunedEdgeIds = pruned.edges.map((e) => e.id).toSet();
  final danglingEdges = graph.edges.where((e) => !prunedEdgeIds.contains(e.id)).toList();

  // 안 닫힌 이유를 root cause로 보고하기 위한 최소 진단 — 실제 gap 크기가
  // 아니라 "이 dangling edge가 어디서 끊겼는지"를 WallGap 형태로 재사용한다
  // (§9 정확히 어떤 edge/evidence가 부족한지 report).
  final unresolvedGaps = [
    for (final e in danglingEdges)
      WallGap(
        gapPx: e.thicknessPx,
        kind: GapKind.notConnected,
        centerPx: (x: (graph.vertices[e.v1].xPx + graph.vertices[e.v2].xPx) / 2, y: (graph.vertices[e.v1].yPx + graph.vertices[e.v2].yPx) / 2),
      ),
  ];

  final componentCount = countConnectedComponents(pruned);
  final faces = extractFaces(pruned);
  final outerFaces = findOuterFaces(faces);

  if (outerFaces.isEmpty || componentCount > 1) {
    return FloorDomainResult(
      loop: null,
      failureReason: componentCount > 1
          ? 'PlanarGraph: 구조 벽이 서로 이어지지 않는 $componentCount개 성분으로 나뉘어 단일 outer loop를 만들 수 없음'
                '(dangling edge ${danglingEdges.length}개 — source evidence 부족)'
          : 'PlanarGraph: 닫힌 outer face를 찾지 못함(dangling edge ${danglingEdges.length}개 — source evidence 부족)',
      virtualBoundaries: virtualBoundaries,
      unresolvedGaps: unresolvedGaps,
      graphVertexCount: graph.vertices.length,
      graphEdgeCount: graph.edges.length,
      graphFaceCount: faces.length,
      tJunctionCount: tJunctionCount,
      sourceEvidenceLimited: true,
    );
  }

  final chosen = outerFaces.reduce((a, b) => a.signedArea.abs() >= b.signedArea.abs() ? a : b);
  final loop = [for (final vId in chosen.vertexIds) vertexPoint(vId)];

  return FloorDomainResult(
    loop: loop,
    failureReason: null,
    virtualBoundaries: virtualBoundaries,
    unresolvedGaps: unresolvedGaps,
    graphVertexCount: graph.vertices.length,
    graphEdgeCount: graph.edges.length,
    graphFaceCount: faces.length,
    tJunctionCount: tJunctionCount,
    sourceEvidenceLimited: false,
  );
}
