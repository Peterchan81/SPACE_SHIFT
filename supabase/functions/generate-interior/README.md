# generate-interior Edge Function

ASON Space의 AI 인테리어 이미지 생성 요청을 받는 Supabase Edge Function이다.

> ⚠️ 이번 단계에서는 **실제 Fal.ai 호출을 하지 않는다.**
> 요청 형식(POST/CORS/JSON/style/image)을 검증하고, 항상 더미(Mock)
> JSON 응답만 돌려주는 뼈대만 구현되어 있다. 실제 AI 연동은 이후
> 별도 작업에서 진행한다.

## 1. 역할

Flutter 앱은 Fal.ai(또는 다른 AI 업체)를 **직접 호출하지 않는다.**
반드시 이 Edge Function을 거쳐야 한다.

```
Flutter App → (이 Edge Function) generate-interior → (추후) Fal.ai
```

이렇게 하는 이유는 프로젝트 루트의 `AI_SETUP.md`, `AI_PROVIDER_COMPARISON.md`
문서에 이미 정리되어 있다: Flutter 클라이언트(특히 Web 빌드)에 API Key를
넣으면 빌드 결과물에서 그대로 노출되기 때문이다.

## 2. API 인터페이스

### Endpoint

```
POST /functions/v1/generate-interior
```

### Request

```json
{
  "style": "modern",
  "image": "base64로 인코딩된 이미지 문자열 또는 접근 가능한 이미지 URL"
}
```

- `style` (string, 필수): 사용자가 선택한 인테리어 스타일 이름
  (예: 모던, 미니멀, 북유럽, 호텔, 따뜻한 우드).
- `image` (string, 필수): 원본 사진. **Base64 인코딩 문자열** 또는
  **접근 가능한 URL 문자열** 둘 다 받을 수 있도록 설계되어 있다.
  (실제로 어느 형식을 어떻게 판별/검증할지는 Fal.ai 연동 시점에 구체화한다.)

### Response — 성공 (이번 단계: 항상 Mock)

```json
{
  "success": true,
  "provider": "mock",
  "message": "Edge Function 준비 완료",
  "imageUrl": null
}
```

실제 연동 이후에는 다음과 같은 형태가 된다.

```json
{
  "success": true,
  "provider": "fal",
  "imageUrl": "https://..."
}
```

### Response — 실패

```json
{
  "success": false,
  "message": "style 값이 필요합니다."
}
```

| 상황 | HTTP 상태 코드 |
| --- | --- |
| POST가 아닌 메서드로 호출 | 405 |
| 요청 본문이 JSON이 아님 | 400 |
| `style` 누락/빈 값 | 400 |
| `image` 누락/빈 값 | 400 |
| 처리 중 예외 발생 | 500 |

모든 응답(성공/실패, OPTIONS 포함)에는 CORS 헤더가 포함되어 Flutter Web
등 브라우저 환경에서도 호출할 수 있다.

## 3. 보안 원칙 (반드시 지킨다)

1. **Flutter(클라이언트)에는 어떤 AI API Key도 저장하지 않는다.**
   `AppEnvironment`의 `AI_API_KEY`(dart-define)는 현재 항상 빈 값이며,
   설령 값이 채워지더라도 클라이언트가 AI 업체를 직접 호출하는 데
   사용해서는 안 된다.
2. **Fal.ai API Key 같은 Secret은 Edge Function만 접근할 수 있다.**
   Supabase Secrets(`supabase secrets set ...`)로만 등록하고, 코드나
   `.env.example`, 이 README에도 실제 값을 절대 적지 않는다.
3. **Fal.ai(및 향후 다른 AI Provider)는 항상 Edge Function을 통해서만
   호출한다.** Flutter → Edge Function → AI Provider → Edge Function →
   Flutter 순서를 반드시 지킨다.
4. Edge Function 내부에서도 오류가 발생하면 예외를 그대로 노출하지
   않고, `{ success: false, message: ... }` 형태로 안전하게 변환해
   응답한다.

## 4. 환경 변수

`.env.example`(같은 폴더)을 참고한다. 로컬 개발 시에는 이 파일을
복사해 `.env`로 만들고 실제 값을 채워 사용한다. **`.env` 파일은 git에
커밋하지 않는다.**

```
FAL_API_KEY=
AI_PROVIDER=fal
```

이번 단계에서는 실제 Fal.ai 호출이 없으므로 `FAL_API_KEY`가 비어 있어도
Edge Function은 정상 동작한다(Mock 응답만 반환).

## 5. Supabase Secrets 등록 (배포 환경, 실제 연동 이후)

배포된 Edge Function은 `.env` 파일이 아니라 Supabase Secrets에서 값을
읽는다. 실제 연동 시점에 아래 명령으로 등록한다.

```bash
# 실제 키 값은 아래 "..." 자리에 절대 커밋/문서화하지 않는다.
supabase secrets set FAL_API_KEY=...
supabase secrets set AI_PROVIDER=fal
```

등록된 Secret 목록 확인:

```bash
supabase secrets list
```

## 6. 로컬 실행

```bash
# 1. Supabase 로컬 스택 시작 (최초 1회 또는 재부팅 후)
supabase start

# 2. generate-interior 함수만 로컬에서 서빙
supabase functions serve generate-interior
```

로컬 호출 예시:

```bash
curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/generate-interior' \
  --header 'Content-Type: application/json' \
  --data '{
    "style": "modern",
    "image": "base64-or-url-placeholder"
  }'
```

## 7. 배포

```bash
supabase functions deploy generate-interior
```

배포 전 `supabase login`, `supabase link --project-ref <PROJECT_REF>`로
프로젝트 연결이 되어 있어야 한다.

## 8. 다음 단계 (이번 작업 범위 아님)

- `index.ts` 상단 TODO 주석을 참고해 실제 Fal.ai 이미지 편집 API 호출
  구현
- 요청/응답 크기 제한, Rate Limit 등 운영 안전장치 추가
- 생성 결과 이미지를 Supabase Storage에 저장하고 서명된 URL 반환
- 사용자 인증(Supabase Auth) 연계 후 `config.toml`의 `verify_jwt`를
  `true`로 전환
