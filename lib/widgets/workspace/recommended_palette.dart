import 'package:flutter/material.dart';

import '../../theme/space_shift_colors.dart';

/// 추천 색상 하나(이름 + 대표 색상 +썸네일에 쓸 그라디언트 톤).
class WorkspacePaletteOption {
  const WorkspacePaletteOption(this.label, this.color, this.gradient);

  final String label;
  final Color color;
  final List<Color> gradient;
}

/// 컬러 피커 아래 "추천 색상" — 단순 원형 chip이 아니라, 실제 공간에서
/// 보이는 톤을 가늠할 수 있도록 톤 그라디언트 thumbnail 카드로 보여준다.
///
/// 실제 인테리어 사진 자산은 이번 범위에 없어(임의로 만들지 않음) 각
/// 팔레트의 대표 톤을 그라디언트로 표현했다 — 실제 촬영/생성 이미지가
/// 준비되면 [WorkspacePaletteOption]에 이미지 참조만 추가하면 된다.
class RecommendedPalette extends StatelessWidget {
  const RecommendedPalette({super.key, required this.onSelected});

  final ValueChanged<WorkspacePaletteOption> onSelected;

  static const List<WorkspacePaletteOption> options = [
    WorkspacePaletteOption('Warm beige', Color(0xFFD8C3A5), [
      Color(0xFFE8D9C2),
      Color(0xFFC9AF8C),
    ]),
    WorkspacePaletteOption('Ivory', Color(0xFFF2EEE9), [
      Color(0xFFFAF7F2),
      Color(0xFFE8E1D6),
    ]),
    WorkspacePaletteOption('Natural wood', Color(0xFFB98A5C), [
      Color(0xFFCDA073),
      Color(0xFF8F6339),
    ]),
    WorkspacePaletteOption('Modern gray', Color(0xFFA9ADB2), [
      Color(0xFFC7CBCF),
      Color(0xFF7C8186),
    ]),
    WorkspacePaletteOption('Warm white', Color(0xFFF7F1E7), [
      Color(0xFFFFFCF6),
      Color(0xFFEDE2CC),
    ]),
    WorkspacePaletteOption('Charcoal accent', Color(0xFF3B3A39), [
      Color(0xFF5A5856),
      Color(0xFF232221),
    ]),
  ];

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
            '추천 색상',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: SpaceShiftColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.95,
            ),
            itemCount: options.length,
            itemBuilder: (context, index) {
              final option = options[index];
              return _PaletteCard(
                option: option,
                onTap: () => onSelected(option),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PaletteCard extends StatelessWidget {
  const _PaletteCard({required this.option, required this.onTap});

  final WorkspacePaletteOption option;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: SpaceShiftColors.border),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: option.gradient,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              option.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: SpaceShiftColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
