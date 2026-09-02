import 'package:flutter/material.dart';

import '../../models/cad_workspace_state.dart';
import '../../models/floor_plan_file.dart';
import '../../models/floor_plan_geometry.dart';
import '../../models/space_scene.dart';
import '../../models/workspace_task_item.dart';
import '../../theme/space_shift_colors.dart';
import 'floor_plan_preview.dart';

/// 중앙 공간 이미지/3D 작업 화면.
///
/// 실제 3D 렌더링 엔진은 이번 작업 범위가 아니다 — 배경은
/// [FloorPlanPreview]가 업로드/분석/CAD 단계별 상태를 정직하게 보여주고,
/// 그 위에 "사용자가 실제로 만든 작업"의 번호 marker만 정규화 좌표
/// (0.0~1.0)로 겹쳐 보여주는 구조다. 분석 geometry(벽/공간/문·창)는
/// 사용자 작업이 아니므로 여기서 번호를 붙이지 않는다 — CAD
/// geometry 자체의 표시/선택은 [FloorPlanPreview] 안의 CAD 오버레이가
/// 담당한다.
///
/// CAD 표시 도구모음/분석 상태 안내는 더 이상 이 캔버스 위에 그리지
/// 않는다 — 도면을 가리는 문제가 있어 우측 "사용자 작업 환경"의
/// [FloorPlanStatusSection]으로 옮겼다. 중앙은 평면도 자체를 보는 화면으로
/// 최대한 단순하게 유지한다.
class WorkspaceCanvas extends StatelessWidget {
  const WorkspaceCanvas({
    super.key,
    required this.tasks,
    required this.selectedId,
    required this.onSelect,
    required this.viewMode,
    required this.floorPlanFile,
    required this.analysisResult,
    required this.cad,
    required this.cadCallbacks,
    required this.onPickFloorPlanFile,
    this.spaceScene,
    this.spaceGenerationFailureMessage,
  });

  final List<WorkspaceTaskItem> tasks;
  final int? selectedId;
  final ValueChanged<int> onSelect;

  final WorkspaceViewMode viewMode;
  final FloorPlanFile? floorPlanFile;
  final FloorPlanAnalysisResult? analysisResult;
  final CadWorkspaceState cad;
  final CadWorkspaceCallbacks cadCallbacks;
  final VoidCallback onPickFloorPlanFile;

  /// [CadWorkspaceCallbacks.onGenerate3D]가 실제로 만든 3D geometry —
  /// null이면(아직 생성 전) [FloorPlanPreview]가 준비 상태 안내를 보여준다.
  final SpaceScene? spaceScene;
  final String? spaceGenerationFailureMessage;

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
                analysisResult: analysisResult,
                cad: cad,
                cadCallbacks: cadCallbacks,
                onPickFile: onPickFloorPlanFile,
                spaceScene: spaceScene,
                spaceGenerationFailureMessage: spaceGenerationFailureMessage,
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
