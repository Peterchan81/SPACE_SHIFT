/// SS001 §4.2 / §16 — 단계 이름(Route)으로 화면을 연다. 이미 있는 화면은 그대로 쓰고(기존 기능 보호 — §14),
/// 아직 없는 단계는 공통 단계 화면([SsStageScreen])으로 연다 — 각 Work Order(SS002~SS017)가 자기 화면으로 바꾼다.
///
/// 기존 연결(로그인 → 평면도 작업 화면)은 바꾸지 않는다. 이름으로 여는 경로를 더하기만 한다.
///
/// SS001-UI — 공통 프레임(SsStageScreen·SsNavRail·SsStageHeader)과 상단 Header([SsTopBar])는
/// 2026-09-28 확정 MASTER UI(Dark Navy·Rainbow/Neon·고정 좌측 메뉴, [SsMasterTheme])를 쓴다.
/// 흰색 V1 테마(`SpaceShiftColors`)는 아직 V1 화면이 쓰므로 그대로 둔다.
library;

import 'package:flutter/material.dart';

import '../screens/floor_plan_workspace_screen.dart';
import '../screens/login_screen.dart';
import '../screens/photo_select_screen.dart';
import '../screens/settings_screen.dart';
import '../services/auth_service.dart';
import '../theme/ss_master_theme.dart';
import 'ss_stage.dart';

abstract final class SsRouter {
  /// 이미 있는 화면이 맡는 단계 — 화면을 새로 만들지 않고 연결만 한다.
  /// 평면도 업로드·AI 인식·보정·CAD 변환·CAD 편집·DXF는 기존 [FloorPlanWorkspaceScreen] 한 화면이 한다.
  static final Map<SsStage, WidgetBuilder> existing = {
    SsStage.login: (_) => const LoginScreen(),
    SsStage.floorPlanUpload: (_) => const FloorPlanWorkspaceScreen(),
    SsStage.floorPlanReview: (_) => const FloorPlanWorkspaceScreen(),
    SsStage.cadConversion: (_) => const FloorPlanWorkspaceScreen(),
    SsStage.cadEditor: (_) => const FloorPlanWorkspaceScreen(),
    SsStage.imageEditing: (_) => const PhotoSelectScreen(),
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
/// 아직 동작이 없는 도움말·알림 아이콘은 누를 수 없게 비활성(onPressed: null)만 두고 가짜 동작을 만들지 않는다.
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
          IconButton(key: const Key('ssTopBarHelp'), onPressed: null, icon: const Icon(Icons.help_outline, color: SsMasterTheme.textSecondary)),
          IconButton(
            key: const Key('ssTopBarNotifications'),
            onPressed: null,
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

/// 3초 법칙 머리말 — "지금 무엇을 하는 화면인가 / 다음에 무엇을 하나"(MASTER UI 5 머리말 기준: 번호 상자 + 제목 + 설명).
class SsStageHeader extends StatelessWidget {
  const SsStageHeader({super.key, required this.stage});
  final SsStage stage;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(gradient: SsMasterTheme.selectedItem, borderRadius: BorderRadius.circular(10)),
          child: Text(stage.masterUi, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                stage.title,
                key: const Key('ssStageTitle'),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: SsMasterTheme.textPrimary),
              ),
              const SizedBox(height: 6),
              Text(stage.whatIsThis, key: const Key('ssStageWhat'), style: const TextStyle(fontSize: 14, color: SsMasterTheme.textSecondary)),
              const SizedBox(height: 2),
              Text(
                '다음: ${stage.whatNext}',
                key: const Key('ssStageNext'),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: SsMasterTheme.neonBlue),
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
    return Container(
      key: const Key('ssNavRail'),
      width: 236,
      decoration: const BoxDecoration(color: SsMasterTheme.panel, border: Border(right: BorderSide(color: SsMasterTheme.panelBorder))),
      child: Column(
        children: [
          const SizedBox(height: 16),
          for (final item in mainItems)
            _SsNavRow(item: item, icon: _icons[item]!, isSelected: item == selected, onTap: onSelect == null ? null : () => onSelect!(item)),
          if (showCurrentProjects)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      '진행 중인 프로젝트',
                      key: Key('ssNavCurrentProjectsLabel'),
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: SsMasterTheme.textMuted, letterSpacing: 0.4),
                    ),
                    SizedBox(height: 8),
                    Expanded(child: SizedBox(key: Key('ssNavCurrentProjectsList'))),
                  ],
                ),
              ),
            )
          else
            const Spacer(),
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
        ],
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
