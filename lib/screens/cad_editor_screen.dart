/// SS011 — MASTER UI 8(CAD 수정 및 내보내기). SS010(CadConversionScreen)이
/// [SsDataSlot.cadData]에 저장한 CAD 결과를 실제로 편집 가능한 작업환경으로 연다:
/// 벽 생성/삭제, 문/창 추가, 가구 넣기, 선택/이동/복사/회전/크기 조정, Snap, 치수,
/// 거리 측정, Calibration(실제 치수 보존), Undo/Redo/History, 선택된 객체에만
/// 보이는 compact property panel, 도면 저장, DXF 내보내기.
///
/// 공통 상단바([SsTopBar])·좌측 메뉴([SsNavRail])는 [SsRouter]가 [SsStageScreen]
/// 으로 이미 감싸 준다 — 이 화면은 그 안쪽만 그린다. CAD를 편집해 [SsProject.
/// withStageData]로 [SsDataSlot.cadData]를 다시 쓸 때마다 revision이 올라,
/// 이미 만들어진 3D ISO([SsDataSlot.isoData])가 있다면 기존 [SsProject.
/// staleNotices]가 그대로 "업데이트 필요"로 표시한다(§완료조건 — 새 구현 불필요).
library;

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/ss_cad_editor_controller.dart';
import '../core/ss_editing.dart';
import '../core/ss_project.dart';
import '../core/ss_project_store.dart';
import '../core/ss_router.dart' show SsStageHeader;
import '../core/ss_stage.dart';
import '../models/cad_floor_plan.dart';
import '../models/floor_plan_geometry.dart';
import '../models/ss_cad_scene.dart';
import '../models/ss_spatial_model_json.dart';
import '../services/dxf_export_service.dart';
import '../services/e2e_dxf_exporter.dart';
import '../services/ss_project_store_provider.dart';
import '../theme/ss_master_theme.dart';
import 'cad_floor_plan_from_spatial_model_shim.dart' show cadFloorPlanFromSpatialModelCompat;

class CadEditorScreen extends StatefulWidget {
  const CadEditorScreen({
    super.key,
    this.projectId,
    this.projectStore,
    this.dxfExporter = const E2eDxfExporter(),
    this.dxfExportService = const DxfExportService(),
  });

  /// 연 프로젝트 id(없으면 — 라우팅 테스트처럼 — 저장 없이 맛보기만 한다).
  final String? projectId;

  /// 테스트에서 주입. 없으면 앱 공용 [SsProjectStoreProvider] 저장소.
  final SsProjectStore? projectStore;

  final E2eDxfExporter dxfExporter;
  final DxfExportService dxfExportService;

  @override
  State<CadEditorScreen> createState() => _CadEditorScreenState();
}

enum _CadEditorLoad { loading, loaded, missing, error }

class _CadEditorScreenState extends State<CadEditorScreen> {
  _CadEditorLoad _state = _CadEditorLoad.loading;
  SsProjectStore? _store;
  SsProject? _project;
  SsAutosaveController? _autosave;
  SsCadEditorController? _controller;
  double _zoom = 1.0;
  double _zoomGestureStart = 1.0;
  PointerDeviceKind _pointerKind = PointerDeviceKind.mouse;
  final TextEditingController _calibrationInput = TextEditingController();

  static const CadFloorPlan _emptyPlan = CadFloorPlan(sourceWidthPx: 1000, sourceHeightPx: 800, walls: [], openings: [], rooms: [], warnings: []);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final pid = widget.projectId;
    if (pid == null) {
      _setController(SsCadEditorController(initialScene: const SsCadScene(plan: _emptyPlan)));
      if (!mounted) return;
      setState(() => _state = _CadEditorLoad.loaded);
      return;
    }
    try {
      final store = widget.projectStore ?? await SsProjectStoreProvider.instance.store();
      final project = await store.load(pid);
      if (project == null) {
        if (!mounted) return;
        setState(() => _state = _CadEditorLoad.error);
        return;
      }
      final cadSlot = project.data[SsDataSlot.cadData];
      if (cadSlot == null) {
        if (!mounted) return;
        setState(() {
          _project = project;
          _state = _CadEditorLoad.missing;
        });
        return;
      }
      final scene = _sceneFromPayload(cadSlot.payload);
      if (scene == null) {
        if (!mounted) return;
        setState(() => _state = _CadEditorLoad.error);
        return;
      }
      if (!mounted) return;
      _setController(SsCadEditorController(initialScene: scene));
      setState(() {
        _store = store;
        _project = project;
        _autosave = SsAutosaveController(store: store, project: project);
        _state = _CadEditorLoad.loaded;
      });
    } catch (e, st) {
      // 네트워크를 쓰지 않는 화면이므로 네트워크 오류로 오분류하지 않는다 — 실제
      // 원인은 로그로 남기고 사용자에게는 일반 안내만 보인다.
      debugPrint('CadEditorScreen._load 실패 (${e.runtimeType}): $e\n$st');
      if (!mounted) return;
      setState(() => _state = _CadEditorLoad.error);
    }
  }

  /// SS010이 남긴 레거시 형식({'model': SSSpatialModel JSON, 'scale': {...}})과
  /// 이 화면이 다시 저장하는 신규 형식({'kind': 'ssCadScene', 'scene': {...}})을
  /// 모두 읽을 수 있어야 한다 — 둘 다 같은 [SsDataSlot.cadData] 칸을 쓰기 때문.
  SsCadScene? _sceneFromPayload(Map<String, Object?> payload) {
    if (payload['kind'] == 'ssCadScene') return SsCadScene.tryFromJson(payload['scene']);
    final model = ssSpatialModelFromJson(payload['model']);
    if (model == null) return null;
    final plan = cadFloorPlanFromSpatialModelCompat(model);
    final scaleJson = payload['scale'];
    final scale = scaleJson is Map ? _legacyScaleFromJson(scaleJson) : null;
    return SsCadScene(plan: plan, scale: scale);
  }

  FloorPlanScale? _legacyScaleFromJson(Map j) {
    final mmPerPixel = j['mmPerPixel'];
    final refLen = j['referenceLengthMm'];
    final start = j['referenceStart'];
    final end = j['referenceEnd'];
    if (mmPerPixel is! num || refLen is! num || start is! Map || end is! Map) return null;
    final sx = start['x'];
    final sy = start['y'];
    final ex = end['x'];
    final ey = end['y'];
    if (sx is! num || sy is! num || ex is! num || ey is! num) return null;
    final sourceName = j['source'];
    final source = ScaleSource.values.where((s) => s.name == sourceName).firstOrNull ?? ScaleSource.unknown;
    return FloorPlanScale(
      mmPerPixel: mmPerPixel.toDouble(),
      referenceStart: Point2(sx.toDouble(), sy.toDouble()),
      referenceEnd: Point2(ex.toDouble(), ey.toDouble()),
      referenceLengthMm: refLen.toDouble(),
      source: source,
    );
  }

  void _setController(SsCadEditorController c) {
    _controller?.history.removeListener(_onCommitted);
    _controller?.dispose();
    _controller = c..history.addListener(_onCommitted);
  }

  /// History에 실제로 커밋된 편집(생성·삭제·이동·수정)만 자동저장한다 — 드래그 중
  /// 미리보기 프레임마다는 저장하지 않는다.
  void _onCommitted() {
    final autosave = _autosave;
    final controller = _controller;
    if (autosave == null || controller == null) return;
    final updated = autosave.project.withStageData(
      SsDataSlot.cadData,
      {'kind': 'ssCadScene', 'scene': controller.scene.toJson()},
      label: 'CAD 편집',
    );
    _project = updated;
    autosave.update(updated);
    setState(() {});
  }

  Future<void> _saveNow() async {
    await _autosave?.saveNow();
  }

  Future<void> _exportDxf() async {
    final controller = _controller;
    if (controller == null) return;
    final result = widget.dxfExporter.export(controller.plan, scale: controller.scale);
    if (!mounted) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('ssCadExportSave'),
              leading: const Icon(Icons.save_outlined),
              title: const Text('기기에 저장'),
              onTap: () => Navigator.of(ctx).pop('save'),
            ),
            ListTile(
              key: const Key('ssCadExportShare'),
              leading: const Icon(Icons.ios_share),
              title: const Text('공유하기'),
              onTap: () => Navigator.of(ctx).pop('share'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    try {
      if (choice == 'save') {
        await widget.dxfExportService.save(result.dxfContent);
      } else {
        await widget.dxfExportService.share(result.dxfContent);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.isScaled ? 'DXF 내보내기 완료' : 'DXF 내보내기 완료(비실측 — 치수 보정을 먼저 해주세요)')));
    } catch (e, st) {
      debugPrint('CadEditorScreen._exportDxf 실패 (${e.runtimeType}): $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('DXF 내보내기에 실패했습니다. 다시 시도해주세요.')));
    }
  }

  @override
  void dispose() {
    _controller?.history.removeListener(_onCommitted);
    _controller?.dispose();
    _autosave?.dispose();
    _calibrationInput.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_state == _CadEditorLoad.error) {
      return const Center(
        child: Text('프로젝트를 불러오지 못했습니다. 프로젝트 관리에서 다시 열어주세요.', key: Key('ssCadEditorLoadError'), style: TextStyle(color: SsMasterTheme.textSecondary)),
      );
    }
    if (_state == _CadEditorLoad.loading) {
      return const Center(child: CircularProgressIndicator(key: Key('ssCadEditorLoading')));
    }
    if (_state == _CadEditorLoad.missing) {
      return const Center(
        child: Text('먼저 CAD 변환을 완료해주세요.', key: Key('ssCadEditorMissingData'), style: TextStyle(color: SsMasterTheme.textSecondary)),
      );
    }
    final controller = _controller!;
    return Padding(
      key: const Key('ssCadEditorScreen'),
      padding: const EdgeInsets.all(24),
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeaderRow(controller),
            const SizedBox(height: 16),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 3, child: _buildCanvasPanel(controller)),
                  const SizedBox(width: 16),
                  SizedBox(width: 320, child: _buildRightPanel(controller)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderRow(SsCadEditorController controller) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(child: SsStageHeader(stage: SsStage.cadEditor)),
        _buildViewModeToggle(),
        const SizedBox(width: 12),
        _buildUndoRedo(controller),
        const SizedBox(width: 12),
        _buildZoomControl(),
      ],
    );
  }

  Widget _buildViewModeToggle() {
    Widget seg(String label, {required bool selected, String? disabledTooltip, Key? key}) {
      final child = Container(
        key: key,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(gradient: selected ? SsMasterTheme.selectedItem : null, borderRadius: BorderRadius.circular(10)),
        child: Text(label, style: TextStyle(color: selected ? Colors.white : SsMasterTheme.textMuted, fontWeight: FontWeight.w700, fontSize: 13)),
      );
      return disabledTooltip == null ? child : Tooltip(message: disabledTooltip, child: child);
    }

    return Container(
      decoration: BoxDecoration(color: SsMasterTheme.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: SsMasterTheme.panelBorder)),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg('2D 도면', selected: true, key: const Key('ssCadViewMode2d')),
          seg('3D', selected: false, disabledTooltip: '3D ISO 변환을 먼저 완료해주세요', key: const Key('ssCadViewMode3d')),
          seg('ISO', selected: false, disabledTooltip: '3D ISO 변환을 먼저 완료해주세요', key: const Key('ssCadViewModeIso')),
        ],
      ),
    );
  }

  Widget _buildUndoRedo(SsCadEditorController controller) {
    return Row(
      children: [
        IconButton(key: const Key('ssCadUndo'), tooltip: '실행 취소', onPressed: controller.canUndo ? controller.undo : null, icon: const Icon(Icons.undo), color: SsMasterTheme.textSecondary),
        IconButton(key: const Key('ssCadRedo'), tooltip: '다시 실행', onPressed: controller.canRedo ? controller.redo : null, icon: const Icon(Icons.redo), color: SsMasterTheme.textSecondary),
      ],
    );
  }

  Widget _buildZoomControl() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(color: SsMasterTheme.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: SsMasterTheme.panelBorder)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(key: const Key('ssCadZoomOut'), onPressed: () => setState(() => _zoom = (_zoom - 0.1).clamp(0.5, 3.0)), icon: const Icon(Icons.remove, size: 18), color: SsMasterTheme.textSecondary),
          SizedBox(width: 48, child: Text('${(_zoom * 100).round()}%', key: const Key('ssCadZoomLabel'), textAlign: TextAlign.center, style: const TextStyle(color: SsMasterTheme.textPrimary, fontWeight: FontWeight.w700))),
          IconButton(key: const Key('ssCadZoomIn'), onPressed: () => setState(() => _zoom = (_zoom + 0.1).clamp(0.5, 3.0)), icon: const Icon(Icons.add, size: 18), color: SsMasterTheme.textSecondary),
        ],
      ),
    );
  }

  Point2 _toDoc(Offset local, Size size) => Point2((local.dx / size.width).clamp(0.0, 1.0), (local.dy / size.height).clamp(0.0, 1.0));

  void _onCanvasTap(SsCadEditorController controller, Point2 p) {
    switch (controller.tool) {
      case SsCadTool.select:
        controller.selectAt(p);
      case SsCadTool.addDoor:
        controller.addOpeningAtPoint(p, OpeningType.door);
      case SsCadTool.addWindow:
        controller.addOpeningAtPoint(p, OpeningType.window);
      case SsCadTool.addFurniture:
        controller.addFurnitureAt(SsCadFurnitureKind.other, p);
      case SsCadTool.measure:
        controller.measureTapAt(p);
      case SsCadTool.addWall:
      case SsCadTool.calibrate:
        break;
    }
  }

  Widget _buildCanvasPanel(SsCadEditorController controller) {
    final plan = controller.plan;
    final aspect = plan.sourceWidthPx > 0 && plan.sourceHeightPx > 0 ? plan.sourceWidthPx / plan.sourceHeightPx : 4 / 3;
    Point2? wallDragStart;
    return Container(
      key: const Key('ssCadCanvasBox'),
      decoration: BoxDecoration(color: const Color(0xFF081628), borderRadius: BorderRadius.circular(16), border: Border.all(color: SsMasterTheme.panelBorder)),
      clipBehavior: Clip.antiAlias,
      child: Center(
        child: AspectRatio(
          aspectRatio: aspect,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest;
              return Transform.scale(
                scale: _zoom,
                child: Listener(
                  onPointerDown: (e) => _pointerKind = e.kind,
                  child: GestureDetector(
                    key: const Key('ssCadCanvas'),
                    behavior: HitTestBehavior.opaque,
                    onScaleStart: (d) {
                      _zoomGestureStart = _zoom;
                      if (d.pointerCount >= 2) return;
                      if (controller.tool == SsCadTool.addWall) wallDragStart = _toDoc(d.localFocalPoint, size);
                      if (controller.tool == SsCadTool.calibrate) wallDragStart = _toDoc(d.localFocalPoint, size);
                    },
                    onScaleUpdate: (d) {
                      if (d.pointerCount >= 2) {
                        setState(() => _zoom = (_zoomGestureStart * d.scale).clamp(0.5, 3.0));
                      }
                    },
                    onScaleEnd: (d) {
                      final start = wallDragStart;
                      wallDragStart = null;
                      if (start == null) return;
                      if (controller.tool == SsCadTool.addWall) {
                        // 끝점은 onScaleUpdate의 마지막 focal point를 따로 추적하지 않고,
                        // 터치 탭-탭 흐름으로도 벽을 그릴 수 있게 탭 핸들러에서 처리한다.
                      }
                    },
                    onTapUp: (d) {
                      final p = _toDoc(d.localPosition, size);
                      if (controller.tool == SsCadTool.addWall) {
                        final pending = wallDragStart;
                        if (pending == null) {
                          wallDragStart = p;
                        } else {
                          controller.addWallDrag(pending, p);
                          wallDragStart = null;
                        }
                        return;
                      }
                      if (controller.tool == SsCadTool.calibrate) {
                        final pending = wallDragStart;
                        if (pending == null) {
                          wallDragStart = p;
                        } else {
                          controller.startCalibrationDrag(pending, p);
                          wallDragStart = null;
                        }
                        return;
                      }
                      _onCanvasTap(controller, p);
                    },
                    onPanStart: controller.tool != SsCadTool.select
                        ? null
                        : (d) {
                            final p = _toDoc(d.localPosition, size);
                            controller.selectAt(p);
                          },
                    onPanUpdate: controller.tool != SsCadTool.select
                        ? null
                        : (d) {
                            final p = _toDoc(d.localPosition, size);
                            if (controller.selection.objectType == '벽') {
                              controller.moveSelectedWallEndpoint(true, p);
                            } else if (controller.selection.objectType == '가구') {
                              controller.moveSelectedFurniture(p);
                            }
                          },
                    child: CustomPaint(size: size, painter: _SsCadPainter(controller: controller)),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _panel({required String titleIcon, required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: SsMasterTheme.panel, borderRadius: BorderRadius.circular(14), border: Border.all(color: SsMasterTheme.panelBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [Text(title, style: const TextStyle(color: SsMasterTheme.textPrimary, fontWeight: FontWeight.w800, fontSize: 14))]),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _buildRightPanel(SsCadEditorController controller) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _panel(titleIcon: '', title: '도면 속성', child: _buildSelectionProperties(controller)),
          const SizedBox(height: 14),
          _panel(titleIcon: '', title: '작업 도구', child: _buildTools(controller)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  key: const Key('ssCadSaveButton'),
                  onPressed: () => unawaited(_saveNow()),
                  style: ElevatedButton.styleFrom(backgroundColor: SsMasterTheme.neonBlue, padding: const EdgeInsets.symmetric(vertical: 14)),
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('도면 저장'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  key: const Key('ssCadExportButton'),
                  onPressed: () => unawaited(_exportDxf()),
                  style: ElevatedButton.styleFrom(backgroundColor: SsMasterTheme.neonPurple, padding: const EdgeInsets.symmetric(vertical: 14)),
                  icon: const Icon(Icons.file_present_outlined, size: 18),
                  label: const Text('CAD 파일 내보내기'),
                ),
              ),
            ],
          ),
          if (_autosave != null) ...[
            const SizedBox(height: 10),
            ListenableBuilder(
              listenable: _autosave!,
              builder: (context, _) => Text(_autosave!.state.label, key: const Key('ssCadSaveState'), style: const TextStyle(color: SsMasterTheme.textMuted, fontSize: 12)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value, {Key? valueKey}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: SsMasterTheme.textSecondary, fontSize: 13)),
          Text(value, key: valueKey, style: const TextStyle(color: SsMasterTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _editableMmRow(String label, double? valueMm, Key fieldKey, ValueChanged<double> onSubmit) {
    final controllerText = TextEditingController(text: valueMm == null ? '' : valueMm.round().toString());
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: SsMasterTheme.textSecondary, fontSize: 13))),
          SizedBox(
            width: 90,
            child: TextField(
              key: fieldKey,
              controller: controllerText,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: SsMasterTheme.textPrimary, fontSize: 13),
              decoration: const InputDecoration(isDense: true, suffixText: 'mm', contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
              onSubmitted: (text) {
                final v = double.tryParse(text);
                if (v != null && v > 0) onSubmit(v);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionProperties(SsCadEditorController controller) {
    final sel = controller.selection;
    if (sel.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('요소를 선택하면 치수를 확인할 수 있습니다.', key: Key('ssCadNoSelection'), style: TextStyle(color: SsMasterTheme.textSecondary, fontSize: 13)),
      );
    }
    final props = sel.properties;
    final children = <Widget>[
      Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('선택된 요소', style: const TextStyle(color: SsMasterTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w700))),
      _row('종류', sel.objectType, valueKey: const Key('ssCadSelectedType')),
    ];
    if (sel.objectType == '벽') {
      children.add(_editableMmRow('길이', (props['lengthMm'] as num?)?.toDouble(), const Key('ssCadPropertyLength'), controller.setSelectedWallLengthMm));
      children.add(_editableMmRow('두께', (props['thicknessMm'] as num?)?.toDouble(), const Key('ssCadPropertyThickness'), controller.setSelectedWallThicknessMm));
      children.add(_editableMmRow('높이', (props['heightMm'] as num?)?.toDouble(), const Key('ssCadPropertyHeight'), controller.setSelectedWallHeightMm));
    } else if (sel.objectType == '문' || sel.objectType == '창') {
      children.add(_editableMmRow('폭', (props['widthMm'] as num?)?.toDouble(), const Key('ssCadPropertyWidth'), controller.setSelectedOpeningWidthMm));
    } else if (sel.objectType == '공간') {
      final areaM2 = (props['areaM2'] as num?)?.toDouble();
      children.add(_row('면적', areaM2 == null ? '알 수 없음' : '${areaM2.toStringAsFixed(1)} m²', valueKey: const Key('ssCadPropertyArea')));
    } else if (sel.objectType == '가구') {
      children.add(_editableMmRow('폭', (props['widthMm'] as num?)?.toDouble(), const Key('ssCadPropertyFurnitureWidth'), controller.setSelectedFurnitureWidthMm));
      children.add(_editableMmRow('깊이', (props['depthMm'] as num?)?.toDouble(), const Key('ssCadPropertyFurnitureDepth'), controller.setSelectedFurnitureDepthMm));
      children.add(_row('회전', '${(props['rotation'] as num? ?? 0).round()}°', valueKey: const Key('ssCadPropertyRotation')));
    }
    children.add(const SizedBox(height: 8));
    children.add(
      Row(
        children: [
          if (sel.objectType == '벽' || sel.objectType == '가구')
            Expanded(
              child: TextButton.icon(
                key: const Key('ssCadDuplicateSelected'),
                onPressed: controller.duplicateSelected,
                icon: const Icon(Icons.copy_outlined, size: 16),
                label: const Text('복사'),
              ),
            ),
          if (sel.objectType == '가구')
            Expanded(
              child: TextButton.icon(
                key: const Key('ssCadRotateSelected'),
                onPressed: () => controller.rotateSelectedFurniture(90),
                icon: const Icon(Icons.rotate_right, size: 16),
                label: const Text('회전'),
              ),
            ),
          Expanded(
            child: TextButton.icon(
              key: const Key('ssCadDeleteSelected'),
              onPressed: controller.deleteSelected,
              icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
              label: const Text('삭제', style: TextStyle(color: Colors.redAccent)),
            ),
          ),
        ],
      ),
    );
    if (controller.tool == SsCadTool.measure) {
      final d = controller.measureDistanceMm;
      children.add(const SizedBox(height: 8));
      children.add(Text(d == null ? '두 점을 찍어 거리를 재보세요.' : '거리: ${d.round()}mm', key: const Key('ssCadMeasureResult'), style: const TextStyle(color: SsMasterTheme.neonCyan, fontSize: 12)));
    }
    if (controller.tool == SsCadTool.calibrate && controller.hasCalibrationSelection) {
      children.add(const SizedBox(height: 10));
      children.add(_buildCalibrationInput(controller));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  Widget _buildCalibrationInput(SsCadEditorController controller) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: const Key('ssCadCalibrationInput'),
            controller: _calibrationInput,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: SsMasterTheme.textPrimary, fontSize: 13),
            decoration: const InputDecoration(isDense: true, hintText: '실제 길이(mm)', contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          key: const Key('ssCadCalibrationApply'),
          onPressed: () {
            final v = double.tryParse(_calibrationInput.text);
            if (v != null && v > 0) controller.applyCalibrationLengthMm(v);
            _calibrationInput.clear();
          },
          child: const Text('적용'),
        ),
      ],
    );
  }

  Widget _toolButton({required Key key, required IconData icon, required String label, required VoidCallback? onTap, bool selected = false, bool enabled = true}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: key,
            borderRadius: BorderRadius.circular(10),
            onTap: enabled ? onTap : null,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                gradient: selected ? SsMasterTheme.selectedItem : null,
                color: selected ? null : SsMasterTheme.background.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: SsMasterTheme.panelBorder),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: enabled ? (selected ? Colors.white : SsMasterTheme.textSecondary) : SsMasterTheme.textMuted),
                  const SizedBox(height: 4),
                  Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: enabled ? (selected ? Colors.white : SsMasterTheme.textSecondary) : SsMasterTheme.textMuted)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTools(SsCadEditorController controller) {
    final hasWallSelected = controller.selection.objectType == '벽';
    return Column(
      children: [
        Row(
          children: [
            _toolButton(
              key: const Key('ssCadToolAddWall'),
              icon: Icons.view_agenda_outlined,
              label: '벽체 생성',
              selected: controller.tool == SsCadTool.addWall,
              onTap: () => controller.setTool(controller.tool == SsCadTool.addWall ? SsCadTool.select : SsCadTool.addWall),
            ),
            _toolButton(
              key: const Key('ssCadToolDeleteWall'),
              icon: Icons.delete_sweep_outlined,
              label: '벽체 삭제',
              enabled: hasWallSelected,
              onTap: controller.deleteSelected,
            ),
          ],
        ),
        Row(
          children: [
            _toolButton(
              key: const Key('ssCadToolAddDoor'),
              icon: Icons.sensor_door_outlined,
              label: '문 추가',
              selected: controller.tool == SsCadTool.addDoor,
              onTap: () => controller.setTool(controller.tool == SsCadTool.addDoor ? SsCadTool.select : SsCadTool.addDoor),
            ),
            _toolButton(
              key: const Key('ssCadToolAddWindow'),
              icon: Icons.window_outlined,
              label: '창문 추가',
              selected: controller.tool == SsCadTool.addWindow,
              onTap: () => controller.setTool(controller.tool == SsCadTool.addWindow ? SsCadTool.select : SsCadTool.addWindow),
            ),
          ],
        ),
        Row(
          children: [
            _toolButton(
              key: const Key('ssCadToolAddFurniture'),
              icon: Icons.chair_outlined,
              label: '가구 넣기',
              selected: controller.tool == SsCadTool.addFurniture,
              onTap: () => controller.setTool(controller.tool == SsCadTool.addFurniture ? SsCadTool.select : SsCadTool.addFurniture),
            ),
            _toolButton(
              key: const Key('ssCadToolMeasure'),
              icon: Icons.straighten,
              label: '거리 측정',
              selected: controller.tool == SsCadTool.measure,
              onTap: () => controller.setTool(controller.tool == SsCadTool.measure ? SsCadTool.select : SsCadTool.measure),
            ),
          ],
        ),
        Row(
          children: [
            _toolButton(
              key: const Key('ssCadToolCalibrate'),
              icon: Icons.rule,
              label: '치수 보정',
              selected: controller.tool == SsCadTool.calibrate,
              onTap: () => controller.setTool(controller.tool == SsCadTool.calibrate ? SsCadTool.select : SsCadTool.calibrate),
            ),
            _toolButton(
              key: const Key('ssCadToolSnap'),
              icon: controller.snapEnabled ? Icons.grid_on : Icons.grid_off,
              label: 'Snap',
              selected: controller.snapEnabled,
              onTap: () => controller.setSnapEnabled(!controller.snapEnabled),
            ),
          ],
        ),
      ],
    );
  }
}

/// 2D CAD 캔버스 — 벽/문·창/공간/가구를 그리고 선택 강조·측정선·Calibration
/// 선택을 겹쳐 그린다. 좌표는 전부 정규화(0~1) — [CadFloorPlan]과 같은 좌표계.
class _SsCadPainter extends CustomPainter {
  const _SsCadPainter({required this.controller});
  final SsCadEditorController controller;

  Offset _pt(Point2 p, Size size) => Offset(p.x * size.width, p.y * size.height);

  @override
  void paint(Canvas canvas, Size size) {
    final plan = controller.plan;
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);

    for (final room in plan.rooms) {
      if (room.polygon.length < 3) continue;
      final path = Path()..moveTo(_pt(room.polygon.first, size).dx, _pt(room.polygon.first, size).dy);
      for (final p in room.polygon.skip(1)) {
        final o = _pt(p, size);
        path.lineTo(o.dx, o.dy);
      }
      path.close();
      final selected = controller.selection.objectType == '공간' && controller.selection.objectId == room.id;
      canvas.drawPath(path, Paint()..color = (selected ? SsMasterTheme.neonBlue : const Color(0xFFBEE3F8)).withValues(alpha: 0.5));
    }

    for (final wall in plan.walls) {
      final selected = controller.selection.objectType == '벽' && controller.selection.objectId == wall.id;
      final paint = Paint()
        ..color = selected ? SsMasterTheme.neonBlue : const Color(0xFF203A5C)
        ..strokeWidth = (wall.thicknessNormalized * size.shortestSide).clamp(2.0, 14.0) + (selected ? 2 : 0)
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(_pt(wall.start, size), _pt(wall.end, size), paint);
    }

    for (final opening in plan.openings) {
      final selected = controller.selection.objectId == opening.id && (controller.selection.objectType == '문' || controller.selection.objectType == '창');
      final paint = Paint()..color = selected ? SsMasterTheme.neonBlue : (opening.type == OpeningType.door ? SsMasterTheme.neonOrange : SsMasterTheme.neonCyan);
      canvas.drawCircle(_pt(opening.center, size), selected ? 7 : 5, paint);
    }

    for (final f in controller.scene.furniture) {
      final selected = controller.selection.objectType == '가구' && controller.selection.objectId == f.id;
      final center = _pt(f.center, size);
      final rect = Rect.fromCenter(center: Offset.zero, width: f.widthNormalized * size.width, height: f.depthNormalized * size.height);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(f.rotationDegrees * 3.14159265 / 180);
      canvas.drawRect(rect, Paint()..color = (selected ? SsMasterTheme.neonBlue : SsMasterTheme.neonPurple).withValues(alpha: 0.75));
      canvas.restore();
    }

    final cs = controller.calibrationStart;
    final ce = controller.calibrationEnd;
    if (cs != null && ce != null) {
      canvas.drawLine(_pt(cs, size), _pt(ce, size), Paint()..color = SsMasterTheme.neonOrange..strokeWidth = 3);
    }

    final ms = controller.measureStart;
    final me = controller.measureEnd;
    if (ms != null) {
      canvas.drawCircle(_pt(ms, size), 4, Paint()..color = SsMasterTheme.neonCyan);
      if (me != null) {
        canvas.drawLine(_pt(ms, size), _pt(me, size), Paint()..color = SsMasterTheme.neonCyan..strokeWidth = 2);
        canvas.drawCircle(_pt(me, size), 4, Paint()..color = SsMasterTheme.neonCyan);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SsCadPainter oldDelegate) => true;
}
