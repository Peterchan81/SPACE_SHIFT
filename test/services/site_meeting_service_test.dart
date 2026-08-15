import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ason_space/models/site_meeting_request.dart';
import 'package:ason_space/services/site_meeting_service.dart';

void main() {
  SiteMeetingRequest request() => const SiteMeetingRequest(
    name: '홍길동',
    contact: '010-1234-5678',
    visitArea: '서울시 강남구',
    preferredDateTime: '8월 20일 오후 2시',
    notes: '주말 방문을 희망합니다.',
    privacyAgreed: true,
  );

  test('Mock 서비스는 예외 없이 즉시 성공한다', () async {
    await const SiteMeetingService().submit(request());
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
    final service = EdgeFunctionSiteMeetingService(
      endpoint: Uri.parse(
        'https://project.supabase.co/functions/v1/submit-site-meeting',
      ),
      client: client,
    );

    await service.submit(request());
    final body = jsonDecode(sentRequest!.body) as Map<String, dynamic>;

    expect(body['name'], '홍길동');
    expect(body['contact'], '010-1234-5678');
    expect(body['visitArea'], '서울시 강남구');
    expect(body['preferredDateTime'], '8월 20일 오후 2시');
    expect(body['privacyAgreed'], isTrue);
  });

  test('Edge Function 실패 응답이면 예외를 던진다', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({'success': false, 'message': '문의 접수에 실패했습니다.'}),
        502,
        headers: {'content-type': 'application/json'},
      ),
    );
    final service = EdgeFunctionSiteMeetingService(
      endpoint: Uri.parse(
        'https://project.supabase.co/functions/v1/submit-site-meeting',
      ),
      client: client,
    );

    expect(
      () => service.submit(request()),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('문의 접수에 실패했습니다.'),
        ),
      ),
    );
  });

  test('createSiteMeetingService는 URL이 없으면 Mock을 반환한다', () {
    expect(
      createSiteMeetingService(edgeFunctionUrlOverride: ''),
      isA<SiteMeetingService>(),
    );
    expect(
      createSiteMeetingService(
        edgeFunctionUrlOverride:
            'https://project.supabase.co/functions/v1/submit-site-meeting',
      ),
      isA<EdgeFunctionSiteMeetingService>(),
    );
  });
}
