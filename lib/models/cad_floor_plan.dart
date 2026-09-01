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

/// 사용자가 도면에서 두 점을 고르고 실제 길이(mm)를 입력해 만든 기준
/// 축척. 언제든 다시 설정할 수 있고, 재설정되면 이 값을 참조하는 모든
/// 실측값이 자동으로 다시 계산된다(따로 캐시하지 않기 때문 — WO 9번).
@immutable
class FloorPlanScale {
  const FloorPlanScale({
    required this.mmPerPixel,
    required this.referenceStart,
    required this.referenceEnd,
    required this.referenceLengthMm,
  });

  final double mmPerPixel;
  final Point2 referenceStart;
  final Point2 referenceEnd;
  final double referenceLengthMm;
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
