import 'package:flutter/material.dart';

import '../../models/workspace_task_item.dart';
import '../../theme/space_shift_colors.dart';

/// "선택된 항목" — 보기/숨기기, 잠금/잠금 해제만 빠른 아이콘으로 두고,
/// 세로 점 3개(⋮) 메뉴는 "이름 변경 / 복제 / 삭제"처럼 실제로 필요한
/// secondary action이 있을 때만 둔다(관성적으로 유지하지 않음, WO 11-1).
class SelectedItemHeader extends StatelessWidget {
  const SelectedItemHeader({
    super.key,
    required this.task,
    required this.onToggleVisible,
    required this.onToggleLocked,
    required this.onRename,
    required this.onDuplicate,
    required this.onDelete,
  });

  final WorkspaceTaskItem task;
  final VoidCallback onToggleVisible;
  final VoidCallback onToggleLocked;
  final VoidCallback onRename;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final accent = workspaceMarkerColorFor(task.number);

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
            '선택된 항목',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: SpaceShiftColors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${task.number}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  task.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: SpaceShiftColors.textPrimary,
                  ),
                ),
              ),
              IconButton(
                onPressed: onToggleVisible,
                tooltip: task.visible ? '숨기기' : '보이기',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  task.visible
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                ),
              ),
              IconButton(
                onPressed: onToggleLocked,
                tooltip: task.locked ? '잠금 해제' : '잠금',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  task.locked
                      ? Icons.lock_outline_rounded
                      : Icons.lock_open_rounded,
                  size: 20,
                ),
              ),
              PopupMenuButton<VoidCallback>(
                tooltip: '더 보기',
                icon: const Icon(Icons.more_vert_rounded, size: 20),
                onSelected: (action) => action(),
                itemBuilder: (context) => [
                  PopupMenuItem(value: onRename, child: const Text('이름 변경')),
                  PopupMenuItem(value: onDuplicate, child: const Text('복제')),
                  PopupMenuItem(
                    value: onDelete,
                    child: const Text(
                      '삭제',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
