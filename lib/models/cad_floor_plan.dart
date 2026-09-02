import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'floor_plan_geometry.dart';

/// CAD 벽이 외벽/내벽 중 어느 쪽인지 — 렌더링/작업 생성 시 참고용일 뿐,
/// [WorkspaceTaskCategory]와는 독립된 값이다.
enum CadWallType { exterior, interior }

/// geometry 한 개가 어떻게 만들어졌는지 — 실제 분석 결과인지, 사용자가
/// 도면을 보정한 것인지, 사용자가 새로 그린 것인지 구분한다.
enum CadElementSource { analyzed, userEdited, userCreated }

/// 편집 가능한 CAD 벽 — 실제 분석 엔진(run-length 벽 검출)의 [WallSegment]
/// 결과를 감싸되, 중심선 + 두께 개념으로 명시적으로 분리하고 사용자가
/// 끝점을 옮기거나 삭제할 수 있는 편집 상태([edited]/[source])를 더한다.
///
/// [id]는 분석에서 부여된 geometry id(예: `wall-3`)를 그대로 유지한다 —
/// 사용자가 이 벽으로부터 실제 인테리어 작업을 만들 때 생기는 작업
/// 번호(①②③)와는 완전히 다른 식별자다.
@immutable
class CadWall {
  const CadWall({
    required this.id,
    required this.start,
    required this.end,
    required this.thicknessNormalized,
    required this.wallType,
    required this.confidence,
    this.source = CadElementSource.analyzed,
    this.edited = false,
    this.heightMm,
  });

  final String id;

  /// 벽 중심선의 시작/끝 — 두께는 여기서 수직으로 펼쳐 계산한다.
  final Point2 start;
  final Point2 end;

  /// 벽 두께. 정규화 좌표계와 같은 단위(이미지 대각선 대비 비율)로만
  /// 담는다 — 실제 mm는 [FloorPlanScale]이 확정된 뒤에만 계산한다(WO 9번,
  /// 임의 mm 생성 금지).
  final double thicknessNormalized;

  final CadWallType wallType;
  final double confidence;
  final CadElementSource source;

  /// 사용자가 끝점/두께를 직접 수정했는지 — true면 [confidence] 기반
  /// debug 표시보다 사용자 편집을 우선한다.
  final bool edited;

  /// 벽 높이(mm). 자동 추정하지 않는다(WO 18/천장고 지침) — 항상 null로
  /// 시작하고, 천장고 입력 이후 채워질 자리만 미리 마련해 둔다.
  final double? heightMm;

  Point2 get centerStart => start;
  Point2 get centerEnd => end;
  double get lengthNormalized => start.distanceTo(end);

  /// 두께가 있는 벽을 그리기 위한 4점 폴리곤(중심선 기준 양쪽으로
  /// 두께의 절반만큼 수직 offset) — CAD 렌더링과 hit-test(끝점 편집)가
  /// 모두 이 계산을 재사용한다.
  List<Point2> get boundaryPolygon {
    final dx = end.x - start.x;
    final dy = end.y - start.y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len == 0) {
      return [start, start, start, start];
    }
    final halfThickness = thicknessNormalized / 2;
    final nx = -dy / len * halfThickness;
    final ny = dx / len * halfThickness;
    return [
      Point2(start.x + nx, start.y + ny),
      Point2(end.x + nx, end.y + ny),
      Point2(end.x - nx, end.y - ny),
      Point2(start.x - nx, start.y - ny),
    ];
  }

  CadWall copyWith({
    Point2? start,
    Point2? end,
    double? thicknessNormalized,
    bool? edited,
    CadElementSource? source,
    double? heightMm,
  }) {
    return CadWall(
      id: id,
      start: start ?? this.start,
      end: end ?? this.end,
      thicknessNormalized: thicknessNormalized ?? this.thicknessNormalized,
      wallType: wallType,
      confidence: confidence,
      source: source ?? this.source,
      edited: edited ?? this.edited,
      heightMm: heightMm ?? this.heightMm,
    );
  }
}

/// 편집 가능한 CAD 문/창 후보.
@immutable
class CadOpening {
  const CadOpening({
    required this.id,
    required this.type,
    required this.center,
    required this.widthNormalized,
    required this.confidence,
    this.wallId,
    this.source = CadElementSource.analyzed,
  });

  final String id;
  final OpeningType type;
  final Point2 center;
  final double widthNormalized;
  final double confidence;
  final String? wallId;
  final CadElementSource source;
}

/// 편집 가능한 CAD 공간(방) 후보.
@immutable
class CadRoom {
  const CadRoom({
    required this.id,
    required this.polygon,
    required this.areaNormalized,
    required this.confidence,
    this.closed = true,
    this.source = CadElementSource.analyzed,
  });

  final String id;
  final List<Point2> polygon;
  final double areaNormalized;
  final double confidence;
  final bool closed;
  final CadElementSource source;

  bool containsPoint(Point2 p) {
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final a = polygon[i];
      final b = polygon[j];
      final intersects =
          ((a.y > p.y) != (b.y > p.y)) &&
          (p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x);
      if (intersects) inside = !inside;
    }
    return inside;
  }
}

/// [FloorPlanScale]이 실제로 어떻게 얻어졌는지 — 화면이 "실측값"과
/// "대략적인 추정값"을 절대 같은 것처럼 보여주지 않기 위한 구분이다(2D
/// 단순화 WO — 5번 "하나의 고정 숫자를 실측값으로 취급하지 않는다").
enum ScaleSource {
  /// 사용자가 "치수 보정"에서 두 점 + 실제 길이(mm)를 직접 입력함.
  measured,

  /// 도면 자체에 있는 치수 텍스트/치수선에서 읽어냄. 이번 1차 구현에는
  /// 그런 파서가 없어 아직 실제로 만들어지지 않는다 — 향후 과제로만
  /// 자리를 남겨 둔다.
  drawingDimension,

  /// 문 gap 폭(널리 쓰이는 표준 문 폭 가정)으로부터 역산함 — "실측"이
  /// 아니라 "추정"임을 항상 함께 표시해야 한다.
  estimatedFromDoor,

  /// 실측도 추정도 불가능해, 3D를 일단 보여주기 위한 임의 기준 축척.
  /// 실제 크기와 무관할 수 있다는 점을 반드시 사용자에게 알려야 한다.
  unknown,
}

extension ScaleSourceX on ScaleSource {
  bool get isReliable =>
      this == ScaleSource.measured || this == ScaleSource.drawingDimension;

  String get label => switch (this) {
    ScaleSource.measured => '직접 입력한 실측값',
    ScaleSource.drawingDimension => '도면 치수 표기',
    ScaleSource.estimatedFromDoor => '문 크기 기준 추정값',
    ScaleSource.unknown => '크기를 추정할 수 없음(임시 기준)',
  };
}

/// 도면의 실제 크기를 아는 유일한 값 — 사용자가 도면에서 두 점을 고르고
/// 실제 길이(mm)를 입력해 만들거나([ScaleSource.measured]), 문 폭 등으로
/// 자동 추정한다([ScaleSource.estimatedFromDoor]). 언제든 다시 설정할 수
/// 있고, 재설정되면 이 값을 참조하는 모든 실측값이 자동으로 다시
/// 계산된다(따로 캐시하지 않기 때문 — WO 9번).
@immutable
class FloorPlanScale {
  const FloorPlanScale({
    required this.mmPerPixel,
    required this.referenceStart,
    required this.referenceEnd,
    required this.referenceLengthMm,
    this.source = ScaleSource.measured,
  });

  final double mmPerPixel;
  final Point2 referenceStart;
  final Point2 referenceEnd;
  final double referenceLengthMm;

  final ScaleSource source;
}

/// 일반적으로 쓰이는 실내 여닫이문(단짝문) 폭 — 문 gap을 실제 치수로
/// 역산할 때만 쓰는 내부 추정 기준이다. 실측값이 아니므로 이 값으로
/// 계산한 [FloorPlanScale]은 항상 [ScaleSource.estimatedFromDoor]로
/// 표시한다(2D 단순화 WO — 5번).
const double kAssumedDoorWidthMm = 900;

/// 문 후보(gap 폭 기반, 항상 [FloorPlanObjectStatus.needsReview])로부터
/// 축척을 추정한다. 가장 신뢰도가 높은 문 하나를 골라 [kAssumedDoorWidthMm]
/// 로 역산한다 — 여러 문의 평균을 내지 않는 이유는, 서로 다른 신뢰도의
/// 후보를 섞으면 어느 쪽이 실제로 얼마나 기여했는지 사용자에게 설명할 수
/// 없기 때문이다(단순하고 설명 가능한 쪽을 택함).
///
/// 문 후보가 하나도 없거나, 있어도 폭을 계산할 수 없으면(0 이하) null —
/// 호출부는 이 경우 [ScaleSource.unknown] 폴백으로 넘어가야 한다(4번:
/// "정확한 치수인 것처럼 거짓 값을 만들지 않는다").
FloorPlanScale? estimateScaleFromDoors(CadFloorPlan plan) {
  final doors = plan.openings.where((o) => o.type == OpeningType.door);
  if (doors.isEmpty) return null;

  CadOpening best = doors.first;
  for (final door in doors) {
    if (door.confidence > best.confidence) best = door;
  }

  final widthPx = best.widthNormalized * plan.diagonalPx;
  if (widthPx <= 0) return null;

  return FloorPlanScale(
    mmPerPixel: kAssumedDoorWidthMm / widthPx,
    referenceStart: best.center,
    referenceEnd: best.center,
    referenceLengthMm: kAssumedDoorWidthMm,
    source: ScaleSource.estimatedFromDoor,
  );
}

/// 실측도 문 기준 추정도 불가능할 때 3D 생성을 막지 않기 위한 마지막
/// 폴백 — 도면 전체 대각선이 "일반적인 작은 주거 공간" 정도의 실제
/// 크기([kUnknownScaleFallbackDiagonalMm])라고 가정한다. 절대 실측값처럼
/// 보이면 안 되므로 [ScaleSource.unknown]으로만 만들어진다 — 화면은 이
/// source를 보고 "크기를 추정할 수 없습니다" 같은 명시적 경고를 반드시
/// 함께 보여줘야 한다(4번).
const double kUnknownScaleFallbackDiagonalMm = 8000;

FloorPlanScale unknownFallbackScale(CadFloorPlan plan) {
  final diagonalPx = plan.diagonalPx;
  final mmPerPixel = diagonalPx > 0
      ? kUnknownScaleFallbackDiagonalMm / diagonalPx
      : 1.0;
  return FloorPlanScale(
    mmPerPixel: mmPerPixel,
    referenceStart: const Point2(0, 0),
    referenceEnd: const Point2(1, 1),
    referenceLengthMm: kUnknownScaleFallbackDiagonalMm,
    source: ScaleSource.unknown,
  );
}

/// 평면도 분석 직후 자동으로 적용할 축척을 우선순위(WO 4번 A→B→C)대로
/// 결정한다. [existing]이 이미 있으면(사용자가 직접 보정했거나 이전
/// 분석에서 이미 추정됨) 절대 덮어쓰지 않는다 — 자동 추정은 오직 "아직
/// 축척이 전혀 없을 때"만 적용된다.
///
/// A(도면 자체 치수 텍스트)는 이번 1차 구현에 해당 파서가 없어 시도하지
/// 않는다 — 없는 기능을 있는 것처럼 흉내내지 않는다.
FloorPlanScale resolveAutoScale(CadFloorPlan plan, FloorPlanScale? existing) {
  if (existing != null) return existing;
  return estimateScaleFromDoors(plan) ?? unknownFallbackScale(plan);
}

/// 천장고 설정 — 자동 추정하지 않고 사용자 입력만 반영한다(WO 10번).
/// 이번 단계는 전체 기본값만 입력받지만, 공간별 override를 나중에 붙일
/// 수 있도록 데이터 구조를 미리 준비해 둔다(이번 범위는 UI 없음).
@immutable
class CeilingHeightSettings {
  const CeilingHeightSettings({
    required this.defaultHeightMm,
    this.perRoomOverridesMm = const {},
  });

  final double defaultHeightMm;

  /// room id → 그 공간만의 override 높이(mm). 비어 있으면 전부 기본값을
  /// 쓴다.
  final Map<String, double> perRoomOverridesMm;

  double heightForRoom(String roomId) =>
      perRoomOverridesMm[roomId] ?? defaultHeightMm;
}

/// 평면도 한 장의 편집 가능한 CAD geometry 전체.
@immutable
class CadFloorPlan {
  const CadFloorPlan({
    required this.sourceWidthPx,
    required this.sourceHeightPx,
    required this.walls,
    required this.openings,
    required this.rooms,
    required this.warnings,
  });

  final int sourceWidthPx;
  final int sourceHeightPx;
  final List<CadWall> walls;
  final List<CadOpening> openings;
  final List<CadRoom> rooms;
  final List<String> warnings;

  double get diagonalPx => math.sqrt(
    sourceWidthPx * sourceWidthPx + sourceHeightPx * sourceHeightPx,
  );

  double pixelDistance(Point2 start, Point2 end) {
    final dx = (end.x - start.x) * sourceWidthPx;
    final dy = (end.y - start.y) * sourceHeightPx;
    return math.sqrt(dx * dx + dy * dy);
  }

  double? realMmBetween(Point2 start, Point2 end, FloorPlanScale? scale) {
    if (scale == null) return null;
    return pixelDistance(start, end) * scale.mmPerPixel;
  }

  /// [scale]이 없으면 null — 실제 mm 값을 임의로 추정하지 않는다(WO 9번).
  double? realMmForNormalizedLength(
    double normalizedLength,
    FloorPlanScale? scale,
  ) {
    if (scale == null) return null;
    return normalizedLength * diagonalPx * scale.mmPerPixel;
  }

  CadFloorPlan copyWithWalls(List<CadWall> walls) {
    return CadFloorPlan(
      sourceWidthPx: sourceWidthPx,
      sourceHeightPx: sourceHeightPx,
      walls: walls,
      openings: openings,
      rooms: rooms,
      warnings: warnings,
    );
  }
}

/// 실제 분석 엔진 결과([FloorPlanAnalysisResult])를 편집 가능한 CAD
/// geometry로 옮긴다 — 좌표/두께/신뢰도를 새로 만들어내지 않고 그대로
/// 감싸기만 한다(WO 15번: 기존 분석 엔진을 CAD 변환의 입력으로 재사용).
CadFloorPlan buildCadFloorPlan(FloorPlanAnalysisResult result) {
  return CadFloorPlan(
    sourceWidthPx: result.sourceWidthPx,
    sourceHeightPx: result.sourceHeightPx,
    walls: [
      for (final wall in result.walls)
        CadWall(
          id: wall.id,
          start: wall.start,
          end: wall.end,
          thicknessNormalized: wall.thicknessNormalized,
          wallType: wall.isExterior
              ? CadWallType.exterior
              : CadWallType.interior,
          confidence: wall.confidence,
        ),
    ],
    openings: [
      for (final opening in result.openings)
        CadOpening(
          id: opening.id,
          type: opening.type,
          center: opening.center,
          widthNormalized: opening.widthNormalized,
          confidence: opening.confidence,
          wallId: opening.wallId,
        ),
    ],
    rooms: [
      for (final room in result.rooms)
        CadRoom(
          id: room.id,
          polygon: room.polygon,
          areaNormalized: room.areaNormalized,
          confidence: room.confidence,
          closed: room.closed,
        ),
    ],
    warnings: result.warnings,
  );
}
