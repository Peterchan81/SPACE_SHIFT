/// SS007 — MASTER UI 4-2-1(이미지 변환: AI 렌더링 진행). SS006에서 완료한 편집 지시([SsPhotoScene])를
/// 실제 이미지로 렌더링하는 동안 단계별 진행 상태([SsRenderStep])를 보여준다. 실패해도 원본 사진과 편집
/// 지시는 이 화면이 건드리지 않으므로 그대로 남고(§5·§8 — SsProject.sourceData/userCorrections 보존),
/// 사용자는 재시도하거나 편집 화면으로 안전하게 돌아갈 수 있다. 완료되면 결과를 SsDataSlot.renderData에
/// 저장하고 이미지 결과 화면(MASTER UI 4-2-2, ImageResultScreen)으로 넘어간다.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/ss_ai_task.dart';
import '../core/ss_image_render_controller.dart';
import '../core/ss_project.dart';
import '../core/ss_project_store.dart';
import '../core/ss_render_step.dart';
import '../core/ss_router.dart';
import '../core/ss_stage.dart';
import '../models/ss_photo_scene.dart';
import '../services/ss_photo_render_service.dart';
import '../services/ss_project_store_provider.dart';
import '../theme/ss_master_theme.dart';

enum _RenderLoad { loading, loaded, error }

class ImageRenderingScreen extends StatefulWidget {
  const ImageRenderingScreen({super.key, this.projectId, this.projectStore, this.renderService = const SsPhotoRenderService()});

  /// 렌더링할 프로젝트 id(SS006에서 완료하기를 누를 때 함께 넘어온다).
  final String? projectId;

  /// 테스트에서 주입. 없으면 앱 공용 [SsProjectStoreProvider] 저장소.
  final SsProjectStore? projectStore;

  /// 실제 AI 렌더링 호출(테스트에서 가짜 구현으로 교체 가능 — PhotoDesignEditorScreen과 같은 패턴).
  final SsPhotoRenderService renderService;

  @override
  State<ImageRenderingScreen> createState() => _ImageRenderingScreenState();
}

class _ImageRenderingScreenState extends State<ImageRenderingScreen> {
  _RenderLoad _state = _RenderLoad.loading;
  SsProjectStore? _store;
  SsProject? _project;
  SsPhotoScene? _scene;
  final SsImageRenderController _controller = SsImageRenderController();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final pid = widget.projectId;
    if (pid == null) {
      setState(() => _state = _RenderLoad.error);
      return;
    }
    try {
      final store = widget.projectStore ?? await SsProjectStoreProvider.instance.store();
      final project = await store.load(pid);
      if (project == null) {
        if (!mounted) return;
        setState(() => _state = _RenderLoad.error);
        return;
      }
      final b64 = project.data[SsDataSlot.sourceData]?.payload['imageBase64'];
      Uint8List? bytes;
      if (b64 is String) {
        try {
          bytes = base64Decode(b64);
        } catch (e, st) {
          debugPrint('ImageRenderingScreen 원본 사진 디코딩 실패 (${e.runtimeType}): $e\n$st');
        }
      }
      if (bytes == null) {
        if (!mounted) return;
        setState(() => _state = _RenderLoad.error);
        return;
      }
      final scene = SsPhotoScene.fromEditJson(bytes, project.data[SsDataSlot.userCorrections]?.payload['edit']);
      if (!mounted) return;
      setState(() {
        _store = store;
        _project = project;
        _scene = scene;
        _state = _RenderLoad.loaded;
      });
      unawaited(_startRender());
    } catch (e, st) {
      debugPrint('ImageRenderingScreen._load 실패 (${e.runtimeType}): $e\n$st');
      if (!mounted) return;
      setState(() => _state = _RenderLoad.error);
    }
  }

  Future<void> _startRender() async {
    final scene = _scene;
    if (scene == null) return;
    final status = await _controller.start((onStep) => widget.renderService.render(scene, onStep: onStep));
    if (status == SsAiStatus.completed) unawaited(_onRenderCompleted());
  }

  Future<void> _retry() async {
    final status = await _controller.retry();
    if (status == SsAiStatus.completed) unawaited(_onRenderCompleted());
  }

  Future<void> _onRenderCompleted() async {
    final project = _project;
    final store = _store;
    final bytes = _controller.task.lastGoodResult;
    if (project == null || store == null || bytes == null) return;
    final moved = project.withStageData(SsDataSlot.renderData, {'imageBase64': base64Encode(bytes)}, label: 'AI 렌더링 결과').moveTo(SsStage.imageResult);
    try {
      await store.save(moved);
    } catch (e, st) {
      debugPrint('ImageRenderingScreen 렌더링 결과 저장 실패 (${e.runtimeType}): $e\n$st');
    }
    _project = moved;
    if (!mounted) return;
    final pid = widget.projectId;
    await Navigator.of(context).pushReplacementNamed(SsStage.imageResult.routeName, arguments: pid);
  }

  void _backToEditing() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.pushReplacementNamed(SsStage.imageEditing.routeName, arguments: widget.projectId);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_state == _RenderLoad.error) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('렌더링할 작업을 불러오지 못했습니다.', key: Key('ssRenderLoadError'), style: TextStyle(color: SsMasterTheme.textSecondary)),
            const SizedBox(height: 12),
            OutlinedButton(key: const Key('ssRenderBackToEditFromError'), onPressed: _backToEditing, child: const Text('이미지 디자인으로 돌아가기')),
          ],
        ),
      );
    }
    if (_state == _RenderLoad.loading) {
      return const Center(child: CircularProgressIndicator(key: Key('ssRenderLoading')));
    }
    final scene = _scene!;
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final status = _controller.task.status;
        return Padding(
          key: const Key('ssRenderScreen'),
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
                    Expanded(flex: 3, child: _buildPreview(scene)),
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
        const Expanded(child: SsStageHeader(stage: SsStage.imageRendering)),
        IconButton(
          key: const Key('ssRenderBackToEdit'),
          tooltip: '수정 작업으로 돌아가기',
          onPressed: _backToEditing,
          icon: const Icon(Icons.edit_outlined, color: SsMasterTheme.textSecondary),
        ),
      ],
    );
  }

  Widget _buildPreview(SsPhotoScene scene) {
    return Container(
      key: const Key('ssRenderPreview'),
      decoration: BoxDecoration(color: const Color(0xFF081628), borderRadius: BorderRadius.circular(16), border: Border.all(color: SsMasterTheme.panelBorder)),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColorFiltered(
            colorFilter: const ColorFilter.mode(Color(0xFF1C3FFF), BlendMode.color),
            child: Image.memory(scene.imageBytes, fit: BoxFit.cover, gaplessPlayback: true),
          ),
          Container(color: SsMasterTheme.neonBlue.withValues(alpha: 0.12)),
          Positioned.fill(child: CustomPaint(painter: _SsRenderGridPainter())),
        ],
      ),
    );
  }

  Widget _buildStatusPanel(SsAiStatus status) {
    final failed = status == SsAiStatus.failed || status == SsAiStatus.retryable;
    return Container(
      key: const Key('ssRenderStatusPanel'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: SsMasterTheme.panel, borderRadius: BorderRadius.circular(16), border: Border.all(color: SsMasterTheme.panelBorder)),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(failed ? Icons.error_outline : Icons.auto_awesome, color: failed ? Colors.redAccent : SsMasterTheme.neonBlue, size: 28),
            const SizedBox(height: 12),
            Text(
              failed ? '이미지를 만들지 못했습니다' : '이미지를 생성하고 있습니다.',
              key: const Key('ssRenderStatusTitle'),
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              failed ? (_controller.task.message ?? '다시 시도하거나 수정 작업으로 돌아갈 수 있습니다.') : '사용자의 수정 사항을 반영하여 새로운 이미지를 렌더링하고 있습니다.',
              key: const Key('ssRenderStatusMessage'),
              style: const TextStyle(color: SsMasterTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 18),
            if (!failed) _buildProgressBar(),
            const SizedBox(height: 18),
            for (final step in SsRenderStep.values) _buildStepRow(step),
            if (failed) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(key: const Key('ssRenderBackToEditFromFail'), onPressed: _backToEditing, child: const Text('수정 작업으로 돌아가기')),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      key: const Key('ssRenderRetry'),
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
        Text('${(p * 100).round()}%', key: const Key('ssRenderProgressPercent'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _buildStepRow(SsRenderStep step) {
    final done = _controller.completedSteps.contains(step);
    final active = _controller.currentStep == step;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle : (active ? Icons.radio_button_checked : Icons.radio_button_unchecked),
            key: Key('ssRenderStep_${step.name}'),
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

/// Blue line-style room preview 위에 겹치는 은은한 격자 — MASTER UI 4-2-1의 "스캔 중" 시각언어.
class _SsRenderGridPainter extends CustomPainter {
  const _SsRenderGridPainter();

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
  bool shouldRepaint(covariant _SsRenderGridPainter oldDelegate) => false;
}
