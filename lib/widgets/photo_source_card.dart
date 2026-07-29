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
  });

  /// 버튼 왼쪽에 표시할 아이콘
  final IconData icon;

  /// 버튼에 표시할 텍스트
  final String label;

  /// 버튼을 눌렀을 때 실행할 동작.
  /// null을 전달하면 버튼이 비활성화된다(예: 사진 선택창을 여는 동안).
  final VoidCallback? onTap;

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
            height: 72,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFD7CCC8), width: 1.5),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 30,
                  color: const Color(0xFF8D6E63),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF3E2723),
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFFBCAAA4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
