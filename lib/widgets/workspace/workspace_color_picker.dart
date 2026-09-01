import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import '../../theme/space_shift_colors.dart';

/// "색상 선택" 카드 — 2D color field + hue spectrum + HEX + RGB를 제공한다.
///
/// Photoshop류 프로그램 수준의 정밀한 컬러 선택을 새로 구현하지 않고,
/// Flutter 생태계에서 가장 널리 쓰이는 [ColorPicker](flutter_colorpicker
/// 패키지)를 그대로 재사용한다 — 순수 Dart라 플랫폼별 추가 설정이 없고,
/// HSV 2D 영역/hue 슬라이더/HEX·RGB 입력을 기본으로 제공한다.
///
/// 색상 변경은 AI 재생성 없이 [onColorChanged]로 즉시 반영되어 중앙
/// workspace/작업 목록에 실시간 preview된다.
class WorkspaceColorPicker extends StatelessWidget {
  const WorkspaceColorPicker({
    super.key,
    required this.color,
    required this.onColorChanged,
  });

  final Color color;
  final ValueChanged<Color> onColorChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SpaceShiftColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '색상 선택',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: SpaceShiftColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          ColorPicker(
            pickerColor: color,
            onColorChanged: onColorChanged,
            enableAlpha: false,
            displayThumbColor: true,
            paletteType: PaletteType.hsv,
            pickerAreaHeightPercent: 0.55,
            labelTypes: const [ColorLabelType.hex, ColorLabelType.rgb],
            pickerAreaBorderRadius: BorderRadius.circular(12),
          ),
        ],
      ),
    );
  }
}
