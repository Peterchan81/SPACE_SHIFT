# SPACE SHIFT – AI · 리드 접수 연동 설정 가이드

## 구조

```text
Flutter App → Supabase generate-interior Edge Function → Fal.ai FLUX.1 Kontext Pro
Flutter App → Supabase submit-estimate Edge Function      → estimate_requests 테이블
Flutter App → Supabase submit-site-meeting Edge Function  → site_meeting_requests 테이블
```

Flutter 앱에는 AI Provider API Key를 저장하지 않는다. 앱은 공개된 Edge
Function URL만 알고, Fal.ai Secret은 Supabase Edge Function 환경에서만
읽는다. 예상견적/현장미팅 접수 함수는 Supabase가 모든 Edge Function에
자동으로 주입하는 `SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY`만 사용하므로
별도 Secret 등록이 필요 없다.

## 기본 Mock 모드

아무 설정 없이 실행하면 AI는 기존 Mock 이미지를, 예상견적/현장미팅
접수는 로컬 즉시-성공 Mock을 사용한다.

```bash
flutter run --dart-define=AI_PROVIDER=mock
```

`AI_PROVIDER`, `AI_EDGE_FUNCTION_URL`, `ESTIMATE_EDGE_FUNCTION_URL`,
`SITE_MEETING_EDGE_FUNCTION_URL`이 없을 때도 안전하게 Mock으로 동작하므로
로컬 개발과 자동 테스트에 외부 서비스가 필요하지 않다.

## 실제 AI 모드

Fal.ai에서 발급한 Key를 Supabase Secret으로만 등록한다. 실제 값을 코드,
문서, `.env.example`, Git 또는 Flutter 빌드 옵션에 넣지 않는다.

```bash
supabase secrets set FAL_KEY=...
supabase functions deploy generate-interior
```

## 예상견적 · 현장미팅 접수 배포

두 함수는 Secret 없이 DB 마이그레이션과 함수 배포만 하면 된다.

```bash
supabase db push
supabase functions deploy submit-estimate
supabase functions deploy submit-site-meeting
```

## Release 빌드

배포 후 Flutter에는 Secret이 아닌 함수 URL만 전달한다. Edge Function
URL은 Secret이 아니라 공개 엔드포인트이므로 dart-define으로 노출되어도
안전하다.

```bash
flutter run \
  --dart-define=AI_PROVIDER=fal \
  --dart-define=AI_EDGE_FUNCTION_URL=https://mljvgngjmrvoqjwvvyeg.supabase.co/functions/v1/generate-interior \
  --dart-define=ESTIMATE_EDGE_FUNCTION_URL=https://mljvgngjmrvoqjwvvyeg.supabase.co/functions/v1/submit-estimate \
  --dart-define=SITE_MEETING_EDGE_FUNCTION_URL=https://mljvgngjmrvoqjwvvyeg.supabase.co/functions/v1/submit-site-meeting
```

`flutter build appbundle`/`flutter build ipa` 등 실제 배포용 빌드도 반드시
위 네 `dart-define`을 함께 지정해야 한다. 하나라도 빠지면 해당 기능만
조용히 Mock으로 동작하므로, 릴리스 빌드 명령에 이 네 줄을 그대로
포함해야 한다. `FAL_KEY`와 `SUPABASE_SERVICE_ROLE_KEY`는 어떤 Flutter
명령에도 전달하지 않는다.

## SS CAD TEST — "GPT 구조 분석 실행" 실사용 확인

`GPT_FLOORPLAN_EDGE_FUNCTION_URL`을 지정하지 않고 실행하면(예: 그냥
`flutter run -d windows`) "GPT 구조 분석 실행" 버튼은 **항상, 즉시**
"GPT 구조 분석에 실패했습니다. 잠시 후 다시 시도해주세요."로 실패한다 —
이것은 버그가 아니라 [UnavailableVisionInterpretationService]의 의도된
안전한 기본값이지만, 실제 화면에서는 원인을 구분할 방법이 없다. 실제로
GPT 구조 분석까지 확인하려면 반드시 아래 URL을 함께 지정해야 한다:

```bash
flutter run -d windows \
  --dart-define=GPT_FLOORPLAN_EDGE_FUNCTION_URL=https://mljvgngjmrvoqjwvvyeg.supabase.co/functions/v1/gpt-floorplan-understand
```

이 URL도 Secret이 아니라 공개 Edge Function 엔드포인트다. Edge Function
자체의 `OPENAI_API_KEY` 배포 방법은
`supabase/functions/gpt-floorplan-understand/README.md`를 참고한다.

## SS CAD TEST — "OpenAI 직접 호출" 개발/검증 전용 우회 경로

기본 경로는 항상 `App → Supabase Edge Function → OpenAI`다
(`GPT_FLOORPLAN_PROVIDER` 기본값 `supabase`). Supabase 배포 상태와 무관하게
OpenAI 응답 자체를 검증하고 싶을 때만, **Windows 개발 실행에 한해** 아래처럼
Supabase를 건너뛰고 OpenAI를 직접 호출할 수 있다:

```bash
flutter run -d windows ^
  --dart-define=GPT_FLOORPLAN_PROVIDER=direct ^
  --dart-define=OPENAI_API_KEY=<로컬에서만 쓰는 실제 키, 문서/커밋에 적지 않는다>
```

Supabase 경로(기존과 동일, provider를 명시하고 싶을 때):

```bash
flutter run -d windows ^
  --dart-define=GPT_FLOORPLAN_PROVIDER=supabase ^
  --dart-define=GPT_FLOORPLAN_EDGE_FUNCTION_URL=<Edge Function URL>
```

**반드시 지킨다:**
- `OPENAI_API_KEY`는 `.dart` 파일에 하드코딩하지 않고, 어떤 커밋/문서에도
  실제 값을 적지 않는다.
- `flutter build apk`/`appbundle`/`ipa` 등 배포용 빌드 명령에는
  `OPENAI_API_KEY`(그리고 `GPT_FLOORPLAN_PROVIDER=direct`)를 **절대**
  포함하지 않는다 — 지정하지 않으면 컴파일 시점에 빈 문자열로 고정되어
  배포 바이너리에 key가 남을 수 없다. 배포용 빌드는 항상 기본값
  (`supabase`)이어야 한다.
- `GPT_FLOORPLAN_PROVIDER`를 인식하지 못하는 값으로 잘못 지정해도
  안전하게 `supabase`로 취급된다([parseGptFloorplanProvider]).

direct 경로의 요청(OpenAI model/system prompt/JSON schema)과 응답 변환은
`lib/services/gpt_floorplan_openai_contract.dart`에 Edge Function
(`supabase/functions/gpt-floorplan-understand/index.ts`)과 동일하게
미러링되어 있다 — 두 파일 중 하나만 고치면 두 경로의 결과가 갈라지므로,
이 계약을 바꿀 때는 반드시 둘 다 함께 고친다.

## 동작

- 앱은 원본 사진을 Base64 data URI와 선택 스타일로 Edge Function에 보낸다.
- Edge Function은 5개 허용 스타일을 구조 보존형 프롬프트로 변환한다.
- Fal.ai `fal-ai/flux-pro/kontext`가 원래 벽·창·문·구도·원근을 유지하며
  가구, 마감, 색상, 조명과 장식을 변경한다.
- 앱은 반환된 이미지 URL을 다운로드해 기존 결과·저장·공유 흐름에 전달한다.
- 실패 시 생성 화면에서 오류를 표시하고 사용자가 다시 시도할 수 있다.
- 결과 화면의 "무료 예상견적 받기"/"현장미팅 문의하기" 폼을 제출하면 앱은
  submit-estimate/submit-site-meeting Edge Function을 호출해 해당 테이블에
  저장한다.
- 접수에 실패하면 폼 화면에 오류 메시지를 표시하고 완료 화면으로 넘어가지
  않으며, 사용자는 다시 제출을 시도할 수 있다.

## 필요한 외부 설정

1. Fal.ai 계정 및 유효한 `FAL_KEY`
2. Supabase 프로젝트 연결과 `FAL_KEY` Secret 등록
3. `generate-interior` 함수 배포
4. `supabase db push`로 `estimate_requests`/`site_meeting_requests` 테이블 생성
5. `submit-estimate`/`submit-site-meeting` 함수 배포
6. 배포된 네 `dart-define`(`AI_PROVIDER`, `AI_EDGE_FUNCTION_URL`,
   `ESTIMATE_EDGE_FUNCTION_URL`, `SITE_MEETING_EDGE_FUNCTION_URL`)을
   Flutter 릴리스 빌드 시 주입
