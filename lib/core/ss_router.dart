/// SS001 §4.2 / §16 — 단계 이름(Route)으로 화면을 연다. 이미 있는 화면은 그대로 쓰고(기존 기능 보호 — §14),
/// 아직 없는 단계는 공통 단계 화면([SsStageScreen])으로 연다 — 각 Work Order(SS002~SS017)가 자기 화면으로 바꾼다.
///
/// 기존 연결(로그인 → 평면도 작업 화면)은 바꾸지 않는다. 이름으로 여는 경로를 더하기만 한다.
///
/// SS001-UI — 공통 프레임(SsStageScreen·SsNavRail·SsStageHeader)과 상단 Header([SsTopBar])는
/// 2026-09-28 확정 MASTER UI(Dark Navy·Rainbow/Neon·고정 좌측 메뉴, [SsMasterTheme])를 쓴다.
/// 흰색 V1 테마(`SpaceShiftColors`)는 아직 V1 화면이 쓰므로 그대로 둔다.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../screens/cad_conversion_screen.dart';
import '../screens/cad_editor_screen.dart';
import '../screens/direct_draw_screen.dart';
import '../screens/elevation_face_editor_screen.dart';
import '../screens/final_result_screen.dart';
import '../screens/floor_plan_review_screen.dart';
import '../screens/floor_plan_upload_screen.dart';
import '../screens/floor_plan_workspace_screen.dart';
import '../screens/iso_conversion_screen.dart';
import '../screens/iso_editor_screen.dart';
import '../screens/iso_rendering_screen.dart';
import '../screens/home_screen.dart';
import '../screens/login_screen.dart';
import '../screens/image_rendering_screen.dart';
import '../screens/image_result_screen.dart';
import '../screens/photo_design_editor_screen.dart';
import '../screens/project_creation_screen.dart';
import '../screens/project_management_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/ss_guide_screen.dart';
import '../widgets/ss_keep_words_text.dart';
import '../widgets/ss_nav_current_projects.dart';
import '../widgets/ss_notifications_panel.dart';
import '../widgets/ss_project_rename_dialog.dart';
import 'ss_project.dart';
import 'ss_project_store.dart';
import 'ss_recent_projects.dart';
import 'ss_stage_guide.dart';
import '../services/auth_service.dart';
import '../services/ss_project_store_provider.dart';
import '../theme/ss_master_theme.dart';
import 'ss_stage.dart';

abstract final class SsRouter {
  /// 이미 있는 화면이 맡는 단계 — 화면을 새로 만들지 않고 연결만 한다.
  /// SS008부터 "평면도 업로드"는 신규 MASTER UI 5(원본·AI 인식 결과 비교) 전용 화면
  /// [FloorPlanUploadScreen]을, SS009부터 "평면도 확인·보정"은 신규 MASTER UI 6(펜/
  /// 형광펜/지우개/선택 보정 도구) 전용 화면 [FloorPlanReviewScreen]을 쓴다. SS010부터
  /// "CAD 변환"(MASTER UI 7)은 신규 [CadConversionScreen](Blue line-only 진행 화면)을
  /// 쓴다 — "CAD 편집·내보내기"(MASTER UI 8)는 그 다음 Work Order(SS011)가 MASTER
  /// UI로 옮기기 전까지 기존 [FloorPlanWorkspaceScreen] 화면이 그대로 한다.
  static final Map<SsStage, WidgetBuilder> existing = {
    SsStage.login: (_) => const LoginScreen(),
    SsStage.home: (_) => const HomeScreen(),
    SsStage.projectManagement: (_) => const ProjectManagementScreen(),
    SsStage.projectCreation: (_) => const ProjectCreationScreen(),
    SsStage.directDrawing: (context) => DirectDrawScreen(projectId: ModalRoute.of(context)?.settings.arguments as String?),
    SsStage.floorPlanUpload: (context) => FloorPlanUploadScreen(projectId: ModalRoute.of(context)?.settings.arguments as String?),
    SsStage.floorPlanReview: (context) => FloorPlanReviewScreen(projectId: ModalRoute.of(context)?.settings.arguments as String?),
    SsStage.cadConversion: (context) => CadConversionScreen(projectId: ModalRoute.of(context)?.settings.arguments as String?),
    SsStage.cadEditor: (context) => CadEditorScreen(projectId: ModalRoute.of(context)?.settings.arguments as String?),
    SsStage.isoConversion: (context) => IsoConversionScreen(projectId: ModalRoute.of(context)?.settings.arguments as String?),
    SsStage.isoEditor: (context) => IsoEditorScreen(projectId: ModalRoute.of(context)?.settings.arguments as String?),
    SsStage.elevationFaceEditor: (context) {
      final args = ModalRoute.of(context)?.settings.arguments;
      final map = args is Map ? args : const <String, Object?>{};
      return ElevationFaceEditorScreen(projectId: map['projectId'] as String?, wallId: map['wallId'] as String?);
    },
    SsStage.isoRendering: (context) => IsoRenderingScreen(projectId: ModalRoute.of(context)?.settings.arguments as String?),
    SsStage.finalResult: (context) => FinalResultScreen(projectId: ModalRoute.of(context)?.settings.arguments as String?),
    SsStage.imageEditing: (context) => PhotoDesignEditorScreen(projectId: ModalRoute.of(context)?.settings.arguments as String?),
    SsStage.imageRendering: (context) => ImageRenderingScreen(projectId: ModalRoute.of(context)?.settings.arguments as String?),
    SsStage.imageResult: (context) => ImageResultScreen(projectId: ModalRoute.of(context)?.settings.arguments as String?),
  };

  /// MaterialApp.onGenerateRoute — 모르는 이름이면 null(기존 Navigator 동작 그대로).
  ///
  /// SS002 §5 "라우트 보호" — 앱이 세션 복원을 마쳤는데도([AuthController.initialized])
  /// 로그인 상태가 아니면, 로그인 화면이 아닌 다른 모든 단계 Route는 로그인
  /// 화면으로 돌려보낸다. 세션 복원이 아직 끝나지 않았으면(이 저장소의 기존
  /// 테스트들처럼 AuthController를 전혀 거치지 않는 경우 포함) 막지 않는다 —
  /// 실제 앱은 main.dart가 시작할 때 항상 먼저 [AuthController.bootstrap]을
  /// 끝내므로 실사용에서는 보호가 그대로 적용된다.
  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    final stage = SsStage.fromRoute(settings.name);
    if (stage == null) return null;
    if (stage != SsStage.login && AuthController.instance.initialized && !AuthController.instance.isAuthenticated) {
      return MaterialPageRoute<void>(settings: const RouteSettings(name: '/login'), builder: existing[SsStage.login]!);
    }
    return MaterialPageRoute<void>(settings: settings, builder: builderFor(stage));
  }

  static WidgetBuilder builderFor(SsStage stage) {
    if (stage == SsStage.login) return existing[stage]!;
    final existingBuilder = existing[stage];
    return (context) => SsStageScreen(stage: stage, child: existingBuilder == null ? null : Builder(builder: existingBuilder));
  }

  /// 단계 화면 열기(이름 그대로 — 화면끼리 클래스를 직접 알 필요 없음).
  static Future<T?> open<T>(BuildContext context, SsStage stage) => Navigator.of(context).pushNamed<T>(stage.routeName);

  /// SS001 보완(S1) — 좌측 메뉴 선택을 실제 화면 이동으로 연결한다(SsNavigation.targetFor로 정한 곳).
  /// 이미 있는 화면(설정 포함)을 그대로 재사용하고, 저장/내보내기처럼 화면 이동이 아닌 항목이나 지금 보고 있는
  /// 단계를 다시 고른 경우는 아무 것도 하지 않는다(중복 이동/중복 화면 방지).
  static void handleNavSelect(BuildContext context, SsStage currentStage, SsNavItem item) {
    final target = SsNavigation.targetFor(item, currentStage);
    if (target == null) return;
    if (target is SsNavSettingsTarget) {
      Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => SettingsScreen()));
      return;
    }
    if (target is SsNavStageTarget && target.stage != currentStage) {
      open(context, target.stage);
    }
  }

  /// SS001-UI — 지금 단계에 해당해서 좌측 메뉴에서 "선택" 강조로 보일 항목. 홈/프로젝트 관리/프로젝트 생성은
  /// 그 항목 자신이, 그 외 작업 단계(평면도·CAD·ISO 등)는 "현재 프로젝트"가 선택 상태다. 메뉴가 없는 로그인은 null.
  static SsNavItem? selectedNavItemFor(SsStage stage) {
    switch (stage) {
      case SsStage.login:
        return null;
      case SsStage.home:
        return SsNavItem.home;
      case SsStage.projectManagement:
        return SsNavItem.projects;
      case SsStage.projectCreation:
        return SsNavItem.createProject;
      default:
        return SsNavItem.currentProject;
    }
  }
}

/// SS002 §5(2026-10-28 #2 후속 지시) — 설정 화면([SettingsScreen])과
/// [SsTopBar]가 공유하는 로그아웃 동작 하나. Supabase 세션 종료
/// ([AuthController.signOut]) + 앱 인증 상태 초기화 뒤 로그인 화면으로
/// 돌아가며(pushAndRemoveUntil로 뒤로가기를 막아 보호된 화면 재진입을
/// 차단), 세션 종료 로직을 두 번 구현하지 않는다.
Future<void> performLogout(BuildContext context) async {
  await AuthController.instance.signOut();
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute<void>(builder: (_) => const LoginScreen(), settings: const RouteSettings(name: '/login')),
    (route) => false,
  );
}

/// 아직 세부 화면이 없는 단계의 공통 화면 — 3초 법칙(§15) 머리말 + 상단 Header + 좌측 Navigation(단계별
/// 활성화) + 담당 Work Order. MASTER UI(Dark Navy·Neon·고정 좌측 메뉴) 공통 프레임.
class SsStageScreen extends StatelessWidget {
  const SsStageScreen({super.key, required this.stage, this.child});
  final SsStage stage;

  /// SS001-UI 보완 — 이미 있는 화면(FloorPlanWorkspaceScreen 등)을 공통 프레임(Header+NavRail) 안에 그대로
  /// 보여줄 때 쓴다. 없으면(세부 화면이 아직 없는 단계) 3초 법칙 머리말 + 대기 안내를 보인다.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final enabled = SsNavigation.enabledFor(stage);
    return Scaffold(
      backgroundColor: SsMasterTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            const SsTopBar(),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SsNavRail(
                    enabled: enabled,
                    selected: SsRouter.selectedNavItemFor(stage),
                    onSelect: (item) => SsRouter.handleNavSelect(context, stage, item),
                  ),
                  Expanded(
                    child: child ??
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SsStageHeader(stage: stage),
                              const SizedBox(height: 24),
                              Expanded(
                                child: Center(
                                  child: Text(
                                    '${stage.title} 화면은 ${stage.workOrder}에서 만듭니다 · MASTER UI ${stage.masterUi}',
                                    key: const Key('ssStagePending'),
                                    style: const TextStyle(color: SsMasterTheme.textSecondary, fontSize: 16),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 상단 공통 Header(MASTER UI 2·5 기준) — 왼쪽 무지개 SS 로고 + "SPACE SHIFT", 오른쪽 도움말·알림·프로필.
/// 도움말 아이콘은 시작 가이드([SsGuideScreen])를, 알림 아이콘은 실제 프로젝트 저장소의 최근 활동만 보여주는
/// 알림 패널([SsNotificationsPanel])을 연다(SS-BUG-011 — 가짜 알림은 만들지 않는다).
///
/// 프로필 아이콘(2026-10-28 #2 후속 지시 — Galaxy Tab 실기 검증 후) — 더 이상
/// 이 아이콘에서 직접 로그아웃하지 않는다. 누르면 [SettingsScreen]으로 이동해,
/// "계정" 구역의 로그아웃(확인 창 → [performLogout])에서 로그아웃하게 한다.
class SsTopBar extends StatelessWidget {
  const SsTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('ssTopBar'),
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: SsMasterTheme.panel,
        border: Border(bottom: BorderSide(color: SsMasterTheme.panelBorder)),
      ),
      child: Row(
        children: [
          ShaderMask(
            shaderCallback: (bounds) => SsMasterTheme.rainbow.createShader(bounds),
            child: const Text('SS', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white)),
          ),
          const SizedBox(width: 10),
          const Text(
            'SPACE SHIFT',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 1.1),
          ),
          const Spacer(),
          IconButton(
            key: const Key('ssTopBarHelp'),
            tooltip: '도움말',
            onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => const SsGuideScreen())),
            icon: const Icon(Icons.help_outline, color: SsMasterTheme.textSecondary),
          ),
          IconButton(
            key: const Key('ssTopBarNotifications'),
            tooltip: '알림',
            onPressed: () => showSsNotificationsPanel(context),
            icon: const Icon(Icons.notifications_outlined, color: SsMasterTheme.textSecondary),
          ),
          IconButton(
            key: const Key('ssTopBarProfile'),
            tooltip: '설정',
            onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => SettingsScreen())),
            icon: const Icon(Icons.account_circle_outlined, color: SsMasterTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// 3초 법칙 머리말 — MASTER 화면처럼 큰 제목 + 한 줄 안내 문장([SsStageGuide])으로 "지금 어디인지 / 다음에 무엇을
/// 하는지"를 알려준다(SS-수정003 — 개발용 번호 상자·"다음: …" 표시는 쓰지 않는다).
///
/// SS-수정003 4차 — 열린 프로젝트가 있으면(작업 단계 + 프로젝트 id) MASTER 05처럼 왼쪽 프로젝트 번호 상자(목록 번호
/// 01·02…), 큰 프로젝트 이름과 이름 바꾸기 ✎ 버튼, 그 아래 이 단계 안내 한 줄을 보인다. 프로젝트가 없는 화면(홈·관리·
/// 생성)이나 프로젝트를 읽지 못하면 지금 머리말(단계 제목 + 안내) 그대로다.
class SsStageHeader extends StatefulWidget {
  const SsStageHeader({super.key, required this.stage, this.projectId, this.projectStore});
  final SsStage stage;

  /// 열린 프로젝트 id. 없으면 지금 Route 인자(String 또는 {'projectId': …})에서 찾는다.
  final String? projectId;

  /// 테스트 주입용. 없으면 앱 공용 저장소([SsProjectStoreProvider]).
  final SsProjectStore? projectStore;

  /// Route 인자에서 프로젝트 id를 찾는다(단계 화면은 id 글자, 정면도 화면은 {'projectId': …}).
  static String? projectIdFromArguments(Object? arguments) {
    if (arguments is String) return arguments.isEmpty ? null : arguments;
    if (arguments is Map) {
      final id = arguments['projectId'];
      if (id is String && id.isNotEmpty) return id;
    }
    return null;
  }

  @override
  State<SsStageHeader> createState() => _SsStageHeaderState();
}

class _SsStageHeaderState extends State<SsStageHeader> {
  bool _resolved = false;
  SsProjectStore? _store;
  SsProject? _project;
  int _number = 0;
  bool _renaming = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_resolved) return;
    _resolved = true;
    if (SsFlows.entry.contains(widget.stage)) return;
    final id = widget.projectId ?? SsStageHeader.projectIdFromArguments(ModalRoute.of(context)?.settings.arguments);
    if (id != null) unawaited(_load(id));
  }

  Future<void> _load(String projectId) async {
    try {
      final store = widget.projectStore ?? await SsProjectStoreProvider.instance.store();
      final all = await SsRecentProjects.load(store);
      final index = all.indexWhere((p) => p.info.id == projectId);
      if (!mounted || index < 0) return;
      setState(() {
        _store = store;
        _project = all[index];
        _number = index + 1;
      });
    } catch (e, st) {
      // 저장소 오류인지 다른 예외인지 단정하지 않는다 — 머리말은 단계 머리말 그대로 두고, 실제 원인은 개발자에게.
      debugPrint('SsStageHeader 프로젝트 정보 불러오기 실패 (${e.runtimeType}): $e / $st');
    }
  }

  Future<void> _rename() async {
    final store = _store;
    final project = _project;
    if (store == null || project == null || _renaming) return;
    final name = await showSsProjectRenameDialog(context, initialName: project.info.name);
    if (name == null || !mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    _renaming = true;
    try {
      final renamed = await renameSsProject(store, project.info.id, name);
      if (!mounted) return;
      if (renamed == null) {
        messenger?.showSnackBar(const SnackBar(content: Text('이름을 바꿀 프로젝트를 찾지 못했습니다.', key: Key('ssProjectRenameError'))));
        return;
      }
      setState(() => _project = renamed);
    } catch (e, st) {
      // 저장 실패의 원인을 단정하지 않는다 — 화면엔 일반 실패만, 실제 원인(타입 포함)은 개발자에게.
      debugPrint('프로젝트 이름 바꾸기 실패 (${e.runtimeType}): $e / $st');
      messenger?.showSnackBar(const SnackBar(content: Text('프로젝트 이름을 저장하지 못했습니다. 다시 시도해주세요.', key: Key('ssProjectRenameError'))));
    } finally {
      _renaming = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final stage = widget.stage;
    final sentence = SsStageGuide.sentenceFor(stage);
    final project = _project;
    if (project == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            stage.title,
            key: const Key('ssStageTitle'),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: SsMasterTheme.textPrimary, height: 1.2),
          ),
          const SizedBox(height: 8),
          SsKeepWordsText(
            sentence,
            key: const Key('ssStageWhat'),
            style: const TextStyle(fontSize: 14, color: SsMasterTheme.textSecondary, height: 1.4),
          ),
        ],
      );
    }
    return Row(
      key: const Key('ssStageProjectHeader'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          key: const Key('ssStageProjectNumberBox'),
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: SsMasterTheme.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: SsMasterTheme.neonBlue, width: 1.5),
          ),
          child: Text(
            _number.toString().padLeft(2, '0'),
            key: const Key('ssStageProjectNumber'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      project.info.name,
                      key: const Key('ssStageProjectName'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: SsMasterTheme.textPrimary, height: 1.2),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    key: const Key('ssStageProjectRename'),
                    tooltip: '프로젝트 이름 바꾸기',
                    onPressed: () => unawaited(_rename()),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                    iconSize: 18,
                    icon: const Icon(Icons.edit_outlined, color: SsMasterTheme.textSecondary),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      stage.title,
                      key: const Key('ssStageTitle'),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: SsMasterTheme.neonCyan),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SsKeepWordsText(
                sentence,
                key: const Key('ssStageWhat'),
                style: const TextStyle(fontSize: 14, color: SsMasterTheme.textSecondary, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 좌측 Navigation(MASTER UI 2·5 기준) — Dark Navy 고정 패널. 디자인은 하나지만, 단계에서 쓸 수 있는
/// 항목만 보여준다(§16 — 쓸 수 없는 항목을 흐리게 늘어놓지 않음). 지금 단계에 해당하는 항목은 그라데이션
/// 강조 상자로 선택 표시하고, 작업 단계에는 MASTER 5처럼 "진행 중인 프로젝트" 영역 자리를 둔다(데이터 연결은
/// SS004). 설정은 맨 아래 고정.
class SsNavRail extends StatelessWidget {
  const SsNavRail({super.key, required this.enabled, this.selected, this.onSelect});
  final Set<SsNavItem> enabled;
  final SsNavItem? selected;
  final ValueChanged<SsNavItem>? onSelect;

  static const _icons = {
    SsNavItem.home: Icons.home_outlined,
    SsNavItem.projects: Icons.folder_outlined,
    SsNavItem.createProject: Icons.add_box_outlined,
    SsNavItem.currentProject: Icons.work_outline,
    SsNavItem.save: Icons.save_outlined,
    SsNavItem.export: Icons.ios_share,
    SsNavItem.view2d: Icons.grid_on,
    SsNavItem.view3d: Icons.view_in_ar_outlined,
    SsNavItem.settings: Icons.settings_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final mainItems = SsNavItem.values.where((i) => i != SsNavItem.settings && enabled.contains(i)).toList();
    final showSettings = enabled.contains(SsNavItem.settings);
    final showCurrentProjects = enabled.contains(SsNavItem.currentProject);
    final navRows = <Widget>[
      for (final item in mainItems)
        _SsNavRow(item: item, icon: _icons[item]!, isSelected: item == selected, onTap: onSelect == null ? null : () => onSelect!(item)),
    ];
    final settingsRows = <Widget>[
      if (showSettings) ...[
        const Divider(height: 1, color: SsMasterTheme.panelBorder),
        _SsNavRow(
          item: SsNavItem.settings,
          icon: _icons[SsNavItem.settings]!,
          isSelected: SsNavItem.settings == selected,
          onTap: onSelect == null ? null : () => onSelect!(SsNavItem.settings),
        ),
        const SizedBox(height: 12),
      ],
    ];
    // SS-BUG-011 — 진행 중인 프로젝트는 실제 저장소 목록([SsNavCurrentProjects]) — 누르면 마지막 저장 단계로 재개.
    const currentProjects = Padding(
      padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '진행 중인 프로젝트',
            key: Key('ssNavCurrentProjectsLabel'),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: SsMasterTheme.textMuted, letterSpacing: 0.4),
          ),
          SizedBox(height: 8),
          Expanded(child: SsNavCurrentProjects(key: Key('ssNavCurrentProjectsList'))),
        ],
      ),
    );
    return Container(
      key: const Key('ssNavRail'),
      width: 236,
      decoration: const BoxDecoration(color: SsMasterTheme.panel, border: Border(right: BorderSide(color: SsMasterTheme.panelBorder))),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 낮은 창(예: 640×480)에서는 메뉴가 잘리지 않게 전체를 스크롤하고, 진행 중인 프로젝트 영역은 고정 높이로 둔다.
          final needed = 16.0 + mainItems.length * 52 + (showSettings ? 65 : 0) + (showCurrentProjects ? 140 : 0);
          if (constraints.maxHeight.isFinite && constraints.maxHeight < needed) {
            return SingleChildScrollView(
              key: const Key('ssNavRailScroll'),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  ...navRows,
                  if (showCurrentProjects) const SizedBox(height: 180, child: currentProjects),
                  ...settingsRows,
                ],
              ),
            );
          }
          return Column(
            children: [
              const SizedBox(height: 16),
              ...navRows,
              if (showCurrentProjects) const Expanded(child: currentProjects) else const Spacer(),
              ...settingsRows,
            ],
          );
        },
      ),
    );
  }
}

/// 좌측 메뉴 한 줄(아이콘 + 글자) — 선택 상태면 파랑→보라 그라데이션 강조 상자.
class _SsNavRow extends StatelessWidget {
  const _SsNavRow({required this.item, required this.icon, required this.isSelected, this.onTap});
  final SsNavItem item;
  final IconData icon;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = isSelected ? Colors.white : SsMasterTheme.textSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        key: Key('ssNav_${item.name}'),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(gradient: isSelected ? SsMasterTheme.selectedItem : null, borderRadius: BorderRadius.circular(12)),
          child: Row(
            children: [
              Icon(icon, color: foreground, size: 20),
              const SizedBox(width: 12),
              Text(item.label, style: TextStyle(fontSize: 14, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, color: foreground)),
            ],
          ),
        ),
      ),
    );
  }
}
