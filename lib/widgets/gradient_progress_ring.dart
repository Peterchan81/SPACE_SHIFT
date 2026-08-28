import 'package:flutter/material.dart';

import '../theme/space_shift_colors.dart';

/// MASTER UI 5/7번 화면(AI 생성/재생성 진행률)의 spectrum gradient 원형
/// 진행률 표시. 중앙에 퍼센트 숫자를 함께 보여준다.
class GradientProgressRing extends StatelessWidget {
  const GradientProgressRing({
    super.key,
    required this.progress,
    this.size = 160,
  });

  /// 0.0 ~ 1.0 사이의 진행률.
  final double progress;

  final double size;

  @override
  Widget build(BuildContext context) {
    final clamped = progress.clamp(0.0, 1.0);
    final strokeWidth = size * 0.09;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: 1,
              strokeWidth: strokeWidth,
              color: SpaceShiftColors.border,
            ),
          ),
          SizedBox.expand(
            child: ShaderMask(
              shaderCallback: (rect) =>
                  SpaceShiftColors.spectrum.createShader(rect),
              child: CircularProgressIndicator(
                value: clamped,
                strokeWidth: strokeWidth,
                strokeCap: StrokeCap.round,
                backgroundColor: Colors.transparent,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          ),
          Text(
            '${(clamped * 100).round()}%',
            style: TextStyle(
              fontSize: size * 0.2,
              fontWeight: FontWeight.bold,
              color: SpaceShiftColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
