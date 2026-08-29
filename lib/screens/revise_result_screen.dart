import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/work_instruction.dart';
import '../services/result_image_service.dart';
import '../theme/space_shift_colors.dart';
import '../widgets/action_button.dart';
import '../widgets/more_options_sheet.dart';
import '../widgets/primary_button.dart';
import '../widgets/result_image_card.dart';
import 'estimate_request_screen.dart';
import 'site_meeting_request_screen.dart';
import 'workspace_screen.dart';

/// MASTER UI 8번 화면 — 수정된 결과 확인.
///
/// GenerateScreen(7번, 수정 요청 처리 중)이 성공적으로 끝나면 도착하는
/// 화면으로, 수정된 공간을 보여주고 공유하기/저장하기/추가로 수정하기와
/// 무료 예상견적/현장 미팅 문의로 이어지는 다음 행동을 안내한다. "추가
/// 옵션"(10번 화면, 고화질 다운로드 등)은 이 화면의 더보기 메뉴에서 진입한다.
class ReviseResultScreen extends StatelessWidget {
  const ReviseResultScreen({
    super.key,
    required this.selectedImageBytes,
    this.generatedImageBytes,
    this.resultImageService = const ResultImageService(),
    this.workInstructions = const [],
    this.selectedStyle = '',
    this.additionalNotes = '',
  });

  /// 원본 공간 사진. "추가로 수정하기"에서 공간 작업실로 되돌아갈 때도 사용한다.
  final Uint8List selectedImageBytes;

  /// 수정 반영 후 AI가 새로 생성한 이미지.
  final Uint8List? generatedImageBytes;

  /// 저장/공유를 담당하며 테스트에서는 가짜 구현으로 교체할 수 있다.
  final ResultImageService resultImageService;

  /// 이 결과를 만든 작업 지시 목록. "추가로 수정하기"에서 공간 작업실로
  /// 이어받고, "다른 사진으로 새로운 공간 만들기"를 누르면 새 프로젝트로
  /// 초기화되므로 그 경우에는 참고 정보로만 사용한다.
  final List<WorkInstruction> workInstructions;

  /// 선택된 스타일 이름(있는 경우). "추가로 수정하기"에서 공간 작업실로 이어받는다.
  final String selectedStyle;

  /// 부위에 묶이지 않는 추가 작업 지시. "추가로 수정하기"에서 이어받는다.
  final String additionalNotes;

  Future<void> _handleSave(BuildContext context) async {
    final bytes = generatedImageBytes;
    if (bytes == null) {
      _showMessage(context, '저장할 결과 이미지가 없습니다.');
      return;
    }
    try {
      await resultImageService.save(bytes);
      if (context.mounted) _showMessage(context, '결과 이미지를 저장했습니다.');
    } catch (_) {
      if (context.mounted) _showMessage(context, '이미지를 저장하지 못했습니다. 다시 시도해주세요.');
    }
  }

  Future<void> _handleShare(BuildContext context) async {
    final bytes = generatedImageBytes;
    if (bytes == null) {
      _showMessage(context, '공유할 결과 이미지가 없습니다.');
      return;
    }
    try {
      await resultImageService.share(bytes);
    } catch (_) {
      if (context.mounted) _showMessage(context, '이미지를 공유하지 못했습니다. 다시 시도해주세요.');
    }
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // 지금까지의 작업 지시를 그대로 이어받아 공간 작업실로 돌아가 추가로
  // 수정할 수 있게 한다. 다시 생성하면 GenerateScreen이 isRevision 흐름을
  // 타 이 화면으로 다시 돌아온다.
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

  void _goToNewProject(BuildContext context) {
    Navigator.of(context).popUntil(ModalRoute.withName('photo_select'));
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
        title: const Text('수정된 결과 확인'),
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
            constraints: const BoxConstraints(maxWidth: 900),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '수정된 공간을 확인해주세요',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: SpaceShiftColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ResultImageCard(
                    title: '수정된 공간',
                    placeholderIcon: Icons.auto_awesome_rounded,
                    placeholderText: '생성된 이미지',
                    imageBytes: generatedImageBytes,
                  ),
                  const SizedBox(height: 20),
                  // 공유하기 / 저장하기 / 추가로 수정하기.
                  // Galaxy Tab 가로 화면처럼 넓은 화면에서는 3개를 한 줄에,
                  // 좁은 화면(휴대폰)에서는 세로로 쌓아 보여준다.
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final shareButton = ActionButton(
                        icon: Icons.share_rounded,
                        label: '공유하기',
                        onPressed: () => _handleShare(context),
                      );
                      final saveButton = ActionButton(
                        icon: Icons.download_rounded,
                        label: '저장하기',
                        onPressed: () => _handleSave(context),
                      );
                      final reviseButton = ActionButton(
                        icon: Icons.edit_rounded,
                        label: '추가로 수정하기',
                        onPressed: () => _goToAdditionalRevision(context),
                      );

                      if (constraints.maxWidth < 560) {
                        return Column(
                          children: [
                            shareButton,
                            const SizedBox(height: 12),
                            saveButton,
                            const SizedBox(height: 12),
                            reviseButton,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: shareButton),
                          const SizedBox(width: 12),
                          Expanded(child: saveButton),
                          const SizedBox(width: 12),
                          Expanded(child: reviseButton),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 28),
                  _ActionCard(
                    icon: Icons.request_quote_outlined,
                    color: SpaceShiftColors.blue,
                    title: '무료 예상견적 받기',
                    subtitle: '공간 변화에 따른 예상 비용을 무료로 확인해보세요.',
                    onTap: () => _goToEstimateRequest(context),
                  ),
                  const SizedBox(height: 14),
                  _ActionCard(
                    icon: Icons.handshake_outlined,
                    color: SpaceShiftColors.purple,
                    title: '현장 미팅 문의하기',
                    subtitle: '전문가와 상담하고 맞춤 인테리어를 진행해보세요.',
                    onTap: () => _goToSiteMeetingRequest(context),
                  ),
                  const SizedBox(height: 28),
                  PrimaryButton(
                    label: '다른 사진으로 새로운 공간 만들기',
                    onPressed: () => _goToNewProject(context),
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

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: SpaceShiftColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: SpaceShiftColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: SpaceShiftColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
