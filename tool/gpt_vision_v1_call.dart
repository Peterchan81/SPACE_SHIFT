// SPACE SHIFT — PC1 FINAL REAL GPT VISION E2E.
//
// 독립 dev-side 스크립트(Flutter 앱 소스/바이너리에 포함되지 않음).
// 실제 "이미지 2" 원본을 OpenAI Vision API에 보내 ss-cad-vision-v1
// Detailed CAD JSON을 받아 파일로 저장한다.
//
// 실행: dart run tool/gpt_vision_v1_call.dart
// 전제: OPENAI_API_KEY 환경변수가 이 프로세스에 설정되어 있어야 한다.
//       (값은 이 스크립트 어디에도 출력하지 않는다.)
//
// 이 스크립트는 API 키를 코드/설정 파일에 저장하지 않는다 — 오직
// Platform.environment에서만 읽는다.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const String kRealImage2Path = r'C:\Users\user\Desktop\스크린샷\평면도1.PNG';
const String kOpenAiModel = 'gpt-4o';
const String kOpenAiEndpoint = 'https://api.openai.com/v1/chat/completions';

const String kSchemaPrompt = '''
당신은 건축 평면도 이미지를 실제 편집 가능한 CAD로 재구성하기 위해 분석하는 비전 모델입니다.
목적은 예쁜 그림 생성이 아니라 구조화된 geometry 생성입니다.

이 이미지는 한국 아파트 평면도이며, 다음 13개 공간이 실제로 존재합니다(모두 유지하세요, 임의로 삭제하지 마세요):
부부거실, 드레스룸, 욕실2, 주방/식당, 발코니, 펜트리, 현관, 욕실1, 실외기실, 안방, 거실, 침실2, 침실1

이미지 크기: 443 x 300 정도의 작은 해상도입니다. 좌표는 이 이미지의 실제 픽셀 좌표(좌상단이 (0,0))를 사용하세요.

반드시 지킬 것:
- 실제 구조적(structural) 벽만 wall로 취급하세요. 가구, 텍스트, 문 스윙 호선, 창문 세부선, 욕실 기구, 주방 가구/수납장은 wall이 아닙니다.
- 모든 주요 exterior 돌출부/함몰부(예: 발코니 돌출, 실외기실 돌출)를 보존하세요. FloorDomain을 단순 직사각형으로 만들지 마세요.
- FloorDomain의 orderedCornerIds는 건물 외곽을 실제 순서대로(한 방향으로 한 바퀴) 나열해야 합니다. 자기교차하거나 실제로 존재하지 않는 긴 대각선 연결을 만들지 마세요.
- 각 space의 boundaryWallIds가 참조하는 wall들을 순서 없이 나열해도 되지만, 그 wall들의 cornerIds를 모두 변(edge)으로 풀었을 때 반드시 "정확히 하나의 단순 닫힌 루프"를 이루어야 합니다 — 즉 그 공간의 경계에 나온 모든 corner는 정확히 2개의 변에만 연결되어야 합니다. 방을 감싸는 벽만 정확히 나열하세요.
- 불확실하면 confidence를 낮게 표시하세요(0.0~1.0). 확신이 낮다고 entity 자체를 삭제하지 말고 confidence만 낮추세요.
- 이 도면에는 인쇄된 실측 치수가 없습니다 — dimensionHints는 빈 배열로 두고 mm/㎡ 값을 만들어내지 마세요.
- 오직 JSON만 반환하세요. JSON 외의 설명 텍스트를 포함하지 마세요.

다음 JSON 스키마(schemaVersion "ss-cad-vision-v1")를 정확히 따르세요:

{
  "schemaVersion": "ss-cad-vision-v1",
  "image": {"widthPx": <int>, "heightPx": <int>, "coordinateSystem": "top-left-pixel", "scaleStatus": "unknown"},
  "floorDomain": {"orderedCornerIds": ["C..."], "confidence": <0..1>},
  "corners": [{"id": "C1", "x": <double>, "y": <double>, "kind": "exteriorConvex"|"exteriorConcave"|"interiorJunction"|"tJunction"|"endpoint", "confidence": <0..1>, "notes": "<string, optional>"}],
  "walls": [{"id": "W1", "type": "exterior"|"interior", "cornerIds": ["C1","C2", ...], "thicknessPxHint": <double, optional>, "confidence": <0..1>, "notes": "<string, optional>"}],
  "spaces": [{"id": "S1", "label": "<한글 공간명>", "semanticType": "<string>", "boundaryWallIds": ["W1", ...], "confidence": <0..1>, "reviewReasons": ["..."]}],
  "doors": [{"id": "D1", "hostWallId": "W1", "startT": <0..1>, "endT": <0..1>, "connectsSpaceIds": ["S1","S2"], "swingDirection": "<string, optional>", "confidence": <0..1>}],
  "windows": [{"id": "WIN1", "hostWallId": "W1", "startT": <0..1>, "endT": <0..1>, "confidence": <0..1>}],
  "openings": [{"id": "O1", "hostWallId": "W1", "startT": <0..1>, "endT": <0..1>, "connectsSpaceIds": ["S1","S2"], "confidence": <0..1>}],
  "objects": [{"id": "OBJ1", "type": "<string>", "bboxPx": [x1,y1,x2,y2], "containingSpaceId": "S1", "confidence": <0..1>}],
  "relationships": [{"entityA": "S1", "entityB": "S2", "relation": "adjacent"|"connectedByDoor"|"connectedByOpening"|"contains"|"hostedBy"}],
  "dimensionHints": [],
  "reviewReasons": []
}

모든 id는 전체 문서 안에서 고유해야 합니다(corner/wall/space/door/window/opening/object가 서로 다른 id 이름공간을 공유합니다).
startT/endT는 hostWall의 첫 corner(0.0)부터 마지막 corner(1.0) 사이의 상대 위치입니다.
''';

/// §13 — "JSON contract 복구 요청은 최대 1회만 허용". run1의 진단
/// 결과(모든 space가 외곽 벽만 참조해 wall topology loop 유도에
/// 실패함)를 바탕으로 한 구체적 critique.
const String kCorrectiveCritique = '''
직전 응답을 실제로 파싱/검증해 보니 중요한 문제가 있습니다.

당신이 준 walls는 건물 외곽(exterior) 10개뿐이고, 13개 공간을 서로
나누는 실제 내부 칸막이 벽(interior wall)이 전혀 없습니다. 그 결과
모든 space의 boundaryWallIds가 외곽 벽 2~3개만 참조하고 있어서, 각
공간의 경계를 실제로 감싸는 "닫힌 루프"를 전혀 만들 수 없었습니다
(모든 공간이 서로 극심하게 겹치는 잘못된 결과가 나왔습니다).

이미지를 다시 자세히 보고, 다음을 반드시 포함해 처음부터 다시
JSON을 생성하세요:

1. 13개 공간을 서로 나누는 실제 내부 칸막이 벽(interior wall)을
   corners/walls에 명시적으로 추가하세요. 예: 안방과 거실 사이,
   드레스룸과 부부거실 사이, 욕실1/욕실2와 인접 공간 사이 등 이미지에
   실제로 보이는 모든 내부 벽선.

2. 각 space의 boundaryWallIds가 참조하는 wall들의 cornerIds를 전부
   변(edge)으로 풀었을 때, 반드시 정확히 하나의 단순 닫힌 루프를
   이루어야 합니다 — 그 공간의 경계에 등장하는 모든 corner는 정확히
   2개의 변에만 연결되어야 합니다(외곽 벽 + 내부 칸막이 벽을 함께
   사용해서 각 방을 완전히 둘러싸세요).

3. 같은 물리적 위치를 나타내는 corner는 여러 wall에서 같은 id로
   재사용하세요(예: 벽 A와 벽 B가 만나는 지점은 하나의 corner id를
   공유해야 두 벽이 그 지점에서 실제로 연결됩니다).

이전과 동일한 스키마(schemaVersion "ss-cad-vision-v1")를 그대로
따르고, 오직 JSON만 반환하세요.
''';

Future<void> main(List<String> args) async {
  final apiKey = Platform.environment['OPENAI_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    stderr.writeln('OPENAI_API_KEY: NOT SET — aborting. (value is never printed by this script)');
    exitCode = 2;
    return;
  }
  stdout.writeln('OPENAI_API_KEY: SET');

  final imageFile = File(kRealImage2Path);
  if (!imageFile.existsSync()) {
    stderr.writeln('ACTUAL IMAGE 2 NOT FOUND at $kRealImage2Path');
    exitCode = 3;
    return;
  }
  final imageBytes = imageFile.readAsBytesSync();
  final base64Image = base64Encode(imageBytes);
  stdout.writeln('Loaded actual Image 2: ${imageBytes.lengthInBytes} bytes from $kRealImage2Path');

  final captureDir = Directory('lib/vision_cad_poc/gpt_vision_v1/captured');
  if (!captureDir.existsSync()) captureDir.createSync(recursive: true);

  final isRetry = args.contains('--retry');
  final attempt = isRetry ? 2 : 1;

  final messages = <Map<String, dynamic>>[
    {
      'role': 'user',
      'content': [
        {'type': 'text', 'text': kSchemaPrompt},
        {
          'type': 'image_url',
          'image_url': {'url': 'data:image/png;base64,$base64Image'},
        },
      ],
    },
  ];

  if (isRetry) {
    final prevRaw = File('${captureDir.path}/image2_run1.json').readAsStringSync();
    messages.add({'role': 'assistant', 'content': prevRaw});
    messages.add({'role': 'user', 'content': kCorrectiveCritique});
  }

  stdout.writeln('--- OpenAI Vision API call #$attempt (model=$kOpenAiModel)${isRetry ? " [CORRECTIVE RETRY]" : ""} ---');
  final response = await http.post(
    Uri.parse(kOpenAiEndpoint),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
    },
    body: jsonEncode({
      'model': kOpenAiModel,
      'messages': messages,
      'response_format': {'type': 'json_object'},
      'max_tokens': 8000,
    }),
  );

  if (response.statusCode != 200) {
    stderr.writeln('API call #$attempt FAILED: HTTP ${response.statusCode}');
    stderr.writeln(response.body);
    exitCode = 4;
    return;
  }

  final responseJson = jsonDecode(response.body) as Map<String, dynamic>;
  final usage = responseJson['usage'] as Map<String, dynamic>?;
  stdout.writeln('prompt_tokens: ${usage?['prompt_tokens']}');
  stdout.writeln('completion_tokens: ${usage?['completion_tokens']}');
  stdout.writeln('total_tokens: ${usage?['total_tokens']}');

  final content = (responseJson['choices'] as List).first['message']['content'] as String;

  final rawFile = File('${captureDir.path}/image2_run$attempt.json');
  rawFile.writeAsStringSync(content);
  stdout.writeln('Saved raw GPT response to ${rawFile.path}');

  final metaFile = File('${captureDir.path}/image2_run${attempt}_meta.json');
  metaFile.writeAsStringSync(jsonEncode({
    'model': kOpenAiModel,
    'timestamp': DateTime.now().toIso8601String(),
    'imagePath': kRealImage2Path,
    'imageBytes': imageBytes.lengthInBytes,
    'attempt': attempt,
    'isCorrectiveRetry': isRetry,
    'usage': responseJson['usage'],
  }));
  stdout.writeln('Saved metadata to ${metaFile.path}');
  stdout.writeln('DONE.');
}
