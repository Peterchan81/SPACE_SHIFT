import 'package:flutter/material.dart';

import '../../theme/space_shift_colors.dart';

const List<double> ceilingHeightPresetsMm = [2300, 2400, 2500, 2700];

/// "천장고 입력" 바텀시트 — 프리셋(2300/2400/2500/2700mm) 또는 직접
/// 입력만 받는다. 이미지에서 자동으로 추정하지 않는다(WO 10번).
Future<double?> showCeilingHeightSheet(
  BuildContext context, {
  double? initialMm,
}) {
  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    backgroundColor: SpaceShiftColors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => _CeilingHeightSheetBody(initialMm: initialMm),
  );
}

class _CeilingHeightSheetBody extends StatefulWidget {
  const _CeilingHeightSheetBody({this.initialMm});

  final double? initialMm;

  @override
  State<_CeilingHeightSheetBody> createState() =>
      _CeilingHeightSheetBodyState();
}

class _CeilingHeightSheetBodyState extends State<_CeilingHeightSheetBody> {
  double? _selectedPreset;
  late final TextEditingController _customController;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialMm;
    _selectedPreset =
        (initial != null && ceilingHeightPresetsMm.contains(initial))
        ? initial
        : null;
    _customController = TextEditingController(
      text: (initial != null && _selectedPreset == null)
          ? initial.toStringAsFixed(0)
          : '',
    );
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  double? get _resolvedValue {
    if (_selectedPreset != null) return _selectedPreset;
    return double.tryParse(_customController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '천장고 입력',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: SpaceShiftColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '3D 공간 생성 전 기본 천장고를 입력해주세요. 자동으로 추정하지 않습니다.',
            style: TextStyle(
              fontSize: 13,
              color: SpaceShiftColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in ceilingHeightPresetsMm)
                ChoiceChip(
                  label: Text('${preset.toStringAsFixed(0)}mm'),
                  selected: _selectedPreset == preset,
                  onSelected: (_) => setState(() {
                    _selectedPreset = preset;
                    _customController.clear();
                  }),
                  selectedColor: SpaceShiftColors.textPrimary,
                  labelStyle: TextStyle(
                    color: _selectedPreset == preset
                        ? Colors.white
                        : SpaceShiftColors.textPrimary,
                  ),
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: SpaceShiftColors.border),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _customController,
            keyboardType: const TextInputType.numberWithOptions(),
            decoration: const InputDecoration(
              hintText: '직접 입력',
              suffixText: 'mm',
            ),
            onChanged: (_) => setState(() => _selectedPreset = null),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor: SpaceShiftColors.textPrimary,
                    side: const BorderSide(color: SpaceShiftColors.border),
                  ),
                  child: const Text('취소'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    final value = _resolvedValue;
                    Navigator.of(
                      context,
                    ).pop(value != null && value > 0 ? value : null);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: SpaceShiftColors.textPrimary,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text('적용'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
