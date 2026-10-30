/// SS008 — MASTER UI 5(평면도 업로드). 사용자가 평면도 이미지를 올리면,
/// 기존에 검증된 평면도 분석 파이프라인([FloorPlanAnalysisService] — run-
/// length 벽/문/창 검출 + flood-fill 방 검출)과 규칙 기반 보조 해석
/// ([SSSpatialModelBuilder] · [EnvelopeFirstInterpreter])을 그대로 재사용해
/// 공간/벽/문/창/가구/설비를 인식하고, 좌측 원본·우측 AI 인식 결과를 나란히
/// 비교할 수 있게 한다.
///
/// - 인식 결과는 "구조화된 공간 모델"([SSSpatialModel])로 프로젝트의 AI 인식
///   데이터 칸(SsDataSlot.recognitionData)에 저장한다([ssSpatialModelToJson]).
/// - "수정하기"는 곧바로 다음 보정 단계(SS009, [SsStage.floorPlanReview])로
///   이동한다.
/// - "CAD 파일로 변환"은 사용자가 결과를 확인했다는 확인 창을 거친 뒤에만
///   다음 단계로 진행한다(CAD 변환 자체의 실행은 SS009/SS010 범위).
/// - 공통 상단바([SsTopBar])·좌측 메뉴([SsNavRail])는 [SsRouter]가
///   [SsStageScreen]으로 이미 감싸 준다 — 이 화면은 그 안쪽만 그린다.
/// - MASTER UI 5 원본 패널 툴바(회전/자르기/확대-축소/전체화면)와 우측 결과
///   패널의 "인식된 요소"/"레이어 표시" 2단 구성을 반영한다. 자르기는 아직
///   실제 자르기 기능이 없으므로(§SS008 범위 밖) 도움말/알림 아이콘과 같은
///   원칙으로 비활성(onPressed: null)만 두고 가짜 동작을 만들지 않는다.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/ss_project.dart';
import '../core/ss_project_store.dart';
import '../core/ss_router.dart' show SsStageHeader;
import '../core/ss_stage.dart';
import '../models/floor_plan_file.dart';
import '../models/floor_plan_geometry.dart';
import '../models/ss_spatial_model.dart';
import '../models/ss_spatial_model_json.dart';
import '../services/floor_plan_analysis_service.dart';
import '../services/floor_plan_upload_service.dart';
import '../services/ss_project_store_provider.dart';
import '../services/ss_recognition_summary.dart';
import '../services/ss_spatial_model_builder.dart';
import '../theme/ss_master_theme.dart';

class FloorPlanUploadScreen extends StatefulWidget {
  const FloorPlanUploadScreen({
    super.key,
    this.projectId,
    this.projectStore,
    this.uploadService = const FloorPlanUploadService(),
    this.analysisService = const FloorPlanAnalysisService(),
    this.spatialModelBuilder = const SSSpatialModelBuilder(),
  });

  /// 연 프로젝트 id(없으면 프로젝트 없이 미리보기만 — 자동저장은 하지 않는다).
  final String? projectId;

  /// 테스트에서 주입. 없으면 앱 공용 [SsProjectStoreProvider] 저장소.
  final SsProjectStore? projectStore;

  final FloorPlanUploadService uploadService;
  final FloorPlanAnalysisService analysisService;

  /// 테스트가 실제 CV 해석 없이 정해진 [SSSpatialModel]을 주입할 수 있게 한다
  /// ([FloorPlanUploadService]/[FloorPlanAnalysisService]와 같은 패턴).
  final SSSpatialModelBuilder spatialModelBuilder;

  @override
  State<FloorPlanUploadScreen> createState() => _FloorPlanUploadScreenState();
}

enum _FloorPlanUploadLoad { loading, loaded, error }

class _FloorPlanUploadScreenState extends State<FloorPlanUploadScreen> {
  _FloorPlanUploadLoad _state = _FloorPlanUploadLoad.loading;
  SsProjectStore? _store;
  SsProject? _project;
  SsAutosaveController? _autosave;

  FloorPlanFile? _sourceFile;
  bool _analyzing = false;
  FloorPlanAnalysisOutcome? _outcome;
  SSSpatialModel? _model;
  Set<SsRecognitionLayer> _visibleLayers = SsRecognitionLayer.values.toSet();

  // MASTER UI 5 원본 패널 툴바(회전/확대-축소) 상태 — 보기 전용(분석에는 영향 없음).
  int _rotationQuarters = 0;
  double _zoomScale = 1.0;
  final TransformationController _zoomController = TransformationController();

  bool get _hasImage => _sourceFile != null && _sourceFile!.kind == FloorPlanFileKind.image && _sourceFile!.bytes != null;

  @override
  void initState() {
    super.initState();
    _zoomController.addListener(_onZoomChanged);
    if (widget.projectId == null) {
      _state = _FloorPlanUploadLoad.loaded;
    } else {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _zoomController.removeListener(_onZoomChanged);
    _zoomController.dispose();
    _autosave?.dispose();
    super.dispose();
  }

  void _onZoomChanged() {
    final scale = _zoomController.value.getMaxScaleOnAxis();
    if (!mounted || (scale - _zoomScale).abs() <= 0.001) return;
    setState(() => _zoomScale = scale);
  }

  void _setZoom(double scale) {
    final clamped = scale.clamp(0.5, 4.0);
    setState(() {
      _zoomScale = clamped;
      _zoomController.value = Matrix4.identity()..scale(clamped);
    });
  }

  void _rotateImage() {
    setState(() => _rotationQuarters = (_rotationQuarters + 1) % 4);
  }

  void _resetViewTransform() {
    _rotationQuarters = 0;
    _zoomScale = 1.0;
    _zoomController.value = Matrix4.identity();
  }

  Future<void> _showFullscreen() async {
    final file = _sourceFile;
    if (file == null || file.bytes == null) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        key: const Key('ssFullscreenDialog'),
        insetPadding: const EdgeInsets.all(16),
        child: RotatedBox(
          quarterTurns: _rotationQuarters,
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 6,
            child: Image.memory(file.bytes!, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  Future<void> _load() async {
    final pid = widget.projectId!;
    try {
      final store = widget.projectStore ?? await SsProjectStoreProvider.instance.store();
      final project = await store.load(pid);
      if (project == null) {
        if (!mounted) return;
        setState(() => _state = _FloorPlanUploadLoad.error);
        return;
      }

      FloorPlanFile? restoredFile;
      final sourcePayload = project.data[SsDataSlot.sourceData]?.payload;
      final b64 = sourcePayload?['imageBase64'];
      if (b64 is String) {
        try {
          final bytes = base64Decode(b64);
          restoredFile = FloorPlanFile(
            fileName: '${sourcePayload?['fileName'] ?? '평면도'}',
            extension: '${sourcePayload?['extension'] ?? 'png'}',
            kind: FloorPlanFileKind.image,
            sizeBytes: bytes.length,
            bytes: bytes,
          );
        } catch (e, st) {
          debugPrint('FloorPlanUploadScreen._load 원본 이미지 복원 실패 (${e.runtimeType}): $e\n$st');
        }
      }

      SSSpatialModel? restoredModel;
      final recognitionSlot = project.data[SsDataSlot.recognitionData];
      final sourceRevision = project.data[SsDataSlot.sourceData]?.revision;
      if (recognitionSlot != null && sourceRevision != null && recognitionSlot.basedOn[SsDataSlot.sourceData] == sourceRevision) {
        restoredModel = ssSpatialModelFromJson(recognitionSlot.payload['model']);
      }

      if (!mounted) return;
      setState(() {
        _store = store;
        _project = project;
        _autosave = SsAutosaveController(store: store, project: project);
        _sourceFile = restoredFile;
        _model = restoredModel;
        _visibleLayers = SsRecognitionLayer.values.toSet();
        _resetViewTransform();
        _state = _FloorPlanUploadLoad.loaded;
      });

      if (restoredFile != null && restoredModel == null) {
        await _runAnalysis(restoredFile);
      }
    } catch (e, st) {
      // 네트워크를 쓰지 않는 화면이므로 네트워크 오류로 오분류하지 않는다 — 실제
      // 원인은 로그로 남기고 사용자에게는 일반 안내만 보인다.
      debugPrint('FloorPlanUploadScreen._load 실패 (${e.runtimeType}): $e\n$st');
      if (!mounted) return;
      setState(() => _state = _FloorPlanUploadLoad.error);
    }
  }

  Future<void> _pickFile() async {
    final FloorPlanFile? picked;
    try {
      picked = await widget.uploadService.pickFloorPlanFile();
    } catch (e, st) {
      debugPrint('FloorPlanUploadScreen._pickFile 실패 (${e.runtimeType}): $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('파일을 선택하지 못했습니다. 다시 시도해주세요.', key: Key('ssUploadPickError'))),
      );
      return;
    }
    if (picked == null) return; // 취소는 정상 흐름

    if (picked.kind == FloorPlanFileKind.pdf) {
      if (!mounted) return;
      setState(() {
        _sourceFile = picked;
        _model = null;
        _outcome = null;
        _resetViewTransform();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF는 미리보기만 지원합니다. 이미지(JPG/PNG)로 다시 올려주세요.', key: Key('ssPdfUnsupportedNotice'))),
      );
      return;
    }

    final project = _project;
    if (project != null && project.data[SsDataSlot.sourceData] != null) {
      // SS001 §5 "원본 데이터는 항상 보존" — 이미 정한 원본은 이 화면에서 바꾸지 않는다.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('원본 평면도는 바꿀 수 없습니다. 다른 평면도로 시작하려면 새 프로젝트를 만들어주세요.', key: Key('ssSourceImmutableNotice')),
        ),
      );
      return;
    }
    if (project != null && picked.bytes != null) {
      final updated = project.withSource({
        'imageBase64': base64Encode(picked.bytes!),
        'fileName': picked.fileName,
        'extension': picked.extension,
      }, label: '원본 평면도');
      _project = updated;
      _autosave?.update(updated);
    }

    if (!mounted) return;
    setState(() {
      _sourceFile = picked;
      _model = null;
      _outcome = null;
      _resetViewTransform();
    });
    await _runAnalysis(picked);
  }

  Future<void> _runAnalysis(FloorPlanFile file) async {
    if (!mounted) return;
    setState(() {
      _analyzing = true;
      _outcome = null;
    });

    FloorPlanAnalysisOutcome outcome;
    try {
      outcome = await widget.analysisService.analyze(file);
    } catch (e, st) {
      debugPrint('FloorPlanUploadScreen._runAnalysis 분석 실패 (${e.runtimeType}): $e\n$st');
      outcome = const FloorPlanAnalysisOutcome.failure(
        FloorPlanAnalysisFailureReason.internalError,
        '평면도 분석 중 문제가 발생했습니다. 잠시 후 다시 시도해주세요.',
      );
    }

    SSSpatialModel? model;
    if (outcome.isSuccess) {
      try {
        model = widget.spatialModelBuilder.build(outcome.result!);
      } catch (e, st) {
        debugPrint('FloorPlanUploadScreen._runAnalysis 공간모델 생성 실패 (${e.runtimeType}): $e\n$st');
        outcome = const FloorPlanAnalysisOutcome.failure(
          FloorPlanAnalysisFailureReason.internalError,
          '평면도 분석 중 문제가 발생했습니다. 잠시 후 다시 시도해주세요.',
        );
      }
    }

    if (!mounted) return;
    setState(() {
      _outcome = outcome;
      _model = model;
      _analyzing = false;
      _visibleLayers = SsRecognitionLayer.values.toSet();
    });

    final project = _project;
    if (model != null && project != null) {
      final saved = project.withStageData(
        SsDataSlot.recognitionData,
        {'kind': 'ssSpatialModel', 'model': ssSpatialModelToJson(model)},
        label: 'AI 공간 인식',
      );
      _project = saved;
      _autosave?.update(saved);
    }
  }

  void _toggleAllLayers(List<SsRecognitionLayer> shown) {
    setState(() {
      if (_visibleLayers.containsAll(shown)) {
        _visibleLayers.removeAll(shown);
      } else {
        _visibleLayers.addAll(shown);
      }
    });
  }

  /// "수정하기"/"CAD 파일로 변환(확인 후)" 공통 — 다음 보정 단계(SS009)로 이동한다.
  Future<void> _goNext() async {
    if (_model == null) return;
    final project = _project;
    final autosave = _autosave;
    if (project != null && autosave != null) {
      await autosave.saveNow();
      final current = autosave.project;
      final next = SsFlows.next(current.sourceType, current.currentStage);
      if (next == null) return;
      final moved = current.moveTo(next);
      try {
        await (_store ?? autosave.store).save(moved);
      } catch (e, st) {
        debugPrint('FloorPlanUploadScreen._goNext 저장 실패 (${e.runtimeType}): $e\n$st');
      }
      if (!mounted) return;
      await Navigator.of(context).pushNamed(next.routeName, arguments: project.info.id);
    } else {
      if (!mounted) return;
      await Navigator.of(context).pushNamed(SsStage.floorPlanReview.routeName);
    }
  }

  Future<void> _onConvertPressed() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('ssConvertConfirmDialog'),
        title: const Text('인식 결과를 확인하셨나요?'),
        content: const Text('CAD 파일로 변환하기 전에 원본과 AI 인식 결과를 비교해, 확인이 필요한 요소가 없는지 살펴보세요. 계속하면 평면도 확인·보정 단계로 이동합니다.'),
        actions: [
          TextButton(key: const Key('ssConvertCancel'), onPressed: () => Navigator.of(ctx).pop(false), child: const Text('취소')),
          ElevatedButton(key: const Key('ssConvertConfirm'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('확인했습니다, 계속')),
        ],
      ),
    );
    if (confirmed == true) await _goNext();
  }

  @override
  Widget build(BuildContext context) {
    if (_state == _FloorPlanUploadLoad.error) {
      return const Center(
        child: Text(
          '프로젝트를 불러오지 못했습니다. 프로젝트 관리에서 다시 열어주세요.',
          key: Key('ssUploadLoadError'),
          style: TextStyle(color: SsMasterTheme.textSecondary),
        ),
      );
    }
    if (_state == _FloorPlanUploadLoad.loading) {
      return const Center(child: CircularProgressIndicator(key: Key('ssUploadLoading')));
    }
    return Material(
      type: MaterialType.transparency,
      child: Padding(
        key: const Key('ssUploadScreen'),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SsStageHeader(stage: SsStage.floorPlanUpload),
            const SizedBox(height: 16),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _buildSourcePanel()),
                  const SizedBox(width: 16),
                  Expanded(child: _buildRecognitionPanel()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  BoxDecoration get _panelDecoration =>
      BoxDecoration(color: SsMasterTheme.panel, borderRadius: BorderRadius.circular(14), border: Border.all(color: SsMasterTheme.panelBorder));

  Widget _buildSourcePanel() {
    return Container(
      decoration: _panelDecoration,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.image_outlined, color: SsMasterTheme.textSecondary, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('업로드한 평면도', style: TextStyle(color: SsMasterTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              // MASTER UI 5 원본 패널 툴바 — 다른 이미지 업로드 + 회전/자르기(미구현은
              // 비활성)/확대-축소/전체화면. 좁은 화면에서도 줄바꿈되게 Wrap을 쓴다.
              Wrap(
                spacing: 2,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton.icon(
                    key: const Key('ssUploadPickButton'),
                    onPressed: _pickFile,
                    icon: const Icon(Icons.upload_file, size: 18, color: SsMasterTheme.neonBlue),
                    label: Text(_sourceFile == null ? '평면도 업로드' : '다른 이미지 업로드', style: const TextStyle(color: SsMasterTheme.neonBlue)),
                  ),
                  IconButton(
                    key: const Key('ssRotateButton'),
                    tooltip: '회전',
                    onPressed: _hasImage ? _rotateImage : null,
                    icon: const Icon(Icons.rotate_90_degrees_ccw_outlined, color: SsMasterTheme.textSecondary, size: 20),
                  ),
                  IconButton(
                    key: const Key('ssCropButton'),
                    tooltip: '자르기',
                    onPressed: null,
                    icon: const Icon(Icons.crop_outlined, color: SsMasterTheme.textSecondary, size: 20),
                  ),
                  IconButton(
                    key: const Key('ssZoomOutButton'),
                    tooltip: '축소',
                    onPressed: _hasImage ? () => _setZoom(_zoomScale - 0.25) : null,
                    icon: const Icon(Icons.remove, color: SsMasterTheme.textSecondary, size: 18),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text(
                      '${(_zoomScale * 100).round()}%',
                      key: const Key('ssZoomLevelText'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: SsMasterTheme.textSecondary, fontSize: 13),
                    ),
                  ),
                  IconButton(
                    key: const Key('ssZoomInButton'),
                    tooltip: '확대',
                    onPressed: _hasImage ? () => _setZoom(_zoomScale + 0.25) : null,
                    icon: const Icon(Icons.add, color: SsMasterTheme.textSecondary, size: 18),
                  ),
                  IconButton(
                    key: const Key('ssFullscreenButton'),
                    tooltip: '전체화면',
                    onPressed: _hasImage ? _showFullscreen : null,
                    icon: const Icon(Icons.fullscreen, color: SsMasterTheme.textSecondary, size: 20),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(child: _buildSourceBody()),
        ],
      ),
    );
  }

  Widget _buildSourceBody() {
    final file = _sourceFile;
    if (file == null) {
      return const Center(
        child: Column(
          key: Key('ssUploadEmptyState'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_photo_alternate_outlined, color: SsMasterTheme.textMuted, size: 48),
            SizedBox(height: 12),
            Text(
              '평면도 이미지(JPG/PNG)를 업로드하면\nAI가 공간을 인식합니다.',
              textAlign: TextAlign.center,
              style: TextStyle(color: SsMasterTheme.textSecondary),
            ),
          ],
        ),
      );
    }
    if (file.kind == FloorPlanFileKind.pdf || file.bytes == null) {
      return Center(
        child: Column(
          key: const Key('ssUploadPdfPlaceholder'),
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.picture_as_pdf_outlined, color: SsMasterTheme.textMuted, size: 48),
            const SizedBox(height: 12),
            Text(file.fileName, style: const TextStyle(color: SsMasterTheme.textSecondary)),
          ],
        ),
      );
    }
    return Stack(
      children: [
        Positioned.fill(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4,
            transformationController: _zoomController,
            child: Center(
              child: RotatedBox(
                quarterTurns: _rotationQuarters,
                child: Image.memory(file.bytes!, key: const Key('ssUploadedImage'), fit: BoxFit.contain),
              ),
            ),
          ),
        ),
        if (_analyzing)
          Positioned.fill(
            child: Container(
              color: SsMasterTheme.background.withValues(alpha: 0.7),
              child: const Center(
                child: Column(
                  key: Key('ssAnalyzingIndicator'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('AI가 평면도를 분석하고 있습니다…', style: TextStyle(color: SsMasterTheme.textPrimary)),
                  ],
                ),
              ),
            ),
          ),
        if (!_analyzing && _outcome != null && !_outcome!.isSuccess)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Container(
              key: const Key('ssAnalysisError'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.15),
                border: Border.all(color: Colors.redAccent),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_outcome!.message ?? '평면도 분석에 실패했습니다.', style: const TextStyle(color: Colors.redAccent)),
            ),
          ),
      ],
    );
  }

  Widget _buildRecognitionPanel() {
    final model = _model;
    return Container(
      decoration: _panelDecoration,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.view_in_ar_outlined, color: SsMasterTheme.textSecondary, size: 20),
              const SizedBox(width: 8),
              const Text('공간 인식 결과', style: TextStyle(color: SsMasterTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
              const Spacer(),
              OutlinedButton.icon(
                key: const Key('ssUploadEditButton'),
                onPressed: model == null ? null : _goNext,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('수정하기'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: model == null
                ? const Center(
                    child: Text(
                      '평면도를 업로드하면\nAI 인식 결과가 여기에 표시됩니다.',
                      key: Key('ssRecognitionEmptyState'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: SsMasterTheme.textSecondary),
                    ),
                  )
                : _buildRecognitionBody(model),
          ),
        ],
      ),
    );
  }

  Widget _buildRecognitionBody(SSSpatialModel model) {
    final summary = SsRecognitionSummary.fromModel(model);
    final aspect = model.sourceWidthPx > 0 && model.sourceHeightPx > 0 ? model.sourceWidthPx / model.sourceHeightPx : 1.0;
    final shownLayers = [
      for (final layer in SsRecognitionLayer.values)
        if (SsRecognitionLayers.alwaysShown.contains(layer) || (summary.counts[layer] ?? 0) > 0) layer,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 레이어 목록·확인 배너는 내용이 길어질 수 있어 스크롤하되, "CAD 파일로 변환"
        // 버튼은 스크롤 영역 밖에 고정해 항상 패널 하단에 온전히 보이고 눌릴 수 있게
        // 한다(스크롤 내부에 있으면 내용이 넘칠 때 버튼이 뷰포트 경계에 걸려 탭이
        // 빗나갈 수 있었다).
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  key: const Key('ssRecognitionOverlay'),
                  height: 260,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                  clipBehavior: Clip.antiAlias,
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: aspect,
                      child: CustomPaint(painter: _SsRecognitionPainter(model: model, visibleLayers: _visibleLayers)),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '인식된 요소 (총 ${summary.totalCount}개)',
                        key: const Key('ssRecognizedTotal'),
                        style: const TextStyle(color: SsMasterTheme.textPrimary, fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      key: const Key('ssLayerToggleAll'),
                      tooltip: '모두 보기/숨기기',
                      onPressed: () => _toggleAllLayers(shownLayers),
                      icon: Icon(
                        _visibleLayers.containsAll(shownLayers) ? Icons.visibility : Icons.visibility_off,
                        color: SsMasterTheme.textSecondary,
                        size: 20,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // MASTER UI 5 — "인식된 요소"(개수) 목록과 "레이어 표시"(체크박스) 목록을
                // 좌우 두 박스로 나눠 보여준다(기능은 기존과 동일 — 레이어별 개수 확인 +
                // 보이기/숨기기 전환).
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [for (final layer in shownLayers) _buildLayerCountRow(layer, summary.counts[layer] ?? 0)],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      key: const Key('ssLayerVisibilityPanel'),
                      width: 150,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: SsMasterTheme.background.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: SsMasterTheme.panelBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('레이어 표시', style: TextStyle(color: SsMasterTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 12)),
                          const SizedBox(height: 6),
                          for (final layer in shownLayers) _buildLayerCheckboxRow(layer),
                        ],
                      ),
                    ),
                  ],
                ),
                if (summary.reviewItems.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    key: const Key('ssReviewBanner'),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.12),
                      border: Border.all(color: Colors.orangeAccent),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '확인이 필요한 요소 ${summary.reviewItems.length}개 — "수정하기"에서 확인하세요',
                            style: const TextStyle(color: Colors.orangeAccent, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final item in summary.reviewItems)
                    ListTile(
                      key: Key('ssReviewItem_${item.id}'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        width: 10,
                        height: 10,
                        margin: const EdgeInsets.only(top: 4),
                        decoration: BoxDecoration(color: SsRecognitionLayers.all[item.layer]!.color, borderRadius: BorderRadius.circular(3)),
                      ),
                      title: Text(item.label, style: const TextStyle(color: SsMasterTheme.textPrimary, fontSize: 13)),
                      subtitle: Text(item.reason, style: const TextStyle(color: SsMasterTheme.textSecondary, fontSize: 12)),
                    ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            key: const Key('ssUploadConvertButton'),
            onPressed: _onConvertPressed,
            style: ElevatedButton.styleFrom(backgroundColor: SsMasterTheme.neonBlue, padding: const EdgeInsets.symmetric(vertical: 14)),
            child: const Text('CAD 파일로 변환'),
          ),
        ),
      ],
    );
  }

  Widget _buildLayerCountRow(SsRecognitionLayer layer, int count) {
    final info = SsRecognitionLayers.all[layer]!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        key: Key('ssLayerRow_${layer.name}'),
        children: [
          Container(width: 14, height: 14, decoration: BoxDecoration(color: info.color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 8),
          Expanded(child: Text(info.label, style: const TextStyle(color: SsMasterTheme.textPrimary, fontSize: 13))),
          Text('$count개', style: const TextStyle(color: SsMasterTheme.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildLayerCheckboxRow(SsRecognitionLayer layer) {
    final info = SsRecognitionLayers.all[layer]!;
    final visible = _visibleLayers.contains(layer);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              key: Key('ssLayerCheckbox_${layer.name}'),
              value: visible,
              activeColor: info.color,
              onChanged: (v) => setState(() {
                if (v == true) {
                  _visibleLayers.add(layer);
                } else {
                  _visibleLayers.remove(layer);
                }
              }),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(child: Text(info.label, style: const TextStyle(color: SsMasterTheme.textSecondary, fontSize: 12))),
        ],
      ),
    );
  }
}

/// 우측 "공간 인식 결과" 오버레이 — [SSSpatialModel]을 레이어별 색으로
/// 정규화 좌표([Point2], 0.0~1.0)에서 바로 그린다.
class _SsRecognitionPainter extends CustomPainter {
  const _SsRecognitionPainter({required this.model, required this.visibleLayers});

  final SSSpatialModel model;
  final Set<SsRecognitionLayer> visibleLayers;

  static const _fixtureKinds = {SSObjectKind.sink, SSObjectKind.toilet, SSObjectKind.bathtub, SSObjectKind.equipment};

  Offset _pt(Point2 p, Size size) => Offset(p.x * size.width, p.y * size.height);

  Path _polygonPath(List<Point2> polygon, Size size) {
    final path = Path();
    final first = _pt(polygon.first, size);
    path.moveTo(first.dx, first.dy);
    for (final p in polygon.skip(1)) {
      final o = _pt(p, size);
      path.lineTo(o.dx, o.dy);
    }
    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (visibleLayers.contains(SsRecognitionLayer.space)) {
      final fill = Paint()..color = SsRecognitionLayers.all[SsRecognitionLayer.space]!.color.withValues(alpha: 0.55);
      for (final space in model.spaces) {
        if (space.polygon.length < 3) continue;
        canvas.drawPath(_polygonPath(space.polygon, size), fill);
      }
    }

    for (final obj in model.objects) {
      final layer = _fixtureKinds.contains(obj.kind) ? SsRecognitionLayer.fixture : SsRecognitionLayer.furniture;
      if (!visibleLayers.contains(layer) || obj.polygon.length < 3) continue;
      final fill = Paint()..color = SsRecognitionLayers.all[layer]!.color.withValues(alpha: 0.85);
      canvas.drawPath(_polygonPath(obj.polygon, size), fill);
    }

    for (final s in model.structuralElements) {
      final layer = switch (s.kind) {
        SSStructuralKind.column => SsRecognitionLayer.column,
        SSStructuralKind.stair => SsRecognitionLayer.stair,
        SSStructuralKind.elevator => SsRecognitionLayer.elevator,
        SSStructuralKind.shaft || SSStructuralKind.voidSpace => SsRecognitionLayer.otherStructural,
      };
      if (!visibleLayers.contains(layer) || s.polygon.length < 3) continue;
      final fill = Paint()..color = SsRecognitionLayers.all[layer]!.color.withValues(alpha: 0.9);
      canvas.drawPath(_polygonPath(s.polygon, size), fill);
    }

    if (visibleLayers.contains(SsRecognitionLayer.wall)) {
      final strokeColor = SsRecognitionLayers.all[SsRecognitionLayer.wall]!.color;
      for (final wall in model.walls) {
        final paint = Paint()
          ..color = strokeColor
          ..strokeWidth = (wall.thicknessNormalized * size.shortestSide).clamp(1.5, 10)
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(_pt(wall.start, size), _pt(wall.end, size), paint);
      }
    }

    for (final opening in model.openings) {
      final layer = opening.kind == SSOpeningKind.window ? SsRecognitionLayer.window : SsRecognitionLayer.door;
      if (!visibleLayers.contains(layer)) continue;
      final paint = Paint()..color = SsRecognitionLayers.all[layer]!.color;
      canvas.drawCircle(_pt(opening.center, size), 4.5, paint);
    }
  }

  bool _setEquals(Set<Object?> a, Set<Object?> b) => a.length == b.length && a.containsAll(b);

  @override
  bool shouldRepaint(covariant _SsRecognitionPainter oldDelegate) =>
      oldDelegate.model != model || !_setEquals(oldDelegate.visibleLayers, visibleLayers);
}
