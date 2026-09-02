import 'package:flutter/foundation.dart';

import 'floor_plan_geometry.dart';

/// SS 건축도면 이해 엔진 V1 — "SS 표준 공간모델(SSSpatialModel)".
///
/// PC2 재작업 WO — 기존 pipeline은 검출기(Otsu/run-length/flood-fill)의
/// 출력을 그대로 최종 CAD로 썼다("detector → 바로 CAD"). 그 결과 굵기/
/// 길이만으로 벽을 판단하다 보니, 벽과 비슷한 두께로 그려진 가구/설비
/// 외곽선이 실제 벽처럼 인식되어 방을 잘못 쪼개는 문제가 반복됐다.
///
/// 이 파일이 정의하는 [SSSpatialModel]은 검출기 출력([WallSegment]/
/// [OpeningCandidate]/[RoomCandidate] — 이제부터 "evidence"라고 부른다)과
/// 최종 CAD 사이에 새로 끼워 넣는 "해석(interpretation)" 계층이다.
/// [SSSpatialModelBuilder](ss_spatial_model_builder.dart)가 evidence를
/// 입력받아, "닫힌 사각형을 전부 방으로 본다"가 아니라 "사람이 사용/
/// 이동할 수 있는 건축 공간인가?"를 판단해 [SSSpace](진짜 공간)와
/// [SSObjectCandidate](가구/설비로 보이는 후보)를 구분하고, 공간 간
/// 인접/출입 관계까지 만든다.
///
/// 아직 만들지 않은 것(가짜로 흉내내지 않는다, 향후 과제로 남겨 둠):
/// - Project/Storey(다층 건물) — 이번 분석은 한 장의 평면도(단일 층)만
///   다루므로 지금 이 구조를 추가해도 항상 비어 있는 껍데기일 뿐이다.
/// - StructuralElements(기둥/샤프트/계단), Annotations(치수/문자/기호)
///   — 이들을 실제로 검출하는 로직이 아직 없다. 검출기가 생기면 그때
///   이 모델에 필드로 추가한다.

/// [SSSpace]가 실제 사용 가능한 건축 공간이라는 판단의 근거 강도.
enum SSSpaceConfidence { high, medium, low }

/// 도면에서 파악된 "건축적으로 사용되는 공간" 하나.
///
/// 반드시 용도(침실/거실 등)를 알아야 하는 것은 아니다 — 이름이 없으면
/// 화면이 "공간 N"으로 보여준다(기존 [RoomCandidate]/[CadRoom]과 같은
/// 원칙, WO 4번).
@immutable
class SSSpace {
  const SSSpace({
    required this.id,
    required this.polygon,
    required this.areaNormalized,
    required this.closed,
    required this.confidence,
    this.spaceConfidence = SSSpaceConfidence.high,
    this.adjacentSpaceIds = const [],
    this.boundaryOpeningIds = const [],
    this.boundaryIds = const [],
    this.containedObjectIds = const [],
  });

  final String id;
  final List<Point2> polygon;
  final double areaNormalized;

  /// 이미지 경계에 닿지 않고 완전히 경계로 둘러싸였는지.
  final bool closed;

  /// 원래 flood-fill 후보의 채움 비율 기반 신뢰도(기존 [RoomCandidate.confidence]
  /// 그대로 승계) — 형태 신뢰도.
  final double confidence;

  /// "이 닫힌 영역이 가구/설비 섬이 아니라 진짜 독립 공간이다"라는
  /// 판단 자체의 신뢰도 — 형태 신뢰도([confidence])와는 다른 축이다.
  final SSSpaceConfidence spaceConfidence;

  /// 경계(주로 내벽)를 공유하는 다른 공간의 id 목록.
  final List<String> adjacentSpaceIds;

  /// 이 공간 경계에 붙어 있는 [SSOpening]의 id 목록(문/창/통로).
  final List<String> boundaryOpeningIds;

  /// Space-first 재작업 WO — 이 공간의 폴리곤 변을 하나씩 해석한
  /// [SSBoundary] id 목록(벽/문/창/열린통로/기둥/가상/미상). 벽
  /// evidence가 없는 구간도 빠뜨리지 않는다는 게 [boundaryOpeningIds]/
  /// 기존 벽 목록과의 핵심 차이다.
  final List<String> boundaryIds;

  /// 이 공간 내부에 있는 [SSObjectCandidate](가구/설비) id 목록.
  final List<String> containedObjectIds;

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

  SSSpace copyWith({
    List<String>? adjacentSpaceIds,
    List<String>? boundaryOpeningIds,
    List<String>? boundaryIds,
    List<String>? containedObjectIds,
  }) {
    return SSSpace(
      id: id,
      polygon: polygon,
      areaNormalized: areaNormalized,
      closed: closed,
      confidence: confidence,
      spaceConfidence: spaceConfidence,
      adjacentSpaceIds: adjacentSpaceIds ?? this.adjacentSpaceIds,
      boundaryOpeningIds: boundaryOpeningIds ?? this.boundaryOpeningIds,
      boundaryIds: boundaryIds ?? this.boundaryIds,
      containedObjectIds: containedObjectIds ?? this.containedObjectIds,
    );
  }
}

/// Space-first 재작업 WO — [SSSpace] 경계 한 구간의 건축적 의미. 폴리곤
/// 변 하나가 항상 벽인 것은 아니다(WO 지시 6번) — 벽 evidence가 있으면
/// wall, 문/창 evidence가 있으면 door/window, 벽 없이 다른 SPACE와
/// 맞닿아 있으면 virtual(열린 경계), 그마저 없으면 unknown으로 정직하게
/// 남긴다.
enum SSBoundaryType { wall, door, window, openPassage, column, virtual, unknown }

@immutable
class SSBoundary {
  const SSBoundary({
    required this.id,
    required this.spaceId,
    required this.start,
    required this.end,
    required this.type,
    required this.confidence,
    this.oppositeSpaceId,
    this.isExterior = false,
    this.wallId,
    this.openingId,
  });

  final String id;

  /// 이 경계가 속한 [SSSpace]의 id.
  final String spaceId;
  final Point2 start;
  final Point2 end;
  final SSBoundaryType type;
  final double confidence;

  /// 이 경계 반대편의 다른 [SSSpace] id(있으면 — 두 공간을 나눈다는 뜻).
  final String? oppositeSpaceId;

  /// 반대편이 건물 바깥(다른 SPACE가 아님)인지.
  final bool isExterior;

  /// 이 경계의 근거가 된 [SSWall]/[SSOpening] id(있으면).
  final String? wallId;
  final String? openingId;
}

/// [SSWall]이 건물 외곽을 이루는지, 공간을 나누는 내부 경계인지.
enum SSWallKind { exterior, interior }

/// 공간을 둘러싸거나 나누는 건축 경계 하나. 기존 [WallSegment] evidence를
/// 그대로 감싸되, "이 벽이 실제로 어느 두 공간을 나누는가"([separatesSpaceIds])
/// 관계를 더한다 — 벽을 "선"이 아니라 "공간 사이의 경계"로 취급한다는
/// 원칙(WO 6번)의 핵심 데이터다.
@immutable
class SSWall {
  const SSWall({
    required this.id,
    required this.start,
    required this.end,
    required this.thicknessNormalized,
    required this.kind,
    required this.confidence,
    this.separatesSpaceIds = const [],
  });

  final String id;
  final Point2 start;
  final Point2 end;
  final double thicknessNormalized;
  final SSWallKind kind;
  final double confidence;

  /// 이 벽 양쪽에서 실제로 검출된 공간 id — 0개(양쪽 다 공간 밖/미검출),
  /// 1개(외벽처럼 한쪽만 공간), 2개(두 공간을 나누는 내벽)일 수 있다.
  final List<String> separatesSpaceIds;
}

/// [SSOpening]의 건축적 의미.
enum SSOpeningKind { door, window, openPassage, unknown }

/// 공간과 공간을(또는 공간과 외부를) 연결하는 개구부. 기존
/// [OpeningCandidate] evidence를 감싸되, "이 문이 실제로 어느 공간들을
/// 연결하는가"([connectsSpaceIds])를 더한다 — 문을 arc 기호가 아니라
/// "공간 간 연결"이라는 의미로 취급한다는 원칙(WO 7번)의 핵심 데이터다.
@immutable
class SSOpening {
  const SSOpening({
    required this.id,
    required this.kind,
    required this.center,
    required this.widthNormalized,
    required this.confidence,
    this.wallId,
    this.connectsSpaceIds = const [],
  });

  final String id;
  final SSOpeningKind kind;
  final Point2 center;
  final double widthNormalized;
  final double confidence;
  final String? wallId;

  /// 이 개구부가 실제로 연결하는 공간 id — 보통 2개(두 공간을 연결)
  /// 이지만, 외벽에 붙은 문/창은 1개(공간 하나만 연결, 반대쪽은 건물
  /// 바깥)일 수 있다.
  final List<String> connectsSpaceIds;
}

/// [SSSpace]로 인정되지 않은 닫힌 영역 — 가구/설비로 보이는 후보.
///
/// "닫힌 사각형 = 방"이 아니라는 원칙(WO 5번)에 따라 최종 공간 목록에서
/// 제외된 evidence를 버리지 않고 별도 의미 객체로 보존한다(WO 11번 —
/// 가구/설비/문자/치수는 각각 분리된 의미 객체). 이번 v1은 실제
/// 가구 종류(침대/책상 등)를 분류하지 않고 [SSObjectKind.furnitureOrEquipment]
/// 하나로만 묶는다 — 종류별 분류기가 없는데 있는 것처럼 흉내내지 않는다.
enum SSObjectKind { furnitureOrEquipment }

@immutable
class SSObjectCandidate {
  const SSObjectCandidate({
    required this.id,
    required this.polygon,
    required this.kind,
    this.containingSpaceId,
  });

  final String id;
  final List<Point2> polygon;
  final SSObjectKind kind;

  /// 이 후보를 둘러싼 [SSSpace]의 id(찾았으면).
  final String? containingSpaceId;
}

/// 평면도 한 장을 해석한 SS 표준 공간모델 전체.
///
/// [SSSpatialModelBuilder.build]의 출력이며, [buildCadFloorPlan]이 이
/// 모델을 화면이 쓰는 [CadFloorPlan]으로 다시 감싼다 — 즉 evidence
/// (검출기 출력)를 최종 CAD가 직접 소비하지 않고, 항상 이 해석 계층을
/// 거친다.
@immutable
class SSSpatialModel {
  const SSSpatialModel({
    required this.sourceWidthPx,
    required this.sourceHeightPx,
    required this.spaces,
    required this.walls,
    required this.openings,
    required this.objects,
    required this.warnings,
    this.boundaries = const [],
  });

  final int sourceWidthPx;
  final int sourceHeightPx;
  final List<SSSpace> spaces;
  final List<SSWall> walls;
  final List<SSOpening> openings;
  final List<SSObjectCandidate> objects;

  /// Space-first 재작업 WO — 모든 공간의 폴리곤 변을 해석한 전체 경계
  /// 목록([SSBoundary], 벽/문/창/열린통로/기둥/가상/미상). [walls]는
  /// "검증된 벽 evidence"만 담는 기존 렌더링용 목록이고, 이 목록은
  /// 그보다 완전하다 — 벽 evidence가 없는 구간도 빠뜨리지 않는다.
  final List<SSBoundary> boundaries;

  /// "가구/설비로 보이는 N개 후보를 공간에서 제외했습니다" 같은, 해석
  /// 과정에서 사용자가 알아야 할 안내 메시지.
  final List<String> warnings;
}
