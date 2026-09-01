import 'package:flutter/material.dart';

import '../../models/floor_plan_file.dart';
import '../../models/workspace_task_item.dart';
import '../../theme/space_shift_colors.dart';
import 'floor_plan_preview.dart';

/// 중앙 공간 이미지/3D 작업 화면.
///
/// 실제 3D 렌더링 엔진은 이번 작업 범위가 아니다(WO 지침 20번) — 배경은
/// [FloorPlanPreview]가 업로드/분석 단계별 상태를 정직하게 보여주고, 그
/// 위에 작업 대상 번호 marker를 정규화 좌표(0.0~1.0)로 겹쳐 보여주는
/// 구조다. 실제 3D 생성이 연결되면 [FloorPlanPreview]의 3D 분기만
/// 교체하면 되고, marker/선택 동기화 로직은 그대로 재사용할 수 있다.
class WorkspaceCanvas extends StatelessWidget {
  const WorkspaceCanvas({
    super.key,
    required this.tasks,
    required this.selectedId,
    required this.onSelect,
    required this.viewMode,
    required this.floorPlanFile,
    required this.analysisPhase,
    required this.onPickFloorPlanFile,
    required this.onStartAnalysis,
  });

  final List<WorkspaceTaskItem> tasks;
  final int? selectedId;
  final ValueChanged<int> onSelect;

  final WorkspaceViewMode viewMode;
  final FloorPlanFile? floorPlanFile;
  final FloorPlanAnalysisPhase analysisPhase;
  final VoidCallback onPickFloorPlanFile;
  final VoidCallback onStartAnalysis;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SpaceShiftColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            fit: StackFit.expand,
            children: [
              FloorPlanPreview(
                viewMode: viewMode,
                file: floorPlanFile,
                analysisPhase: analysisPhase,
                onPickFile: onPickFloorPlanFile,
                onStartAnalysis: onStartAnalysis,
              ),
              for (final task in tasks)
                if (task.visible)
                  Positioned(
                    left: task.markerPosition.dx * constraints.maxWidth - 16,
                    top: task.markerPosition.dy * constraints.maxHeight - 16,
                    child: _CanvasMarker(
                      task: task,
                      selected: task.id == selectedId,
                      onTap: () => onSelect(task.id),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _CanvasMarker extends StatelessWidget {
  const _CanvasMarker({
    required this.task,
    required this.selected,
    required this.onTap,
  });

  final WorkspaceTaskItem task;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = workspaceMarkerColorFor(task.number);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: accent,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: selected ? 3 : 2),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: selected ? 0.55 : 0.3),
              blurRadius: selected ? 12 : 6,
              spreadRadius: selected ? 2 : 0,
            ),
          ],
        ),
        child: Text(
          '${task.number}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
