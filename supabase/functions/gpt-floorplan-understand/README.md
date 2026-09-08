# gpt-floorplan-understand Edge Function

사용자가 업로드한 평면도 이미지를 GPT Vision(OpenAI `gpt-4o`)으로 분석해,
구조화된 공간 이해 결과(`VisionUnderstanding` 계약과 동일한 모양)를
돌려준다. GPT는 "이 평면도가 무엇인지" — 외곽/공간/벽/문·창의 대략적인
위치와 용도만 이해하고, 정밀 CAD 좌표 확정은 Flutter 쪽
`HintedGeometryExtractor`/`TopologyValidator`가 실제 픽셀 evidence로
다시 검증한다.

## API

`POST /functions/v1/gpt-floorplan-understand`

```json
{
  "image": "data:image/png;base64,..."
}
```

성공 응답 (`understanding`은 `ason_space/lib/models/vision_understanding.dart`의
`VisionUnderstanding.fromJson`이 그대로 읽을 수 있는 모양이다):

```json
{
  "success": true,
  "understanding": {
    "floorDomain": { "...": "..." },
    "spaces": [ { "...": "..." } ],
    "boundaries": [ { "...": "..." } ],
    "openings": [ { "...": "..." } ],
    "objects": [],
    "structuralElements": [],
    "dimensions": [],
    "scaleConfirmed": false,
    "notes": []
  }
}
```

이 함수는 실제 mm 치수를 절대 만들어내지 않는다 — `scaleConfirmed`는
항상 `false`로 고정된다. 실제 축척은 이후 사용자 calibration(치수 보정)
으로만 확정한다.

## Secret 및 배포

OpenAI Key는 반드시 Supabase Secret에만 저장한다.

```bash
supabase secrets set OPENAI_API_KEY=...
supabase functions deploy gpt-floorplan-understand
```

`OPENAI_API_KEY`가 없으면 함수는 외부 호출을 하지 않고 HTTP 503과 안전한
오류 메시지를 반환한다. Secret 값은 로그나 응답에 포함하지 않는다.

## 로컬 실행

로컬 전용 `.env`에 `OPENAI_API_KEY`를 설정하고 Git에 포함하지 않는다.

```bash
supabase functions serve gpt-floorplan-understand --env-file supabase/functions/.env
```

## Flutter 쪽 연결

`lib/services/gpt_floorplan_vision_service.dart`의
`createVisionInterpretationService()`가 `--dart-define=GPT_FLOORPLAN_EDGE_FUNCTION_URL=...`
로 이 함수의 배포 URL을 받으면 실제로 이 함수를 호출한다. 지정하지
않으면 `UnavailableVisionInterpretationService`로 안전하게 폴백해,
네트워크 호출 없이 즉시 "아직 설정되지 않음"으로 실패하고 기존 geometry
전용 분석으로 이어진다.
