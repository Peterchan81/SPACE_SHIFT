import 'package:flutter/material.dart';

import '../../models/floor_plan_file.dart';
import '../../models/workspace_task_item.dart';
import '../../theme/space_shift_colors.dart';

/// 좌측 "시작 방식 선택"의 "① 평면도 업로드" 카드.
///
/// 다른 두 방식 카드([WorkspaceStartMethod.drawManually]/
/// [WorkspaceStartMethod.photoConvert])와 같은 시각 언어를 쓰되, 이 방식만
/// 실제로 동작하므로 파일 선택 상태와 "파일 선택"/"다시 선택" 버튼을
/// 추가로 보여준다.
///
/// 카드를 탭하면(헤더 영역) 시작 방식만 선택되고, 실제 업로드는 항상
/// 눈에 보이는 별도 버튼으로만 실행한다 — "카드가 이미 선택돼 있어서
/// 업로드 action을 못 찾는" 구조를 피하기 위함이다(WO 4번).
class FloorPlanUploadCard extends StatelessWidget {
  const FloorPlanUploadCard({
    super.key,
    required this.selected,
    required this.file,
    required this.onSelectCard,
    required this.onPickFile,
  });

  final bool selected;
  final FloorPlanFile? file;
  final VoidCallback onSelectCard;
  final VoidCallback onPickFile;

  @override
  Widget build(BuildContext context) {
    final accent = workspaceMarkerColorFor(1);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onSelectCard,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? accent : SpaceShiftColors.border,
              width: selected ? 1.5 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                    child: const Text(
                      '1',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '평면도 업로드',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: SpaceShiftColors.textPrimary,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '도면 이미지를 업로드하여\n3D 공간을 자동 생성합니다.',
                          style: TextStyle(
                            fontSize: 12,
                            color: SpaceShiftColors.textSecondary,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: SpaceShiftColors.background,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: SpaceShiftColors.border),
                    ),
                    child: Icon(
                      Icons.upload_file_rounded,
                      size: 20,
                      color: accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (file != null) _FileStatusRow(file: file!),
              if (file != null) const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: onPickFile,
                icon: Icon(
                  file == null
                      ? Icons.file_open_outlined
                      : Icons.change_circle_outlined,
                  size: 18,
                ),
                label: Text(file == null ? '파일 선택' : '다시 선택'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  foregroundColor: SpaceShiftColors.textPrimary,
                  side: const BorderSide(color: SpaceShiftColors.border),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FileStatusRow extends StatelessWidget {
  const _FileStatusRow({required this.file});

  final FloorPlanFile file;

  @override
  Widget build(BuildContext context) {
    final sizeText = file.sizeBytes > 0
        ? '${(file.sizeBytes / 1024).toStringAsFixed(0)}KB'
        : '';

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: SpaceShiftColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: SpaceShiftColors.border),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 32,
              height: 32,
              child: file.kind == FloorPlanFileKind.image && file.bytes != null
                  ? Image.memory(file.bytes!, fit: BoxFit.cover, cacheWidth: 64)
                  : Container(
                      color: Colors.white,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.picture_as_pdf_outlined,
                        size: 18,
                        color: SpaceShiftColors.textSecondary,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: SpaceShiftColors.textPrimary,
                  ),
                ),
                Text(
                  '${file.extension.toUpperCase()}${sizeText.isEmpty ? '' : ' · $sizeText'} · 선택 완료',
                  style: const TextStyle(
                    fontSize: 11,
                    color: SpaceShiftColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
