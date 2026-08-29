import 'package:flutter/material.dart';

import '../theme/space_shift_colors.dart';

/// 사진을 가져올 방법(카메라 촬영 / 갤러리 선택)을 고르는 버튼 카드.
///
/// SS_V1_UI_MASTER.png 2번 화면 기준, 아이콘이 위에 오고 라벨이 아래에 오는
/// 정사각형에 가까운 카드 형태이며, 카메라/갤러리 두 카드를 가로로 나란히
/// 배치해 사용한다.
class PhotoSourceCard extends StatelessWidget {
  const PhotoSourceCard({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  /// 카드 위쪽에 표시할 아이콘
  final IconData icon;

  /// 카드에 표시할 텍스트
  final String label;

  /// 카드를 눌렀을 때 실행할 동작.
  /// null을 전달하면 카드가 비활성화된다(예: 사진 선택창을 여는 동안).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            height: 116,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: SpaceShiftColors.border, width: 1.5),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: SpaceShiftColors.spectrum,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: Colors.white, size: 24),
                ),
                const SizedBox(height: 10),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: SpaceShiftColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
