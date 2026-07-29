# ASON Space – AI 연동 설정 가이드

이 문서는 ASON Space 앱의 AI 인테리어 이미지 생성 기능을
실제 AI 서비스와 연동하기 위한 환경 설정 방법을 설명한다.

## 1. 현재 상태: Mock AI만 사용한다

이 프로젝트는 현재 **실제 AI API를 호출하지 않는다.**
`AiGenerationService`는 어떤 Provider가 선택되어 있든 항상
3초 대기 후 `assets/images/mock_ai_result.png`를 읽어 결과로 돌려주는
Mock 구현을 사용한다.

UI(화면) 코드는 `AiGenerationService`와 `createAiGenerationService()`
Factory 함수만 알고 있으며, 실제로 어떤 AI 업체를 쓰는지는 전혀 모른다.
실제 연동을 추가할 때도 화면 코드는 수정할 필요가 없다.

## 2. 지원 예정 Provider

다음 중 하나를 선택해 연결할 수 있도록 구조가 준비되어 있다.
(아직 실제 연동 코드는 없다.)

- Fal.ai
- OpenAI Images API
- Stability AI
- Replicate

`AiProviderType` enum(`lib/config/app_environment.dart`)으로 구분하며,
문자열 → enum 변환은 `parseAiProvider()`가 담당한다. 대소문자를
구분하지 않고, 지원하지 않는 값이 들어오면 항상 `mock`으로
안전하게 처리된다.

## 3. 개발 실행 예시

Provider를 명시적으로 mock으로 지정해 실행하는 예시:

```bash
flutter run -d chrome \
  --dart-define=AI_PROVIDER=mock
```

`--dart-define`을 아예 지정하지 않아도 기본값이 `mock`이므로
평소 개발 중에는 그냥 `flutter run`으로 실행해도 된다.

## 4. API Key 전달 예시 (아직 실제로 연결되지는 않음)

향후 실제 Provider를 연결했을 때, API Key는 다음과 같이
`--dart-define`으로 전달하는 구조를 사용한다.

```bash
flutter run \
  --dart-define=AI_PROVIDER=fal \
  --dart-define=AI_API_KEY=실제키값을_여기에_입력
```

> ⚠️ 위 명령의 `실제키값을_여기에_입력` 부분은 예시일 뿐이다.
> **실제 API Key 값은 이 문서, 커밋, 코드 어디에도 절대 작성하지 않는다.**
> 키는 실행하는 사람의 로컬 환경(터미널 입력, CI/CD 시크릿 저장소 등)에서만
> 전달한다.

## 5. ⚠️ Flutter Web에서 API Key 노출 위험

`--dart-define`으로 전달한 값은 컴파일 시점에 앱 코드에 그대로
문자열로 삽입된다. **Flutter Web으로 빌드하면 이 값이 JS 번들 파일
안에 그대로 남아, 브라우저 개발자 도구나 빌드 결과물 분석만으로도
API Key를 누구나 추출할 수 있다.**

즉, Flutter Web 앱이 `AI_API_KEY`를 가지고 AI 업체 API를 **직접**
호출하도록 만들면 그 즉시 키가 유출된 것과 같다. 모바일(Android/iOS)
빌드도 완전히 안전하지는 않다(디컴파일로 추출 가능).

## 6. 권장 구조: 서버/Edge Function을 경유한다

그러므로 실제 서비스에서는 Flutter 앱이 AI Provider를 **직접**
호출하지 않아야 한다. 대신 다음과 같은 흐름을 권장한다.

```
Flutter App  --(사진, 스타일, 앱 자체 인증 토큰)-->  백엔드 서버 / Supabase Edge Function
                                                          │
                                                          ├─ 여기에만 실제 AI_API_KEY 보관
                                                          ▼
                                                    Fal.ai / OpenAI / Stability AI / Replicate
```

- 실제 AI Provider의 API Key는 서버(또는 Supabase Edge Function)
  환경 변수에만 저장한다.
- Flutter 앱은 자체 백엔드에만 요청을 보내고, 백엔드가 AI Provider를
  대신 호출한 뒤 결과 이미지만 앱으로 돌려준다.
- 이렇게 하면 API Key가 클라이언트 빌드 결과물에 전혀 포함되지 않는다.

이 구조를 실제로 구축하는 것은 이번 작업 범위가 아니며,
지금은 이 구조로 쉽게 전환할 수 있도록 `AiGenerationService`와
`createAiGenerationService()`만 준비해 둔 상태다.

## 7. 지금 Provider를 fal 등으로 지정하면?

`AI_PROVIDER`를 `fal`, `openai`, `stability`, `replicate` 중 하나로
지정해 실행해도, 이번 단계에서는 **실제 네트워크 호출을 하지 않고
동일한 Mock 결과를 반환한다.** 콘솔에는 다음 안내만 출력된다
(API Key 등 민감 정보는 절대 출력하지 않는다).

```
선택된 AI Provider는 아직 연결되지 않아 Mock 서비스를 사용합니다.
```

## 8. 관련 코드 위치

| 역할 | 파일 |
| --- | --- |
| 실행 환경/Provider/API Key 설정 | `lib/config/app_environment.dart` |
| Provider별 서비스 생성 Factory | `lib/services/ai_generation_provider.dart` |
| AI 생성 서비스(현재는 Mock 구현) | `lib/services/ai_generation_service.dart` |
| 요청/응답 데이터 모델 | `lib/models/ai_generation_request.dart`, `lib/models/ai_generation_response.dart` |
