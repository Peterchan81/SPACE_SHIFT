// SPACE SHIFT — Vision-Guided Full Pixel Wall Extraction POC.
//
// "ss-cad-semantic-v4" 계약 — v1/v2/v3와 근본적으로 다르다: GPT는 벽/코너
// 좌표를 단 하나도 만들지 않는다. WHAT(라벨) / RELATIONSHIP(인접) /
// WHERE TO LOOK(대략 ROI, CAD 좌표 아님) / 출입구·가구·모호 영역
// 힌트만 준다. 실제 geometry는 pixel_wall_extractor.dart가 이미지에서
// 직접 뽑는다.

class GptApproxRegion {
  const GptApproxRegion({required this.x0, required this.y0, required this.x1, required this.y1});

  /// 정규화(0~1) bounding box — "이 근처를 보라"는 탐색 힌트일 뿐,
  /// 벽 경계로 그대로 쓰지 않는다.
  final double x0;
  final double y0;
  final double x1;
  final double y1;

  factory GptApproxRegion.fromJson(Map<String, dynamic> json) {
    return GptApproxRegion(
      x0: _reqDouble(json, 'x0'),
      y0: _reqDouble(json, 'y0'),
      x1: _reqDouble(json, 'x1'),
      y1: _reqDouble(json, 'y1'),
    );
  }

  double get area => (x1 - x0).abs() * (y1 - y0).abs();

  /// 다른 bbox와의 IoU — GPT ROI와 실제 pixel RoomCandidate bbox를
  /// 매칭할 때만 쓰는 근사치(둘 다 대략적인 사각형이라는 전제).
  double iouWith(GptApproxRegion other) {
    final ix0 = x0 > other.x0 ? x0 : other.x0;
    final iy0 = y0 > other.y0 ? y0 : other.y0;
    final ix1 = x1 < other.x1 ? x1 : other.x1;
    final iy1 = y1 < other.y1 ? y1 : other.y1;
    final iw = ix1 - ix0;
    final ih = iy1 - iy0;
    if (iw <= 0 || ih <= 0) return 0;
    final inter = iw * ih;
    final union = area + other.area - inter;
    return union <= 0 ? 0 : inter / union;
  }
}

class GptSemanticOpening {
  const GptSemanticOpening({required this.type, required this.approxRegion, this.adjacentSpaceId});
  final String type; // door | window
  final GptApproxRegion approxRegion;
  final String? adjacentSpaceId;

  factory GptSemanticOpening.fromJson(Map<String, dynamic> json) {
    return GptSemanticOpening(
      type: _reqString(json, 'type'),
      approxRegion: GptApproxRegion.fromJson(_reqMap(json, 'approxRegion')),
      adjacentSpaceId: json['adjacentSpaceId'] as String?,
    );
  }
}

class GptSemanticSpace {
  const GptSemanticSpace({
    required this.id,
    required this.label,
    required this.semanticType,
    required this.approxRegion,
    this.neighborSpaceIds = const [],
    this.exteriorSides = const [],
  });

  final String id;
  final String label;
  final String semanticType;
  final GptApproxRegion approxRegion;
  final List<String> neighborSpaceIds;

  /// "top"/"bottom"/"left"/"right" 부분집합 — 이 공간의 어느 쪽이
  /// 건물 외부와 맞닿는지에 대한 힌트(FloorDomain 검증 보조용).
  final List<String> exteriorSides;

  factory GptSemanticSpace.fromJson(Map<String, dynamic> json) {
    return GptSemanticSpace(
      id: _reqString(json, 'id'),
      label: _reqString(json, 'label'),
      semanticType: _reqString(json, 'semanticType'),
      approxRegion: GptApproxRegion.fromJson(_reqMap(json, 'approxRegion')),
      neighborSpaceIds: _optStringList(json, 'neighborSpaceIds'),
      exteriorSides: _optStringList(json, 'exteriorSides'),
    );
  }
}

class GptSemanticRegionNote {
  const GptSemanticRegionNote({required this.approxRegion, required this.note});
  final GptApproxRegion approxRegion;
  final String note;

  factory GptSemanticRegionNote.fromJson(Map<String, dynamic> json) {
    return GptSemanticRegionNote(
      approxRegion: GptApproxRegion.fromJson(_reqMap(json, 'approxRegion')),
      note: _reqString(json, 'note'),
    );
  }
}

class GptSemanticResponse {
  const GptSemanticResponse({
    required this.spaces,
    this.openings = const [],
    this.furnitureRegions = const [],
    this.ambiguousRegions = const [],
  });

  final List<GptSemanticSpace> spaces;
  final List<GptSemanticOpening> openings;
  final List<GptSemanticRegionNote> furnitureRegions;
  final List<GptSemanticRegionNote> ambiguousRegions;

  factory GptSemanticResponse.fromJson(Map<String, dynamic> json) {
    final spacesJson = json['spaces'];
    if (spacesJson is! List || spacesJson.isEmpty) {
      throw const FormatException('spaces: 최소 1개 이상의 공간이 필요합니다');
    }
    final openingsJson = json['openings'];
    final furnitureJson = json['furnitureRegions'];
    final ambiguousJson = json['ambiguousRegions'];
    return GptSemanticResponse(
      spaces: [for (final s in spacesJson) GptSemanticSpace.fromJson(s as Map<String, dynamic>)],
      openings: openingsJson is List
          ? [for (final o in openingsJson) GptSemanticOpening.fromJson(o as Map<String, dynamic>)]
          : const [],
      furnitureRegions: furnitureJson is List
          ? [for (final f in furnitureJson) GptSemanticRegionNote.fromJson(f as Map<String, dynamic>)]
          : const [],
      ambiguousRegions: ambiguousJson is List
          ? [for (final a in ambiguousJson) GptSemanticRegionNote.fromJson(a as Map<String, dynamic>)]
          : const [],
    );
  }
}

String _reqString(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v is! String || v.isEmpty) {
    throw FormatException('$key: 필수 문자열 필드가 없습니다');
  }
  return v;
}

double _reqDouble(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v is num) return v.toDouble();
  throw FormatException('$key: 필수 숫자 필드가 없습니다');
}

Map<String, dynamic> _reqMap(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v is! Map<String, dynamic>) {
    throw FormatException('$key: 필수 객체 필드가 없습니다');
  }
  return v;
}

List<String> _optStringList(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v is! List) return const [];
  return [for (final e in v) e as String];
}
