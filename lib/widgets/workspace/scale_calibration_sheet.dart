import 'package:flutter/material.dart';

import '../../theme/space_shift_colors.dart';

/// "기준 치수 설정" 바텀시트 — 사용자가 도면 위에서 이미 두 점을 찍은
/// 뒤, 그 구간의 실제 길이(mm)를 입력받는다.
///
/// 픽셀 거리로부터 mm를 자동으로 추측하지 않는다(WO 9번) — 이 값은
/// 오직 사용자가 직접 입력한 숫자에서만 나온다. 취소하거나 빈 값이면
/// null을 반환해 축척을 적용하지 않는다.
Future<double?> showScaleReferenceLengthSheet(BuildContext context) {
  final controller = TextEditingController();
  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    backgroundColor: SpaceShiftColors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      return Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '기준 치수 입력',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: SpaceShiftColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '방금 도면 위에서 선택한 두 점 사이의 실제 길이를 입력해주세요. '
              '이후 전체 도면의 실측값 계산에 사용됩니다.',
              style: TextStyle(
                fontSize: 13,
                color: SpaceShiftColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(),
              decoration: const InputDecoration(
                hintText: '예: 3600',
                suffixText: 'mm',
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      foregroundColor: SpaceShiftColors.textPrimary,
                      side: const BorderSide(color: SpaceShiftColors.border),
                    ),
                    child: const Text('취소'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      final value = double.tryParse(controller.text.trim());
                      Navigator.of(
                        sheetContext,
                      ).pop(value != null && value > 0 ? value : null);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: SpaceShiftColors.textPrimary,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: const Text('축척 적용'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
