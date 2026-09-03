// SPACE SHIFT — GPT Space Boundary Loop Recovery POC.
//
// 독립 dev-side 스크립트. PASS A(전체 의미 이해) → PASS B(공간별 완전
// 순서 경계) 순서로 실제 OpenAI Vision API를 호출해 raw JSON을
// 파일로 저장한다. 최대 3회(A=1, B=1, C=실패 시 최대 1)까지만 호출.
//
// 실행: dart run tool/gpt_vision_v2_call.dart [--pass-c "<critique>"]
// 전제: OPENAI_API_KEY 환경변수가 이 프로세스에 설정되어 있어야 한다.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const String kRealImage2Path = r'C:\Users\user\Desktop\스크린샷\평면도1.PNG';
const String kOpenAiModel = 'gpt-4o';
const String kOpenAiEndpoint = 'https://api.openai.com/v1/chat/completions';

const String kSpaceLabels = '''
부부거실, 드레스룸, 욕실2, 주방/식당, 발코니, 펜트리, 현관, 욕실1, 실외기실, 안방, 거실, 침실2, 침실1
''';

const String kPassAPrompt = '''
당신은 건축 평면도 이미지를 CAD 재구성을 위해 분석하는 비전 모델입니다.
이번 단계(PASS A)의 목적은 전체 도면의 의미를 이해하는 것입니다 — 정밀한 벽 좌표는 다음 단계(PASS B)에서 다룹니다.

이 이미지는 한국 아파트 평면도이며, 다음 13개 공간이 실제로 존재합니다:
$kSpaceLabels

이미지 크기는 443 x 300 픽셀입니다.

다음 JSON만 반환하세요(다른 텍스트 없이):
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
이번 단계(PASS B)는 오직 공간 경계(boundary)만 다룹니다 — 목표는 "각 공간마다 완전한, 순서가 있는 닫힌 경계"를 만드는 것입니다.

이미지 크기: 443 x 300 픽셀. 좌표는 이미지 픽셀 좌표(좌상단이 (0,0))를 사용하세요.

다음 13개 공간 각각에 대해 독립적으로 경계를 설명하세요:
${spaceIdsAndLabels.join('\n')}

매우 중요한 규칙:
- 각 공간마다, 그 공간을 완전히 둘러싸는 변(segment)들을 실제 벽을 따라 시계 방향(또는 반시계 방향, 일관되게)으로 순서대로 나열하세요.
- 각 segment의 끝점(end)은 반드시 다음 segment의 시작점(start)과 같은 실제 위치를 가리켜야 합니다. 마지막 segment의 end는 첫 segment의 start로 돌아와야 합니다(닫힌 루프).
- 다른 공간과 공유하는 벽이면 sharedWithSpaceId에 그 공간의 id를 적으세요. 같은 벽을 그 이웃 공간 쪽에서도 각자 다시 설명해도 됩니다 — 정확히 같은 좌표일 필요는 없습니다.
- "각 방은 최소 4개 벽" 같은 규칙은 없습니다 — L자형이나 복합 형태면 필요한 만큼 segment를 쓰세요. 하지만 반드시 완전히 닫혀야 합니다.
- kind는 "wall"(구조벽), "opening"(문/트인 통로), "exterior"(건물 외곽과 접하는 변) 중 하나입니다.
- 가구, 텍스트, 문 스윙 호선, 창문 세부선, 욕실 기구, 주방 가구는 segment로 만들지 마세요.
- 불확실하면 confidence를 낮게 표시하세요. 확신이 낮다고 공간 자체를 빼지 마세요.

다음 JSON만 반환하세요(다른 텍스트 없이):
{
  "spaceBoundaryLoops": [
    {
      "spaceId": "S01",
      "segments": [
        {"id": "SB001", "start": {"x": <num>, "y": <num>}, "end": {"x": <num>, "y": <num>}, "kind": "wall|opening|exterior", "sharedWithSpaceId": "<id 또는 null>", "confidence": <0..1>}
      ],
      "closed": true,
      "confidence": <0..1>,
      "reviewReasons": []
    }
  ]
}
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

String buildPassCPrompt(List<String> missingSpaceIdsAndLabels) => '''
당신은 건축 평면도 이미지를 CAD 재구성을 위해 분석하는 비전 모델입니다.
직전 요청에서 13개 공간 중 일부만 응답했습니다. 이번에는 **오직 다음
공간들만** 같은 방식으로 완전한 순서 있는 경계를 만드세요(이미 완료된
공간은 다시 만들 필요 없습니다):

${missingSpaceIdsAndLabels.join('\n')}

이미지 크기: 443 x 300 픽셀. 좌표는 이미지 픽셀 좌표(좌상단이 (0,0)).

규칙(동일):
- 각 공간을 완전히 둘러싸는 변을 실제 벽을 따라 순서대로 나열. 마지막
  segment의 end는 첫 segment의 start로 돌아와야 합니다(닫힌 루프).
- 이웃 공간과 공유하는 벽은 sharedWithSpaceId에 그 공간 id 표시.
- kind는 "wall"|"opening"|"exterior".
- 가구/텍스트/문 스윙 호선/창문 세부선/기구/가구는 제외.

다음 JSON만 반환하세요:
{
  "spaceBoundaryLoops": [
    {"spaceId": "S05", "segments": [...], "closed": true, "confidence": <0..1>, "reviewReasons": []}
  ]
}

반드시 요청된 공간 전부(${missingSpaceIdsAndLabels.length}개)를 포함하세요.
''';

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

  final captureDir = Directory('lib/vision_cad_poc/gpt_vision_v2/captured');
  if (!captureDir.existsSync()) captureDir.createSync(recursive: true);

  final usageLogFile = File('${captureDir.path}/usage_log.json');
  final usageLog = usageLogFile.existsSync()
      ? ((jsonDecode(usageLogFile.readAsStringSync()) as Map<String, dynamic>)['calls'] as List).cast<Map<String, dynamic>>()
      : <Map<String, dynamic>>[];

  if (args.contains('--pass-c')) {
    // §11 PASS C — 실패한(누락된) space만 대상으로 최대 1회 추가 호출.
    final passAJson = jsonDecode(File('${captureDir.path}/pass_a.json').readAsStringSync()) as Map<String, dynamic>;
    final allSpaces = (passAJson['spaces'] as List).cast<Map<String, dynamic>>();
    final passBJson = jsonDecode(File('${captureDir.path}/pass_b.json').readAsStringSync()) as Map<String, dynamic>;
    final coveredIds = (passBJson['spaceBoundaryLoops'] as List)
        .cast<Map<String, dynamic>>()
        .map((e) => e['spaceId'] as String)
        .toSet();
    final missing = [for (final s in allSpaces) if (!coveredIds.contains(s['id'])) '${s['id']}: ${s['label']}'];
    if (missing.isEmpty) {
      stdout.writeln('No missing spaces — PASS C not needed.');
      return;
    }
    stdout.writeln('--- PASS C (model=$kOpenAiModel) — missing: ${missing.join(", ")} ---');
    final passCPrompt = buildPassCPrompt(missing);
    final passCResponse = await _callOpenAi(apiKey, passCPrompt, base64Image);
    final passCUsage = passCResponse['usage'] as Map<String, dynamic>?;
    stdout.writeln('PASS C prompt_tokens=${passCUsage?['prompt_tokens']} completion_tokens=${passCUsage?['completion_tokens']}');
    usageLog.add({'pass': 'C', 'usage': passCUsage});
    final passCContent = (passCResponse['choices'] as List).first['message']['content'] as String;
    File('${captureDir.path}/pass_c.json').writeAsStringSync(passCContent);
    stdout.writeln('Saved PASS C response to ${captureDir.path}/pass_c.json');

    usageLogFile.writeAsStringSync(jsonEncode({
      'model': kOpenAiModel,
      'timestamp': DateTime.now().toIso8601String(),
      'imagePath': kRealImage2Path,
      'imageBytes': imageBytes.lengthInBytes,
      'calls': usageLog,
    }));
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
  final passBPrompt = buildPassBPrompt(spaceIdsAndLabels);
  final passBResponse = await _callOpenAi(apiKey, passBPrompt, base64Image);
  final passBUsage = passBResponse['usage'] as Map<String, dynamic>?;
  stdout.writeln('PASS B prompt_tokens=${passBUsage?['prompt_tokens']} completion_tokens=${passBUsage?['completion_tokens']}');
  usageLog.add({'pass': 'B', 'usage': passBUsage});
  final passBContent = (passBResponse['choices'] as List).first['message']['content'] as String;
  File('${captureDir.path}/pass_b.json').writeAsStringSync(passBContent);
  stdout.writeln('Saved PASS B response to ${captureDir.path}/pass_b.json');

  usageLogFile.writeAsStringSync(jsonEncode({
    'model': kOpenAiModel,
    'timestamp': DateTime.now().toIso8601String(),
    'imagePath': kRealImage2Path,
    'imageBytes': imageBytes.lengthInBytes,
    'calls': usageLog,
  }));
  stdout.writeln('DONE. Total calls: ${usageLog.length}');
}
