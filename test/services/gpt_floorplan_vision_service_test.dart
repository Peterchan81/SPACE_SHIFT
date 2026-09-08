import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ason_space/models/vision_understanding.dart';
import 'package:ason_space/services/gpt_floorplan_vision_service.dart';

void main() {
  Uint8List fakeImage() => Uint8List.fromList([137, 80, 78, 71, 1, 2, 3, 4]);

  Map<String, dynamic> fakeUnderstandingJson() => {
    'floorDomain': {
      'id': 'floor-domain',
      'type': 'floorDomain',
      'confidence': 'medium',
      'source': 'vision',
      'geometryHint': {
        'kind': 'polygon',
        'points': [
          {'x': 0.0, 'y': 0.0},
          {'x': 1.0, 'y': 0.0},
          {'x': 1.0, 'y': 1.0},
          {'x': 0.0, 'y': 1.0},
        ],
      },
      'notes': <String>[],
    },
    'spaces': [
      {
        'id': 'space-1',
        'type': 'space',
        'confidence': 'high',
        'source': 'vision',
        'geometryHint': {
          'kind': 'boundingBox',
          'minX': 0.1,
          'minY': 0.1,
          'maxX': 0.4,
          'maxY': 0.4,
        },
        'notes': <String>[],
        'label': null,
        'semanticType': 'bathroom',
        'adjacentSpaceIds': <String>[],
        'containedObjectIds': <String>[],
      },
    ],
    'boundaries': <Map<String, dynamic>>[],
    'openings': <Map<String, dynamic>>[],
    'objects': <Map<String, dynamic>>[],
    'structuralElements': <Map<String, dynamic>>[],
    'dimensions': <Map<String, dynamic>>[],
    'scaleConfirmed': false,
    'notes': <String>[],
  };

  group('GptFloorplanEdgeFunctionVisionService', () {
    test('이미지를 Edge Function에 보내고 VisionUnderstanding으로 파싱한다', () async {
      http.Request? sentRequest;
      final client = MockClient((incoming) async {
        sentRequest = incoming;
        return http.Response(
          jsonEncode({'success': true, 'understanding': fakeUnderstandingJson()}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = GptFloorplanEdgeFunctionVisionService(
        endpoint: Uri.parse('https://project.supabase.co/functions/v1/gpt-floorplan-understand'),
        client: client,
      );

      final result = await service.interpret(fakeImage());
      final body = jsonDecode(sentRequest!.body) as Map<String, dynamic>;

      expect(body['image'], startsWith('data:image/png;base64,'));
      expect(result.spaces, hasLength(1));
      expect(result.spaces.single.semanticType, VisionSpaceSemanticType.bathroom);
      expect(result.scaleConfirmed, isFalse);
    });

    test('Edge Function이 실패 응답을 주면 예외를 던진다(정직한 실패, 가짜 성공 없음)', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({'success': false, 'message': 'GPT 평면도 분석 기능이 아직 설정되지 않았습니다.'}),
          503,
          headers: {'content-type': 'application/json'},
        ),
      );
      final service = GptFloorplanEdgeFunctionVisionService(
        endpoint: Uri.parse('https://project.supabase.co/functions/v1/gpt-floorplan-understand'),
        client: client,
      );

      expect(
        () => service.interpret(fakeImage()),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('아직 설정되지 않았습니다'))),
      );
    });

    test('응답 본문이 JSON이 아니면 안전하게 예외를 던진다', () async {
      final client = MockClient((_) async => http.Response('not json', 200));
      final service = GptFloorplanEdgeFunctionVisionService(
        endpoint: Uri.parse('https://project.supabase.co/functions/v1/gpt-floorplan-understand'),
        client: client,
      );

      expect(() => service.interpret(fakeImage()), throwsException);
    });
  });

  group('UnavailableVisionInterpretationService', () {
    test('네트워크 호출 없이 즉시 예외를 던진다(안전한 기본값)', () async {
      const service = UnavailableVisionInterpretationService();
      expect(() => service.interpret(fakeImage()), throwsException);
    });
  });

  group('createVisionInterpretationService', () {
    test('dart-define URL이 없으면 UnavailableVisionInterpretationService를 돌려준다', () {
      final service = createVisionInterpretationService();
      expect(service, isA<UnavailableVisionInterpretationService>());
    });

    test('WO090 — urlOverride를 주면 실제 GptFloorplanEdgeFunctionVisionService를 만든다', () {
      final service = createVisionInterpretationService(
        urlOverride: 'https://project.supabase.co/functions/v1/gpt-floorplan-understand',
      );
      expect(service, isA<GptFloorplanEdgeFunctionVisionService>());
      expect(
        (service as GptFloorplanEdgeFunctionVisionService).endpoint.toString(),
        'https://project.supabase.co/functions/v1/gpt-floorplan-understand',
      );
    });

    test('urlOverride가 빈 문자열이면 여전히 안전한 기본값을 돌려준다', () {
      final service = createVisionInterpretationService(urlOverride: '');
      expect(service, isA<UnavailableVisionInterpretationService>());
    });
  });
}
