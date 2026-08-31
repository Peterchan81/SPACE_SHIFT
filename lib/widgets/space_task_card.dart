import 'package:flutter/material.dart';

import '../models/space_task.dart';

/// 공간 작업실에서 등록한 작업 하나를 보여주는 입력 Card.
///
/// 선택 대상/영역 요약, 변경 내용 텍스트 입력, 참고 이미지 첨부,
/// 영역 재선택/삭제 Action을 한 곳에서 다룬다.
class SpaceTaskCard extends StatefulWidget {
  const SpaceTaskCard({
    super.key,
    required this.task,
    required this.index,
    required this.isEditingRegion,
    required this.onInstructionChanged,
    required this.onPickReferenceImage,
    required this.onRemoveReferenceImage,
    required this.onEditRegion,
    required this.onDelete,
  });

  final SpaceTask task;
  final int index;

  /// 이 작업의 영역을 지금 Canvas에서 재선택하고 있는 중인지 여부.
  final bool isEditingRegion;

  final ValueChanged<String> onInstructionChanged;
  final VoidCallback onPickReferenceImage;
  final VoidCallback onRemoveReferenceImage;
  final VoidCallback onEditRegion;
  final VoidCallback onDelete;

  @override
  State<SpaceTaskCard> createState() => _SpaceTaskCardState();
}

class _SpaceTaskCardState extends State<SpaceTaskCard> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.task.instruction,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent =
        spaceRainbowPalette[widget.index % spaceRainbowPalette.length];
    final referenceBytes = widget.task.referenceImageBytes;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: widget.isEditingRegion ? accent : const Color(0xFFE5E5E5),
          width: widget.isEditingRegion ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '작업 ${widget.index + 1} · ${widget.task.category.label}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF212121),
                  ),
                ),
              ),
              IconButton(
                onPressed: widget.onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
                color: const Color(0xFF9E9E9E),
                tooltip: '작업 삭제',
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  '선택 영역: ${widget.task.rect.sizeSummary}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF757575),
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: widget.onEditRegion,
                icon: const Icon(Icons.crop_free_rounded, size: 16),
                label: Text(widget.isEditingRegion ? '영역 조정 중' : '영역 재선택'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            minLines: 2,
            maxLines: 4,
            onChanged: widget.onInstructionChanged,
            decoration: InputDecoration(
              hintText:
                  '예: 좌측 벽을 밝은 아이보리 컬러로 변경하고 TV 뒤쪽은 밝은 우드 패널로 만들어줘.',
              filled: true,
              fillColor: const Color(0xFFFAFAFA),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (referenceBytes != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.memory(
                    referenceBytes,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: widget.onRemoveReferenceImage,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: const Color(0xFF9E9E9E),
                  tooltip: '참고 이미지 제거',
                ),
              ] else
                OutlinedButton.icon(
                  onPressed: widget.onPickReferenceImage,
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: const Text('참고 이미지 첨부'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF616161),
                    side: const BorderSide(color: Color(0xFFE0E0E0)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
