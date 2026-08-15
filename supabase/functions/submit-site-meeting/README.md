# submit-site-meeting Edge Function

SPACE SHIFT의 현장미팅 문의를 `site_meeting_requests` 테이블에 접수한다.

## API

`POST /functions/v1/submit-site-meeting`

```json
{
  "name": "홍길동",
  "contact": "010-1234-5678",
  "visitArea": "서울시 강남구",
  "preferredDateTime": "8월 20일 오후 2시",
  "notes": "주말 방문을 희망합니다.",
  "privacyAgreed": true
}
```

`privacyAgreed`가 `true`가 아니면 400을 반환한다.

성공 응답:

```json
{ "success": true }
```

## 배포

이 함수는 별도 Secret 없이 Supabase가 모든 Edge Function에 자동으로 주입하는
`SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY`만 사용한다.

```bash
supabase db push
supabase functions deploy submit-site-meeting
```

## 로컬 실행

```bash
supabase functions serve submit-site-meeting
```
