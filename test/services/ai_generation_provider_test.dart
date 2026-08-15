// createAiGenerationService() Factory에 대한 단위 테스트.
//
// 5. Factory가 AiGenerationService를 반환하는지 확인한다.
// 6. Edge Function URL이 없으면 fal에서도 Mock 응답을 반환하는지
//    확인한다(providerOverride로 dart-define 없이도 검증 가능하게 한다).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/config/app_environment.dart';
import 'package:ason_space/models/ai_generation_request.dart';
import 'package:ason_space/services/ai_generation_provider.dart';
import 'package:ason_space/services/ai_generation_service.dart';
import 'package:ason_space/services/edge_function_ai_generation_service.dart';

void main() {
  // Mock 서비스가 내부적으로 rootBundle.load()를 사용하므로, testWidgets가
  // 아닌 일반 test에서도 플랫폼 바인딩을 명시적으로 초기화해 둔다.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('createAiGenerationService는 AiGenerationService 인스턴스를 반환한다', () {
    final service = createAiGenerationService();

    expect(service, isA<AiGenerationService>());
    // dart-define을 지정하지 않았으므로 기본값은 mock이다.
    expect(service.provider, AiProviderType.mock);
  });

  test('providerOverride로 지정한 Provider가 서비스에 그대로 반영된다', () {
    final service = createAiGenerationService(
      providerOverride: AiProviderType.fal,
    );

    expect(service.provider, AiProviderType.fal);
  });

  test('fal과 Edge Function URL을 지정하면 실제 Edge Function 서비스를 생성한다', () {
    final service = createAiGenerationService(
      providerOverride: AiProviderType.fal,
      edgeFunctionUrlOverride:
          'https://project.supabase.co/functions/v1/generate-interior',
    );

    expect(service, isA<EdgeFunctionAiGenerationService>());
    expect(service.provider, AiProviderType.fal);
  });

  test(
    'Edge Function URL 없이 fal만 지정하면 Mock 응답을 반환한다',
    () async {
      final service = createAiGenerationService(
        providerOverride: AiProviderType.fal,
      );

      final request = AiGenerationRequest(
        imageBytes: Uint8List.fromList([1, 2, 3, 4]),
        selectedStyle: '모던',
        createdAt: DateTime.now(),
        appVersion: AppEnvironment.appVersion,
      );

      final response = await service.generate(request);

      expect(response.success, isTrue);
      expect(response.generatedImageBytes, isNotNull);
      expect(response.generatedImageBytes, isNotEmpty);
    },
    // Mock 구현이 실제로 3초 대기하므로 기본 타임아웃보다 넉넉하게 잡는다.
    timeout: const Timeout(Duration(seconds: 10)),
  );
}
