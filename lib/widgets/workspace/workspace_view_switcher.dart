import 'package:flutter/material.dart';

import '../../models/workspace_task_item.dart';
import '../../theme/space_shift_colors.dart';

/// 상단 중앙 View 전환 — 2D 평면도 / 3D 아이소 / 3D 투시.
///
/// 이 셋은 "작업 종류"가 아니라 "같은 공간을 보는 방식"이므로, 전환해도
/// 현재 프로젝트/선택/작업 목록/편집값이 사라지지 않는다(호출부에서
/// 화면 전체를 다시 만들지 않고 이 위젯만 상태로 갈아끼우도록 한다).
class WorkspaceViewSwitcher extends StatelessWidget {
  const WorkspaceViewSwitcher({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final WorkspaceViewMode selected;
  final ValueChanged<WorkspaceViewMode> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: SpaceShiftColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SpaceShiftColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final mode in WorkspaceViewMode.values)
            _ViewTab(
              label: mode.label,
              selected: mode == selected,
              onTap: () => onSelected(mode),
            ),
        ],
      ),
    );
  }
}

class _ViewTab extends StatelessWidget {
  const _ViewTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            gradient: selected ? SpaceShiftColors.spectrum : null,
            color: selected ? null : Colors.transparent,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: selected ? Colors.white : SpaceShiftColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
