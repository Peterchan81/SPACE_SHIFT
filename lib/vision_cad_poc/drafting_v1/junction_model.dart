// SPACE SHIFT — WO088-6 5mm SNAP + JUNCTION MODEL.
//
// §8 핵심 원칙: grid snap과 junction merge는 서로 다른 결정이다.
// - junction 병합 여부는 RAW(스냅 전) mm 거리로만 판단한다(고정된 물리적
//   근접도 기준 — grid 크기와 무관, "실제로 같은 접점인가"만 본다).
// - grid snap은 그 판단이 끝난 "뒤에" 좌표 표시값에만 적용한다.
// 이렇게 분리하지 않으면(즉 "snap 후 좌표가 우연히 같아졌다"를 병합
// 기준으로 쓰면) grid 경계에 걸친 서로 다른 두 점이 우연히 같은 칸으로
// 반올림되어 의도하지 않은 연결이 생길 수 있다 — 이 파일은 그 실수를
// 구조적으로 방지한다.

import 'dart:math' as math;

import '../pixel_wall_v4/virtual_cad_scale.dart' show RealWorldScale;
import 'drafting_model.dart';
import 'real_mm_grid.dart';

enum JunctionType { end, lJunction, straightPassThrough, tJunction, xJunction, openingEnd, unconnectedReview }

/// [touchedWallBodyId] — tJunction일 때만 채워진다: 이 접점이 어느
/// 벽의 "끝점"이 아니라 "몸통"에 닿아 만들어진 T-junction인지 추적한다
/// (§7 T-JUNCTION 정의 그대로 — through-wall 자체를 split하지는 않는다,
/// 이는 wall 검출 알고리즘 변경에 해당하므로 이번 WO 범위 밖).
class Junction {
  const Junction({required this.id, required this.point, required this.type, required this.memberEndpoints, this.touchedWallBodyId});
  final String id;
  final RealMmPoint point;
  final JunctionType type;
  final List<({String wallId, bool isStart})> memberEndpoints;
  final String? touchedWallBodyId;

  int get degree => memberEndpoints.length;
}

class JunctionWall {
  const JunctionWall({
    required this.id,
    required this.rawStart,
    required this.rawEnd,
    required this.startJunctionId,
    required this.endJunctionId,
    required this.classification,
    required this.method,
  });
  final String id;

  /// raw(스냅 전) mm — §5 보존 원칙.
  final RealMmPoint rawStart;
  final RealMmPoint rawEnd;

  /// 실제 그려야 할 좌표는 항상 이 id로 [JunctionDraftResult.junctions]를
  /// 조회해서 얻는다 — 좌표를 벽마다 중복 저장하지 않는다(§7 "동일
  /// Junction을 참조할 수 있는 구조").
  final String startJunctionId;
  final String endJunctionId;
  final WallAngleClass classification;
  final String method;
}

class JunctionStats {
  const JunctionStats({
    required this.wallCount,
    required this.rawEndpointCount,
    required this.snappedEndpointCount,
    required this.uniqueJunctionCount,
    required this.endCount,
    required this.lJunctionCount,
    required this.straightPassThroughCount,
    required this.tJunctionCount,
    required this.xJunctionCount,
    required this.reviewCount,
    required this.avgSnapMoveMm,
    required this.maxSnapMoveMm,
    required this.wallsLostToZeroLength,
    required this.preventedNearMissMerges,
  });

  final int wallCount;
  final int rawEndpointCount;

  /// snap 적용 후 실제로 쓰이는 서로 다른 좌표 개수(= unique junction 좌표 수).
  final int snappedEndpointCount;
  final int uniqueJunctionCount;
  final int endCount;
  final int lJunctionCount;
  final int straightPassThroughCount;
  final int tJunctionCount;
  final int xJunctionCount;
  final int reviewCount;
  final double avgSnapMoveMm;
  final double maxSnapMoveMm;
  final int wallsLostToZeroLength;

  /// grid snap 좌표가 우연히 같아졌지만 raw 거리 기준으로는 병합하지
  /// 않은(즉 "잘못 자동 연결될 뻔했으나 막은") 경우의 수.
  final int preventedNearMissMerges;
}

class JunctionDraftResult {
  const JunctionDraftResult({required this.scale, required this.walls, required this.junctions, required this.gridMm, required this.stats});
  final RealWorldScale scale;
  final List<JunctionWall> walls;
  final Map<String, Junction> junctions;
  final double gridMm;
  final JunctionStats stats;

  RealMmPoint snappedPointOf(String junctionId) => junctions[junctionId]!.point;
}

double _snapValue(double v, double gridMm) => (v / gridMm).round() * gridMm;

RealMmPoint _snapPoint(RealMmPoint p, double gridMm) => RealMmPoint(_snapValue(p.xMm, gridMm), _snapValue(p.yMm, gridMm));

class _UnionFind {
  _UnionFind(int n) : parent = List.generate(n, (i) => i);
  final List<int> parent;
  int find(int x) => parent[x] == x ? x : (parent[x] = find(parent[x]));
  void union(int a, int b) {
    final ra = find(a), rb = find(b);
    if (ra != rb) parent[ra] = rb;
  }
}

/// [mmDraft](real_mm_grid.dart 산출, raw mm)로부터 §7/§8의 snap+junction
/// 모델을 만든다.
///
/// [junctionMergeToleranceMm]을 넘기지 않으면 [kCornerClusterTolerancePx]
/// (drafting_model.dart, 이미 WO088-4에서 검증된 px 단위 코너 근접
/// 허용오차)를 그대로 [scale]로 mm 환산해 쓴다 — 이번 WO 전용 새
/// magic number가 아니다.
JunctionDraftResult buildJunctionDraft(
  RealMmDraft mmDraft, {
  double gridMm = 5.0,
  double? junctionMergeToleranceMm,
  double reviewBandMultiplier = 3.0,
}) {
  final mergeTol = junctionMergeToleranceMm ?? (kCornerClusterTolerancePx * mmDraft.scale.mmPerVirtualUnit!);
  final reviewBand = mergeTol * reviewBandMultiplier;

  final walls = mmDraft.walls;
  // endpoint index: 2*i = wall[i].start, 2*i+1 = wall[i].end.
  final points = <RealMmPoint>[];
  final refs = <({String wallId, bool isStart})>[];
  for (final w in walls) {
    points.add(w.rawStart);
    refs.add((wallId: w.id, isStart: true));
    points.add(w.rawEnd);
    refs.add((wallId: w.id, isStart: false));
  }
  final n = points.length;
  final uf = _UnionFind(n);

  var preventedNearMiss = 0;
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      if (refs[i].wallId == refs[j].wallId) continue; // 같은 벽의 두 끝점은 별개 접점.
      final rawDist = points[i].distanceTo(points[j]);
      if (rawDist <= mergeTol) {
        uf.union(i, j);
      } else {
        // grid snap 후에는 같은 칸이 될 수 있는데도(§8 위험) raw 거리
        // 기준으로는 병합하지 않은 경우를 별도로 센다.
        final si = _snapPoint(points[i], gridMm);
        final sj = _snapPoint(points[j], gridMm);
        if (si.xMm == sj.xMm && si.yMm == sj.yMm) preventedNearMiss++;
      }
    }
  }

  // union-find 그룹별로 묶기.
  final groups = <int, List<int>>{};
  for (var i = 0; i < n; i++) {
    groups.putIfAbsent(uf.find(i), () => []).add(i);
  }

  final junctions = <String, Junction>{};
  final startJunctionByWall = <String, String>{};
  final endJunctionByWall = <String, String>{};
  final snapMoves = <double>[];
  var jCounter = 0;

  final wallById = {for (final w in walls) w.id: w};

  double angleOfWallAtEndpoint(String wallId, bool isStart) {
    final w = wallById[wallId]!;
    final dx = isStart ? (w.rawEnd.xMm - w.rawStart.xMm) : (w.rawStart.xMm - w.rawEnd.xMm);
    final dy = isStart ? (w.rawEnd.yMm - w.rawStart.yMm) : (w.rawStart.yMm - w.rawEnd.yMm);
    return math.atan2(dy, dx) * 180 / math.pi;
  }

  // §9 0/90° 구조 보존 — WO088-6 최초 구현에서 실측으로 발견된 버그의
  // 수정: junction 좌표를 "관련된 모든 끝점의 (x,y) 평균"으로 그냥
  // 계산하면, 가로벽의 y값이 그 지점에서 만나는 세로벽의(수직 방향으로
  // 임의인) x/y와 섞여 평균이 왜곡된다 — 그 결과 원래 완전히 수평/수직
  // 이던 벽이 snap 후 육안으로 보일 만큼 기울어지는 현상이 image
  // C(5mm Snapped Draft) 초안에서 실제로 나타났다. 수정: 가로벽은
  // y좌표만, 세로벽은 x좌표만 그 축의 snap 근거로 쓴다(서로의 축을
  // 섞지 않는다) — 같은 벽의 두 끝점은 항상 같은 축 값에서 출발하므로
  // (structural_layer.dart run-length band는 원본에서 정확히 동일한
  // cross 값을 쓴다), 이 분리만으로 벽의 원래 축정렬이 snap 후에도
  // 그대로 보존된다.
  ({double? yFromHorizontal, double? xFromVertical}) axisContribution(String wallId) {
    final w = wallById[wallId]!;
    final dx = (w.rawEnd.xMm - w.rawStart.xMm).abs();
    final dy = (w.rawEnd.yMm - w.rawStart.yMm).abs();
    if (dx >= dy) {
      return (yFromHorizontal: (w.rawStart.yMm + w.rawEnd.yMm) / 2, xFromVertical: null);
    }
    return (yFromHorizontal: null, xFromVertical: (w.rawStart.xMm + w.rawEnd.xMm) / 2);
  }

  for (final entry in groups.entries) {
    final memberIdx = entry.value;
    final memberRefs = [for (final idx in memberIdx) refs[idx]];

    final yContribs = <double>[];
    final xContribs = <double>[];
    for (final r in memberRefs) {
      final c = axisContribution(r.wallId);
      if (c.yFromHorizontal != null) yContribs.add(c.yFromHorizontal!);
      if (c.xFromVertical != null) xContribs.add(c.xFromVertical!);
    }
    final fallbackAvgX = memberIdx.map((i) => points[i].xMm).reduce((a, b) => a + b) / memberIdx.length;
    final fallbackAvgY = memberIdx.map((i) => points[i].yMm).reduce((a, b) => a + b) / memberIdx.length;
    // 세로벽이 하나라도 있으면 그 x값들로 x를 정하고, 없으면(예: 이
    // 접점에 가로벽만 여럿 모인 드문 경우) 전체 평균으로 대체한다 —
    // y도 대칭으로 동일하게 처리한다.
    final rawX = xContribs.isNotEmpty ? xContribs.reduce((a, b) => a + b) / xContribs.length : fallbackAvgX;
    final rawY = yContribs.isNotEmpty ? yContribs.reduce((a, b) => a + b) / yContribs.length : fallbackAvgY;
    final rawAvg = RealMmPoint(rawX, rawY);
    final snapped = _snapPoint(rawAvg, gridMm);
    snapMoves.add(rawAvg.distanceTo(snapped));

    JunctionType type;
    if (memberRefs.length == 1) {
      type = JunctionType.end; // T-junction 승격은 아래 별도 pass에서.
    } else if (memberRefs.length == 2) {
      final a1 = angleOfWallAtEndpoint(memberRefs[0].wallId, memberRefs[0].isStart);
      final a2 = angleOfWallAtEndpoint(memberRefs[1].wallId, memberRefs[1].isStart);
      var diff = (a1 - a2).abs() % 360;
      if (diff > 180) diff = 360 - diff;
      type = (diff <= 20 || diff >= 160) ? JunctionType.straightPassThrough : JunctionType.lJunction;
    } else if (memberRefs.length == 3) {
      type = JunctionType.tJunction;
    } else {
      type = JunctionType.xJunction;
    }

    final id = 'junction-${jCounter++}';
    junctions[id] = Junction(id: id, point: snapped, type: type, memberEndpoints: memberRefs);
    for (final r in memberRefs) {
      if (r.isStart) {
        startJunctionByWall[r.wallId] = id;
      } else {
        endJunctionByWall[r.wallId] = id;
      }
    }
  }

  // T-junction 승격 pass — degree-1(END)인 접점이 "다른 벽의 몸통"에
  // 닿아 있는지 확인한다(§7 T-JUNCTION의 실제 정의: 몸통 접촉).
  final endJunctionIds = junctions.values.where((j) => j.type == JunctionType.end).map((j) => j.id).toList();
  final promoted = <String, Junction>{};
  for (final jid in endJunctionIds) {
    final j = junctions[jid]!;
    final selfWallId = j.memberEndpoints.single.wallId;
    for (final w in walls) {
      if (w.id == selfWallId) continue;
      final proj = _projectOntoSegment(j.point, w.rawStart, w.rawEnd);
      if (proj == null) continue;
      final (t, perpDist) = proj;
      if (t > 0.02 && t < 0.98 && perpDist <= mergeTol) {
        promoted[jid] = Junction(id: j.id, point: j.point, type: JunctionType.tJunction, memberEndpoints: j.memberEndpoints, touchedWallBodyId: w.id);
        break;
      }
    }
  }
  junctions.addAll(promoted);

  // REVIEW 승격 pass — 여전히 END인데, 다른 벽 endpoint/body와
  // "애매하게" 가까우면(mergeTol보다는 멀지만 reviewBand 이내)
  // unconnectedReview로 표시한다(§8 "확신할 수 없는 연결은 REVIEW로").
  final reviewPromoted = <String, Junction>{};
  for (final j in junctions.values) {
    if (j.type != JunctionType.end) continue;
    final selfWallId = j.memberEndpoints.single.wallId;
    var suspicious = false;
    for (final other in junctions.values) {
      if (other.id == j.id) continue;
      if (other.memberEndpoints.any((e) => e.wallId == selfWallId)) continue;
      final d = j.point.distanceTo(other.point);
      if (d > mergeTol && d <= reviewBand) {
        suspicious = true;
        break;
      }
    }
    if (!suspicious) {
      for (final w in walls) {
        if (w.id == selfWallId) continue;
        final proj = _projectOntoSegment(j.point, w.rawStart, w.rawEnd);
        if (proj == null) continue;
        final (t, perpDist) = proj;
        if (t > 0 && t < 1 && perpDist > mergeTol && perpDist <= reviewBand) {
          suspicious = true;
          break;
        }
      }
    }
    if (suspicious) {
      reviewPromoted[j.id] = Junction(id: j.id, point: j.point, type: JunctionType.unconnectedReview, memberEndpoints: j.memberEndpoints);
    }
  }
  junctions.addAll(reviewPromoted);

  final junctionWalls = [
    for (final w in walls)
      JunctionWall(
        id: w.id,
        rawStart: w.rawStart,
        rawEnd: w.rawEnd,
        startJunctionId: startJunctionByWall[w.id]!,
        endJunctionId: endJunctionByWall[w.id]!,
        classification: w.classification,
        method: w.method,
      ),
  ];

  var wallsLost = 0;
  for (final jw in junctionWalls) {
    final sp = junctions[jw.startJunctionId]!.point;
    final ep = junctions[jw.endJunctionId]!.point;
    if (sp.xMm == ep.xMm && sp.yMm == ep.yMm) wallsLost++;
  }

  final stats = JunctionStats(
    wallCount: walls.length,
    rawEndpointCount: n,
    snappedEndpointCount: junctions.values.map((j) => '${j.point.xMm},${j.point.yMm}').toSet().length,
    uniqueJunctionCount: junctions.length,
    endCount: junctions.values.where((j) => j.type == JunctionType.end).length,
    lJunctionCount: junctions.values.where((j) => j.type == JunctionType.lJunction).length,
    straightPassThroughCount: junctions.values.where((j) => j.type == JunctionType.straightPassThrough).length,
    tJunctionCount: junctions.values.where((j) => j.type == JunctionType.tJunction).length,
    xJunctionCount: junctions.values.where((j) => j.type == JunctionType.xJunction).length,
    reviewCount: junctions.values.where((j) => j.type == JunctionType.unconnectedReview).length,
    avgSnapMoveMm: snapMoves.isEmpty ? 0 : snapMoves.reduce((a, b) => a + b) / snapMoves.length,
    maxSnapMoveMm: snapMoves.isEmpty ? 0 : snapMoves.reduce(math.max),
    wallsLostToZeroLength: wallsLost,
    preventedNearMissMerges: preventedNearMiss,
  );

  return JunctionDraftResult(scale: mmDraft.scale, walls: junctionWalls, junctions: junctions, gridMm: gridMm, stats: stats);
}

/// [p]를 선분 [a]-[b]에 투영한다. 반환: (t: 0~1 사이면 선분 내부,
/// perpendicularDistanceMm). 선분 길이가 0이면 null.
(double, double)? _projectOntoSegment(RealMmPoint p, RealMmPoint a, RealMmPoint b) {
  final dx = b.xMm - a.xMm, dy = b.yMm - a.yMm;
  final lenSq = dx * dx + dy * dy;
  if (lenSq == 0) return null;
  final t = ((p.xMm - a.xMm) * dx + (p.yMm - a.yMm) * dy) / lenSq;
  final projX = a.xMm + t * dx, projY = a.yMm + t * dy;
  final perp = math.sqrt((p.xMm - projX) * (p.xMm - projX) + (p.yMm - projY) * (p.yMm - projY));
  return (t, perp);
}
