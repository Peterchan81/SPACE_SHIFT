import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/work_area.dart';
import '../models/work_instruction.dart';
import '../theme/space_shift_colors.dart';
import '../widgets/gradient_cta_button.dart';
import '../widgets/result_image_card.dart';
import 'workspace_screen.dart';

/// MASTER UI 9번 화면 — 최종 확인(생성 전 최종 체크).
///
/// ResultScreen(6번)에서 "완료"를 눌렀을 때 도착하는 마지막 확인 단계로,
/// 최종 결과와 변경 요약을 다시 보여주고 추가 수정 또는 최종 확정 중 하나를
/// 고르게 한다.
class FinalConfirmScreen extends StatelessWidget {
  const FinalConfirmScreen({
    super.key,
    required this.selectedStyle,
    required this.selectedImageBytes,
    this.generatedImageBytes,
    this.workInstructions = const [],
    this.additionalNotes = '',
  });

  final String selectedStyle;
  final Uint8List selectedImageBytes;
  final Uint8List? generatedImageBytes;
  final List<WorkInstruction> workInstructions;
  final String additionalNotes;

  void _goToAdditionalRevision(BuildContext context) {
    Navigator.of(context).push(
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

  Future<void> _confirmFinal(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('공간 변화가 확정되었습니다'),
        content: const Text('결과가 저장되었습니다. 새로운 공간을 또 만들어보세요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    Navigator.of(context).popUntil(ModalRoute.withName('photo_select'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpaceShiftColors.background,
      appBar: AppBar(
        title: const Text('최종 확인'),
        backgroundColor: SpaceShiftColors.background,
        foregroundColor: SpaceShiftColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '최종 결과를 확인해주세요',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: SpaceShiftColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '이대로 결과를 저장하거나, 추가 수정을 요청할 수 있어요.',
                    style: TextStyle(
                      fontSize: 14,
                      color: SpaceShiftColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ResultImageCard(
                    title: '최종 결과',
                    placeholderIcon: Icons.auto_awesome_rounded,
                    placeholderText: '생성된 이미지',
                    imageBytes: generatedImageBytes,
                  ),
                  if (workInstructions.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const Text(
                      '변경 요약',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: SpaceShiftColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: SpaceShiftColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final instruction in workInstructions)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    instruction.area.icon,
                                    size: 18,
                                    color: SpaceShiftColors.selectionAccent,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: RichText(
                                      text: TextSpan(
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: SpaceShiftColors.textPrimary,
                                          height: 1.4,
                                        ),
                                        children: [
                                          TextSpan(
                                            text: '${instruction.area.label}: ',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          TextSpan(
                                            text: instruction.instructionText,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _goToAdditionalRevision(context),
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
                            '추가 수정하기',
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
                          label: '이대로 확정하기',
                          onPressed: () => _confirmFinal(context),
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
