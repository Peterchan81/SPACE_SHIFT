/// SS015 — MASTER UI 11(3D 아이소 랜더링). SS013/SS014([IsoEditorScreen]/[ElevationFaceEditorScreen])가
/// [SsDataSlot.cadData]/[SsDataSlot.isoData]에 남긴 완성된 ISO 디자인(구조+마감재+가구+조명+설비)을
/// 실사 스타일 최종 렌더링으로 처리하는 동안 단계별 진행 상태([SsIsoRenderStep])를 Blue neon ISO
/// wireframe 미리보기와 함께 보여준다. 3D geometry/재질 엔진은 새로 만들지 않고 기존
/// [buildIsoEditorScene](SS013, [IsoRenderService] 참고)을 그대로 재사용한다. 실패해도 확정된
/// CAD/ISO 디자인 데이터([SsDataSlot.cadData]/[SsDataSlot.isoData])는 이 화면이 건드리지 않으므로
/// 그대로 남고, 사용자는 다시 시도하거나(일반 오류) 3D 디자인 화면으로 돌아가 입력을 고칠 수 있다
/// (입력 자체가 문제인 경우).
///
/// 이미 최신 렌더링 결과가 있으면([SsProject.staleNotices]가 renderData를 낡았다고 하지 않으면) 다시
/// 렌더링하지 않고 상태만 보여준다(§완료조건 "중복 렌더링 요청 방지" — [IsoConversionScreen]과 같은
/// 패턴, SS012). [SsIsoRenderController.start]/[retry]도 이미 처리 중이면 새 요청을 만들지 않아,
/// 실제 렌더 엔진/API를 쓸 때 불필요한 중복 호출을 막는다.
///
/// 완료되면 [SsDataSlot.renderData]에 결과를 저장하고 최종 결과 화면(MASTER UI 12, SS016)으로
/// 넘어간다 — SS016이 아직 전용 화면을 만들기 전까지는 공통 단계 화면([SsStageScreen])이 대기 안내를
/// 보여준다.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/ss_ai_task.dart';
import '../core/ss_iso_render_controller.dart';
import '../core/ss_iso_render_step.dart';
import '../core/ss_project.dart';
import '../core/ss_project_store.dart';
import '../core/ss_router.dart' show SsStageHeader;
import '../core/ss_stage.dart';
import '../models/iso_render_result.dart';
import '../models/space_scene_v2.dart';
import '../models/ss_cad_scene.dart';
import '../models/ss_iso_camera_state.dart';
import '../models/ss_iso_design_extras.dart';
import '../services/iso_conversion_input_builder.dart' show sceneFromCadDataPayload;
import '../services/iso_conversion_service.dart' show kIsoDefaultCeilingHeightMm;
import '../services/iso_render_service.dart';
import '../services/ss_iso_editor_scene_builder.dart' show buildIsoEditorScene;
import '../services/ss_project_store_provider.dart';
import '../theme/ss_master_theme.dart';
import '../widgets/iso_conversion/blue_neon_iso_preview.dart';

enum _IsoRenderLoad { loading, loaded, missingInput, error }

class IsoRenderingScreen extends StatefulWidget {
  const IsoRenderingScreen({super.key, this.projectId, this.projectStore, this.renderService = const IsoRenderService()});

  /// 렌더링할 프로젝트 id(ISO 디자인 화면에서 "렌더링 시작"을 누를 때 함께 전달된다).
  final String? projectId;

  /// 테스트에서 주입. 없으면 앱 공용 [SsProjectStoreProvider] 저장소.
  final SsProjectStore? projectStore;

  /// 실제 최종 렌더링 엔진 호출(테스트에서 가짜 구현으로 교체 가능 — IsoConversionScreen과 같은 패턴).
  final IsoRenderService renderService;

  @override
  State<IsoRenderingScreen> createState() => _IsoRenderingScreenState();
}

class _IsoRenderingScreenState extends State<IsoRenderingScreen> {
  _IsoRenderLoad _state = _IsoRenderLoad.loading;
  SsProjectStore? _store;
  SsProject? _project;
  SsCadScene? _cad;
  SsIsoDesignExtras _extras = SsIsoDesignExtras.empty;
  SsIsoCameraState? _previousCamera;
  Map<String, Object?>? _previousRenderPayload;
  bool _alreadyUpToDate = false;
  final SsIsoRenderController _controller = SsIsoRenderController();

  /// MASTER UI 11 — 렌더링이 끝나기 전에도(아직 [SsAiTask.lastGoodResult]가 없을 때) 이미 확정된
  /// ISO 디자인으로부터 즉시 계산할 수 있는 미리보기([buildIsoEditorScene]는 결정적 순수 함수라 몇
  /// 번을 다시 불러도 안전하다 — 새 3D 엔진을 만들지 않는다, §구현 원칙). 단계 진행 중에도 Blue neon
  /// wireframe이 빈 화면이 아니라 실제 완성된 ISO 모델을 보여주게 한다.
  SpaceSceneV2? _previewScene;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final pid = widget.projectId;
    if (pid == null) {
      setState(() => _state = _IsoRenderLoad.error);
      return;
    }
    try {
      final store = widget.projectStore ?? await SsProjectStoreProvider.instance.store();
      final project = await store.load(pid);
      if (project == null) {
        if (!mounted) return;
        setState(() => _state = _IsoRenderLoad.error);
        return;
      }
      final cadPayload = project.data[SsDataSlot.cadData]?.payload;
      final cad = cadPayload == null ? null : sceneFromCadDataPayload(cadPayload);
      if (!mounted) return;
      if (cad == null) {
        setState(() {
          _store = store;
          _project = project;
          _state = _IsoRenderLoad.missingInput;
        });
        return;
      }
      final isoSlot = project.data[SsDataSlot.isoData];
      final extras = SsIsoDesignExtras.tryFromJson(isoSlot?.payload['design']);
      final renderSlot = project.data[SsDataSlot.renderData];
      final stale = project.staleNotices().any((n) => n.stale == SsDataSlot.renderData);
      final upToDate = renderSlot != null && !stale;
      final previousCamera = SsIsoCameraState.tryFromJson(isoSlot?.payload['camera']);
      setState(() {
        _store = store;
        _project = project;
        _cad = cad;
        _extras = extras;
        _previousCamera = previousCamera;
        _previousRenderPayload = renderSlot?.payload;
        _alreadyUpToDate = upToDate;
        _previewScene = _tryBuildPreviewScene(cad, extras);
        _state = _IsoRenderLoad.loaded;
      });
      if (!upToDate) unawaited(_startRender(cad, extras, previousCamera));
    } catch (e, st) {
      // 네트워크를 쓰지 않는 화면이므로 네트워크 오류로 오분류하지 않는다 — 실제 원인은 로그로 남기고
      // 사용자에게는 일반 안내만 보인다.
      debugPrint('IsoRenderingScreen._load 실패 (${e.runtimeType}): $e\n$st');
      if (!mounted) return;
      setState(() => _state = _IsoRenderLoad.error);
    }
  }

  /// [IsoRenderService.render]가 내부적으로 하는 것과 같은 계산(완성된 ISO 디자인→최종 3D scene)을
  /// 지연 없이 한 번 더 해서 미리보기 전용으로 쓴다 — 결과를 저장하지 않고 화면에만 쓰므로 실패해도
  /// 조용히 null을 돌려주고 기존 "스캔 중" 격자로 넘어간다(지어내지 않는다).
  SpaceSceneV2? _tryBuildPreviewScene(SsCadScene cad, SsIsoDesignExtras extras) {
    final plan = cad.plan;
    if (plan.walls.isEmpty && plan.rooms.isEmpty) return null;
    try {
      final scene = buildIsoEditorScene(cad: cad, extras: extras, ceilingHeightMm: kIsoDefaultCeilingHeightMm);
      return scene.isEmpty ? null : scene;
    } catch (e, st) {
      debugPrint('IsoRenderingScreen._tryBuildPreviewScene 실패 (${e.runtimeType}): $e\n$st');
      return null;
    }
  }

  Future<void> _startRender(SsCadScene cad, SsIsoDesignExtras extras, SsIsoCameraState? previousCamera) async {
    final status = await _controller.start(
      (onStep) => widget.renderService.render(cad, extras: extras, previousCamera: previousCamera, onStep: onStep),
    );
    if (status == SsAiStatus.completed) unawaited(_onRenderCompleted());
  }

  Future<void> _retry() async {
    final status = await _controller.retry();
    if (status == SsAiStatus.completed) unawaited(_onRenderCompleted());
  }

  /// 사용자가 "다시 렌더링"을 눌렀을 때 — 이미 최신 상태라도 강제로 다시 렌더링한다. 기존 Orbit
  /// 카메라는 그대로 이어받는다(§완료조건 "사용자 디자인 데이터를 소실하지 않는다").
  Future<void> _regenerate() async {
    final cad = _cad;
    if (cad == null) return;
    setState(() => _alreadyUpToDate = false);
    unawaited(_startRender(cad, _extras, _previousCamera));
  }

  Future<void> _onRenderCompleted() async {
    final project = _project;
    final store = _store;
    final result = _controller.task.lastGoodResult;
    if (project == null || store == null || result == null) return;
    final moved = project.withStageData(SsDataSlot.renderData, _renderDataPayload(result), label: '3D ISO 렌더링 결과').moveTo(SsStage.finalResult);
    try {
      await store.save(moved);
    } catch (e, st) {
      debugPrint('IsoRenderingScreen 결과 저장 실패 (${e.runtimeType}): $e\n$st');
    }
    _project = moved;
    if (!mounted) return;
    await Navigator.of(context).pushReplacementNamed(SsStage.finalResult.routeName, arguments: widget.projectId);
  }

  /// SS015가 관리하는 필드만 덮어쓰고, 다른 FLOW(이미지 변환, SS007)가 같은 칸에 남겼을 수 있는 필드는
  /// 이 화면이 지어내지 않는다 — 같은 프로젝트는 항상 하나의 sourceType/FLOW만 쓰므로(§구현 원칙)
  /// 실제로 섞일 일은 없지만, 혹시 모를 이전 payload의 다른 키는 그대로 들고 간다(사용자 데이터를
  /// 조용히 지우지 않는다).
  Map<String, Object?> _renderDataPayload(IsoRenderResult result) {
    final preserved = <String, Object?>{...?_previousRenderPayload};
    preserved.removeWhere((k, _) => _managedRenderDataKeys.contains(k));
    return {
      ...preserved,
      'kind': 'ssIsoRender',
      'camera': result.camera.toJson(),
      'quality': result.quality.name,
      'warnings': result.warnings,
      'wallCount': result.scene.wallCount,
      'floorCount': result.scene.floorCount,
      'generatedAt': DateTime.now().toIso8601String(),
    };
  }

  static const Set<String> _managedRenderDataKeys = {'kind', 'camera', 'quality', 'warnings', 'wallCount', 'floorCount', 'generatedAt'};

  void _backToPreviousStage() {
    final project = _project;
    final previous = project == null ? null : SsFlows.previous(project.sourceType, SsStage.isoRendering);
    final navigator = Navigator.of(context);
    if (previous == null) {
      if (navigator.canPop()) navigator.pop();
      return;
    }
    // 정면도·측면도 화면([ElevationFaceEditorScreen])은 Map 형태 인자(projectId/wallId)를 받는다 —
    // 다른 단계로 돌아갈 때와 인자 형식이 다르므로 대상에 맞게 만든다.
    final Object? args = previous == SsStage.elevationFaceEditor ? <String, Object?>{'projectId': widget.projectId} : widget.projectId;
    navigator.pushReplacementNamed(previous.routeName, arguments: args);
  }

  /// 이미 최신 렌더링 결과가 있을 때 "최종 결과 확인하기" — 다시 렌더링하지 않고 바로 최종 결과(SS016)로
  /// 넘어간다. 그래도 단계 이동은 저장해 둔다(이 화면에 어떤 경로로 다시 들어왔든 currentStage가
  /// 정확하게 남도록).
  Future<void> _goToFinalResult() async {
    final project = _project;
    final store = _store;
    if (project != null && store != null) {
      final moved = project.moveTo(SsStage.finalResult);
      try {
        await store.save(moved);
        _project = moved;
      } catch (e, st) {
        debugPrint('IsoRenderingScreen 단계 이동 저장 실패 (${e.runtimeType}): $e\n$st');
      }
    }
    if (!mounted) return;
    await Navigator.of(context).pushReplacementNamed(SsStage.finalResult.routeName, arguments: widget.projectId);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_state == _IsoRenderLoad.error) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('렌더링할 작업을 불러오지 못했습니다.', key: Key('ssIsoRenderLoadError'), style: TextStyle(color: SsMasterTheme.textSecondary)),
            const SizedBox(height: 12),
            OutlinedButton(key: const Key('ssIsoRenderBackFromError'), onPressed: _backToPreviousStage, child: const Text('이전 단계로 돌아가기')),
          ],
        ),
      );
    }
    if (_state == _IsoRenderLoad.loading) {
      return const Center(child: CircularProgressIndicator(key: Key('ssIsoRenderLoading')));
    }
    if (_state == _IsoRenderLoad.missingInput) {
      return Padding(
        key: const Key('ssIsoRenderScreen'),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SsStageHeader(stage: SsStage.isoRendering),
            const SizedBox(height: 16),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '렌더링할 3D ISO 디자인이 없습니다. 먼저 3D 디자인을 완료해 주세요.',
                      key: Key('ssIsoRenderMissingInput'),
                      style: TextStyle(color: SsMasterTheme.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(key: const Key('ssIsoRenderBackToPrevious'), onPressed: _backToPreviousStage, child: const Text('이전 단계로 돌아가기')),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final status = _controller.task.status;
        return Padding(
          key: const Key('ssIsoRenderScreen'),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 3, child: _buildPreview()),
                    const SizedBox(width: 20),
                    SizedBox(width: 340, child: _alreadyUpToDate ? _buildUpToDatePanel() : _buildStatusPanel(status)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(child: SsStageHeader(stage: SsStage.isoRendering)),
        IconButton(
          key: const Key('ssIsoRenderBack'),
          tooltip: '이전 단계로 돌아가기',
          onPressed: _backToPreviousStage,
          icon: const Icon(Icons.arrow_back, color: SsMasterTheme.textSecondary),
        ),
      ],
    );
  }

  /// MASTER UI 11 원본 — 진행 중에도 이미 완성된 ISO 모델이 보인다. 아직 확정 결과가 없으면([SsAiTask.
  /// lastGoodResult]가 null — 렌더링 전/진행 중) 디자인으로부터 즉시 계산한 미리보기([_previewScene])를
  /// 먼저 쓰고, 그것도 없으면(벽/공간이 없는 등) 마지막으로 "스캔 중" 격자를 보여준다. 확정 결과가
  /// 생기면(또는 재생성 전 lastGoodResult) 그 값을 그대로 쓴다.
  Widget _buildPreview() {
    final scene = _controller.task.lastGoodResult?.scene ?? _previewScene;
    return Container(
      key: const Key('ssIsoRenderPreview'),
      decoration: BoxDecoration(color: const Color(0xFF081628), borderRadius: BorderRadius.circular(16), border: Border.all(color: SsMasterTheme.panelBorder)),
      clipBehavior: Clip.antiAlias,
      child: scene == null
          ? Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(painter: _SsIsoRenderScanGridPainter()),
                const Center(child: Icon(Icons.view_in_ar_outlined, color: SsMasterTheme.neonBlue, size: 64)),
              ],
            )
          : BlueNeonIsoPreview(scene: scene),
    );
  }

  Widget _buildUpToDatePanel() {
    return Container(
      key: const Key('ssIsoRenderUpToDatePanel'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: SsMasterTheme.panel, borderRadius: BorderRadius.circular(16), border: Border.all(color: SsMasterTheme.panelBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline, color: SsMasterTheme.neonBlue, size: 28),
          const SizedBox(height: 12),
          const Text('이미 최신 렌더링 결과가 있습니다.', key: Key('ssIsoRenderUpToDateTitle'), style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('3D 디자인이 바뀌지 않아 다시 렌더링할 필요가 없습니다.', key: Key('ssIsoRenderUpToDateMessage'), style: TextStyle(color: SsMasterTheme.textSecondary, fontSize: 12)),
          const SizedBox(height: 18),
          ElevatedButton(key: const Key('ssIsoRenderContinue'), onPressed: () => unawaited(_goToFinalResult()), child: const Text('최종 결과 확인하기')),
          const SizedBox(height: 10),
          OutlinedButton(key: const Key('ssIsoRenderRegenerate'), onPressed: () => unawaited(_regenerate()), child: const Text('다시 렌더링')),
        ],
      ),
    );
  }

  Widget _buildStatusPanel(SsAiStatus status) {
    final failed = status == SsAiStatus.failed || status == SsAiStatus.retryable || status == SsAiStatus.inputFixNeeded;
    final title = failed ? '최종 렌더링을 만들지 못했습니다' : '랜더링을 생성하고 있습니다.';
    final subtitle = failed
        ? (_controller.task.message ?? '다시 시도하거나 이전 단계로 돌아가 3D 디자인을 확인해 주세요.')
        : '선택한 공간의 디자인을 실사 스타일로 렌더링하여 3D 아이소 모델에 반영합니다.';
    return Container(
      key: const Key('ssIsoRenderStatusPanel'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: SsMasterTheme.panel, borderRadius: BorderRadius.circular(16), border: Border.all(color: SsMasterTheme.panelBorder)),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(failed ? Icons.error_outline : Icons.auto_awesome, color: failed ? Colors.redAccent : SsMasterTheme.neonBlue, size: 28),
            const SizedBox(height: 12),
            Text(title, key: const Key('ssIsoRenderStatusTitle'), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(subtitle, key: const Key('ssIsoRenderStatusMessage'), style: const TextStyle(color: SsMasterTheme.textSecondary, fontSize: 12)),
            const SizedBox(height: 18),
            if (!failed) _buildProgressBar(),
            const SizedBox(height: 18),
            for (final step in SsIsoRenderStep.values) _buildStepRow(step),
            if (failed) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(key: const Key('ssIsoRenderBackFromFail'), onPressed: _backToPreviousStage, child: const Text('이전 단계로 돌아가기')),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      key: const Key('ssIsoRenderRetry'),
                      onPressed: _controller.task.canRetry ? () => unawaited(_retry()) : null,
                      child: const Text('다시 시도'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    final p = _controller.progress;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 10,
              child: Stack(
                children: [
                  Container(color: SsMasterTheme.panelBorder),
                  FractionallySizedBox(
                    widthFactor: p.clamp(0.0, 1.0),
                    child: Container(decoration: const BoxDecoration(gradient: SsMasterTheme.selectedItem)),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text('${(p * 100).round()}%', key: const Key('ssIsoRenderProgressPercent'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _buildStepRow(SsIsoRenderStep step) {
    final done = _controller.completedSteps.contains(step);
    final active = _controller.currentStep == step;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle : (active ? Icons.radio_button_checked : Icons.radio_button_unchecked),
            key: Key('ssIsoRenderStep_${step.name}'),
            size: 18,
            color: done ? SsMasterTheme.neonBlue : (active ? SsMasterTheme.neonCyan : SsMasterTheme.textMuted),
          ),
          const SizedBox(width: 10),
          Text(step.label, style: TextStyle(color: done || active ? Colors.white : SsMasterTheme.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }
}

/// Blue neon 진행 화면 — 결과가 아직 없을 때(첫 프레임) 보여주는 "스캔 중" 격자(MASTER UI 9/7과
/// 같은 시각언어, IsoConversionScreen._SsIsoScanGridPainter와 같은 생각).
class _SsIsoRenderScanGridPainter extends CustomPainter {
  _SsIsoRenderScanGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = SsMasterTheme.neonCyan.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SsIsoRenderScanGridPainter oldDelegate) => false;
}
