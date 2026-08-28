import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/work_area.dart';
import '../models/work_instruction.dart';
import '../services/result_image_service.dart';
import '../theme/space_shift_colors.dart';

/// MASTER UI 10번 화면 "추가 옵션"을 바텀시트로 보여준다.
///
/// 결과 확인(6번) / 수정된 결과 확인(8번) 화면 양쪽에서 공용으로 사용한다.
/// 저장하기/공유하기는 실제 [ResultImageService]로 동작하고, 아직 백엔드가
/// 없는 고화질 다운로드/인쇄/프로젝트 정보는 안전한 안내만 표시한다.
Future<void> showMoreOptionsSheet(
  BuildContext context, {
  required Uint8List? resultImageBytes,
  required ResultImageService resultImageService,
  List<WorkInstruction> workInstructions = const [],
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: SpaceShiftColors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => _MoreOptionsSheet(
      resultImageBytes: resultImageBytes,
      resultImageService: resultImageService,
      workInstructions: workInstructions,
    ),
  );
}

class _MoreOptionsSheet extends StatelessWidget {
  const _MoreOptionsSheet({
    required this.resultImageBytes,
    required this.resultImageService,
    required this.workInstructions,
  });

  final Uint8List? resultImageBytes;
  final ResultImageService resultImageService;
  final List<WorkInstruction> workInstructions;

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleSave(BuildContext context) async {
    final bytes = resultImageBytes;
    Navigator.of(context).pop();
    if (bytes == null) return;
    try {
      await resultImageService.save(bytes);
      if (context.mounted) _showMessage(context, '결과 이미지를 저장했습니다.');
    } catch (_) {
      if (context.mounted) _showMessage(context, '이미지를 저장하지 못했습니다. 다시 시도해주세요.');
    }
  }

  Future<void> _handleShare(BuildContext context) async {
    final bytes = resultImageBytes;
    Navigator.of(context).pop();
    if (bytes == null) return;
    try {
      await resultImageService.share(bytes);
    } catch (_) {
      if (context.mounted) _showMessage(context, '이미지를 공유하지 못했습니다. 다시 시도해주세요.');
    }
  }

  void _showComingSoon(BuildContext context, String feature) {
    Navigator.of(context).pop();
    _showMessage(context, '$feature 기능은 준비 중입니다.');
  }

  void _showProjectInfo(BuildContext context) {
    Navigator.of(context).pop();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('프로젝트 정보'),
        content: Text(
          workInstructions.isEmpty
              ? '등록된 작업 지시가 없습니다.'
              : '총 ${workInstructions.length}개 부위에 작업 지시가 적용되었습니다.\n'
                    '(${workInstructions.map((e) => e.area.label).join(', ')})',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: SpaceShiftColors.border,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '추가 옵션',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: SpaceShiftColors.textPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            _OptionTile(
              icon: Icons.save_alt_rounded,
              title: '결과 저장하기',
              subtitle: '내 프로젝트에 저장',
              onTap: () => _handleSave(context),
            ),
            _OptionTile(
              icon: Icons.ios_share_rounded,
              title: '결과 공유하기',
              subtitle: '링크로 결과 공유',
              onTap: () => _handleShare(context),
            ),
            _OptionTile(
              icon: Icons.high_quality_rounded,
              title: '고화질 다운로드',
              subtitle: '고해상도로 저장 (유료)',
              onTap: () => _showComingSoon(context, '고화질 다운로드'),
            ),
            _OptionTile(
              icon: Icons.print_rounded,
              title: '인쇄하기',
              subtitle: 'A4 / A3 인쇄 파일 생성',
              onTap: () => _showComingSoon(context, '인쇄하기'),
            ),
            _OptionTile(
              icon: Icons.info_outline_rounded,
              title: '프로젝트 정보',
              subtitle: '작업 내용 및 메모 관리',
              onTap: () => _showProjectInfo(context),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    foregroundColor: SpaceShiftColors.textSecondary,
                    side: const BorderSide(color: SpaceShiftColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    '닫기',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: SpaceShiftColors.selectionAccent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: SpaceShiftColors.selectionAccent, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.bold,
          color: SpaceShiftColors.textPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: SpaceShiftColors.textSecondary),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: SpaceShiftColors.textSecondary,
      ),
    );
  }
}
