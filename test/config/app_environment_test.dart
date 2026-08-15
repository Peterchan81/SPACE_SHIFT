// AppEnvironment / AiProviderType 파싱에 대한 단위 테스트.
//
// 환경 변수는 const String.fromEnvironment 특성상 테스트 실행 중에는
// 런타임으로 바꿀 수 없으므로, 순수 함수인 parseAiProvider()를 다양한
// 입력값으로 직접 검증한다.
//
// 1. AI Provider 문자열 파싱 테스트 (mock/FAL/openai/stability/replicate/알 수 없는 값)
// 2. 공백과 대소문자 처리 테스트
// 3. 알 수 없는 Provider는 mock 반환
// 4. Edge Function URL이 없으면 Mock 모드를 유지함

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/config/app_environment.dart';

void main() {
  group('parseAiProvider', () {
    test('지원하는 소문자 문자열을 올바른 enum으로 변환한다', () {
      expect(parseAiProvider('mock'), AiProviderType.mock);
      expect(parseAiProvider('fal'), AiProviderType.fal);
      expect(parseAiProvider('openai'), AiProviderType.openai);
      expect(parseAiProvider('stability'), AiProviderType.stability);
      expect(parseAiProvider('replicate'), AiProviderType.replicate);
    });

    test('대소문자를 구분하지 않는다', () {
      expect(parseAiProvider('FAL'), AiProviderType.fal);
      expect(parseAiProvider('OpenAI'), AiProviderType.openai);
      expect(parseAiProvider('STABILITY'), AiProviderType.stability);
      expect(parseAiProvider('Replicate'), AiProviderType.replicate);
      expect(parseAiProvider('MOCK'), AiProviderType.mock);
    });

    test('앞뒤 공백을 제거한 뒤 판단한다', () {
      expect(parseAiProvider('  fal  '), AiProviderType.fal);
      expect(parseAiProvider('\topenai\n'), AiProviderType.openai);
    });

    test('알 수 없는 값이 들어오면 안전하게 mock을 반환한다', () {
      expect(parseAiProvider('gemini'), AiProviderType.mock);
      expect(parseAiProvider('unknown-provider'), AiProviderType.mock);
      expect(parseAiProvider(''), AiProviderType.mock);
    });
  });

  group('AppEnvironment', () {
    test('appVersion은 비어 있지 않은 고정 문자열이다', () {
      expect(AppEnvironment.appVersion, isNotEmpty);
    });

    test('dart-define을 지정하지 않으면 개발 환경/mock Provider로 안전하게 기본값이 잡힌다', () {
      expect(AppEnvironment.current, AppEnvironmentType.development);
      expect(AppEnvironment.aiProvider, AiProviderType.mock);
    });

    test('Edge Function URL을 지정하지 않으면 Mock 모드를 유지한다', () {
      expect(AppEnvironment.edgeFunctionUrl, isEmpty);
      expect(AppEnvironment.useMockAi, isTrue);
    });

    test('예상견적/현장미팅 Edge Function URL을 지정하지 않으면 비어 있다', () {
      expect(AppEnvironment.estimateEdgeFunctionUrl, isEmpty);
      expect(AppEnvironment.siteMeetingEdgeFunctionUrl, isEmpty);
    });
  });
}
