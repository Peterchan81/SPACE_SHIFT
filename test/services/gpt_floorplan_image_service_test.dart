import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ason_space/services/gpt_floorplan_image_service.dart';

void main() {
  Uint8List fakeImage() => Uint8List.fromList([137, 80, 78, 71, 1, 2, 3, 4]);
  Uint8List fakeGeneratedImage() => Uint8List.fromList([137, 80, 78, 71, 9, 8, 7, 6]);

  group('GptFloorplanCadImageService', () {
    test('원본 이미지를 Edge Function에 보내고 생성된 이미지 bytes를 돌려받는다', () async {
      http.Request? sentRequest;
      final client = MockClient((incoming) async {
        sentRequest = incoming;
        return http.Response(
          jsonEncode({
            'success': true,
            'image': 'data:image/png;base64,${base64Encode(fakeGeneratedImage())}',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = GptFloorplanCadImageService(
        endpoint: Uri.parse('https://project.supabase.co/functions/v1/gpt-floorplan-cad-image'),
        client: client,
      );

      final result = await service.generate(fakeImage());
      final body = jsonDecode(sentRequest!.body) as Map<String, dynamic>;

      expect(body['image'], startsWith('data:image/png;base64,'));
      expect(result, fakeGeneratedImage());
    });

    test('Edge Function이 실패 응답을 주면 예외를 던진다(정직한 실패, 가짜 성공 없음)', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({'success': false, 'message': 'AI 평면도 생성 기능이 아직 설정되지 않았습니다.'}),
          503,
          headers: {'content-type': 'application/json'},
        ),
      );
      final service = GptFloorplanCadImageService(
        endpoint: Uri.parse('https://project.supabase.co/functions/v1/gpt-floorplan-cad-image'),
        client: client,
      );

      expect(
        () => service.generate(fakeImage()),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('아직 설정되지 않았습니다'))),
      );
    });

    test('응답 본문이 JSON이 아니면 안전하게 예외를 던진다', () async {
      final client = MockClient((_) async => http.Response('not json', 200));
      final service = GptFloorplanCadImageService(
        endpoint: Uri.parse('https://project.supabase.co/functions/v1/gpt-floorplan-cad-image'),
        client: client,
      );

      expect(() => service.generate(fakeImage()), throwsException);
    });
  });

  group('UnavailableFloorPlanImageGenerationService', () {
    test('네트워크 호출 없이 즉시 예외를 던진다(안전한 기본값)', () async {
      const service = UnavailableFloorPlanImageGenerationService();
      expect(() => service.generate(fakeImage()), throwsException);
    });
  });

  group('createFloorPlanImageGenerationService', () {
    test('dart-define URL이 없으면 UnavailableFloorPlanImageGenerationService를 돌려준다', () {
      final service = createFloorPlanImageGenerationService();
      expect(service, isA<UnavailableFloorPlanImageGenerationService>());
    });

    test('urlOverride를 주면 실제 GptFloorplanCadImageService를 만든다', () {
      final service = createFloorPlanImageGenerationService(
        urlOverride: 'https://project.supabase.co/functions/v1/gpt-floorplan-cad-image',
      );
      expect(service, isA<GptFloorplanCadImageService>());
      expect(
        (service as GptFloorplanCadImageService).endpoint.toString(),
        'https://project.supabase.co/functions/v1/gpt-floorplan-cad-image',
      );
    });

    test('urlOverride가 빈 문자열이면 여전히 안전한 기본값을 돌려준다', () {
      final service = createFloorPlanImageGenerationService(urlOverride: '');
      expect(service, isA<UnavailableFloorPlanImageGenerationService>());
    });
  });
}
