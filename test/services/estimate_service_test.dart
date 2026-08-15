import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ason_space/models/estimate_request.dart';
import 'package:ason_space/services/estimate_service.dart';

void main() {
  EstimateRequest request() => const EstimateRequest(
    spaceType: '거실',
    approximateArea: '10~20평',
    constructionScope: '부분 시공',
    desiredColorTone: '베이지',
    customColorTone: '',
    notes: '수납공간을 늘리고 싶어요.',
  );

  test('Mock 서비스는 예외 없이 즉시 성공한다', () async {
    await const EstimateService().submit(request());
  });

  test('요청 내용을 Edge Function에 그대로 전달한다', () async {
    http.Request? sentRequest;
    final client = MockClient((incoming) async {
      sentRequest = incoming;
      return http.Response(
        jsonEncode({'success': true}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final service = EdgeFunctionEstimateService(
      endpoint: Uri.parse('https://project.supabase.co/functions/v1/submit-estimate'),
      client: client,
    );

    await service.submit(request());
    final body = jsonDecode(sentRequest!.body) as Map<String, dynamic>;

    expect(body['spaceType'], '거실');
    expect(body['approximateArea'], '10~20평');
    expect(body['constructionScope'], '부분 시공');
    expect(body['desiredColorTone'], '베이지');
    expect(body['notes'], '수납공간을 늘리고 싶어요.');
  });

  test('Edge Function 실패 응답이면 예외를 던진다', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({'success': false, 'message': '요청 접수에 실패했습니다.'}),
        502,
        headers: {'content-type': 'application/json'},
      ),
    );
    final service = EdgeFunctionEstimateService(
      endpoint: Uri.parse('https://project.supabase.co/functions/v1/submit-estimate'),
      client: client,
    );

    expect(
      () => service.submit(request()),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('요청 접수에 실패했습니다.'),
        ),
      ),
    );
  });

  test('createEstimateService는 URL이 없으면 Mock을 반환한다', () {
    expect(
      createEstimateService(edgeFunctionUrlOverride: ''),
      isA<EstimateService>(),
    );
    expect(
      createEstimateService(
        edgeFunctionUrlOverride: 'https://project.supabase.co/functions/v1/submit-estimate',
      ),
      isA<EdgeFunctionEstimateService>(),
    );
  });
}
