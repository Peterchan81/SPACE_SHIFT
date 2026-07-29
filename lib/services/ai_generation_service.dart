import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../config/app_environment.dart';
import '../models/ai_generation_request.dart';
import '../models/ai_generation_response.dart';

/// AI 인테리어 이미지 생성을 요청하는 서비스.
///
/// 화면(UI)은 이 클래스만 알면 되고, 실제로 어떤 AI 서비스(OpenAI, Gemini,
/// Fal.ai, Stability AI, Replicate 등)를 쓰는지는 몰라도 된다. 추후 실제
/// AI 연동이 필요해지면 [requestGeneration] 내부 구현만 교체하면 되며,
/// [generate]를 호출하는 화면 코드는 전혀 수정할 필요가 없다.
class AiGenerationService {
  const AiGenerationService({this.provider = AiProviderType.mock});

  /// 이 서비스 인스턴스가 대상으로 하는 AI Provider.
  ///
  /// 이번 단계에서는 어떤 Provider가 지정되어도 항상 Mock 결과를
  /// 반환하지만, 값 자체는 내부적으로 유지해 추후 Provider별 실제 구현을
  /// 분기할 때 사용할 수 있도록 한다.
  final AiProviderType provider;

  /// AI 이미지 생성을 요청하고 결과를 반환한다.
  ///
  /// 내부에서 예외가 발생해도 앱이 종료되지 않도록 안전하게 잡아
  /// success=false인 [AiGenerationResponse]로 변환해 반환한다.
  Future<AiGenerationResponse> generate(AiGenerationRequest request) async {
    debugPrint('AI 생성 요청 - 선택한 스타일: ${request.selectedStyle}');
    debugPrint('AI 생성 요청 - 이미지 크기: ${request.imageBytes.length} bytes');

    try {
      final generatedImageBytes = await requestGeneration(request);
      return AiGenerationResponse(
        success: true,
        generatedImageBytes: generatedImageBytes,
        elapsedTime: const Duration(seconds: 3),
      );
    } catch (error) {
      debugPrint('AI 생성 실패: $error');
      return AiGenerationResponse(
        success: false,
        errorMessage: error.toString(),
        elapsedTime: const Duration(seconds: 3),
      );
    }
  }

  /// 실제 AI 요청을 수행하는 지점.
  ///
  /// 지금은 실제 API를 호출하지 않고, 3초 대기 후 assets에 미리 넣어 둔
  /// Mock 이미지(assets/images/mock_ai_result.png)를 읽어 반환하는 더미
  /// 구현이다. 이렇게 하면 사용자가 실제 AI가 동작하는 것처럼 결과 화면에서
  /// 이미지를 확인할 수 있다. 테스트에서는 이 메서드를 오버라이드해
  /// 성공/실패 상황을 손쉽게 흉내낼 수 있다.
  ///
  /// TODO(실제 AI 연동 시 아래 순서로 이 메서드 내부만 교체한다.
  /// [generate]나 화면(GenerateScreen 등) 코드는 수정할 필요가 없다):
  ///   1. Remove Mock response
  ///      → 지금의 "3초 대기 + assets 이미지 읽기" 코드를 제거한다.
  ///   2. Call Supabase Edge Function
  ///      → Flutter는 Fal.ai를 직접 호출하지 않는다. 반드시
  ///        `supabase/functions/generate-interior`(POST
  ///        `/functions/v1/generate-interior`, body: `{ "style": ...,
  ///        "image": ... }`)를 HTTP로 호출한다. 자세한 요청/응답 형식은
  ///        해당 Edge Function의 README.md를 참고한다.
  ///   3. Receive generated image URL
  ///      → Edge Function 응답의 `imageUrl`(성공 시) 또는 `message`
  ///        (실패 시)를 받는다.
  ///   4. Return AiGenerationResponse
  ///      → 받은 이미지를 내려받아 Uint8List로 변환하거나(또는 URL 그대로
  ///        ResultScreen에 전달하도록 모델을 확장), 실패 시에는 예외를
  ///        던져 [generate]의 try/catch가 success=false 응답으로 안전하게
  ///        변환하도록 한다.
  @protected
  Future<Uint8List?> requestGeneration(AiGenerationRequest request) async {
    await Future.delayed(const Duration(seconds: 3));

    final byteData = await rootBundle.load('assets/images/mock_ai_result.png');
    return byteData.buffer.asUint8List();
  }
}
