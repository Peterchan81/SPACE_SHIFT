# SPACE SHIFT – AI 연동 설정 가이드

## 구조

```text
Flutter App → Supabase generate-interior Edge Function → Fal.ai FLUX.1 Kontext Pro
```

Flutter 앱에는 AI Provider API Key를 저장하지 않는다. 앱은 공개된 Edge
Function URL만 알고, Fal.ai Secret은 Supabase Edge Function 환경에서만
읽는다.

## 기본 Mock 모드

아무 설정 없이 실행하면 기존 Mock 이미지를 사용한다.

```bash
flutter run --dart-define=AI_PROVIDER=mock
```

`AI_PROVIDER` 또는 `AI_EDGE_FUNCTION_URL`이 없을 때도 안전하게 Mock으로
동작하므로 로컬 개발과 자동 테스트에 외부 서비스가 필요하지 않다.

## 실제 AI 모드

Fal.ai에서 발급한 Key를 Supabase Secret으로만 등록한다. 실제 값을 코드,
문서, `.env.example`, Git 또는 Flutter 빌드 옵션에 넣지 않는다.

```bash
supabase secrets set FAL_KEY=...
supabase functions deploy generate-interior
```

배포 후 Flutter에는 Secret이 아닌 함수 URL만 전달한다.

```bash
flutter run \
  --dart-define=AI_PROVIDER=fal \
  --dart-define=AI_EDGE_FUNCTION_URL=https://<PROJECT_REF>.supabase.co/functions/v1/generate-interior
```

Release 빌드도 동일한 두 `dart-define`만 사용한다. `FAL_KEY`는 어떤
Flutter 명령에도 전달하지 않는다.

## 동작

- 앱은 원본 사진을 Base64 data URI와 선택 스타일로 Edge Function에 보낸다.
- Edge Function은 5개 허용 스타일을 구조 보존형 프롬프트로 변환한다.
- Fal.ai `fal-ai/flux-pro/kontext`가 원래 벽·창·문·구도·원근을 유지하며
  가구, 마감, 색상, 조명과 장식을 변경한다.
- 앱은 반환된 이미지 URL을 다운로드해 기존 결과·저장·공유 흐름에 전달한다.
- 실패 시 생성 화면에서 오류를 표시하고 사용자가 다시 시도할 수 있다.

## 필요한 외부 설정

1. Fal.ai 계정 및 유효한 `FAL_KEY`
2. Supabase 프로젝트 연결과 `FAL_KEY` Secret 등록
3. `generate-interior` 함수 배포
4. 배포된 `AI_EDGE_FUNCTION_URL`을 Flutter 빌드 시 주입
