# gpt-floorplan-iso Edge Function

GPT가 생성한 Clean CAD 스타일 2D 평면도(`gpt-floorplan-cad-image`의
결과)를 입력으로 받아, 같은 공간 배치를 반영한 3D 아이소메트릭 인테리어
이미지를 OpenAI `gpt-image-1`(이미지 편집)로 새로 그려서 돌려준다.

이 함수는 기존 실시간 geometry 3D(`SpaceSceneBuilderV2`/`three.js`,
`Space3DViewGpuV2`)를 대체하지 않는다 — V1 1차 완성에서 사용자에게
먼저 보여줄 "AI가 그려주는 아이소 이미지" 경로이며, 실시간 3D는 그대로
보존된다(V1 보완/V2에서 정확도를 강화할 대상).

## API

`POST /functions/v1/gpt-floorplan-iso`

```json
{
  "image": "data:image/png;base64,..."
}
```

`image`는 원본 사진이 아니라 **Clean 2D 평면도 이미지**(gpt-floorplan-
cad-image의 출력)를 전달한다.

성공 응답:

```json
{
  "success": true,
  "image": "data:image/png;base64,..."
}
```

기본 재질 규칙(프롬프트에 고정):
- 내부 벽: 흰색
- 일반 공간 바닥: 우드
- 욕실로 보이는 공간의 바닥/벽: 타일
- 시점: 위에서 내려다보는 bird's-eye 아이소메트릭
- 가구는 최소/기본 수준만(방 용도를 알아볼 정도), 과도한 인테리어
  디자인 금지

## Secret 및 배포

`gpt-floorplan-cad-image`와 같은 `OPENAI_API_KEY` Secret을 공유한다.

```bash
supabase secrets set OPENAI_API_KEY=...   # 이미 설정돼 있으면 생략
supabase functions deploy gpt-floorplan-iso
```

`OPENAI_API_KEY`가 없으면 함수는 외부 호출을 하지 않고 HTTP 503과
안전한 오류 메시지를 반환한다.

## Flutter 쪽 연결

`lib/services/gpt_floorplan_iso_service.dart`의
`createFloorPlanIsoImageService()`가
`--dart-define=GPT_FLOORPLAN_ISO_EDGE_FUNCTION_URL=...`로 이 함수의
배포 URL을 받으면 실제로 호출한다. 지정하지 않으면
`UnavailableFloorPlanIsoImageService`로 안전하게 폴백해, 네트워크 호출
없이 즉시 실패하고 화면은 기존 실시간 3D(가능하면) 또는 준비 안내로
대체한다.
