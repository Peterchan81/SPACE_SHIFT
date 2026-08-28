import 'package:flutter/material.dart';

import '../theme/space_shift_colors.dart';

/// 앱 전반에서 재사용하는 큰 버튼 위젯.
///
/// 40대 이상 사용자도 쉽게 누를 수 있도록 버튼 높이와 글자 크기를 크게 유지한다.
/// 추후 다른 화면에서도 동일한 스타일의 버튼이 필요할 때 재사용한다.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  /// 버튼에 표시할 텍스트
  final String label;

  /// 버튼을 눌렀을 때 실행할 동작.
  /// null을 전달하면 버튼이 비활성화된다(예: 사진을 아직 선택하지 않은 상태).
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: SpaceShiftColors.selectionAccent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 2,
          // 비활성화 상태에서도 글자가 잘 읽히도록 충분한 명암 대비를 유지한다.
          disabledBackgroundColor: SpaceShiftColors.border,
          disabledForegroundColor: SpaceShiftColors.textSecondary,
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
