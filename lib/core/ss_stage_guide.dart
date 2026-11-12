/// SS-수정003 — 공통 머리말([SsStageHeader])의 한 줄 안내 문장.
///
/// MASTER UI 화면처럼 큰 제목 아래 안내 문장 한 줄로 3초 법칙(SS001·SS003 — 지금 어디인지,
/// 다음에 무엇을 하는지)을 지킨다. MASTER 화면에 있는 문구를 우선 쓴다(예: MASTER 3 프로젝트 관리).
/// 개발용 번호 상자·"다음: …" 표시는 쓰지 않는다.
library;

import 'ss_stage.dart';

abstract final class SsStageGuide {
  /// 그 단계 머리말에 보일 안내 문장(지금 하는 일 + 다음에 할 일).
  static String sentenceFor(SsStage stage) => switch (stage) {
        SsStage.login => '이메일과 비밀번호를 입력하고 로그인하세요.',
        SsStage.home => 'AI와 함께, 당신의 공간을 새롭게 디자인하세요.',
        SsStage.projectManagement => '진행 중인 프로젝트를 선택하여 작업을 계속하거나 새로운 프로젝트를 만들어보세요.',
        SsStage.projectCreation => '프로젝트 이름과 시작 방식을 정해 새로운 프로젝트를 만들어보세요.',
        SsStage.directDrawing => '벽을 그려 평면도를 직접 만들고, 완성되면 CAD 변환으로 넘어가세요.',
        SsStage.imageEditing => '실제 공간 사진에서 바꿀 부분을 고르고 원하는 스타일을 적어보세요.',
        SsStage.imageRendering => 'AI가 이미지를 만들고 있습니다. 완료되면 결과를 확인하세요.',
        SsStage.imageResult => '완성된 이미지를 확인하고, 수정하거나 파일로 내보내세요.',
        SsStage.floorPlanUpload => '평면도 이미지나 PDF를 업로드하면 AI가 공간을 인식합니다.',
        SsStage.floorPlanReview => 'AI가 인식한 공간을 확인하고, 틀린 곳을 고친 뒤 CAD 변환을 진행하세요.',
        SsStage.cadConversion => '평면도를 CAD 도면으로 변환하고 있습니다. 변환이 끝나면 CAD를 편집하세요.',
        SsStage.cadEditor => 'CAD 도면의 치수를 확인·수정하고, DXF로 내보내거나 3D로 넘어가세요.',
        SsStage.isoConversion => 'CAD 도면으로 3D ISO 공간을 만들고 있습니다. 완료되면 3D 디자인을 시작하세요.',
        SsStage.isoEditor => '3D 공간에서 마감재와 가구를 골라 디자인해보세요.',
        SsStage.elevationFaceEditor => '선택한 벽면을 정면에서 보며 마감을 디자인하세요.',
        SsStage.isoRendering => '최종 3D 이미지를 만들고 있습니다. 완료되면 결과를 확인하세요.',
        SsStage.finalResult => '최종 ISO·투시도를 확인하고 파일로 내보내세요.',
      };
}
