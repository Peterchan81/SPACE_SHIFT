import 'package:flutter/material.dart';

import '../theme/space_shift_colors.dart';

/// SPACE SHIFT의 spectrum 그라데이션을 사용하는 핵심 CTA 버튼.
///
/// "공간의 변화 만들기"처럼 화면에서 가장 중요한 행동 버튼에 사용한다.
/// [onPressed]가 null이면 비활성화된 흐린 스타일로 표시된다.
class GradientCtaButton extends StatelessWidget {
  const GradientCtaButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.trailingIcon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// 글자 오른쪽에 두는 보조 아이콘(MASTER UI 1번의 "로그인 →"처럼 글자
  /// 뒤에 화살표를 붙일 때 쓴다, 2026-10-28 추가 지시). [icon](왼쪽)과는
  /// 독립적으로 쓸 수 있다.
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          gradient: SpaceShiftColors.spectrum,
          borderRadius: BorderRadius.circular(16),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: SpaceShiftColors.purple.withValues(alpha: 0.28),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onPressed,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: Colors.white, size: 22),
                    const SizedBox(width: 10),
                  ],
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  if (trailingIcon != null) ...[
                    const SizedBox(width: 10),
                    Icon(trailingIcon, color: Colors.white, size: 20),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
