/// SS001 §4.2 / §16 — 단계 이름(Route)으로 화면을 연다. 이미 있는 화면은 그대로 쓰고(기존 기능 보호 — §14),
/// 아직 없는 단계는 공통 단계 화면([SsStageScreen])으로 연다 — 각 Work Order(SS002~SS017)가 자기 화면으로 바꾼다.
///
/// 기존 연결(로그인 → 평면도 작업 화면)은 바꾸지 않는다. 이름으로 여는 경로를 더하기만 한다.
library;

import 'package:flutter/material.dart';

import '../screens/floor_plan_workspace_screen.dart';
import '../screens/login_screen.dart';
import '../screens/photo_select_screen.dart';
import '../screens/settings_screen.dart';
import '../theme/space_shift_colors.dart';
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
  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    final stage = SsStage.fromRoute(settings.name);
    if (stage == null) return null;
    return MaterialPageRoute<void>(settings: settings, builder: builderFor(stage));
  }

  static WidgetBuilder builderFor(SsStage stage) => existing[stage] ?? (_) => SsStageScreen(stage: stage);

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
}

/// 아직 세부 화면이 없는 단계의 공통 화면 — 3초 법칙(§15) 머리말 + 좌측 Navigation(단계별 활성화) + 담당 Work Order.
class SsStageScreen extends StatelessWidget {
  const SsStageScreen({super.key, required this.stage});
  final SsStage stage;

  @override
  Widget build(BuildContext context) {
    final enabled = SsNavigation.enabledFor(stage);
    return Scaffold(
      backgroundColor: SpaceShiftColors.background,
      body: SafeArea(
        child: Row(
          children: [
            SsNavRail(enabled: enabled, onSelect: (item) => SsRouter.handleNavSelect(context, stage, item)),
            Expanded(
              child: Padding(
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
                          style: const TextStyle(color: SpaceShiftColors.textSecondary, fontSize: 16),
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
    );
  }
}

/// 3초 법칙 머리말 — "지금 무엇을 하는 화면인가 / 다음에 무엇을 하나".
class SsStageHeader extends StatelessWidget {
  const SsStageHeader({super.key, required this.stage});
  final SsStage stage;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(stage.title, key: const Key('ssStageTitle'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: SpaceShiftColors.textPrimary)),
        const SizedBox(height: 6),
        Text(stage.whatIsThis, key: const Key('ssStageWhat'), style: const TextStyle(fontSize: 15, color: SpaceShiftColors.textSecondary)),
        const SizedBox(height: 2),
        Text('다음: ${stage.whatNext}', key: const Key('ssStageNext'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: SpaceShiftColors.blue)),
      ],
    );
  }
}

/// 좌측 Navigation — 디자인은 하나, 단계에 필요한 항목만 활성화(§16).
class SsNavRail extends StatelessWidget {
  const SsNavRail({super.key, required this.enabled, this.onSelect});
  final Set<SsNavItem> enabled;
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
    return Container(
      width: 92,
      decoration: const BoxDecoration(border: Border(right: BorderSide(color: SpaceShiftColors.border))),
      child: Column(
        children: [
          const SizedBox(height: 16),
          const Text('SS', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: SpaceShiftColors.purple)),
          const SizedBox(height: 12),
          for (final item in SsNavItem.values)
            Opacity(
              opacity: enabled.contains(item) ? 1 : 0.3,
              child: InkWell(
                key: Key('ssNav_${item.name}'),
                onTap: enabled.contains(item) && onSelect != null ? () => onSelect!(item) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      Icon(_icons[item], color: SpaceShiftColors.textPrimary),
                      const SizedBox(height: 2),
                      Text(item.label, style: const TextStyle(fontSize: 11, color: SpaceShiftColors.textSecondary)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
