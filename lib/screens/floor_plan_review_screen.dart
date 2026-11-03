/// SS009 — MASTER UI 6(평면도 확인·보정). SS008이 만든 AI 공간 인식 결과
/// ([SSSpatialModel], SsDataSlot.recognitionData)를 사용자가 쉽고 빠르게 보정하고,
/// CAD 변환용 최종 공간 모델을 확정한다.
///
/// - 좌측 "원본 평면도"·우측 "공간 인식 결과"를 나란히 두어 원본과 인식 결과를
///   항상 비교할 수 있게 한다(§구현범위).
/// - 보정(펜/형광펜/지우개/선택 + 색상/굵기 + Undo/Redo, 객체 의미 수정, 잘못된
///   구조요소 삭제, 누락 요소 추가)은 [SsReviewEditorController]가 맡는다 — AI
///   인식 결과 자체는 바꾸지 않고 보정 레이어([SsReviewScene])를 겹쳐 최종 모델
///   ([SsReviewEditorController.effectiveModel])을 만든다.
/// - "확인 필요" 요소가 남았는지는 [SsRecognitionSummary](SS008)를 그대로 재사용해
///   보여준다.
/// - "CAD 파일로 변환"은 남은 확인 항목 수를 알려주는 확인 창을 거친 뒤에만 다음
///   단계로 이동하고, 그 시점의 최종 모델을 [SsDataSlot.userCorrections]에 저장한다
///   — [SsDataDependencies]가 이미 cadData의 upstream으로 정해 둔 칸이라, SS010이
///   이 칸을 그대로 이어받을 수 있다(완료 조건).
/// - 공통 상단바([SsTopBar])·좌측 메뉴([SsNavRail])는 [SsRouter]가 [SsStageScreen]
///   으로 이미 감싸 준다 — 이 화면은 그 안쪽만 그린다.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/ss_project.dart';
import '../core/ss_project_store.dart';
import '../core/ss_review_editor_controller.dart';
import '../core/ss_router.dart' show SsStageHeader;
import '../core/ss_stage.dart';
import '../models/floor_plan_geometry.dart';
import '../models/ss_review_scene.dart';
import '../models/ss_spatial_model.dart';
import '../models/ss_spatial_model_json.dart';
import '../services/ss_project_store_provider.dart';
import '../services/ss_recognition_summary.dart';
import '../theme/ss_master_theme.dart';

class FloorPlanReviewScreen extends StatefulWidget {
  const FloorPlanReviewScreen({super.key, this.projectId, this.projectStore});

  /// 연 프로젝트 id(없으면 AI 인식 결과가 있을 수 없으므로 안내만 보인다).
  final String? projectId;

  /// 테스트에서 주입. 없으면 앱 공용 [SsProjectStoreProvider] 저장소.
  final SsProjectStore? projectStore;

  @override
  State<FloorPlanReviewScreen> createState() => _FloorPlanReviewScreenState();
}

enum _ReviewLoad { loading, loaded, error }

class _FloorPlanReviewScreenState extends State<FloorPlanReviewScreen> {
  _ReviewLoad _state = _ReviewLoad.loading;
  SsProjectStore? _store;
  SsProject? _project;
  SsAutosaveController? _autosave;
  SsReviewEditorController? _controller;
  Uint8List? _sourceBytes;

  /// MASTER UI 6 "수정하기" 토글 — 꺼져 있으면(기본값) 원본/인식 결과 비교만 하고,
  /// 도구를 하나라도 고르면 자동으로 켜진다(3초 법칙 — 먼저 비교, 그다음 보정).
  bool _editMode = false;
  Set<SsRecognitionLayer> _visibleLayers = SsRecognitionLayer.values.toSet();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final pid = widget.projectId;
    if (pid == null) {
      if (!mounted) return;
      setState(() => _state = _ReviewLoad.loaded);
      return;
    }
    try {
      final store = widget.projectStore ?? await SsProjectStoreProvider.instance.store();
      final project = await store.load(pid);
      if (project == null) {
        if (!mounted) return;
        setState(() => _state = _ReviewLoad.error);
        return;
      }

      Uint8List? sourceBytes;
      final sourcePayload = project.data[SsDataSlot.sourceData]?.payload;
      final b64 = sourcePayload?['imageBase64'];
      if (b64 is String) {
        try {
          sourceBytes = base64Decode(b64);
        } catch (e, st) {
          debugPrint('FloorPlanReviewScreen._load 원본 이미지 복원 실패 (${e.runtimeType}): $e\n$st');
        }
      }

      final recognitionSlot = project.data[SsDataSlot.recognitionData];
      SSSpatialModel? model;
      if (recognitionSlot != null) {
        model = ssSpatialModelFromJson(recognitionSlot.payload['model']);
      }

      var initialScene = SsReviewScene.empty;
      final correctionsSlot = project.data[SsDataSlot.userCorrections];
      if (correctionsSlot != null && recognitionSlot != null && correctionsSlot.basedOn[SsDataSlot.recognitionData] == recognitionSlot.revision) {
        initialScene = SsReviewScene.tryFromJson(correctionsSlot.payload['review']);
      }

      if (!mounted) return;
      _controller?.history.removeListener(_onReviewCommitted);
      _controller?.dispose();
      setState(() {
        _store = store;
        _project = project;
        _autosave = SsAutosaveController(store: store, project: project);
        _sourceBytes = sourceBytes;
        _controller = model == null
            ? null
            : (SsReviewEditorController(baseModel: model, initialScene: initialScene)..history.addListener(_onReviewCommitted));
        _visibleLayers = SsRecognitionLayer.values.toSet();
        _state = _ReviewLoad.loaded;
      });
    } catch (e, st) {
      // 네트워크를 쓰지 않는 화면이므로 네트워크 오류로 오분류하지 않는다 — 실제
      // 원인은 로그로 남기고 사용자에게는 일반 안내만 보인다.
      debugPrint('FloorPlanReviewScreen._load 실패 (${e.runtimeType}): $e\n$st');
      if (!mounted) return;
      setState(() => _state = _ReviewLoad.error);
    }
  }

  /// History에 실제로 커밋된 보정만 자동저장한다 — 드래그 중 미리보기 프레임마다는
  /// 저장하지 않는다. [SsDataSlot.userCorrections]는 이미 cadData의 upstream으로
  /// 정해져 있는 칸이라(ss_project.dart), SS010이 그대로 이어받을 수 있다.
  void _onReviewCommitted() {
    final autosave = _autosave;
    final controller = _controller;
    if (autosave == null || controller == null) return;
    final updated = autosave.project.withStageData(
      SsDataSlot.userCorrections,
      {'kind': 'ssSpatialModel', 'review': controller.scene.toJson(), 'model': ssSpatialModelToJson(controller.effectiveModel)},
      label: '평면도 보정',
    );
    _project = updated;
    autosave.update(updated);
  }

  Future<void> _onConvertPressed() async {
    final controller = _controller;
    if (controller == null) return;
    final remaining = SsRecognitionSummary.fromModel(controller.effectiveModel).reviewItems.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('ssReviewConvertDialog'),
        title: const Text('CAD 변환 전 최종 확인'),
        content: Text(
          remaining > 0
              ? '아직 확인하지 않은 요소가 $remaining개 있습니다. 원본과 비교해 다시 확인하는 것을 권장합니다. 그래도 CAD로 변환하시겠습니까?'
              : '모든 확인이 끝났습니다. 보정한 내용을 최종 공간 모델로 확정하고 CAD로 변환합니다. 계속하시겠습니까?',
        ),
        actions: [
          TextButton(key: const Key('ssReviewConvertCancel'), onPressed: () => Navigator.of(ctx).pop(false), child: const Text('취소')),
          ElevatedButton(key: const Key('ssReviewConvertConfirm'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('확인했습니다, 계속')),
        ],
      ),
    );
    if (confirmed == true) await _goNext();
  }

  Future<void> _goNext() async {
    final controller = _controller;
    final project = _project;
    final autosave = _autosave;
    if (controller == null || project == null || autosave == null) return;
    final finalProject = autosave.project.withStageData(
      SsDataSlot.userCorrections,
      {'kind': 'ssSpatialModel', 'review': controller.scene.toJson(), 'model': ssSpatialModelToJson(controller.effectiveModel)},
      label: '평면도 최종 확정',
    );
    _project = finalProject;
    autosave.update(finalProject);
    await autosave.saveNow();
    final current = autosave.project;
    final next = SsFlows.next(current.sourceType, current.currentStage);
    if (next == null) return;
    final moved = current.moveTo(next);
    try {
      await (_store ?? autosave.store).save(moved);
    } catch (e, st) {
      debugPrint('FloorPlanReviewScreen._goNext 저장 실패 (${e.runtimeType}): $e\n$st');
    }
    if (!mounted) return;
    await Navigator.of(context).pushNamed(next.routeName, arguments: project.info.id);
  }

  @override
  void dispose() {
    _controller?.history.removeListener(_onReviewCommitted);
    _controller?.dispose();
    _autosave?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_state == _ReviewLoad.error) {
      return const Center(
        child: Text(
          '프로젝트를 불러오지 못했습니다. 프로젝트 관리에서 다시 열어주세요.',
          key: Key('ssReviewLoadError'),
          style: TextStyle(color: SsMasterTheme.textSecondary),
        ),
      );
    }
    if (_state == _ReviewLoad.loading) {
      return const Center(child: CircularProgressIndicator(key: Key('ssReviewLoading')));
    }
    final controller = _controller;
    return Material(
      type: MaterialType.transparency,
      child: Padding(
        key: const Key('ssReviewScreen'),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SsStageHeader(stage: SsStage.floorPlanReview),
            const SizedBox(height: 16),
            Expanded(
              child: controller == null
                  ? _buildMissingModel()
                  : ListenableBuilder(listenable: controller, builder: (context, _) => _buildBody(controller)),
            ),
          ],
        ),
      ),
    );
  }

  BoxDecoration get _panelDecoration =>
      BoxDecoration(color: SsMasterTheme.panel, borderRadius: BorderRadius.circular(14), border: Border.all(color: SsMasterTheme.panelBorder));

  Widget _buildMissingModel() {
    return const Center(
      child: Column(
        key: Key('ssReviewMissingModel'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_search_outlined, color: SsMasterTheme.textMuted, size: 48),
          SizedBox(height: 12),
          Text('먼저 평면도 업로드에서 AI 인식을 완료해주세요.', style: TextStyle(color: SsMasterTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildBody(SsReviewEditorController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildSourcePanel()),
              const SizedBox(width: 16),
              Expanded(child: _buildReviewPanel(controller)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildBottomToolbar(controller),
      ],
    );
  }

  Widget _buildSourcePanel() {
    final bytes = _sourceBytes;
    return Container(
      decoration: _panelDecoration,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.image_outlined, color: SsMasterTheme.textSecondary, size: 20),
              SizedBox(width: 8),
              Text('원본 평면도', key: Key('ssReviewSourceTitle'), style: TextStyle(color: SsMasterTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: bytes == null
                ? const Center(
                    child: Text('원본 이미지를 찾을 수 없습니다.', key: Key('ssReviewSourceMissing'), style: TextStyle(color: SsMasterTheme.textSecondary)),
                  )
                : InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4,
                    child: Center(child: Image.memory(bytes, key: const Key('ssReviewSourceImage'), fit: BoxFit.contain)),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewPanel(SsReviewEditorController controller) {
    final model = controller.effectiveModel;
    final summary = SsRecognitionSummary.fromModel(model);
    final aspect = model.sourceWidthPx > 0 && model.sourceHeightPx > 0 ? model.sourceWidthPx / model.sourceHeightPx : 1.0;
    final shownLayers = [
      for (final layer in SsRecognitionLayer.values)
        if (SsRecognitionLayers.alwaysShown.contains(layer) || (summary.counts[layer] ?? 0) > 0) layer,
    ];

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
              IconButton(
                key: const Key('ssReviewAddWallButton'),
                tooltip: '누락된 벽 추가',
                onPressed: () => _activateTool(controller, SsReviewTool.addWall),
                icon: Icon(Icons.view_agenda_outlined, size: 18, color: controller.tool == SsReviewTool.addWall ? SsMasterTheme.neonBlue : SsMasterTheme.textSecondary),
              ),
              IconButton(
                key: const Key('ssReviewAddDoorButton'),
                tooltip: '누락된 문 추가',
                onPressed: () => _activateTool(controller, SsReviewTool.addDoor),
                icon: Icon(Icons.sensor_door_outlined, size: 18, color: controller.tool == SsReviewTool.addDoor ? SsMasterTheme.neonBlue : SsMasterTheme.textSecondary),
              ),
              IconButton(
                key: const Key('ssReviewAddWindowButton'),
                tooltip: '누락된 창문 추가',
                onPressed: () => _activateTool(controller, SsReviewTool.addWindow),
                icon: Icon(Icons.window_outlined, size: 18, color: controller.tool == SsReviewTool.addWindow ? SsMasterTheme.neonBlue : SsMasterTheme.textSecondary),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const Key('ssReviewEditToggle'),
                onPressed: () => setState(() => _editMode = !_editMode),
                icon: Icon(_editMode ? Icons.visibility_outlined : Icons.edit_outlined, size: 16),
                label: Text(_editMode ? '보기 모드로' : '수정하기'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCanvas(controller, model, aspect),
                  if (!controller.selection.isEmpty) ...[
                    const SizedBox(height: 10),
                    _buildSelectionPanel(controller),
                  ],
                  const SizedBox(height: 14),
                  _buildReviewBanner(summary),
                  const SizedBox(height: 14),
                  Text(
                    '인식된 요소 (총 ${summary.totalCount}개)',
                    key: const Key('ssReviewRecognizedTotal'),
                    style: const TextStyle(color: SsMasterTheme.textPrimary, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final layer in shownLayers) _buildLayerCountRow(layer, summary.counts[layer] ?? 0)]),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        key: const Key('ssReviewLayerVisibilityPanel'),
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
                        trailing: TextButton(
                          key: Key('ssReviewResolve_${item.id}'),
                          onPressed: () => controller.markResolvedById(item.id),
                          child: const Text('확인함'),
                        ),
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
              key: const Key('ssReviewConvertButton'),
              onPressed: _onConvertPressed,
              style: ElevatedButton.styleFrom(backgroundColor: SsMasterTheme.neonBlue, padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text('CAD 파일로 변환'),
            ),
          ),
        ],
      ),
    );
  }

  void _activateTool(SsReviewEditorController controller, SsReviewTool tool) {
    if (!_editMode) setState(() => _editMode = true);
    controller.setTool(controller.tool == tool ? SsReviewTool.select : tool);
  }

  Widget _buildReviewBanner(SsRecognitionSummary summary) {
    if (summary.reviewItems.isEmpty) {
      return Container(
        key: const Key('ssReviewAllClear'),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.12), border: Border.all(color: Colors.greenAccent), borderRadius: BorderRadius.circular(8)),
        child: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 18),
            SizedBox(width: 8),
            Expanded(child: Text('확인이 필요한 요소가 없습니다. CAD로 변환할 준비가 되었습니다.', style: TextStyle(color: Colors.greenAccent, fontSize: 13))),
          ],
        ),
      );
    }
    return Container(
      key: const Key('ssReviewPendingBanner'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.12), border: Border.all(color: Colors.orangeAccent), borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text('확인이 필요한 요소 ${summary.reviewItems.length}개가 남아 있습니다.', style: const TextStyle(color: Colors.orangeAccent, fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildSelectionPanel(SsReviewEditorController controller) {
    final sel = controller.selection;
    return Container(
      key: const Key('ssReviewSelectionPanel'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: SsMasterTheme.background.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(8), border: Border.all(color: SsMasterTheme.panelBorder)),
      child: Row(
        children: [
          Expanded(child: Text('${sel.objectType} ${sel.objectId} 선택됨', style: const TextStyle(color: SsMasterTheme.textPrimary, fontSize: 13))),
          if (sel.objectType == '문')
            TextButton(key: const Key('ssReviewConvertToWindow'), onPressed: () => controller.setSelectedOpeningKind(SSOpeningKind.window), child: const Text('창으로 바꾸기')),
          if (sel.objectType == '창')
            TextButton(key: const Key('ssReviewConvertToDoor'), onPressed: () => controller.setSelectedOpeningKind(SSOpeningKind.door), child: const Text('문으로 바꾸기')),
          TextButton(key: const Key('ssReviewMarkResolved'), onPressed: controller.markSelectedResolved, child: const Text('확인함')),
          TextButton(
            key: const Key('ssReviewDeleteSelected'),
            onPressed: controller.deleteSelected,
            child: const Text('삭제', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  Widget _buildCanvas(SsReviewEditorController controller, SSSpatialModel model, double aspect) {
    return Container(
      key: const Key('ssReviewCanvasBox'),
      height: 320,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
      clipBehavior: Clip.antiAlias,
      child: Center(
        child: AspectRatio(
          aspectRatio: aspect,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest;
              Point2 toNorm(Offset local) => Point2((local.dx / size.width).clamp(0.0, 1.0), (local.dy / size.height).clamp(0.0, 1.0));
              return GestureDetector(
                key: const Key('ssReviewCanvas'),
                behavior: HitTestBehavior.opaque,
                onPanStart: !_editMode ? null : (d) => controller.pointerDown(toNorm(d.localPosition)),
                onPanUpdate: !_editMode ? null : (d) => controller.pointerMove(toNorm(d.localPosition)),
                onPanEnd: !_editMode ? null : (_) => controller.pointerUp(),
                onTapUp: !_editMode
                    ? null
                    : (d) {
                        final p = toNorm(d.localPosition);
                        controller.pointerDown(p);
                        controller.pointerUp();
                      },
                child: CustomPaint(
                  size: size,
                  painter: _SsReviewPainter(
                    model: model,
                    visibleLayers: _visibleLayers,
                    scene: controller.scene,
                    selection: controller.selection,
                    draftPoints: controller.draftStrokePoints,
                    draftTool: controller.tool,
                    draftColorValue: controller.colorValue,
                    draftStrokeWidth: controller.strokeWidth,
                    addWallDraftStart: controller.addWallDraftStart,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLayerCountRow(SsRecognitionLayer layer, int count) {
    final info = SsRecognitionLayers.all[layer]!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        key: Key('ssReviewLayerRow_${layer.name}'),
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
              key: Key('ssReviewLayerCheckbox_${layer.name}'),
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

  Widget _buildBottomToolbar(SsReviewEditorController controller) {
    const colors = [0xFFEF4444, 0xFFF97316, 0xFFEAB308, 0xFF3B82F6, 0xFFA855F7, 0xFFFFFFFF];
    return Container(
      key: const Key('ssReviewBottomToolbar'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(color: SsMasterTheme.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: SsMasterTheme.panelBorder)),
      child: Row(
        children: [
          _reviewToolButton(controller, SsReviewTool.pen, Icons.edit_outlined, '펜'),
          _reviewToolButton(controller, SsReviewTool.highlighter, Icons.brush_outlined, '형광펜'),
          _reviewToolButton(controller, SsReviewTool.eraser, Icons.auto_fix_normal_outlined, '지우개'),
          _reviewToolButton(controller, SsReviewTool.select, Icons.crop_free, '선택'),
          const SizedBox(width: 16),
          for (final c in colors) _colorSwatch(controller, c),
          const SizedBox(width: 16),
          const Text('굵기', style: TextStyle(color: SsMasterTheme.textSecondary, fontSize: 12)),
          SizedBox(
            width: 120,
            child: Slider(
              key: const Key('ssReviewStrokeWidthSlider'),
              value: controller.strokeWidth,
              min: 1,
              max: 10,
              divisions: 9,
              label: controller.strokeWidth.round().toString(),
              onChanged: controller.setStrokeWidth,
            ),
          ),
          const Spacer(),
          if (_autosave != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ListenableBuilder(
                listenable: _autosave!,
                builder: (context, _) => Text(_autosave!.state.label, key: const Key('ssReviewSaveState'), style: const TextStyle(color: SsMasterTheme.textMuted, fontSize: 12)),
              ),
            ),
          IconButton(key: const Key('ssReviewUndo'), onPressed: controller.canUndo ? controller.undo : null, icon: const Icon(Icons.undo), color: SsMasterTheme.textSecondary),
          IconButton(key: const Key('ssReviewRedo'), onPressed: controller.canRedo ? controller.redo : null, icon: const Icon(Icons.redo), color: SsMasterTheme.textSecondary),
        ],
      ),
    );
  }

  Widget _reviewToolButton(SsReviewEditorController controller, SsReviewTool tool, IconData icon, String label) {
    final selected = controller.tool == tool;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: Key('ssReviewTool_${tool.name}'),
          borderRadius: BorderRadius.circular(10),
          onTap: () => _activateTool(controller, tool),
          child: Container(
            width: 60,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(gradient: selected ? SsMasterTheme.selectedItem : null, borderRadius: BorderRadius.circular(10)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: selected ? Colors.white : SsMasterTheme.textSecondary, size: 20),
                const SizedBox(height: 4),
                Text(label, style: TextStyle(fontSize: 11, color: selected ? Colors.white : SsMasterTheme.textSecondary)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _colorSwatch(SsReviewEditorController controller, int colorValue) {
    final selected = controller.colorValue == colorValue;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        key: Key('ssReviewColor_${colorValue.toRadixString(16)}'),
        onTap: () => controller.setColor(colorValue),
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: Color(colorValue),
            shape: BoxShape.circle,
            border: Border.all(color: selected ? SsMasterTheme.neonBlue : SsMasterTheme.panelBorder, width: selected ? 3 : 1),
          ),
        ),
      ),
    );
  }
}

/// 우측 "공간 인식 결과" 캔버스 — [SSSpatialModel](보정 반영된 최종 모델)을
/// 레이어별 색으로 그리고, 그 위에 선택 강조 + 펜/형광펜 주석 + 벽 추가 임시선을
/// 겹쳐 그린다. SS008 [_SsRecognitionPainter]와 같은 좌표 변환 방식(정규화
/// 좌표 → 캔버스 픽셀)을 쓰되, 이 화면 전용 선택/주석 표시가 추가된 버전이다.
class _SsReviewPainter extends CustomPainter {
  const _SsReviewPainter({
    required this.model,
    required this.visibleLayers,
    required this.scene,
    required this.selection,
    this.draftPoints,
    this.draftTool,
    this.draftColorValue = 0xFFFFFFFF,
    this.draftStrokeWidth = 3,
    this.addWallDraftStart,
  });

  final SSSpatialModel model;
  final Set<SsRecognitionLayer> visibleLayers;
  final SsReviewScene scene;
  final dynamic selection;
  final List<Point2>? draftPoints;
  final SsReviewTool? draftTool;
  final int draftColorValue;
  final double draftStrokeWidth;
  final Point2? addWallDraftStart;

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
      final isSelected = selection.objectType == '가구/설비' && selection.objectId == obj.id;
      final fill = Paint()..color = (isSelected ? SsMasterTheme.neonBlue : SsRecognitionLayers.all[layer]!.color).withValues(alpha: 0.85);
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
      for (final wall in model.walls) {
        final isSelected = selection.objectType == '벽' && selection.objectId == wall.id;
        final paint = Paint()
          ..color = isSelected ? SsMasterTheme.neonBlue : SsRecognitionLayers.all[SsRecognitionLayer.wall]!.color
          ..strokeWidth = (wall.thicknessNormalized * size.shortestSide).clamp(1.5, 10) + (isSelected ? 2 : 0)
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(_pt(wall.start, size), _pt(wall.end, size), paint);
      }
    }

    for (final opening in model.openings) {
      final layer = opening.kind == SSOpeningKind.window ? SsRecognitionLayer.window : SsRecognitionLayer.door;
      if (!visibleLayers.contains(layer)) continue;
      final isSelected = selection.objectId == opening.id && (selection.objectType == '문' || selection.objectType == '창');
      final paint = Paint()..color = isSelected ? SsMasterTheme.neonBlue : SsRecognitionLayers.all[layer]!.color;
      canvas.drawCircle(_pt(opening.center, size), isSelected ? 6.5 : 4.5, paint);
    }

    final draftStart = addWallDraftStart;
    if (draftStart != null) {
      canvas.drawCircle(_pt(draftStart, size), 5, Paint()..color = SsMasterTheme.neonBlue);
    }

    for (final stroke in scene.strokes) {
      _paintStroke(canvas, size, stroke.tool, stroke.colorValue, stroke.strokeWidth, stroke.points);
    }

    final pts = draftPoints;
    if (pts != null && pts.length >= 2 && (draftTool == SsReviewTool.pen || draftTool == SsReviewTool.highlighter)) {
      _paintStroke(canvas, size, draftTool == SsReviewTool.pen ? SsAnnotationTool.pen : SsAnnotationTool.highlighter, draftColorValue, draftStrokeWidth, pts);
    }
  }

  void _paintStroke(Canvas canvas, Size size, SsAnnotationTool tool, int colorValue, double strokeWidth, List<Point2> points) {
    if (points.length < 2) return;
    final first = _pt(points.first, size);
    final path = Path()..moveTo(first.dx, first.dy);
    for (final p in points.skip(1)) {
      final o = _pt(p, size);
      path.lineTo(o.dx, o.dy);
    }
    final paint = Paint()
      ..color = Color(colorValue).withValues(alpha: tool == SsAnnotationTool.highlighter ? 0.4 : 1.0)
      ..strokeWidth = tool == SsAnnotationTool.highlighter ? strokeWidth * 3 : strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SsReviewPainter oldDelegate) => true; // 요소 수가 적어 매번 다시 그려도 비용이 크지 않다.
}
