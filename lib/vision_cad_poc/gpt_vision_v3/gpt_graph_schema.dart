/// SPACE SHIFT — Canonical Wall Graph First POC.
///
/// GPT가 이번에는 13개 방을 각자 따로 설명하지 않고, 건물 전체를
/// 하나의 공유 corner/wall 그래프로 설명한다. 벽 하나가 실제로 두
/// 공간이 공유하면, GPT가 같은 wall id를 두 공간의 boundaryWallIds에
/// 함께 넣어주길 기대한다 — 다만 GPT가 완벽하게 재사용하지 못하는
/// 경우를 대비해 SS 쪽에서도 기하학적 중복 제거를 한 번 더 한다
/// ([GptWallGraphProcessor] 참고).
library;

enum GptCornerKind { exteriorConvex, exteriorConcave, interiorJunction, tJunction, endpoint }

enum GptWallType { exterior, interior }

class GptGraphCorner {
  const GptGraphCorner({required this.id, required this.x, required this.y, required this.kind, required this.confidence});

  final String id;
  final double x;
  final double y;
  final GptCornerKind kind;
  final double confidence;

  factory GptGraphCorner.fromJson(Map<String, dynamic> json) => GptGraphCorner(
        id: _reqString(json, 'id'),
        x: _reqDouble(json, 'x'),
        y: _reqDouble(json, 'y'),
        kind: _reqEnum(json, 'kind', GptCornerKind.values, (e) => e.name),
        confidence: _reqConfidence(json, 'confidence'),
      );
}

class GptGraphWall {
  const GptGraphWall({
    required this.id,
    required this.startCornerId,
    required this.endCornerId,
    required this.type,
    required this.confidence,
    this.adjacentSpaceIds = const [],
    this.notes = '',
  });

  final String id;
  final String startCornerId;
  final String endCornerId;
  final GptWallType type;
  final List<String> adjacentSpaceIds;
  final double confidence;
  final String notes;

  factory GptGraphWall.fromJson(Map<String, dynamic> json) => GptGraphWall(
        id: _reqString(json, 'id'),
        startCornerId: _reqString(json, 'startCornerId'),
        endCornerId: _reqString(json, 'endCornerId'),
        type: _reqEnum(json, 'type', GptWallType.values, (e) => e.name),
        adjacentSpaceIds: (json['adjacentSpaceIds'] as List?)?.cast<String>() ?? const [],
        confidence: _reqConfidence(json, 'confidence'),
        notes: json['notes'] as String? ?? '',
      );
}

class GptGraphSpace {
  const GptGraphSpace({
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

  factory GptGraphSpace.fromJson(Map<String, dynamic> json) => GptGraphSpace(
        id: _reqString(json, 'id'),
        label: _reqString(json, 'label'),
        semanticType: _reqString(json, 'semanticType'),
        boundaryWallIds: (json['boundaryWallIds'] as List?)?.cast<String>() ?? const [],
        confidence: _reqConfidence(json, 'confidence'),
        reviewReasons: (json['reviewReasons'] as List?)?.cast<String>() ?? const [],
      );
}

class GptWallGraphResponse {
  const GptWallGraphResponse({required this.corners, required this.walls, required this.spaces});

  final List<GptGraphCorner> corners;
  final List<GptGraphWall> walls;
  final List<GptGraphSpace> spaces;

  factory GptWallGraphResponse.fromJson(Map<String, dynamic> json) => GptWallGraphResponse(
        corners: _reqList(json, 'corners').map((e) => GptGraphCorner.fromJson(e as Map<String, dynamic>)).toList(),
        walls: _reqList(json, 'walls').map((e) => GptGraphWall.fromJson(e as Map<String, dynamic>)).toList(),
        spaces: _reqList(json, 'spaces').map((e) => GptGraphSpace.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

String _reqString(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v is! String || v.isEmpty) {
    throw FormatException('required non-empty string field "$key" missing or invalid: $json');
  }
  return v;
}

double _reqDouble(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v is! num) throw FormatException('required numeric field "$key" missing: $json');
  return v.toDouble();
}

double _reqConfidence(Map<String, dynamic> json, String key) {
  final v = _reqDouble(json, key);
  if (v < 0.0 || v > 1.0) throw FormatException('confidence "$key" must be within 0.0..1.0, got $v: $json');
  return v;
}

List<dynamic> _reqList(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v is! List) throw FormatException('required array field "$key" missing or invalid: $json');
  return v;
}

T _reqEnum<T>(Map<String, dynamic> json, String key, List<T> values, String Function(T) nameOf) {
  final raw = json[key];
  if (raw is! String) throw FormatException('required enum field "$key" missing: $json');
  for (final v in values) {
    if (nameOf(v) == raw) return v;
  }
  throw FormatException('field "$key" has unknown value "$raw" (expected one of ${values.map(nameOf).join(", ")})');
}
