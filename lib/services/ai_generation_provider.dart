import 'package:flutter/foundation.dart';

import '../config/app_environment.dart';
import 'ai_generation_service.dart';

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
}) {
  final provider = providerOverride ?? AppEnvironment.aiProvider;

  if (provider != AiProviderType.mock) {
    // API Key 등 민감 정보는 절대 출력하지 않는다.
    debugPrint('선택된 AI Provider는 아직 연결되지 않아 Mock 서비스를 사용합니다.');
  }

  // 이번 단계에서는 Provider와 무관하게 항상 Mock 결과를 반환하는
  // AiGenerationService를 생성한다. 실제 Fal.ai/OpenAI/Stability AI/
  // Replicate 연동은 이번 작업 범위가 아니다.
  //
  // TODO(provider == AiProviderType.fal 실제 연동 시):
  //   여기서 Mock을 쓰는 AiGenerationService 대신, requestGeneration()이
  //   supabase/functions/generate-interior Edge Function을 HTTP로 호출하는
  //   구현으로 교체한 서비스를 반환한다. Edge Function의 요청/응답 형식은
  //   `supabase/functions/generate-interior/README.md`를 참고한다.
  //   (Flutter는 이 경우에도 Fal.ai를 직접 호출하지 않는다.)
  return AiGenerationService(provider: provider);
}
