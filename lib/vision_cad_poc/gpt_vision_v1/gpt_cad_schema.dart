/// SPACE SHIFT — Real GPT Vision → Detailed CAD JSON → SS Refinement POC.
///
/// GPT Vision API가 반드시 이 형태(JSON only)로 응답해야 하는 계약
/// ("ss-cad-vision-v1"). 이 파일은 순수 파싱만 담당한다 — cross-reference
/// 검증(중복 id/존재하지 않는 참조/좌표 범위/FloorDomain 폐합 등)은
/// `gpt_cad_json_validator.dart`가 별도로 한다. 여기서는 "이 JSON이
/// 최소한 올바른 모양인가"만 본다.
library;

enum GptCornerKind { exteriorConvex, exteriorConcave, interiorJunction, tJunction, endpoint }

enum GptWallType { exterior, interior }

enum GptRelationKind { adjacent, connectedByDoor, connectedByOpening, contains, hostedBy }

class GptImageInfo {
  const GptImageInfo({
    required this.widthPx,
    required this.heightPx,
    required this.coordinateSystem,
    required this.scaleStatus,
  });

  final int widthPx;
  final int heightPx;
  final String coordinateSystem;
  final String scaleStatus;

  factory GptImageInfo.fromJson(Map<String, dynamic> json) => GptImageInfo(
        widthPx: _reqInt(json, 'widthPx'),
        heightPx: _reqInt(json, 'heightPx'),
        coordinateSystem: _reqString(json, 'coordinateSystem'),
        scaleStatus: _reqString(json, 'scaleStatus'),
      );
}

class GptCorner {
  const GptCorner({
    required this.id,
    required this.x,
    required this.y,
    required this.kind,
    required this.confidence,
    this.notes = '',
  });

  final String id;
  final double x;
  final double y;
  final GptCornerKind kind;
  final double confidence;
  final String notes;

  factory GptCorner.fromJson(Map<String, dynamic> json) => GptCorner(
        id: _reqString(json, 'id'),
        x: _reqDouble(json, 'x'),
        y: _reqDouble(json, 'y'),
        kind: _reqEnum(json, 'kind', GptCornerKind.values, (e) => e.name),
        confidence: _reqConfidence(json, 'confidence'),
        notes: json['notes'] as String? ?? '',
      );
}

class GptWall {
  const GptWall({
    required this.id,
    required this.type,
    required this.cornerIds,
    required this.confidence,
    this.thicknessPxHint,
    this.notes = '',
  });

  final String id;
  final GptWallType type;
  final List<String> cornerIds;
  final double? thicknessPxHint;
  final double confidence;
  final String notes;

  factory GptWall.fromJson(Map<String, dynamic> json) => GptWall(
        id: _reqString(json, 'id'),
        type: _reqEnum(json, 'type', GptWallType.values, (e) => e.name),
        cornerIds: _reqStringList(json, 'cornerIds'),
        thicknessPxHint: (json['thicknessPxHint'] as num?)?.toDouble(),
        confidence: _reqConfidence(json, 'confidence'),
        notes: json['notes'] as String? ?? '',
      );
}

class GptFloorDomain {
  const GptFloorDomain({required this.orderedCornerIds, required this.confidence});

  final List<String> orderedCornerIds;
  final double confidence;

  factory GptFloorDomain.fromJson(Map<String, dynamic> json) => GptFloorDomain(
        orderedCornerIds: _reqStringList(json, 'orderedCornerIds'),
        confidence: _reqConfidence(json, 'confidence'),
      );
}

class GptSpace {
  const GptSpace({
    required this.id,
    required this.label,
    required this.semanticType,
    required this.boundaryWallIds,
    required this.confidence,
    this.reviewReasons = const [],
  });

  final String id;
  final String label;
  final String semanticType;
  final List<String> boundaryWallIds;
  final double confidence;
  final List<String> reviewReasons;

  factory GptSpace.fromJson(Map<String, dynamic> json) => GptSpace(
        id: _reqString(json, 'id'),
        label: _reqString(json, 'label'),
        semanticType: _reqString(json, 'semanticType'),
        boundaryWallIds: _reqStringList(json, 'boundaryWallIds'),
        confidence: _reqConfidence(json, 'confidence'),
        reviewReasons: (json['reviewReasons'] as List?)?.cast<String>() ?? const [],
      );
}

class GptDoor {
  const GptDoor({
    required this.id,
    required this.hostWallId,
    required this.startT,
    required this.endT,
    required this.connectsSpaceIds,
    required this.confidence,
    this.swingDirection,
  });

  final String id;
  final String hostWallId;
  final double startT;
  final double endT;
  final List<String> connectsSpaceIds;
  final String? swingDirection;
  final double confidence;

  factory GptDoor.fromJson(Map<String, dynamic> json) => GptDoor(
        id: _reqString(json, 'id'),
        hostWallId: _reqString(json, 'hostWallId'),
        startT: _reqT(json, 'startT'),
        endT: _reqT(json, 'endT'),
        connectsSpaceIds: _reqStringList(json, 'connectsSpaceIds'),
        swingDirection: json['swingDirection'] as String?,
        confidence: _reqConfidence(json, 'confidence'),
      );
}

class GptWindow {
  const GptWindow({
    required this.id,
    required this.hostWallId,
    required this.startT,
    required this.endT,
    required this.confidence,
  });

  final String id;
  final String hostWallId;
  final double startT;
  final double endT;
  final double confidence;

  factory GptWindow.fromJson(Map<String, dynamic> json) => GptWindow(
        id: _reqString(json, 'id'),
        hostWallId: _reqString(json, 'hostWallId'),
        startT: _reqT(json, 'startT'),
        endT: _reqT(json, 'endT'),
        confidence: _reqConfidence(json, 'confidence'),
      );
}

class GptOpening {
  const GptOpening({
    required this.id,
    required this.hostWallId,
    required this.startT,
    required this.endT,
    required this.connectsSpaceIds,
    required this.confidence,
  });

  final String id;
  final String hostWallId;
  final double startT;
  final double endT;
  final List<String> connectsSpaceIds;
  final double confidence;

  factory GptOpening.fromJson(Map<String, dynamic> json) => GptOpening(
        id: _reqString(json, 'id'),
        hostWallId: _reqString(json, 'hostWallId'),
        startT: _reqT(json, 'startT'),
        endT: _reqT(json, 'endT'),
        connectsSpaceIds: _reqStringList(json, 'connectsSpaceIds'),
        confidence: _reqConfidence(json, 'confidence'),
      );
}

class GptObject {
  const GptObject({
    required this.id,
    required this.type,
    required this.bboxPx,
    required this.confidence,
    this.containingSpaceId,
  });

  final String id;
  final String type;
  final List<double> bboxPx;
  final String? containingSpaceId;
  final double confidence;

  factory GptObject.fromJson(Map<String, dynamic> json) {
    final box = (json['bboxPx'] as List?)?.map((e) => (e as num).toDouble()).toList();
    if (box == null || box.length != 4) {
      throw FormatException('object.bboxPx must be [x1,y1,x2,y2]: $json');
    }
    return GptObject(
      id: _reqString(json, 'id'),
      type: _reqString(json, 'type'),
      bboxPx: box,
      containingSpaceId: json['containingSpaceId'] as String?,
      confidence: _reqConfidence(json, 'confidence'),
    );
  }
}

class GptRelationship {
  const GptRelationship({required this.entityA, required this.entityB, required this.relation});

  final String entityA;
  final String entityB;
  final GptRelationKind relation;

  factory GptRelationship.fromJson(Map<String, dynamic> json) => GptRelationship(
        entityA: _reqString(json, 'entityA'),
        entityB: _reqString(json, 'entityB'),
        relation: _reqEnum(json, 'relation', GptRelationKind.values, (e) => e.name),
      );
}

class GptDimensionHint {
  const GptDimensionHint({required this.rawText, this.associatedGeometryId, this.confidence});

  final String rawText;
  final String? associatedGeometryId;
  final double? confidence;

  factory GptDimensionHint.fromJson(Map<String, dynamic> json) => GptDimensionHint(
        rawText: _reqString(json, 'rawText'),
        associatedGeometryId: json['associatedGeometryId'] as String?,
        confidence: (json['confidence'] as num?)?.toDouble(),
      );
}

/// 최상위 GPT Vision 응답 — "ss-cad-vision-v1"만 지원한다. 다른
/// schemaVersion은 [GptCadJsonValidator]가 명시적으로 거부한다(임의
/// 하위호환 추정 금지).
class GptCadProposal {
  const GptCadProposal({
    required this.schemaVersion,
    required this.image,
    required this.floorDomain,
    required this.corners,
    required this.walls,
    required this.spaces,
    required this.doors,
    required this.windows,
    required this.openings,
    required this.objects,
    required this.relationships,
    required this.dimensionHints,
    required this.reviewReasons,
  });

  final String schemaVersion;
  final GptImageInfo image;
  final GptFloorDomain floorDomain;
  final List<GptCorner> corners;
  final List<GptWall> walls;
  final List<GptSpace> spaces;
  final List<GptDoor> doors;
  final List<GptWindow> windows;
  final List<GptOpening> openings;
  final List<GptObject> objects;
  final List<GptRelationship> relationships;
  final List<GptDimensionHint> dimensionHints;
  final List<String> reviewReasons;

  factory GptCadProposal.fromJson(Map<String, dynamic> json) => GptCadProposal(
        schemaVersion: _reqString(json, 'schemaVersion'),
        image: GptImageInfo.fromJson(_reqMap(json, 'image')),
        floorDomain: GptFloorDomain.fromJson(_reqMap(json, 'floorDomain')),
        corners: _reqList(json, 'corners').map((e) => GptCorner.fromJson(e as Map<String, dynamic>)).toList(),
        walls: _reqList(json, 'walls').map((e) => GptWall.fromJson(e as Map<String, dynamic>)).toList(),
        spaces: _reqList(json, 'spaces').map((e) => GptSpace.fromJson(e as Map<String, dynamic>)).toList(),
        doors: (json['doors'] as List? ?? const []).map((e) => GptDoor.fromJson(e as Map<String, dynamic>)).toList(),
        windows:
            (json['windows'] as List? ?? const []).map((e) => GptWindow.fromJson(e as Map<String, dynamic>)).toList(),
        openings: (json['openings'] as List? ?? const [])
            .map((e) => GptOpening.fromJson(e as Map<String, dynamic>))
            .toList(),
        objects:
            (json['objects'] as List? ?? const []).map((e) => GptObject.fromJson(e as Map<String, dynamic>)).toList(),
        relationships: (json['relationships'] as List? ?? const [])
            .map((e) => GptRelationship.fromJson(e as Map<String, dynamic>))
            .toList(),
        dimensionHints: (json['dimensionHints'] as List? ?? const [])
            .map((e) => GptDimensionHint.fromJson(e as Map<String, dynamic>))
            .toList(),
        reviewReasons: (json['reviewReasons'] as List?)?.cast<String>() ?? const [],
      );
}

// ---- 파싱 헬퍼 (형태 오류를 명확한 FormatException으로) ----

String _reqString(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v is! String || v.isEmpty) {
    throw FormatException('required non-empty string field "$key" missing or invalid: $json');
  }
  return v;
}

int _reqInt(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v is! num) throw FormatException('required numeric field "$key" missing: $json');
  return v.toInt();
}

double _reqDouble(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v is! num) throw FormatException('required numeric field "$key" missing: $json');
  return v.toDouble();
}

double _reqConfidence(Map<String, dynamic> json, String key) {
  final v = _reqDouble(json, key);
  if (v < 0.0 || v > 1.0) {
    throw FormatException('confidence "$key" must be within 0.0..1.0, got $v: $json');
  }
  return v;
}

double _reqT(Map<String, dynamic> json, String key) {
  final v = _reqDouble(json, key);
  if (v < 0.0 || v > 1.0) {
    throw FormatException('parametric position "$key" must be within 0.0..1.0, got $v: $json');
  }
  return v;
}

Map<String, dynamic> _reqMap(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v is! Map<String, dynamic>) {
    throw FormatException('required object field "$key" missing or invalid: $json');
  }
  return v;
}

List<dynamic> _reqList(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v is! List) throw FormatException('required array field "$key" missing or invalid: $json');
  return v;
}

List<String> _reqStringList(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v is! List || v.isEmpty || v.any((e) => e is! String)) {
    throw FormatException('required non-empty string array "$key" missing or invalid: $json');
  }
  return v.cast<String>();
}

T _reqEnum<T>(Map<String, dynamic> json, String key, List<T> values, String Function(T) nameOf) {
  final raw = json[key];
  if (raw is! String) throw FormatException('required enum field "$key" missing: $json');
  for (final v in values) {
    if (nameOf(v) == raw) return v;
  }
  throw FormatException('field "$key" has unknown value "$raw" (expected one of ${values.map(nameOf).join(", ")})');
}
