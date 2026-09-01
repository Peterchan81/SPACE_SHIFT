import 'package:flutter/material.dart';

import '../../models/floor_plan_file.dart';
import '../../models/workspace_task_item.dart';
import '../../theme/space_shift_colors.dart';
import 'floor_plan_upload_card.dart';

/// 좌측 "시작 방식 선택" 패널 — 항상 3가지 방식을 카드로 보여준다.
///
/// 이번 작업 범위는 [WorkspaceStartMethod.floorPlanUpload]가 실제로
/// 동작하는 것이다 — 이 카드만 [FloorPlanUploadCard]로 그려 파일 선택
/// 상태/버튼을 함께 보여준다. 나머지 두 방식은 진입 선택 UI만 유지하고
/// (카드 클릭 시 안내만 표시), 전체 기능은 후속 작업(WO)에서 진행한다.
class StartMethodPanel extends StatelessWidget {
  const StartMethodPanel({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.floorPlanFile,
    required this.onPickFloorPlanFile,
  });

  final WorkspaceStartMethod selected;
  final ValueChanged<WorkspaceStartMethod> onSelected;

  /// 현재까지 선택된 평면도 파일(없으면 null) — "① 평면도 업로드" 카드의
  /// 상태 표시에 쓰인다.
  final FloorPlanFile? floorPlanFile;
  final VoidCallback onPickFloorPlanFile;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '시작 방식 선택',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: SpaceShiftColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (final method in WorkspaceStartMethod.values) ...[
          if (method == WorkspaceStartMethod.floorPlanUpload)
            FloorPlanUploadCard(
              selected: method == selected,
              file: floorPlanFile,
              onSelectCard: () => onSelected(method),
              onPickFile: onPickFloorPlanFile,
            )
          else
            _StartMethodCard(
              method: method,
              selected: method == selected,
              onTap: () => onSelected(method),
            ),
          if (method != WorkspaceStartMethod.values.last)
            const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _StartMethodCard extends StatelessWidget {
  const _StartMethodCard({
    required this.method,
    required this.selected,
    required this.onTap,
  });

  final WorkspaceStartMethod method;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = workspaceMarkerColorFor(method.index + 1);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? accent : SpaceShiftColors.border,
              width: selected ? 1.5 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${method.index + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      method.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: SpaceShiftColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      method.description,
                      style: const TextStyle(
                        fontSize: 12,
                        color: SpaceShiftColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: SpaceShiftColors.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: SpaceShiftColors.border),
                ),
                child: Icon(method.icon, size: 20, color: accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
