import 'package:flutter/material.dart';

import '../../models/floor_plan_file.dart';
import '../../models/workspace_task_item.dart';
import '../../theme/space_shift_colors.dart';

/// 중앙 캔버스에서 "평면도 업로드" 단계별 상태를 보여주는 위젯.
///
/// 2D 평면도 View에서만 실제 업로드한 파일을 보여준다. 3D 아이소/투시
/// View는 아직 3D 생성 엔진이 없으므로, 파일이 있어도 정직하게 "아직
/// 생성되지 않았다"고 안내한다(WO 13번 — 뷰를 넘나들어도 2D 쪽 파일
/// 상태는 그대로 유지된다. 상태를 들고 있는 쪽은 이 위젯이 아니라
/// 호출부이므로, 이 위젯 자체는 항상 stateless로 값만 그린다).
class FloorPlanPreview extends StatelessWidget {
  const FloorPlanPreview({
    super.key,
    required this.viewMode,
    required this.file,
    required this.analysisPhase,
    required this.onPickFile,
    required this.onStartAnalysis,
  });

  final WorkspaceViewMode viewMode;
  final FloorPlanFile? file;
  final FloorPlanAnalysisPhase analysisPhase;
  final VoidCallback onPickFile;
  final VoidCallback onStartAnalysis;

  @override
  Widget build(BuildContext context) {
    if (viewMode != WorkspaceViewMode.plan2d) {
      return const _StatusPlaceholder(
        icon: Icons.view_in_ar_outlined,
        title: '3D 공간이 아직 생성되지 않았습니다',
        subtitle: '평면도 분석 기능이 준비되면 이 화면에 3D 공간이 생성됩니다.',
      );
    }

    final file = this.file;
    if (file == null) {
      return _StatusPlaceholder(
        icon: Icons.upload_file_rounded,
        title: '평면도를 업로드해주세요',
        subtitle: '왼쪽 "평면도 업로드" 카드에서 JPG/PNG/PDF 파일을 선택할 수 있습니다.',
        actionLabel: '평면도 선택',
        onAction: onPickFile,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          color: const Color(0xFFF7F8FA),
          child: Center(
            child: file.kind == FloorPlanFileKind.image && file.bytes != null
                ? Image.memory(
                    file.bytes!,
                    fit: BoxFit.contain,
                    // 큰 원본 이미지를 화면 크기보다 훨씬 큰 해상도로 통째로
                    // 디코드하지 않도록 downsample한다(WO 11번 — 메모리 절감).
                    cacheWidth: 1600,
                  )
                : const _PdfPlaceholderIcon(),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          top: 16,
          child: _StatusBanner(file: file),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: _AnalysisActionBar(
            phase: analysisPhase,
            onStartAnalysis: onStartAnalysis,
          ),
        ),
      ],
    );
  }
}

class _PdfPlaceholderIcon extends StatelessWidget {
  const _PdfPlaceholderIcon();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.picture_as_pdf_outlined,
          size: 72,
          color: SpaceShiftColors.textSecondary,
        ),
        SizedBox(height: 8),
        Text(
          'PDF 미리보기는 지원하지 않습니다',
          style: TextStyle(fontSize: 12, color: SpaceShiftColors.textSecondary),
        ),
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.file});

  final FloorPlanFile file;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SpaceShiftColors.border),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            size: 18,
            color: Color(0xFF22C55E),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '평면도가 선택되었습니다 · ${file.fileName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: SpaceShiftColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalysisActionBar extends StatelessWidget {
  const _AnalysisActionBar({
    required this.phase,
    required this.onStartAnalysis,
  });

  final FloorPlanAnalysisPhase phase;
  final VoidCallback onStartAnalysis;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SpaceShiftColors.border),
      ),
      child: switch (phase) {
        FloorPlanAnalysisPhase.notStarted => SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onStartAnalysis,
            icon: const Icon(Icons.auto_awesome_rounded, size: 18),
            label: const Text('평면도 분석 시작'),
            style: ElevatedButton.styleFrom(
              backgroundColor: SpaceShiftColors.textPrimary,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(44),
            ),
          ),
        ),
        FloorPlanAnalysisPhase.analyzing => const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text(
              '평면도를 확인하는 중입니다...',
              style: TextStyle(
                fontSize: 13,
                color: SpaceShiftColors.textSecondary,
              ),
            ),
          ],
        ),
        FloorPlanAnalysisPhase.unavailable => const Row(
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 18,
              color: SpaceShiftColors.textSecondary,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '평면도 분석 기능은 아직 준비 중입니다. 업로드한 평면도는 그대로 확인할 수 있습니다.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: SpaceShiftColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      },
    );
  }
}

class _StatusPlaceholder extends StatelessWidget {
  const _StatusPlaceholder({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF7F8FA),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: SpaceShiftColors.border),
                ),
                child: Icon(
                  icon,
                  size: 30,
                  color: SpaceShiftColors.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: SpaceShiftColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: SpaceShiftColors.textSecondary,
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.upload_file_rounded, size: 18),
                  label: Text(actionLabel!),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SpaceShiftColors.textPrimary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
