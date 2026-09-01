import 'package:flutter/material.dart';

import '../../theme/space_shift_colors.dart';

/// "추가 옵션" — 마감재/색상 이후 필요한 고급 옵션. 첫 화면에 전부 펼쳐
/// 두지 않고 접기/펼치기(ExpansionTile 계열)로 구성해 화면을 압도하지
/// 않는다. 실제 값 반영(재질 스케일 슬라이더 등)은 후속 작업에서
/// 재질 엔진과 연결하고, 이번에는 진입 구조만 제공한다.
class AdditionalOptionsSection extends StatefulWidget {
  const AdditionalOptionsSection({super.key});

  @override
  State<AdditionalOptionsSection> createState() =>
      _AdditionalOptionsSectionState();
}

class _AdditionalOptionsSectionState extends State<AdditionalOptionsSection> {
  bool _expanded = false;

  static const _options = [
    (Icons.texture_rounded, '재질 스케일'),
    (Icons.wb_sunny_outlined, '반사 / 광택'),
    (Icons.grid_view_rounded, '패턴 방향'),
    (Icons.straighten_rounded, '두께 설정'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SpaceShiftColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '추가 옵션',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: SpaceShiftColors.textPrimary,
                        ),
                      ),
                    ),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: SpaceShiftColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in _options)
                    Chip(
                      avatar: Icon(
                        option.$1,
                        size: 16,
                        color: SpaceShiftColors.textSecondary,
                      ),
                      label: Text(
                        option.$2,
                        style: const TextStyle(fontSize: 12),
                      ),
                      backgroundColor: SpaceShiftColors.background,
                      side: const BorderSide(color: SpaceShiftColors.border),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
