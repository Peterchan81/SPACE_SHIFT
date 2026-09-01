import 'package:flutter/material.dart';

import '../../models/workspace_task_item.dart';
import '../../theme/space_shift_colors.dart';

/// 중앙 하단 "작업 목록" — 승인된 MASTER 디자인의 큰 구조를 유지한다.
///
/// 여기서 선택하면 [onSelect]를 통해 중앙 3D marker highlight와 우측
/// 작업 Tab이 함께 바뀐다(같은 [WorkspaceTaskItem.id]를 공유하는 양방향
/// 동기화 — 화면 쪽에서 상태 하나만 갈아끼우면 된다).
class WorkspaceTaskList extends StatelessWidget {
  const WorkspaceTaskList({
    super.key,
    required this.tasks,
    required this.selectedId,
    required this.onSelect,
    required this.onToggleVisible,
  });

  final List<WorkspaceTaskItem> tasks;
  final int? selectedId;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onToggleVisible;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SpaceShiftColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                const Text(
                  '작업 목록',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: SpaceShiftColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${tasks.length}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: SpaceShiftColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: SpaceShiftColors.border),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: tasks.length,
              separatorBuilder: (context, index) =>
                  const Divider(height: 1, color: SpaceShiftColors.border),
              itemBuilder: (context, index) {
                final task = tasks[index];
                return _TaskRow(
                  task: task,
                  selected: task.id == selectedId,
                  onTap: () => onSelect(task.id),
                  onToggleVisible: () => onToggleVisible(task.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.task,
    required this.selected,
    required this.onTap,
    required this.onToggleVisible,
  });

  final WorkspaceTaskItem task;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onToggleVisible;

  @override
  Widget build(BuildContext context) {
    final accent = workspaceMarkerColorFor(task.number);

    return Material(
      color: selected ? accent.withValues(alpha: 0.06) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${task.number}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: SpaceShiftColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      task.heightMm != null
                          ? '${task.finishLabel}  |  높이 ${task.heightMm!.toStringAsFixed(0)}mm'
                          : task.finishLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        color: SpaceShiftColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 22,
                height: 22,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: task.color,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: SpaceShiftColors.border),
                ),
              ),
              IconButton(
                onPressed: onToggleVisible,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  task.visible
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                  color: SpaceShiftColors.textSecondary,
                ),
              ),
              IconButton(
                onPressed: onTap,
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.edit_outlined,
                  size: 18,
                  color: SpaceShiftColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
