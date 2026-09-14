import 'package:flutter/material.dart';

import '../../theme/space_shift_colors.dart';

/// WO099 — 좌/우 패널을 "기본은 아이콘만, hover 시 tooltip"인 세로
/// 아이콘 레일로 압축할 때 양쪽이 공유하는 항목 하나.
class WorkspaceRailItem {
  const WorkspaceRailItem({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.selected = false,
    this.enabled = true,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  /// PROFESSIONAL WORKSPACE UI RESTRUCTURE WO §3 — 아직 실제 기능이 없는
  /// 메뉴는 다른 항목과 똑같이 보이면 안 된다("disabled/준비중 상태를
  /// 명확하게 표현"). tap 자체는 계속 받아 안내(SnackBar 등)는 그대로
  /// 나가되, 아이콘만 눈에 띄게 흐리게 표시한다.
  final bool enabled;
}

/// FINAL PROFESSIONAL UI RESTRUCTURE WO §3/§10 — Supabase 스타일 좌/우
/// Main Menu 레일. 이전(WO099)에는 "기본 상태는 아이콘만, 이름은 hover
/// tooltip으로만" 이었지만, 이번 WO는 "아이콘 + 짧은 메뉴명"이 항상 함께
/// 보이는 구조를 요구한다 — 그래서 [item.tooltip]을 hover 안내뿐 아니라
/// 아이콘 아래 상시 노출 캡션으로도 그대로 재사용한다(새 label 필드를
/// 따로 만들지 않는다 — 문자열 하나로 두 역할을 겸한다).
class WorkspaceIconRail extends StatelessWidget {
  const WorkspaceIconRail({super.key, required this.items});

  final List<WorkspaceRailItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: kWorkspaceRailWidth,
      decoration: BoxDecoration(
        color: SpaceShiftColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SpaceShiftColors.border),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      // FINAL PROFESSIONAL UI RESTRUCTURE WO §3/§10 — 아이콘 아래 캡션이
      // 항상 보이면서 항목 수도 늘어나(좌측 8개) 레일 하나의 전체 높이가
      // 짧은 창/작은 화면에서는 사용 가능한 세로 공간보다 커질 수 있다.
      // 예전(아이콘만) 폭 [Column]은 그 경우 RenderFlex overflow로
      // 깨졌다 — 항목을 줄이거나 숨기는 대신 스크롤 가능하게 만들어
      // 어떤 창 크기에서도 모든 메뉴가 항상 접근 가능하게 한다.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in items) ...[
              _RailButton(item: item),
              if (item != items.last) const SizedBox(height: 4),
            ],
          ],
        ),
      ),
    );
  }
}

/// 좌/우 레일 폭 — 아이콘 + 짧은 메뉴명 캡션(최대 2줄)을 한 열에 담을 수
/// 있는 최소 폭이다(WO099 시절의 아이콘 전용 56px보다 넓다).
const double kWorkspaceRailWidth = 74;

class _RailButton extends StatelessWidget {
  const _RailButton({required this.item});

  final WorkspaceRailItem item;

  @override
  Widget build(BuildContext context) {
    final color = !item.enabled
        ? SpaceShiftColors.textSecondary.withValues(alpha: 0.35)
        : item.selected
        ? SpaceShiftColors.selectionAccent
        : SpaceShiftColors.textSecondary;
    return Tooltip(
      message: item.tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: Material(
        color: item.selected
            ? SpaceShiftColors.selectionAccent.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: item.onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: item.selected
                    ? SpaceShiftColors.selectionAccent
                    : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(item.icon, size: 20, color: color),
                const SizedBox(height: 3),
                Text(
                  item.tooltip,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5,
                    height: 1.15,
                    fontWeight: item.selected
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
