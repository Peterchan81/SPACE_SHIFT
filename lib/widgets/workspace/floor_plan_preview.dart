import 'package:flutter/material.dart';

import '../../models/cad_workspace_state.dart';
import '../../models/floor_plan_file.dart';
import '../../models/floor_plan_geometry.dart';
import '../../models/workspace_task_item.dart';
import '../../theme/space_shift_colors.dart';
import 'cad_floor_plan_overlay.dart';
import 'floor_plan_analysis_overlay.dart';

/// 중앙 캔버스에서 "평면도 업로드/분석/CAD 편집" 단계별 상태를 보여주는
/// 위젯.
///
/// 2D 평면도 View에서만 실제 콘텐츠(원본 이미지 또는 CAD geometry)를
/// 보여준다. 3D 아이소/투시 View는 아직 3D 생성 엔진이 없으므로, CAD
/// geometry·축척·천장고가 모두 준비됐는지 정직하게 안내하고, 셋 다
/// 갖춰졌을 때만 [CadWorkspaceCallbacks.onGenerate3D]를 실행할 수 있게
/// 한다(WO 11번 — 가짜 3D 이미지를 만들지 않는다).
class FloorPlanPreview extends StatelessWidget {
  const FloorPlanPreview({
    super.key,
    required this.viewMode,
    required this.file,
    required this.analysisPhase,
    required this.analysisStep,
    required this.analysisResult,
    required this.failureMessage,
    required this.cad,
    required this.cadCallbacks,
    required this.onPickFile,
    required this.onStartAnalysis,
  });

  final WorkspaceViewMode viewMode;
  final FloorPlanFile? file;
  final FloorPlanAnalysisPhase analysisPhase;

  /// [analysisPhase]가 [FloorPlanAnalysisPhase.analyzing]일 때만 의미가
  /// 있는 실제 진행 단계.
  final FloorPlanAnalysisStep? analysisStep;

  /// [analysisPhase]가 [FloorPlanAnalysisPhase.completed]일 때 채워지는
  /// 실제 분석 결과 — debug(분석 확인) 모드 오버레이에만 쓰인다.
  final FloorPlanAnalysisResult? analysisResult;

  /// [analysisPhase]가 [FloorPlanAnalysisPhase.failed]일 때 보여줄, 이미
  /// 사용자 친화적으로 다듬어진 메시지.
  final String? failureMessage;

  final CadWorkspaceState cad;
  final CadWorkspaceCallbacks cadCallbacks;

  final VoidCallback onPickFile;
  final VoidCallback onStartAnalysis;

  @override
  Widget build(BuildContext context) {
    if (viewMode != WorkspaceViewMode.plan2d) {
      return _Cad3DReadinessPlaceholder(cad: cad, callbacks: cadCallbacks);
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
    final floorPlan = cad.floorPlan;
    final showOriginal =
        cad.displayMode != FloorPlanDisplayMode.cad || floorPlan == null;
    final showCad =
        floorPlan != null && cad.displayMode != FloorPlanDisplayMode.original;

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          color: const Color(0xFFF7F8FA),
          child: showOriginal
              ? Center(
                  child:
                      file.kind == FloorPlanFileKind.image && file.bytes != null
                      ? Image.memory(
                          file.bytes!,
                          fit: BoxFit.contain,
                          // 큰 원본 이미지를 화면 크기보다 훨씬 큰 해상도로
                          // 통째로 디코드하지 않도록 downsample한다(메모리
                          // 절감).
                          cacheWidth: 1600,
                        )
                      : const _PdfPlaceholderIcon(),
                )
              : null,
        ),
        if (showCad && cad.debugOverlay && result != null)
          Positioned.fill(
            child: FloorPlanAnalysisOverlay(
              result: result,
              selectedIds: cad.selectedObjectId == null
                  ? const {}
                  : {cad.selectedObjectId!},
              onSelect: (id) => cadCallbacks.onSelectObject(id),
            ),
          )
        else if (showCad)
          Positioned.fill(
            child: CadFloorPlanOverlay(
              floorPlan: floorPlan,
              selectedId: cad.selectedObjectId,
              onSelect: cadCallbacks.onSelectObject,
              onWallEndpointChanged: cadCallbacks.onWallEndpointChanged,
              calibrating: cad.calibrating,
              calibrationPoints: cad.calibrationPoints,
              onCalibrationTap: cadCallbacks.onCalibrationTap,
            ),
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

/// 분석 전(CAD geometry가 아직 없는) 상태에서 캔버스 상단에 보여주는
/// 요약 배너. [WorkspaceCanvas]가 캔버스 위에 겹쳐 그리지 않고, 캔버스와
/// 별도의 레이아웃 공간을 차지하는 헤더 자리에 그린다 — 예전엔
/// Positioned로 캔버스 위에 떠 있어서, 벽이 캔버스 상단 근처에 있으면
/// 탭이 배너에 가로채여 실제 벽을 선택할 수 없는 문제가 있었다.
class FloorPlanStatusBanner extends StatelessWidget {
  const FloorPlanStatusBanner({
    super.key,
    required this.file,
    required this.result,
  });

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

/// 분석 완료 후 상단에 뜨는 CAD 표시 도구모음 — 원본/CAD/비교 전환,
/// 분석 확인(debug) 토글, 기준 치수/천장고 빠른 진입(WO 5/6/9/10번).
///
/// [WorkspaceCanvas]가 이 위젯을 캔버스 위에 떠 있는 Positioned가 아니라
/// 별도 레이아웃 공간(헤더 행)에 그린다 — 안 그러면 이 도구모음이
/// 캔버스 상단 근처의 벽 탭을 가로채 선택이 안 되는 실제 버그가 있었다.
class CadToolbar extends StatelessWidget {
  const CadToolbar({super.key, required this.cad, required this.callbacks});

  final CadWorkspaceState cad;
  final CadWorkspaceCallbacks callbacks;

  @override
  Widget build(BuildContext context) {
    // Row+SingleChildScrollView는 캔버스 상단 전체 너비를 차지하는
    // Viewport를 만들어, 버튼 사이 빈 공간까지도 hitTestSelf로 탭을
    // 가로채 버렸다(그 아래 CadFloorPlanOverlay가 탭을 못 받는 원인이
    // 됐던 실제 버그). Wrap은 스크롤 gesture recognizer가 없어 자기
    // 자식이 실제로 그려진 영역 밖에서는 탭을 가로채지 않으므로, 캔버스
    // 상단부의 벽 탭 선택이 막히지 않는다. 대신 좁은 화면에서는 다음
    // 줄로 자연스럽게 넘어간다.
    return Align(
      alignment: Alignment.topLeft,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: SpaceShiftColors.border),
        ),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _ModeSegment(
              selected: cad.displayMode,
              onChanged: callbacks.onDisplayModeChanged,
            ),
            _ToolbarIconButton(
              icon: Icons.bug_report_outlined,
              active: cad.debugOverlay,
              tooltip: '분석 확인(개발자용)',
              onTap: callbacks.onToggleDebugOverlay,
            ),
            _ToolbarTextButton(
              icon: Icons.straighten_rounded,
              label: cad.hasScale ? '축척 재설정' : '기준 치수 설정',
              active: cad.calibrating,
              onTap: callbacks.onStartCalibration,
            ),
            _ToolbarTextButton(
              icon: Icons.height_rounded,
              label: cad.hasCeilingHeight
                  ? '천장고 ${cad.ceilingHeightMm!.toStringAsFixed(0)}mm'
                  : '천장고 입력',
              active: false,
              onTap: callbacks.onSetCeilingHeight,
            ),
            if (cad.calibrating)
              Text(
                '기준점 ${cad.calibrationPoints.length}/2 선택됨',
                style: const TextStyle(
                  fontSize: 12,
                  color: SpaceShiftColors.selectionAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ModeSegment extends StatelessWidget {
  const _ModeSegment({required this.selected, required this.onChanged});

  final FloorPlanDisplayMode selected;
  final ValueChanged<FloorPlanDisplayMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: SpaceShiftColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: SpaceShiftColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final mode in FloorPlanDisplayMode.values)
            InkWell(
              onTap: () => onChanged(mode),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: selected == mode
                      ? SpaceShiftColors.textPrimary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  mode.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected == mode
                        ? Colors.white
                        : SpaceShiftColors.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ToolbarIconButton extends StatelessWidget {
  const _ToolbarIconButton({
    required this.icon,
    required this.active,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final bool active;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: active
                ? SpaceShiftColors.selectionAccent.withValues(alpha: 0.12)
                : SpaceShiftColors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active
                  ? SpaceShiftColors.selectionAccent
                  : SpaceShiftColors.border,
            ),
          ),
          child: Icon(
            icon,
            size: 18,
            color: active
                ? SpaceShiftColors.selectionAccent
                : SpaceShiftColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _ToolbarTextButton extends StatelessWidget {
  const _ToolbarTextButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? SpaceShiftColors.selectionAccent.withValues(alpha: 0.12)
              : SpaceShiftColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active
                ? SpaceShiftColors.selectionAccent
                : SpaceShiftColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: active
                  ? SpaceShiftColors.selectionAccent
                  : SpaceShiftColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active
                    ? SpaceShiftColors.selectionAccent
                    : SpaceShiftColors.textPrimary,
              ),
            ),
          ],
        ),
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
                '도면 구조를 CAD로 변환했습니다. 벽/공간을 눌러 확인하고, 실제 '
                '작업 대상은 우측 패널에서 "작업으로 추가"해주세요.',
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

/// 3D View(아이소/투시)에서 보여주는 정직한 준비 상태 안내 —
/// geometry/축척/천장고가 모두 갖춰지기 전까지 가짜 3D를 보여주지
/// 않는다(WO 11번).
class _Cad3DReadinessPlaceholder extends StatelessWidget {
  const _Cad3DReadinessPlaceholder({
    required this.cad,
    required this.callbacks,
  });

  final CadWorkspaceState cad;
  final CadWorkspaceCallbacks callbacks;

  @override
  Widget build(BuildContext context) {
    final ready = cad.isReadyFor3D;
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
                  ready ? Icons.view_in_ar_rounded : Icons.view_in_ar_outlined,
                  size: 30,
                  color: ready
                      ? SpaceShiftColors.selectionAccent
                      : SpaceShiftColors.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                ready ? '3D 생성 준비가 완료되었습니다' : '3D 공간이 아직 생성되지 않았습니다',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: SpaceShiftColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              if (!ready)
                for (final reason in cad.missing3DReasons)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '· $reason',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: SpaceShiftColors.textSecondary,
                      ),
                    ),
                  )
              else
                const Text(
                  '실제 3D 렌더링은 이번 범위 밖입니다 — 지금은 CAD geometry/축척/'
                  '천장고를 모아 3D 생성 입력 데이터를 준비하는 단계까지만 진행합니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: SpaceShiftColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: ready ? callbacks.onGenerate3D : null,
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('3D 공간 생성'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: SpaceShiftColors.textPrimary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: SpaceShiftColors.border,
                ),
              ),
            ],
          ),
        ),
      ),
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
