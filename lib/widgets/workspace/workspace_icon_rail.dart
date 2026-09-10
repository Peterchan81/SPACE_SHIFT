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
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;
}

/// WO099 UI COMPACT MODE — 좌/우 큰 카드형 패널을 대체하는 세로 아이콘
/// 레일. 중앙 canvas를 최대한 확보하기 위해 폭을 고정된 좁은 값
/// ([kWorkspaceRailWidth])으로 유지하고, 각 항목은 [Tooltip]으로만
/// 제목을 보여준다(기본 상태에서는 아이콘만 보인다 — 상시 노출 텍스트
/// 없음).
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
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in items) ...[
            _RailButton(item: item),
            if (item != items.last) const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

/// 좌/우 레일 폭 — 아이콘 하나(44 터치 타겟) + 여백만 담는 최소 폭이다.
const double kWorkspaceRailWidth = 56;

class _RailButton extends StatelessWidget {
  const _RailButton({required this.item});

  final WorkspaceRailItem item;

  @override
  Widget build(BuildContext context) {
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
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: item.selected
                    ? SpaceShiftColors.selectionAccent
                    : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Icon(
              item.icon,
              size: 22,
              color: item.selected
                  ? SpaceShiftColors.selectionAccent
                  : SpaceShiftColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
