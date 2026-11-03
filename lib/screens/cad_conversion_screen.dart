/// SS010 — MASTER UI 7(평면도 CAD변환). SS009(평면도 확인·보정)/SS005(직접 그리기)가 확정한 공간
/// 데이터를 기존 CAD/DXF 엔진([CadConversionService] — Geometry Validation([TopologyValidator])·
/// 치수/Scale([resolveAutoScale])·CAD/DXF 생성([E2eDxfExporter])을 그대로 재사용)에 넘겨 변환하는 동안
/// 단계별 진행 상태([SsCadConversionStep])를 Blue line-only CAD 미리보기와 함께 보여준다. 실패해도
/// 확정된 공간 데이터(SsDataSlot.userCorrections/recognitionData)는 이 화면이 건드리지 않으므로 그대로
/// 남고, 사용자는 다시 시도하거나(일반 오류) SS009/SS005로 돌아가 입력을 고칠 수 있다(입력 자체가
/// 문제인 경우 — §완료 조건 "실패/재시도 FLOW"). 완료되면 결과를 SsDataSlot.cadData에 저장하고 CAD
/// 편집 화면(MASTER UI 8, SS011)으로 넘어간다.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/ss_ai_task.dart';
import '../core/ss_cad_conversion_controller.dart';
import '../core/ss_cad_conversion_step.dart';
import '../core/ss_project.dart';
import '../core/ss_project_store.dart';
import '../core/ss_router.dart' show SsStageHeader;
import '../core/ss_stage.dart';
import '../models/cad_conversion_result.dart';
import '../models/ss_spatial_model_json.dart';
import '../services/cad_conversion_input_builder.dart';
import '../services/cad_conversion_service.dart';
import '../services/ss_project_store_provider.dart';
import '../theme/ss_master_theme.dart';
import '../widgets/cad_conversion/blue_line_cad_preview.dart';

enum _CadConversionLoad { loading, loaded, error }

class CadConversionScreen extends StatefulWidget {
  const CadConversionScreen({super.key, this.projectId, this.projectStore, this.conversionService = const CadConversionService()});

  /// 변환할 프로젝트 id(SS009/SS005에서 다음 단계로 넘어올 때 함께 전달된다).
  final String? projectId;

  /// 테스트에서 주입. 없으면 앱 공용 [SsProjectStoreProvider] 저장소.
  final SsProjectStore? projectStore;

  /// 실제 CAD 변환 엔진 호출(테스트에서 가짜 구현으로 교체 가능 — ImageRenderingScreen과 같은 패턴).
  final CadConversionService conversionService;

  @override
  State<CadConversionScreen> createState() => _CadConversionScreenState();
}

class _CadConversionScreenState extends State<CadConversionScreen> {
  _CadConversionLoad _state = _CadConversionLoad.loading;
  SsProjectStore? _store;
  SsProject? _project;
  CadConversionInput? _input;
  final SsCadConversionController _controller = SsCadConversionController();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final pid = widget.projectId;
    if (pid == null) {
      setState(() => _state = _CadConversionLoad.error);
      return;
    }
    try {
      final store = widget.projectStore ?? await SsProjectStoreProvider.instance.store();
      final project = await store.load(pid);
      if (project == null) {
        if (!mounted) return;
        setState(() => _state = _CadConversionLoad.error);
        return;
      }
      final input = buildCadConversionInput(project);
      if (!mounted) return;
      setState(() {
        _store = store;
        _project = project;
        _input = input;
        _state = _CadConversionLoad.loaded;
      });
      if (input != null) unawaited(_startConversion(input));
    } catch (e, st) {
      // 네트워크를 쓰지 않는 화면이므로 네트워크 오류로 오분류하지 않는다 — 실제 원인은 로그로 남기고
      // 사용자에게는 일반 안내만 보인다.
      debugPrint('CadConversionScreen._load 실패 (${e.runtimeType}): $e\n$st');
      if (!mounted) return;
      setState(() => _state = _CadConversionLoad.error);
    }
  }

  Future<void> _startConversion(CadConversionInput input) async {
    final status = await _controller.start(
      (onStep) => widget.conversionService.convert(input.model, knownScale: input.knownScale, onStep: onStep),
    );
    if (status == SsAiStatus.completed) unawaited(_onConversionCompleted());
  }

  Future<void> _retry() async {
    final status = await _controller.retry();
    if (status == SsAiStatus.completed) unawaited(_onConversionCompleted());
  }

  Future<void> _onConversionCompleted() async {
    final project = _project;
    final store = _store;
    final result = _controller.task.lastGoodResult;
    if (project == null || store == null || result == null) return;
    final moved = project.withStageData(SsDataSlot.cadData, _cadDataPayload(result), label: 'CAD 변환 결과').moveTo(SsStage.cadEditor);
    try {
      await store.save(moved);
    } catch (e, st) {
      debugPrint('CadConversionScreen 결과 저장 실패 (${e.runtimeType}): $e\n$st');
    }
    _project = moved;
    if (!mounted) return;
    await Navigator.of(context).pushReplacementNamed(SsStage.cadEditor.routeName, arguments: widget.projectId);
  }

  Map<String, Object?> _cadDataPayload(CadConversionResult result) => {
    'kind': 'cadFloorPlan',
    'model': ssSpatialModelToJson(result.validatedModel),
    'scale': {
      'mmPerPixel': result.scale.mmPerPixel,
      'source': result.scale.source.name,
      'referenceLengthMm': result.scale.referenceLengthMm,
      'referenceStart': {'x': result.scale.referenceStart.x, 'y': result.scale.referenceStart.y},
      'referenceEnd': {'x': result.scale.referenceEnd.x, 'y': result.scale.referenceEnd.y},
    },
    'dxfContent': result.dxfContent,
    'isScaled': result.isScaled,
    'warnings': result.plan.warnings,
  };

  void _backToPreviousStage() {
    final project = _project;
    final previous = project == null ? null : SsFlows.previous(project.sourceType, SsStage.cadConversion);
    final navigator = Navigator.of(context);
    if (previous == null) {
      if (navigator.canPop()) navigator.pop();
      return;
    }
    navigator.pushReplacementNamed(previous.routeName, arguments: widget.projectId);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_state == _CadConversionLoad.error) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('CAD 변환할 작업을 불러오지 못했습니다.', key: Key('ssCadConversionLoadError'), style: TextStyle(color: SsMasterTheme.textSecondary)),
            const SizedBox(height: 12),
            OutlinedButton(key: const Key('ssCadConversionBackFromError'), onPressed: _backToPreviousStage, child: const Text('이전 단계로 돌아가기')),
          ],
        ),
      );
    }
    if (_state == _CadConversionLoad.loading) {
      return const Center(child: CircularProgressIndicator(key: Key('ssCadConversionLoading')));
    }
    if (_input == null) {
      return Padding(
        key: const Key('ssCadConversionScreen'),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SsStageHeader(stage: SsStage.cadConversion),
            const SizedBox(height: 16),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '변환할 확정된 평면도 데이터가 없습니다. 이전 단계에서 평면도를 완성해 주세요.',
                      key: Key('ssCadConversionMissingInput'),
                      style: TextStyle(color: SsMasterTheme.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(key: const Key('ssCadConversionBackToPrevious'), onPressed: _backToPreviousStage, child: const Text('이전 단계로 돌아가기')),
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
          key: const Key('ssCadConversionScreen'),
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
                    SizedBox(width: 340, child: _buildStatusPanel(status)),
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
        const Expanded(child: SsStageHeader(stage: SsStage.cadConversion)),
        IconButton(
          key: const Key('ssCadConversionBack'),
          tooltip: '이전 단계로 돌아가기',
          onPressed: _backToPreviousStage,
          icon: const Icon(Icons.arrow_back, color: SsMasterTheme.textSecondary),
        ),
      ],
    );
  }

  Widget _buildPreview() {
    final result = _controller.task.lastGoodResult;
    return Container(
      key: const Key('ssCadConversionPreview'),
      decoration: BoxDecoration(color: const Color(0xFF081628), borderRadius: BorderRadius.circular(16), border: Border.all(color: SsMasterTheme.panelBorder)),
      clipBehavior: Clip.antiAlias,
      child: result == null
          ? Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(painter: _SsCadScanGridPainter()),
                const Center(child: Icon(Icons.blur_on, color: SsMasterTheme.neonBlue, size: 64)),
              ],
            )
          : BlueLineCadPreview(plan: result.plan, scale: result.scale),
    );
  }

  Widget _buildStatusPanel(SsAiStatus status) {
    final failed = status == SsAiStatus.failed || status == SsAiStatus.retryable || status == SsAiStatus.inputFixNeeded;
    final title = failed ? 'CAD로 변환하지 못했습니다' : 'AI가 도면을 분석하고 있습니다.';
    final subtitle = failed
        ? (_controller.task.message ?? '다시 시도하거나 이전 단계로 돌아가 입력을 확인해 주세요.')
        : '공간의 구조와 요소를 인식하여 CAD 도면으로 변환합니다.';
    return Container(
      key: const Key('ssCadConversionStatusPanel'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: SsMasterTheme.panel, borderRadius: BorderRadius.circular(16), border: Border.all(color: SsMasterTheme.panelBorder)),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(failed ? Icons.error_outline : Icons.view_in_ar_outlined, color: failed ? Colors.redAccent : SsMasterTheme.neonBlue, size: 28),
            const SizedBox(height: 12),
            Text(title, key: const Key('ssCadConversionStatusTitle'), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(subtitle, key: const Key('ssCadConversionStatusMessage'), style: const TextStyle(color: SsMasterTheme.textSecondary, fontSize: 12)),
            const SizedBox(height: 18),
            if (!failed) _buildProgressBar(),
            const SizedBox(height: 18),
            for (final step in SsCadConversionStep.values) _buildStepRow(step),
            if (failed) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(key: const Key('ssCadConversionBackFromFail'), onPressed: _backToPreviousStage, child: const Text('이전 단계로 돌아가기')),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      key: const Key('ssCadConversionRetry'),
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
        Text('${(p * 100).round()}%', key: const Key('ssCadConversionProgressPercent'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _buildStepRow(SsCadConversionStep step) {
    final done = _controller.completedSteps.contains(step);
    final active = _controller.currentStep == step;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle : (active ? Icons.radio_button_checked : Icons.radio_button_unchecked),
            key: Key('ssCadConversionStep_${step.name}'),
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

/// Blue line-only CAD 진행 화면 — 결과가 아직 없을 때(첫 프레임) 보여주는 "스캔 중" 격자(MASTER UI
/// 4-2-1의 같은 시각언어, ImageRenderingScreen._SsRenderGridPainter와 같은 생각).
class _SsCadScanGridPainter extends CustomPainter {
  _SsCadScanGridPainter();

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
  bool shouldRepaint(covariant _SsCadScanGridPainter oldDelegate) => false;
}
