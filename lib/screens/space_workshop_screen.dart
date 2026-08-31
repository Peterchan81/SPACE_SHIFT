import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/space_task.dart';
import '../services/image_picker_service.dart';
import '../widgets/space_canvas.dart';
import '../widgets/space_task_card.dart';
import '../widgets/tool_category_panel.dart';
import 'generate_screen.dart';

/// SPACE SHIFT V1의 핵심 화면인 공간 작업실.
///
/// 사용자가 업로드한 공간 사진을 작업 Canvas로 사용해 원하는 영역을
/// Finger/S-Pen으로 직접 선택하고, 카테고리·변경 지시 텍스트·참고 이미지로
/// 구성된 작업을 여러 개 등록한 뒤 "공간의 변화 만들기"로 AI 생성을
/// 요청하는 화면이다.
class SpaceWorkshopScreen extends StatefulWidget {
  const SpaceWorkshopScreen({
    super.key,
    required this.imageBytes,
    this.initialTasks = const [],
    this.imagePickerService = const ImagePickerService(),
  });

  /// 작업 Canvas로 사용할 공간 사진.
  /// 수정 재요청 흐름에서는 이전 AI 생성 결과 이미지가 전달될 수 있다.
  final Uint8List imageBytes;

  /// 수정 재요청 등으로 재진입할 때 이어서 편집할 기존 작업 목록.
  final List<SpaceTask> initialTasks;

  final ImagePickerService imagePickerService;

  @override
  State<SpaceWorkshopScreen> createState() => _SpaceWorkshopScreenState();
}

class _SpaceWorkshopScreenState extends State<SpaceWorkshopScreen> {
  late List<SpaceTask> _tasks = List.of(widget.initialTasks);
  SpaceCategory _selectedCategory = SpaceCategory.all;
  NormalizedRect? _editingRect;
  String? _activeTaskId;
  int _taskSequence = 0;

  bool get _hasValidTasks =>
      _tasks.isNotEmpty && _tasks.every((task) => task.instruction.trim().isNotEmpty);

  String _newTaskId() {
    _taskSequence++;
    return 'task_${DateTime.now().microsecondsSinceEpoch}_$_taskSequence';
  }

  void _handleEditingRectChanged(NormalizedRect? rect) {
    setState(() => _editingRect = rect);
  }

  void _handleTaskTap(String taskId) {
    final task = _tasks.firstWhere((t) => t.id == taskId);
    setState(() {
      _activeTaskId = taskId;
      _editingRect = task.rect;
      _selectedCategory = task.category;
    });
  }

  void _cancelSelection() {
    setState(() {
      _editingRect = null;
      _activeTaskId = null;
    });
  }

  void _confirmSelection() {
    final rect = _editingRect;
    if (rect == null) return;

    setState(() {
      final activeId = _activeTaskId;
      if (activeId != null) {
        final index = _tasks.indexWhere((t) => t.id == activeId);
        if (index != -1) {
          _tasks[index] = _tasks[index].copyWith(
            category: _selectedCategory,
            rect: rect,
          );
          _editingRect = null;
          _activeTaskId = null;
          return;
        }
      }

      _tasks = [
        ..._tasks,
        SpaceTask(id: _newTaskId(), category: _selectedCategory, rect: rect),
      ];
      _editingRect = null;
      _activeTaskId = null;
    });
  }

  void _editTaskRegion(SpaceTask task) {
    setState(() {
      _activeTaskId = task.id;
      _editingRect = task.rect;
      _selectedCategory = task.category;
    });
  }

  void _updateInstruction(String taskId, String value) {
    setState(() {
      final index = _tasks.indexWhere((t) => t.id == taskId);
      if (index == -1) return;
      _tasks[index] = _tasks[index].copyWith(instruction: value);
    });
  }

  Future<void> _pickReferenceImage(String taskId) async {
    final bytes = await widget.imagePickerService.pickGalleryImage();
    if (bytes == null || !mounted) return;
    setState(() {
      final index = _tasks.indexWhere((t) => t.id == taskId);
      if (index == -1) return;
      _tasks[index] = _tasks[index].copyWith(referenceImageBytes: bytes);
    });
  }

  void _removeReferenceImage(String taskId) {
    setState(() {
      final index = _tasks.indexWhere((t) => t.id == taskId);
      if (index == -1) return;
      _tasks[index] = _tasks[index].copyWith(clearReferenceImage: true);
    });
  }

  void _deleteTask(String taskId) {
    setState(() {
      _tasks = _tasks.where((t) => t.id != taskId).toList();
      if (_activeTaskId == taskId) {
        _activeTaskId = null;
        _editingRect = null;
      }
    });
  }

  void _goToGenerate() {
    if (!_hasValidTasks) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => GenerateScreen(
          selectedStyle: _tasks.map((t) => t.summary).join(' / '),
          selectedImageBytes: widget.imageBytes,
          tasks: _tasks,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('공간 작업실'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF212121),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '사진에서 바꾸고 싶은 부분을 선택해주세요',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF212121),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '손가락이나 S Pen으로 영역을 드래그해 지정하고, 오른쪽에서 대상을 고른 뒤\n'
                    '변경하고 싶은 내용을 적어주세요.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF757575),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SpaceCanvas(
                          imageBytes: widget.imageBytes,
                          tasks: _tasks,
                          editingRect: _editingRect,
                          activeTaskId: _activeTaskId,
                          onEditingRectChanged: _handleEditingRectChanged,
                          onTaskTap: _handleTaskTap,
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        height: 340,
                        child: ToolCategoryPanel(
                          selected: _selectedCategory,
                          onSelected: (category) =>
                              setState(() => _selectedCategory = category),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_editingRect != null)
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _confirmSelection,
                            icon: const Icon(Icons.check_rounded),
                            label: Text(
                              _activeTaskId != null ? '영역 수정 적용' : '이 영역으로 작업 추가',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: _cancelSelection,
                          child: const Text('선택 취소'),
                        ),
                      ],
                    )
                  else if (_tasks.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 14,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.add_rounded,
                            size: 18,
                            color: Color(0xFF757575),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '다른 부분을 더 바꾸려면 Canvas에서 새 영역을 드래그하세요.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF757575),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 20),
                  if (_tasks.isNotEmpty) ...[
                    const Text(
                      '등록된 작업',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF212121),
                      ),
                    ),
                    const SizedBox(height: 10),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _tasks.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final task = _tasks[index];
                        return SpaceTaskCard(
                          key: ValueKey(task.id),
                          task: task,
                          index: index,
                          isEditingRegion: task.id == _activeTaskId,
                          onInstructionChanged: (value) =>
                              _updateInstruction(task.id, value),
                          onPickReferenceImage: () =>
                              _pickReferenceImage(task.id),
                          onRemoveReferenceImage: () =>
                              _removeReferenceImage(task.id),
                          onEditRegion: () => _editTaskRegion(task),
                          onDelete: () => _deleteTask(task.id),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                  ],
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: _hasValidTasks ? spaceRainbowGradient : null,
                      color: _hasValidTasks ? null : const Color(0xFFEEEEEE),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: _hasValidTasks ? _goToGenerate : null,
                        child: SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: Center(
                            child: Text(
                              '공간의 변화 만들기',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: _hasValidTasks
                                    ? Colors.white
                                    : const Color(0xFF9E9E9E),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_tasks.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        '먼저 사진 위에서 영역을 하나 이상 선택해 작업을 등록해주세요.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF9E9E9E)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
