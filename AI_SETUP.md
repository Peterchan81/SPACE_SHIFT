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
