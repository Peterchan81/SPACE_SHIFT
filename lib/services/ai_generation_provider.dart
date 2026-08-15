import 'package:flutter/foundation.dart';

import '../config/app_environment.dart';
import 'ai_generation_service.dart';
import 'edge_function_ai_generation_service.dart';

/// [AppEnvironment] 설정에 맞는 [AiGenerationService]를 생성한다.
///
/// UI(화면)는 이 함수만 호출하면 되고, 어떤 AI Provider가 선택되어 있는지는
/// 알 필요가 없다. 이번 단계에서는 [AiProviderType.mock]이 아닌 Provider가
/// 선택되어 있어도 실제 네트워크 호출은 하지 않고 항상 Mock 서비스를
/// 반환한다. 추후 실제 AI 연동을 추가할 때는 이 함수의 분기만 확장하면
/// 되고, [GenerateScreen] 등 화면 코드는 수정할 필요가 없다.
///
/// [providerOverride]를 지정하면 [AppEnvironment.aiProvider] 대신 이 값을
/// 사용한다. `--dart-define` 값은 컴파일 타임에 고정되어 테스트에서 런타임에
/// 바꿀 수 없으므로, 여러 Provider 상황을 테스트하기 위한 용도로 둔 값이다.
AiGenerationService createAiGenerationService({
  AiProviderType? providerOverride,
  String? edgeFunctionUrlOverride,
}) {
  final provider = providerOverride ?? AppEnvironment.aiProvider;
  final edgeFunctionUrl =
      edgeFunctionUrlOverride ?? AppEnvironment.edgeFunctionUrl;

  if (provider == AiProviderType.fal && edgeFunctionUrl.trim().isNotEmpty) {
    return EdgeFunctionAiGenerationService(
      endpoint: Uri.parse(edgeFunctionUrl),
    );
  }

  if (provider != AiProviderType.mock) {
    debugPrint('Edge Function URL이 없어 Mock AI를 사용합니다.');
  }
  return AiGenerationService(provider: provider);
}
