import 'package:flutter/material.dart';

/// 사진을 가져올 방법(카메라 촬영 / 갤러리 선택)을 고르는 큰 버튼 카드.
///
/// 아이콘 + 텍스트로 구성되어 있어 무엇을 하는 버튼인지 한눈에 파악할 수 있다.
/// 카메라, 갤러리 두 곳 모두에서 재사용하며,
/// 추후 다른 사진 소스가 추가되어도 동일한 형태로 확장할 수 있다.
class PhotoSourceCard extends StatelessWidget {
  const PhotoSourceCard({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.compact = false,
  });

  /// 버튼 왼쪽에 표시할 아이콘
  final IconData icon;

  /// 버튼에 표시할 텍스트
  final String label;

  /// 버튼을 눌렀을 때 실행할 동작.
  /// null을 전달하면 버튼이 비활성화된다(예: 사진 선택창을 여는 동안).
  final VoidCallback? onTap;

  /// true이면 좁은 폭(Tablet Landscape에서 카메라/갤러리 버튼을 나란히 배치할 때)에
  /// 맞춰 여백·아이콘·글자 크기를 줄이고 화살표 아이콘을 생략한다.
  /// 어떤 폭에서도 줄바꿈 없이 한 줄로 표시되도록 말줄임 처리한다.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: compact ? 64 : 72,
            padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFD7CCC8), width: 1.5),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: compact ? 24 : 30,
                  color: const Color(0xFF8D6E63),
                ),
                SizedBox(width: compact ? 10 : 16),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? 16 : 18,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF3E2723),
                    ),
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFFBCAAA4),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
