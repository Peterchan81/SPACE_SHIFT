/// SPACE SHIFT — GPT Space Boundary Loop Recovery POC.
///
/// PASS B 계약: 기존 ss-cad-vision-v1의 "전역 공유 corner/wall 그래프"
/// 대신, 각 space가 **자기 자신의 완전한 순서 있는 경계**를 독립적으로
/// 기술하게 한다 — GPT가 13개 방에 걸쳐 corner id를 스스로 일관되게
/// 재사용해야 하는 부담(직전 세션에서 실패의 근본 원인으로 확인됨)을
/// 아예 없앤다. 같은 벽을 두 공간이 각자 다시 설명해도 된다 — SS가
/// 기하학적으로 병합한다([GptSharedWallMerger] 참고).
library;

enum GptSegmentKind { wall, opening, exterior }

class GptPixelPoint {
  const GptPixelPoint(this.x, this.y);
  final double x;
  final double y;

  /// GPT가 프롬프트에서 요청한 `{"x":..,"y":..}` 대신 `[x,y]` 배열로
  /// 응답하는 경우가 실제로 관찰되었다 — 둘 다 명확히 파싱 가능한
  /// 형태이므로, geometry를 지어내는 것이 아니라 표현 형식만 관대하게
  /// 받아들인다.
  factory GptPixelPoint.fromDynamic(dynamic json) {
    if (json is List && json.length == 2) {
      return GptPixelPoint((json[0] as num).toDouble(), (json[1] as num).toDouble());
    }
    if (json is Map<String, dynamic>) {
      return GptPixelPoint(_reqDouble(json, 'x'), _reqDouble(json, 'y'));
    }
    throw FormatException('point must be {"x":..,"y":..} or [x,y]: $json');
  }
}

class GptBoundarySegment {
  const GptBoundarySegment({
    required this.id,
    required this.start,
    required this.end,
    required this.kind,
    required this.confidence,
    this.sharedWithSpaceId,
  });

  final String id;
  final GptPixelPoint start;
  final GptPixelPoint end;
  final GptSegmentKind kind;
  final String? sharedWithSpaceId;
  final double confidence;

  /// [fallbackConfidence]는 segment 자체에 confidence가 없을 때(관찰된
  /// 실제 GPT 응답 변형) 상위 space loop의 confidence를 그대로 쓴다 —
  /// 임의의 새 값을 지어내는 것이 아니라 이미 GPT가 준 상위 확신도를
  /// 상속할 뿐이다. [fallbackId]도 마찬가지로 순번 기반 합성 id다.
  factory GptBoundarySegment.fromJson(
    Map<String, dynamic> json, {
    required double fallbackConfidence,
    required String fallbackId,
  }) =>
      GptBoundarySegment(
        id: (json['id'] as String?) ?? fallbackId,
        start: GptPixelPoint.fromDynamic(json['start']),
        end: GptPixelPoint.fromDynamic(json['end']),
        kind: _reqEnum(json, 'kind', GptSegmentKind.values, (e) => e.name),
        sharedWithSpaceId: json['sharedWithSpaceId'] as String?,
        confidence: (json['confidence'] as num?)?.toDouble() ?? fallbackConfidence,
      );
}

class GptSpaceBoundaryLoop {
  const GptSpaceBoundaryLoop({
    required this.spaceId,
    required this.segments,
    required this.closed,
    required this.confidence,
    this.reviewReasons = const [],
  });

  final String spaceId;
  final List<GptBoundarySegment> segments;

  /// GPT 스스로의 자기 평가일 뿐이다 — SS는 이를 그대로 신뢰하지 않고
  /// [GptBoundaryLoopProcessor]에서 실제로 순서가 닫히는지 독립적으로
  /// 재검증한다.
  final bool closed;
  final double confidence;
  final List<String> reviewReasons;

  factory GptSpaceBoundaryLoop.fromJson(Map<String, dynamic> json) {
    final spaceId = _reqString(json, 'spaceId');
    final confidence = _reqConfidence(json, 'confidence');
    final rawSegments = _reqList(json, 'segments');
    return GptSpaceBoundaryLoop(
      spaceId: spaceId,
      segments: [
        for (var i = 0; i < rawSegments.length; i++)
          GptBoundarySegment.fromJson(
            rawSegments[i] as Map<String, dynamic>,
            fallbackConfidence: confidence,
            fallbackId: '$spaceId-seg$i',
          ),
      ],
      closed: json['closed'] as bool? ?? false,
      confidence: confidence,
      reviewReasons: (json['reviewReasons'] as List?)?.cast<String>() ?? const [],
    );
  }
}

class GptPassBResponse {
  const GptPassBResponse({required this.spaceBoundaryLoops});

  final List<GptSpaceBoundaryLoop> spaceBoundaryLoops;

  factory GptPassBResponse.fromJson(Map<String, dynamic> json) => GptPassBResponse(
        spaceBoundaryLoops: _reqList(json, 'spaceBoundaryLoops')
            .map((e) => GptSpaceBoundaryLoop.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// ---- 파싱 헬퍼 ----

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
  if (v < 0.0 || v > 1.0) {
    throw FormatException('confidence "$key" must be within 0.0..1.0, got $v: $json');
  }
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
