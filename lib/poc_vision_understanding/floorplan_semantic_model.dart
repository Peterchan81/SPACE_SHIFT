/// SPACE SHIFT — Vision-style Floorplan Understanding POC.
///
/// 독립 POC 전용 모델이다 — 기존 SS CAD 엔진(floor_plan_analysis_engine/
/// architectural_drawing_interpreter/envelope_first_interpreter 등)과
/// 완전히 분리돼 있고, 어떤 파일도 서로 import하지 않는다. 이 POC의
/// 목표는 "Otsu → run-length → flood-fill" 같은 픽셀 검출기 없이,
/// 도면 전체를 사람(또는 vision 모델)이 한 번에 보고 이해하는 방식으로
/// 구조화된 건축 의미 데이터를 만들 수 있는가를 검증하는 것이다.
///
/// 좌표는 항상 정규화(0.0~1.0, 도면 전체 bounding box 기준) 좌표다 —
/// 축척이 확정되지 않았으므로 mm 값을 만들지 않는다(WO 지시 5번 "축척
/// 미확정 유지").
library;

class Pt {
  const Pt(this.x, this.y);
  final double x;
  final double y;
}

/// 이 구조 데이터를 어떻게 얻었는지 — POC 단계에서는 항상 "사람/vision
/// 모델이 도면 전체를 보고 직접 판단"(manualVisionReading)이다. 향후
/// 자동화된 VLM 호출로 교체되면 값만 바뀐다(스키마는 그대로).
enum UnderstandingSource { manualVisionReading, automatedVlm }

enum BoundaryType { exteriorWall, interiorWall, virtual, unknown }

enum OpeningKind { door, window, openPassage }

enum StructuralObjectKind { stair, elevator, shaft, column }

enum NonStructuralObjectKind { furniture, fixture, annotation }

class SemanticSpace {
  const SemanticSpace({
    required this.id,
    required this.name,
    required this.polygon,
    required this.confidence,
  });

  final String id;

  /// 도면에 실제로 쓰인 글자를 그대로 옮긴 이름(있으면) — 없으면 null,
  /// 화면은 "공간 N"으로 표시한다(기존 SS의 "거짓 이름 단정 금지"
  /// 원칙과 동일).
  final String? name;
  final List<Pt> polygon;

  /// 이 SPACE 판단 자체의 신뢰도(0~1) — 벽 evidence가 약하거나 형태가
  /// 애매한 경우 낮게 매긴다. 가짜로 1.0을 주지 않는다.
  final double confidence;
}

class SemanticBoundary {
  const SemanticBoundary({
    required this.id,
    required this.type,
    required this.geometry,
    this.adjacentSpaceIds = const [],
  });

  final String id;
  final BoundaryType type;
  final List<Pt> geometry;
  final List<String> adjacentSpaceIds;
}

class SemanticOpening {
  const SemanticOpening({
    required this.id,
    required this.kind,
    required this.boundaryId,
    required this.geometry,
  });

  final String id;
  final OpeningKind kind;
  final String boundaryId;
  final Pt geometry;
}

class SemanticStructuralObject {
  const SemanticStructuralObject({
    required this.id,
    required this.kind,
    required this.polygon,
  });

  final String id;
  final StructuralObjectKind kind;
  final List<Pt> polygon;
}

class SemanticNonStructuralObject {
  const SemanticNonStructuralObject({
    required this.id,
    required this.kind,
    required this.polygon,
    this.containingSpaceId,
  });

  final String id;
  final NonStructuralObjectKind kind;
  final List<Pt> polygon;
  final String? containingSpaceId;
}

/// 도면 한 장을 이해한 결과 전체 — Building/FloorDomain 하나에 대응한다
/// (이번 POC는 단층 평면도 한 장만 다룬다).
class FloorplanUnderstanding {
  const FloorplanUnderstanding({
    required this.source,
    required this.floorDomain,
    required this.spaces,
    required this.boundaries,
    required this.openings,
    required this.structuralObjects,
    required this.nonStructuralObjects,
    required this.scaleConfirmed,
    this.notes = const [],
  });

  final UnderstandingSource source;

  /// 건물 외곽(Envelope) 폴리곤 — 비정형/대각/돌출을 그대로 보존한다.
  final List<Pt> floorDomain;
  final List<SemanticSpace> spaces;
  final List<SemanticBoundary> boundaries;
  final List<SemanticOpening> openings;
  final List<SemanticStructuralObject> structuralObjects;
  final List<SemanticNonStructuralObject> nonStructuralObjects;

  /// false면 화면이 "축척 미확정"을 표시하고 ㎡/평 등 확정값을 만들지
  /// 않는다(WO 지시 5번). 원본 도면에 실측 치수 텍스트가 있어도, 이
  /// POC는 그 텍스트를 자동으로 검증(OCR)하지 않으므로 항상 false다.
  final bool scaleConfirmed;

  /// 이해 과정에서 사람이 남긴 불확실성 메모(가짜로 확정 처리하지
  /// 않기 위해) — 예: "우측 상단 돌출부 정확한 꺾임 위치는 근사치".
  final List<String> notes;
}
