import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ason_space/models/ai_generation_request.dart';
import 'package:ason_space/services/edge_function_ai_generation_service.dart';

void main() {
  AiGenerationRequest request() => AiGenerationRequest(
    imageBytes: Uint8List.fromList([137, 80, 78, 71, 1, 2, 3, 4]),
    selectedStyle: '모던',
    createdAt: DateTime(2026, 8, 14),
    appVersion: '1.0.0',
  );

  test('원본 이미지와 스타일을 Edge Function에 보내고 결과 이미지를 내려받는다', () async {
    http.Request? generationRequest;
    final client = MockClient((incoming) async {
      if (incoming.method == 'POST') {
        generationRequest = incoming;
        return http.Response(
          jsonEncode({
            'success': true,
            'provider': 'fal',
            'imageUrl': 'https://images.example/result.png',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response.bytes([137, 80, 78, 71, 9, 8, 7, 6], 200);
    });
    final service = EdgeFunctionAiGenerationService(
      endpoint: Uri.parse(
        'https://project.supabase.co/functions/v1/generate-interior',
      ),
      client: client,
    );

    final response = await service.generate(request());
    final body = jsonDecode(generationRequest!.body) as Map<String, dynamic>;

    expect(response.success, isTrue);
    expect(response.generatedImageBytes, [137, 80, 78, 71, 9, 8, 7, 6]);
    expect(body['style'], '모던');
    expect(body['image'], startsWith('data:image/png;base64,'));
    expect(generationRequest!.headers, isNot(contains('Authorization')));
  });

  test('Edge Function 실패 응답을 안전한 실패 결과로 변환한다', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({'success': false, 'message': 'AI 서비스가 아직 설정되지 않았습니다.'}),
        503,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    final service = EdgeFunctionAiGenerationService(
      endpoint: Uri.parse(
        'https://project.supabase.co/functions/v1/generate-interior',
      ),
      client: client,
    );

    final response = await service.generate(request());

    expect(response.success, isFalse);
    expect(response.generatedImageBytes, isNull);
    expect(response.errorMessage, contains('AI 서비스가 아직 설정되지 않았습니다.'));
  });
}
