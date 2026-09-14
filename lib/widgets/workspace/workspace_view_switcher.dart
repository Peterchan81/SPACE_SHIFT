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
      // FINAL PROFESSIONAL UI RESTRUCTURE WO §5 — 이 View 전환이 상단에서
      // "가장 눈에 띄어야" 하므로 글자를 줄이거나 숨기지 않는다. 대신 좌/
      // 우 레일이 넓어지고 상단 바에 Zoom%가 더해져 중앙에 남는 폭이
      // 줄어든 상태에서도(특히 좁은 창/구조 확인 Sub Menu가 펼쳐져 있을
      // 때) 실기에서 반복 관측된 RenderFlex overflow가 다시 나지 않도록,
      // 정말 자리가 부족할 때만 전체 배지를 통째로 축소해 항상 화면
      // 안에 담는다(글자만 잘리는 대신 3개 탭 비율은 그대로 유지된다).
      child: FittedBox(
        fit: BoxFit.scaleDown,
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
          // WO099 UI COMPACT MODE — "상단 mode selector는 유지하되
          // compact하게": 가로 padding을 줄여 좁은 창에서도 3개 탭이
          // 한 줄에 넘치지 않게 한다(실기에서 관측된 RenderFlex overflow
          // 재발 방지).
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            gradient: selected ? SpaceShiftColors.spectrum : null,
            color: selected ? null : Colors.transparent,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: selected ? Colors.white : SpaceShiftColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
