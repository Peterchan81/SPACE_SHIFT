# gpt-floorplan-cad-image Edge Function

사용자가 업로드한 평면도 사진을 OpenAI `gpt-image-1`(이미지 편집)에 보내,
원본의 배치/벽/문/창을 최대한 유지한 **깨끗한 CAD 스타일 2D 평면도
이미지**를 새로 그려서 돌려준다.

이 함수는 `gpt-floorplan-understand`(구조화 좌표 JSON을 돌려주던 이전
경로)를 대체하는 V1 production 경로다 — `gpt-floorplan-understand`는
삭제하지 않고 R&D/대체 경로로 남아 있지만, 화면에는 더 이상 연결하지
않는다.

## API

`POST /functions/v1/gpt-floorplan-cad-image`

```json
{
  "image": "data:image/png;base64,..."
}
```

성공 응답:

```json
{
  "success": true,
  "image": "data:image/png;base64,..."
}
```

프롬프트는 다음을 명시적으로 요구한다:
- 원본 공간 배치/벽 위치/두께/문·창 위치를 그대로 유지
- 새 방/벽/문/창을 추가하거나 기존 것을 제거·병합하지 않음
- 전체 비율(외곽선) 변경 금지
- 가구/바닥무늬/글자/치수 텍스트/사진 노이즈는 정리 가능(간단한 흑백
  CAD 선 도면 스타일로)

## Secret 및 배포

`gpt-floorplan-understand`와 같은 `OPENAI_API_KEY` Secret을 공유한다.

```bash
supabase secrets set OPENAI_API_KEY=...   # 이미 설정돼 있으면 생략
supabase functions deploy gpt-floorplan-cad-image
```

`OPENAI_API_KEY`가 없으면 함수는 외부 호출을 하지 않고 HTTP 503과
안전한 오류 메시지를 반환한다.

## Flutter 쪽 연결

`lib/services/gpt_floorplan_image_service.dart`의
`createFloorPlanImageGenerationService()`가
`--dart-define=GPT_FLOORPLAN_IMAGE_EDGE_FUNCTION_URL=...`로 이 함수의
배포 URL을 받으면 실제로 호출한다. 지정하지 않으면
`UnavailableFloorPlanImageGenerationService`로 안전하게 폴백해, 네트워크
호출 없이 즉시 실패하고 화면은 원본 사진을 그대로 보여준다.
