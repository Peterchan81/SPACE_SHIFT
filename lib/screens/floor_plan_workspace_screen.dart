import 'package:flutter/material.dart';

import '../models/workspace_task_item.dart';
import '../theme/space_shift_colors.dart';
import '../widgets/workspace/start_method_panel.dart';
import '../widgets/workspace/user_workspace_panel.dart';
import '../widgets/workspace/workspace_canvas.dart';
import '../widgets/workspace/workspace_task_list.dart';
import '../widgets/workspace/workspace_view_switcher.dart';

/// 신규 MASTER 1번 — "평면도 업로드" 작업실.
///
/// 이번 작업 범위는 [WorkspaceStartMethod.floorPlanUpload]의 실제 화면
/// 구현이다. 나머지 두 시작 방식(직접 그리기/사진으로 변환)은 좌측 패널의
/// 진입 선택 UI만 제공하고, 실제 화면은 아직 없어 선택 시 안내만 보여준다.
///
/// 기존 [WorkspaceScreen](공간 작업실, 사진 기반 부분 영역 선택)은 그대로
/// 유지되며 이 화면과 무관하게 계속 동작한다 — 이 화면은 완전히 새로운
/// 평면도 기반 3D 작업실이다.
class FloorPlanWorkspaceScreen extends StatefulWidget {
  const FloorPlanWorkspaceScreen({super.key, this.projectName = '새 프로젝트'});

  final String projectName;

  @override
  State<FloorPlanWorkspaceScreen> createState() =>
      _FloorPlanWorkspaceScreenState();
}

class _FloorPlanWorkspaceScreenState extends State<FloorPlanWorkspaceScreen> {
  WorkspaceStartMethod _startMethod = WorkspaceStartMethod.floorPlanUpload;
  WorkspaceViewMode _viewMode = WorkspaceViewMode.plan2d;
  WorkspaceSelectionTool _tool = WorkspaceSelectionTool.select;

  late List<WorkspaceTaskItem> _tasks;
  int? _selectedTaskId;

  final List<List<WorkspaceTaskItem>> _undoStack = [];
  final List<List<WorkspaceTaskItem>> _redoStack = [];

  @override
  void initState() {
    super.initState();
    _tasks = _demoTasks();
    _selectedTaskId = _tasks.first.id;
  }

  static List<WorkspaceTaskItem> _demoTasks() => [
    const WorkspaceTaskItem(
      id: 1,
      number: 1,
      name: '거실 벽 (TV 벽체)',
      category: WorkspaceTaskCategory.wall,
      finishLabel: '패널',
      color: Color(0xFFB98A5C),
      markerPosition: Offset(0.28, 0.32),
      heightMm: 2700,
      widthMm: 3600,
      thicknessMm: 120,
    ),
    const WorkspaceTaskItem(
      id: 2,
      number: 2,
      name: '거실 바닥',
      category: WorkspaceTaskCategory.floor,
      finishLabel: '마루',
      color: Color(0xFFCDA073),
      markerPosition: Offset(0.5, 0.72),
      heightMm: 0,
      widthMm: 4200,
      thicknessMm: 15,
    ),
    const WorkspaceTaskItem(
      id: 3,
      number: 3,
      name: '안방 벽',
      category: WorkspaceTaskCategory.wall,
      finishLabel: '벽지',
      color: Color(0xFFF2EEE9),
      markerPosition: Offset(0.72, 0.28),
      heightMm: 2700,
      widthMm: 3000,
      thicknessMm: 120,
    ),
    const WorkspaceTaskItem(
      id: 4,
      number: 4,
      name: '욕실 벽',
      category: WorkspaceTaskCategory.wall,
      finishLabel: '타일',
      color: Color(0xFFE3E7E9),
      markerPosition: Offset(0.34, 0.58),
      heightMm: 2400,
      widthMm: 2000,
      thicknessMm: 100,
    ),
    const WorkspaceTaskItem(
      id: 5,
      number: 5,
      name: '침실 벽',
      category: WorkspaceTaskCategory.wall,
      finishLabel: '페인트',
      color: Color(0xFFEDE6DC),
      markerPosition: Offset(0.6, 0.52),
      heightMm: 2700,
      widthMm: 3200,
      thicknessMm: 120,
    ),
    const WorkspaceTaskItem(
      id: 6,
      number: 6,
      name: '서재 벽',
      category: WorkspaceTaskCategory.wall,
      finishLabel: '석재',
      color: Color(0xFFA9ADB2),
      markerPosition: Offset(0.8, 0.62),
      heightMm: 2700,
      widthMm: 2600,
      thicknessMm: 130,
    ),
  ];

  WorkspaceTaskItem? get _selectedTask =>
      _tasks.where((task) => task.id == _selectedTaskId).firstOrNull;

  void _mutate(
    List<WorkspaceTaskItem> Function(List<WorkspaceTaskItem>) mutator,
  ) {
    setState(() {
      _undoStack.add(List.of(_tasks));
      _redoStack.clear();
      _tasks = mutator(List.of(_tasks));
    });
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    setState(() {
      _redoStack.add(List.of(_tasks));
      _tasks = _undoStack.removeLast();
    });
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    setState(() {
      _undoStack.add(List.of(_tasks));
      _tasks = _redoStack.removeLast();
    });
  }

  void _updateSelected(WorkspaceTaskItem Function(WorkspaceTaskItem) update) {
    final id = _selectedTaskId;
    if (id == null) return;
    _mutate(
      (tasks) => [
        for (final task in tasks)
          if (task.id == id) update(task) else task,
      ],
    );
  }

  void _onStartMethodSelected(WorkspaceStartMethod method) {
    setState(() => _startMethod = method);
    if (method != WorkspaceStartMethod.floorPlanUpload) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${method.title}"은(는) 준비 중입니다. 곧 지원할 예정입니다.')),
      );
      setState(() => _startMethod = WorkspaceStartMethod.floorPlanUpload);
    }
  }

  void _onAiAssistantTap() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => const Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.smart_toy_outlined,
              size: 28,
              color: SpaceShiftColors.textPrimary,
            ),
            SizedBox(height: 12),
            Text(
              'AI 어시스턴트',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'AI 어시스턴트 대화 기능은 현재 준비 중입니다.\nAI 렌더링(생성/재생성)과는 별도로 이후 연결될 예정입니다.',
              style: TextStyle(
                fontSize: 13,
                color: SpaceShiftColors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final task = _selectedTask;

    return Scaffold(
      backgroundColor: SpaceShiftColors.background,
      appBar: AppBar(
        title: const Text('평면도 업로드 작업실'),
        backgroundColor: SpaceShiftColors.background,
        foregroundColor: SpaceShiftColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 800;
              return isWide ? _buildWideBody(task) : _buildNarrowBody(task);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildWideBody(WorkspaceTaskItem? task) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 240,
          child: SingleChildScrollView(
            child: StartMethodPanel(
              selected: _startMethod,
              onSelected: _onStartMethodSelected,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(child: _buildCenterColumn(task)),
        const SizedBox(width: 16),
        SizedBox(
          width: 320,
          child: UserWorkspacePanel(
            task: task,
            projectName: widget.projectName,
            taskCount: _tasks.length,
            visibleTaskCount: _tasks.where((t) => t.visible).length,
            selectedTool: _tool,
            onToolSelected: (tool) => setState(() => _tool = tool),
            onToggleVisible: () =>
                _updateSelected((t) => t.copyWith(visible: !t.visible)),
            onToggleLocked: () =>
                _updateSelected((t) => t.copyWith(locked: !t.locked)),
            onRename: () => _showRenameDialog(task),
            onDuplicate: _duplicateSelected,
            onDelete: _deleteSelected,
            onHeightChanged: (value) =>
                _updateSelected((t) => t.copyWith(heightMm: value)),
            onWidthChanged: (value) =>
                _updateSelected((t) => t.copyWith(widthMm: value)),
            onThicknessChanged: (value) =>
                _updateSelected((t) => t.copyWith(thicknessMm: value)),
            onFinishSelected: (value) =>
                _updateSelected((t) => t.copyWith(finishLabel: value)),
            onColorChanged: (value) =>
                _updateSelected((t) => t.copyWith(color: value)),
            canUndo: _undoStack.isNotEmpty,
            canRedo: _redoStack.isNotEmpty,
            onUndo: _undo,
            onRedo: _redo,
            onAiAssistantTap: _onAiAssistantTap,
          ),
        ),
      ],
    );
  }

  Widget _buildNarrowBody(WorkspaceTaskItem? task) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StartMethodPanel(
            selected: _startMethod,
            onSelected: _onStartMethodSelected,
          ),
          const SizedBox(height: 16),
          Center(
            child: WorkspaceViewSwitcher(
              selected: _viewMode,
              onSelected: (mode) => setState(() => _viewMode = mode),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 320,
            child: WorkspaceCanvas(
              tasks: _tasks,
              selectedId: _selectedTaskId,
              onSelect: (id) => setState(() => _selectedTaskId = id),
            ),
          ),
          const SizedBox(height: 12),
          WorkspaceTaskList(
            tasks: _tasks,
            selectedId: _selectedTaskId,
            onSelect: (id) => setState(() => _selectedTaskId = id),
            onToggleVisible: (id) => _mutate(
              (tasks) => [
                for (final t in tasks)
                  if (t.id == id) t.copyWith(visible: !t.visible) else t,
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 560,
            child: UserWorkspacePanel(
              task: task,
              projectName: widget.projectName,
              taskCount: _tasks.length,
              visibleTaskCount: _tasks.where((t) => t.visible).length,
              selectedTool: _tool,
              onToolSelected: (tool) => setState(() => _tool = tool),
              onToggleVisible: () =>
                  _updateSelected((t) => t.copyWith(visible: !t.visible)),
              onToggleLocked: () =>
                  _updateSelected((t) => t.copyWith(locked: !t.locked)),
              onRename: () => _showRenameDialog(task),
              onDuplicate: _duplicateSelected,
              onDelete: _deleteSelected,
              onHeightChanged: (value) =>
                  _updateSelected((t) => t.copyWith(heightMm: value)),
              onWidthChanged: (value) =>
                  _updateSelected((t) => t.copyWith(widthMm: value)),
              onThicknessChanged: (value) =>
                  _updateSelected((t) => t.copyWith(thicknessMm: value)),
              onFinishSelected: (value) =>
                  _updateSelected((t) => t.copyWith(finishLabel: value)),
              onColorChanged: (value) =>
                  _updateSelected((t) => t.copyWith(color: value)),
              canUndo: _undoStack.isNotEmpty,
              canRedo: _redoStack.isNotEmpty,
              onUndo: _undo,
              onRedo: _redo,
              onAiAssistantTap: _onAiAssistantTap,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCenterColumn(WorkspaceTaskItem? task) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: WorkspaceViewSwitcher(
            selected: _viewMode,
            onSelected: (mode) => setState(() => _viewMode = mode),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: WorkspaceCanvas(
            tasks: _tasks,
            selectedId: _selectedTaskId,
            onSelect: (id) => setState(() => _selectedTaskId = id),
          ),
        ),
        const SizedBox(height: 12),
        WorkspaceTaskList(
          tasks: _tasks,
          selectedId: _selectedTaskId,
          onSelect: (id) => setState(() => _selectedTaskId = id),
          onToggleVisible: (id) => _mutate(
            (tasks) => [
              for (final t in tasks)
                if (t.id == id) t.copyWith(visible: !t.visible) else t,
            ],
          ),
        ),
      ],
    );
  }

  void _duplicateSelected() {
    final task = _selectedTask;
    if (task == null) return;
    _mutate((tasks) {
      final nextNumber = tasks.length + 1;
      final nextId = tasks.map((t) => t.id).reduce((a, b) => a > b ? a : b) + 1;
      final copy = WorkspaceTaskItem(
        id: nextId,
        number: nextNumber,
        name: '${task.name} 사본',
        category: task.category,
        finishLabel: task.finishLabel,
        color: task.color,
        markerPosition: task.markerPosition + const Offset(0.04, 0.04),
        heightMm: task.heightMm,
        widthMm: task.widthMm,
        thicknessMm: task.thicknessMm,
      );
      return [...tasks, copy];
    });
    setState(() => _selectedTaskId = _tasks.last.id);
  }

  void _deleteSelected() {
    final id = _selectedTaskId;
    if (id == null) return;
    _mutate((tasks) => tasks.where((t) => t.id != id).toList());
    setState(() => _selectedTaskId = null);
  }

  Future<void> _showRenameDialog(WorkspaceTaskItem? task) async {
    if (task == null) return;
    final controller = TextEditingController(text: task.name);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('이름 변경'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      _updateSelected((t) => t.copyWith(name: result));
    }
  }
}
