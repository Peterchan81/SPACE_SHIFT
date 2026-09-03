// SPACE SHIFT — Real GPT Vision → Detailed CAD JSON → SS Refinement POC.
//
// 파이프라인 전체(파싱→검증→refinement→topology→canonical model) 통합
// 테스트. auth-missing 경로는 실제로 예외가 나는지, 정상 경로는 실제
// 이미지 2에 대해 canonical SSSpatialModel이 만들어지는지 확인한다.
// JSON 자체는 파서/솔버를 통과시키기 위한 테스트 데이터이며 실제 GPT
// 응답이 아니다.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/vision_cad_poc/e2e_v2/real_image2_source.dart';
import 'package:ason_space/vision_cad_poc/gpt_vision_v1/gpt_cad_pipeline.dart';
import 'package:ason_space/vision_cad_poc/gpt_vision_v1/gpt_vision_api_service.dart';

class _AuthMissingService implements GptVisionApiService {
  const _AuthMissingService();
  @override
  Future<String> requestCadJson(Uint8List imageBytes) => const OpenAiGptVisionApiService().requestCadJson(imageBytes);
}

Map<String, dynamic> _testJson() => {
      'schemaVersion': 'ss-cad-vision-v1',
      'image': {'widthPx': 443, 'heightPx': 301, 'coordinateSystem': 'top-left-pixel', 'scaleStatus': 'unknown'},
      'floorDomain': {
        'orderedCornerIds': ['C1', 'C2', 'C3', 'C4'],
        'confidence': 0.9,
      },
      'corners': [
        // 실제 안방|거실 벽(x≈0.358) 부근을 사각형 형태로 근사 — e2e_v3에서 검증된 좌표 재사용.
        {'id': 'C1', 'x': 0.358 * 443, 'y': 0.573 * 301, 'kind': 'interiorJunction', 'confidence': 0.85},
        {'id': 'C2', 'x': 0.598 * 443, 'y': 0.573 * 301, 'kind': 'interiorJunction', 'confidence': 0.85},
        {'id': 'C3', 'x': 0.598 * 443, 'y': 0.930 * 301, 'kind': 'interiorJunction', 'confidence': 0.85},
        {'id': 'C4', 'x': 0.358 * 443, 'y': 0.930 * 301, 'kind': 'interiorJunction', 'confidence': 0.85},
      ],
      'walls': [
        {'id': 'W1', 'type': 'interior', 'cornerIds': ['C1', 'C2'], 'confidence': 0.85},
        {'id': 'W2', 'type': 'interior', 'cornerIds': ['C2', 'C3'], 'confidence': 0.85},
        {'id': 'W3', 'type': 'interior', 'cornerIds': ['C3', 'C4'], 'confidence': 0.85},
        {'id': 'W4', 'type': 'interior', 'cornerIds': ['C4', 'C1'], 'confidence': 0.85},
      ],
      'spaces': [
        {
          'id': 'S1',
          'label': '거실',
          'semanticType': 'living',
          'boundaryWallIds': ['W1', 'W2', 'W3', 'W4'],
          'confidence': 0.9,
        },
      ],
      'doors': [
        {
          'id': 'D1',
          'hostWallId': 'W1',
          'startT': 0.4,
          'endT': 0.6,
          'connectsSpaceIds': ['S1'],
          'confidence': 0.8,
        },
      ],
      'windows': [],
      'openings': [],
      'objects': [],
      'relationships': [],
      'dimensionHints': [],
      'reviewReasons': [],
    };

void main() {
  test('API 키가 없으면 authRequired로 명확히 실패한다 (mock으로 대체하지 않음)', () async {
    const pipeline = GptCadPipeline(apiService: _AuthMissingService());
    final result = await pipeline.run(Uint8List(0));
    expect(result.failureKind, GptPipelineFailureKind.authRequired);
    expect(result.succeeded, isFalse);
  });

  test('형식이 잘못된 JSON은 jsonParseError로 실패한다', () {
    const pipeline = GptCadPipeline(apiService: _AuthMissingService());
    final result = pipeline.runWithRawJson('{not valid json', Uint8List(0));
    expect(result.failureKind, GptPipelineFailureKind.jsonParseError);
  });

  test('cross-reference가 깨진 JSON은 validationError로 실패한다', () {
    const pipeline = GptCadPipeline(apiService: _AuthMissingService());
    final json = _testJson();
    (json['walls'] as List)[0] = {'id': 'W1', 'type': 'interior', 'cornerIds': ['C1', 'C99'], 'confidence': 0.85};
    final result = pipeline.runWithRawJson(jsonEncode(json), Uint8List(0));
    expect(result.failureKind, GptPipelineFailureKind.validationError);
  });

  test('실제 이미지 2에 대해 전체 파이프라인이 canonical SSSpatialModel을 만든다', () {
    final realBytes = loadRealImage2Bytes();
    if (realBytes == null) {
      // ignore: avoid_print
      print('SKIP: 실제 이미지 2 파일 없음');
      return;
    }
    const pipeline = GptCadPipeline(apiService: _AuthMissingService());
    final result = pipeline.runWithRawJson(jsonEncode(_testJson()), realBytes);
    expect(result.failureKind, GptPipelineFailureKind.none);
    expect(result.succeeded, isTrue);
    expect(result.model!.spaces, hasLength(1));
    expect(result.model!.spaces.first.label, '거실');
    expect(result.model!.spaces.first.polygon, hasLength(4));
    // wall topology에서 유도된 닫힌 loop이므로 closed=true여야 한다.
    expect(result.model!.spaces.first.closed, isTrue);
    expect(result.model!.walls, hasLength(4));
    expect(result.model!.openings, hasLength(1));
  });
}
