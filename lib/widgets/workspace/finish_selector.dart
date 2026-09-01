import 'package:flutter/material.dart';

import '../../theme/space_shift_colors.dart';

/// "마감재 선택" 카드 — 선택된 대상 종류(벽/바닥/천장)에 따라 옵션이
/// 달라지는 chip 목록 + texture thumbnail 그리드.
///
/// 실제 texture 이미지 asset/업로드 파이프라인은 이번 범위가 아니므로,
/// 마감재 종류를 시각적으로 구분할 수 있는 색/아이콘 기반 placeholder
/// thumbnail을 사용한다. "사용자 선택"은 실제 업로드 UI까지 연결해 두고,
/// 후속 작업에서 실제 저장/불러오기 service만 연결하면 되도록
/// [onUploadCustom] 콜백으로 분리해 둔다.
class FinishSelector extends StatelessWidget {
  const FinishSelector({
    super.key,
    required this.options,
    required this.selectedOption,
    required this.onOptionSelected,
    required this.onUploadCustom,
  });

  final List<String> options;
  final String selectedOption;
  final ValueChanged<String> onOptionSelected;
  final VoidCallback onUploadCustom;

  static const List<Color> _thumbnailTints = [
    Color(0xFFEFEBE4),
    Color(0xFFE7E2DC),
    Color(0xFFEDE6DC),
    Color(0xFFE3E7E9),
    Color(0xFFE9E4DE),
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
            '마감재 선택',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: SpaceShiftColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in options)
                _OptionChip(
                  label: option,
                  selected: option == selectedOption,
                  onTap: () => onOptionSelected(option),
                ),
            ],
          ),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1,
            ),
            itemCount: 6,
            itemBuilder: (context, index) {
              if (index == 5) {
                return _UploadThumbnail(onTap: onUploadCustom);
              }
              return Container(
                decoration: BoxDecoration(
                  color: _thumbnailTints[index % _thumbnailTints.length],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: SpaceShiftColors.border),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? SpaceShiftColors.textPrimary : Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? SpaceShiftColors.textPrimary
                  : SpaceShiftColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : SpaceShiftColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _UploadThumbnail extends StatelessWidget {
  const _UploadThumbnail({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: SpaceShiftColors.border,
              style: BorderStyle.solid,
            ),
          ),
          child: const Center(
            child: Icon(
              Icons.add_photo_alternate_outlined,
              size: 22,
              color: SpaceShiftColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
