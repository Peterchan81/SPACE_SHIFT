# SPACE SHIFT – AI 이미지 생성 Provider 비교·분석 및 추천안

> 이 문서는 실제 AI API를 연결하기 전 단계의 **조사·설계 문서**다.
> 이번 작업에서는 어떤 AI 업체와도 실제로 연결하지 않으며,
> 본 문서의 목적은 향후 연동 시점에 근거 있는 의사결정을 내릴 수 있도록
> 객관적 비교 자료와 추천안, 그리고 안전한 연동 구조를 미리 설계해 두는 것이다.

작성 시점: 2026년 7월 기준 공개 요금제/자료를 근거로 작성했다.
AI API 요금은 변동이 매우 잦은 영역이므로(실제로 Stability AI는 2026년 8월
크레딧 단가를 소급 변경한 사례가 있다), **실제 계약/연동 시점에 반드시
각 업체의 최신 공식 요금 페이지를 재확인**해야 한다.

---

## 1. 비교 목적

SPACE SHIFT는 사용자가 업로드한 **자기 집 사진의 공간 구조(벽, 창문, 문,
천장, 바닥 배치 등)는 그대로 유지한 채, 인테리어 스타일(모던/북유럽/
호텔/우드/미니멀 등)만 바꿔주는** 서비스다. 즉 우리가 필요한 것은

- ❌ 텍스트만으로 새 이미지를 만드는 "생성형 아트"
- ❌ 사람 얼굴을 만들거나 보정하는 "인물 이미지 생성"
- ✅ **원본 사진의 구조를 최대한 보존하면서 표면(마감재·가구·색감·조명
  분위기)만 바꾸는 "구조 보존형 이미지 편집(Image-to-Image Editing)"**

이 기준에 가장 적합한 AI 서비스를 객관적으로 비교하고, 비용·품질·안정성·
연동 난이도·확장성을 종합해 SPACE SHIFT에 가장 알맞은 추천안을 도출하는
것이 이 문서의 목적이다.

## 2. 비교 대상

### 주 비교 대상 (4개, 요구사항 필수)

| Provider | 대표 모델(2026.07 기준) | 비고 |
| --- | --- | --- |
| **Fal.ai** | FLUX.1 Kontext (Pro/Max), FLUX Schnell/Dev, Seedream V4 등 | 서버리스 추론 특화, 다양한 오픈소스/독점 모델을 큐레이션해 API로 제공 |
| **OpenAI Images API** | GPT Image 1 / 1.5 (2026년 10월 GPT Image 1 단종 예정, 후속 모델로 전환 필요) | 텍스트-이미지 통합 모델, `edit` 엔드포인트로 이미지 편집 지원 |
| **Stability AI** | Stable Image Ultra / Core, SD3.5 (Large/Turbo) | Stable Diffusion 계열 원조 업체, 파인튜닝·ControlNet 생태계가 넓음 |
| **Replicate** | 1,000개 이상 모델 마켓플레이스(FLUX 계열, ControlNet, SDXL 등) 호스팅 | 모델 자체를 만들지 않고 다양한 모델을 GPU 단위 과금으로 서빙 |

### 참고 대상 (2개, 필요 시 참고)

| Provider | 대표 모델 | 비고 |
| --- | --- | --- |
| **Google Imagen / Gemini("Nano Banana") API** | Imagen 4 (Fast/Standard/Ultra), Gemini 2.5·3 Flash Image | 2026년 7월 기준 이미지 편집 품질 벤치마크 최상위권. Vertex AI/GCP 종속성이 있어 참고용으로만 포함 |
| **Adobe Firefly API** | Firefly Image Model | 학습 데이터가 라이선스 확보된 소스(Adobe Stock 등)로만 구성되어 상업적 책임 리스크가 가장 낮음. 다만 엔터프라이즈 계약(월 최소 비용 약 $1,000)이 필요해 초기 스타트업 단계에는 부담 |

---

## 3. 비교표

아래 표는 요청된 14개 항목을 모두 포함한다. 별점(★)은 5점 만점,
SPACE SHIFT의 핵심 요구사항인 **"구조 보존 + 인테리어 스타일 변경"**
관점에서 상대 평가한 값이다.

| # | 항목 | Fal.ai | OpenAI Images API | Stability AI | Replicate |
|---|---|---|---|---|---|
| 1 | 인테리어 이미지 변환 품질 | ★★★★★ | ★★★★☆ | ★★★★☆ | ★★★★★ |
| 2 | 원본 구조 유지(벽/창문/문 위치) | ★★★★★ (FLUX Kontext) | ★★★☆☆ | ★★★☆☆ (ControlNet 직접 구성 필요) | ★★★★★ (동일 모델 접근 가능) |
| 3 | 스타일 변경 능력(모던/북유럽/호텔/우드/미니멀) | ★★★★★ | ★★★★☆ | ★★★★☆ | ★★★★★ |
| 4 | 생성 속도 | ★★★★★ (수 초, 추론 최적화 특화) | ★★★☆☆ (고품질일수록 지연 증가) | ★★★★☆ | ★★★☆☆ (모델/GPU 콜드스타트 영향) |
| 5 | 가격(장당, 대표 모델 기준) | ★★★★☆ (~$0.03~0.05) | ★★★☆☆ (~$0.02~0.19) | ★★★★☆ (~$0.03~0.08) | ★★★☆☆ (동일 모델 대비 Fal보다 30~50% 비쌈) |
| 6 | 상업적 이용 가능 여부 | ✅ (모델별 라이선스 확인 필요) | ✅ (약관상 명확히 허용) | ✅ (모델별 라이선스 확인 필요) | ✅ (모델별 라이선스 확인 필요) |
| 7 | API 안정성 | ★★★★☆ | ★★★★★ (대기업 SLA·인프라) | ★★★☆☆ (요금 정책 변경 이력 등 변동성) | ★★★★☆ |
| 8 | 문서 품질 | ★★★★☆ | ★★★★★ | ★★★☆☆ | ★★★★☆ |
| 9 | Flutter 연동 난이도 | 낮음 (REST + JSON, SDK 불필요) | 낮음 (REST, 공식 SDK 多) | 낮음 (REST) | 낮음~중간 (모델별 입출력 스키마 상이) |
| 10 | 서버(Edge Function) 연동 난이도 | 낮음 | 낮음 | 낮음~중간 (모델별 파라미터 편차) | 중간 (모델 버전·스키마 변경 잦음) |
| 11 | 한국 서비스 운영 적합성 | 보통 (리전 고정, 국내 리전 없음) | 보통 (리전 고정, 국내 리전 없음) | 보통 | 보통 |
| 12 | 장기 유지보수성 | 높음 (모델 카탈로그 지속 업데이트) | 매우 높음 (단일 벤더, 버전 정책 명확) | 중간 (가격 정책 변동 이력) | 높음 (모델 다양성으로 대체 용이) |
| 13 | 무료 테스트 가능 여부 | 가입 시 소액 크레딧(정책 변동 가능) | 없음(과금 카드 등록 필요, 최초 소액 크레딧 제공되는 경우 있음) | ✅ 가입 시 25 크레딧 등 무료 크레딧 제공 | ✅ 신규 가입 크레딧 제공(모델별 상이) |
| 14 | 제한사항 | 모델별 상업 라이선스 상이, 국내 리전 없음 | 2026.10 GPT Image 1 단종 예정(후속 모델 마이그레이션 필요), 콘텐츠 정책 엄격 | ControlNet 등 구조 보존 파이프라인을 직접 구성해야 함(엔지니어링 비용↑), 최근 요금 정책 소급 변경 사례 | 요금이 상대적으로 비쌈, 모델 유지·삭제가 커뮤니티 소유주에 따라 달라질 수 있음 |

> 한국 리전: 4개 서비스 모두 한국 전용 리전을 제공하지 않는다(대부분
> 미국/유럽 리전). 다만 이미지 1장 처리에 걸리는 네트워크 왕복 지연은
> 전체 생성 시간(수 초~십수 초) 대비 비중이 작아 사용자 경험에 큰 영향은
> 없을 것으로 판단한다.

---

## 4. 비용 비교

### 4-1. 산정 기준

SPACE SHIFT의 실제 워크로드(인테리어 사진, 중~고품질 필요)를 감안해
아래 대표 모델/등급을 기준으로 계산했다. 실제 비용은 선택 모델·해상도·
품질 등급에 따라 크게 달라질 수 있다.

| Provider | 대표 모델(비교용) | 장당 단가 |
| --- | --- | --- |
| Fal.ai | FLUX.1 Kontext Pro (구조 보존 편집) | $0.04 |
| OpenAI Images API | GPT Image 1, medium quality | $0.07 |
| Stability AI | Stable Image Ultra | $0.08 |
| Replicate | FLUX Kontext급 모델(호스팅 마진 포함) | $0.045 |
| *(참고)* Google Imagen 4 | Standard | $0.04 |
| *(참고)* Adobe Firefly API | 표준 이미지 생성 | $0.02~$0.10 + **월 최소 약 $1,000 엔터프라이즈 계약** |

### 4-2. 예상 비용표 (부가세/카드 수수료 등 제외, 단순 장당 단가 × 수량)

| 수량 | Fal.ai | OpenAI Images API | Stability AI | Replicate |
| --- | --- | --- | --- | --- |
| 100장 | $4 | $7 | $8 | $4.5 |
| 1,000장 | $40 | $70 | $80 | $45 |
| 10,000장 | $400 | $700 | $800 | $450 |

> 참고: Adobe Firefly는 위 표의 어떤 수량에서도 월 최소 계약금(약 $1,000)이
> 실제 사용량 비용보다 크므로, 10,000장을 처리해도 월 청구액은 최소 계약금
> 수준(약 $1,000)에서 시작한다. 초기 트래픽이 적은 SPACE SHIFT 단계에서는
> 비용 효율이 가장 낮다.

### 4-3. 비용 관점 요약

- **가장 저렴**: Fal.ai (동일 계열 모델을 Replicate 대비 30~50% 저렴하게 제공)
- **중간**: Replicate (모델 선택 폭은 넓지만 호스팅 마진이 붙어 Fal보다 비쌈)
- **다소 비쌈**: OpenAI, Stability AI (다만 품질·안정성 대비 합리적인 수준)
- **가장 비쌈(소규모 기준)**: Adobe Firefly (엔터프라이즈 최소 계약금 구조)

10,000장 규모부터는 대부분의 업체가 **협상 가능한 볼륨 할인/엔터프라이즈
플랜**을 제공하므로, 실제 서비스가 이 규모에 도달하면 정가가 아닌 협상가
기준으로 재계산이 필요하다.

---

## 5. 품질 비교 (SPACE SHIFT 핵심 기준: 구조 보존형 스타일 변경)

2026년 7월 기준 이미지 편집 벤치마크(KontextBench 등 커뮤니티 리더보드)를
종합하면, **"원본을 보존하면서 편집"** 이라는 과제에서는 다음 순서로
평가된다.

1. **Google Gemini("Nano Banana") 계열** — 원본의 구도·조명·원근을 매우
   충실히 재구성. 편집 품질 리더보드 최상위. (참고 대상, 4개 필수
   비교군에는 없음)
2. **FLUX.1 Kontext (Fal.ai / Replicate에서 제공)** — 텍스트 지시 기반
   편집과 캐릭터/구조 보존에서 최상위권. 평균 응답 속도도 가장 빠른
   축에 속함(수 초 단위).
3. **GPT Image 1/1.5 (OpenAI)** — 자연어 지시 이해도가 높고 텍스트 렌더링,
   생태계 통합이 강점. 구조 보존은 "양호" 수준으로, Flux Kontext/Nano
   Banana 대비 원본 유지율이 다소 낮다는 커뮤니티 평가가 있다.
4. **Stability AI (SD3.5 / Stable Image)** — 기본 텍스트-이미지 생성
   품질은 우수하지만, "구조를 보존하며 스타일만 바꾸기"는 img2img
   strength 조절이나 **ControlNet(Depth/Canny/Segmentation) 파이프라인을
   직접 구성**해야 안정적으로 달성된다. 즉 모델 자체보다 우리 쪽 엔지니어링
   투자가 더 필요하다.

**결론**: SPACE SHIFT의 핵심 요구사항(구조 보존)에는 **FLUX.1 Kontext
계열 모델**이 가장 적합하며, 이 모델은 Fal.ai와 Replicate 양쪽에서 모두
API로 제공된다. 따라서 "어떤 회사냐"보다 "어떤 모델을 어떤 회사가 더
빠르고 싸고 안정적으로 서빙하느냐"가 실질적 결정 요인이 된다.

---

## 6. 추천 순위

### 🥇 1위 — Fal.ai

- FLUX.1 Kontext 등 **구조 보존형 이미지 편집에 특화된 최신 모델**을
  가장 빠르고 저렴하게 제공한다.
- 서버리스 추론에 특화되어 있어 **생성 속도**가 4개 후보 중 가장
  우수하다 — GenerateScreen의 "3초 대기" 같은 UX를 실제로 충족시키기
  가장 유리하다.
- 동일 모델 기준 Replicate보다 30~50% 저렴해 **단가 경쟁력**이 가장
  좋다.
- REST 기반 API로 Flutter/Edge Function 연동 난이도가 낮다.

### 🥈 2위 — OpenAI Images API

- **API 안정성·문서 품질·생태계**가 4개 후보 중 압도적으로 우수하다.
  대기업 SLA, 명확한 버전 정책, 풍부한 공식 SDK를 갖추고 있어 "장기
  운영 리스크"가 가장 낮다.
- 콘텐츠 정책·모더레이션이 내장되어 있어 상업 서비스 운영 시 **법적/
  정책적 리스크 관리**가 쉽다.
- 다만 구조 보존 정밀도는 Flux Kontext 대비 다소 아쉬우며, 가격도
  중간 이상이다. "빠른 실험보다 안정적인 장기 운영"을 우선할 때
  유리한 선택지다.

### 🥉 3위 — Replicate

- **모델 마켓플레이스**의 유연성이 가장 큰 강점 — Flux Kontext,
  ControlNet, 향후 나올 신규 오픈소스 모델까지 코드 변경 최소화로
  즉시 시도해볼 수 있다.
- 다만 Fal.ai와 동일 모델을 제공함에도 **가격이 더 비싸고**, 모델
  버전/스키마가 자주 바뀌어 유지보수 비용이 상대적으로 크다.
- **R&D/실험 단계**나, Fal.ai에 없는 특수 모델(예: 3D, 특정 커뮤니티
  파인튜닝 모델)이 필요할 때 보조 옵션으로 유용하다.

### 참고 — Stability AI (4위, 이번 순위에서는 제외)

- 파인튜닝·LoRA 생태계가 넓어 "SPACE SHIFT 전용 인테리어 모델"을
  자체 학습시키는 **장기 로드맵**에는 매력적이다.
- 다만 구조 보존을 위해서는 ControlNet 파이프라인을 직접 구성해야
  하는 **엔지니어링 비용**이 있고, 최근 크레딧 단가를 소급 변경한
  사례가 있어 **가격 정책 신뢰도**에 물음표가 남는다.
- 초기 단계보다는, 자체 모델 파인튜닝이 필요해지는 **성장 단계**에서
  재검토를 권장한다.

### 참고 — Google Gemini(Nano Banana)/Imagen, Adobe Firefly

- **Google**: 2026년 7월 기준 편집 품질 벤치마크 최상위. 다만 GCP/Vertex
  종속성, 4개 필수 비교군 외 서비스라는 점에서 이번 1~3위 산정에는
  포함하지 않았다. **품질 최우선 대안**으로 별도 PoC를 권장한다.
- **Adobe Firefly**: 상업적 라이선스 안전성(학습 데이터 전량 라이선스
  확보)이 가장 뛰어나 "저작권 분쟁 리스크 제로"가 중요해지는 단계
  (투자 유치, 대형 파트너십 등)에서 재검토할 가치가 있다. 다만 월 최소
  계약금 구조상 지금 단계에는 적합하지 않다.

---

## 7. SPACE SHIFT 추천안

**최종 추천: 1차 연동은 Fal.ai(FLUX.1 Kontext 계열)로 시작하고,
Provider 구조는 처음부터 OpenAI Images API로 즉시 교체 가능하게
설계한다.**

이유:

1. SPACE SHIFT의 핵심 가치 제안은 "내 방이 진짜 저렇게 바뀔 수 있겠다"는
   **신뢰감**이다. 이는 곧 원본 구조 보존 정밀도 = 제품 품질이라는
   뜻이며, 이 기준에서 Fal.ai(Flux Kontext)가 가장 앞선다.
2. GenerateScreen은 이미 "3초 대기" UX로 설계되어 있다. Fal.ai의 빠른
   추론 속도는 이 UX를 실제 서비스에서도 유지시켜줄 가능성이 가장 크다.
3. 이미 구현된 `AiProviderType`/`createAiGenerationService()` 구조
   덕분에, 만약 Fal.ai의 응답 품질이나 안정성이 기대에 못 미치면
   **화면 코드를 전혀 건드리지 않고** OpenAI Images API(2순위)로
   즉시 전환할 수 있다. 이것이 이번 Provider 구조 설계의 핵심 목적이다.
4. Stability AI/자체 파인튜닝, Google Gemini, Adobe Firefly는 서비스가
   성장한 이후(정확도 고도화, 법적 리스크 최소화, 커스텀 모델화 단계)
   재검토 대상으로 남겨둔다.

---

## 8. 권장 서버 구조

### 8-1. 전체 흐름

Flutter 앱은 **어떤 경우에도 AI 업체를 직접 호출하지 않는다.**
`AI_SETUP.md`에 이미 명시했듯, `--dart-define`으로 주입한 값은 Flutter
Web 빌드 결과물에서 그대로 노출될 수 있기 때문이다. 반드시 서버(또는
Supabase Edge Function)를 경유한다.

```
                 사용자
                   │  (사진 선택, 스타일 선택)
                   ▼
             ┌───────────────┐
             │  Flutter App  │  ← API Key를 절대 갖지 않는다
             └───────┬───────┘
                      │  ① HTTPS 요청
                      │     (사진 bytes, selectedStyle, 앱 자체 인증 토큰)
                      ▼
             ┌───────────────────────┐
             │   Edge Function        │  ← 실제 AI_API_KEY는 여기에만 존재
             │ (Supabase / 자체 서버) │     (환경 변수 / Secret Manager)
             └───────┬────────────────┘
                      │  ② 사용자 인증 검증, 요청 검증(용량/횟수 제한 등)
                      │  ③ AiProvider 인터페이스로 실제 Provider 호출
                      ▼
             ┌───────────────────────┐
             │      AI Provider        │
             │ (Fal.ai / OpenAI / ...) │
             └───────┬────────────────┘
                      │  ④ 생성된 이미지(또는 URL) 응답
                      ▼
             ┌───────────────────────┐
             │   Edge Function        │  ← 응답 검증/후처리, 필요 시 Storage 업로드
             └───────┬────────────────┘
                      │  ⑤ 결과(이미지 bytes 또는 다운로드 URL) 응답
                      ▼
             ┌───────────────┐
             │  Flutter App  │  → ResultScreen에 표시
             └───────────────┘
```

### 8-2. 왜 이 구조인가

- **API Key 보호**: 클라이언트(특히 Web)에는 절대 키가 포함되지 않는다.
- **비용 통제**: Edge Function 레이어에서 사용자별 호출 횟수/일일
  한도를 강제할 수 있어, 악의적 대량 호출로 인한 비용 폭증을 막는다.
- **Provider 교체 유연성**: 클라이언트는 자체 백엔드 API 스펙 하나만
  알면 되므로, 백엔드에서 Fal.ai → OpenAI 등으로 Provider를 바꿔도
  앱을 재배포할 필요가 없다(강제 업데이트 없이 서버만 배포하면 됨).
- **정책/모더레이션 삽입 지점 확보**: 부적절한 이미지 업로드 차단,
  워터마크 삽입, 사용량 과금 로직 등을 클라이언트가 아닌 신뢰 가능한
  서버 레이어에서 처리할 수 있다.

### 8-3. AI Provider 인터페이스 설계 (서버/Edge Function 측, 설계만 제시)

> 아래는 **설계 예시**이며, 이번 작업에서는 실제 코드를 작성하지 않는다.
> Dart(Edge Function이 Deno/Dart 기반이라고 가정) 또는 TypeScript 등
> 실제 구현 언어에 맞춰 동일한 개념으로 옮기면 된다.

```dart
/// 서버(Edge Function) 측에서 사용할, Provider에 무관한 공통 인터페이스.
/// Flutter 클라이언트의 AiGenerationService와 이름은 비슷하지만
/// 실행 위치(서버)와 책임(실제 네트워크 호출)이 다르다.
abstract class AiProvider {
  Future<AiGenerationResponse> generate(AiGenerationRequest request);
}

/// Fal.ai(FLUX.1 Kontext 등)를 호출하는 구현체.
class FalAiProvider implements AiProvider {
  FalAiProvider({required this.apiKey});
  final String apiKey; // Edge Function 환경 변수에서만 주입

  @override
  Future<AiGenerationResponse> generate(AiGenerationRequest request) async {
    // 1. request.imageBytes를 Fal.ai가 요구하는 형식(예: base64, 업로드 URL)으로 변환
    // 2. Fal.ai 이미지 편집 엔드포인트 호출 (스타일 프롬프트 + 원본 이미지)
    // 3. 응답을 공통 AiGenerationResponse 구조로 변환해 반환
    throw UnimplementedError('실제 연동은 이번 작업 범위가 아니다.');
  }
}

/// OpenAI Images API를 호출하는 구현체.
class OpenAiProvider implements AiProvider {
  OpenAiProvider({required this.apiKey});
  final String apiKey;

  @override
  Future<AiGenerationResponse> generate(AiGenerationRequest request) async {
    throw UnimplementedError('실제 연동은 이번 작업 범위가 아니다.');
  }
}

/// Replicate를 호출하는 구현체.
class ReplicateProvider implements AiProvider {
  ReplicateProvider({required this.apiKey});
  final String apiKey;

  @override
  Future<AiGenerationResponse> generate(AiGenerationRequest request) async {
    throw UnimplementedError('실제 연동은 이번 작업 범위가 아니다.');
  }
}

/// 서버 측 Factory. 클라이언트의 createAiGenerationService()와
/// 동일한 사상(Provider 교체가 호출부에 영향 없음)을 서버에도 적용한다.
AiProvider createServerAiProvider(AppEnvironment environment) {
  switch (environment.aiProvider) {
    case AiProviderType.fal:
      return FalAiProvider(apiKey: environment.serverOnlyApiKey);
    case AiProviderType.openai:
      return OpenAiProvider(apiKey: environment.serverOnlyApiKey);
    case AiProviderType.replicate:
      return ReplicateProvider(apiKey: environment.serverOnlyApiKey);
    case AiProviderType.stability:
    case AiProviderType.mock:
      return MockAiProvider(); // 서버에도 동일한 안전장치를 둔다
  }
}
```

이 구조는 **클라이언트에 이미 구현된 `AiGenerationService`/
`createAiGenerationService()` 패턴을 서버 레이어에 그대로 반복**하는
것이다. 클라이언트는 "서버에 요청 → 결과 수신"만 담당하고, "어떤
Provider를 어떻게 부르는지"는 전부 서버가 캡슐화한다. 즉 이중 계층으로
관심사가 분리된다.

```
Flutter (Provider를 모름)
   → 서버 API (Provider를 알지만 클라이언트에 숨김)
      → AiProvider 구현체 (실제 Provider별 호출 로직)
```

---

## 9. 향후 확장 전략

SPACE SHIFT가 이후 **영상 생성, 3D 생성, 가구 배치 추천, 견적 추천**까지
확장한다고 가정했을 때, 각 Provider의 생태계 적합성은 다음과 같다.

| Provider | 영상 생성 | 3D 생성 | 가구 배치(구조화된 출력) | 견적 추천 연계 |
| --- | --- | --- | --- | --- |
| Fal.ai | ★★★★☆ (다양한 영상 모델을 빠르게 카탈로그화) | ★★★☆☆ (3D 모델 일부 제공, 아직 제한적) | ★★★☆☆ (세그멘테이션/뎁스 모델 조합 가능) | ★★☆☆☆ (AI 자체 기능 아님, 별도 로직 필요) |
| OpenAI | ★★★☆☆ (Sora 등 자체 영상 모델 보유, API 개방 속도는 상대적으로 느림) | ★★☆☆☆ (3D 전용 모델 미보유) | ★★★☆☆ (구조화 출력·함수 호출과 결합 용이) | ★★★★☆ (LLM 기반 추천/함수 호출과 결합이 가장 쉬움) |
| Stability AI | ★★★☆☆ (Stable Video 계열 보유) | ★★★★☆ (Stable 3D 계열 보유, 생태계 존재) | ★★★☆☆ | ★★☆☆☆ |
| Replicate | ★★★★☆ (영상/3D 오픈소스 모델을 가장 빠르게 흡수) | ★★★★☆ (커뮤니티 3D 모델 다수) | ★★★☆☆ | ★★☆☆☆ |
| *(참고) Google* | ★★★★★ (Veo 등 최상급 영상 모델) | ★★★☆☆ | ★★★★☆ (Gemini의 구조화 출력/멀티모달 이해도 최상) | ★★★★★ (Gemini + Search 결합으로 견적/제품 추천까지 자연 확장) |

**시사점**:

- **영상/3D 생성**까지 고려하면 **Replicate**(다양한 오픈소스 모델을
  가장 빠르게 흡수)와 **Google**(Veo·Gemini 생태계)이 유리하다. 이는
  Provider 구조를 처음부터 "인터페이스로 추상화"해 둔 이번 설계가
  왜 중요한지 보여준다 — 이미지는 Fal.ai, 영상은 Replicate, 견적
  추천은 OpenAI/Gemini처럼 **기능별로 다른 Provider를 동시에 사용**하는
  것도 이 구조에서는 자연스럽다(`AiProvider` 인터페이스를 기능별로
  여러 개 두면 된다).
- **가구 배치 추천/견적 추천**은 이미지 생성 모델 자체보다 **LLM의
  구조화 출력(함수 호출, JSON 모드) 능력**이 더 중요해진다. 이 영역은
  OpenAI 또는 Google Gemini가 가장 앞서 있다.
- 결론적으로 SPACE SHIFT는 **"이미지 생성 = Fal.ai, 향후 텍스트/추천
  로직 = OpenAI 또는 Gemini"** 식으로 **기능별 멀티 Provider 체제**로
  자연스럽게 진화할 가능성이 높으며, 지금 설계한 `AiProviderType` +
  Factory 구조가 이런 확장을 코드 변경 최소화로 지원한다.

---

## 10. 최종 결론

1. SPACE SHIFT의 핵심 요구사항인 **"구조 보존 + 스타일 변경"** 은
   최신 이미지 편집 모델(FLUX.1 Kontext, Google Nano Banana 계열)이
   가장 잘 해결하며, 이 중 4개 필수 비교 대상에서 **가장 빠르고 저렴하게
   해당 모델에 접근할 수 있는 Fal.ai**를 1순위로 추천한다.
2. **OpenAI Images API**는 품질 1위는 아니지만 안정성·문서·생태계가
   압도적이라 2순위로 추천하며, Fal.ai에 문제가 생겼을 때의 **즉시
   대체(fallback) Provider**로 유효하다.
3. **Replicate**는 모델 다양성이 강점이라 3순위로 추천하며, 특히
   향후 영상·3D 확장 시 재조명될 가능성이 크다.
4. **Stability AI**는 자체 파인튜닝이 필요해지는 성장 단계에서,
   **Google/Adobe**는 각각 "품질 최우선" 및 "저작권 리스크 최소화"가
   중요해지는 단계에서 재검토를 권장한다.
5. 어떤 Provider를 선택하든 **Flutter 앱은 절대 AI 업체를 직접 호출하지
   않고, Edge Function(또는 자체 서버)을 경유**해야 하며, 이미 구현된
   `AiGenerationRequest`/`AiGenerationResponse`/`AiGenerationService`/
   `AiProviderType`/`createAiGenerationService()` 구조는 이 원칙을 그대로
   지키면서 실제 연동으로 확장할 수 있도록 설계되어 있다.
6. **다음 실행 단계(이번 작업 범위 밖)**: (1) Supabase Edge Function
   또는 자체 백엔드 스캐폴딩, (2) Fal.ai 계정 생성 및 무료 크레딧으로
   PoC 진행, (3) 실제 인테리어 사진 샘플셋으로 Fal.ai vs OpenAI 정성
   비교(A/B) 후 최종 확정.

---

## 참고 자료

- [Fal.ai Pricing 2026 — Real Cost per Image](https://pricepertoken.com/fal-ai-pricing)
- [AI Image & Video API Pricing 2026](https://www.teamday.ai/blog/ai-api-pricing-comparison-2026)
- [GPT Image 1 - API Pricing & Benchmarks | OpenRouter](https://openrouter.ai/openai/gpt-image-1)
- [OpenAI Image Generation API Pricing in 2026](https://www.aifreeapi.com/en/posts/openai-image-generation-api-pricing)
- [Stability AI (Stable Diffusion) API Pricing: Full Breakdown (2026)](https://developer.puter.com/tutorials/stability-ai-api-pricing/)
- [Stability AI - Developer Platform Pricing](https://platform.stability.ai/pricing)
- [AI Image Model Pricing - Replicate & Fal.ai API Costs 2026](https://pricepertoken.com/image)
- [fal.ai vs Replicate (2026): Which API platform wins?](https://www.scopeful.org/blog/fal-vs-replicate)
- [AI Image Pricing 2026: Google Gemini vs. OpenAI GPT Cost Analysis](https://intuitionlabs.ai/articles/ai-image-generation-pricing-google-openai)
- [Adobe Firefly API Pricing 2026](https://sudomock.com/blog/adobe-firefly-api-pricing-2026)
- [Best AI for Image Editing in 2026 — Ranked by Blind Human Votes](https://llm-stats.com/leaderboards/best-ai-for-image-editing)
- [Flux Kontext vs Nano Banana](https://www.tigrisdata.com/blog/flux-kontext-vs-nano-banana/)
- [Controlnet for Interior Design (Hugging Face Space)](https://huggingface.co/spaces/ml6team/controlnet-interior-design)

> 위 자료는 2026년 7월 기준 3자 리서치/블로그 자료를 포함하므로,
> 실제 계약 전에는 반드시 각 업체의 공식 문서로 최종 확인해야 한다.
