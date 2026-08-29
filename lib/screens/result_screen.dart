import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/work_area.dart';
import '../models/work_instruction.dart';
import '../services/result_image_service.dart';
import '../theme/space_shift_colors.dart';
import '../widgets/gradient_cta_button.dart';
import '../widgets/more_options_sheet.dart';
import '../widgets/result_image_card.dart';
import 'final_confirm_screen.dart';
import 'workspace_screen.dart';

/// MASTER UI 6번 화면 — 결과 확인 및 바로 수정.
///
/// 원본과 AI 결과 이미지를 비교하고, 변경된 내용을 확인하며, 그 자리에서
/// 수정을 재요청하거나 "완료"로 최종 확인(9번 화면)으로 넘어갈 수 있다.
/// 저장하기/공유하기는 이 단계에서 크게 강조하지 않고(우측 상단 "더보기"
/// 메뉴에서만 제공), 예상견적/현장미팅 문의 등 다음 단계 액션과 함께
/// 저장/공유 버튼은 수정된 결과 확인(8번 화면)에서 제공한다.
class ResultScreen extends StatelessWidget {
  const ResultScreen({
    super.key,
    this.selectedStyle = '',
    required this.selectedImageBytes,
    this.generatedImageBytes,
    this.resultImageService = const ResultImageService(),
    this.workInstructions = const [],
    this.additionalNotes = '',
  });

  /// 선택된 스타일 이름(있는 경우에만 카드로 표시).
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

  // 기존 작업 지시(선택 영역 + 지시문)를 그대로 이어받아 공간 작업실로
  // 돌아가 수정할 수 있게 한다. 수정 후 다시 생성하면 GenerateScreen이
  // isRevision 흐름을 타 ReviseResultScreen(8번)으로 이동한다.
  void _goToReviseRequest(BuildContext context) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => WorkspaceScreen(
          selectedStyle: selectedStyle,
          selectedImageBytes: selectedImageBytes,
          initialWorkInstructions: workInstructions,
          initialAdditionalNotes: additionalNotes,
          isRevision: true,
        ),
      ),
    );
  }

  void _goToFinalConfirm(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FinalConfirmScreen(
          selectedStyle: selectedStyle,
          selectedImageBytes: selectedImageBytes,
          generatedImageBytes: generatedImageBytes,
          workInstructions: workInstructions,
          additionalNotes: additionalNotes,
        ),
      ),
    );
  }

  void _openMoreOptions(BuildContext context) {
    showMoreOptionsSheet(
      context,
      resultImageBytes: generatedImageBytes,
      resultImageService: resultImageService,
      workInstructions: workInstructions,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpaceShiftColors.background,
      appBar: AppBar(
        title: const Text('생성 결과'),
        backgroundColor: SpaceShiftColors.background,
        foregroundColor: SpaceShiftColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            onPressed: () => _openMoreOptions(context),
            icon: const Icon(Icons.more_vert_rounded),
            tooltip: '추가 옵션',
          ),
        ],
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
                    '공간 변화가 완성되었습니다',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: SpaceShiftColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '원본 사진과 AI가 만든 새로운 공간을 비교해보세요.',
                    style: TextStyle(
                      fontSize: 15,
                      color: SpaceShiftColors.textSecondary,
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
                        title: '변경 결과',
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

                  if (selectedStyle.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: SpaceShiftColors.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.style_rounded,
                            size: 28,
                            color: SpaceShiftColors.selectionAccent,
                          ),
                          const SizedBox(width: 14),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '선택한 스타일',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: SpaceShiftColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                selectedStyle,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: SpaceShiftColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                  ],

                  if (workInstructions.isNotEmpty) ...[
                    const Text(
                      '변경된 내용',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: SpaceShiftColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: SpaceShiftColors.border),
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

                  // 수정 재요청(작업실로 돌아가 다시 지시) / 완료(최종 확인으로 이동)
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
                          onPressed: () => _goToFinalConfirm(context),
                        ),
                      ),
                    ],
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
            color: SpaceShiftColors.selectionAccent,
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
                    color: SpaceShiftColors.textPrimary,
                  ),
                ),
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
          TextButton(onPressed: onEditPressed, child: const Text('수정')),
        ],
      ),
    );
  }
}
