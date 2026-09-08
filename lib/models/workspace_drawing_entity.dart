import 'dart:math' as math;

import 'floor_plan_geometry.dart';

/// WO089 CORE EDITING — 사용자가 2D 작업 화면에서 직접 만든 도형.
///
/// 기존 [WorkspaceTaskItem](workspace_task_item.dart)은 이미 존재하는
/// CAD 요소(벽/문/창 등)에 붙는 "작업 항목"(marker 하나, 실제 geometry
/// 없음)이라 이 목적에 맞지 않는다 — 직선/곡선/원형/자유영역은 사용자가
/// 그 자체로 만들어낸 geometry를 가져야 한다(§4 조사 결론: 기존 모델
/// 재사용 불가, 최소 신규 모델 필요).
///
/// 좌표는 항상 정규화 [Point2](0.0~1.0, 이미지/문서 좌표계 — 화면 픽셀도
/// 아니고 CAD mm도 아니다)로만 저장한다. 화면 확대/축소/이동은 이 값에
/// 절대 영향을 주지 않는다(§5).
enum WorkspaceDrawingType { line, curve, circle, freeRegion }

/// [points]의 의미는 [type]에 따라 다르다:
/// - line: [start, end] (정확히 2점)
/// - curve: [start, control, end] (정확히 3점, 2차 베지어)
/// - circle: [center, edgePoint] (정확히 2점 — 반지름은 두 점 사이 거리)
/// - freeRegion: [p0, p1, ..., pn] (2점 이상, 닫힌 도형으로 취급)
class WorkspaceDrawingEntity {
  const WorkspaceDrawingEntity({
    required this.id,
    required this.type,
    required this.points,
    required this.createdAt,
    required this.updatedAt,
    this.selected = false,
    this.visible = true,
    this.metadata = const {},
  });

  final int id;
  final WorkspaceDrawingType type;
  final List<Point2> points;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool selected;
  final bool visible;

  /// 향후 확장(예: 색상/두께/라벨)을 위한 자리 — 이번 WO에서는 채우지 않는다.
  final Map<String, Object?> metadata;

  /// circle 타입 전용 — center와 edgePoint 사이 거리(정규화 좌표 기준).
  double get circleRadius {
    assert(type == WorkspaceDrawingType.circle && points.length == 2);
    return _distance(points[0], points[1]);
  }

  Point2 get circleCenter {
    assert(type == WorkspaceDrawingType.circle);
    return points[0];
  }

  WorkspaceDrawingEntity copyWith({
    List<Point2>? points,
    bool? selected,
    bool? visible,
    DateTime? updatedAt,
  }) {
    return WorkspaceDrawingEntity(
      id: id,
      type: type,
      points: points ?? this.points,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      selected: selected ?? this.selected,
      visible: visible ?? this.visible,
      metadata: metadata,
    );
  }

  /// 이 도형이 문서 좌표 [p]를 포함/근접하는지(선택 hit-test, §6).
  /// [toleranceNormalized]는 화면 zoom과 무관한 문서 좌표 기준 허용
  /// 오차 — 호출부가 현재 화면 배율에 맞춰 "화면상 일정 픽셀"이 되도록
  /// 역산해서 넘긴다(그래야 확대해도 판정 두께가 항상 같은 손가락 굵기로
  /// 보인다).
  bool hitTest(Point2 p, {required double toleranceNormalized}) {
    switch (type) {
      case WorkspaceDrawingType.line:
        return _distanceToSegment(p, points[0], points[1]) <= toleranceNormalized;
      case WorkspaceDrawingType.curve:
        return _distanceToQuadraticBezier(p, points[0], points[1], points[2]) <= toleranceNormalized;
      case WorkspaceDrawingType.circle:
        final d = _distance(p, circleCenter);
        return d <= circleRadius + toleranceNormalized;
      case WorkspaceDrawingType.freeRegion:
        if (points.length < 3) {
          // 아직 닫히지 않은(점 2개 이하) 자유영역은 선분으로만 판정한다.
          return points.length == 2 && _distanceToSegment(p, points[0], points[1]) <= toleranceNormalized;
        }
        return _pointInPolygon(p, points) || _distanceToPolygonEdge(p, points) <= toleranceNormalized;
    }
  }
}

double _distance(Point2 a, Point2 b) {
  final dx = a.x - b.x;
  final dy = a.y - b.y;
  return math.sqrt(dx * dx + dy * dy);
}

double _distanceToSegment(Point2 p, Point2 a, Point2 b) {
  final abx = b.x - a.x;
  final aby = b.y - a.y;
  final lenSq = abx * abx + aby * aby;
  if (lenSq == 0) return _distance(p, a);
  final t = (((p.x - a.x) * abx + (p.y - a.y) * aby) / lenSq).clamp(0.0, 1.0);
  final projX = a.x + t * abx;
  final projY = a.y + t * aby;
  return _distance(p, Point2(projX, projY));
}

/// 2차 베지어 곡선을 [samples]개 선분으로 근사해 최단 거리를 구한다 —
/// 정확한 해석적 최근접점 계산 대신, 이 정도 샘플링으로도 손가락 히트
/// 테스트 목적에는 충분히 정확하다(§8 — 실제 curve geometry 저장/판정,
/// fake 구현 아님).
double _distanceToQuadraticBezier(Point2 p, Point2 start, Point2 control, Point2 end, {int samples = 24}) {
  Point2 bezierAt(double t) {
    final mt = 1 - t;
    final x = mt * mt * start.x + 2 * mt * t * control.x + t * t * end.x;
    final y = mt * mt * start.y + 2 * mt * t * control.y + t * t * end.y;
    return Point2(x, y);
  }

  var minDist = double.infinity;
  var prev = bezierAt(0);
  for (var i = 1; i <= samples; i++) {
    final cur = bezierAt(i / samples);
    final d = _distanceToSegment(p, prev, cur);
    if (d < minDist) minDist = d;
    prev = cur;
  }
  return minDist;
}

/// 표준 ray-casting 알고리즘 — [CadRoom.containsPoint](cad_floor_plan.dart)와
/// 동일한 방식을 재사용한다(중복 로직을 새로 발명하지 않는다).
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

double _distanceToPolygonEdge(Point2 p, List<Point2> polygon) {
  var minDist = double.infinity;
  for (var i = 0; i < polygon.length; i++) {
    final a = polygon[i];
    final b = polygon[(i + 1) % polygon.length];
    final d = _distanceToSegment(p, a, b);
    if (d < minDist) minDist = d;
  }
  return minDist;
}
