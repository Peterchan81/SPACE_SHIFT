import 'package:flutter/material.dart';

import '../../models/cad_floor_plan.dart';
import '../../models/cad_workspace_state.dart';
import '../../models/floor_plan_file.dart';
import '../../models/floor_plan_geometry.dart';
import '../../models/space_scene.dart';
import '../../models/space_scene_v2.dart';
import '../../models/workspace_task_item.dart';
import '../../theme/space_shift_colors.dart';
import 'cad_floor_plan_overlay.dart';
import 'ceiling_height_sheet.dart' show ceilingHeightPresetsMm;
import 'floor_plan_analysis_overlay.dart';
import 'space_3d_view.dart';
import 'space_3d_view_gpu_v2.dart';

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
    required this.analysisResult,
    required this.cad,
    required this.cadCallbacks,
    required this.onPickFile,
    this.spaceScene,
    this.spaceSceneV2,
    this.spaceGenerationFailureMessage,
    this.onExitTo2D,
  });

  final WorkspaceViewMode viewMode;
  final FloorPlanFile? file;

  /// 분석 완료 시 채워지는 실제 분석 결과 — debug(분석 확인) 모드
  /// 오버레이에만 쓰인다. 분석 상태 텍스트/다시 분석 등은 더 이상 이
  /// 캔버스가 아니라 우측 "사용자 작업 환경"의 [FloorPlanStatusSection]이
  /// 담당한다(도면을 가리지 않기 위해).
  final FloorPlanAnalysisResult? analysisResult;

  final CadWorkspaceState cad;
  final CadWorkspaceCallbacks cadCallbacks;

  final VoidCallback onPickFile;

  /// 실제로 생성된 3D geometry. null이면(아직 생성 전) 준비 상태 안내를
  /// 계속 보여준다 — 정적 이미지를 3D인 것처럼 보여주지 않는다(WO 12번).
  final SpaceScene? spaceScene;

  /// NOMPASS V2 WO — 값이 있으면 이 scene([Space3DViewGpuV2], 실제 GPU
  /// 삼각형 rasterization/depth buffer 렌더러)을 우선 표시한다.
  /// [spaceScene](V1/[Space3DView])과 CPU coarse-tile 렌더러
  /// ([Space3DViewV2] — Windows 실기에서 벽/바닥 경계가 계단화된 큰
  /// block으로 보여 renderer architecture를 재검토한 결과 실제 화면
  /// 표시에서는 빠졌다)는 삭제하지 않고 그대로 남겨 둔다(기존 구현
  /// 삭제 금지).
  final SpaceSceneV2? spaceSceneV2;
  final String? spaceGenerationFailureMessage;

  /// 실기 FAIL 재수정 WO(2번) — 3D 아이소 안에 명확한 "2D 평면도로
  /// 돌아가기" 버튼을 항상 보여준다(상단 View 탭 전환만으로는 눈에
  /// 띄지 않았다는 실사용 신고 대응).
  final VoidCallback? onExitTo2D;

  @override
  Widget build(BuildContext context) {
    if (viewMode != WorkspaceViewMode.plan2d) {
      // WO 8번 — "3D 투시는 실제 3D 아이소 기반이 준비되기 전에는 활성
      // 완료 상태로 만들지 않는다." 이번 1차 구현은 궤도 카메라 하나뿐
      // (아이소 전용)이라, 3D 투시 전용 카메라/화면은 아직 없다 — 아이소가
      // 준비돼도 투시는 계속 준비 상태 안내로 남는다(다음 단계로 보고).
      final sceneV2 = viewMode == WorkspaceViewMode.isometric3d
          ? spaceSceneV2
          : null;
      if (sceneV2 != null) {
        return Space3DViewGpuV2(scene: sceneV2, onExitTo2D: onExitTo2D);
      }
      final scene = viewMode == WorkspaceViewMode.isometric3d
          ? spaceScene
          : null;
      if (scene != null) {
        return Space3DView(scene: scene, onExitTo2D: onExitTo2D);
      }
      return _Cad3DReadinessPlaceholder(
        cad: cad,
        callbacks: cadCallbacks,
        failureMessage: spaceGenerationFailureMessage,
        isPerspectiveNotYetSupported:
            viewMode == WorkspaceViewMode.perspective3d,
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
              onCalibrationDragEnd: cadCallbacks.onCalibrationDragEnd,
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

/// CAD 표시 도구모음 — 원본/CAD/비교 전환, 분석 확인(debug) 토글, 기준
/// 치수/천장고 빠른 진입(WO 5/6/9/10번).
///
/// 예전에는 이 도구모음이 중앙 캔버스 위에 떠서 도면을 가리거나 벽 탭을
/// 가로채는 문제가 있었다. 지금은 우측 "사용자 작업 환경"의
/// [FloorPlanStatusSection] 안에 일반 콘텐츠로 배치되므로, 자체 배경/테두리
/// 없이 [Wrap]만 그린다 — 카드 배경은 호출부([FloorPlanStatusSection])가
/// 제공한다.
class CadToolbar extends StatelessWidget {
  const CadToolbar({super.key, required this.cad, required this.callbacks});

  final CadWorkspaceState cad;
  final CadWorkspaceCallbacks callbacks;

  @override
  Widget build(BuildContext context) {
    return Wrap(
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
      ],
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

/// 3D View(아이소/투시)에서 보여주는 정직한 준비 상태 안내 — 실제
/// [Space3DView]가 만들어지기 전까지는 절대 가짜 3D를 보여주지 않는다
/// (WO 9/12번).
class _Cad3DReadinessPlaceholder extends StatelessWidget {
  const _Cad3DReadinessPlaceholder({
    required this.cad,
    required this.callbacks,
    this.failureMessage,
    this.isPerspectiveNotYetSupported = false,
  });

  final CadWorkspaceState cad;
  final CadWorkspaceCallbacks callbacks;

  /// [CadWorkspaceCallbacks.onGenerate3D]가 실제로 실행됐지만 3D
  /// geometry를 만들지 못했을 때의 이유(WO 9번 — 실패하면 2D를 유지하고
  /// 이유를 알기 쉽게 보여준다).
  final String? failureMessage;

  /// 3D 투시는 이번 1차 구현 범위 밖(WO 8/14번) — 아이소가 준비돼도
  /// 계속 이 상태로 남는다.
  final bool isPerspectiveNotYetSupported;

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
                isPerspectiveNotYetSupported
                    ? '3D 투시는 다음 단계에서 지원할 예정입니다'
                    : (ready
                          ? '3D 아이소 생성 준비가 완료되었습니다'
                          : '3D 공간이 아직 생성되지 않았습니다'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: SpaceShiftColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              if (isPerspectiveNotYetSupported)
                const Text(
                  '지금은 상단 "3D 아이소"에서 실제 3D 공간을 만들고 확인할 수 있습니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: SpaceShiftColors.textSecondary,
                    height: 1.4,
                  ),
                )
              else if (failureMessage != null)
                Text(
                  failureMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: SpaceShiftColors.textSecondary,
                    height: 1.4,
                  ),
                )
              else if (!ready)
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
                  '벽/바닥을 실제 3D geometry로 만듭니다. 문/창은 아직 벽에 반영되지 '
                  '않습니다(다음 단계 예정).',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: SpaceShiftColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              if (!isPerspectiveNotYetSupported) ...[
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: ready ? callbacks.onGenerate3D : null,
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('3D 아이소 만들기'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SpaceShiftColors.textPrimary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: SpaceShiftColors.border,
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

/// 우측 "사용자 작업 환경 → 작업" 탭 최상단에 항상 보이는 2D 단계 전용
/// 섹션 — 도면 분석 상태/다시 분석, CAD 표시 설정(원본/CAD/비교·분석
/// 확인·축척·천장고), 3D 전환 준비 상태를 모은다.
///
/// 예전에는 이 컨트롤들이 중앙 캔버스 위에 뜬 툴바/오버레이여서 실제
/// 평면도를 가렸다 — 우측 패널로 옮겨 중앙은 평면도만 보이게 한다.
class FloorPlanStatusSection extends StatelessWidget {
  const FloorPlanStatusSection({
    super.key,
    required this.hasFloorPlanFile,
    required this.analysisPhase,
    required this.analysisStep,
    required this.analysisResult,
    required this.analysisFailureMessage,
    required this.onReanalyze,
    required this.cad,
    required this.cadCallbacks,
  });

  final bool hasFloorPlanFile;
  final FloorPlanAnalysisPhase analysisPhase;
  final FloorPlanAnalysisStep? analysisStep;
  final FloorPlanAnalysisResult? analysisResult;
  final String? analysisFailureMessage;

  /// 분석 시작/재시도/다시 분석 버튼 모두가 공유하는 단일 콜백 — 이미
  /// 사용자가 CAD를 보정한 뒤 다시 분석해 그 보정 내용이 사라질 위험이
  /// 있을 때만 확인 절차를 적용하는 판단은 호출부(화면)가 한다.
  final VoidCallback onReanalyze;

  final CadWorkspaceState cad;
  final CadWorkspaceCallbacks cadCallbacks;

  @override
  Widget build(BuildContext context) {
    if (!hasFloorPlanFile) {
      return const _LabeledCard(
        title: '도면 분석 상태',
        child: Text(
          '왼쪽에서 평면도를 업로드하면 분석 상태가 여기에 표시됩니다.',
          style: TextStyle(
            fontSize: 12.5,
            color: SpaceShiftColors.textSecondary,
            height: 1.4,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AnalysisActionBar(
          phase: analysisPhase,
          step: analysisStep,
          result: analysisResult,
          failureMessage: analysisFailureMessage,
          onStartAnalysis: onReanalyze,
        ),
        if (analysisPhase == FloorPlanAnalysisPhase.completed) ...[
          const SizedBox(height: 16),
          _LabeledCard(
            title: '평면도 준비 완료',
            child: _SpaceSummaryCard(cad: cad, callbacks: cadCallbacks),
          ),
          const SizedBox(height: 16),
          _LabeledCard(
            title: cad.isReadyFor3D ? '3D 아이소 만들기 준비 완료' : '3D 아이소 만들기 준비 상태',
            child: _ReadinessSummary(cad: cad, callbacks: cadCallbacks),
          ),
          const SizedBox(height: 16),
          // 2D 정확도 개선 WO(19번) — CAD/원본/비교 전환·분석 확인은
          // 일반 사용자의 핵심 작업이 아니라 검증용 고급 기능이다.
          // 중앙 작업 영역은 도면 자체가 가장 잘 보이는 게 우선이므로,
          // 기본은 접힌 상태로 두고 필요한 사람만 펼쳐서 쓴다.
          _CollapsibleAdvancedSection(
            child: CadToolbar(cad: cad, callbacks: cadCallbacks),
          ),
        ],
      ],
    );
  }
}

/// 2D 단순화 WO(6번) — 우측 패널에서 일반 사용자가 가장 먼저/크게 보는
/// 카드. 개발자 용어("scale calibration"/"reference points"/"geometry")를
/// 노출하지 않고 "공간 크기"와 "천장 높이"만 보여준다. 정확도를 높이고
/// 싶은 사용자를 위한 "치수 보정"은 맨 아래 작은 보조 링크로만 둔다(WO
/// 3/7번 — 필수 단계에서 제거하되 기능 자체는 그대로 보존).
class _SpaceSummaryCard extends StatelessWidget {
  const _SpaceSummaryCard({required this.cad, required this.callbacks});

  final CadWorkspaceState cad;
  final CadWorkspaceCallbacks callbacks;

  @override
  Widget build(BuildContext context) {
    final plan = cad.floorPlan;
    final scale = cad.scale;
    final estimated = scale != null && !scale.source.isReliable;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '공간별 크기',
          style: TextStyle(fontSize: 12, color: SpaceShiftColors.textSecondary),
        ),
        const SizedBox(height: 8),
        if (plan == null || plan.rooms.isEmpty)
          const Text(
            '인식된 공간이 없습니다',
            style: TextStyle(
              fontSize: 13,
              color: SpaceShiftColors.textSecondary,
            ),
          )
        else
          for (var i = 0; i < plan.rooms.length; i++)
            _RoomAreaRow(
              plan: plan,
              room: plan.rooms[i],
              index: i,
              scale: scale,
              selected: plan.rooms[i].id == cad.selectedObjectId,
              onSelect: () => callbacks.onSelectObject(plan.rooms[i].id),
              onRename: (name) =>
                  callbacks.onRenameRoom(plan.rooms[i].id, name),
            ),
        // 2D 정확도 개선 WO(7번) — 추정 치수 경고는 개발자 용어 없이,
        // 실측값처럼 보이지 않도록 항상 명시적으로 보여준다.
        if (estimated) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFCD9B4)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 15,
                  color: Color(0xFFB45309),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    scale.source == ScaleSource.estimatedFromDoor
                        ? '평면도에 정확한 치수가 없어 문 크기와 공간 구조를 '
                              '기준으로 대략 계산했습니다. 실제 현장 치수와 '
                              '오차가 있을 수 있습니다.'
                        : '도면 정보를 기준으로 계산한 추정 치수입니다. 실제 '
                              '현장 치수와 오차가 있을 수 있습니다.',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF92400E),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (plan != null && plan.rooms.length > 1) ...[
          const SizedBox(height: 8),
          _TotalAreaRow(plan: plan, scale: scale, callbacks: callbacks),
        ],
        const SizedBox(height: 16),
        const Text(
          '천장 높이',
          style: TextStyle(fontSize: 12, color: SpaceShiftColors.textSecondary),
        ),
        const SizedBox(height: 6),
        _CeilingHeightChips(cad: cad, callbacks: callbacks),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: _ToolbarTextButton(
            icon: Icons.straighten_rounded,
            label: '치수 보정',
            active: cad.calibrating,
            onTap: callbacks.onStartCalibration,
          ),
        ),
        if (cad.calibrating) ...[
          const SizedBox(height: 8),
          if (!cad.hasCalibrationSelection)
            const Text(
              '평면도에서 치수를 알고 싶은 벽 구간을 마우스(또는 펜/손가락)로 '
              '눌러서 그대로 드래그해주세요.',
              style: TextStyle(
                fontSize: 12,
                color: SpaceShiftColors.selectionAccent,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            )
          else
            _CalibrationSelectionPanel(cad: cad, callbacks: callbacks),
        ],
      ],
    );
  }
}

/// 실기 FAIL 재수정 WO(13/14번) — 벽을 드래그로 선택하면 즉시 현재
/// 축척 기준 추정 길이를 보여주고, 사용자가 실제 치수를 알면 입력해
/// 축척을 확정할 수 있게 한다.
class _CalibrationSelectionPanel extends StatefulWidget {
  const _CalibrationSelectionPanel({
    required this.cad,
    required this.callbacks,
  });

  final CadWorkspaceState cad;
  final CadWorkspaceCallbacks callbacks;

  @override
  State<_CalibrationSelectionPanel> createState() =>
      _CalibrationSelectionPanelState();
}

class _CalibrationSelectionPanelState
    extends State<_CalibrationSelectionPanel> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cad = widget.cad;
    final pixelLength = cad.calibrationPixelLength!;
    final scale = cad.scale;
    final estimatedMm = scale != null ? pixelLength * scale.mmPerPixel : null;
    final estimated = scale == null || !scale.source.isReliable;
    final label = cad.calibrationWallId != null ? '선택한 벽' : '선택한 구간';

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: SpaceShiftColors.selectionAccent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: SpaceShiftColors.selectionAccent.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              color: SpaceShiftColors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            estimatedMm == null
                ? '현재 추정 길이를 계산할 수 없습니다'
                : '약 ${(estimatedMm / 1000).toStringAsFixed(2)}m'
                      '${estimated ? " (추정)" : ""}',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: SpaceShiftColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '실제 치수를 알고 있다면 입력해 정확하게 보정할 수 있습니다.',
            style: TextStyle(
              fontSize: 11.5,
              color: SpaceShiftColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  keyboardType: const TextInputType.numberWithOptions(),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: '예: 4000',
                    suffixText: 'mm',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  final mm = double.tryParse(_controller.text.trim());
                  if (mm == null || mm <= 0) return;
                  widget.callbacks.onApplyCalibrationLength(mm);
                },
                child: const Text('치수 적용'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: widget.callbacks.onCancelCalibrationSelection,
              child: const Text('다시 선택'),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomAreaRow extends StatelessWidget {
  const _RoomAreaRow({
    required this.plan,
    required this.room,
    required this.index,
    required this.scale,
    required this.selected,
    required this.onSelect,
    required this.onRename,
  });

  final CadFloorPlan plan;
  final CadRoom room;
  final int index;
  final FloorPlanScale? scale;
  final bool selected;
  final VoidCallback onSelect;
  final ValueChanged<String> onRename;

  Future<void> _promptRename(BuildContext context) async {
    final controller = TextEditingController(
      text: room.name ?? displayRoomName(room, index),
    );
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('공간 이름 변경'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '예: 거실, 안방'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (result != null) onRename(result);
  }

  @override
  Widget build(BuildContext context) {
    final m2 = roomAreaM2(plan, room, scale);
    final pyeong = m2 == null ? null : squareMetersToPyeong(m2);
    final estimated = scale != null && !scale!.source.isReliable;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        // 실기 FAIL 재수정 WO(3번) — 행을 누르면(이름/아이콘이 아닌 곳)
        // 중앙 도면의 같은 번호 marker가 highlight된다(양방향 동기화).
        onTap: onSelect,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: selected
                ? SpaceShiftColors.selectionAccent.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? SpaceShiftColors.selectionAccent
                  : Colors.transparent,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 20,
                height: 20,
                margin: const EdgeInsets.only(top: 1),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? SpaceShiftColors.selectionAccent
                      : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: SpaceShiftColors.selectionAccent,
                    width: selected ? 0 : 1.2,
                  ),
                ),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: selected
                        ? Colors.white
                        : SpaceShiftColors.selectionAccent,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            displayRoomName(room, index),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: SpaceShiftColors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () => _promptRename(context),
                          borderRadius: BorderRadius.circular(4),
                          child: const Padding(
                            padding: EdgeInsets.all(2),
                            child: Icon(
                              Icons.edit_outlined,
                              size: 13,
                              color: SpaceShiftColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      m2 == null
                          ? '계산 불가'
                          : scale?.source == ScaleSource.unknown
                          ? '축척 미확정 · 참고 약 ${m2.toStringAsFixed(1)}㎡'
                          : '약 ${m2.toStringAsFixed(1)}㎡ · 약 '
                                '${pyeong!.toStringAsFixed(1)}평'
                                '${estimated ? " (추정)" : ""}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: SpaceShiftColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TotalAreaRow extends StatelessWidget {
  const _TotalAreaRow({
    required this.plan,
    required this.scale,
    required this.callbacks,
  });

  final CadFloorPlan plan;
  final FloorPlanScale? scale;
  final CadWorkspaceCallbacks callbacks;

  @override
  Widget build(BuildContext context) {
    final m2 = totalAreaM2(plan, scale);
    if (m2 == null) return const SizedBox.shrink();

    // NOMPASS V2 WO(2/3번) — "unknown scale에서 임의 diagonal로 계산한
    // 값을 정확한 면적처럼 표시하는 구조를 중단한다." 8m→13m fallback
    // 조정은 근본 해결이 아니었다 — 숫자 자체를 크게/확정처럼 보여주지
    // 않고, "축척 미확정" 상태와 보정 유도를 1순위로 보여준다. 추정값은
    // 참고용 2차 정보로만 작게 남긴다.
    if (scale == null || scale!.source == ScaleSource.unknown) {
      final pyeong = squareMetersToPyeong(m2);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFFCD9B4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '분석된 공간 · 축척 미확정',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: SpaceShiftColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '실제 길이 1곳을 입력하면 공간 면적과 3D 크기를 정확하게 보정할 수 있습니다.',
              style: TextStyle(
                fontSize: 11.5,
                color: Color(0xFF92400E),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '참고 추정: 약 ${m2.toStringAsFixed(1)}㎡ · 약 ${pyeong.toStringAsFixed(1)}평 '
              '(신뢰도 낮음)',
              style: const TextStyle(
                fontSize: 11,
                color: SpaceShiftColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: callbacks.onStartCalibration,
                style: OutlinedButton.styleFrom(
                  foregroundColor: SpaceShiftColors.textPrimary,
                  side: const BorderSide(color: Color(0xFFFCD9B4)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                child: const Text('치수 보정', style: TextStyle(fontSize: 12.5)),
              ),
            ),
          ],
        ),
      );
    }

    final pyeong = squareMetersToPyeong(m2);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: SpaceShiftColors.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '전체',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: SpaceShiftColors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '약 ${m2.toStringAsFixed(1)}㎡ · 약 ${pyeong.toStringAsFixed(1)}평'
            '${!scale!.source.isReliable ? " (추정)" : ""}',
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: SpaceShiftColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 2D 정확도 개선 WO(9번) — 천장 높이를 "자동 확정"처럼 보이지 않게,
/// 프리셋 칩(직접 눌러 확인/변경) + 직접입력으로 보여준다. 현재 값이
/// 프리셋 중 하나면 그 칩이 선택 표시된다.
class _CeilingHeightChips extends StatelessWidget {
  const _CeilingHeightChips({required this.cad, required this.callbacks});

  final CadWorkspaceState cad;
  final CadWorkspaceCallbacks callbacks;

  @override
  Widget build(BuildContext context) {
    final current = cad.ceilingHeightMm;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final preset in ceilingHeightPresetsMm)
          _CeilingChip(
            label: preset.toStringAsFixed(0),
            selected: current == preset,
            onTap: () => callbacks.onCeilingHeightPresetSelected(preset),
          ),
        _CeilingChip(
          label: current != null && !ceilingHeightPresetsMm.contains(current)
              ? '${current.toStringAsFixed(0)}mm(직접입력)'
              : '직접 입력',
          selected:
              current != null && !ceilingHeightPresetsMm.contains(current),
          onTap: callbacks.onSetCeilingHeight,
        ),
      ],
    );
  }
}

class _CeilingChip extends StatelessWidget {
  const _CeilingChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? SpaceShiftColors.selectionAccent.withValues(alpha: 0.14)
              : SpaceShiftColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? SpaceShiftColors.selectionAccent
                : SpaceShiftColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected
                ? SpaceShiftColors.selectionAccent
                : SpaceShiftColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _ReadinessSummary extends StatelessWidget {
  const _ReadinessSummary({required this.cad, required this.callbacks});

  final CadWorkspaceState cad;
  final CadWorkspaceCallbacks callbacks;

  @override
  Widget build(BuildContext context) {
    final ready = cad.isReadyFor3D;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!ready)
          for (final reason in cad.missing3DReasons)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '· $reason',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: SpaceShiftColors.textSecondary,
                  height: 1.4,
                ),
              ),
            )
        else
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text(
              '도면 geometry·축척·천장고가 모두 준비되었습니다. 이제 3D 아이소에서 '
              '실제 인테리어 작업을 시작할 수 있습니다.',
              style: TextStyle(
                fontSize: 12.5,
                color: SpaceShiftColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: ready ? callbacks.onGenerate3D : null,
            icon: const Icon(Icons.view_in_ar_rounded, size: 18),
            label: const Text('3D 아이소 만들기'),
            style: ElevatedButton.styleFrom(
              backgroundColor: SpaceShiftColors.textPrimary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: SpaceShiftColors.border,
              minimumSize: const Size.fromHeight(44),
            ),
          ),
        ),
      ],
    );
  }
}

/// 2D 정확도 개선 WO(19번) — CAD/원본/비교 전환 등 검증용 고급 기능을
/// 기본 접힌 상태로 감싼다. 기능 자체는 삭제하지 않고 그대로 유지한다.
class _CollapsibleAdvancedSection extends StatefulWidget {
  const _CollapsibleAdvancedSection({required this.child});

  final Widget child;

  @override
  State<_CollapsibleAdvancedSection> createState() =>
      _CollapsibleAdvancedSectionState();
}

class _CollapsibleAdvancedSectionState
    extends State<_CollapsibleAdvancedSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SpaceShiftColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(
                    Icons.tune_rounded,
                    size: 16,
                    color: SpaceShiftColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '고급 설정(CAD/원본/비교, 분석 확인)',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: SpaceShiftColors.textSecondary,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: SpaceShiftColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: widget.child,
            ),
        ],
      ),
    );
  }
}

class _LabeledCard extends StatelessWidget {
  const _LabeledCard({required this.title, required this.child});

  final String title;
  final Widget child;

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
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: SpaceShiftColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
