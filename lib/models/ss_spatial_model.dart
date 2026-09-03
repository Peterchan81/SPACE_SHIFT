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
///
/// Vision Guided CAD POC WO — 이 파일은 삭제/재작성하지 않고 호환성을
/// 유지한 채 확장한다. 기존 두 interpreter(space-first/envelope-first,
/// 순수 픽셀 evidence만 봄)는 이 확장 필드들을 채우지 않아도 그대로
/// 컴파일/동작한다(전부 기본값이 있는 optional 필드다) — 오직 새
/// Vision-guided 경로만 이 필드들을 실제로 채운다.
/// - [SSSpace]/[SSBoundary]/[SSWall]/[SSOpening]에 [SSEntitySource]
///   (vision/geometry/ocr/user/validated)와 reviewNeeded/reviewReasons를
///   추가해, "이 값이 어디서 왔고 사람이 다시 봐야 하는가"를 표현한다.
/// - [SSStructuralElement](계단/엘리베이터/기둥/샤프트/void) 신규 추가 —
///   이전에는 검출기가 없어 비워 뒀던 자리를 이제 채운다.
/// - [SSDimension] 신규 추가 — [ScaleSource.drawingDimension](여태
///   파서가 없어 미구현이던 값)의 첫 실제 데이터 통로.
/// - [SSSpatialModel.floorDomain] — 건물 외곽 polygon을 명시적으로
///   노출한다(이전에는 envelope-first 내부 계산에만 존재하고 밖으로
///   드러나지 않았다).

/// [SSSpace]가 실제 사용 가능한 건축 공간이라는 판단의 근거 강도.
enum SSSpaceConfidence { high, medium, low, unknown }

/// Vision Guided CAD POC WO — 이 값이 어디서 만들어졌는지. 기존 두
/// interpreter(순수 픽셀 evidence)가 만드는 모든 entity는 기본값
/// [SSEntitySource.geometry]를 그대로 쓴다(그 값 자체가 이미
/// "픽셀/geometry 검출로 얻었다"는 뜻과 정확히 일치하므로 마이그레이션이
/// 필요 없다).
enum SSEntitySource { vision, geometry, ocr, user, validated }

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
    this.source = SSEntitySource.geometry,
    this.reviewNeeded = false,
    this.reviewReasons = const [],
    this.label,
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

  /// Vision Guided CAD POC WO — 이 SPACE가 어떤 경로로 확정됐는지.
  final SSEntitySource source;

  /// true면 Vision/Geometry가 서로 충돌했거나(CASE D) Vision만 있고
  /// geometry 근거가 없는 등(CASE E) 자동으로 확정하지 않고 사람이
  /// 다시 봐야 하는 상태다 — 이 값이 true인 동안은 이 SPACE를 최종
  /// 확정 CAD로 그대로 신뢰하지 않는다.
  final bool reviewNeeded;

  /// [reviewNeeded]가 true인 이유(정직하게 남긴다, 자동으로 고치지 않는다).
  final List<String> reviewReasons;

  /// Vision Guided CAD POC WO — 도면에 실제로 쓰인 이름(Vision이 읽었거나
  /// 사용자가 지정한 경우). 없으면 null — [CadRoom.name]과 동일하게
  /// "이름 없으면 '공간 N'으로 보여준다"는 원칙을 따른다(거짓 이름을
  /// 지어내지 않는다).
  final String? label;

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
    SSEntitySource? source,
    bool? reviewNeeded,
    List<String>? reviewReasons,
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
      source: source ?? this.source,
      reviewNeeded: reviewNeeded ?? this.reviewNeeded,
      reviewReasons: reviewReasons ?? this.reviewReasons,
      label: label,
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
    this.source = SSEntitySource.geometry,
    this.reviewNeeded = false,
    this.reviewReasons = const [],
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

  final SSEntitySource source;
  final bool reviewNeeded;
  final List<String> reviewReasons;
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
    this.source = SSEntitySource.geometry,
    this.reviewNeeded = false,
    this.reviewReasons = const [],
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

  final SSEntitySource source;
  final bool reviewNeeded;
  final List<String> reviewReasons;
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
    this.source = SSEntitySource.geometry,
    this.reviewNeeded = false,
    this.reviewReasons = const [],
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

  final SSEntitySource source;
  final bool reviewNeeded;
  final List<String> reviewReasons;
}

/// [SSSpace]로 인정되지 않은 닫힌 영역 — 가구/설비로 보이는 후보.
///
/// "닫힌 사각형 = 방"이 아니라는 원칙(WO 5번)에 따라 최종 공간 목록에서
/// 제외된 evidence를 버리지 않고 별도 의미 객체로 보존한다(WO 11번 —
/// 가구/설비/문자/치수는 각각 분리된 의미 객체).
///
/// [furnitureOrEquipment]는 기존 두 interpreter(순수 픽셀 evidence만
/// 봐서 구체적인 가구 종류를 구분할 근거가 없음)가 계속 쓰는 값이다 —
/// 하위 호환을 위해 삭제하지 않는다. Vision Guided CAD POC WO — Vision이
/// 실제로 종류를 지목한 경우에만 구체적인 값(bed/sofa/... )을 쓴다.
enum SSObjectKind {
  furnitureOrEquipment,
  bed,
  sofa,
  cabinet,
  sink,
  toilet,
  bathtub,
  equipment,
  unknown,
}

@immutable
class SSObjectCandidate {
  const SSObjectCandidate({
    required this.id,
    required this.polygon,
    required this.kind,
    this.containingSpaceId,
    this.source = SSEntitySource.geometry,
    this.reviewNeeded = false,
    this.reviewReasons = const [],
  });

  final String id;
  final List<Point2> polygon;
  final SSObjectKind kind;

  /// 이 후보를 둘러싼 [SSSpace]의 id(찾았으면).
  final String? containingSpaceId;

  final SSEntitySource source;
  final bool reviewNeeded;
  final List<String> reviewReasons;
}

/// Vision Guided CAD POC WO — 계단/엘리베이터/기둥/샤프트/void 등 구조
/// 요소. 이전에는 검출기가 없어 자리만 비워 뒀던 항목이다.
enum SSStructuralKind { stair, elevator, column, shaft, voidSpace }

@immutable
class SSStructuralElement {
  const SSStructuralElement({
    required this.id,
    required this.kind,
    required this.polygon,
    required this.confidence,
    this.source = SSEntitySource.geometry,
    this.reviewNeeded = false,
    this.reviewReasons = const [],
  });

  final String id;
  final SSStructuralKind kind;
  final List<Point2> polygon;
  final double confidence;
  final SSEntitySource source;
  final bool reviewNeeded;
  final List<String> reviewReasons;
}

/// Vision Guided CAD POC WO — 도면에 실제로 인쇄된 치수 텍스트 하나.
/// [parsedValueMm]은 그 텍스트를 실제로 숫자로 읽어냈을 때만 채운다 —
/// 이 파이프라인의 어떤 단계도 이 값을 임의로 만들어내지 않는다(WO
/// 절대 금지 4/5번). null이면 "치수 텍스트가 있는 것은 확인했지만
/// 아직 파싱하지 못했다"는 뜻이고, 여전히 [ScaleSource.unknown] 상태를
/// 유지해야 한다.
@immutable
class SSDimension {
  const SSDimension({
    required this.id,
    required this.rawText,
    this.parsedValueMm,
    this.appliesToBoundaryId,
    this.confidence = SSSpaceConfidence.unknown,
    this.source = SSEntitySource.ocr,
  });

  final String id;
  final String rawText;
  final double? parsedValueMm;
  final String? appliesToBoundaryId;
  final SSSpaceConfidence confidence;
  final SSEntitySource source;
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
    this.structuralElements = const [],
    this.dimensions = const [],
    this.floorDomain,
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

  /// Vision Guided CAD POC WO — 계단/엘리베이터/기둥/샤프트/void.
  final List<SSStructuralElement> structuralElements;

  /// Vision Guided CAD POC WO — 도면에 실제로 인쇄된 치수 텍스트들.
  /// 비어 있으면(기본값) "이 도면에서 치수를 찾지 못했다"는 뜻이고,
  /// 이 경우 화면은 축척을 항상 미확정으로 유지해야 한다.
  final List<SSDimension> dimensions;

  /// Vision Guided CAD POC WO — 건물 외곽(Envelope) polygon을 명시적으로
  /// 노출한다. null이면(기존 두 interpreter 경로) 화면이 walls/spaces의
  /// 합집합으로 외곽을 유추해야 한다는 뜻 — 이 필드가 있으면 그럴
  /// 필요 없이 바로 쓸 수 있다.
  final List<Point2>? floorDomain;

  /// "가구/설비로 보이는 N개 후보를 공간에서 제외했습니다" 같은, 해석
  /// 과정에서 사용자가 알아야 할 안내 메시지.
  final List<String> warnings;
}
