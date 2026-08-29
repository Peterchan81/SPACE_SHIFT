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

  /// "선택 부위 변경 지시" 질문 + 텍스트 입력 영역.
  /// 좁은 화면/넓은 화면 레이아웃 양쪽에서 공용으로 사용한다.
  Widget _buildInstructionField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
      ],
    );
  }

  /// "참고 이미지" 라벨 + 썸네일 선택 영역.
  Widget _buildReferenceImages() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
      ],
    );
  }

  Widget _buildAddInstructionButton() {
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: _addCurrentAsInstruction,
        icon: const Icon(Icons.add_rounded),
        label: const Text('다른 부분 작업 추가'),
        style: OutlinedButton.styleFrom(
          foregroundColor: SpaceShiftColors.selectionAccent,
          side: const BorderSide(color: SpaceShiftColors.selectionAccent),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildWorkList() {
    if (_instructions.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
    );
  }

  Widget _buildAdditionalNotesField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
      ],
    );
  }

  Widget _buildUsageLabel() {
    return Center(
      child: Text(
        '오늘의 무료 생성 ${UsagePolicyService.instance.usedToday}/'
        '${UsagePolicyService.freeDailyLimit}회 사용',
        style: const TextStyle(fontSize: 13, color: SpaceShiftColors.textSecondary),
      ),
    );
  }

  /// 휴대폰 세로 레이아웃(MASTER 기준): 사진+메뉴 → 지시 입력 → 참고 이미지
  /// → 작업 목록 → 기타 지시 → CTA 순서로 위에서 아래로 이어지는 단일
  /// 스크롤 화면.
  Widget _buildNarrowLayout() {
    return SingleChildScrollView(
      physics: _isSelectingRegion
          ? const NeverScrollableScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 320,
            child: RegionSelector(
              imageBytes: widget.selectedImageBytes,
              selection: _currentSelection,
              onChanged: (selection) =>
                  setState(() => _currentSelection = selection),
              onDragActiveChanged: (active) =>
                  setState(() => _isSelectingRegion = active),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 180,
            child: WorkAreaPanel(
              selected: _selectedArea,
              onSelected: (area) => setState(() => _selectedArea = area),
            ),
          ),
          const SizedBox(height: 16),
          _SelectionInfoBar(selection: _currentSelection),
          const SizedBox(height: 20),
          _buildInstructionField(),
          const SizedBox(height: 14),
          _buildReferenceImages(),
          const SizedBox(height: 12),
          _buildAddInstructionButton(),
          if (_instructions.isNotEmpty) ...[
            const SizedBox(height: 20),
            _buildWorkList(),
          ],
          const SizedBox(height: 20),
          _buildAdditionalNotesField(),
          const SizedBox(height: 16),
          _buildUsageLabel(),
          const SizedBox(height: 10),
          GradientCtaButton(label: '공간의 변화 만들기', onPressed: _handleSubmit),
        ],
      ),
    );
  }

  /// Galaxy Tab 가로 레이아웃: 작업 사진을 화면의 가장 중요한 좌측 영역으로
  /// 고정하고, 작업 부위 메뉴 + 지시 입력 + 참고 이미지 + 작업 목록을 우측
  /// 컬럼에 모아 한 화면 안에서 함께 확인할 수 있게 한다. 하단 CTA는 항상
  /// 화면 아래에 고정해, 콘텐츠가 늘어나도 스크롤 없이 바로 누를 수 있다.
  Widget _buildWideLayout() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: RegionSelector(
                          imageBytes: widget.selectedImageBytes,
                          selection: _currentSelection,
                          onChanged: (selection) =>
                              setState(() => _currentSelection = selection),
                          onDragActiveChanged: (active) =>
                              setState(() => _isSelectingRegion = active),
                        ),
                      ),
                      // 선택 영역 위치/크기(또는 아직 선택 전이라는 안내)는
                      // 화면을 크게 차지하지 않도록 사진 위에 떠 있는 작은
                      // 정보 칩으로만 보여준다.
                      Positioned(
                        left: 10,
                        top: 10,
                        right: 10,
                        child: _CompactSelectionChip(
                          selection: _currentSelection,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 360,
                  child: SingleChildScrollView(
                    physics: _isSelectingRegion
                        ? const NeverScrollableScrollPhysics()
                        : const AlwaysScrollableScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 230,
                          child: WorkAreaPanel(
                            selected: _selectedArea,
                            onSelected: (area) =>
                                setState(() => _selectedArea = area),
                          ),
                        ),
                        const SizedBox(height: 14),
                        _buildInstructionField(),
                        const SizedBox(height: 12),
                        _buildReferenceImages(),
                        const SizedBox(height: 10),
                        _buildAddInstructionButton(),
                        if (_instructions.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          _buildWorkList(),
                        ],
                        const SizedBox(height: 14),
                        _buildAdditionalNotesField(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildUsageLabel(),
          const SizedBox(height: 10),
          GradientCtaButton(label: '공간의 변화 만들기', onPressed: _handleSubmit),
        ],
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
            constraints: const BoxConstraints(maxWidth: 1400),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 800;
                return isWide ? _buildWideLayout() : _buildNarrowLayout();
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Galaxy Tab 가로 레이아웃에서 선택 영역의 위치/크기(또는 아직 선택하지
/// 않았다는 안내)를 사진 위에 작게 떠 있는 칩 형태로 보여준다. 별도 줄을
/// 차지하던 기존 정보 바([_SelectionInfoBar])를 좁은 화면(휴대폰)에서만
/// 계속 사용하고, 넓은 화면에서는 이 칩으로 대체한다.
class _CompactSelectionChip extends StatelessWidget {
  const _CompactSelectionChip({required this.selection});

  /// 아직 선택 영역이 없으면 null이며, 이때는 안내 문구를 대신 보여준다.
  final RegionSelection? selection;

  @override
  Widget build(BuildContext context) {
    final selection = this.selection;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xE6FFFFFF),
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.crop_rounded, size: 14, color: SpaceShiftColors.selectionAccent),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              selection == null
                  ? '사진 위에서 손가락(또는 마우스)으로 드래그해 변경하고 싶은 부분을 선택해주세요.'
                  : '${selection.xPercent}%, ${selection.yPercent}% · '
                        '${selection.widthPercent}%×${selection.heightPercent}%',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: SpaceShiftColors.textPrimary,
              ),
            ),
          ),
        ],
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
