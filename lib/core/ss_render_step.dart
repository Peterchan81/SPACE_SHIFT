/// SS007 — MASTER UI 4-2-1(이미지 AI 렌더링) 진행 단계. 작업지시서 "렌더링 단계 예시" 순서 그대로
/// 5단계로 고정한다 — 실제 AI 연동이 바뀌어도 사용자에게 보여주는 단계 이름/순서는 이 한 곳만 바꾸면 된다.
library;

enum SsRenderStep {
  analyzingImage('이미지 분석 중'),
  applyingUserEdits('사용자 수정 사항 적용 중'),
  generatingSpaceImage('공간 이미지 생성 중'),
  finalizingImage('최종 이미지 처리 중'),
  preparingResult('완료 이미지 준비 중');

  const SsRenderStep(this.label);
  final String label;
}
