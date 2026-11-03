/// SS010 — MASTER UI 7(평면도 CAD변환) 진행 단계. MASTER UI 디자인(화면 캡처 체크리스트)에 보이는
/// 5단계 문구를 그대로 고정한다 — 실제 변환 엔진 내부 구현이 바뀌어도 사용자에게 보여주는 단계 이름/
/// 순서는 이 한 곳만 바꾸면 된다([SsRenderStep]과 같은 패턴, SS007). "Geometry Validation"
/// 단계(작업지시서 처리 단계의 4번째)는 MASTER UI에 별도 체크리스트 줄로 나타나지 않는다 — 생략하지
/// 않고 [wallOpeningGeometry] 단계가 끝나는 시점에 함께 수행한다([CadConversionService] 참고).
library;

enum SsCadConversionStep {
  preprocessing('이미지 전처리 완료'),
  spatialAnalysis('공간 구조 분석 중'),
  wallOpeningGeometry('벽/문/창 인식 중'),
  dimensionScale('치수 계산 중'),
  cadGeneration('CAD 도면 생성 중');

  const SsCadConversionStep(this.label);
  final String label;
}
