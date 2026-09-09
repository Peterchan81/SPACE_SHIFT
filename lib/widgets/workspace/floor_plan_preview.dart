import 'dart:typed_data';

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
    this.generatedIsoImageBytes,
    this.isGeneratingIsoImage = false,
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

  /// V1 GPT CAD-STYLE 2D → GPT ISO IMAGE FLOW WO §7/§8 — GPT가 Clean 2D
  /// 결과를 기반으로 새로 그려준 3D 아이소메트릭 이미지. 값이 있으면
  /// [spaceSceneV2](실시간 geometry, 삭제하지 않고 그대로 보존)보다
  /// 우선 표시한다 — V1 기본 흐름은 이 AI 이미지를 먼저 보여준다.
  final Uint8List? generatedIsoImageBytes;

  /// true인 동안 "3D 아이소 생성 중" 상태를 보여준다.
  final bool isGeneratingIsoImage;

  /// 실기 FAIL 재수정 WO(2번) — 3D 아이소 안에 명확한 "2D 평면도로
  /// 돌아가기" 버튼을 항상 보여준다(상단 View 탭 전환만으로는 눈에
  /// 띄지 않았다는 실사용 신고 대응).
  final VoidCallback? onExitTo2D;

  @override
  Widget build(BuildContext context) {
    if (viewMode != WorkspaceViewMode.plan2d) {
      // WO092 §3/§6 — 실시간 geometry 기반 3D(Space3DViewGpuV2)가 이제
      // 3D 아이소/3D 투시 모두의 주 작업화면이다. 둘은 완전히 같은
      // scene을 쓰고 카메라 배치([Space3DCameraMode])만 다르다 — GPT가
      // 생성한 정적 아이소 이미지는 더 이상 주 화면을 대체하지 않고,
      // 아이소 탭에서만 선택적으로 열어보는 "AI 참고 이미지" 버튼으로
      // 격하한다(§0 "미리보기/참고 기능으로만 보존").
      final isIso = viewMode == WorkspaceViewMode.isometric3d;
      final isPerspective = viewMode == WorkspaceViewMode.perspective3d;

      final sceneV2 = spaceSceneV2;
      if (sceneV2 != null) {
        return Stack(
          children: [
            Positioned.fill(
              child: Space3DViewGpuV2(
                scene: sceneV2,
                cameraMode: isPerspective
                    ? Space3DCameraMode.perspective
                    : Space3DCameraMode.isometric,
                onExitTo2D: onExitTo2D,
                selectedObjectId: cad.selected3DObjectId,
                onObjectSelected: cadCallbacks.onSelect3DObject,
              ),
            ),
            if (isIso && (isGeneratingIsoImage || generatedIsoImageBytes != null))
              Positioned(
                right: 12,
                bottom: 12,
                child: _AiReferenceImageButton(
                  isGenerating: isGeneratingIsoImage,
                  imageBytes: generatedIsoImageBytes,
                ),
              ),
          ],
        );
      }
      // 실시간 geometry가 아직 없으면(V1 [Space3DView] 폴백, 둘 다
      // 삭제하지 않고 그대로 보존) V1 CPU 렌더러로, 그마저 없으면 준비
      // 상태 안내로 대체한다.
      final scene = spaceScene;
      if (scene != null) {
        return Space3DView(scene: scene, onExitTo2D: onExitTo2D);
      }
      return _Cad3DReadinessPlaceholder(
        cad: cad,
        callbacks: cadCallbacks,
        failureMessage: spaceGenerationFailureMessage,
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
    final generatedImage = cad.generatedFloorPlanImageBytes;
    // V1 AI-IMAGE FLOW WO — "CAD" 표시 슬롯은 이제 좌표 기반
    // CadFloorPlanOverlay가 아니라 GPT가 새로 그려준 평면도 이미지
    // 그 자체를 보여준다. 분석 확인(debug) 오버레이는 여전히 원본
    // 사진의 픽셀 evidence를 보여주는 별개의 고급 기능이라(WO 5번,
    // "치수 보정"과 같은 위치에 숨겨진 CadToolbar에서만 켤 수 있다)
    // 그대로 유지한다 — [floorPlan]은 이제 화면에 직접 그려지지 않고
    // 3D 아이소 생성에만 쓰인다(§9).
    final showDebugOverlay =
        cad.debugOverlay && cad.displayMode != FloorPlanDisplayMode.original && result != null;
    final showGeneratedImage =
        !showDebugOverlay && generatedImage != null && cad.displayMode != FloorPlanDisplayMode.original;
    final showOriginal = !showDebugOverlay && !showGeneratedImage;

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
        if (showDebugOverlay)
          Positioned.fill(
            child: FloorPlanAnalysisOverlay(
              result: result,
              selectedIds: cad.selectedObjectId == null
                  ? const {}
                  : {cad.selectedObjectId!},
              onSelect: (id) => cadCallbacks.onSelectObject(id),
            ),
          )
        else if (showGeneratedImage)
          Center(
            child: Image.memory(
              generatedImage,
              fit: BoxFit.contain,
              cacheWidth: 1600,
            ),
          ),
        // V1 AI-IMAGE FLOW WO — "치수 보정"은 좌표 기반 CAD 결과를
        // 상시 노출하는 기능이 아니라, 사용자가 명시적으로 "치수 보정"을
        // 눌러 실제 축척(mm)을 입력하려 할 때만 켜지는 opt-in 고급
        // 기능이다(WO 절대 금지 목록의 "좌표 복원 연구"와는 다르다 —
        // 이미 있던 기존 기능을 그대로 재사용할 뿐이다). 벽 구간을
        // 드래그로 고르는 제스처/미리보기 선은 [CadFloorPlanOverlay]가
        // 담당하므로, 이 모드일 때만 위에 겹쳐 보여준다. floorPlan은
        // 화면에 그려지는 이미지(생성 이미지 또는 원본)와 같은 소스에서
        // 나온 것이라 좌표가 어긋나지 않는다(§9 — 생성된 이미지를
        // 기준으로 재계산한 geometry를 그대로 쓴다).
        if (cad.calibrating && cad.floorPlan != null)
          Positioned.fill(
            child: CadFloorPlanOverlay(
              floorPlan: cad.floorPlan!,
              selectedId: cad.selectedObjectId,
              onSelect: cadCallbacks.onSelectObject,
              onWallEndpointChanged: cadCallbacks.onWallEndpointChanged,
              calibrating: true,
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
    required this.failureMessage,
    required this.onStartAnalysis,
    required this.hasGeneratedImage,
  });

  final FloorPlanAnalysisPhase phase;
  final FloorPlanAnalysisStep? step;
  final String? failureMessage;
  final VoidCallback onStartAnalysis;

  /// V1 AI-IMAGE FLOW WO — true면 GPT가 실제로 새 CAD 스타일 평면도
  /// 이미지를 만들어냈다는 뜻이다. false면(생성 실패/미설정) 완료
  /// 문구를 "생성 완료"가 아니라 정직하게 "원본 이미지 유지"로
  /// 보여준다 — 실패했는데 성공한 것처럼 보이지 않게 한다.
  final bool hasGeneratedImage;

  // V1 AI-IMAGE FLOW WO §8 — 내부적으로는 여전히 여러 단계(기본 분석 →
  // AI 평면도 생성)를 거치지만, 사용자에게는 개발자용 엔진 단계 이름
  // ("벽 분석 중"/"문·창 후보 분석 중" 등) 대신 하나의 단순한 문구만
  // 보여준다.
  String get _stepLabel => 'AI 평면도를 생성하는 중입니다...';

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
            label: const Text('AI 평면도 생성'),
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
          hasGeneratedImage: hasGeneratedImage,
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
  const _CompletedSummary({
    required this.hasGeneratedImage,
    required this.onReanalyze,
  });

  final bool hasGeneratedImage;
  final VoidCallback onReanalyze;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              hasGeneratedImage ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
              size: 18,
              color: hasGeneratedImage ? const Color(0xFF22C55E) : const Color(0xFFB45309),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hasGeneratedImage
                    ? 'AI 평면도 생성 완료 — 확인 후 3D 아이소로 진행해주세요.'
                    : 'AI 평면도 생성에 실패해 원본 이미지를 표시하고 있습니다.',
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
            onPressed: onReanalyze,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('AI 평면도 다시 생성'),
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

/// WO092 §0/§3 — GPT 정적 아이소 이미지가 더 이상 주 3D 화면이 아니게
/// 되면서 이 두 위젯(_IsoGenerationLoading/_GeneratedIsoView)은 전체
/// 화면 대체 용도로는 쓰이지 않는다. 삭제하지 않고 보존한다 — 로직은
/// 여전히 유효하고([_AiReferenceImageButton] 아래가 실제로 이 이미지를
/// 보여주는 자리를 대신한다), 향후 "AI 참고 이미지" 전체화면 보기 등에
/// 재사용할 수 있다.
class _IsoGenerationLoading extends StatelessWidget {
  const _IsoGenerationLoading();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF7F8FA),
      alignment: Alignment.center,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          SizedBox(height: 14),
          Text(
            '3D 아이소 생성 중입니다...',
            style: TextStyle(fontSize: 13.5, color: SpaceShiftColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// V1 GPT CAD-STYLE 2D → GPT ISO IMAGE FLOW WO §7/§9 — GPT가 그려준
/// 3D 아이소메트릭 이미지를 그대로 보여준다. 실시간 geometry 3D
/// ([Space3DViewGpuV2])와 똑같이 "2D 평면도로 돌아가기" 버튼을 항상
/// 보여준다(실기 FAIL 재수정 WO 2번과 동일한 원칙).
class _GeneratedIsoView extends StatelessWidget {
  const _GeneratedIsoView({required this.imageBytes, this.onExitTo2D});

  final Uint8List imageBytes;
  final VoidCallback? onExitTo2D;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            color: const Color(0xFFEFF2F5),
            alignment: Alignment.center,
            child: Image.memory(imageBytes, fit: BoxFit.contain),
          ),
        ),
        if (onExitTo2D != null)
          Positioned(
            left: 12,
            top: 12,
            child: Material(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: onExitTo2D,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_back_rounded, size: 16, color: Colors.white),
                      SizedBox(width: 6),
                      Text(
                        '2D 평면도로 돌아가기',
                        style: TextStyle(fontSize: 12.5, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// WO092 §0/§3 — GPT가 그려준 정적 아이소 이미지를 "미리보기/참고
/// 기능"으로만 보존하는 작은 버튼. 실시간 3D 위에 겹쳐 떠 있고, 탭하면
/// 이미지를 전체 화면 dialog로 보여준다 — 실시간 3D 화면을 절대
/// 가리거나 대체하지 않는다.
class _AiReferenceImageButton extends StatelessWidget {
  const _AiReferenceImageButton({required this.isGenerating, this.imageBytes});

  final bool isGenerating;
  final Uint8List? imageBytes;

  @override
  Widget build(BuildContext context) {
    final bytes = imageBytes;
    return Material(
      color: Colors.black.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: bytes == null ? null : () => _showFullscreen(context, bytes),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isGenerating)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              else
                const Icon(Icons.image_rounded, size: 16, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                isGenerating ? 'AI 참고 이미지 생성 중...' : 'AI 참고 이미지 보기',
                style: const TextStyle(fontSize: 12.5, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFullscreen(BuildContext context, Uint8List bytes) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.memory(bytes, fit: BoxFit.contain),
            ),
            Positioned(
              right: 4,
              top: 4,
              child: Material(
                color: Colors.black.withValues(alpha: 0.6),
                shape: const CircleBorder(),
                child: IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
          ],
        ),
      ),
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
  });

  final CadWorkspaceState cad;
  final CadWorkspaceCallbacks callbacks;

  /// [CadWorkspaceCallbacks.onGenerate3D]가 실제로 실행됐지만 3D
  /// geometry를 만들지 못했을 때의 이유(WO 9번 — 실패하면 2D를 유지하고
  /// 이유를 알기 쉽게 보여준다).
  final String? failureMessage;

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
                ready ? '3D 아이소 생성 준비가 완료되었습니다' : '3D 공간이 아직 생성되지 않았습니다',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: SpaceShiftColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              if (failureMessage != null)
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
    final action = onAction;
    final content = Center(
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
              child: Icon(icon, size: 30, color: SpaceShiftColors.textSecondary),
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
              style: const TextStyle(fontSize: 12, color: SpaceShiftColors.textSecondary),
            ),
            if (actionLabel != null && action != null) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: action,
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
    );

    // GPT FLOORPLAN → STRUCTURED 2D → REAL 3D ISO FLOW WO §1 — 파일이
    // 아직 없는 중앙 큰 이미지 영역 "자체"에서도 평면도를 선택할 수
    // 있어야 한다. 기존에는 안쪽의 작은 버튼만 탭 가능했다 — action이
    // 있는 상태(= 실제로 파일을 고를 수 있는 placeholder, 예: "평면도를
    // 업로드해주세요")에서만 배경 전체를 같은 handler에 연결한다(분석
    // 중/실패 등 action이 없는 다른 placeholder 상태는 그대로 탭 불가).
    return Container(
      color: const Color(0xFFF7F8FA),
      child: action == null
          ? content
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: action,
              child: content,
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
    required this.analysisFailureMessage,
    required this.onReanalyze,
    required this.cad,
    required this.cadCallbacks,
  });

  final bool hasFloorPlanFile;
  final FloorPlanAnalysisPhase analysisPhase;
  final FloorPlanAnalysisStep? analysisStep;
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
          failureMessage: analysisFailureMessage,
          onStartAnalysis: onReanalyze,
          hasGeneratedImage: cad.generatedFloorPlanImageBytes != null,
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
    // GPT FLOORPLAN → STRUCTURED 2D → REAL 3D ISO FLOW WO §7 — "공간별
    // 크기"(공간 1/공간 2... 개별 면적 목록 + 전체 면적 합계 + 추정치
    // 경고)는 V1 production UI에서 제거한다. 이 정보를 만드는
    // 데이터(roomAreaM2/totalAreaM2/CadRoom 등)는 삭제하지 않고 그대로
    // 둔다 — 화면에서만 뺀다. 벽 선택/이름 변경 등은 여전히 중앙 CAD
    // 오버레이에서 직접 탭해서 할 수 있다(이 카드가 없어져도 기능
    // 자체가 사라지지 않는다).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
