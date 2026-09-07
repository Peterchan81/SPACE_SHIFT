// SPACE SHIFT — WO083 METRIC CAD FOUNDATION.
//
// virtual_cad_scale.dart가 formalize한 4단계 좌표 계층의 마지막 단
// (Virtual CAD -> Real-world Metric mm)에 실제 타입을 붙인다. 이 파일
// 자체는 새 evidence를 만들지 않는다 — 이미 확정된 [SSSpatialModel]
// (wallEdges/openings/spaces)과 사용자가 확정한 [RealWorldScale]만
// 입력으로 받아 결정론적으로 mm 기하를 계산한다.
//
// §3B/§14 절대 원칙: [RealWorldScale.isCalibrated]가 false면(아직 축척을
// 모름) mm 값을 임의로 만들지 않는다 — [buildMetricCad]는 이 경우 빈
// 목록을 반환한다(확정되지 않은 것을 확정된 것처럼 저장하지 않는다).
//
// §5 절대 원칙: 벽 중심선/두께는 [SSWallEdge]에 이미 있는 evidence 기반
// thicknessNormalized만 쓴다 — 100mm/150mm/200mm 같은 건축 기본값을
// 대입하지 않는다.
//
// §5/§12 절대 원칙: [SSSpatialModel.wallEdges]만 벽 source로 쓴다 —
// FloorDomain 폐합용 virtual bridge(PlanarEdge.isVirtualBridge)는
// wallEdges에 애초에 섞이지 않으므로(pixel_wall_pipeline.dart 참고)
// 이 계층에서도 자동으로 제외된다.

import 'dart:math' as math;

import '../../models/floor_plan_geometry.dart';
import '../../models/ss_spatial_model.dart';
import 'virtual_cad_scale.dart';

/// Real-world Metric Coordinate(mm) 위의 점 — 좌표 계층의 마지막 단.
class MetricCadPoint {
  const MetricCadPoint(this.xMm, this.yMm);

  final double xMm;
  final double yMm;

  double distanceTo(MetricCadPoint other) {
    final dx = xMm - other.xMm;
    final dy = yMm - other.yMm;
    return math.sqrt(dx * dx + dy * dy);
  }

  @override
  bool operator ==(Object other) => other is MetricCadPoint && other.xMm == xMm && other.yMm == yMm;

  @override
  int get hashCode => Object.hash(xMm, yMm);

  @override
  String toString() => 'MetricCadPoint(${xMm.toStringAsFixed(1)}mm, ${yMm.toStringAsFixed(1)}mm)';
}

/// Normalized Drawing Coordinate([Point2])를 Virtual CAD를 거쳐 mm로
/// 변환한다. [scale]이 calibrate되지 않았으면 null — 임의 mm를 만들지
/// 않는다(§3B).
MetricCadPoint? toMetricCadPoint(
  Point2 normalized,
  RealWorldScale scale, {
  required int sourceWidthPx,
  required int sourceHeightPx,
}) {
  if (!scale.isCalibrated) return null;
  final virtual = VirtualCadPoint.fromNormalized(normalized, w: sourceWidthPx, h: sourceHeightPx);
  final mm = scale.toMmPoint(virtual);
  if (mm == null) return null;
  return MetricCadPoint(mm.xMm, mm.yMm);
}

/// 연속 구조 벽([SSWallEdge]) 하나의 mm 기하. centerline/length는 항상
/// 값이 있지만(길이는 두 끝점만 있으면 항상 계산 가능), [thicknessMm]은
/// evidence 기반 두께 계산이 유한하지 않으면 null로 남는다 — 신뢰할 수
/// 없는 두께를 임의 기본값으로 채우지 않는다(§5).
class MetricWall {
  const MetricWall({
    required this.id,
    required this.start,
    required this.end,
    required this.lengthMm,
    required this.thicknessMm,
    required this.sourceWallEdgeId,
    required this.source,
    required this.reviewNeeded,
  });

  final String id;
  final MetricCadPoint start;
  final MetricCadPoint end;
  final double lengthMm;
  final double? thicknessMm;

  /// 이 MetricWall이 유래한 [SSWallEdge.id] — provenance 추적용.
  final String sourceWallEdgeId;
  final SSEntitySource source;
  final bool reviewNeeded;
}

/// 개구부([SSOpening]) 하나의 mm 기하. [SSOpening.kind]가 unknown이면
/// 이 계층에서도 unknown 그대로 유지한다(§6 — "문처럼 보인다"는 이유만
/// 으로 확정하지 않는다) — geometry(parentWallId/startT/endT/widthMm)는
/// kind가 unknown이어도 evidence가 있으면 그대로 채운다.
class MetricOpening {
  const MetricOpening({
    required this.id,
    required this.parentWallId,
    required this.kind,
    required this.startT,
    required this.endT,
    required this.center,
    required this.widthMm,
    required this.source,
    required this.reviewNeeded,
  });

  final String id;
  final String? parentWallId;
  final SSOpeningKind kind;
  final double? startT;
  final double? endT;
  final MetricCadPoint? center;
  final double? widthMm;
  final SSEntitySource source;
  final bool reviewNeeded;
}

/// 공간([SSSpace]) 하나의 mm 폴리곤. [SSSpace.closed]가 false거나
/// polygon이 3점 미만이면(SOURCE_EVIDENCE_LIMITED 등 불완전 evidence)
/// [polygon]을 빈 목록으로, [areaMm2]를 null로 남긴다 — bbox/convex
/// hull/임의 폐합으로 채우지 않는다(§7).
class MetricRoom {
  const MetricRoom({
    required this.id,
    required this.polygon,
    required this.areaMm2,
    required this.sourceSpaceId,
    required this.confidence,
  });

  final String id;
  final List<MetricCadPoint> polygon;
  final double? areaMm2;
  final String sourceSpaceId;
  final double confidence;
}

/// [buildMetricCad] 출력 전체 — [scale]을 함께 담아 소비자가 항상
/// "이 geometry가 어떤 축척 신뢰도로 계산됐는지"를 알 수 있게 한다.
class MetricCadResult {
  const MetricCadResult({required this.scale, required this.walls, required this.openings, required this.rooms});

  final RealWorldScale scale;
  final List<MetricWall> walls;
  final List<MetricOpening> openings;
  final List<MetricRoom> rooms;
}

double _shoelaceAreaMm2(List<MetricCadPoint> polygon) {
  var sum = 0.0;
  for (var i = 0; i < polygon.length; i++) {
    final p1 = polygon[i];
    final p2 = polygon[(i + 1) % polygon.length];
    sum += p1.xMm * p2.yMm - p2.xMm * p1.yMm;
  }
  return sum.abs() / 2;
}

/// [model]과 [scale]로부터 결정론적으로 Metric CAD geometry를 만든다.
/// 같은 입력에는 항상 같은 출력이다(§8/§15) — AI를 다시 호출하지 않고,
/// 이미 확정된 evidence/topology/scale만 산술로 변환한다.
///
/// [scale]이 calibrate되지 않았으면(ScaleConfidence.unknown) 세 목록
/// 모두 빈 상태로 반환한다 — mm 기하가 존재하지 않는다는 뜻을 명시적으로
/// 표현한다(§3B).
MetricCadResult buildMetricCad(SSSpatialModel model, RealWorldScale scale) {
  if (!scale.isCalibrated) {
    return MetricCadResult(scale: scale, walls: const [], openings: const [], rooms: const []);
  }

  final w = model.sourceWidthPx;
  final h = model.sourceHeightPx;

  VirtualCadPoint virtualOf(Point2 p) => VirtualCadPoint.fromNormalized(p, w: w, h: h);

  final walls = <MetricWall>[];
  for (final edge in model.wallEdges) {
    final startVirtual = virtualOf(edge.start);
    final endVirtual = virtualOf(edge.end);
    final startMm = toMetricCadPoint(edge.start, scale, sourceWidthPx: w, sourceHeightPx: h);
    final endMm = toMetricCadPoint(edge.end, scale, sourceWidthPx: w, sourceHeightPx: h);
    final lengthMm = scale.toMm(startVirtual.distanceTo(endVirtual));
    if (startMm == null || endMm == null || lengthMm == null) continue;

    // §5 두께는 벽 축(긴 변)에 수직인 축의 정규화 값이다 — 기존
    // pixel_wall_v4 관례(wall_system.dart 등)와 동일한 축 선택.
    final isHorizontal = (endVirtual.x - startVirtual.x).abs() >= (endVirtual.y - startVirtual.y).abs();
    final thicknessVirtual = edge.thicknessNormalized * (isHorizontal ? h : w);
    final thicknessMm = scale.toMm(thicknessVirtual);

    walls.add(
      MetricWall(
        id: edge.id,
        start: startMm,
        end: endMm,
        lengthMm: lengthMm,
        thicknessMm: thicknessMm,
        sourceWallEdgeId: edge.id,
        source: edge.source,
        reviewNeeded: edge.reviewNeeded,
      ),
    );
  }

  final wallEdgeById = {for (final e in model.wallEdges) e.id: e};

  final openings = <MetricOpening>[];
  for (final o in model.openings) {
    final parentId = o.parentWallId;
    final startT = o.startT;
    final endT = o.endT;
    final edge = parentId == null ? null : wallEdgeById[parentId];

    MetricCadPoint? center;
    double? widthMm;
    if (edge != null && startT != null && endT != null) {
      final startVirtual = virtualOf(edge.start);
      final endVirtual = virtualOf(edge.end);
      final edgeLengthVirtual = startVirtual.distanceTo(endVirtual);
      widthMm = scale.toMm((endT - startT) * edgeLengthVirtual);
      final t = (startT + endT) / 2;
      final centerNormalized = Point2(
        edge.start.x + (edge.end.x - edge.start.x) * t,
        edge.start.y + (edge.end.y - edge.start.y) * t,
      );
      center = toMetricCadPoint(centerNormalized, scale, sourceWidthPx: w, sourceHeightPx: h);
    }

    openings.add(
      MetricOpening(
        id: o.id,
        parentWallId: parentId,
        kind: o.kind,
        startT: startT,
        endT: endT,
        center: center,
        widthMm: widthMm,
        source: o.source,
        reviewNeeded: o.reviewNeeded,
      ),
    );
  }

  final rooms = <MetricRoom>[];
  for (final space in model.spaces) {
    if (!space.closed || space.polygon.length < 3) {
      rooms.add(
        MetricRoom(id: space.id, polygon: const [], areaMm2: null, sourceSpaceId: space.id, confidence: space.confidence),
      );
      continue;
    }
    final polygonMm = <MetricCadPoint>[];
    for (final p in space.polygon) {
      final mp = toMetricCadPoint(p, scale, sourceWidthPx: w, sourceHeightPx: h);
      if (mp == null) break;
      polygonMm.add(mp);
    }
    if (polygonMm.length != space.polygon.length) {
      rooms.add(
        MetricRoom(id: space.id, polygon: const [], areaMm2: null, sourceSpaceId: space.id, confidence: space.confidence),
      );
      continue;
    }
    rooms.add(
      MetricRoom(
        id: space.id,
        polygon: polygonMm,
        areaMm2: _shoelaceAreaMm2(polygonMm),
        sourceSpaceId: space.id,
        confidence: space.confidence,
      ),
    );
  }

  return MetricCadResult(scale: scale, walls: walls, openings: openings, rooms: rooms);
}
