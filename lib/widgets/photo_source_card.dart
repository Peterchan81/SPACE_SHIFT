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
    this.compact = false,
  });

  /// 카드 위쪽에 표시할 아이콘
  final IconData icon;

  /// 카드에 표시할 텍스트
  final String label;

  /// 카드를 눌렀을 때 실행할 동작.
  /// null을 전달하면 카드가 비활성화된다(예: 사진 선택창을 여는 동안).
  final VoidCallback? onTap;

  /// true이면 세로 공간이 좁은 Tablet Landscape 2단 레이아웃에 맞춰
  /// 카드 높이·아이콘·글자 크기를 줄인다. 라벨은 어떤 크기에서도 줄바꿈
  /// 없이 한 줄로 말줄임 처리해 overflow를 방지한다.
  final bool compact;

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
            // 높이를 고정하지 않고 내용만큼만 차지하도록 하여, compact일 때도
            // RenderFlex overflow 없이 자연스럽게 줄어든다.
            padding: EdgeInsets.symmetric(vertical: compact ? 10 : 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: SpaceShiftColors.border, width: 1.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: compact ? 32 : 44,
                  height: compact ? 32 : 44,
                  decoration: BoxDecoration(
                    gradient: SpaceShiftColors.spectrum,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: Colors.white,
                    size: compact ? 16 : 22,
                  ),
                ),
                SizedBox(height: compact ? 6 : 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: compact ? 13 : 15,
                      fontWeight: FontWeight.bold,
                      color: SpaceShiftColors.textPrimary,
                    ),
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
