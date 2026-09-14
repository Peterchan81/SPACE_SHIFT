// SS CAD TEST — Windows 개발/검증 전용 "OpenAI 직접 호출" 경로.
// GptFloorplanEdgeFunctionVisionService(기존 Supabase 경로)와 동일한
// VisionUnderstanding 계약을 돌려주는지, 그리고 401/429/5xx/timeout/
// malformed JSON을 구분해서 처리하되 API key는 절대 예외 메시지에
// 노출하지 않는지 확인한다.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ason_space/models/vision_understanding.dart';
import 'package:ason_space/services/gpt_floorplan_direct_openai_vision_service.dart';

void main() {
  Uint8List fakeImage() => Uint8List.fromList([137, 80, 78, 71, 1, 2, 3, 4]);
  const fakeApiKey = 'sk-fake-local-only-never-real';

  Map<String, dynamic> fakeGptIntermediateJson() => {
    'floorDomainPolygon': [
      {'x': 0.0, 'y': 0.0},
      {'x': 1.0, 'y': 0.0},
      {'x': 1.0, 'y': 1.0},
      {'x': 0.0, 'y': 1.0},
    ],
    'spaces': [
      {
        'id': 'space-1',
        'label': null,
        'semanticType': 'bathroom',
        'confidence': 'high',
        'boundingBox': {'minX': 0.1, 'minY': 0.1, 'maxX': 0.4, 'maxY': 0.4},
      },
    ],
    'boundaries': [
      {
        'id': 'b1',
        'boundaryType': 'exteriorWall',
        'confidence': 'high',
        'start': {'x': 0.0, 'y': 0.0},
        'end': {'x': 1.0, 'y': 0.0},
      },
    ],
    'openings': <Map<String, dynamic>>[],
    'notes': <String>[],
  };

  http.Response fakeOpenAiSuccessResponse() => http.Response(
    jsonEncode({
      'choices': [
        {
          'message': {'content': jsonEncode(fakeGptIntermediateJson())},
        },
      ],
    }),
    200,
    headers: {'content-type': 'application/json'},
  );

  group('GptDirectOpenAiVisionService — 성공 경로', () {
    test('OpenAI를 직접 호출하고 supabase 경로와 동일한 VisionUnderstanding 계약으로 파싱한다', () async {
      http.Request? sentRequest;
      final client = MockClient((incoming) async {
        sentRequest = incoming;
        return fakeOpenAiSuccessResponse();
      });
      final service = GptDirectOpenAiVisionService(apiKey: fakeApiKey, client: client);

      final result = await service.interpret(fakeImage());

      expect(sentRequest!.url.toString(), 'https://api.openai.com/v1/chat/completions');
      expect(sentRequest!.headers['Authorization'], 'Bearer $fakeApiKey');
      final body = jsonDecode(sentRequest!.body) as Map<String, dynamic>;
      expect(body['model'], 'gpt-4o');

      expect(result.spaces, hasLength(1));
      expect(result.spaces.single.semanticType, VisionSpaceSemanticType.bathroom);
      expect(result.boundaries, hasLength(1));
      expect(result.boundaries.single.boundaryType, VisionBoundaryType.exteriorWall);
      expect(result.scaleConfirmed, isFalse);
    });
  });

  group('GptDirectOpenAiVisionService — 실패 경로 구분(§5)', () {
    test('401이면 예외를 던지고, 예외 메시지에 API key가 노출되지 않는다', () async {
      final client = MockClient((_) async => http.Response('{"error":"invalid_api_key"}', 401));
      final service = GptDirectOpenAiVisionService(apiKey: fakeApiKey, client: client);

      try {
        await service.interpret(fakeImage());
        fail('should have thrown');
      } catch (e) {
        expect(e.toString(), isNot(contains(fakeApiKey)));
      }
    });

    test('429면 예외를 던진다(rate/quota)', () async {
      final client = MockClient((_) async => http.Response('{"error":"rate_limited"}', 429));
      final service = GptDirectOpenAiVisionService(apiKey: fakeApiKey, client: client);
      expect(() => service.interpret(fakeImage()), throwsException);
    });

    test('5xx면 예외를 던진다(OpenAI 서버 오류)', () async {
      final client = MockClient((_) async => http.Response('{}', 503));
      final service = GptDirectOpenAiVisionService(apiKey: fakeApiKey, client: client);
      expect(() => service.interpret(fakeImage()), throwsException);
    });

    test('응답 본문이 JSON이 아니면 예외를 던진다(malformed JSON)', () async {
      final client = MockClient((_) async => http.Response('not json', 200));
      final service = GptDirectOpenAiVisionService(apiKey: fakeApiKey, client: client);
      expect(() => service.interpret(fakeImage()), throwsException);
    });

    test('choices[0].message.content가 없으면 예외를 던진다(schema mismatch)', () async {
      final client = MockClient((_) async => http.Response(jsonEncode({'choices': <Object?>[]}), 200));
      final service = GptDirectOpenAiVisionService(apiKey: fakeApiKey, client: client);
      expect(() => service.interpret(fakeImage()), throwsException);
    });

    test('GPT content가 JSON이 아니면 예외를 던진다(malformed JSON)', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'not-json-content'},
              },
            ],
          }),
          200,
        ),
      );
      final service = GptDirectOpenAiVisionService(apiKey: fakeApiKey, client: client);
      expect(() => service.interpret(fakeImage()), throwsException);
    });
  });
}
