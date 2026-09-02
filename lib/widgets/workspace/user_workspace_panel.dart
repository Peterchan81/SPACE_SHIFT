import 'package:flutter/material.dart';

import '../../models/cad_floor_plan.dart';
import '../../models/cad_workspace_state.dart';
import '../../models/floor_plan_file.dart';
import '../../models/floor_plan_geometry.dart';
import '../../models/workspace_task_item.dart';
import '../../theme/space_shift_colors.dart';
import 'cad_structure_tab.dart';
import 'display_tab.dart';
import 'floor_plan_preview.dart';
import 'furniture_tab.dart';
import 'info_tab.dart';
import 'work_tab.dart';

enum _PanelTab { work, furniture, display, info }

extension on _PanelTab {
  String get label => switch (this) {
    _PanelTab.work => '작업',
    _PanelTab.furniture => '가구',
    _PanelTab.display => '디스플레이',
    _PanelTab.info => '정보',
  };

  IconData get icon => switch (this) {
    _PanelTab.work => Icons.build_outlined,
    _PanelTab.furniture => Icons.weekend_outlined,
    _PanelTab.display => Icons.tune_rounded,
    _PanelTab.info => Icons.info_outline_rounded,
  };
}

/// 우측 "사용자 작업 환경" 패널.
///
/// 정확히 4개 탭(작업/가구/디스플레이/정보)만 둔다 — "속성"은 "작업"으로
/// 이름을 바꾸고, 별도 "조명" 탭은 두지 않고 디스플레이 탭 안에 흡수한다
/// (WO 10번). Undo/Redo는 화면 좌측 상단의 옛 플로팅 툴바 대신 이 패널
/// 안으로 옮겼다.
///
/// 실기 FAIL 재수정 WO(16번) — 이 2D/CAD 준비 단계에서는 AI 어시스턴트가
/// 핵심 기능이 아니라는 실사용 피드백에 따라 진입 버튼을 제거했다.
/// AI는 이후 3D 인테리어 작업 단계(디자인/재질/가구 추천)에서 다시
/// 제공할 계획이다 — 지금 여기서 만들지 않는다.
class UserWorkspacePanel extends StatefulWidget {
  const UserWorkspacePanel({
    super.key,
    required this.task,
    required this.projectName,
    required this.taskCount,
    required this.visibleTaskCount,
    required this.viewMode,
    required this.hasFloorPlanFile,
    required this.analysisPhase,
    required this.analysisStep,
    required this.analysisResult,
    required this.analysisFailureMessage,
    required this.onReanalyze,
    required this.cad,
    required this.cadCallbacks,
    required this.selectedTool,
    required this.onToolSelected,
    required this.onToggleVisible,
    required this.onToggleLocked,
    required this.onRename,
    required this.onDuplicate,
    required this.onDelete,
    required this.onHeightChanged,
    required this.onWidthChanged,
    required this.onThicknessChanged,
    required this.onFinishSelected,
    required this.onColorChanged,
    required this.canUndo,
    required this.canRedo,
    required this.onUndo,
    required this.onRedo,
    this.analysisDebugStats,
    this.selectedCadWall,
    this.selectedCadOpening,
    this.selectedCadRoom,
    this.cadScale,
    this.cadSourceWidthPx = 0,
    this.cadSourceHeightPx = 0,
    this.canUndoCad = false,
    this.onUndoCad,
    this.onDeleteCad,
    this.onCreateWorkItemFromCad,
  });

  final WorkspaceTaskItem? task;
  final String projectName;
  final int taskCount;
  final int visibleTaskCount;
  final FloorPlanAnalysisDebugStats? analysisDebugStats;

  /// 현재 보고 있는 View — "작업" 탭 상단에 2D 단계 전용 도면
  /// 분석/표시/3D 준비 상태 섹션([FloorPlanStatusSection])을 보여줄지
  /// 판단하는 데 쓰인다(WO 22번, 우측 패널이 단계별로 다른 내용을
  /// 보여준다).
  final WorkspaceViewMode viewMode;
  final bool hasFloorPlanFile;
  final FloorPlanAnalysisPhase analysisPhase;
  final FloorPlanAnalysisStep? analysisStep;
  final FloorPlanAnalysisResult? analysisResult;
  final String? analysisFailureMessage;
  final VoidCallback onReanalyze;
  final CadWorkspaceState cad;
  final CadWorkspaceCallbacks cadCallbacks;

  /// [task]가 null이고 이 값들 중 하나가 있으면, 사용자 작업 대신 CAD
  /// geometry(도면 보정) 화면을 보여준다 — 둘은 서로 다른 선택 상태다
  /// (WO 8/12번).
  final CadWall? selectedCadWall;
  final CadOpening? selectedCadOpening;
  final CadRoom? selectedCadRoom;
  final FloorPlanScale? cadScale;
  final int cadSourceWidthPx;
  final int cadSourceHeightPx;
  final bool canUndoCad;
  final VoidCallback? onUndoCad;
  final VoidCallback? onDeleteCad;
  final VoidCallback? onCreateWorkItemFromCad;

  final WorkspaceSelectionTool selectedTool;
  final ValueChanged<WorkspaceSelectionTool> onToolSelected;
  final VoidCallback onToggleVisible;
  final VoidCallback onToggleLocked;
  final VoidCallback onRename;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final ValueChanged<double> onHeightChanged;
  final ValueChanged<double> onWidthChanged;
  final ValueChanged<double> onThicknessChanged;
  final ValueChanged<String> onFinishSelected;
  final ValueChanged<Color> onColorChanged;

  final bool canUndo;
  final bool canRedo;
  final VoidCallback onUndo;
  final VoidCallback onRedo;

  @override
  State<UserWorkspacePanel> createState() => _UserWorkspacePanelState();
}

class _UserWorkspacePanelState extends State<UserWorkspacePanel> {
  _PanelTab _tab = _PanelTab.work;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: SpaceShiftColors.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SpaceShiftColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '사용자 작업 환경',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: SpaceShiftColors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: widget.canUndo ? widget.onUndo : null,
                  tooltip: '실행 취소',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.undo_rounded, size: 20),
                ),
                IconButton(
                  onPressed: widget.canRedo ? widget.onRedo : null,
                  tooltip: '다시 실행',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.redo_rounded, size: 20),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                for (final tab in _PanelTab.values)
                  Expanded(
                    child: _PanelTabButton(
                      tab: tab,
                      selected: tab == _tab,
                      onTap: () => setState(() => _tab = tab),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: SpaceShiftColors.border),
          Expanded(child: _buildTabContent()),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_tab) {
      case _PanelTab.work:
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.viewMode == WorkspaceViewMode.plan2d)
              FloorPlanStatusSection(
                hasFloorPlanFile: widget.hasFloorPlanFile,
                analysisPhase: widget.analysisPhase,
                analysisStep: widget.analysisStep,
                analysisResult: widget.analysisResult,
                analysisFailureMessage: widget.analysisFailureMessage,
                onReanalyze: widget.onReanalyze,
                cad: widget.cad,
                cadCallbacks: widget.cadCallbacks,
              )
            else
              _StageNotice(viewMode: widget.viewMode),
            const SizedBox(height: 16),
            _buildSelectionContent(),
          ],
        );
      case _PanelTab.furniture:
        return const FurnitureTab();
      case _PanelTab.display:
        return const DisplayTab();
      case _PanelTab.info:
        return InfoTab(
          projectName: widget.projectName,
          taskCount: widget.taskCount,
          visibleTaskCount: widget.visibleTaskCount,
          analysisDebugStats: widget.analysisDebugStats,
        );
    }
  }

  /// "작업" 탭의 [FloorPlanStatusSection]/[_StageNotice] 아래에 이어지는,
  /// 선택 상태에 따른 실제 편집 콘텐츠 — 사용자 작업(①②③...)이 선택되면
  /// [WorkTab], CAD geometry(도면 보정 대상)가 선택되면 [CadStructureTab],
  /// 아무 것도 선택되지 않았으면 안내만 보여준다(WO 8/12번).
  Widget _buildSelectionContent() {
    final task = widget.task;
    final cadSelected =
        widget.selectedCadWall ??
        widget.selectedCadOpening ??
        widget.selectedCadRoom;
    if (task == null && cadSelected != null) {
      return CadStructureTab(
        wall: widget.selectedCadWall,
        opening: widget.selectedCadOpening,
        room: widget.selectedCadRoom,
        scale: widget.cadScale,
        sourceWidthPx: widget.cadSourceWidthPx,
        sourceHeightPx: widget.cadSourceHeightPx,
        canUndo: widget.canUndoCad,
        onUndo: widget.onUndoCad ?? () {},
        onDelete: widget.onDeleteCad ?? () {},
        onCreateWorkItem: widget.onCreateWorkItemFromCad ?? () {},
      );
    }
    if (task == null) {
      // 삭제 직후에는 선택이 함께 풀리므로, 방금 지운 도면 보정을
      // 되돌릴 방법이 선택 상태에 갇힌 CadStructureTab 안에만 있으면
      // 안 된다 — 선택이 비어 있어도 실행 취소는 여기서 계속 할 수
      // 있어야 한다.
      return _EmptySelectionNotice(
        canUndoCad: widget.canUndoCad,
        onUndoCad: widget.onUndoCad,
      );
    }
    return WorkTab(
      task: task,
      selectedTool: widget.selectedTool,
      onToolSelected: widget.onToolSelected,
      onToggleVisible: widget.onToggleVisible,
      onToggleLocked: widget.onToggleLocked,
      onRename: widget.onRename,
      onDuplicate: widget.onDuplicate,
      onDelete: widget.onDelete,
      onHeightChanged: widget.onHeightChanged,
      onWidthChanged: widget.onWidthChanged,
      onThicknessChanged: widget.onThicknessChanged,
      onFinishSelected: widget.onFinishSelected,
      onColorChanged: widget.onColorChanged,
    );
  }
}

/// 3D 아이소/투시 단계에서 "작업" 탭 상단에 보여주는 안내 — 아직 실제
/// 3D 렌더링 엔진이 없으므로, 있지도 않은 3D 편집 도구를 있는 것처럼
/// 보여주지 않는다(WO 11/22번). 마커 선택 시 아래 [WorkTab]에서 실제로
/// 되는 속성(사이즈/마감재/색상) 편집은 그대로 이어진다.
class _StageNotice extends StatelessWidget {
  const _StageNotice({required this.viewMode});

  final WorkspaceViewMode viewMode;

  @override
  Widget build(BuildContext context) {
    final title = viewMode == WorkspaceViewMode.isometric3d
        ? '3D 아이소 — 인테리어 작업 단계'
        : '3D 투시 — 결과 확인 단계';
    final message = viewMode == WorkspaceViewMode.isometric3d
        ? '2D에서 확정한 도면 구조·축척·천장고를 바탕으로 인테리어 작업을 진행하는 '
              '단계입니다. 실제 3D 렌더링 엔진은 아직 이번 범위에 포함되어 있지 않아, '
              '지금은 마커로 표시된 작업을 선택해 사이즈·마감재·색상을 편집할 수 '
              '있습니다.'
        : '완성된 공간을 실제 시점에서 확인하는 최종 확인 화면입니다. 실제 3D 렌더링 '
              '엔진은 아직 이번 범위에 포함되어 있지 않습니다. 수정이 필요하면 상단 '
              '탭에서 "3D 아이소"로 돌아가세요.';
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
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: SpaceShiftColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: const TextStyle(
              fontSize: 12.5,
              color: SpaceShiftColors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelTabButton extends StatelessWidget {
  const _PanelTabButton({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final _PanelTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: selected ? SpaceShiftColors.spectrum : null,
            border: selected
                ? null
                : Border.all(color: SpaceShiftColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                tab.icon,
                size: 18,
                color: selected ? Colors.white : SpaceShiftColors.textSecondary,
              ),
              const SizedBox(height: 3),
              Text(
                tab.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? Colors.white
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

class _EmptySelectionNotice extends StatelessWidget {
  const _EmptySelectionNotice({this.canUndoCad = false, this.onUndoCad});

  final bool canUndoCad;
  final VoidCallback? onUndoCad;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '선택된 항목이 없습니다.\n평면도에서 작업할 영역을 선택해주세요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: SpaceShiftColors.textSecondary,
                height: 1.5,
              ),
            ),
            if (canUndoCad && onUndoCad != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onUndoCad,
                icon: const Icon(Icons.undo_rounded, size: 18),
                label: const Text('실행 취소'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: SpaceShiftColors.textPrimary,
                  side: const BorderSide(color: SpaceShiftColors.border),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
