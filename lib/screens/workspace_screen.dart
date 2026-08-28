import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/region_selection.dart';
import '../models/work_area.dart';
import '../models/work_instruction.dart';
import '../services/image_picker_service.dart';
import '../services/usage_policy_service.dart';
import '../theme/space_shift_colors.dart';
import '../widgets/gradient_cta_button.dart';
import '../widgets/reference_image_picker.dart';
import '../widgets/region_selector.dart';
import '../widgets/work_area_panel.dart';
import 'generate_screen.dart';

/// SPACE SHIFT V1의 핵심 화면 — "공간 작업실".
///
/// 사용자가 공간 사진 위에서 변경하고 싶은 부분을 직접 지정(부분 영역
/// 선택)하고, 부위별로 자연어 작업 지시와 참고 이미지를 더해 하나 이상의
/// [WorkInstruction]을 완성한 뒤 AI 생성으로 넘어가는 화면이다.
class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({
    super.key,
    this.selectedStyle = '',
    required this.selectedImageBytes,
    List<WorkInstruction>? initialWorkInstructions,
    this.initialAdditionalNotes = '',
    this.isRevision = false,
    this.imagePickerService = const ImagePickerService(),
  }) : initialWorkInstructions = initialWorkInstructions ?? const [];

  /// 선택된 스타일 이름. MASTER 최종 흐름에는 별도 스타일 선택 화면이 없으므로
  /// 기본값은 빈 문자열이며, 결과 화면에서는 값이 있을 때만 스타일 카드를 보여준다.
  final String selectedStyle;

  /// 작업 대상이 되는 공간 사진.
  final Uint8List selectedImageBytes;

  /// 결과 화면의 "수정 재요청"에서 되돌아올 때 기존 작업 지시를 이어서
  /// 편집할 수 있도록 미리 채워주는 값. 새로 시작하는 경우 비어 있다.
  final List<WorkInstruction> initialWorkInstructions;

  /// "수정 재요청"에서 이어받는 기타 작업 지시.
  final String initialAdditionalNotes;

  /// 결과 화면(6/9번)에서 "수정 재요청"으로 돌아온 경우 true.
  /// true이면 재생성 후 결과가 아닌 [ReviseResultScreen](8번 화면)으로 이동한다.
  final bool isRevision;

  /// 참고 이미지 선택에 사용하는 서비스. 테스트에서 가짜 구현으로 교체할 수 있다.
  final ImagePickerService imagePickerService;

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  static const Color _background = SpaceShiftColors.background;

  late List<WorkInstruction> _instructions;
  late final TextEditingController _instructionController;
  late final TextEditingController _additionalNotesController;

  WorkArea _selectedArea = WorkArea.wall;
  RegionSelection? _currentSelection;
  List<Uint8List> _referenceImages = [];
  int _idCounter = 0;

  /// 사진 위에서 영역을 드래그하는 동안에는 바깥 스크롤을 잠가, 손가락으로
  /// 선택 영역을 그리는 도중에 화면 전체가 함께 스크롤되지 않도록 한다.
  bool _isSelectingRegion = false;

  @override
  void initState() {
    super.initState();
    _instructions = List.of(widget.initialWorkInstructions);
    _instructionController = TextEditingController();
    _additionalNotesController = TextEditingController(
      text: widget.initialAdditionalNotes,
    );
  }

  @override
  void dispose() {
    _instructionController.dispose();
    _additionalNotesController.dispose();
    super.dispose();
  }

  String _newId() => 'work_${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}';

  void _showGuidance(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addReferenceImage() async {
    if (_referenceImages.length >= 3) return;
    try {
      final bytes = await widget.imagePickerService.pickGalleryImage();
      if (bytes == null || !mounted) return;
      setState(() => _referenceImages = [..._referenceImages, bytes]);
    } catch (_) {
      if (!mounted) return;
      _showGuidance('참고 이미지를 불러오지 못했습니다. 다시 시도해주세요.');
    }
  }

  void _removeReferenceImage(int index) {
    setState(() {
      _referenceImages = List.of(_referenceImages)..removeAt(index);
    });
  }

  void _addCurrentAsInstruction() {
    final selection = _currentSelection;
    final text = _instructionController.text.trim();
    if (selection == null) {
      _showGuidance('먼저 사진 위에서 변경하고 싶은 부분을 선택해주세요.');
      return;
    }
    if (text.isEmpty) {
      _showGuidance('선택한 부분을 어떻게 바꾸고 싶은지 입력해주세요.');
      return;
    }
    setState(() {
      _instructions = [
        ..._instructions,
        WorkInstruction(
          id: _newId(),
          area: _selectedArea,
          selection: selection,
          instructionText: text,
          referenceImages: List.of(_referenceImages),
        ),
      ];
      _currentSelection = null;
      _instructionController.clear();
      _referenceImages = [];
    });
    _showGuidance('작업 목록에 추가했습니다. 다른 부분을 이어서 선택해보세요.');
  }

  void _editInstruction(int index) {
    setState(() {
      final item = _instructions[index];
      _instructions = List.of(_instructions)..removeAt(index);
      _selectedArea = item.area;
      _currentSelection = item.selection;
      _instructionController.text = item.instructionText;
      _referenceImages = List.of(item.referenceImages);
    });
  }

  void _removeInstruction(int index) {
    setState(() {
      _instructions = List.of(_instructions)..removeAt(index);
    });
  }

  /// 완료된 작업 목록에, 아직 목록에 추가하지 않은 현재 작업(선택 영역 +
  /// 지시문이 모두 채워진 경우)까지 합쳐 최종 목록을 만든다.
  List<WorkInstruction> _buildFinalInstructions() {
    final result = List.of(_instructions);
    final selection = _currentSelection;
    final text = _instructionController.text.trim();
    if (selection != null && text.isNotEmpty) {
      result.add(
        WorkInstruction(
          id: _newId(),
          area: _selectedArea,
          selection: selection,
          instructionText: text,
          referenceImages: List.of(_referenceImages),
        ),
      );
    }
    return result;
  }

  Future<void> _showLimitReachedDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('오늘의 무료 생성 횟수를 모두 사용했어요'),
        content: const Text(
          '하루 3회까지 무료로 공간 변화를 생성할 수 있어요.\n'
          '추가 이용 안내는 준비 중입니다. 내일 다시 무료로 이용해주세요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  void _handleSubmit() {
    final finalInstructions = _buildFinalInstructions();
    final notes = _additionalNotesController.text.trim();

    if (finalInstructions.isEmpty && notes.isEmpty) {
      if (_currentSelection == null && _instructions.isEmpty) {
        _showGuidance('먼저 사진 위에서 변경하고 싶은 부분을 선택해주세요.');
      } else {
        _showGuidance('선택한 부분을 어떻게 바꾸고 싶은지 입력해주세요.');
      }
      return;
    }

    if (!UsagePolicyService.instance.canGenerate) {
      _showLimitReachedDialog();
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => GenerateScreen(
          selectedStyle: widget.selectedStyle,
          selectedImageBytes: widget.selectedImageBytes,
          workInstructions: finalInstructions,
          additionalNotes: notes,
          isRevision: widget.isRevision,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        title: const Text('공간 작업실'),
        backgroundColor: _background,
        foregroundColor: SpaceShiftColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: SingleChildScrollView(
              physics: _isSelectingRegion
                  ? const NeverScrollableScrollPhysics()
                  : const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 800;
                      final imageArea = SizedBox(
                        height: isWide ? 420 : 320,
                        child: RegionSelector(
                          imageBytes: widget.selectedImageBytes,
                          selection: _currentSelection,
                          onChanged: (selection) =>
                              setState(() => _currentSelection = selection),
                          onDragActiveChanged: (active) =>
                              setState(() => _isSelectingRegion = active),
                        ),
                      );
                      final panel = SizedBox(
                        height: isWide ? 420 : 180,
                        width: isWide ? 210 : double.infinity,
                        child: WorkAreaPanel(
                          selected: _selectedArea,
                          onSelected: (area) =>
                              setState(() => _selectedArea = area),
                        ),
                      );

                      if (isWide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: imageArea),
                            const SizedBox(width: 16),
                            panel,
                          ],
                        );
                      }
                      return Column(
                        children: [imageArea, const SizedBox(height: 12), panel],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  _SelectionInfoBar(selection: _currentSelection),
                  const SizedBox(height: 20),
                  Text(
                    _selectedArea.instructionQuestion,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: SpaceShiftColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _instructionController,
                    maxLines: 3,
                    maxLength: 300,
                    decoration: InputDecoration(
                      hintText: '예: 좌측 벽 부분만 밝은 아이보리 컬러로 변경하고 텍스처는 매트하게 해주세요.',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: SpaceShiftColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: SpaceShiftColors.border),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '참고 이미지 (선택)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: SpaceShiftColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ReferenceImagePicker(
                    images: _referenceImages,
                    onAdd: _addReferenceImage,
                    onRemove: _removeReferenceImage,
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _addCurrentAsInstruction,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('다른 부분 작업 추가'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: SpaceShiftColors.selectionAccent,
                        side: const BorderSide(
                          color: SpaceShiftColors.selectionAccent,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  if (_instructions.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Text(
                      '작업 목록',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: SpaceShiftColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (var i = 0; i < _instructions.length; i++)
                      _WorkInstructionTile(
                        index: i,
                        instruction: _instructions[i],
                        onEdit: () => _editInstruction(i),
                        onRemove: () => _removeInstruction(i),
                      ),
                  ],
                  const SizedBox(height: 20),
                  const Text(
                    '다른 부분 작업 지시 (선택)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: SpaceShiftColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _additionalNotesController,
                    maxLines: 3,
                    maxLength: 300,
                    decoration: InputDecoration(
                      hintText: '예: 전등은 간접조명, 바닥은 밝은 원목으로.',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: SpaceShiftColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: SpaceShiftColors.border),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      '오늘의 무료 생성 ${UsagePolicyService.instance.usedToday}/'
                      '${UsagePolicyService.freeDailyLimit}회 사용',
                      style: const TextStyle(
                        fontSize: 13,
                        color: SpaceShiftColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  GradientCtaButton(
                    label: '공간의 변화 만들기',
                    onPressed: _handleSubmit,
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

/// 현재 선택 영역을 사용자 친화적인 백분율로 간결하게 보여주는 정보 바.
class _SelectionInfoBar extends StatelessWidget {
  const _SelectionInfoBar({required this.selection});

  final RegionSelection? selection;

  @override
  Widget build(BuildContext context) {
    final selection = this.selection;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SpaceShiftColors.border),
      ),
      child: selection == null
          ? const Text(
              '사진 위에서 손가락(또는 마우스)으로 드래그해 변경하고 싶은 부분을 선택해주세요.',
              style: TextStyle(fontSize: 14, color: SpaceShiftColors.textSecondary),
            )
          : Row(
              children: [
                const Icon(
                  Icons.crop_rounded,
                  size: 18,
                  color: SpaceShiftColors.selectionAccent,
                ),
                const SizedBox(width: 8),
                const Text(
                  '선택 영역',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: SpaceShiftColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '위치 ${selection.xPercent}%, ${selection.yPercent}%  ·  '
                    '크기 가로 ${selection.widthPercent}% / 세로 ${selection.heightPercent}%',
                    style: const TextStyle(
                      fontSize: 13,
                      color: SpaceShiftColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
    );
  }
}

class _WorkInstructionTile extends StatelessWidget {
  const _WorkInstructionTile({
    required this.index,
    required this.instruction,
    required this.onEdit,
    required this.onRemove,
  });

  final int index;
  final WorkInstruction instruction;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SpaceShiftColors.border),
      ),
      child: Row(
        children: [
          Icon(instruction.area.icon, color: SpaceShiftColors.selectionAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '작업 ${index + 1} · ${instruction.area.label}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: SpaceShiftColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  instruction.instructionText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: SpaceShiftColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onEdit, child: const Text('수정')),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
            color: SpaceShiftColors.textSecondary,
          ),
        ],
      ),
    );
  }
}
