import 'package:flutter/material.dart';

import '../models/work_area.dart';
import '../theme/space_shift_colors.dart';

/// 공간 작업실 이미지 오른쪽(또는 좁은 화면에서는 아래쪽)에 배치하는
/// "작업 부위 선택" 패널.
///
/// 항목이 많아도 패널 내부에서 스크롤할 수 있다.
class WorkAreaPanel extends StatelessWidget {
  const WorkAreaPanel({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final WorkArea selected;
  final ValueChanged<WorkArea> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SpaceShiftColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(
              '작업 부위 선택',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: SpaceShiftColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              itemCount: WorkArea.values.length,
              separatorBuilder: (context, index) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final area = WorkArea.values[index];
                final isSelected = area == selected;
                return _AreaTile(
                  area: area,
                  selected: isSelected,
                  onTap: () => onSelected(area),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AreaTile extends StatelessWidget {
  const _AreaTile({
    required this.area,
    required this.selected,
    required this.onTap,
  });

  final WorkArea area;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? SpaceShiftColors.selectionAccent.withValues(alpha: 0.12)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? SpaceShiftColors.selectionAccent
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Icon(
                area.icon,
                size: 20,
                color: selected
                    ? SpaceShiftColors.selectionAccent
                    : SpaceShiftColors.textSecondary,
              ),
              const SizedBox(width: 10),
              Text(
                area.label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                  color: selected
                      ? SpaceShiftColors.selectionAccent
                      : SpaceShiftColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
