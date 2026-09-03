/// SPACE SHIFT — GPT Space Boundary Loop Recovery POC.
///
/// PASS A 계약: 전체 도면 의미 이해 전용(설계 3번). 완벽한 pixel wall
/// geometry를 요구하지 않는다 — 그건 PASS B의 역할이다.
library;

class GptPassASpace {
  const GptPassASpace({
    required this.id,
    required this.label,
    required this.semanticType,
    required this.confidence,
    this.isExterior = false,
  });

  final String id;
  final String label;
  final String semanticType;
  final double confidence;

  /// 이 공간이 건물 외곽에 직접 접하는지(발코니/실외기실처럼 돌출된
  /// 공간을 FloorDomain 재구성 시 우선 참고하기 위함).
  final bool isExterior;

  factory GptPassASpace.fromJson(Map<String, dynamic> json) => GptPassASpace(
        id: _reqString(json, 'id'),
        label: _reqString(json, 'label'),
        semanticType: _reqString(json, 'semanticType'),
        confidence: _reqConfidence(json, 'confidence'),
        isExterior: json['isExterior'] as bool? ?? false,
      );
}

class GptPassARelationship {
  const GptPassARelationship({required this.spaceIdA, required this.spaceIdB, required this.relation});

  final String spaceIdA;
  final String spaceIdB;
  final String relation;

  factory GptPassARelationship.fromJson(Map<String, dynamic> json) => GptPassARelationship(
        spaceIdA: _reqString(json, 'spaceIdA'),
        spaceIdB: _reqString(json, 'spaceIdB'),
        relation: _reqString(json, 'relation'),
      );
}

class GptPassAResponse {
  const GptPassAResponse({
    required this.spaces,
    required this.relationships,
    required this.majorExteriorNotes,
    this.reviewReasons = const [],
  });

  final List<GptPassASpace> spaces;
  final List<GptPassARelationship> relationships;
  final String majorExteriorNotes;
  final List<String> reviewReasons;

  factory GptPassAResponse.fromJson(Map<String, dynamic> json) => GptPassAResponse(
        spaces: _reqList(json, 'spaces').map((e) => GptPassASpace.fromJson(e as Map<String, dynamic>)).toList(),
        relationships: (json['relationships'] as List? ?? const [])
            .map((e) => GptPassARelationship.fromJson(e as Map<String, dynamic>))
            .toList(),
        majorExteriorNotes: json['majorExteriorNotes'] as String? ?? '',
        reviewReasons: (json['reviewReasons'] as List?)?.cast<String>() ?? const [],
      );
}

String _reqString(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v is! String || v.isEmpty) {
    throw FormatException('required non-empty string field "$key" missing or invalid: $json');
  }
  return v;
}

double _reqConfidence(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v is! num) throw FormatException('required numeric field "$key" missing: $json');
  final d = v.toDouble();
  if (d < 0.0 || d > 1.0) throw FormatException('confidence "$key" must be within 0.0..1.0, got $d: $json');
  return d;
}

List<dynamic> _reqList(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v is! List) throw FormatException('required array field "$key" missing or invalid: $json');
  return v;
}
