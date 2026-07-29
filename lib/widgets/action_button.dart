import 'package:flutter/material.dart';

/// 결과 화면 하단의 보조 액션 버튼(저장하기, 공유하기 등)에 사용하는 위젯.
///
/// PrimaryButton보다 시각적으로 약하게 강조되는 아웃라인 스타일을 사용해
/// 결과 이미지보다 튀지 않도록 한다.
class ActionButton extends StatelessWidget {
  const ActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  /// 버튼 왼쪽에 표시할 아이콘
  final IconData icon;

  /// 버튼에 표시할 텍스트
  final String label;

  /// 버튼을 눌렀을 때 실행할 동작
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 22),
        label: Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF3E2723),
          side: const BorderSide(color: Color(0xFF8D6E63), width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}
