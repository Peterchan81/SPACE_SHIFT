/// SS015 — MASTER UI 11(3D 아이소 랜더링) 진행 단계. MASTER UI 디자인(화면 캡처 체크리스트: "이미지
/// 품질 처리 중 · 재질 및 조명 적용 중 · 공간 분위기 렌더링 중 · 최종 이미지 생성 중 · 3D 아이소
/// 모델에 반영 중")에 보이는 5단계 문구를 그대로 고정한다 — 실제 렌더 엔진 내부 구현이 바뀌어도
/// 사용자에게 보여주는 단계 이름/순서는 이 한 곳만 바꾸면 된다([SsIsoConversionStep]/[SsRenderStep]과
/// 같은 패턴, SS012/SS007).
library;

enum SsIsoRenderStep {
  imageQualityProcessing('이미지 품질 처리 중'),
  materialLighting('재질 및 조명 적용 중'),
  atmosphereRendering('공간 분위기 렌더링 중'),
  finalImageGeneration('최종 이미지 생성 중'),
  applyToIsoModel('3D 아이소 모델에 반영 중');

  const SsIsoRenderStep(this.label);
  final String label;
}
