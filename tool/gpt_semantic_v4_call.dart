// SPACE SHIFT — Vision-Guided Full Pixel Wall Extraction POC.
//
// 독립 dev-side 스크립트. GPT는 이번에는 wall/corner 좌표를 단 하나도
// 만들지 않는다 — WHAT(라벨)/RELATIONSHIP(인접)/WHERE TO LOOK(대략
// ROI)만 담당한다("ss-cad-semantic-v4"). 실제 geometry는
// pixel_wall_extractor.dart가 이미지에서 직접 뽑는다.
//
// 예산: 최대 2회(기본 호출 1회 + --clarify 로 선택적 보정 1회).
//
// 실행: dart run tool/gpt_semantic_v4_call.dart [--clarify "<critique>"]
// 전제: OPENAI_API_KEY 환경변수가 이 프로세스에 설정되어 있어야 한다.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const String kRealImage2Path = r'C:\Users\user\Desktop\스크린샷\평면도1.PNG';
const String kOpenAiModel = 'gpt-4o';
const String kOpenAiEndpoint = 'https://api.openai.com/v1/chat/completions';
const String kCaptureDirPath = 'lib/vision_cad_poc/pixel_wall_v4/captured';

const String kSpaceLabels =
    '부부거실, 드레스룸, 욕실2, 주방/식당, 발코니, 펜트리, 현관, 욕실1, 실외기실, 안방, 거실, 침실2, 침실1';

const String kBasePrompt = '''
당신은 건축 평면도 이미지를 분석하는 비전 모델입니다. 이번 작업에서
당신의 역할은 이전과 완전히 다릅니다:

**당신은 벽/코너의 좌표를 단 하나도 만들지 않습니다.** 실제 벽 geometry는
별도의 이미지 픽셀 분석 알고리즘이 이 이미지에서 직접 추출합니다. 당신은
오직 다음만 답합니다:
1. WHAT — 각 공간이 무엇인지(라벨/용도)
2. RELATIONSHIP — 어느 공간과 어느 공간이 인접한지
3. WHERE TO LOOK — 각 공간이 이미지의 대략 어느 영역에 있는지(정확한
   벽 경계가 아니라 "이 근처를 보라"는 대략적인 탐색 힌트일 뿐입니다)
4. 외부와 맞닿는 방향, 문/창 대략 위치, 가구로 보이는 영역, 애매한 영역

이미지는 한국 아파트 평면도이며, 다음 13개 공간이 실제로 존재합니다:
$kSpaceLabels

좌표는 모두 정규화(0.0~1.0, 좌상단이 (0,0), 우하단이 (1,1)) bounding
box로만 답하세요 — 정밀한 벽 좌표가 아니라 대략적인 사각 영역입니다.

다음 JSON만 반환하세요:
{
  "spaces": [
    {
      "id": "S01",
      "label": "부부거실",
      "semanticType": "<string>",
      "approxRegion": {"x0": 0.0, "y0": 0.0, "x1": 1.0, "y1": 1.0},
      "neighborSpaceIds": ["S02"],
      "exteriorSides": ["top","left"]
    }
  ],
  "openings": [
    {"type": "door|window", "approxRegion": {"x0":0,"y0":0,"x1":1,"y1":1}, "adjacentSpaceId": "S01"}
  ],
  "furnitureRegions": [
    {"approxRegion": {"x0":0,"y0":0,"x1":1,"y1":1}, "note": "침대로 보임"}
  ],
  "ambiguousRegions": [
    {"approxRegion": {"x0":0,"y0":0,"x1":1,"y1":1}, "note": "구조가 불명확함"}
  ]
}

반드시 13개 공간 전부(spaces 배열에 13개)를 포함하세요. exteriorSides는
"top"/"bottom"/"left"/"right" 중 해당하는 것만 배열로 넣으세요(외부와
전혀 안 닿으면 빈 배열).
''';

String buildClarifyPrompt(String critique) => '''
당신은 건축 평면도 이미지를 분석하는 비전 모델입니다. 직전 응답에 대한
구체적인 보정 요청이 있습니다 — 전체를 다시 만들지 말고, 아래에서 지목한
문제만 고쳐서 같은 형식의 전체 JSON을 다시 반환하세요.

보정 요청:
$critique

이미지는 한국 아파트 평면도이며, 다음 13개 공간이 실제로 존재합니다:
$kSpaceLabels

당신은 여전히 벽/코너 좌표를 만들지 않습니다 — approxRegion은 정규화
(0.0~1.0) 대략 bounding box일 뿐입니다.

다음 JSON만 반환하세요(형식은 첫 호출과 동일):
{
  "spaces": [{"id":"S01","label":"부부거실","semanticType":"<string>","approxRegion":{"x0":0,"y0":0,"x1":1,"y1":1},"neighborSpaceIds":["S02"],"exteriorSides":["top"]}],
  "openings": [{"type":"door|window","approxRegion":{"x0":0,"y0":0,"x1":1,"y1":1},"adjacentSpaceId":"S01"}],
  "furnitureRegions": [{"approxRegion":{"x0":0,"y0":0,"x1":1,"y1":1},"note":""}],
  "ambiguousRegions": [{"approxRegion":{"x0":0,"y0":0,"x1":1,"y1":1},"note":""}]
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
      'max_tokens': 4000,
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

  final captureDir = Directory(kCaptureDirPath);
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

  if (usageLog.length >= 2) {
    stderr.writeln('예산 초과 방지: 이미 ${usageLog.length}회 호출됨(최대 2회). 중단.');
    exitCode = 4;
    return;
  }

  final clarifyIndex = args.indexOf('--clarify');
  if (clarifyIndex != -1) {
    final critique = args.length > clarifyIndex + 1 ? args[clarifyIndex + 1] : '';
    if (critique.isEmpty) {
      stderr.writeln('--clarify 뒤에 구체적인 보정 요청 문자열이 필요합니다.');
      exitCode = 5;
      return;
    }
    stdout.writeln('--- CLARIFY CALL (model=$kOpenAiModel) ---');
    final response = await _callOpenAi(apiKey, buildClarifyPrompt(critique), base64Image);
    final usage = response['usage'] as Map<String, dynamic>?;
    stdout.writeln('CLARIFY prompt_tokens=${usage?['prompt_tokens']} completion_tokens=${usage?['completion_tokens']}');
    usageLog.add({'call': 'clarify', 'usage': usage});
    final content = (response['choices'] as List).first['message']['content'] as String;
    File('${captureDir.path}/semantic_v4.json').writeAsStringSync(content);
    stdout.writeln('Saved CLARIFY response to ${captureDir.path}/semantic_v4.json (덮어씀)');
    saveUsageLog();
    stdout.writeln('DONE. Total calls so far: ${usageLog.length}/2');
    return;
  }

  stdout.writeln('--- BASE CALL (model=$kOpenAiModel) ---');
  final response = await _callOpenAi(apiKey, kBasePrompt, base64Image);
  final usage = response['usage'] as Map<String, dynamic>?;
  stdout.writeln('BASE prompt_tokens=${usage?['prompt_tokens']} completion_tokens=${usage?['completion_tokens']}');
  usageLog.add({'call': 'base', 'usage': usage});
  final content = (response['choices'] as List).first['message']['content'] as String;
  File('${captureDir.path}/semantic_v4.json').writeAsStringSync(content);
  stdout.writeln('Saved BASE response to ${captureDir.path}/semantic_v4.json');

  saveUsageLog();
  stdout.writeln('DONE. Total calls: ${usageLog.length}/2');
}
