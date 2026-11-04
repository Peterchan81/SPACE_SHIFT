/// SS012 — MASTER UI 9(3D 아이소 변환) 진행 단계. MASTER UI 디자인(화면 캡처 체크리스트: "이미지
/// 전처리 완료 · 공간 구조 분석 중 · 건축 요소 3D 모델링 중 · 재질 및 색상 적용 중 · 3D 아이소 모델
/// 생성 중")에 보이는 5단계 문구를 그대로 고정한다 — 실제 변환 엔진 내부 구현이 바뀌어도 사용자에게
/// 보여주는 단계 이름/순서는 이 한 곳만 바꾸면 된다([SsCadConversionStep]/[SsRenderStep]과 같은 패턴,
/// SS010/SS007).
library;

enum SsIsoConversionStep {
  preprocessing('이미지 전처리 완료'),
  spatialAnalysis('공간 구조 분석 중'),
  architecturalModeling('건축 요소 3D 모델링 중'),
  materialColor('재질 및 색상 적용 중'),
  isoModelGeneration('3D 아이소 모델 생성 중');

  const SsIsoConversionStep(this.label);
  final String label;
}
