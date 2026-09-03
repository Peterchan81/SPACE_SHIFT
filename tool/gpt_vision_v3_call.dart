// SPACE SHIFT — Canonical Wall Graph First POC.
//
// 독립 dev-side 스크립트. PASS A(전체 의미) → PASS B(하나의 공유
// corner/wall 그래프 — 13개 방을 각자 설명하지 않는다) → 필요 시
// PASS C(그래프 결함만 선택적 보수). 최대 3회.
//
// 실행: dart run tool/gpt_vision_v3_call.dart [--pass-c "<critique>"]
// 전제: OPENAI_API_KEY 환경변수가 이 프로세스에 설정되어 있어야 한다.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const String kRealImage2Path = r'C:\Users\user\Desktop\스크린샷\평면도1.PNG';
const String kOpenAiModel = 'gpt-4o';
const String kOpenAiEndpoint = 'https://api.openai.com/v1/chat/completions';

const String kSpaceLabels =
    '부부거실, 드레스룸, 욕실2, 주방/식당, 발코니, 펜트리, 현관, 욕실1, 실외기실, 안방, 거실, 침실2, 침실1';

const String kPassAPrompt = '''
당신은 건축 평면도 이미지를 CAD 재구성을 위해 분석하는 비전 모델입니다.
이번 단계(PASS A)의 목적은 전체 도면의 의미를 이해하는 것입니다.

이 이미지는 한국 아파트 평면도이며, 다음 13개 공간이 실제로 존재합니다:
$kSpaceLabels

이미지 크기는 443 x 300 픽셀입니다.

다음 JSON만 반환하세요:
{
  "spaces": [{"id": "S01", "label": "부부거실", "semanticType": "<string>", "confidence": <0..1>, "isExterior": <bool>}],
  "relationships": [{"spaceIdA": "S01", "spaceIdB": "S02", "relation": "adjacent|connectedByDoor|connectedByOpening"}],
  "majorExteriorNotes": "<건물 외곽의 주요 돌출/함몰부를 자연어로 간단히 설명>",
  "reviewReasons": []
}

id는 S01~S13처럼 이 순서대로: $kSpaceLabels
''';

String buildPassBPrompt(List<String> spaceIdsAndLabels) => '''
당신은 건축 평면도 이미지를 CAD 재구성을 위해 분석하는 비전 모델입니다.
이번 단계(PASS B)는 이전 방식과 다릅니다.

**DO NOT draw 13 independent room polygons.**
**Build ONE shared architectural wall graph for the entire floor plan.**
**Any wall shared by two rooms must exist exactly once — both rooms reference the same wall id.**

이미지 크기: 443 x 300 픽셀. 좌표는 이미지 픽셀 좌표(좌상단이 (0,0)).

13개 공간:
${spaceIdsAndLabels.join('\n')}

절차:
1. 먼저 건물 전체에서 실제로 존재하는 corner(벽의 방향이 바뀌거나 여러 벽이 만나는 지점)를 나열하세요. 같은 물리적 지점은 반드시 하나의 corner id만 사용하세요.
2. 그 corner들을 잇는 wall을 나열하세요. 안방과 거실 사이의 벽처럼 두 방이 공유하는 벽은 **정확히 하나의 wall id**로만 존재해야 하고, 그 wall의 adjacentSpaceIds에 두 공간의 id를 모두 넣으세요. 외벽은 안쪽 공간 하나만 adjacentSpaceIds에 넣으세요.
3. 각 공간은 자신을 감싸는 wall id 목록(boundaryWallIds)만 나열하세요 — 새 좌표를 만들지 마세요.

규칙:
- "각 방 최소 4벽" 같은 규칙은 없습니다 — 실제 벽만큼만 쓰세요.
- 가구/텍스트/문 스윙 호선/창문 세부선/기구/가구는 wall이 아닙니다.
- 실제 pixel evidence가 약한데 방을 닫기 위해 임의의 diagonal을 만들지 마세요 — 불확실하면 confidence를 낮추고 reviewReasons에 이유를 남기세요.
- 불확실해도 공간 자체를 빼지 마세요.

다음 JSON만 반환하세요:
{
  "corners": [{"id": "C001", "x": <num>, "y": <num>, "kind": "exteriorConvex|exteriorConcave|interiorJunction|tJunction|endpoint", "confidence": <0..1>}],
  "walls": [{"id": "W001", "startCornerId": "C001", "endCornerId": "C002", "type": "exterior|interior", "adjacentSpaceIds": ["S01","S02"], "confidence": <0..1>, "notes": ""}],
  "spaces": [{"id": "S01", "label": "부부거실", "semanticType": "<string>", "boundaryWallIds": ["W001","W018"], "confidence": <0..1>, "reviewReasons": []}]
}

반드시 13개 공간 전부(spaces 배열에 13개)를 포함하세요.
''';

String buildPassCPrompt(List<String> spaceIdsAndLabels, List<String> knownAdjacentPairs) => '''
당신은 건축 평면도 이미지를 CAD 재구성을 위해 분석하는 비전 모델입니다.
직전 응답은 건물 전체를 6개 벽, 7개 corner만으로 설명해 지나치게
부실했습니다(13개 방에 비해 명백히 부족).

이번에는 다음 두 요구를 동시에 만족하세요:

1. 13개 공간 각각에 대해, 그 공간을 실제로 완전히 둘러싸는 corner/wall을
   빠짐없이 나열하세요(작은 방도 최소 3~4개, 복잡한 방은 그 이상).
   즉 이미지에서 실제로 보이는 모든 구조벽을 사용하세요 — 이전처럼
   방 하나에 벽 1~2개만 배정하지 마세요.

2. 두 공간이 실제로 벽을 공유하면(특히 다음 알려진 인접 쌍들:
   ${knownAdjacentPairs.join(', ')}), 그 공유 벽에는 **정확히 같은
   wall id**를 두 공간의 boundaryWallIds에 함께 사용하고, 그 wall의
   adjacentSpaceIds에 두 공간 id를 모두 넣으세요. 같은 물리적 corner도
   마찬가지로 하나의 corner id만 재사용하세요.

13개 공간:
${spaceIdsAndLabels.join('\n')}

이미지 크기: 443 x 300 픽셀. 좌표는 이미지 픽셀 좌표(좌상단이 (0,0)).

규칙:
- 가구/텍스트/문 스윙 호선/창문 세부선/기구/가구는 wall이 아닙니다.
- 확신이 낮으면 confidence를 낮추되 공간 자체를 빼지 마세요.

다음 JSON만 반환하세요:
{
  "corners": [{"id": "C001", "x": <num>, "y": <num>, "kind": "exteriorConvex|exteriorConcave|interiorJunction|tJunction|endpoint", "confidence": <0..1>}],
  "walls": [{"id": "W001", "startCornerId": "C001", "endCornerId": "C002", "type": "exterior|interior", "adjacentSpaceIds": ["S01","S02"], "confidence": <0..1>, "notes": ""}],
  "spaces": [{"id": "S01", "label": "부부거실", "semanticType": "<string>", "boundaryWallIds": ["W001","W018","W019"], "confidence": <0..1>, "reviewReasons": []}]
}

반드시 13개 공간 전부를 포함하세요.
''';

Future<Map<String, dynamic>> _callOpenAi(String apiKey, String prompt, String base64Image) async {
  final response = await http.post(
    Uri.parse(kOpenAiEndpoint),
    headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $apiKey'},
    body: jsonEncode({
      'model': kOpenAiModel,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
            {
              'type': 'image_url',
              'image_url': {'url': 'data:image/png;base64,$base64Image'},
            },
          ],
        },
      ],
      'response_format': {'type': 'json_object'},
      'max_tokens': 8000,
    }),
  );
  if (response.statusCode != 200) {
    throw Exception('API call FAILED: HTTP ${response.statusCode}\n${response.body}');
  }
  return jsonDecode(response.body) as Map<String, dynamic>;
}

Future<void> main(List<String> args) async {
  final apiKey = Platform.environment['OPENAI_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    stderr.writeln('OPENAI_API_KEY: NOT SET — aborting.');
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
  stdout.writeln('Loaded actual Image 2: ${imageBytes.lengthInBytes} bytes');

  final captureDir = Directory('lib/vision_cad_poc/gpt_vision_v3/captured');
  if (!captureDir.existsSync()) captureDir.createSync(recursive: true);

  final usageLogFile = File('${captureDir.path}/usage_log.json');
  final usageLog = usageLogFile.existsSync()
      ? ((jsonDecode(usageLogFile.readAsStringSync()) as Map<String, dynamic>)['calls'] as List).cast<Map<String, dynamic>>()
      : <Map<String, dynamic>>[];

  void saveUsageLog() {
    usageLogFile.writeAsStringSync(jsonEncode({
      'model': kOpenAiModel,
      'timestamp': DateTime.now().toIso8601String(),
      'imagePath': kRealImage2Path,
      'imageBytes': imageBytes.lengthInBytes,
      'calls': usageLog,
    }));
  }

  if (args.contains('--pass-c')) {
    final passAJson = jsonDecode(File('${captureDir.path}/pass_a.json').readAsStringSync()) as Map<String, dynamic>;
    final passASpaces = (passAJson['spaces'] as List).cast<Map<String, dynamic>>();
    final spaceIdsAndLabels = [for (final s in passASpaces) '${s['id']}: ${s['label']}'];
    final relationships = (passAJson['relationships'] as List? ?? const []).cast<Map<String, dynamic>>();
    final knownAdjacentPairs = [for (final r in relationships) '${r['spaceIdA']}-${r['spaceIdB']}'];

    stdout.writeln('--- PASS C (model=$kOpenAiModel) ---');
    final passCResponse = await _callOpenAi(apiKey, buildPassCPrompt(spaceIdsAndLabels, knownAdjacentPairs), base64Image);
    final passCUsage = passCResponse['usage'] as Map<String, dynamic>?;
    stdout.writeln('PASS C prompt_tokens=${passCUsage?['prompt_tokens']} completion_tokens=${passCUsage?['completion_tokens']}');
    usageLog.add({'pass': 'C', 'usage': passCUsage});
    final passCContent = (passCResponse['choices'] as List).first['message']['content'] as String;
    File('${captureDir.path}/pass_b_repaired.json').writeAsStringSync(passCContent);
    stdout.writeln('Saved PASS C response to ${captureDir.path}/pass_b_repaired.json');
    saveUsageLog();
    stdout.writeln('DONE. Total calls so far: ${usageLog.length}');
    return;
  }

  // ---- PASS A ----
  stdout.writeln('--- PASS A (model=$kOpenAiModel) ---');
  final passAResponse = await _callOpenAi(apiKey, kPassAPrompt, base64Image);
  final passAUsage = passAResponse['usage'] as Map<String, dynamic>?;
  stdout.writeln('PASS A prompt_tokens=${passAUsage?['prompt_tokens']} completion_tokens=${passAUsage?['completion_tokens']}');
  usageLog.add({'pass': 'A', 'usage': passAUsage});
  final passAContent = (passAResponse['choices'] as List).first['message']['content'] as String;
  File('${captureDir.path}/pass_a.json').writeAsStringSync(passAContent);
  stdout.writeln('Saved PASS A response to ${captureDir.path}/pass_a.json');

  final passAJson = jsonDecode(passAContent) as Map<String, dynamic>;
  final spaces = (passAJson['spaces'] as List).cast<Map<String, dynamic>>();
  final spaceIdsAndLabels = [for (final s in spaces) '${s['id']}: ${s['label']}'];
  stdout.writeln('PASS A spaces: ${spaces.length}');

  // ---- PASS B ----
  stdout.writeln('--- PASS B (model=$kOpenAiModel) ---');
  final passBResponse = await _callOpenAi(apiKey, buildPassBPrompt(spaceIdsAndLabels), base64Image);
  final passBUsage = passBResponse['usage'] as Map<String, dynamic>?;
  stdout.writeln('PASS B prompt_tokens=${passBUsage?['prompt_tokens']} completion_tokens=${passBUsage?['completion_tokens']}');
  usageLog.add({'pass': 'B', 'usage': passBUsage});
  final passBContent = (passBResponse['choices'] as List).first['message']['content'] as String;
  File('${captureDir.path}/pass_b.json').writeAsStringSync(passBContent);
  stdout.writeln('Saved PASS B response to ${captureDir.path}/pass_b.json');

  saveUsageLog();
  stdout.writeln('DONE. Total calls: ${usageLog.length}');
}
