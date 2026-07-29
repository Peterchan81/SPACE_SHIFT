/// 앱이 실행되는 배포 환경 종류.
enum AppEnvironmentType {
  development,
  staging,
  production,
}

/// 지원하는(또는 지원 예정인) AI 이미지 생성 Provider 종류.
///
/// 이번 단계에서는 [mock]을 제외한 나머지 값이 선택되어도 실제 네트워크
/// 호출은 하지 않고 Mock 결과를 반환한다. 자세한 내용은
/// [AiGenerationService]와 프로젝트 루트의 AI_SETUP.md를 참고한다.
enum AiProviderType {
  mock,
  fal,
  openai,
  stability,
  replicate,
}

/// 문자열을 [AiProviderType]으로 안전하게 변환한다.
///
/// 대소문자를 구분하지 않고 앞뒤 공백은 제거한다. 지원하지 않는 값이
/// 들어오면 항상 [AiProviderType.mock]을 반환해, 환경 변수 설정 실수로
/// 인해 앱이 예기치 않게 실제 API를 호출하려 시도하는 일이 없도록 한다.
AiProviderType parseAiProvider(String value) {
  switch (value.trim().toLowerCase()) {
    case 'mock':
      return AiProviderType.mock;
    case 'fal':
      return AiProviderType.fal;
    case 'openai':
      return AiProviderType.openai;
    case 'stability':
      return AiProviderType.stability;
    case 'replicate':
      return AiProviderType.replicate;
    default:
      return AiProviderType.mock;
  }
}

/// 앱의 실행 환경과 AI Provider 관련 설정을 한 곳에서 관리하는 유틸리티.
///
/// 모든 값은 빌드 시점에 `--dart-define`으로 주입되는 컴파일 타임 상수다.
/// 예)
/// ```
/// flutter run -d chrome \
///   --dart-define=AI_PROVIDER=mock
/// ```
///
/// ⚠️ 보안 경고 — Flutter Web에서의 API Key 노출
/// `--dart-define`으로 전달한 값은 Flutter Web 빌드 결과물(JS 번들) 안에
/// 그대로 문자열로 포함되어, 브라우저 개발자 도구 등으로 손쉽게 추출할 수
/// 있다. 즉 `AI_API_KEY`를 실제 서비스에서 그대로 사용해 Flutter 앱이
/// AI 업체를 직접 호출하도록 만들면 API Key가 유출된다.
/// 그러므로 실제 서비스에서는 Flutter 앱이 AI Provider를 직접 호출하지
/// 않고, 백엔드 서버 또는 Supabase Edge Function 등 신뢰할 수 있는
/// 서버를 경유해 호출해야 한다. 자세한 내용은 AI_SETUP.md를 참고한다.
class AppEnvironment {
  const AppEnvironment._();

  /// 앱 버전. 여러 화면/서비스에서 이 값을 그대로 사용해 버전 문자열이
  /// 여러 곳에 중복 하드코딩되지 않도록 한다.
  static const String appVersion = '1.0.0';

  /// `--dart-define=APP_ENV=development|staging|production`.
  /// 지정하지 않으면 development로 취급한다.
  static const String _rawEnvironment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'development',
  );

  /// `--dart-define=AI_PROVIDER=mock|fal|openai|stability|replicate`.
  /// 지정하지 않으면 mock으로 취급한다.
  static const String _rawProvider = String.fromEnvironment(
    'AI_PROVIDER',
    defaultValue: 'mock',
  );

  /// `--dart-define=AI_API_KEY=...`.
  ///
  /// 실제 키 값은 절대 이 파일이나 다른 Dart 파일에 하드코딩하지 않는다.
  /// 의도적으로 private으로 두어, 이 클래스 밖에서는 값 자체가 아니라
  /// [hasApiKey](설정 여부)만 확인할 수 있게 한다. debugPrint, toString,
  /// 로그, 예외 메시지 어디에도 이 값을 그대로 출력해서는 안 된다.
  static const String _apiKey = String.fromEnvironment(
    'AI_API_KEY',
    defaultValue: '',
  );

  /// `--dart-define=AI_API_BASE_URL=...`. 지정하지 않으면 빈 문자열이다.
  static const String apiBaseUrl = String.fromEnvironment(
    'AI_API_BASE_URL',
    defaultValue: '',
  );

  /// 현재 실행 환경.
  static AppEnvironmentType get current {
    switch (_rawEnvironment.trim().toLowerCase()) {
      case 'production':
        return AppEnvironmentType.production;
      case 'staging':
        return AppEnvironmentType.staging;
      default:
        return AppEnvironmentType.development;
    }
  }

  /// 현재 선택된 AI Provider. 알 수 없는 값이면 mock으로 안전하게 처리된다.
  static AiProviderType get aiProvider => parseAiProvider(_rawProvider);

  /// API Key가 비어 있지 않은지 여부. 값 자체는 노출하지 않는다.
  static bool get hasApiKey => _apiKey.isNotEmpty;

  /// Mock AI를 사용해야 하는지 여부.
  /// Provider가 명시적으로 mock이거나, 아직 API Key가 없으면 true다.
  static bool get useMockAi =>
      aiProvider == AiProviderType.mock || !hasApiKey;
}
