import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/work_area.dart';
import '../models/work_instruction.dart';
import '../services/result_image_service.dart';
import '../theme/space_shift_colors.dart';
import '../widgets/action_button.dart';
import '../widgets/gradient_cta_button.dart';
import '../widgets/primary_button.dart';
import '../widgets/result_image_card.dart';
import 'estimate_request_screen.dart';
import 'site_meeting_request_screen.dart';
import 'workspace_screen.dart';

/// AI 생성 결과를 확인하는 화면.
///
/// 원본과 AI 결과 이미지를 비교하고, 선택했던 스타일을 확인하며,
/// 저장/공유와 다시 만들기 흐름을 제공한다.
class ResultScreen extends StatelessWidget {
  const ResultScreen({
    super.key,
    required this.selectedStyle,
    required this.selectedImageBytes,
    this.generatedImageBytes,
    this.resultImageService = const ResultImageService(),
    this.workInstructions = const [],
    this.additionalNotes = '',
  });

  /// StyleSelectScreen에서 사용자가 선택한 스타일 이름
  final String selectedStyle;

  /// PhotoSelectScreen에서 사용자가 선택한 원본 사진 데이터.
  /// 원본 카드에 실제 이미지로 표시한다.
  final Uint8List selectedImageBytes;

  /// AiGenerationService가 반환한, AI가 생성한 이미지 데이터.
  /// 아직 결과 이미지가 없으면(현재 더미 응답) null이며, 이 경우
  /// AI 결과 카드는 기존 Placeholder를 표시한다. 값이 채워지면
  /// ResultImageCard가 자동으로 Image.memory로 표시한다.
  final Uint8List? generatedImageBytes;

  /// 결과 이미지 저장/공유를 담당하며 테스트에서는 가짜 구현으로 교체할 수 있다.
  final ResultImageService resultImageService;

  /// WorkspaceScreen(공간 작업실)에서 완성해 이 결과를 만든 작업 지시 목록.
  /// "변경된 내용" 요약과 "수정 재요청" 흐름에 사용한다.
  final List<WorkInstruction> workInstructions;

  /// WorkspaceScreen에서 입력한 추가 작업 지시.
  final String additionalNotes;

  /// Splash, 사진/스타일 선택 화면과 동일한 밝은 아이보리 계열 배경색
  static const Color _ivoryBackground = Color(0xFFFFF8E7);

  Future<void> _handleSave(BuildContext context) async {
    final imageBytes = generatedImageBytes;
    if (imageBytes == null) {
      _showMessage(context, '저장할 결과 이미지가 없습니다.');
      return;
    }

    try {
      await resultImageService.save(imageBytes);
      if (context.mounted) _showMessage(context, '결과 이미지를 저장했습니다.');
    } catch (_) {
      if (context.mounted) _showMessage(context, '이미지를 저장하지 못했습니다. 다시 시도해주세요.');
    }
  }

  Future<void> _handleShare(BuildContext context) async {
    final imageBytes = generatedImageBytes;
    if (imageBytes == null) {
      _showMessage(context, '공유할 결과 이미지가 없습니다.');
      return;
    }

    try {
      await resultImageService.share(imageBytes);
    } catch (_) {
      if (context.mounted) _showMessage(context, '이미지를 공유하지 못했습니다. 다시 시도해주세요.');
    }
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // StyleSelectScreen은 이미 스택에 쌓여 있으므로 새로 쌓지 않고
  // 해당 화면까지 되돌아가 다시 스타일을 고를 수 있게 한다.
  // 'style_select'는 photo_select_screen.dart에서 StyleSelectScreen을
  // 열 때 지정한 라우트 이름과 동일해야 한다.
  void _goToStyleSelectAgain(BuildContext context) {
    Navigator.of(context).popUntil(ModalRoute.withName('style_select'));
  }

  // PhotoSelectScreen까지 되돌아가 처음부터 다시 시작할 수 있게 한다.
  // 'photo_select'는 splash_screen.dart에서 PhotoSelectScreen을
  // 열 때 지정한 라우트 이름과 동일해야 한다.
  void _goToPhotoSelectAgain(BuildContext context) {
    Navigator.of(context).popUntil(ModalRoute.withName('photo_select'));
  }

  void _goToEstimateRequest(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => EstimateRequestScreen(
          onSiteMeetingRequested: () => _goToSiteMeetingRequest(context),
        ),
      ),
    );
  }

  void _goToSiteMeetingRequest(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => SiteMeetingRequestScreen()),
    );
  }

  // 기존 작업 지시(선택 영역 + 지시문)를 그대로 이어받아 공간 작업실로
  // 돌아가 수정할 수 있게 한다. 수정 후 다시 생성하면 새 ResultScreen으로
  // 교체되어 이전 결과 화면 스택은 남기지 않는다.
  void _goToReviseRequest(BuildContext context) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => WorkspaceScreen(
          selectedStyle: selectedStyle,
          selectedImageBytes: selectedImageBytes,
          initialWorkInstructions: workInstructions,
          initialAdditionalNotes: additionalNotes,
        ),
      ),
    );
  }

  void _showMoreOptions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.download_rounded),
                  title: const Text('결과 저장하기'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _handleSave(context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.share_rounded),
                  title: const Text('결과 공유하기'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _handleShare(context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.request_quote_outlined),
                  title: const Text('무료 예상견적 받기'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _goToEstimateRequest(context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.handshake_outlined),
                  title: const Text('현장미팅 문의하기'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _goToSiteMeetingRequest(context);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ivoryBackground,
      appBar: AppBar(
        title: const Text('생성 결과'),
        backgroundColor: _ivoryBackground,
        foregroundColor: const Color(0xFF3E2723),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 상단 안내 문구
                  Text(
                    '새로운 공간이 완성되었어요',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF3E2723),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '원본 사진과 AI가 만든 새로운 공간을 비교해보세요.',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: const Color(0xFF5D4037),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Before / After 이미지 비교 영역.
                  // 넓은 화면에서는 가로로, 좁은 화면에서는 세로로 배치한다.
                  LayoutBuilder(
                    builder: (context, constraints) {
                      // 원본 카드는 실제 선택한 사진을 표시한다.
                      final beforeCard = ResultImageCard(
                        title: '원본',
                        placeholderIcon: Icons.home_rounded,
                        placeholderText: '원본 사진',
                        imageBytes: selectedImageBytes,
                      );
                      // generatedImageBytes가 null이면(현재 더미 응답) 기존
                      // Placeholder를, 값이 채워지면 실제 이미지를 표시한다.
                      final afterCard = ResultImageCard(
                        title: 'AI 결과',
                        placeholderIcon: Icons.auto_awesome_rounded,
                        placeholderText: '생성된 이미지',
                        imageBytes: generatedImageBytes,
                      );

                      if (constraints.maxWidth >= 480) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: beforeCard),
                            const SizedBox(width: 16),
                            Expanded(child: afterCard),
                          ],
                        );
                      }
                      return Column(
                        children: [
                          beforeCard,
                          const SizedBox(height: 16),
                          afterCard,
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),

                  // 선택한 스타일 정보 카드
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFD7CCC8),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.style_rounded,
                          size: 28,
                          color: Color(0xFF8D6E63),
                        ),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '선택한 스타일',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF8D6E63),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              selectedStyle,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF3E2723),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  if (workInstructions.isNotEmpty) ...[
                    const Text(
                      '변경된 내용',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF3E2723),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFFD7CCC8),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        children: [
                          for (final instruction in workInstructions)
                            _ChangedItemTile(
                              instruction: instruction,
                              onEditPressed: () => _goToReviseRequest(context),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // 수정 재요청(작업실로 돌아가 다시 지시) / 완료(추가 옵션)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _goToReviseRequest(context),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            foregroundColor: SpaceShiftColors.selectionAccent,
                            side: const BorderSide(
                              color: SpaceShiftColors.selectionAccent,
                              width: 1.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            '수정 재요청',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GradientCtaButton(
                          label: '완료',
                          onPressed: () => _showMoreOptions(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // 저장하기 / 공유하기 버튼.
                  // 화면 폭이 좁으면 세로로, 넓으면 가로로 배치한다.
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final saveButton = ActionButton(
                        icon: Icons.download_rounded,
                        label: '저장하기',
                        onPressed: () => _handleSave(context),
                      );
                      final shareButton = ActionButton(
                        icon: Icons.share_rounded,
                        label: '공유하기',
                        onPressed: () => _handleShare(context),
                      );

                      if (constraints.maxWidth < 340) {
                        return Column(
                          children: [
                            saveButton,
                            const SizedBox(height: 12),
                            shareButton,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: saveButton),
                          const SizedBox(width: 12),
                          Expanded(child: shareButton),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),

                  PrimaryButton(
                    label: '무료 예상견적 받기',
                    onPressed: () => _goToEstimateRequest(context),
                  ),
                  const SizedBox(height: 12),

                  PrimaryButton(
                    label: '현장미팅 문의하기',
                    onPressed: () => _goToSiteMeetingRequest(context),
                  ),
                  const SizedBox(height: 12),

                  // 다른 스타일로 다시 만들기
                  PrimaryButton(
                    label: '다른 스타일로 다시 만들기',
                    onPressed: () => _goToStyleSelectAgain(context),
                  ),
                  const SizedBox(height: 12),

                  // 처음부터 다시 시작 (사진 다시 선택)
                  Center(
                    child: TextButton(
                      onPressed: () => _goToPhotoSelectAgain(context),
                      child: const Text(
                        '다른 사진 선택하기',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF8D6E63),
                        ),
                      ),
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

/// "변경된 내용" 목록에서 작업 지시 하나를 요약해서 보여주는 줄.
/// 오른쪽의 "수정"을 누르면 해당 작업을 이어서 고칠 수 있도록 공간
/// 작업실로 돌아간다.
class _ChangedItemTile extends StatelessWidget {
  const _ChangedItemTile({
    required this.instruction,
    required this.onEditPressed,
  });

  final WorkInstruction instruction;
  final VoidCallback onEditPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(
            instruction.area.icon,
            size: 20,
            color: const Color(0xFF8D6E63),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  instruction.area.label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF3E2723),
                  ),
                ),
                Text(
                  instruction.instructionText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF5D4037)),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onEditPressed, child: const Text('수정')),
        ],
      ),
    );
  }
}
