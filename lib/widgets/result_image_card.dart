import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/space_shift_colors.dart';

/// Before/After 비교에 사용하는 이미지 카드.
///
/// [imageBytes]가 있으면 실제 이미지를 표시하고, 없으면 아이콘 Placeholder를
/// 표시한다. 원본 카드(선택한 사진)와 AI 결과 카드(아직 생성 전) 양쪽에서
/// 동일한 구조로 재사용한다.
class ResultImageCard extends StatelessWidget {
  const ResultImageCard({
    super.key,
    required this.title,
    required this.placeholderIcon,
    required this.placeholderText,
    this.imageBytes,
  });

  /// 카드 상단에 표시할 제목 (예: 원본, AI 결과)
  final String title;

  /// 이미지가 없을 때 중앙에 표시할 아이콘
  final IconData placeholderIcon;

  /// 이미지가 없을 때 아이콘 아래에 표시할 안내 문구
  final String placeholderText;

  /// 실제로 표시할 이미지 데이터. null이면 Placeholder를 표시한다.
  final Uint8List? imageBytes;

  @override
  Widget build(BuildContext context) {
    final bytes = imageBytes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: SpaceShiftColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        AspectRatio(
          aspectRatio: 4 / 3,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: SpaceShiftColors.border, width: 1.5),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: bytes == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          placeholderIcon,
                          size: 48,
                          color: SpaceShiftColors.border,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          placeholderText,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: SpaceShiftColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  )
                : Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                  ),
          ),
        ),
      ],
    );
  }
}
