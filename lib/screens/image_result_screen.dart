/// SS007 — MASTER UI 4-2-2(이미지 변환 완료). ImageRenderingScreen이 만든 최종 이미지를 원본과
/// Before/After로 비교하고, 수정 작업으로 돌아가거나 완료하거나, JPG/PNG로 내보낼 수 있다.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/ss_editing.dart';
import '../core/ss_project.dart';
import '../core/ss_project_store.dart';
import '../core/ss_router.dart';
import '../core/ss_stage.dart';
import '../services/ss_image_export_service.dart';
import '../services/ss_project_store_provider.dart';
import '../theme/ss_master_theme.dart';

enum _ResultLoad { loading, loaded, error }

class ImageResultScreen extends StatefulWidget {
  const ImageResultScreen({super.key, this.projectId, this.projectStore, this.exportService = const SsImageExportService()});

  /// 결과를 확인할 프로젝트 id.
  final String? projectId;

  /// 테스트에서 주입. 없으면 앱 공용 [SsProjectStoreProvider] 저장소.
  final SsProjectStore? projectStore;

  /// 파일 내보내기(테스트에서 가짜 구현으로 교체 가능 — file_saver는 테스트 환경에 실제 플랫폼 채널이 없다).
  final SsImageExportService exportService;

  @override
  State<ImageResultScreen> createState() => _ImageResultScreenState();
}

class _ImageResultScreenState extends State<ImageResultScreen> {
  _ResultLoad _state = _ResultLoad.loading;
  SsProjectStore? _store;
  SsProject? _project;
  Uint8List? _originalBytes;
  Uint8List? _resultBytes;
  bool _compareMode = false;
  SsExportFormat _format = SsExportFormat.png;
  double _jpgQuality = 90;
  bool _chooseLocation = false;
  bool _exporting = false;
  SsExportJob? _exportJob;
  final TextEditingController _fileName = TextEditingController(text: 'space_shift_result');

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final pid = widget.projectId;
    if (pid == null) {
      setState(() => _state = _ResultLoad.error);
      return;
    }
    try {
      final store = widget.projectStore ?? await SsProjectStoreProvider.instance.store();
      final project = await store.load(pid);
      if (project == null) {
        if (!mounted) return;
        setState(() => _state = _ResultLoad.error);
        return;
      }
      final srcB64 = project.data[SsDataSlot.sourceData]?.payload['imageBase64'];
      final renderB64 = project.data[SsDataSlot.renderData]?.payload['imageBase64'];
      Uint8List? original;
      Uint8List? result;
      if (srcB64 is String) {
        try {
          original = base64Decode(srcB64);
        } catch (e, st) {
          debugPrint('ImageResultScreen 원본 디코딩 실패 (${e.runtimeType}): $e\n$st');
        }
      }
      if (renderB64 is String) {
        try {
          result = base64Decode(renderB64);
        } catch (e, st) {
          debugPrint('ImageResultScreen 렌더링 결과 디코딩 실패 (${e.runtimeType}): $e\n$st');
        }
      }
      if (original == null || result == null) {
        if (!mounted) return;
        setState(() => _state = _ResultLoad.error);
        return;
      }
      if (!mounted) return;
      setState(() {
        _store = store;
        _project = project;
        _originalBytes = original;
        _resultBytes = result;
        _state = _ResultLoad.loaded;
      });
    } catch (e, st) {
      debugPrint('ImageResultScreen._load 실패 (${e.runtimeType}): $e\n$st');
      if (!mounted) return;
      setState(() => _state = _ResultLoad.error);
    }
  }

  Future<void> _export() async {
    final bytes = _resultBytes;
    if (bytes == null || _exporting) return;
    final name = _fileName.text.trim().isEmpty ? 'space_shift_result' : _fileName.text.trim();
    final job = SsExportJob(fileName: name, format: _format);
    setState(() {
      _exporting = true;
      _exportJob = job.started();
    });
    try {
      final savedTo = await widget.exportService.save(bytes, job, jpgQuality: _jpgQuality.round(), chooseLocation: _chooseLocation);
      if (!mounted) return;
      if (savedTo == null) {
        // 저장 위치 선택을 취소한 경우 — 실패가 아니라 그냥 처음 상태로 돌아간다.
        setState(() {
          _exporting = false;
          _exportJob = null;
        });
        return;
      }
      setState(() {
        _exporting = false;
        _exportJob = job.succeeded(savedTo);
      });
    } catch (e, st) {
      // 로컬 파일 저장 실패를 "네트워크 오류"로 잘못 알리지 않는다 — 실제 원인은 로그로, 사용자에겐
      // 일반 안내만 보여준다.
      debugPrint('ImageResultScreen 내보내기 실패 (${e.runtimeType}): $e\n$st');
      if (!mounted) return;
      setState(() {
        _exporting = false;
        _exportJob = job.failedWith('파일을 저장하지 못했습니다. 다시 시도해주세요.');
      });
    }
  }

  void _backToEditing() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.pushReplacementNamed(SsStage.imageEditing.routeName, arguments: widget.projectId);
    }
  }

  Future<void> _complete() async {
    final store = _store;
    final project = _project;
    if (store != null && project != null) {
      try {
        await store.save(project);
      } catch (e, st) {
        debugPrint('ImageResultScreen 완료 저장 실패 (${e.runtimeType}): $e\n$st');
      }
    }
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(SsStage.projectManagement.routeName, (route) => route.isFirst);
  }

  @override
  void dispose() {
    _fileName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_state == _ResultLoad.error) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('완성된 이미지를 불러오지 못했습니다.', key: Key('ssResultLoadError'), style: TextStyle(color: SsMasterTheme.textSecondary)),
            const SizedBox(height: 12),
            OutlinedButton(key: const Key('ssResultBackToEditFromError'), onPressed: _backToEditing, child: const Text('이미지 디자인으로 돌아가기')),
          ],
        ),
      );
    }
    if (_state == _ResultLoad.loading) {
      return const Center(child: CircularProgressIndicator(key: Key('ssResultLoading')));
    }
    return Padding(
      key: const Key('ssResultScreen'),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SsStageHeader(stage: SsStage.imageResult),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: _buildImageArea()),
                const SizedBox(width: 20),
                SizedBox(width: 320, child: _buildSidePanel()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageArea() {
    final result = _resultBytes!;
    final original = _originalBytes!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          key: const Key('ssResultCompareToggle'),
          onPressed: () => setState(() => _compareMode = !_compareMode),
          icon: Icon(_compareMode ? Icons.visibility_outlined : Icons.compare_outlined, size: 18),
          label: Text(_compareMode ? '결과만 보기' : '원본과 비교(Before/After)'),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _compareMode
              ? Row(
                  children: [
                    Expanded(child: _labeledImage('원본(Before)', original, imageKey: const Key('ssResultBeforeImage'))),
                    const SizedBox(width: 12),
                    Expanded(child: _labeledImage('결과(After)', result, imageKey: const Key('ssResultAfterImage'))),
                  ],
                )
              : _labeledImage(null, result, imageKey: const Key('ssResultFinalImage')),
        ),
      ],
    );
  }

  Widget _labeledImage(String? label, Uint8List bytes, {required Key imageKey}) {
    return Container(
      decoration: BoxDecoration(color: const Color(0xFF081628), borderRadius: BorderRadius.circular(16), border: Border.all(color: SsMasterTheme.panelBorder)),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(bytes, key: imageKey, fit: BoxFit.contain, gaplessPlayback: true),
          if (label != null)
            Positioned(
              left: 10,
              top: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(gradient: SsMasterTheme.selectedItem, borderRadius: BorderRadius.circular(8)),
                child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSidePanel() {
    return Container(
      key: const Key('ssResultSidePanel'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: SsMasterTheme.panel, borderRadius: BorderRadius.circular(16), border: Border.all(color: SsMasterTheme.panelBorder)),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('파일 내보내기', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            const Text('형식', style: TextStyle(color: SsMasterTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final f in const [SsExportFormat.png, SsExportFormat.jpg])
                  ChoiceChip(
                    key: Key('ssResultFormat_${f.name}'),
                    label: Text(f.label, style: const TextStyle(fontSize: 12)),
                    selected: _format == f,
                    onSelected: (_) => setState(() => _format = f),
                  ),
              ],
            ),
            if (_format == SsExportFormat.jpg) ...[
              const SizedBox(height: 14),
              Text('화질 ${_jpgQuality.round()}', style: const TextStyle(color: SsMasterTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w700)),
              Slider(
                key: const Key('ssResultJpgQuality'),
                value: _jpgQuality,
                min: 50,
                max: 100,
                divisions: 50,
                label: '${_jpgQuality.round()}',
                onChanged: (v) => setState(() => _jpgQuality = v),
              ),
            ],
            const SizedBox(height: 14),
            const Text('파일 이름', style: TextStyle(color: SsMasterTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            TextField(
              key: const Key('ssResultFileName'),
              controller: _fileName,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(isDense: true, hintText: '파일 이름'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Checkbox(key: const Key('ssResultChooseLocation'), value: _chooseLocation, onChanged: (v) => setState(() => _chooseLocation = v ?? false)),
                const Expanded(child: Text('저장 위치 직접 선택', style: TextStyle(color: Colors.white, fontSize: 12))),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                key: const Key('ssResultExportButton'),
                onPressed: _exporting ? null : () => unawaited(_export()),
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: Text(_exporting ? '내보내는 중…' : '내보내기'),
              ),
            ),
            if (_exportJob != null) ...[const SizedBox(height: 10), _buildExportStatusBanner(_exportJob!)],
            const SizedBox(height: 20),
            const Divider(color: SsMasterTheme.panelBorder),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(key: const Key('ssResultBackToEdit'), onPressed: _backToEditing, child: const Text('수정 작업으로 돌아가기')),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                key: const Key('ssResultComplete'),
                onPressed: () => unawaited(_complete()),
                icon: const Icon(Icons.check),
                label: const Text('완료하기'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExportStatusBanner(SsExportJob job) {
    final (color, text) = switch (job.status) {
      SsExportStatus.exporting => (SsMasterTheme.neonBlue, '내보내는 중…'),
      SsExportStatus.succeeded => (Colors.greenAccent, '저장했습니다 (${job.fullName})'),
      SsExportStatus.failed => (Colors.redAccent, job.error ?? '내보내기에 실패했습니다.'),
      SsExportStatus.pending => (SsMasterTheme.textSecondary, '내보낼 준비가 되었습니다.'),
    };
    return Container(
      key: const Key('ssResultExportStatus'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withValues(alpha: 0.4))),
      child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
