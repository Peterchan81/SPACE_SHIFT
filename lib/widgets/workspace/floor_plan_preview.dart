import 'package:flutter/material.dart';

import '../../models/floor_plan_file.dart';
import '../../models/floor_plan_geometry.dart';
import '../../models/workspace_task_item.dart';
import '../../theme/space_shift_colors.dart';
import 'floor_plan_analysis_overlay.dart';

/// 중앙 캔버스에서 "평면도 업로드/분석" 단계별 상태를 보여주는 위젯.
///
/// 2D 평면도 View에서만 실제 업로드한 파일을 보여준다. 3D 아이소/투시
/// View는 아직 3D 생성 엔진이 없으므로, 파일이 있어도 정직하게 "아직
/// 생성되지 않았다"고 안내한다(WO 13번 — 뷰를 넘나들어도 2D 쪽 파일/분석
/// 상태는 그대로 유지된다. 상태를 들고 있는 쪽은 이 위젯이 아니라
/// 호출부이므로, 이 위젯 자체는 항상 stateless로 값만 그린다).
class FloorPlanPreview extends StatelessWidget {
  const FloorPlanPreview({
    super.key,
    required this.viewMode,
    required this.file,
    required this.analysisPhase,
    required this.analysisStep,
    required this.analysisResult,
    required this.failureMessage,
    required this.selectedAnalysisObjectIds,
    required this.onPickFile,
    required this.onStartAnalysis,
    required this.onSelectAnalysisObject,
  });

  final WorkspaceViewMode viewMode;
  final FloorPlanFile? file;
  final FloorPlanAnalysisPhase analysisPhase;

  /// [analysisPhase]가 [FloorPlanAnalysisPhase.analyzing]일 때만 의미가
  /// 있는 실제 진행 단계.
  final FloorPlanAnalysisStep? analysisStep;

  /// [analysisPhase]가 [FloorPlanAnalysisPhase.completed]일 때 채워지는
  /// 실제 분석 결과.
  final FloorPlanAnalysisResult? analysisResult;

  /// [analysisPhase]가 [FloorPlanAnalysisPhase.failed]일 때 보여줄, 이미
  /// 사용자 친화적으로 다듬어진 메시지.
  final String? failureMessage;

  final Set<String> selectedAnalysisObjectIds;
  final VoidCallback onPickFile;
  final VoidCallback onStartAnalysis;
  final ValueChanged<String> onSelectAnalysisObject;

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

    final result = analysisResult;

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
        if (analysisPhase == FloorPlanAnalysisPhase.completed && result != null)
          Positioned.fill(
            child: FloorPlanAnalysisOverlay(
              result: result,
              selectedIds: selectedAnalysisObjectIds,
              onSelect: onSelectAnalysisObject,
            ),
          ),
        Positioned(
          left: 16,
          right: 16,
          top: 16,
          child: _StatusBanner(file: file, result: result),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: _AnalysisActionBar(
            phase: analysisPhase,
            step: analysisStep,
            result: result,
            failureMessage: failureMessage,
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
  const _StatusBanner({required this.file, required this.result});

  final FloorPlanFile file;
  final FloorPlanAnalysisResult? result;

  @override
  Widget build(BuildContext context) {
    final result = this.result;
    final message = result == null
        ? '평면도가 선택되었습니다 · ${file.fileName}'
        : '벽 ${result.walls.length}개 · 공간 ${result.rooms.length}개 인식됨';

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
              message,
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
    required this.step,
    required this.result,
    required this.failureMessage,
    required this.onStartAnalysis,
  });

  final FloorPlanAnalysisPhase phase;
  final FloorPlanAnalysisStep? step;
  final FloorPlanAnalysisResult? result;
  final String? failureMessage;
  final VoidCallback onStartAnalysis;

  String get _stepLabel {
    switch (step) {
      case FloorPlanAnalysisStep.preparingAndWalls:
        return '이미지를 준비하고 벽을 분석하는 중입니다...';
      case FloorPlanAnalysisStep.roomsAndOpenings:
        return '공간과 문/창 후보를 분석하는 중입니다...';
      case FloorPlanAnalysisStep.finalizing:
        return '결과를 정리하는 중입니다...';
      case null:
        return '평면도를 분석하는 중입니다...';
    }
  }

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
        FloorPlanAnalysisPhase.analyzing => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _stepLabel,
                style: const TextStyle(
                  fontSize: 13,
                  color: SpaceShiftColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
        FloorPlanAnalysisPhase.completed => _CompletedSummary(
          result: result,
          onReanalyze: onStartAnalysis,
        ),
        FloorPlanAnalysisPhase.failed => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 18,
                  color: Colors.redAccent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    failureMessage ?? '평면도를 분석하지 못했습니다.',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: SpaceShiftColors.textPrimary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onStartAnalysis,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('다시 시도'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(40),
                  foregroundColor: SpaceShiftColors.textPrimary,
                  side: const BorderSide(color: SpaceShiftColors.border),
                ),
              ),
            ),
          ],
        ),
      },
    );
  }
}

class _CompletedSummary extends StatelessWidget {
  const _CompletedSummary({required this.result, required this.onReanalyze});

  final FloorPlanAnalysisResult? result;
  final VoidCallback onReanalyze;

  @override
  Widget build(BuildContext context) {
    final result = this.result;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.check_circle_outline_rounded,
              size: 18,
              color: Color(0xFF22C55E),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                '벽/공간 후보를 캔버스 위에 표시했습니다. 항목을 눌러 확인해보세요.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: SpaceShiftColors.textPrimary,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
        if (result != null && result.warnings.isNotEmpty) ...[
          const SizedBox(height: 6),
          for (final warning in result.warnings)
            Padding(
              padding: const EdgeInsets.only(left: 26, top: 2),
              child: Text(
                warning,
                style: const TextStyle(fontSize: 12, color: Color(0xFFB45309)),
              ),
            ),
        ],
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onReanalyze,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('다시 분석'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(40),
              foregroundColor: SpaceShiftColors.textPrimary,
              side: const BorderSide(color: SpaceShiftColors.border),
            ),
          ),
        ),
      ],
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
