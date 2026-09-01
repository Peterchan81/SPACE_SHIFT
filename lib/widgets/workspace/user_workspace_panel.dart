import 'package:flutter/material.dart';

import '../../models/cad_floor_plan.dart';
import '../../models/floor_plan_geometry.dart';
import '../../models/workspace_task_item.dart';
import '../../theme/space_shift_colors.dart';
import 'cad_structure_tab.dart';
import 'display_tab.dart';
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
/// 안으로 옮기고, AI 어시스턴트는 항상 열려있는 채팅이 아니라 이 패널
/// 하단의 진입 버튼 하나로 분리한다(WO 21번, AI 렌더링과는 별개 기능).
class UserWorkspacePanel extends StatefulWidget {
  const UserWorkspacePanel({
    super.key,
    required this.task,
    required this.projectName,
    required this.taskCount,
    required this.visibleTaskCount,
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
    required this.onAiAssistantTap,
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
  final VoidCallback onAiAssistantTap;

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
          const Divider(height: 1, color: SpaceShiftColors.border),
          Padding(
            padding: const EdgeInsets.all(12),
            child: _AiAssistantButton(onTap: widget.onAiAssistantTap),
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_tab) {
      case _PanelTab.work:
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
          // 되돌릴 방법이 선택 상태에 갇힌 CadStructureTab 안에만
          // 있으면 안 된다 — 선택이 비어 있어도 실행 취소는 여기서
          // 계속 할 수 있어야 한다.
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

class _AiAssistantButton extends StatelessWidget {
  const _AiAssistantButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: SpaceShiftColors.spectrum,
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.smart_toy_outlined, size: 18, color: Colors.white),
              SizedBox(width: 8),
              Text(
                'AI 어시스턴트',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
