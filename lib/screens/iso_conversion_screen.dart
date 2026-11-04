/// SS012 — MASTER UI 9(3D ISO 변환). SS011(CadEditorScreen)이 [SsDataSlot.cadData]에 남긴 CAD
/// 데이터를 기존 3D 엔진([buildSpaceSceneV2] — [IsoConversionService] 참고)에 넘겨 변환하는 동안
/// 단계별 진행 상태([SsIsoConversionStep])를 Blue neon wireframe 미리보기와 함께 보여준다. 실패해도
/// 확정된 CAD 데이터([SsDataSlot.cadData])는 이 화면이 건드리지 않으므로 그대로 남고, 사용자는 다시
/// 시도하거나(일반 오류) CAD 편집 화면으로 돌아가 입력을 고칠 수 있다(입력 자체가 문제인 경우).
///
/// CAD↔ISO 최신 상태 추적(§완료조건)은 새로 만들지 않고 이미 있는 [SsProject.staleNotices]/
/// [SsDataDependencies](SS001부터 cadData→isoData로 이미 배선돼 있다)를 그대로 쓴다 — 이미 최신
/// 3D 모델이 있으면 다시 변환하지 않고 상태만 보여주고, CAD가 바뀌어 낡았으면 자동으로 다시 변환한다.
/// 재생성 시 사용자가 이미 돌려본 Orbit 카메라 시점과(향후 SS013이 추가할 3D 전용 편집 데이터) 이
/// WO가 모르는 payload 키는 그대로 보존한다(§완료조건 "사용자 디자인 데이터를 소실하지 않는다").
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/ss_ai_task.dart';
import '../core/ss_iso_conversion_controller.dart';
import '../core/ss_iso_conversion_step.dart';
import '../core/ss_project.dart';
import '../core/ss_project_store.dart';
import '../core/ss_router.dart' show SsStageHeader;
import '../core/ss_stage.dart';
import '../models/cad_floor_plan.dart' show resolveAutoScale;
import '../models/iso_conversion_result.dart';
import '../models/space_scene_v2.dart';
import '../models/ss_cad_scene.dart';
import '../models/ss_iso_camera_state.dart';
import '../services/iso_conversion_input_builder.dart';
import '../services/iso_conversion_service.dart';
import '../services/space_scene_builder_v2.dart';
import '../services/ss_project_store_provider.dart';
import '../theme/ss_master_theme.dart';
import '../widgets/iso_conversion/blue_neon_iso_preview.dart';

enum _IsoConversionLoad { loading, loaded, missingInput, error }

class IsoConversionScreen extends StatefulWidget {
  const IsoConversionScreen({super.key, this.projectId, this.projectStore, this.conversionService = const IsoConversionService()});

  /// 변환할 프로젝트 id(CAD 편집 화면에서 다음 단계로 넘어올 때 함께 전달된다).
  final String? projectId;

  /// 테스트에서 주입. 없으면 앱 공용 [SsProjectStoreProvider] 저장소.
  final SsProjectStore? projectStore;

  /// 실제 3D ISO 변환 엔진 호출(테스트에서 가짜 구현으로 교체 가능 — CadConversionScreen과 같은 패턴).
  final IsoConversionService conversionService;

  @override
  State<IsoConversionScreen> createState() => _IsoConversionScreenState();
}

class _IsoConversionScreenState extends State<IsoConversionScreen> {
  _IsoConversionLoad _state = _IsoConversionLoad.loading;
  SsProjectStore? _store;
  SsProject? _project;
  SsCadScene? _input;
  SsIsoCameraState? _previousCamera;
  Map<String, Object?>? _previousIsoPayload;
  bool _alreadyUpToDate = false;
  final SsIsoConversionController _controller = SsIsoConversionController();

  /// MASTER UI 9 — 변환이 끝나기 전에도(아직 [SsAiTask.lastGoodResult]가 없을 때) 이미 확정된 CAD
  /// 입력으로부터 즉시 계산할 수 있는 미리보기([buildSpaceSceneV2]는 결정적 순수 함수라 몇 번을 다시
  /// 불러도 안전하다 — 새 3D 엔진을 만들지 않는다, §구현 원칙). 단계 진행 중에도 Blue neon wireframe이
  /// 빈 화면이 아니라 실제 건물 형태를 보여주게 한다(MASTER UI 9 원본 — 변환 중에도 아이소 모델이
  /// 이미 보인다).
  SpaceSceneV2? _previewScene;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final pid = widget.projectId;
    if (pid == null) {
      setState(() => _state = _IsoConversionLoad.error);
      return;
    }
    try {
      final store = widget.projectStore ?? await SsProjectStoreProvider.instance.store();
      final project = await store.load(pid);
      if (project == null) {
        if (!mounted) return;
        setState(() => _state = _IsoConversionLoad.error);
        return;
      }
      final input = buildIsoConversionInput(project);
      if (!mounted) return;
      if (input == null) {
        setState(() {
          _store = store;
          _project = project;
          _state = _IsoConversionLoad.missingInput;
        });
        return;
      }
      final isoSlot = project.data[SsDataSlot.isoData];
      final stale = project.staleNotices().any((n) => n.stale == SsDataSlot.isoData);
      final upToDate = isoSlot != null && !stale;
      final previousCamera = isoSlot == null ? null : SsIsoCameraState.tryFromJson(isoSlot.payload['camera']);
      setState(() {
        _store = store;
        _project = project;
        _input = input;
        _previousCamera = previousCamera;
        _previousIsoPayload = isoSlot?.payload;
        _alreadyUpToDate = upToDate;
        _previewScene = _tryBuildPreviewScene(input);
        _state = _IsoConversionLoad.loaded;
      });
      if (!upToDate) unawaited(_startConversion(input, previousCamera));
    } catch (e, st) {
      // 네트워크를 쓰지 않는 화면이므로 네트워크 오류로 오분류하지 않는다 — 실제 원인은 로그로 남기고
      // 사용자에게는 일반 안내만 보인다.
      debugPrint('IsoConversionScreen._load 실패 (${e.runtimeType}): $e\n$st');
      if (!mounted) return;
      setState(() => _state = _IsoConversionLoad.error);
    }
  }

  /// [IsoConversionService.convert]가 내부적으로 하는 것과 같은 계산(CAD→3D)을 지연 없이 한 번 더
  /// 해서 미리보기 전용으로 쓴다 — 결과를 저장하지 않고 화면에만 쓰므로 실패해도(벽/공간이 없거나
  /// geometry 계산이 실패해도) 조용히 null을 돌려주고 기존 "스캔 중" 격자로 넘어간다(지어내지 않는다).
  SpaceSceneV2? _tryBuildPreviewScene(SsCadScene cadScene) {
    final plan = cadScene.plan;
    if (plan.walls.isEmpty && plan.rooms.isEmpty) return null;
    try {
      final scale = cadScene.scale ?? resolveAutoScale(plan, null);
      final scene = buildSpaceSceneV2(plan: plan, scale: scale, ceilingHeightMm: kIsoDefaultCeilingHeightMm);
      return scene.isEmpty ? null : scene;
    } catch (e, st) {
      debugPrint('IsoConversionScreen._tryBuildPreviewScene 실패 (${e.runtimeType}): $e\n$st');
      return null;
    }
  }

  Future<void> _startConversion(SsCadScene input, SsIsoCameraState? previousCamera) async {
    final status = await _controller.start(
      (onStep) => widget.conversionService.convert(input, previousCamera: previousCamera, onStep: onStep),
    );
    if (status == SsAiStatus.completed) unawaited(_onConversionCompleted());
  }

  Future<void> _retry() async {
    final status = await _controller.retry();
    if (status == SsAiStatus.completed) unawaited(_onConversionCompleted());
  }

  /// 사용자가 "다시 생성"을 눌렀을 때 — 이미 최신 상태라도 강제로 다시 변환한다. 기존 Orbit 카메라는
  /// 그대로 이어받는다(§완료조건 "사용자 디자인 데이터를 소실하지 않는다").
  Future<void> _regenerate() async {
    final input = _input;
    if (input == null) return;
    setState(() => _alreadyUpToDate = false);
    unawaited(_startConversion(input, _previousCamera));
  }

  Future<void> _onConversionCompleted() async {
    final project = _project;
    final store = _store;
    final result = _controller.task.lastGoodResult;
    if (project == null || store == null || result == null) return;
    final moved = project.withStageData(SsDataSlot.isoData, _isoDataPayload(result), label: '3D ISO 변환 결과').moveTo(SsStage.isoEditor);
    try {
      await store.save(moved);
    } catch (e, st) {
      debugPrint('IsoConversionScreen 결과 저장 실패 (${e.runtimeType}): $e\n$st');
    }
    _project = moved;
    if (!mounted) return;
    await Navigator.of(context).pushReplacementNamed(SsStage.isoEditor.routeName, arguments: widget.projectId);
  }

  /// SS012가 관리하는 필드만 덮어쓰고, 앞으로(SS013) 생길 수 있는 3D 전용 사용자 편집 데이터(가구
  /// 배치/마감재 선택 등 — 아직 이 WO 범위에는 없다)는 이전 payload에 있었다면 그대로 들고 간다 —
  /// 재생성이 사용자 디자인 데이터를 조용히 지우지 않게 하기 위함(§완료 조건).
  Map<String, Object?> _isoDataPayload(IsoConversionResult result) {
    final preserved = <String, Object?>{...?_previousIsoPayload};
    preserved.removeWhere((k, _) => _managedIsoDataKeys.contains(k));
    return {
      ...preserved,
      'kind': 'ssIsoScene',
      'camera': result.camera.toJson(),
      'warnings': result.warnings,
      'furnitureCount': result.furniture.length,
      'wallCount': result.scene.wallCount,
      'floorCount': result.scene.floorCount,
      'generatedAt': DateTime.now().toIso8601String(),
    };
  }

  static const Set<String> _managedIsoDataKeys = {'kind', 'camera', 'warnings', 'furnitureCount', 'wallCount', 'floorCount', 'generatedAt'};

  void _backToPreviousStage() {
    final project = _project;
    final previous = project == null ? null : SsFlows.previous(project.sourceType, SsStage.isoConversion);
    final navigator = Navigator.of(context);
    if (previous == null) {
      if (navigator.canPop()) navigator.pop();
      return;
    }
    navigator.pushReplacementNamed(previous.routeName, arguments: widget.projectId);
  }

  /// 이미 최신 3D 모델이 있을 때 "계속하기" — 다시 변환하지 않고 바로 3D 디자인(SS013)으로 넘어간다.
  /// 그래도 단계 이동은 저장해 둔다(이 화면에 어떤 경로로 다시 들어왔든 currentStage가 정확하게
  /// 남도록).
  Future<void> _goToIsoEditor() async {
    final project = _project;
    final store = _store;
    if (project != null && store != null) {
      final moved = project.moveTo(SsStage.isoEditor);
      try {
        await store.save(moved);
        _project = moved;
      } catch (e, st) {
        debugPrint('IsoConversionScreen 단계 이동 저장 실패 (${e.runtimeType}): $e\n$st');
      }
    }
    if (!mounted) return;
    await Navigator.of(context).pushReplacementNamed(SsStage.isoEditor.routeName, arguments: widget.projectId);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_state == _IsoConversionLoad.error) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('3D ISO로 변환할 작업을 불러오지 못했습니다.', key: Key('ssIsoConversionLoadError'), style: TextStyle(color: SsMasterTheme.textSecondary)),
            const SizedBox(height: 12),
            OutlinedButton(key: const Key('ssIsoConversionBackFromError'), onPressed: _backToPreviousStage, child: const Text('이전 단계로 돌아가기')),
          ],
        ),
      );
    }
    if (_state == _IsoConversionLoad.loading) {
      return const Center(child: CircularProgressIndicator(key: Key('ssIsoConversionLoading')));
    }
    if (_state == _IsoConversionLoad.missingInput) {
      return Padding(
        key: const Key('ssIsoConversionScreen'),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SsStageHeader(stage: SsStage.isoConversion),
            const SizedBox(height: 16),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '3D로 변환할 CAD 데이터가 없습니다. 먼저 CAD 편집을 완료해 주세요.',
                      key: Key('ssIsoConversionMissingInput'),
                      style: TextStyle(color: SsMasterTheme.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(key: const Key('ssIsoConversionBackToPrevious'), onPressed: _backToPreviousStage, child: const Text('이전 단계로 돌아가기')),
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
          key: const Key('ssIsoConversionScreen'),
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
        const Expanded(child: SsStageHeader(stage: SsStage.isoConversion)),
        IconButton(
          key: const Key('ssIsoConversionBack'),
          tooltip: '이전 단계로 돌아가기',
          onPressed: _backToPreviousStage,
          icon: const Icon(Icons.arrow_back, color: SsMasterTheme.textSecondary),
        ),
      ],
    );
  }

  /// MASTER UI 9 원본 — 진행 중에도 이미 건물 형태가 보인다. 아직 확정 결과가 없으면([SsAiTask.
  /// lastGoodResult]가 null — 변환 전/진행 중) CAD로부터 즉시 계산한 미리보기([_previewScene])를
  /// 먼저 쓰고, 그것도 없으면(벽/공간이 없는 등) 마지막으로 "스캔 중" 격자를 보여준다. 확정 결과가
  /// 생기면(또는 재생성 전 lastGoodResult) 그 값을 그대로 쓴다.
  Widget _buildPreview() {
    final scene = _controller.task.lastGoodResult?.scene ?? _previewScene;
    return Container(
      key: const Key('ssIsoConversionPreview'),
      decoration: BoxDecoration(color: const Color(0xFF081628), borderRadius: BorderRadius.circular(16), border: Border.all(color: SsMasterTheme.panelBorder)),
      clipBehavior: Clip.antiAlias,
      child: scene == null
          ? Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(painter: _SsIsoScanGridPainter()),
                const Center(child: Icon(Icons.view_in_ar_outlined, color: SsMasterTheme.neonBlue, size: 64)),
              ],
            )
          : BlueNeonIsoPreview(scene: scene),
    );
  }

  Widget _buildUpToDatePanel() {
    return Container(
      key: const Key('ssIsoConversionUpToDatePanel'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: SsMasterTheme.panel, borderRadius: BorderRadius.circular(16), border: Border.all(color: SsMasterTheme.panelBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline, color: SsMasterTheme.neonBlue, size: 28),
          const SizedBox(height: 12),
          const Text('이미 최신 3D 모델이 있습니다.', key: Key('ssIsoConversionUpToDateTitle'), style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('CAD가 바뀌지 않아 다시 변환할 필요가 없습니다.', key: Key('ssIsoConversionUpToDateMessage'), style: TextStyle(color: SsMasterTheme.textSecondary, fontSize: 12)),
          const SizedBox(height: 18),
          ElevatedButton(key: const Key('ssIsoConversionContinue'), onPressed: () => unawaited(_goToIsoEditor()), child: const Text('3D 디자인 계속하기')),
          const SizedBox(height: 10),
          OutlinedButton(key: const Key('ssIsoConversionRegenerate'), onPressed: () => unawaited(_regenerate()), child: const Text('다시 생성')),
        ],
      ),
    );
  }

  Widget _buildStatusPanel(SsAiStatus status) {
    final failed = status == SsAiStatus.failed || status == SsAiStatus.retryable || status == SsAiStatus.inputFixNeeded;
    final title = failed ? '3D ISO로 변환하지 못했습니다' : 'AI가 도면을 3D 아이소로 변환하고 있습니다.';
    final subtitle = failed
        ? (_controller.task.message ?? '다시 시도하거나 이전 단계로 돌아가 CAD를 확인해 주세요.')
        : '공간의 구조와 요소를 분석하여 3D 아이소 모델로 생성합니다.';
    return Container(
      key: const Key('ssIsoConversionStatusPanel'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: SsMasterTheme.panel, borderRadius: BorderRadius.circular(16), border: Border.all(color: SsMasterTheme.panelBorder)),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(failed ? Icons.error_outline : Icons.view_in_ar_outlined, color: failed ? Colors.redAccent : SsMasterTheme.neonBlue, size: 28),
            const SizedBox(height: 12),
            Text(title, key: const Key('ssIsoConversionStatusTitle'), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(subtitle, key: const Key('ssIsoConversionStatusMessage'), style: const TextStyle(color: SsMasterTheme.textSecondary, fontSize: 12)),
            const SizedBox(height: 18),
            if (!failed) _buildProgressBar(),
            const SizedBox(height: 18),
            for (final step in SsIsoConversionStep.values) _buildStepRow(step),
            if (failed) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(key: const Key('ssIsoConversionBackFromFail'), onPressed: _backToPreviousStage, child: const Text('이전 단계로 돌아가기')),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      key: const Key('ssIsoConversionRetry'),
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
        Text('${(p * 100).round()}%', key: const Key('ssIsoConversionProgressPercent'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _buildStepRow(SsIsoConversionStep step) {
    final done = _controller.completedSteps.contains(step);
    final active = _controller.currentStep == step;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle : (active ? Icons.radio_button_checked : Icons.radio_button_unchecked),
            key: Key('ssIsoConversionStep_${step.name}'),
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

/// Blue neon 진행 화면 — 결과가 아직 없을 때(첫 프레임) 보여주는 "스캔 중" 격자(MASTER UI 7/4-2-1과
/// 같은 시각언어, CadConversionScreen._SsCadScanGridPainter와 같은 생각).
class _SsIsoScanGridPainter extends CustomPainter {
  _SsIsoScanGridPainter();

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
  bool shouldRepaint(covariant _SsIsoScanGridPainter oldDelegate) => false;
}
