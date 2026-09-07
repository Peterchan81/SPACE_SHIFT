// SPACE SHIFT — WO088-2 SEMANTIC → COORDINATE → REAL SCALE ARCHITECTURE POC.
//
// §4/§5 — 이 파일은 새 좌표/축척 산술을 발명하지 않는다. WO082
// (virtual_cad_scale.dart)가 이미 formalize한 4단계 좌표 계층
// (Image px -> Normalized [Point2] -> Virtual CAD -> Real-world mm)과
// WO083(metric_cad.dart)가 이미 만든 결정론적 변환(toMetricCadPoint)을
// coord_structure_v1(WO088-1, WallSystem/PlanarGraph/FloorDomain에
// 의존하지 않는 독립 경로)의 [CoordStructureModel]에 그대로 연결한다.
//
// metric_cad.dart가 [SSSpatialModel](CAD/FloorDomain 결과물)을 입력으로
// 받는 것과 달리, 이 파일은 [CoordStructureModel](FloorDomain 없이도
// 항상 존재하는 pre-topology 구조)을 입력으로 받는다는 것이 유일한 차이다
// — 축척 계산 자체(RealWorldScale, VirtualCadPoint)는 완전히 동일한
// 코드를 재사용한다(중복 발명 금지, WO 지침 §4).
//
// §3B/§14 절대 원칙 재확인: [RealWorldScale.isCalibrated]가 false면(아직
// 사용자가 anchor를 확정하지 않음) mm 값을 임의로 만들지 않는다 —
// [buildMetricCoordStructure]는 이 경우 빈 목록을 반환한다.

import 'dart:math' as math;

import '../../models/floor_plan_geometry.dart';
import '../pixel_wall_v4/metric_cad.dart';
import '../pixel_wall_v4/virtual_cad_scale.dart';
import 'coord_structure_model.dart';

/// §4 [4] Real World Coordinate — [CoordWallSegment] 하나의 mm 기하.
/// [thicknessMm]은 evidence 기반 두께가 유한하지 않으면 null(§5 —
/// 건축 기본값을 대입하지 않는다).
class MetricCoordWall {
  const MetricCoordWall({
    required this.id,
    required this.start,
    required this.end,
    required this.lengthMm,
    required this.thicknessMm,
    required this.isExterior,
    required this.confidence,
    required this.reviewNeeded,
    required this.reviewReasons,
    required this.source,
  });

  final String id;
  final MetricCadPoint start;
  final MetricCadPoint end;
  final double lengthMm;
  final double? thicknessMm;
  final bool isExterior;
  final double confidence;
  final bool reviewNeeded;
  final List<String> reviewReasons;
  final CoordEvidenceSource source;
}

class MetricCoordOpening {
  const MetricCoordOpening({
    required this.id,
    required this.center,
    required this.widthMm,
    required this.kind,
    required this.confidence,
    required this.reviewNeeded,
    required this.source,
  });

  final String id;
  final MetricCadPoint center;
  final double? widthMm;
  final CoordOpeningKind kind;
  final double confidence;
  final bool reviewNeeded;
  final CoordEvidenceSource source;
}

/// §7 RoomBoundary — [CoordRegion]과 동일하게 폐합을 위상적으로 보장하지
/// 않는다(flood-fill 결과 그대로). polygon 변환 도중 한 점이라도 계산
/// 불가면(이론상 calibrate된 scale에서는 발생하지 않지만 방어적으로)
/// 빈 polygon + null area로 남긴다.
class MetricCoordRegion {
  const MetricCoordRegion({required this.id, required this.polygon, required this.areaMm2, required this.confidence});
  final String id;
  final List<MetricCadPoint> polygon;
  final double? areaMm2;
  final double confidence;
}

class MetricCoordCorner {
  const MetricCoordCorner({required this.id, required this.point, required this.wallIds});
  final String id;
  final MetricCadPoint point;
  final List<String> wallIds;
}

/// [buildMetricCoordStructure] 출력 전체 — [scale]을 함께 담아 소비자가
/// 항상 "이 geometry가 어떤 축척 신뢰도로 계산됐는지"를 알 수 있게 한다
/// (metric_cad.dart의 MetricCadResult와 동일한 설계).
class MetricCoordStructureModel {
  const MetricCoordStructureModel({required this.scale, required this.walls, required this.openings, required this.regions, required this.corners});

  final RealWorldScale scale;
  final List<MetricCoordWall> walls;
  final List<MetricCoordOpening> openings;
  final List<MetricCoordRegion> regions;
  final List<MetricCoordCorner> corners;
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

/// [model]과 [scale]로부터 결정론적으로 Real World Coordinate geometry를
/// 만든다 — 같은 입력에는 항상 같은 출력(§8/§15, AI를 다시 호출하지
/// 않는다). [scale]이 calibrate되지 않았으면(§3B) 네 목록 모두 빈 상태로
/// 반환한다.
MetricCoordStructureModel buildMetricCoordStructure(
  CoordStructureModel model,
  RealWorldScale scale, {
  required int sourceWidthPx,
  required int sourceHeightPx,
}) {
  if (!scale.isCalibrated) {
    return MetricCoordStructureModel(scale: scale, walls: const [], openings: const [], regions: const [], corners: const []);
  }

  final w = sourceWidthPx;
  final h = sourceHeightPx;

  VirtualCadPoint virtualOf(Point2 p) => VirtualCadPoint.fromNormalized(p, w: w, h: h);
  MetricCadPoint? mmOf(Point2 p) => toMetricCadPoint(p, scale, sourceWidthPx: w, sourceHeightPx: h);

  final walls = <MetricCoordWall>[];
  for (final wall in model.walls) {
    final startVirtual = virtualOf(wall.start);
    final endVirtual = virtualOf(wall.end);
    final startMm = mmOf(wall.start);
    final endMm = mmOf(wall.end);
    final lengthMm = scale.toMm(startVirtual.distanceTo(endVirtual));
    if (startMm == null || endMm == null || lengthMm == null) continue;

    // §5 두께는 벽 축(긴 변)에 수직인 축의 정규화 값이다 — metric_cad.dart와
    // 동일한 축 선택 관례.
    final isHorizontal = (endVirtual.x - startVirtual.x).abs() >= (endVirtual.y - startVirtual.y).abs();
    final thicknessVirtual = wall.thicknessNormalized * (isHorizontal ? h : w);
    final thicknessMm = scale.toMm(thicknessVirtual);

    walls.add(
      MetricCoordWall(
        id: wall.id,
        start: startMm,
        end: endMm,
        lengthMm: lengthMm,
        thicknessMm: thicknessMm,
        isExterior: wall.isExterior,
        confidence: wall.confidence,
        reviewNeeded: wall.reviewNeeded,
        reviewReasons: wall.reviewReasons,
        source: wall.source,
      ),
    );
  }

  final openings = <MetricCoordOpening>[];
  for (final o in model.openings) {
    final centerMm = mmOf(o.center);
    if (centerMm == null) continue;
    final widthMm = scale.toMm(o.widthNormalized * math.max(w, h));
    openings.add(
      MetricCoordOpening(
        id: o.id,
        center: centerMm,
        widthMm: widthMm,
        kind: o.kind,
        confidence: o.confidence,
        reviewNeeded: o.reviewNeeded,
        source: o.source,
      ),
    );
  }

  final regions = <MetricCoordRegion>[];
  for (final r in model.regions) {
    final polygonMm = <MetricCadPoint>[];
    for (final p in r.polygon) {
      final mp = mmOf(p);
      if (mp == null) break;
      polygonMm.add(mp);
    }
    if (polygonMm.length != r.polygon.length || polygonMm.length < 3) {
      regions.add(MetricCoordRegion(id: r.id, polygon: const [], areaMm2: null, confidence: r.confidence));
      continue;
    }
    regions.add(MetricCoordRegion(id: r.id, polygon: polygonMm, areaMm2: _shoelaceAreaMm2(polygonMm), confidence: r.confidence));
  }

  final corners = <MetricCoordCorner>[];
  for (final c in model.corners) {
    final p = mmOf(c.point);
    if (p == null) continue;
    corners.add(MetricCoordCorner(id: c.id, point: p, wallIds: c.wallIds));
  }

  return MetricCoordStructureModel(scale: scale, walls: walls, openings: openings, regions: regions, corners: corners);
}

/// [MetricCadPoint]를 다시 Normalized Drawing Coordinate([Point2])로
/// 되돌린다 — round-trip 검증 및 "mm 좌표를 다시 화면에 스냅"하는 향후
/// 편집 UI를 위한 역변환. [scale]이 calibrate되지 않았으면 null.
Point2? metricCoordPointToNormalized(
  MetricCadPoint p,
  RealWorldScale scale, {
  required int sourceWidthPx,
  required int sourceHeightPx,
}) {
  if (!scale.isCalibrated) return null;
  final mmPerUnit = scale.mmPerVirtualUnit!;
  if (mmPerUnit == 0) return null;
  final virtual = VirtualCadPoint(p.xMm / mmPerUnit, p.yMm / mmPerUnit);
  return virtual.toNormalized(w: sourceWidthPx, h: sourceHeightPx);
}

/// §4 [4] User Scale Anchor 진입점 — 사용자가 도면 위 두 정규화 좌표
/// (예: coord_structure_screen.dart에서 탭한 두 점)와 실제 길이(mm)를
/// 주면 축척을 계산한다. virtual_cad_scale.dart의
/// [calibrateScaleFromUserAnchor]를 그대로 감싸는 얇은 래퍼일 뿐이다 —
/// Point2(정규화) <-> VirtualCadPoint(px) 변환만 이 함수의 책임이다.
///
/// §4 중요: "문은 보통 900/1000mm"라는 이유만으로 자동 확정하지 않는다
/// — 이 함수는 [realWorldMm]을 무조건 호출자(사용자 입력 또는 사용자가
/// 명시적으로 고른 900/1000mm candidate)로부터만 받는다. 여기서 표준값을
/// 추정하지 않는다.
RealWorldScale calibrateCoordScaleFromAnchor({
  required Point2 a,
  required Point2 b,
  required double realWorldMm,
  required int sourceWidthPx,
  required int sourceHeightPx,
  String? anchorDescription,
}) {
  final va = VirtualCadPoint.fromNormalized(a, w: sourceWidthPx, h: sourceHeightPx);
  final vb = VirtualCadPoint.fromNormalized(b, w: sourceWidthPx, h: sourceHeightPx);
  return calibrateScaleFromUserAnchor(a: va, b: vb, realWorldMm: realWorldMm, anchorDescription: anchorDescription);
}
