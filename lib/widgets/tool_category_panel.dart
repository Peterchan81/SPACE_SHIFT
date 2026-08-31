import 'package:flutter/material.dart';

import '../models/space_task.dart';

/// 공간 작업실 사진 오른쪽에 두는 세로 Tool Panel.
///
/// 전체/천장/벽/바닥/창호/조명/가구/문/기타 카테고리를 세로로 나열하고,
/// 항목이 많아져도 내부 Scroll로 대응한다. 선택된 항목은 Rainbow Accent로
/// 표시한다.
class ToolCategoryPanel extends StatelessWidget {
  const ToolCategoryPanel({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final SpaceCategory selected;
  final ValueChanged<SpaceCategory> onSelected;

  static const Map<SpaceCategory, IconData> _icons = {
    SpaceCategory.all: Icons.grid_view_rounded,
    SpaceCategory.ceiling: Icons.arrow_upward_rounded,
    SpaceCategory.wall: Icons.crop_square_rounded,
    SpaceCategory.floor: Icons.arrow_downward_rounded,
    SpaceCategory.window: Icons.crop_din_rounded,
    SpaceCategory.lighting: Icons.lightbulb_rounded,
    SpaceCategory.furniture: Icons.chair_rounded,
    SpaceCategory.door: Icons.meeting_room_rounded,
    SpaceCategory.etc: Icons.more_horiz_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 84,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E5E5)),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        itemCount: SpaceCategory.values.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final category = SpaceCategory.values[index];
          return _CategoryButton(
            icon: _icons[category]!,
            label: category.label,
            selected: category == selected,
            onTap: () => onSelected(category),
          );
        },
      ),
    );
  }
}

class _CategoryButton extends StatelessWidget {
  const _CategoryButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 60,
          decoration: BoxDecoration(
            gradient: selected ? spaceRainbowGradient : null,
            color: selected ? null : const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? Colors.white : const Color(0xFF616161),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                  color: selected ? Colors.white : const Color(0xFF616161),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
