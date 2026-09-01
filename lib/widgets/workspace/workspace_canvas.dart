import 'package:flutter/material.dart';

import '../../models/cad_workspace_state.dart';
import '../../models/floor_plan_file.dart';
import '../../models/floor_plan_geometry.dart';
import '../../models/workspace_task_item.dart';
import '../../theme/space_shift_colors.dart';
import 'floor_plan_preview.dart';

/// [FloorPlanPreview]가 그리는 2D 캔버스와 헤더(CAD 도구모음/상태 배너)
/// 사이의 경계가, 아래 [WorkspaceCanvas]가 헤더를 캔버스 위에 겹쳐
/// 그리지 않고 별도 레이아웃 공간에 그리도록 이 함수로 판단한다 —
/// [FloorPlanPreview] 내부의 조건과 정확히 같아야 한다(2D 뷰 + 파일
/// 있음일 때만 헤더가 있다).
bool _showsCanvasHeader(WorkspaceViewMode viewMode, FloorPlanFile? file) {
  return viewMode == WorkspaceViewMode.plan2d && file != null;
}

/// 중앙 공간 이미지/3D 작업 화면.
///
/// 실제 3D 렌더링 엔진은 이번 작업 범위가 아니다 — 배경은
/// [FloorPlanPreview]가 업로드/분석/CAD 단계별 상태를 정직하게 보여주고,
/// 그 위에 "사용자가 실제로 만든 작업"의 번호 marker만 정규화 좌표
/// (0.0~1.0)로 겹쳐 보여주는 구조다. 분석 geometry(벽/공간/문·창)는
/// 사용자 작업이 아니므로 여기서 번호를 붙이지 않는다 — CAD
/// geometry 자체의 표시/선택은 [FloorPlanPreview] 안의 CAD 오버레이가
/// 담당한다.
class WorkspaceCanvas extends StatelessWidget {
  const WorkspaceCanvas({
    super.key,
    required this.tasks,
    required this.selectedId,
    required this.onSelect,
    required this.viewMode,
    required this.floorPlanFile,
    required this.analysisPhase,
    required this.analysisStep,
    required this.analysisResult,
    required this.analysisFailureMessage,
    required this.cad,
    required this.cadCallbacks,
    required this.onPickFloorPlanFile,
    required this.onStartAnalysis,
  });

  final List<WorkspaceTaskItem> tasks;
  final int? selectedId;
  final ValueChanged<int> onSelect;

  final WorkspaceViewMode viewMode;
  final FloorPlanFile? floorPlanFile;
  final FloorPlanAnalysisPhase analysisPhase;
  final FloorPlanAnalysisStep? analysisStep;
  final FloorPlanAnalysisResult? analysisResult;
  final String? analysisFailureMessage;
  final CadWorkspaceState cad;
  final CadWorkspaceCallbacks cadCallbacks;
  final VoidCallback onPickFloorPlanFile;
  final VoidCallback onStartAnalysis;

  @override
  Widget build(BuildContext context) {
    final showsHeader = _showsCanvasHeader(viewMode, floorPlanFile);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SpaceShiftColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          if (showsHeader)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: cad.floorPlan != null
                  ? Align(
                      alignment: Alignment.topLeft,
                      child: CadToolbar(cad: cad, callbacks: cadCallbacks),
                    )
                  : FloorPlanStatusBanner(
                      file: floorPlanFile!,
                      result: analysisResult,
                    ),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    FloorPlanPreview(
                      viewMode: viewMode,
                      file: floorPlanFile,
                      analysisPhase: analysisPhase,
                      analysisStep: analysisStep,
                      analysisResult: analysisResult,
                      failureMessage: analysisFailureMessage,
                      cad: cad,
                      cadCallbacks: cadCallbacks,
                      onPickFile: onPickFloorPlanFile,
                      onStartAnalysis: onStartAnalysis,
                    ),
                    for (final task in tasks)
                      if (task.visible)
                        Positioned(
                          left:
                              task.markerPosition.dx * constraints.maxWidth -
                              16,
                          top:
                              task.markerPosition.dy * constraints.maxHeight -
                              16,
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
          ),
        ],
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
