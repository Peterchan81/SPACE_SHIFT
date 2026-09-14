/// SS CAD TEST — Supabase Edge Function(`supabase/functions/
/// gpt-floorplan-understand/index.ts`)이 OpenAI에 실제로 보내는 요청
/// (model/system prompt/JSON schema)과, 받은 응답을 [VisionUnderstanding]
/// 계약으로 바꾸는 변환 로직을 Dart 쪽에 그대로 옮겨 둔 것.
///
/// Edge Function은 Deno/TypeScript라서 이 프로젝트(Flutter/Dart)와 코드를
/// 직접 공유할 수 없다 — 그래서 [GptDirectOpenAiVisionService](Windows
/// 개발/검증 전용, Supabase를 거치지 않고 OpenAI를 직접 부르는 경로)가
/// 기존 `supabase` 경로와 "같은 결과"를 내도록, 이 파일이 그 TS 파일의
/// 내용을 1:1로 미러링한다. **두 파일 중 하나만 고치고 다른 쪽을 잊으면
/// direct/supabase 두 경로의 결과가 갈라진다** — 이 계약을 바꿀 때는
/// 반드시 `supabase/functions/gpt-floorplan-understand/index.ts`도 함께
/// 고친다(또는 그 반대).
library;

import 'dart:convert';
import 'dart:typed_data';

const String kGptFloorplanOpenAiEndpoint = 'https://api.openai.com/v1/chat/completions';
const String kGptFloorplanOpenAiModel = 'gpt-4o';

/// index.ts의 `SYSTEM_PROMPT`와 글자 그대로 동일해야 한다.
const String kGptFloorplanSystemPrompt =
    'You are an architectural floor plan understanding assistant for an interior '
    'design app. You are given one floor plan image. Identify the building\'s '
    'exterior envelope, distinct usable rooms/spaces (with a best-guess semantic '
    'type such as bedroom/bathroom/kitchen/living/etc.), wall segments (exterior '
    'vs interior), and door/window openings. All coordinates MUST be normalized '
    'to the full image (0.0 at left/top, 1.0 at right/bottom) — never pixel or mm '
    'values. Be honest about uncertainty: use confidence "low" or "unknown" '
    'rather than guessing precisely. Do NOT invent a room label that is not '
    'actually printed on the drawing — use null instead. Do NOT infer or state '
    'any real-world millimeter dimension — you have no way to know the true '
    'scale from a raster image alone; leave that to a later calibration step. '
    'If a wall or opening is ambiguous, still report it with lower confidence '
    'rather than omitting it, unless you are not confident it exists at all. '
    'Every opening\'s attachedBoundaryId MUST exactly match the id of one of the '
    'boundaries you reported — never invent an id that isn\'t in your own '
    'boundaries list.';

/// index.ts의 `RESPONSE_JSON_SCHEMA`와 구조가 동일해야 한다 — GPT에게
/// 요청하는 단순화된 중간 스키마(전부 이미지 전체 기준 0.0~1.0 정규화
/// 좌표). [VisionUnderstanding]의 깊은 중첩은 GPT에게 직접 맡기지 않고
/// [convertGptFloorplanIntermediateJson]이 결정론적으로 변환한다.
const Map<String, Object?> kGptFloorplanResponseJsonSchema = {
  'name': 'floorplan_understanding',
  'strict': true,
  'schema': {
    'type': 'object',
    'additionalProperties': false,
    'required': ['floorDomainPolygon', 'spaces', 'boundaries', 'openings', 'notes'],
    'properties': {
      'floorDomainPolygon': {
        'type': 'array',
        'description':
            '건물 외곽(exterior envelope) polygon 꼭짓점을 시계 또는 반시계 순서로, '
            '정규화 좌표(0.0~1.0)로 나열한다. 최소 3점.',
        'items': {
          'type': 'object',
          'additionalProperties': false,
          'required': ['x', 'y'],
          'properties': {
            'x': {'type': 'number'},
            'y': {'type': 'number'},
          },
        },
      },
      'spaces': {
        'type': 'array',
        'items': {
          'type': 'object',
          'additionalProperties': false,
          'required': ['id', 'label', 'semanticType', 'confidence', 'boundingBox'],
          'properties': {
            'id': {'type': 'string'},
            'label': {
              'type': ['string', 'null'],
              'description': '도면에 실제로 쓰인 이름이 보이면 그 텍스트, 없으면 null(지어내지 않는다).',
            },
            'semanticType': {
              'type': 'string',
              'enum': [
                'bedroomMaster', 'bedroom', 'living', 'kitchen', 'bathroom',
                'entrance', 'utility', 'pantry', 'balcony', 'mechanicalRoom',
                'corridor', 'unknown',
              ],
            },
            'confidence': {
              'type': 'string',
              'enum': ['high', 'medium', 'low', 'unknown'],
            },
            'boundingBox': {
              'type': 'object',
              'additionalProperties': false,
              'required': ['minX', 'minY', 'maxX', 'maxY'],
              'properties': {
                'minX': {'type': 'number'},
                'minY': {'type': 'number'},
                'maxX': {'type': 'number'},
                'maxY': {'type': 'number'},
              },
            },
          },
        },
      },
      'boundaries': {
        'type': 'array',
        'items': {
          'type': 'object',
          'additionalProperties': false,
          'required': ['id', 'boundaryType', 'confidence', 'start', 'end'],
          'properties': {
            'id': {'type': 'string'},
            'boundaryType': {
              'type': 'string',
              'enum': ['exteriorWall', 'interiorWall', 'virtualBoundary', 'unknown'],
            },
            'confidence': {
              'type': 'string',
              'enum': ['high', 'medium', 'low', 'unknown'],
            },
            'start': {
              'type': 'object',
              'additionalProperties': false,
              'required': ['x', 'y'],
              'properties': {
                'x': {'type': 'number'},
                'y': {'type': 'number'},
              },
            },
            'end': {
              'type': 'object',
              'additionalProperties': false,
              'required': ['x', 'y'],
              'properties': {
                'x': {'type': 'number'},
                'y': {'type': 'number'},
              },
            },
          },
        },
      },
      'openings': {
        'type': 'array',
        'items': {
          'type': 'object',
          'additionalProperties': false,
          'required': ['id', 'openingType', 'confidence', 'center', 'attachedBoundaryId'],
          'properties': {
            'id': {'type': 'string'},
            'openingType': {
              'type': 'string',
              'enum': ['door', 'window', 'openPassage'],
            },
            'confidence': {
              'type': 'string',
              'enum': ['high', 'medium', 'low', 'unknown'],
            },
            'center': {
              'type': 'object',
              'additionalProperties': false,
              'required': ['x', 'y'],
              'properties': {
                'x': {'type': 'number'},
                'y': {'type': 'number'},
              },
            },
            'attachedBoundaryId': {'type': 'string'},
          },
        },
      },
      'notes': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': '치수 텍스트가 안 보이는 등, 사용자가 알아야 할 불확실성/제약 사항.',
      },
    },
  },
};

/// [GptFloorplanEdgeFunctionVisionService]/[GptDirectOpenAiVisionService]가
/// 공유하는 data URI 변환 — PNG magic bytes만 검사하고 그 외는 JPEG로
/// 가정한다(기존 Edge Function 클라이언트 구현과 동일한 단순 판정).
String toGptFloorplanImageDataUri(Uint8List bytes) {
  final isPng = bytes.length >= 8 && bytes[0] == 137 && bytes[1] == 80 && bytes[2] == 78 && bytes[3] == 71;
  final mimeType = isPng ? 'image/png' : 'image/jpeg';
  return 'data:$mimeType;base64,${base64Encode(bytes)}';
}

/// OpenAI Chat Completions에 그대로 보낼 request body — [imageDataUri]만
/// 호출부가 채워 넣는다. index.ts의 `fetch(OPENAI_ENDPOINT, { body: ... })`
/// 와 필드 구성이 동일해야 한다.
Map<String, Object?> buildGptFloorplanOpenAiRequestBody(String imageDataUri) => {
  'model': kGptFloorplanOpenAiModel,
  'messages': [
    {'role': 'system', 'content': kGptFloorplanSystemPrompt},
    {
      'role': 'user',
      'content': [
        {'type': 'text', 'text': 'Analyze this floor plan image.'},
        {
          'type': 'image_url',
          'image_url': {'url': imageDataUri},
        },
      ],
    },
  ],
  'response_format': {'type': 'json_schema', 'json_schema': kGptFloorplanResponseJsonSchema},
  'max_tokens': 4096,
};

/// index.ts의 `toVisionUnderstanding()`을 그대로 옮긴 것 — GPT가 돌려준
/// 단순화된 중간 JSON([parsed], `kGptFloorplanResponseJsonSchema` 모양)을
/// [VisionUnderstanding.fromJson]이 읽을 수 있는 최종 계약 모양으로
/// 결정론적으로 바꾼다.
Map<String, Object?> convertGptFloorplanIntermediateJson(Map<String, Object?> parsed) {
  final floorDomainPoints = (parsed['floorDomainPolygon'] as List?) ?? const [];

  Map<String, Object?> toPointJson(Object? p) {
    final map = p as Map?;
    return {
      'x': (map?['x'] as num?)?.toDouble() ?? 0.0,
      'y': (map?['y'] as num?)?.toDouble() ?? 0.0,
    };
  }

  final spaces = (parsed['spaces'] as List?) ?? const [];
  final boundaries = (parsed['boundaries'] as List?) ?? const [];
  final openings = (parsed['openings'] as List?) ?? const [];
  final notes = (parsed['notes'] as List?) ?? const [];

  return {
    'floorDomain': {
      'id': 'floor-domain',
      'type': 'floorDomain',
      'confidence': floorDomainPoints.length >= 3 ? 'medium' : 'unknown',
      'source': 'vision',
      'geometryHint': floorDomainPoints.length >= 3
          ? {
              'kind': 'polygon',
              'points': [for (final p in floorDomainPoints) toPointJson(p)],
            }
          : null,
      'notes': const <String>[],
    },
    'spaces': [
      for (final raw in spaces)
        () {
          final s = raw as Map;
          return {
            'id': s['id'],
            'type': 'space',
            'confidence': s['confidence'] ?? 'unknown',
            'source': 'vision',
            'geometryHint': {
              'kind': 'boundingBox',
              'minX': (s['boundingBox'] as Map?)?['minX'],
              'minY': (s['boundingBox'] as Map?)?['minY'],
              'maxX': (s['boundingBox'] as Map?)?['maxX'],
              'maxY': (s['boundingBox'] as Map?)?['maxY'],
            },
            'notes': const <String>[],
            'label': s['label'],
            'semanticType': s['semanticType'] ?? 'unknown',
            'adjacentSpaceIds': const <String>[],
            'containedObjectIds': const <String>[],
          };
        }(),
    ],
    'boundaries': [
      for (final raw in boundaries)
        () {
          final b = raw as Map;
          return {
            'id': b['id'],
            'type': 'boundary',
            'confidence': b['confidence'] ?? 'unknown',
            'source': 'vision',
            'geometryHint': {
              'kind': 'segment',
              'start': toPointJson(b['start']),
              'end': toPointJson(b['end']),
            },
            'notes': const <String>[],
            'boundaryType': b['boundaryType'] ?? 'unknown',
            'adjacentSpaceIds': const <String>[],
          };
        }(),
    ],
    'openings': [
      for (final raw in openings)
        () {
          final o = raw as Map;
          return {
            'id': o['id'],
            'type': 'opening',
            'confidence': o['confidence'] ?? 'unknown',
            'source': 'vision',
            'geometryHint': {'kind': 'point', 'point': toPointJson(o['center'])},
            'notes': const <String>[],
            'openingType': o['openingType'] ?? 'door',
            'attachedBoundaryId': o['attachedBoundaryId'] is String ? o['attachedBoundaryId'] : null,
            'connectsSpaceIds': const <String>[],
          };
        }(),
    ],
    'objects': const <Object?>[],
    'structuralElements': const <Object?>[],
    'dimensions': const <Object?>[],
    'scaleConfirmed': false,
    'notes': [for (final n in notes) n],
  };
}
