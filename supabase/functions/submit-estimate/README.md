# submit-estimate Edge Function

SPACE SHIFT의 무료 예상견적 요청을 `estimate_requests` 테이블에 접수한다.

## API

`POST /functions/v1/submit-estimate`

```json
{
  "spaceType": "거실",
  "approximateArea": "10~20평",
  "constructionScope": "부분 시공",
  "desiredColorTone": "베이지",
  "customColorTone": "",
  "notes": "수납공간을 늘리고 싶어요."
}
```

성공 응답:

```json
{ "success": true }
```

## 배포

이 함수는 별도 Secret 없이 Supabase가 모든 Edge Function에 자동으로 주입하는
`SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY`만 사용한다.

```bash
supabase db push
supabase functions deploy submit-estimate
```

## 로컬 실행

```bash
supabase functions serve submit-estimate
```
