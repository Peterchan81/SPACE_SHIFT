# generate-interior Edge Function

SPACE SHIFT의 원본 공간 사진을 Fal.ai FLUX.1 Kontext Pro로 편집한다.

## API

`POST /functions/v1/generate-interior`

```json
{
  "style": "모던",
  "image": "data:image/png;base64,..."
}
```

허용 스타일은 `모던`, `미니멀`, `북유럽`, `호텔`, `따뜻한 우드`다.

성공 응답:

```json
{
  "success": true,
  "provider": "fal",
  "imageUrl": "https://..."
}
```

## Secret 및 배포

Fal.ai Key는 반드시 Supabase Secret에만 저장한다.

```bash
supabase secrets set FAL_KEY=...
supabase functions deploy generate-interior
```

`FAL_KEY`가 없으면 함수는 외부 호출을 하지 않고 HTTP 503과 안전한 오류
메시지를 반환한다. Secret 값은 로그나 응답에 포함하지 않는다.

## 로컬 실행

로컬 전용 `.env`에 `FAL_KEY`를 설정하고 Git에 포함하지 않는다.

```bash
supabase functions serve generate-interior --env-file supabase/functions/.env
```
