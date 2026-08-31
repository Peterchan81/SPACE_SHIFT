/// 앱이 실행되는 배포 환경 종류.
enum AppEnvironmentType { development, staging, production }

/// 지원하는(또는 지원 예정인) AI 이미지 생성 Provider 종류.
///
/// 이번 단계에서는 [mock]을 제외한 나머지 값이 선택되어도 실제 네트워크
/// 호출은 하지 않고 Mock 결과를 반환한다. 자세한 내용은
/// [AiGenerationService]와 프로젝트 루트의 AI_SETUP.md를 참고한다.
enum AiProviderType { mock, fal, openai, stability, replicate }

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
/// Flutter에는 AI Provider Key를 받는 설정 자체가 없다. 실제 Secret은
/// Supabase Edge Function 환경에만 저장하고 앱은 공개 함수 URL만 사용한다.
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

  /// 공개된 Supabase Edge Function 전체 URL.
  /// AI Provider Secret이 아니며, 지정하지 않으면 안전하게 Mock을 사용한다.
  static const String edgeFunctionUrl = String.fromEnvironment(
    'AI_EDGE_FUNCTION_URL',
    defaultValue: '',
  );

  /// `--dart-define=ESTIMATE_EDGE_FUNCTION_URL=...`.
  /// 무료 예상견적 요청을 접수하는 Supabase Edge Function URL.
  /// 지정하지 않으면 EstimateService가 안전하게 로컬 Mock으로 동작한다.
  static const String estimateEdgeFunctionUrl = String.fromEnvironment(
    'ESTIMATE_EDGE_FUNCTION_URL',
    defaultValue: '',
  );

  /// `--dart-define=SITE_MEETING_EDGE_FUNCTION_URL=...`.
  /// 현장미팅 문의를 접수하는 Supabase Edge Function URL.
  /// 지정하지 않으면 SiteMeetingService가 안전하게 로컬 Mock으로 동작한다.
  static const String siteMeetingEdgeFunctionUrl = String.fromEnvironment(
    'SITE_MEETING_EDGE_FUNCTION_URL',
    defaultValue: '',
  );

  /// `--dart-define=SUPABASE_URL=...`.
  ///
  /// Galaxy Tab 인터넷 기반 무선 업데이트(AppUpdateService)가 공개 배포
  /// 채널(Supabase Storage 공개 버킷)의 위치를 계산하는 데만 사용한다.
  /// 이 값 자체는 Secret이 아니라 공개 프로젝트 URL이며, 지정하지 않으면
  /// [AppUpdateService]가 안전하게 "업데이트 확인 불가"로 처리한다.
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
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

  /// Mock AI를 사용해야 하는지 여부.
  /// Provider가 mock이거나 Edge Function URL이 없으면 true다.
  static bool get useMockAi =>
      aiProvider == AiProviderType.mock || edgeFunctionUrl.trim().isEmpty;

  /// `--dart-define=E2E_UNLIMITED_GENERATION=true`.
  ///
  /// Galaxy Tab V1 FINAL E2E 실기 확인 중 하루 무료 생성 3회 제한 때문에
  /// 후속 화면(수정 재요청 → 완료까지) 검증이 막히지 않도록, 이 플래그가
  /// true인 빌드에서만 [UsagePolicyService.canGenerate] 제한을 우회한다.
  /// 지정하지 않으면 항상 false이므로 기존 3회 정책은 그대로 유지된다.
  static const bool unlimitedGenerationForE2eTest = bool.fromEnvironment(
    'E2E_UNLIMITED_GENERATION',
    defaultValue: false,
  );
}
