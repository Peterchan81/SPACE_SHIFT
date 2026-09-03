import 'package:flutter/foundation.dart';

/// SPACE SHIFT — Vision Guided CAD POC 1단계.
///
/// Vision(예: Claude Vision) 한 번의 분석 결과를 담는 계약(schema)이다.
/// 설계 문서(Vision → SS Spatial Model → CAD 파이프라인)의 3번 항목을
/// 그대로 코드로 옮긴다.
///
/// 핵심 원칙(반드시 지킨다):
/// - 모든 좌표는 이미지 전체 기준 0.0~1.0 정규화 좌표다. mm/픽셀 절대
///   좌표를 담지 않는다 — Vision은 실제 축척을 알 수 없다.
/// - 모든 entity는 [VisionConfidence]/[VisionSource]를 반드시 가진다 —
///   confidence 없이 값을 확정처럼 쓰지 않는다는 이 프로젝트 전체
///   원칙을 이 스키마 레벨에서 강제한다.
/// - 이 파일의 타입은 "Vision이 무엇이라고 말했는가"만 담는다. 실제
///   벽 좌표를 정밀화하는 것은 [HintedGeometryExtractor]의 역할이고,
///   최종 확정은 [SSSpatialModel]의 역할이다 — 이 계층이 그 둘을
///   대신하지 않는다.
enum VisionConfidence { high, medium, low, unknown }

enum VisionSource { vision, geometry, ocr, user, validated }

enum VisionEntityType {
  floorDomain,
  space,
  boundary,
  opening,
  object,
  structuralElement,
  dimension,
}

enum VisionSpaceSemanticType {
  bedroomMaster,
  bedroom,
  living,
  kitchen,
  bathroom,
  entrance,
  utility,
  pantry,
  balcony,
  mechanicalRoom,
  corridor,
  unknown,
}

enum VisionBoundaryType { exteriorWall, interiorWall, virtualBoundary, unknown }

enum VisionOpeningType { door, window, openPassage }

enum VisionObjectType { bed, sofa, cabinet, sink, toilet, bathtub, equipment, unknown }

enum VisionStructuralType { stair, elevator, column, shaft, void_ }

/// 정규화 좌표 한 점 — 이미지 전체(0,0)~(1,1) 기준. 약간의 오버슈트
/// (예: -0.02, 1.03)는 hint 오차로 허용하되, 명백히 범위를 벗어난
/// 값(예: 5.0)은 [isPlausible]로 걸러낼 수 있게 한다.
@immutable
class NormalizedPoint {
  const NormalizedPoint(this.x, this.y);

  final double x;
  final double y;

  bool get isPlausible => x.isFinite && y.isFinite && x > -0.2 && x < 1.2 && y > -0.2 && y < 1.2;

  Map<String, dynamic> toJson() => {'x': x, 'y': y};

  factory NormalizedPoint.fromJson(Map<String, dynamic> json) =>
      NormalizedPoint((json['x'] as num).toDouble(), (json['y'] as num).toDouble());
}

enum GeometryHintKind { point, segment, polygon, boundingBox }

/// Vision이 "대략 여기쯤"이라고 지목한 위치/형태 힌트 — 최종 CAD
/// geometry가 절대 아니다(WO 절대 금지 3번). [HintedGeometryExtractor]가
/// 이 hint 주변을 실제로 탐색해 정밀 geometry를 만든다.
@immutable
class GeometryHint {
  const GeometryHint.point(NormalizedPoint point)
    : kind = GeometryHintKind.point,
      points = const [],
      _point = point,
      _start = null,
      _end = null,
      boundingBox = null;

  const GeometryHint.segment(NormalizedPoint start, NormalizedPoint end)
    : kind = GeometryHintKind.segment,
      points = const [],
      _point = null,
      _start = start,
      _end = end,
      boundingBox = null;

  const GeometryHint.polygon(this.points)
    : kind = GeometryHintKind.polygon,
      _point = null,
      _start = null,
      _end = null,
      boundingBox = null;

  const GeometryHint.boundingBox({
    required double minX,
    required double minY,
    required double maxX,
    required double maxY,
  }) : kind = GeometryHintKind.boundingBox,
       points = const [],
       _point = null,
       _start = null,
       _end = null,
       boundingBox = (minX: minX, minY: minY, maxX: maxX, maxY: maxY);

  final GeometryHintKind kind;
  final NormalizedPoint? _point;
  final NormalizedPoint? _start;
  final NormalizedPoint? _end;
  final List<NormalizedPoint> points;
  final ({double minX, double minY, double maxX, double maxY})? boundingBox;

  NormalizedPoint get point {
    assert(kind == GeometryHintKind.point);
    return _point!;
  }

  NormalizedPoint get start {
    assert(kind == GeometryHintKind.segment);
    return _start!;
  }

  NormalizedPoint get end {
    assert(kind == GeometryHintKind.segment);
    return _end!;
  }

  /// 이 hint를 이루는 모든 점 — kind와 무관하게 "대략 이 근처를
  /// 탐색하라"는 지점들을 얻고 싶을 때 쓴다(bounding box 계산 등).
  List<NormalizedPoint> get allPoints {
    switch (kind) {
      case GeometryHintKind.point:
        return [_point!];
      case GeometryHintKind.segment:
        return [_start!, _end!];
      case GeometryHintKind.polygon:
        return points;
      case GeometryHintKind.boundingBox:
        final box = boundingBox!;
        return [NormalizedPoint(box.minX, box.minY), NormalizedPoint(box.maxX, box.maxY)];
    }
  }

  Map<String, dynamic> toJson() {
    switch (kind) {
      case GeometryHintKind.point:
        return {'kind': 'point', 'point': _point!.toJson()};
      case GeometryHintKind.segment:
        return {'kind': 'segment', 'start': _start!.toJson(), 'end': _end!.toJson()};
      case GeometryHintKind.polygon:
        return {
          'kind': 'polygon',
          'points': [for (final p in points) p.toJson()],
        };
      case GeometryHintKind.boundingBox:
        final box = boundingBox!;
        return {
          'kind': 'boundingBox',
          'minX': box.minX,
          'minY': box.minY,
          'maxX': box.maxX,
          'maxY': box.maxY,
        };
    }
  }

  factory GeometryHint.fromJson(Map<String, dynamic> json) {
    final kind = json['kind'] as String;
    switch (kind) {
      case 'point':
        return GeometryHint.point(
          NormalizedPoint.fromJson(json['point'] as Map<String, dynamic>),
        );
      case 'segment':
        return GeometryHint.segment(
          NormalizedPoint.fromJson(json['start'] as Map<String, dynamic>),
          NormalizedPoint.fromJson(json['end'] as Map<String, dynamic>),
        );
      case 'polygon':
        return GeometryHint.polygon([
          for (final raw in json['points'] as List)
            NormalizedPoint.fromJson(raw as Map<String, dynamic>),
        ]);
      case 'boundingBox':
        return GeometryHint.boundingBox(
          minX: (json['minX'] as num).toDouble(),
          minY: (json['minY'] as num).toDouble(),
          maxX: (json['maxX'] as num).toDouble(),
          maxY: (json['maxY'] as num).toDouble(),
        );
      default:
        throw FormatException('unknown GeometryHint kind: $kind');
    }
  }
}

/// 모든 Vision entity가 공유하는 필드 — 새 entity 타입을 추가해도 이
/// 계약(확신도/출처/좌표 힌트/불확실성 메모)은 항상 함께 다닌다.
mixin VisionEntityBase {
  String get id;
  VisionEntityType get entityType;
  VisionConfidence get confidence;
  VisionSource get source;
  GeometryHint? get geometryHint;
  List<String> get notes;
}

@immutable
class VisionFloorDomain with VisionEntityBase {
  const VisionFloorDomain({
    required this.id,
    required this.confidence,
    required this.geometryHint,
    this.source = VisionSource.vision,
    this.notes = const [],
  });

  @override
  final String id;
  @override
  VisionEntityType get entityType => VisionEntityType.floorDomain;
  @override
  final VisionConfidence confidence;
  @override
  final VisionSource source;
  @override
  final GeometryHint? geometryHint;
  @override
  final List<String> notes;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'floorDomain',
    'confidence': confidence.name,
    'source': source.name,
    'geometryHint': geometryHint?.toJson(),
    'notes': notes,
  };

  factory VisionFloorDomain.fromJson(Map<String, dynamic> json) => VisionFloorDomain(
    id: json['id'] as String,
    confidence: VisionConfidence.values.byName(json['confidence'] as String),
    source: VisionSource.values.byName((json['source'] as String?) ?? 'vision'),
    geometryHint: json['geometryHint'] == null
        ? null
        : GeometryHint.fromJson(json['geometryHint'] as Map<String, dynamic>),
    notes: (json['notes'] as List?)?.cast<String>() ?? const [],
  );
}

@immutable
class VisionSpace with VisionEntityBase {
  const VisionSpace({
    required this.id,
    required this.confidence,
    required this.geometryHint,
    this.label,
    this.semanticType = VisionSpaceSemanticType.unknown,
    this.adjacentSpaceIds = const [],
    this.containedObjectIds = const [],
    this.source = VisionSource.vision,
    this.notes = const [],
  });

  @override
  final String id;
  @override
  VisionEntityType get entityType => VisionEntityType.space;
  @override
  final VisionConfidence confidence;
  @override
  final VisionSource source;
  @override
  final GeometryHint? geometryHint;
  @override
  final List<String> notes;

  /// 도면에 실제로 쓰인 이름(있으면) — 없으면 null, 거짓 이름을
  /// 지어내지 않는다.
  final String? label;
  final VisionSpaceSemanticType semanticType;
  final List<String> adjacentSpaceIds;
  final List<String> containedObjectIds;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'space',
    'confidence': confidence.name,
    'source': source.name,
    'geometryHint': geometryHint?.toJson(),
    'notes': notes,
    'label': label,
    'semanticType': semanticType.name,
    'adjacentSpaceIds': adjacentSpaceIds,
    'containedObjectIds': containedObjectIds,
  };

  factory VisionSpace.fromJson(Map<String, dynamic> json) => VisionSpace(
    id: json['id'] as String,
    confidence: VisionConfidence.values.byName(json['confidence'] as String),
    source: VisionSource.values.byName((json['source'] as String?) ?? 'vision'),
    geometryHint: json['geometryHint'] == null
        ? null
        : GeometryHint.fromJson(json['geometryHint'] as Map<String, dynamic>),
    notes: (json['notes'] as List?)?.cast<String>() ?? const [],
    label: json['label'] as String?,
    semanticType: VisionSpaceSemanticType.values.byName(
      (json['semanticType'] as String?) ?? 'unknown',
    ),
    adjacentSpaceIds: (json['adjacentSpaceIds'] as List?)?.cast<String>() ?? const [],
    containedObjectIds: (json['containedObjectIds'] as List?)?.cast<String>() ?? const [],
  );
}

@immutable
class VisionBoundary with VisionEntityBase {
  const VisionBoundary({
    required this.id,
    required this.confidence,
    required this.geometryHint,
    required this.boundaryType,
    this.adjacentSpaceIds = const [],
    this.source = VisionSource.vision,
    this.notes = const [],
  });

  @override
  final String id;
  @override
  VisionEntityType get entityType => VisionEntityType.boundary;
  @override
  final VisionConfidence confidence;
  @override
  final VisionSource source;
  @override
  final GeometryHint? geometryHint;
  @override
  final List<String> notes;

  final VisionBoundaryType boundaryType;
  final List<String> adjacentSpaceIds;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'boundary',
    'confidence': confidence.name,
    'source': source.name,
    'geometryHint': geometryHint?.toJson(),
    'notes': notes,
    'boundaryType': boundaryType.name,
    'adjacentSpaceIds': adjacentSpaceIds,
  };

  factory VisionBoundary.fromJson(Map<String, dynamic> json) => VisionBoundary(
    id: json['id'] as String,
    confidence: VisionConfidence.values.byName(json['confidence'] as String),
    source: VisionSource.values.byName((json['source'] as String?) ?? 'vision'),
    geometryHint: json['geometryHint'] == null
        ? null
        : GeometryHint.fromJson(json['geometryHint'] as Map<String, dynamic>),
    notes: (json['notes'] as List?)?.cast<String>() ?? const [],
    boundaryType: VisionBoundaryType.values.byName(json['boundaryType'] as String),
    adjacentSpaceIds: (json['adjacentSpaceIds'] as List?)?.cast<String>() ?? const [],
  );
}

@immutable
class VisionOpening with VisionEntityBase {
  const VisionOpening({
    required this.id,
    required this.confidence,
    required this.geometryHint,
    required this.openingType,
    this.attachedBoundaryId,
    this.connectedSpaceIds = const [],
    this.source = VisionSource.vision,
    this.notes = const [],
  });

  @override
  final String id;
  @override
  VisionEntityType get entityType => VisionEntityType.opening;
  @override
  final VisionConfidence confidence;
  @override
  final VisionSource source;
  @override
  final GeometryHint? geometryHint;
  @override
  final List<String> notes;

  final VisionOpeningType openingType;
  final String? attachedBoundaryId;
  final List<String> connectedSpaceIds;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'opening',
    'confidence': confidence.name,
    'source': source.name,
    'geometryHint': geometryHint?.toJson(),
    'notes': notes,
    'openingType': openingType.name,
    'attachedBoundaryId': attachedBoundaryId,
    'connectedSpaceIds': connectedSpaceIds,
  };

  factory VisionOpening.fromJson(Map<String, dynamic> json) => VisionOpening(
    id: json['id'] as String,
    confidence: VisionConfidence.values.byName(json['confidence'] as String),
    source: VisionSource.values.byName((json['source'] as String?) ?? 'vision'),
    geometryHint: json['geometryHint'] == null
        ? null
        : GeometryHint.fromJson(json['geometryHint'] as Map<String, dynamic>),
    notes: (json['notes'] as List?)?.cast<String>() ?? const [],
    openingType: VisionOpeningType.values.byName(json['openingType'] as String),
    attachedBoundaryId: json['attachedBoundaryId'] as String?,
    connectedSpaceIds: (json['connectedSpaceIds'] as List?)?.cast<String>() ?? const [],
  );
}

@immutable
class VisionObject with VisionEntityBase {
  const VisionObject({
    required this.id,
    required this.confidence,
    required this.geometryHint,
    required this.objectType,
    this.containingSpaceId,
    this.source = VisionSource.vision,
    this.notes = const [],
  });

  @override
  final String id;
  @override
  VisionEntityType get entityType => VisionEntityType.object;
  @override
  final VisionConfidence confidence;
  @override
  final VisionSource source;
  @override
  final GeometryHint? geometryHint;
  @override
  final List<String> notes;

  final VisionObjectType objectType;
  final String? containingSpaceId;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'object',
    'confidence': confidence.name,
    'source': source.name,
    'geometryHint': geometryHint?.toJson(),
    'notes': notes,
    'objectType': objectType.name,
    'containingSpaceId': containingSpaceId,
  };

  factory VisionObject.fromJson(Map<String, dynamic> json) => VisionObject(
    id: json['id'] as String,
    confidence: VisionConfidence.values.byName(json['confidence'] as String),
    source: VisionSource.values.byName((json['source'] as String?) ?? 'vision'),
    geometryHint: json['geometryHint'] == null
        ? null
        : GeometryHint.fromJson(json['geometryHint'] as Map<String, dynamic>),
    notes: (json['notes'] as List?)?.cast<String>() ?? const [],
    objectType: VisionObjectType.values.byName(json['objectType'] as String),
    containingSpaceId: json['containingSpaceId'] as String?,
  );
}

@immutable
class VisionStructuralElement with VisionEntityBase {
  const VisionStructuralElement({
    required this.id,
    required this.confidence,
    required this.geometryHint,
    required this.structuralType,
    this.source = VisionSource.vision,
    this.notes = const [],
  });

  @override
  final String id;
  @override
  VisionEntityType get entityType => VisionEntityType.structuralElement;
  @override
  final VisionConfidence confidence;
  @override
  final VisionSource source;
  @override
  final GeometryHint? geometryHint;
  @override
  final List<String> notes;

  final VisionStructuralType structuralType;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'structuralElement',
    'confidence': confidence.name,
    'source': source.name,
    'geometryHint': geometryHint?.toJson(),
    'notes': notes,
    'structuralType': structuralType.name,
  };

  factory VisionStructuralElement.fromJson(Map<String, dynamic> json) => VisionStructuralElement(
    id: json['id'] as String,
    confidence: VisionConfidence.values.byName(json['confidence'] as String),
    source: VisionSource.values.byName((json['source'] as String?) ?? 'vision'),
    geometryHint: json['geometryHint'] == null
        ? null
        : GeometryHint.fromJson(json['geometryHint'] as Map<String, dynamic>),
    notes: (json['notes'] as List?)?.cast<String>() ?? const [],
    structuralType: VisionStructuralType.values.byName(json['structuralType'] as String),
  );
}

/// 도면에 실제로 인쇄된 치수 텍스트를 옮긴 것 — [parsedValueMm]은 OCR로
/// 실제 숫자를 읽었을 때만 채운다. 이 POC는 OCR을 구현하지 않으므로
/// 항상 null이다(WO 절대 금지 4/5번 — 임의 mm 생성 금지).
@immutable
class VisionDimension with VisionEntityBase {
  const VisionDimension({
    required this.id,
    required this.confidence,
    required this.geometryHint,
    required this.rawText,
    this.parsedValueMm,
    this.appliesToBoundaryId,
    this.source = VisionSource.vision,
    this.notes = const [],
  });

  @override
  final String id;
  @override
  VisionEntityType get entityType => VisionEntityType.dimension;
  @override
  final VisionConfidence confidence;
  @override
  final VisionSource source;
  @override
  final GeometryHint? geometryHint;
  @override
  final List<String> notes;

  final String rawText;
  final double? parsedValueMm;
  final String? appliesToBoundaryId;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'dimension',
    'confidence': confidence.name,
    'source': source.name,
    'geometryHint': geometryHint?.toJson(),
    'notes': notes,
    'rawText': rawText,
    'parsedValueMm': parsedValueMm,
    'appliesToBoundaryId': appliesToBoundaryId,
  };

  factory VisionDimension.fromJson(Map<String, dynamic> json) => VisionDimension(
    id: json['id'] as String,
    confidence: VisionConfidence.values.byName(json['confidence'] as String),
    source: VisionSource.values.byName((json['source'] as String?) ?? 'vision'),
    geometryHint: json['geometryHint'] == null
        ? null
        : GeometryHint.fromJson(json['geometryHint'] as Map<String, dynamic>),
    notes: (json['notes'] as List?)?.cast<String>() ?? const [],
    rawText: json['rawText'] as String,
    parsedValueMm: (json['parsedValueMm'] as num?)?.toDouble(),
    appliesToBoundaryId: json['appliesToBoundaryId'] as String?,
  );
}

/// 이미지 한 장에 대한 Vision 분석 결과 전체 — [VisionInterpretationService]
/// 의 출력이다. 이번 POC는 Building/Storey wrapper를 만들지 않는다(단층
/// 도면 한 장만 다루므로 지금 추가하면 항상 빈 껍데기다).
@immutable
class VisionUnderstanding {
  const VisionUnderstanding({
    required this.floorDomain,
    this.spaces = const [],
    this.boundaries = const [],
    this.openings = const [],
    this.objects = const [],
    this.structuralElements = const [],
    this.dimensions = const [],
    this.scaleConfirmed = false,
    this.notes = const [],
  });

  final VisionFloorDomain floorDomain;
  final List<VisionSpace> spaces;
  final List<VisionBoundary> boundaries;
  final List<VisionOpening> openings;
  final List<VisionObject> objects;
  final List<VisionStructuralElement> structuralElements;
  final List<VisionDimension> dimensions;

  /// 이 도면에서 실제 축척을 확정할 근거(치수 텍스트 등)가 있었는지 —
  /// 없으면 항상 false. Vision이 문 폭 등으로 mm를 임의 추정해 이 값을
  /// true로 만들지 않는다(WO 절대 금지 4/5번).
  final bool scaleConfirmed;
  final List<String> notes;

  Map<String, dynamic> toJson() => {
    'floorDomain': floorDomain.toJson(),
    'spaces': [for (final s in spaces) s.toJson()],
    'boundaries': [for (final b in boundaries) b.toJson()],
    'openings': [for (final o in openings) o.toJson()],
    'objects': [for (final o in objects) o.toJson()],
    'structuralElements': [for (final s in structuralElements) s.toJson()],
    'dimensions': [for (final d in dimensions) d.toJson()],
    'scaleConfirmed': scaleConfirmed,
    'notes': notes,
  };

  factory VisionUnderstanding.fromJson(Map<String, dynamic> json) => VisionUnderstanding(
    floorDomain: VisionFloorDomain.fromJson(json['floorDomain'] as Map<String, dynamic>),
    spaces: [
      for (final raw in (json['spaces'] as List? ?? const []))
        VisionSpace.fromJson(raw as Map<String, dynamic>),
    ],
    boundaries: [
      for (final raw in (json['boundaries'] as List? ?? const []))
        VisionBoundary.fromJson(raw as Map<String, dynamic>),
    ],
    openings: [
      for (final raw in (json['openings'] as List? ?? const []))
        VisionOpening.fromJson(raw as Map<String, dynamic>),
    ],
    objects: [
      for (final raw in (json['objects'] as List? ?? const []))
        VisionObject.fromJson(raw as Map<String, dynamic>),
    ],
    structuralElements: [
      for (final raw in (json['structuralElements'] as List? ?? const []))
        VisionStructuralElement.fromJson(raw as Map<String, dynamic>),
    ],
    dimensions: [
      for (final raw in (json['dimensions'] as List? ?? const []))
        VisionDimension.fromJson(raw as Map<String, dynamic>),
    ],
    scaleConfirmed: json['scaleConfirmed'] as bool? ?? false,
    notes: (json['notes'] as List?)?.cast<String>() ?? const [],
  );
}
