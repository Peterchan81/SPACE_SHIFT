import 'package:flutter/material.dart';

import '../../models/workspace_task_item.dart';
import 'additional_options_section.dart';
import 'finish_selector.dart';
import 'recommended_palette.dart';
import 'selected_item_header.dart';
import 'selection_edit_tools.dart';
import 'size_editor.dart';
import 'workspace_color_picker.dart';

/// 우측 "작업 환경 → 작업" Tab. 위에서 아래 순서(WO 11번)로 조립한다 —
/// 선택된 항목 → 사이즈 → 선택 영역 편집 → 마감재 선택 → 색상 선택 →
/// 추천 색상 → 추가 옵션. 항목이 많아도 내부에서 세로 스크롤한다(WO 18).
class WorkTab extends StatelessWidget {
  const WorkTab({
    super.key,
    required this.task,
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
  });

  final WorkspaceTaskItem task;
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectedItemHeader(
          task: task,
          onToggleVisible: onToggleVisible,
          onToggleLocked: onToggleLocked,
          onRename: onRename,
          onDuplicate: onDuplicate,
          onDelete: onDelete,
        ),
        const SizedBox(height: 16),
        SizeEditor(
          // 값이 없으면(예: 평면도 실제 분석으로 만들어진 항목 — 아직
          // 실제 축척을 모름) 가짜 기본값(2700mm 등)으로 채우지 않고
          // "미설정"으로 정직하게 보여준다(WO 17번).
          heightMm: task.heightMm,
          widthMm: task.widthMm,
          thicknessMm: task.thicknessMm,
          onHeightChanged: onHeightChanged,
          onWidthChanged: onWidthChanged,
          onThicknessChanged: onThicknessChanged,
        ),
        const SizedBox(height: 16),
        SelectionEditTools(selected: selectedTool, onSelected: onToolSelected),
        const SizedBox(height: 16),
        FinishSelector(
          options: task.category.finishOptions,
          selectedOption: task.finishLabel,
          onOptionSelected: onFinishSelected,
          onUploadCustom: () {},
        ),
        const SizedBox(height: 16),
        WorkspaceColorPicker(color: task.color, onColorChanged: onColorChanged),
        const SizedBox(height: 16),
        RecommendedPalette(
          onSelected: (option) => onColorChanged(option.color),
        ),
        const SizedBox(height: 16),
        const AdditionalOptionsSection(),
      ],
    );
  }
}
