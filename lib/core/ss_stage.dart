/// SS001 §4.2 / §16 / §22-2 — SPACE SHIFT 전체 작업 단계(Route), 3가지 작업 FLOW, MASTER UI 매핑, 좌측 Navigation 기본 원칙.
///
/// SS002~SS017은 이 단계 이름과 FLOW 순서를 그대로 쓴다. 단계별 세부 화면은 각 Work Order에서 구현한다
/// (SS001은 공통 기반만 — §17).
library;

/// 프로젝트가 시작되는 방식(SS001 §5 sourceType).
enum SsSourceType {
  floorPlanUpload('평면도 업로드'),
  directDraw('직접 그리기'),
  imageTransform('이미지 변환');

  const SsSourceType(this.label);
  final String label;
}

/// 작업 단계. [routeName]은 Navigator 이름, [masterUi]는 MASTER UI 이미지 번호, [workOrder]는 그 화면을 구현하는 작업지시서.
enum SsStage {
  login('/login', '로그인', '1', 'SS002', '계정으로 로그인합니다', '이메일과 비밀번호를 입력하고 로그인하세요'),
  home('/home', '홈', '2', 'SS003', 'SPACE SHIFT 시작 화면입니다', '3가지 시작 방식 중 하나를 고르세요'),
  projectManagement('/projects', '프로젝트 관리', '3', 'SS004', '내 프로젝트를 모아 봅니다', '이어서 할 프로젝트를 고르거나 새로 만드세요'),
  projectCreation('/projects/new', '프로젝트 생성', '4', 'SS004', '새 프로젝트를 만듭니다', '이름과 시작 방식을 정하세요'),
  directDrawing('/draw', '직접 그리기', '4-1', 'SS005', '평면도를 직접 그립니다', '벽을 그려 공간을 만드세요'),
  imageEditing('/image/edit', '이미지 디자인', '4-2', 'SS006', '실제 공간 사진을 디자인합니다', '바꿀 부분을 고르고 원하는 스타일을 적으세요'),
  imageRendering('/image/render', '이미지 AI 렌더링', '4-2-1', 'SS007', 'AI가 이미지를 만들고 있습니다', '완료되면 결과를 확인하세요'),
  imageResult('/image/result', '이미지 결과', '4-2-2', 'SS007', '완성된 이미지를 확인합니다', '수정하거나 파일로 내보내세요'),
  floorPlanUpload('/plan/upload', '평면도 업로드', '5', 'SS008', '평면도를 올리고 AI가 공간을 인식합니다', '평면도 이미지나 PDF를 올리세요'),
  floorPlanReview('/plan/review', '평면도 확인·보정', '6', 'SS009', 'AI가 인식한 공간을 확인합니다', '틀린 곳을 고친 뒤 CAD 변환을 누르세요'),
  cadConversion('/cad/convert', 'CAD 변환', '7', 'SS010', '평면도를 CAD로 바꾸고 있습니다', '변환이 끝나면 CAD를 편집하세요'),
  cadEditor('/cad/edit', 'CAD 편집·내보내기', '8', 'SS011', 'CAD 도면을 편집합니다', '치수를 확인하고 DXF로 내보내거나 3D로 넘어가세요'),
  isoConversion('/iso/convert', '3D ISO 변환', '9', 'SS012', 'CAD로 3D ISO를 만들고 있습니다', '완료되면 3D 디자인을 시작하세요'),
  isoEditor('/iso/edit', '3D ISO 디자인', '10', 'SS013', '3D 공간을 디자인합니다', '마감재와 가구를 고르세요'),
  elevationFaceEditor('/iso/face', '정면도·측면도 디자인', '10', 'SS014', '선택한 면을 정면에서 디자인합니다', '면을 고르고 마감을 정하세요'),
  isoRendering('/iso/render', '3D ISO 렌더링', '11', 'SS015', '최종 3D 이미지를 만들고 있습니다', '완료되면 결과를 확인하세요'),
  finalResult('/result', '최종 결과', '12', 'SS016', '최종 ISO·투시도를 확인합니다', '결과를 확인하고 파일로 내보내세요');

  const SsStage(this.routeName, this.title, this.masterUi, this.workOrder, this.whatIsThis, this.whatNext);

  final String routeName;
  final String title;
  final String masterUi;
  final String workOrder;

  /// 3초 법칙(SS001 §15) — "지금 무엇을 하는 화면인가?"
  final String whatIsThis;

  /// 3초 법칙 — "다음에 무엇을 해야 하는가?"
  final String whatNext;

  static SsStage? fromRoute(String? name) {
    for (final s in SsStage.values) {
      if (s.routeName == name) return s;
    }
    return null;
  }

  static SsStage? fromName(String? name) {
    for (final s in SsStage.values) {
      if (s.name == name) return s;
    }
    return null;
  }
}

/// SS001 §2 — 3가지 작업 FLOW. 프로젝트 작업 단계만(로그인·홈·관리·생성은 공통 입구).
abstract final class SsFlows {
  static const List<SsStage> entry = [SsStage.login, SsStage.home, SsStage.projectManagement, SsStage.projectCreation];

  static const Map<SsSourceType, List<SsStage>> stages = {
    SsSourceType.floorPlanUpload: [
      SsStage.floorPlanUpload,
      SsStage.floorPlanReview,
      SsStage.cadConversion,
      SsStage.cadEditor,
      SsStage.isoConversion,
      SsStage.isoEditor,
      SsStage.elevationFaceEditor,
      SsStage.isoRendering,
      SsStage.finalResult,
    ],
    SsSourceType.directDraw: [
      SsStage.directDrawing,
      SsStage.cadConversion,
      SsStage.cadEditor,
      SsStage.isoConversion,
      SsStage.isoEditor,
      SsStage.elevationFaceEditor,
      SsStage.isoRendering,
      SsStage.finalResult,
    ],
    // 이미지 변환 FLOW는 CAD/3D FLOW와 분리한다(SS001 §2).
    SsSourceType.imageTransform: [SsStage.imageEditing, SsStage.imageRendering, SsStage.imageResult],
  };

  /// 그 FLOW의 첫 작업 단계.
  static SsStage firstStage(SsSourceType type) => stages[type]!.first;

  /// 다음 단계(마지막이면 null). [stage]가 그 FLOW에 없으면 null.
  static SsStage? next(SsSourceType type, SsStage stage) {
    final list = stages[type]!;
    final i = list.indexOf(stage);
    return i < 0 || i == list.length - 1 ? null : list[i + 1];
  }

  /// 이전 단계(처음이면 null).
  static SsStage? previous(SsSourceType type, SsStage stage) {
    final list = stages[type]!;
    final i = list.indexOf(stage);
    return i <= 0 ? null : list[i - 1];
  }

  static bool belongs(SsSourceType type, SsStage stage) => stages[type]!.contains(stage);
}

/// SS001 §16 — 좌측 Navigation 항목. 디자인은 화면마다 바꾸지 않고, 단계에 맞는 항목만 활성화한다.
enum SsNavItem {
  home('홈'),
  projects('프로젝트'),
  createProject('프로젝트 생성'),
  currentProject('현재 프로젝트'),
  save('저장'),
  export('파일 내보내기'),
  view2d('2D'),
  view3d('3D'),
  settings('설정');

  const SsNavItem(this.label);
  final String label;
}

abstract final class SsNavigation {
  static const _always = {SsNavItem.home, SsNavItem.projects, SsNavItem.createProject, SsNavItem.settings};

  /// 그 단계에서 누를 수 있는 Navigation 항목.
  static Set<SsNavItem> enabledFor(SsStage stage) {
    switch (stage) {
      case SsStage.login:
        return const {};
      case SsStage.home:
      case SsStage.projectManagement:
      case SsStage.projectCreation:
        return _always;
      case SsStage.imageEditing:
      case SsStage.imageRendering:
      case SsStage.imageResult:
        return {..._always, SsNavItem.currentProject, SsNavItem.save, SsNavItem.export};
      case SsStage.directDrawing:
      case SsStage.floorPlanUpload:
      case SsStage.floorPlanReview:
      case SsStage.cadConversion:
      case SsStage.cadEditor:
        return {..._always, SsNavItem.currentProject, SsNavItem.save, SsNavItem.export, SsNavItem.view2d};
      case SsStage.isoConversion:
      case SsStage.isoEditor:
      case SsStage.elevationFaceEditor:
      case SsStage.isoRendering:
      case SsStage.finalResult:
        return {..._always, SsNavItem.currentProject, SsNavItem.save, SsNavItem.export, SsNavItem.view2d, SsNavItem.view3d};
    }
  }

  /// SS001 보완(S1) — 메뉴 항목을 선택했을 때 실제로 이동할 곳. [currentStage]는 지금 화면(현재 FLOW를 가늠하는 기준).
  /// 화면 이동이 아니라 지금 화면이 직접 처리하는 동작(저장·내보내기)은 null — 각 화면에서 다룬다.
  static SsNavTarget? targetFor(SsNavItem item, SsStage currentStage) {
    switch (item) {
      case SsNavItem.home:
        return const SsNavStageTarget(SsStage.home);
      case SsNavItem.projects:
        return const SsNavStageTarget(SsStage.projectManagement);
      case SsNavItem.createProject:
        return const SsNavStageTarget(SsStage.projectCreation);
      case SsNavItem.currentProject:
        return SsNavStageTarget(currentStage);
      case SsNavItem.view2d:
        return const SsNavStageTarget(SsStage.cadEditor);
      case SsNavItem.view3d:
        return const SsNavStageTarget(SsStage.isoEditor);
      case SsNavItem.settings:
        return const SsNavSettingsTarget();
      case SsNavItem.save:
      case SsNavItem.export:
        return null;
    }
  }
}

/// 좌측 메뉴 선택이 가리키는 이동 대상(§16) — 이름 있는 단계([SsStage])이거나, 단계 목록 밖의 공통 설정 화면.
abstract class SsNavTarget {
  const SsNavTarget();
}

/// 단계([SsStage]) Route로 이동.
class SsNavStageTarget extends SsNavTarget {
  const SsNavStageTarget(this.stage);
  final SsStage stage;
}

/// 공통 설정 화면(SettingsScreen, lib/screens/settings_screen.dart)으로 이동 — 기존 화면을 그대로 재사용한다.
class SsNavSettingsTarget extends SsNavTarget {
  const SsNavSettingsTarget();
}
