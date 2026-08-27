import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/space_shift_colors.dart';

/// 작업 지시에 첨부할 참고 이미지를 선택/확인/제거할 수 있는 썸네일 목록.
///
/// 실제 파일 선택창을 여는 로직은 부모(WorkspaceScreen)가 [onAdd]로
/// 전달하므로, 이 위젯은 순수하게 목록 표시와 제거 버튼만 담당한다.
class ReferenceImagePicker extends StatelessWidget {
  const ReferenceImagePicker({
    super.key,
    required this.images,
    required this.onAdd,
    required this.onRemove,
    this.maxImages = 3,
  });

  final List<Uint8List> images;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final int maxImages;

  @override
  Widget build(BuildContext context) {
    final canAddMore = images.length < maxImages;

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (var i = 0; i < images.length; i++) _thumbnail(images[i], i),
        if (canAddMore) _addTile(),
      ],
    );
  }

  Widget _thumbnail(Uint8List bytes, int index) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 64,
          height: 64,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: SpaceShiftColors.border),
          ),
          child: Image.memory(bytes, fit: BoxFit.cover),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: () => onRemove(index),
            child: Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                color: Color(0xFF1F2933),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _addTile() {
    return InkWell(
      onTap: onAdd,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: SpaceShiftColors.border),
          color: const Color(0xFFF7F8FA),
        ),
        child: const Icon(
          Icons.add_rounded,
          color: SpaceShiftColors.textSecondary,
        ),
      ),
    );
  }
}
