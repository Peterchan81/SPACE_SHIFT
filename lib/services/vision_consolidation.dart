/// GPT CAD 핵심 이식 — Floorplan-CAD-Test에서 검증된 다회 분석 통합/검증
/// 레이어(WO086)를 이 프로젝트의 [CadFloorPlan] 모델에 맞게 옮긴 것이다.
///
/// 기존 GPT CAD 이미지 생성 흐름([FloorPlanImageGenerationService]/
/// gpt-floorplan-cad-image)과 기존 픽셀 분석 엔진([FloorPlanAnalysisService])은
/// 이 파일에서 전혀 건드리지 않는다 — 이미 완성돼 있던
/// [VisionGuidedSpatialModelBuilder](gpt-floorplan-understand 기반, R&D/
/// 대체 경로로 보존되어 있던 것)를 그대로 재사용해 같은 이미지를 N번
/// 호출하고, 그 결과를 이 파일이 결정론적으로 통합한다 — AI를 더 많이
/// 부르는 것 자체가 목적이 아니라, "몇 번을 불렀을 때 서로 일치하는가"를
/// 프로그램이 판단해 신뢰도로 바꾸는 것이 목적이다.
///
/// 사용자가 이미 확정한 실측값([FloorPlanScale.source] ==
/// [ScaleSource.measured])을 이 통합 결과가 절대 덮어쓰지 않는다는
/// 보장은, 기존 [resolveAutoScale]("existing != null이면 절대 덮어쓰지
/// 않는다")을 호출부가 그대로 재사용하는 것으로 충분하다 — 이 파일은
/// 축척을 전혀 만들지 않는다(walls/openings/rooms의 정규화 geometry와
/// confidence만 통합한다).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../models/cad_floor_plan.dart';
import '../models/floor_plan_geometry.dart';
import 'vision_interpretation_service.dart' show GptBillingExhaustedException;

/// [buildOnce]([VisionGuidedSpatialModelBuilder.buildCad]를 실사용 경로가
/// 그대로 넘긴다 — 테스트는 가짜 함수를 주입해 이 파일의 재시도/통합
/// 로직만 네트워크·픽셀 분석 없이 검증한다)를 같은 이미지에 [samples]번
/// 실행하고, 그 결과를 [consolidateCadFloorPlans]로 통합한다. 개별 호출이
/// 실패해도(네트워크 오류 등) 나머지 성공한 결과만으로 통합을 시도하고,
/// 전부 실패했을 때만 예외를 던진다(기존 단일 호출 실패 처리와 동일한
/// "조용히 실패, 화면은 원본으로 폴백" 원칙은 호출부가 담당).
Future<CadFloorPlan> buildConsolidatedVisionCadFloorPlan(
  Uint8List imageBytes, {
  required Future<CadFloorPlan> Function(Uint8List) buildOnce,
  int samples = 3,
}) async {
  final results = <CadFloorPlan>[];
  Object? lastError;
  for (var i = 0; i < samples; i++) {
    try {
      results.add(await buildOnce(imageBytes));
    } catch (error) {
      lastError = error;
    }
  }
  if (results.isEmpty) {
    throw lastError ?? StateError('모든 GPT 구조 분석 시도가 실패했습니다.');
  }
  return consolidateCadFloorPlans(results);
}

/// SS CAD TEST — API 호출 정책(비용 감사) WO §4/§5/§7. [buildConsolidatedVisionCadFloorPlan]
/// 은 항상 [samples]번(기본 3) 무조건 호출한다 — 실사용 감사 결과 "GPT
/// 구조 분석 실행" 버튼 1회가 항상 정확히 3회의 유료 OpenAI 호출로
/// 이어지고 있었다. 이 함수는 같은 통합 알고리즘([consolidateCadFloorPlans],
/// 새로 만들지 않음)을 재사용하되 호출 횟수를 "1회 기본 + 결과가
/// 불충분할 때만 추가"로 바꾼다:
///
/// - 어떤 시도든 성공하고 [isResultSufficient]가 true면 그 즉시 멈춘다
///   (추가 유료 호출 없음 — 정상적인 경우 실제 OpenAI 요청은 1회뿐이다).
/// - 시도가 실패했거나 결과가 불충분하면(원본 벽이 하나도 없음/외곽이
///   안 닫힘/벽 대부분이 reviewNeeded) [maxSamples]까지 추가로 시도해
///   성공한 결과들만 통합한다 — 2번째 시도가 충분해지면 3번째는 걸지
///   않는다("2/3회차는 무조건 채운다"가 아니다).
/// - [GptBillingExhaustedException]은 몇 번째 시도든 즉시 그대로 다시
///   던지고 멈춘다(§5 — 결제 문제는 재시도해도 100% 같은 이유로 다시
///   실패하므로, 남은 시도를 소비하지 않는다).
///
/// [onAttempt]는 실제 유료 요청이 나갈 때마다(성공/실패와 무관하게) 한 번
/// 호출되는 계측 콜백(§7) — 호출부가 `[AI CALL] ...` 형태로 로그를 남기는
/// 데만 쓰고, 이 함수의 판단 로직에는 전혀 관여하지 않는다.
Future<CadFloorPlan> runAdaptiveVisionConsolidation(
  Uint8List imageBytes, {
  required Future<CadFloorPlan> Function(Uint8List) buildOnce,
  int maxSamples = 3,
  bool Function(CadFloorPlan plan) isResultSufficient = isVisionResultSufficient,
  void Function({required int attempt, required String reason, String? outcome})? onAttempt,
}) async {
  final results = <CadFloorPlan>[];
  Object? lastError;

  for (var attempt = 1; attempt <= maxSamples; attempt++) {
    final reason = attempt == 1 ? 'initial' : 'low_confidence';
    try {
      final result = await buildOnce(imageBytes);
      onAttempt?.call(attempt: attempt, reason: reason, outcome: 'success');
      if (isResultSufficient(result)) {
        // 이번 시도가 이미 충분히 좋다(1번째든 이후든) — 그 결과 하나만
        // 그대로 쓰고 끝낸다. 앞서 쌓인(불충분했던) 결과와 억지로
        // 통합하지 않는다 — consolidateCadFloorPlans는 "여러 번 비슷하게
        // 나온 것"의 합의를 신뢰도로 바꾸는 알고리즘이라, 이미 불충분하다고
        // 판단한(예: 벽 0개) 이전 시도와 섞으면 합의가 흐려져 오히려
        // 결과가 더 나빠질 수 있다(실제로 테스트에서 재현됨).
        return result;
      }
      results.add(result);
    } on GptBillingExhaustedException {
      onAttempt?.call(attempt: attempt, reason: reason, outcome: 'billing_exhausted');
      rethrow;
    } catch (error) {
      lastError = error;
      onAttempt?.call(attempt: attempt, reason: reason, outcome: 'failed');
    }
  }

  if (results.isEmpty) {
    throw lastError ?? StateError('모든 GPT 구조 분석 시도가 실패했습니다.');
  }
  return consolidateCadFloorPlans(results);
}

/// 1회 GPT 구조 분석 결과가 추가로 값비싼 재호출을 할 필요가 없을 만큼
/// 충분히 좋은지 판단한다. 애매하면 추가 호출 쪽을 선택한다(보수적) —
/// pixel_wall_v4의 geometry 자체는 픽셀 기반 결정론적 계산이라 재호출해도
/// 안 바뀌지만, AI 의미 corroboration(문/창 종류, 방 라벨, false-positive
/// 정리)은 호출마다 달라질 수 있어 이 부분 품질이 낮을 때만 재호출이
/// 실제로 값이 있다.
bool isVisionResultSufficient(CadFloorPlan plan) {
  if (plan.walls.isEmpty) return false;
  if (plan.warnings.any((w) => w.contains('FloorDomain INVALID'))) return false;
  final reviewNeededRatio = plan.walls.where((w) => w.reviewNeeded).length / plan.walls.length;
  if (reviewNeededRatio > 0.5) return false;
  return true;
}

/// 두 벡터 사이 각도(도, 0~90 — 방향과 반대 방향을 같은 선으로 본다).
double _angleBetweenDeg(double ax, double ay, double bx, double by) {
  final dot = (ax * bx + ay * by).abs().clamp(-1.0, 1.0);
  return math.acos(dot) * 180 / math.pi;
}

class _WallCandidate {
  _WallCandidate({
    required this.runIndex,
    required this.start,
    required this.end,
    required this.thicknessNormalized,
    required this.confidence,
    required this.wallType,
    required this.originalId,
  });

  final int runIndex;
  final Point2 start; // pixel-space (already multiplied by source dimensions)
  final Point2 end;
  final double thicknessNormalized;
  final double confidence;
  final CadWallType wallType;
  final String originalId;
}

class _WallCluster {
  _WallCluster({required Point2 origin, required this.dirX, required this.dirY, required double t0})
    : originX = origin.x,
      originY = origin.y,
      minT = t0,
      maxT = t0;

  final double originX;
  final double originY;
  final double dirX;
  final double dirY;
  double minT;
  double maxT;
  final List<_WallCandidate> members = [];

  double projectT(Point2 p) => (p.x - originX) * dirX + (p.y - originY) * dirY;
  double perpOffset(Point2 p) {
    final px = p.x - originX;
    final py = p.y - originY;
    return (px * dirY - py * dirX).abs();
  }
}

/// 반복 일치 여부로 신뢰도를 조정한다 — 한 번만 검출된 요소는 원래
/// confidence가 얼마였든 확실히 낮게, 전부 일치한 요소는 확실히 높게
/// 만든다(요구사항 4/5). Floorplan-CAD-Test의
/// `repetitionAdjustedConfidence`와 동일한 임계값을 쓴다.
double repetitionAdjustedConfidence(double avgOriginalConfidence, int matchCount, int totalRuns) {
  if (totalRuns <= 1) return avgOriginalConfidence;
  if (matchCount >= totalRuns) {
    return math.min(0.95, avgOriginalConfidence + 0.15);
  }
  if (matchCount == 1) {
    return math.min(0.35, avgOriginalConfidence * 0.5);
  }
  return math.min(0.9, avgOriginalConfidence * 1.05);
}

const double _wallAngleToleranceDeg = 8;

/// [runs]는 모두 같은 원본 이미지를 분석한 결과여야 한다(sourceWidthPx/
/// sourceHeightPx가 같다고 가정 — 다르면 첫 번째 값을 기준으로 삼는다).
CadFloorPlan consolidateCadFloorPlans(List<CadFloorPlan> runs) {
  if (runs.isEmpty) {
    throw ArgumentError('consolidateCadFloorPlans requires at least one run');
  }
  if (runs.length == 1) return runs.first;

  final totalRuns = runs.length;
  final width = runs.first.sourceWidthPx;
  final height = runs.first.sourceHeightPx;
  final diagonal = math.sqrt(width * width + height * height).clamp(1, double.infinity);

  final wallPerpTolerance = math.max(diagonal * 0.02, 10.0);
  final wallGapTolerance = math.max(diagonal * 0.05, 20.0);
  final openingTolerance = diagonal * 0.05;
  final roomTolerance = diagonal * 0.12;

  Point2 toPixel(Point2 p) => Point2(p.x * width, p.y * height);
  Point2 toNormalized(Point2 p) => Point2(p.x / width, p.y / height);

  // --- Walls: line-based matching (same principle as Floorplan-CAD-Test's
  // consolidateAnalyses.ts — different runs disagree on where a wall
  // starts/ends far more than on its line, so segment-endpoint matching
  // misses same-wall-different-segmentation cases entirely). ---
  final clusters = <_WallCluster>[];
  for (var runIndex = 0; runIndex < runs.length; runIndex++) {
    for (final wall in runs[runIndex].walls) {
      final start = toPixel(wall.start);
      final end = toPixel(wall.end);
      final len = start.distanceTo(end);
      if (len <= 0) continue;
      final dirX = (end.x - start.x) / len;
      final dirY = (end.y - start.y) / len;
      final candidate = _WallCandidate(
        runIndex: runIndex,
        start: start,
        end: end,
        thicknessNormalized: wall.thicknessNormalized,
        confidence: wall.confidence,
        wallType: wall.wallType,
        originalId: wall.id,
      );

      _WallCluster? match;
      for (final cluster in clusters) {
        if (_angleBetweenDeg(cluster.dirX, cluster.dirY, dirX, dirY) > _wallAngleToleranceDeg) continue;
        final offStart = cluster.perpOffset(start);
        final offEnd = cluster.perpOffset(end);
        if (math.max(offStart, offEnd) > wallPerpTolerance) continue;
        final t1 = cluster.projectT(start);
        final t2 = cluster.projectT(end);
        final cMin = math.min(t1, t2);
        final cMax = math.max(t1, t2);
        final overlap = math.min(cMax, cluster.maxT) - math.max(cMin, cluster.minT);
        if (overlap < -wallGapTolerance) continue;
        match = cluster;
        break;
      }
      if (match == null) {
        match = _WallCluster(origin: start, dirX: dirX, dirY: dirY, t0: 0);
        match.maxT = start.distanceTo(end);
        clusters.add(match);
      } else {
        final t1 = match.projectT(start);
        final t2 = match.projectT(end);
        match.minT = math.min(match.minT, math.min(t1, t2));
        match.maxT = math.max(match.maxT, math.max(t1, t2));
      }
      match.members.add(candidate);
    }
  }

  final consolidatedWalls = <CadWall>[];
  final wallIdByRunAndOriginal = <String, String>{};
  var wallIndex = 0;
  final rawWalls = <({Point2 start, Point2 end, double thickness, double confidence, int matchCount, CadWallType type})>[];
  for (final cluster in clusters) {
    final runIndexes = cluster.members.map((m) => m.runIndex).toSet();
    final avgConfidence = cluster.members.map((m) => m.confidence).reduce((a, b) => a + b) / cluster.members.length;
    final avgThickness = cluster.members.map((m) => m.thicknessNormalized).reduce((a, b) => a + b) / cluster.members.length;
    final start = Point2(cluster.originX + cluster.dirX * cluster.minT, cluster.originY + cluster.dirY * cluster.minT);
    final end = Point2(cluster.originX + cluster.dirX * cluster.maxT, cluster.originY + cluster.dirY * cluster.maxT);
    final majorityType = _majorityWallType(cluster.members);
    rawWalls.add((
      start: start,
      end: end,
      thickness: avgThickness,
      confidence: avgConfidence,
      matchCount: runIndexes.length,
      type: majorityType,
    ));
  }

  // Single-pass geometric validation: degenerate walls always dropped;
  // a wall seen in only one run AND sharing no endpoint with anything else
  // surviving is dropped as noise (same rule as consolidateAnalyses.ts).
  final degenerateEpsilon = math.max(wallPerpTolerance * 0.1, 0.5);
  bool isConnected(int i) {
    for (var j = 0; j < rawWalls.length; j++) {
      if (i == j) continue;
      final a = rawWalls[i];
      final b = rawWalls[j];
      if (a.start.distanceTo(b.start) <= wallPerpTolerance ||
          a.start.distanceTo(b.end) <= wallPerpTolerance ||
          a.end.distanceTo(b.start) <= wallPerpTolerance ||
          a.end.distanceTo(b.end) <= wallPerpTolerance) {
        return true;
      }
    }
    return false;
  }

  final keptClusterIndexes = <int>[];
  for (var i = 0; i < rawWalls.length; i++) {
    final w = rawWalls[i];
    if (w.start.distanceTo(w.end) <= degenerateEpsilon) continue;
    if (w.matchCount == 1 && !isConnected(i)) continue;
    keptClusterIndexes.add(i);
  }

  for (final i in keptClusterIndexes) {
    final w = rawWalls[i];
    final id = 'vision-wall-${++wallIndex}';
    for (final m in clusters[i].members) {
      wallIdByRunAndOriginal['${m.runIndex}:${m.originalId}'] = id;
    }
    final confidence = repetitionAdjustedConfidence(w.confidence, w.matchCount, totalRuns);
    consolidatedWalls.add(
      CadWall(
        id: id,
        start: toNormalized(w.start),
        end: toNormalized(w.end),
        thicknessNormalized: w.thickness,
        wallType: w.type,
        confidence: confidence,
        reviewNeeded: w.matchCount == 1,
        reviewReasons: w.matchCount == 1
            ? const ['이 벽은 3회 분석 중 1회에서만 검출되었습니다 — 확인이 필요합니다.']
            : const [],
      ),
    );
  }

  // --- Openings: clustered by pixel position, must resolve to the same
  // consolidated wall. ---
  CadOpening buildOpening(
    String prefix,
    int index,
    List<({int runIndex, Point2 center, double width, double confidence, OpeningType type, String wallId})> cluster,
  ) {
    final matchCount = cluster.map((c) => c.runIndex).toSet().length;
    final avgConfidence = cluster.map((c) => c.confidence).reduce((a, b) => a + b) / cluster.length;
    final avgCenter = Point2(
      cluster.map((c) => c.center.x).reduce((a, b) => a + b) / cluster.length,
      cluster.map((c) => c.center.y).reduce((a, b) => a + b) / cluster.length,
    );
    final avgWidth = cluster.map((c) => c.width).reduce((a, b) => a + b) / cluster.length;
    return CadOpening(
      id: '$prefix-${index + 1}',
      type: cluster.first.type,
      center: toNormalized(avgCenter),
      widthNormalized: avgWidth / diagonal,
      confidence: repetitionAdjustedConfidence(avgConfidence, matchCount, totalRuns),
      wallId: cluster.first.wallId,
      reviewNeeded: matchCount == 1,
      reviewReasons: matchCount == 1 ? const ['이 개구부는 3회 분석 중 1회에서만 검출되었습니다.'] : const [],
    );
  }

  List<CadOpening> consolidateOpenings(String prefix, OpeningType type) {
    final candidates = <({int runIndex, Point2 center, double width, double confidence, OpeningType type, String wallId})>[];
    for (var runIndex = 0; runIndex < runs.length; runIndex++) {
      for (final opening in runs[runIndex].openings) {
        if (opening.type != type) continue;
        final wallId = opening.wallId;
        final consolidatedWallId = wallId == null ? null : wallIdByRunAndOriginal['$runIndex:$wallId'];
        if (consolidatedWallId == null) continue; // its wall was dropped as noise
        final centerPx = toPixel(opening.center);
        final widthPx = opening.widthNormalized * diagonal;
        candidates.add((
          runIndex: runIndex,
          center: centerPx,
          width: widthPx,
          confidence: opening.confidence,
          type: type,
          wallId: consolidatedWallId,
        ));
      }
    }
    final clustersOut = <List<({int runIndex, Point2 center, double width, double confidence, OpeningType type, String wallId})>>[];
    for (final candidate in candidates) {
      var matched = -1;
      for (var c = 0; c < clustersOut.length; c++) {
        if (clustersOut[c].first.wallId != candidate.wallId) continue;
        if (clustersOut[c].first.center.distanceTo(candidate.center) <= openingTolerance) {
          matched = c;
          break;
        }
      }
      if (matched == -1) {
        clustersOut.add([candidate]);
      } else {
        clustersOut[matched].add(candidate);
      }
    }
    return [for (var i = 0; i < clustersOut.length; i++) buildOpening(prefix, i, clustersOut[i])];
  }

  final doors = consolidateOpenings('vision-door', OpeningType.door);
  final windows = consolidateOpenings('vision-window', OpeningType.window);

  // --- Rooms: clustered by centroid proximity. ---
  final roomCandidates = <({int runIndex, List<Point2> polygon, double area, double confidence, String? name})>[];
  for (var runIndex = 0; runIndex < runs.length; runIndex++) {
    for (final room in runs[runIndex].rooms) {
      roomCandidates.add((runIndex: runIndex, polygon: room.polygon, area: room.areaNormalized, confidence: room.confidence, name: room.name));
    }
  }
  Point2 centroidOf(List<Point2> polygon) {
    if (polygon.isEmpty) return const Point2(0, 0);
    final sumX = polygon.map((p) => p.x).reduce((a, b) => a + b);
    final sumY = polygon.map((p) => p.y).reduce((a, b) => a + b);
    return toPixel(Point2(sumX / polygon.length, sumY / polygon.length));
  }

  final roomClusters = <List<({int runIndex, List<Point2> polygon, double area, double confidence, String? name})>>[];
  for (final candidate in roomCandidates) {
    final centroid = centroidOf(candidate.polygon);
    var matched = -1;
    for (var c = 0; c < roomClusters.length; c++) {
      if (centroidOf(roomClusters[c].first.polygon).distanceTo(centroid) <= roomTolerance) {
        matched = c;
        break;
      }
    }
    if (matched == -1) {
      roomClusters.add([candidate]);
    } else {
      roomClusters[matched].add(candidate);
    }
  }

  final rooms = <CadRoom>[];
  for (var i = 0; i < roomClusters.length; i++) {
    final cluster = roomClusters[i];
    final matchCount = cluster.map((c) => c.runIndex).toSet().length;
    final avgConfidence = cluster.map((c) => c.confidence).reduce((a, b) => a + b) / cluster.length;
    final best = cluster.reduce((a, b) => b.confidence > a.confidence ? b : a);
    rooms.add(
      CadRoom(
        id: 'vision-room-${i + 1}',
        polygon: best.polygon,
        areaNormalized: best.area,
        confidence: repetitionAdjustedConfidence(avgConfidence, matchCount, totalRuns),
        name: best.name,
        reviewNeeded: matchCount == 1,
        reviewReasons: matchCount == 1 ? const ['이 공간은 3회 분석 중 1회에서만 검출되었습니다.'] : const [],
      ),
    );
  }

  final warnings = <String>{for (final run in runs) ...run.warnings}.toList();
  warnings.add(
    'GPT 구조 분석 $totalRuns회 통합 결과 — 벽 ${consolidatedWalls.length}개'
    '(1회만 검출 ${consolidatedWalls.where((w) => w.reviewNeeded).length}개 포함).',
  );

  return CadFloorPlan(
    sourceWidthPx: width,
    sourceHeightPx: height,
    walls: consolidatedWalls,
    openings: [...doors, ...windows],
    rooms: rooms,
    warnings: warnings,
  );
}

CadWallType _majorityWallType(List<_WallCandidate> members) {
  final exteriorCount = members.where((m) => m.wallType == CadWallType.exterior).length;
  return exteriorCount * 2 >= members.length ? CadWallType.exterior : CadWallType.interior;
}
