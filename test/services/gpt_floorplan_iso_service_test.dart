import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ason_space/services/gpt_floorplan_iso_service.dart';

void main() {
  Uint8List fakeCleanTwoDImage() => Uint8List.fromList([137, 80, 78, 71, 1, 2, 3, 4]);
  Uint8List fakeIsoImage() => Uint8List.fromList([137, 80, 78, 71, 9, 8, 7, 6]);

  group('GptFloorplanIsoImageService', () {
    test('Clean 2D 이미지를 Edge Function에 보내고 생성된 ISO 이미지 bytes를 돌려받는다', () async {
      http.Request? sentRequest;
      final client = MockClient((incoming) async {
        sentRequest = incoming;
        return http.Response(
          jsonEncode({
            'success': true,
            'image': 'data:image/png;base64,${base64Encode(fakeIsoImage())}',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = GptFloorplanIsoImageService(
        endpoint: Uri.parse('https://project.supabase.co/functions/v1/gpt-floorplan-iso'),
        client: client,
      );

      final result = await service.generate(fakeCleanTwoDImage());
      final body = jsonDecode(sentRequest!.body) as Map<String, dynamic>;

      expect(body['image'], startsWith('data:image/png;base64,'));
      expect(result, fakeIsoImage());
    });

    test('Edge Function이 실패 응답을 주면 예외를 던진다(정직한 실패, 가짜 성공 없음)', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({'success': false, 'message': 'AI 3D 아이소 생성 기능이 아직 설정되지 않았습니다.'}),
          503,
          headers: {'content-type': 'application/json'},
        ),
      );
      final service = GptFloorplanIsoImageService(
        endpoint: Uri.parse('https://project.supabase.co/functions/v1/gpt-floorplan-iso'),
        client: client,
      );

      expect(
        () => service.generate(fakeCleanTwoDImage()),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('아직 설정되지 않았습니다'))),
      );
    });

    test('응답 본문이 JSON이 아니면 안전하게 예외를 던진다', () async {
      final client = MockClient((_) async => http.Response('not json', 200));
      final service = GptFloorplanIsoImageService(
        endpoint: Uri.parse('https://project.supabase.co/functions/v1/gpt-floorplan-iso'),
        client: client,
      );

      expect(() => service.generate(fakeCleanTwoDImage()), throwsException);
    });
  });

  group('UnavailableFloorPlanIsoImageService', () {
    test('네트워크 호출 없이 즉시 예외를 던진다(안전한 기본값)', () async {
      const service = UnavailableFloorPlanIsoImageService();
      expect(() => service.generate(fakeCleanTwoDImage()), throwsException);
    });
  });

  group('createFloorPlanIsoImageService', () {
    test('dart-define URL이 없으면 UnavailableFloorPlanIsoImageService를 돌려준다', () {
      final service = createFloorPlanIsoImageService();
      expect(service, isA<UnavailableFloorPlanIsoImageService>());
    });

    test('urlOverride를 주면 실제 GptFloorplanIsoImageService를 만든다', () {
      final service = createFloorPlanIsoImageService(
        urlOverride: 'https://project.supabase.co/functions/v1/gpt-floorplan-iso',
      );
      expect(service, isA<GptFloorplanIsoImageService>());
      expect(
        (service as GptFloorplanIsoImageService).endpoint.toString(),
        'https://project.supabase.co/functions/v1/gpt-floorplan-iso',
      );
    });

    test('urlOverride가 빈 문자열이면 여전히 안전한 기본값을 돌려준다', () {
      final service = createFloorPlanIsoImageService(urlOverride: '');
      expect(service, isA<UnavailableFloorPlanIsoImageService>());
    });
  });
}
