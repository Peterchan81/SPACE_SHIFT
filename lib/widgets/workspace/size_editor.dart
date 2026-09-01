import 'package:flutter/material.dart';

import '../../theme/space_shift_colors.dart';

/// "사이즈" 카드 — 선택 대상에 따라 필드가 달라질 수 있는 adaptive 구조.
///
/// 값이 null이면 "미설정"으로 정직하게 보여준다 — 평면도 실제 분석으로
/// 만들어진 항목은 아직 실제 축척(scale)을 모르기 때문에 mm 값을 임의로
/// 추정해 채우지 않는다(WO 17번). 사용자가 직접 값을 입력하면 그 값을
/// 그대로 반영한다.
class SizeEditor extends StatelessWidget {
  const SizeEditor({
    super.key,
    required this.heightMm,
    required this.widthMm,
    required this.thicknessMm,
    required this.onHeightChanged,
    required this.onWidthChanged,
    required this.onThicknessChanged,
  });

  final double? heightMm;
  final double? widthMm;
  final double? thicknessMm;
  final ValueChanged<double> onHeightChanged;
  final ValueChanged<double> onWidthChanged;
  final ValueChanged<double> onThicknessChanged;

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '사이즈',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: SpaceShiftColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SizeField(
                      label: '높이',
                      value: heightMm,
                      onChanged: onHeightChanged,
                    ),
                    const SizedBox(height: 8),
                    _SizeField(
                      label: '너비',
                      value: widthMm,
                      onChanged: onWidthChanged,
                    ),
                    const SizedBox(height: 8),
                    _SizeField(
                      label: '두께',
                      value: thicknessMm,
                      onChanged: onThicknessChanged,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              _SizeDiagram(
                heightMm: heightMm,
                widthMm: widthMm,
                thicknessMm: thicknessMm,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SizeField extends StatefulWidget {
  const _SizeField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double? value;
  final ValueChanged<double> onChanged;

  @override
  State<_SizeField> createState() => _SizeFieldState();
}

class _SizeFieldState extends State<_SizeField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value?.toStringAsFixed(0) ?? '',
  );

  @override
  void didUpdateWidget(covariant _SizeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final text = widget.value?.toStringAsFixed(0) ?? '';
    if (_controller.text != text) {
      _controller.text = text;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 32,
          child: Text(
            widget.label,
            style: const TextStyle(
              fontSize: 13,
              color: SpaceShiftColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _controller,
            keyboardType: const TextInputType.numberWithOptions(),
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 14),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
              hintText: '미설정',
              suffixText: 'mm',
            ),
            onChanged: (text) {
              final parsed = double.tryParse(text);
              if (parsed != null) widget.onChanged(parsed);
            },
          ),
        ),
      ],
    );
  }
}

/// 높이/너비 비율을 시각적으로 보여주는 아주 단순한 도식.
class _SizeDiagram extends StatelessWidget {
  const _SizeDiagram({
    required this.heightMm,
    required this.widthMm,
    required this.thicknessMm,
  });

  final double? heightMm;
  final double? widthMm;
  final double? thicknessMm;

  /// 도식 박스 한 변의 최대 길이(px). 라벨 텍스트 폭까지 감안해 Row 안에서
  /// 절대 넘치지 않도록, AspectRatio 대신 두 변 모두 이 값 이하로 직접
  /// 계산해서 그린다.
  static const double _maxBoxDimension = 42;

  @override
  Widget build(BuildContext context) {
    final height = heightMm;
    final width = widthMm;
    final thickness = thicknessMm;
    final ratio = (width == null || width <= 0 || height == null)
        ? 1.0
        : (height / width).clamp(0.4, 2.2);
    final boxWidth = ratio >= 1 ? _maxBoxDimension / ratio : _maxBoxDimension;
    final boxHeight = ratio >= 1 ? _maxBoxDimension : _maxBoxDimension * ratio;

    return SizedBox(
      width: 96,
      height: 96,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  height?.toStringAsFixed(0) ?? '-',
                  style: const TextStyle(
                    fontSize: 10,
                    color: SpaceShiftColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  width: boxWidth,
                  height: boxHeight,
                  decoration: BoxDecoration(
                    color: SpaceShiftColors.background,
                    border: Border.all(color: SpaceShiftColors.border),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${width?.toStringAsFixed(0) ?? '-'} × ${thickness?.toStringAsFixed(0) ?? '-'}',
            style: const TextStyle(
              fontSize: 10,
              color: SpaceShiftColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
