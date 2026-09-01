import 'package:flutter/material.dart';

import '../../models/workspace_task_item.dart';
import '../../theme/space_shift_colors.dart';

/// "선택 영역 편집" 카드 — 도구를 한 줄에 늘어놓지 않고 기능별로 3그룹
/// (영역 생성 / 화면·영역 조작 / 편집)으로 구분해 보여준다.
///
/// Tablet에서 손가락/펜으로 누르기 충분하도록 버튼 하나의 touch target을
/// 44x44 이상으로 유지한다.
class SelectionEditTools extends StatelessWidget {
  const SelectionEditTools({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final WorkspaceSelectionTool selected;
  final ValueChanged<WorkspaceSelectionTool> onSelected;

  static const Map<WorkspaceSelectionToolGroup, String> _groupLabels = {
    WorkspaceSelectionToolGroup.create: '영역 생성',
    WorkspaceSelectionToolGroup.transform: '화면 · 영역 조작',
    WorkspaceSelectionToolGroup.edit: '편집',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SpaceShiftColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '선택 영역 편집',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: SpaceShiftColors.textPrimary,
            ),
          ),
          for (final group in WorkspaceSelectionToolGroup.values) ...[
            const SizedBox(height: 12),
            Text(
              _groupLabels[group]!,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: SpaceShiftColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tool in WorkspaceSelectionTool.values)
                  if (tool.group == group)
                    _ToolButton(
                      tool: tool,
                      selected: tool == selected,
                      onTap: () => onSelected(tool),
                    ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.tool,
    required this.selected,
    required this.onTap,
  });

  final WorkspaceSelectionTool tool;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? SpaceShiftColors.selectionAccent.withValues(alpha: 0.1)
          : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 64,
          height: 56,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? SpaceShiftColors.selectionAccent
                  : SpaceShiftColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                tool.icon,
                size: 20,
                color: selected
                    ? SpaceShiftColors.selectionAccent
                    : SpaceShiftColors.textSecondary,
              ),
              const SizedBox(height: 4),
              Text(
                tool.label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? SpaceShiftColors.selectionAccent
                      : SpaceShiftColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
