/// SS005 — MASTER UI 4-1(직접 그리기). 사용자가 Mouse/Touch/Pen으로 벽·문·창을 그려 평면도를 만들고,
/// 완성되면 CAD FLOW(§2 SsFlows — 직접 그리기 흐름은 평면도 업로드/보정 단계 없이 바로 CAD 변환으로 이어진다)로
/// 넘어간다. 결과는 Raster 이미지가 아니라 [SsDrawScene](벽·개구부) 구조화 데이터로 저장한다.
///
/// 좌/상단 숫자 ruler, 우측 "공간 인식 결과" 패널은 MASTER 기준(§ 작업 내용)에 따라 이 화면에 두지 않는다.
/// 공통 상단바([SsTopBar])·좌측 메뉴([SsNavRail])는 [SsRouter]가 [SsStageScreen]으로 이미 감싸 준다 — 이 화면은
/// 그 안쪽(도구모음+캔버스+하단 도구모음)만 그린다.
library;

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/ss_draw_editor_controller.dart';
import '../core/ss_editing.dart';
import '../core/ss_project.dart';
import '../core/ss_project_store.dart';
import '../core/ss_stage.dart';
import '../models/ss_draw_scene.dart';
import '../models/workspace_viewport_transform.dart';
import '../services/ss_project_store_provider.dart';
import '../theme/ss_master_theme.dart';

class DirectDrawScreen extends StatefulWidget {
  const DirectDrawScreen({super.key, this.projectId, this.projectStore});

  /// 연 프로젝트 id(없으면 프로젝트 없이 맛보기만 — 자동저장은 하지 않는다).
  final String? projectId;

  /// 테스트에서 주입. 없으면 앱 공용 [SsProjectStoreProvider] 저장소.
  final SsProjectStore? projectStore;

  @override
  State<DirectDrawScreen> createState() => _DirectDrawScreenState();
}

enum _DrawLoad { loading, loaded, error }

/// 문서(mm) 1mm를 화면 몇 px로 그릴지(기준 배율 — 실제 화면 배율은 여기에 [SsDrawEditorController.viewport].scale이 곱해진다).
const double _pxPerMm = 0.15;

class _DirectDrawScreenState extends State<DirectDrawScreen> {
  _DrawLoad _state = _DrawLoad.loading;
  SsProjectStore? _store;
  SsProject? _project;
  SsAutosaveController? _autosave;
  late SsDrawEditorController _draw;

  PointerDeviceKind _pointerKind = PointerDeviceKind.mouse;
  SsGesture? _activeGesture;
  Offset _gestureStartLocal = Offset.zero;
  WorkspaceViewportTransform _gestureStartViewport = WorkspaceViewportTransform.identity;
  SsDrawPoint _dragStartDoc = const SsDrawPoint(0, 0);

  @override
  void initState() {
    super.initState();
    _draw = SsDrawEditorController()..history.addListener(_onDrawCommitted);
    if (widget.projectId == null) {
      _state = _DrawLoad.loaded;
    } else {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final pid = widget.projectId!;
    try {
      final store = widget.projectStore ?? await SsProjectStoreProvider.instance.store();
      final project = await store.load(pid);
      if (project == null) {
        if (!mounted) return;
        setState(() => _state = _DrawLoad.error);
        return;
      }
      final initialScene = SsDrawScene.tryFromJson(project.data[SsDataSlot.userCorrections]?.payload['scene']);
      if (!mounted) return;
      _draw.history.removeListener(_onDrawCommitted);
      _draw.dispose();
      setState(() {
        _store = store;
        _project = project;
        _autosave = SsAutosaveController(store: store, project: project);
        _draw = SsDrawEditorController(initialScene: initialScene)..history.addListener(_onDrawCommitted);
        _state = _DrawLoad.loaded;
      });
    } catch (e, st) {
      // 네트워크를 쓰지 않는 화면이므로 네트워크 오류로 오분류하지 않는다 — 실제 원인은 로그로 남기고
      // 사용자에게는 일반 안내만 보인다.
      debugPrint('DirectDrawScreen._load 실패 (${e.runtimeType}): $e\n$st');
      if (!mounted) return;
      setState(() => _state = _DrawLoad.error);
    }
  }

  /// History에 실제로 커밋된 변경(벽/개구부 추가·이동·삭제·수정)만 자동저장한다 — 드래그 중 미리보기
  /// 프레임마다는 저장하지 않는다(§ history.addListener는 push/undo/redo에서만 알린다).
  void _onDrawCommitted() {
    final autosave = _autosave;
    if (autosave == null) return;
    final updated = autosave.project.withStageData(
      SsDataSlot.userCorrections,
      {'kind': 'directDraw', 'scene': _draw.scene.toJson()},
      label: '평면도 수정',
    );
    _project = updated;
    autosave.update(updated);
  }

  Future<void> _goNext() async {
    final project = _project;
    final autosave = _autosave;
    if (project == null || autosave == null || _draw.scene.walls.isEmpty) return;
    await autosave.saveNow();
    final current = autosave.project;
    final next = SsFlows.next(current.sourceType, current.currentStage);
    if (next == null) return;
    final moved = current.moveTo(next);
    try {
      await (_store ?? autosave.store).save(moved);
    } catch (e, st) {
      debugPrint('DirectDrawScreen._goNext 저장 실패 (${e.runtimeType}): $e\n$st');
    }
    if (!mounted) return;
    await Navigator.of(context).pushNamed(next.routeName, arguments: project.info.id);
  }

  SsDrawPoint _toDoc(Offset local) {
    final fitted = _draw.viewport.invert(local);
    return SsDrawPoint(fitted.dx / _pxPerMm, fitted.dy / _pxPerMm);
  }

  void _onPointerDown(PointerDownEvent e) => _pointerKind = e.kind;

  void _onPointerSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      final factor = e.scrollDelta.dy > 0 ? 0.9 : 1.1;
      _draw.zoomByFactor(factor, focal: e.localPosition);
    }
  }

  void _onScaleStart(ScaleStartDetails d) {
    _gestureStartLocal = d.localFocalPoint;
    _gestureStartViewport = _draw.viewport;
    if (d.pointerCount >= 2) {
      _activeGesture = SsGesture.pinchZoom;
      return;
    }
    final kind = SsInput.kindOf(_pointerKind);
    final doc = _toDoc(d.localFocalPoint);
    switch (_draw.tool) {
      case SsDrawTool.wall:
        final gesture = SsInput.primaryDrag(kind, drawToolActive: true);
        _activeGesture = gesture;
        if (gesture == SsGesture.draw) _draw.beginWallDraft(doc);
      case SsDrawTool.select:
      case SsDrawTool.move:
        final gesture = SsInput.primaryDrag(kind, drawToolActive: false);
        _activeGesture = gesture;
        if (gesture == SsGesture.drag) {
          _draw.selectAt(doc);
          if (!_draw.selection.isEmpty) {
            _draw.beginDrag();
            _dragStartDoc = doc;
          }
        }
      case SsDrawTool.door:
      case SsDrawTool.window:
      case SsDrawTool.delete:
        _activeGesture = SsInput.primaryDrag(kind, drawToolActive: false);
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (_activeGesture == SsGesture.pinchZoom || d.pointerCount >= 2) {
      _applyPanZoom(d);
      return;
    }
    switch (_activeGesture) {
      case SsGesture.pan:
        _applyPanZoom(d);
      case SsGesture.draw:
        _draw.updateWallDraft(_toDoc(d.localFocalPoint));
      case SsGesture.drag:
        if (_draw.isDragging) {
          final doc = _toDoc(d.localFocalPoint);
          _draw.updateDrag(doc.xMm - _dragStartDoc.xMm, doc.yMm - _dragStartDoc.yMm);
        }
      case SsGesture.select:
      case SsGesture.zoom:
      case SsGesture.pinchZoom:
      case null:
        break;
    }
  }

  void _applyPanZoom(ScaleUpdateDetails d) {
    final newScale = (_gestureStartViewport.scale * d.scale).clamp(WorkspaceViewportTransform.minScale, WorkspaceViewportTransform.maxScale);
    final fitted = _gestureStartViewport.invert(_gestureStartLocal);
    final newOffset = d.localFocalPoint - fitted * newScale;
    _draw.setViewport(WorkspaceViewportTransform(scale: newScale, offset: newOffset));
  }

  void _onScaleEnd(ScaleEndDetails d) {
    switch (_activeGesture) {
      case SsGesture.draw:
        if (_draw.tool == SsDrawTool.wall) _draw.commitWallDraft();
      case SsGesture.drag:
        if (_draw.isDragging) _draw.endDrag();
      case SsGesture.pan:
      case SsGesture.select:
      case SsGesture.zoom:
      case SsGesture.pinchZoom:
      case null:
        break;
    }
    _activeGesture = null;
  }

  void _onTapUp(TapUpDetails d) {
    final doc = _toDoc(d.localPosition);
    final isTouch = SsInput.kindOf(_pointerKind) == SsInputKind.touch;
    switch (_draw.tool) {
      case SsDrawTool.wall:
        // 마우스/스타일러스는 드래그로 긋는다(onScaleStart~End) — 탭 흐름과 섞이지 않게 터치만 받는다.
        if (!isTouch) return;
        if (_draw.wallDraftStart == null) {
          _draw.beginWallDraft(doc);
        } else {
          _draw.updateWallDraft(doc);
          _draw.commitWallDraft();
        }
      case SsDrawTool.select:
      case SsDrawTool.move:
        if (isTouch) _draw.selectAt(doc);
      case SsDrawTool.door:
        _draw.addOpeningAt(SsDrawOpeningKind.door, doc);
      case SsDrawTool.window:
        _draw.addOpeningAt(SsDrawOpeningKind.window, doc);
      case SsDrawTool.delete:
        _draw.selectAt(doc);
        _draw.deleteSelected();
    }
  }

  @override
  void dispose() {
    _draw.history.removeListener(_onDrawCommitted);
    _draw.dispose();
    _autosave?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_state == _DrawLoad.error) {
      return const Center(
        child: Text(
          '평면도를 불러오지 못했습니다. 프로젝트 관리에서 다시 열어주세요.',
          key: Key('ssDrawLoadError'),
          style: TextStyle(color: SsMasterTheme.textSecondary),
        ),
      );
    }
    if (_state == _DrawLoad.loading) {
      return const Center(child: CircularProgressIndicator(key: Key('ssDrawLoading')));
    }
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) unawaited(_autosave?.saveNow());
      },
      child: ListenableBuilder(
        listenable: _draw,
        builder: (context, _) => Column(
          key: const Key('ssDrawScreen'),
          children: [
            _buildTopToolbar(),
            const Divider(height: 1, color: SsMasterTheme.panelBorder),
            Expanded(
              child: Stack(
                children: [
                  Listener(
                    onPointerDown: _onPointerDown,
                    onPointerSignal: _onPointerSignal,
                    child: GestureDetector(
                      key: const Key('ssDrawCanvas'),
                      behavior: HitTestBehavior.opaque,
                      onScaleStart: _onScaleStart,
                      onScaleUpdate: _onScaleUpdate,
                      onScaleEnd: _onScaleEnd,
                      onTapUp: _onTapUp,
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _SsDrawPainter(
                          scene: _draw.scene,
                          draftStart: _draw.wallDraftStart,
                          draftEnd: _draw.wallDraftEnd,
                          selectedType: _draw.selection.objectType,
                          selectedId: _draw.selection.objectId,
                          viewport: _draw.viewport,
                          gridMm: _draw.gridMm,
                          gridVisible: _draw.gridVisible,
                        ),
                      ),
                    ),
                  ),
                  Positioned(left: 16, top: 16, child: _buildHint()),
                  if (!_draw.selection.isEmpty) Positioned(right: 16, top: 16, child: _SelectionPanel(controller: _draw)),
                ],
              ),
            ),
            const Divider(height: 1, color: SsMasterTheme.panelBorder),
            _buildBottomToolbar(),
          ],
        ),
      ),
    );
  }

  Widget _buildHint() {
    final text = switch (_draw.tool) {
      SsDrawTool.select => '벽·문·창을 눌러 선택하세요',
      SsDrawTool.move => '이동할 벽·문·창을 선택한 뒤 드래그하세요(펜/마우스)',
      SsDrawTool.wall => '드래그해서 벽을 그리세요 · 터치는 두 번 탭으로 긋습니다',
      SsDrawTool.door => '벽 위를 눌러 문을 놓으세요',
      SsDrawTool.window => '벽 위를 눌러 창문을 놓으세요',
      SsDrawTool.delete => '지울 벽·문·창을 누르세요',
    };
    return Container(
      key: const Key('ssDrawHint'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: SsMasterTheme.panel.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: const TextStyle(color: SsMasterTheme.textSecondary, fontSize: 13)),
    );
  }

  Widget _buildTopToolbar() {
    return Container(
      key: const Key('ssDrawTopToolbar'),
      height: 96,
      color: SsMasterTheme.panel,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _ToolButton(toolKey: 'select', icon: Icons.near_me_outlined, label: '선택', selected: _draw.tool == SsDrawTool.select, onTap: () => _draw.setTool(SsDrawTool.select)),
            const SizedBox(width: 18),
            _ToolGroup(
              title: '그리기',
              children: [
                _ToolButton(toolKey: 'move', icon: Icons.open_with, label: '이동', selected: _draw.tool == SsDrawTool.move, onTap: () => _draw.setTool(SsDrawTool.move)),
                _ToolButton(toolKey: 'delete', icon: Icons.delete_outline, label: '삭제', selected: _draw.tool == SsDrawTool.delete, onTap: () => _draw.setTool(SsDrawTool.delete)),
              ],
            ),
            const SizedBox(width: 18),
            _ToolGroup(
              title: '구조',
              children: [
                _ToolButton(toolKey: 'wall', icon: Icons.view_agenda_outlined, label: '벽체', selected: _draw.tool == SsDrawTool.wall, onTap: () => _draw.setTool(SsDrawTool.wall)),
              ],
            ),
            const SizedBox(width: 18),
            _ToolGroup(
              title: '개구부',
              children: [
                _ToolButton(toolKey: 'door', icon: Icons.sensor_door_outlined, label: '문', selected: _draw.tool == SsDrawTool.door, onTap: () => _draw.setTool(SsDrawTool.door)),
                _ToolButton(toolKey: 'window', icon: Icons.window_outlined, label: '창문', selected: _draw.tool == SsDrawTool.window, onTap: () => _draw.setTool(SsDrawTool.window)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveIndicator() {
    final autosave = _autosave;
    if (autosave == null) {
      return const Text('프로젝트 없음', key: Key('ssDrawSaveState'), style: TextStyle(color: SsMasterTheme.textMuted, fontSize: 12));
    }
    return ListenableBuilder(
      listenable: autosave,
      builder: (context, _) => Text(autosave.state.label, key: const Key('ssDrawSaveState'), style: const TextStyle(color: SsMasterTheme.textMuted, fontSize: 12)),
    );
  }

  Widget _buildGridMenu() {
    const options = [50.0, 100.0, 200.0, 300.0, 500.0];
    return PopupMenuButton<double>(
      key: const Key('ssDrawGridSize'),
      initialValue: _draw.gridMm,
      color: SsMasterTheme.panel,
      onSelected: _draw.setGridMm,
      itemBuilder: (context) => [
        for (final v in options) PopupMenuItem<double>(value: v, child: Text(SsLength.mm(v).format(SsLengthUnit.mm), style: const TextStyle(color: Colors.white))),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(border: Border.all(color: SsMasterTheme.panelBorder), borderRadius: BorderRadius.circular(8)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(SsLength.mm(_draw.gridMm).format(SsLengthUnit.mm), style: const TextStyle(color: Colors.white)),
            const Icon(Icons.arrow_drop_down, color: SsMasterTheme.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomToolbar() {
    final canProceed = _project != null && _draw.scene.walls.isNotEmpty;
    return Container(
      key: const Key('ssDrawBottomToolbar'),
      height: 68,
      color: SsMasterTheme.panel,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _buildSaveIndicator(),
          const SizedBox(width: 16),
          IconButton(key: const Key('ssDrawUndo'), onPressed: _draw.canUndo ? _draw.undo : null, icon: const Icon(Icons.undo), color: SsMasterTheme.textSecondary),
          IconButton(key: const Key('ssDrawRedo'), onPressed: _draw.canRedo ? _draw.redo : null, icon: const Icon(Icons.redo), color: SsMasterTheme.textSecondary),
          const SizedBox(width: 8),
          IconButton(
            key: const Key('ssDrawZoomOut'),
            onPressed: () => _draw.zoomByFactor(0.85, focal: const Offset(400, 300)),
            icon: const Icon(Icons.zoom_out),
            color: SsMasterTheme.textSecondary,
          ),
          IconButton(
            key: const Key('ssDrawZoomIn'),
            onPressed: () => _draw.zoomByFactor(1.15, focal: const Offset(400, 300)),
            icon: const Icon(Icons.zoom_in),
            color: SsMasterTheme.textSecondary,
          ),
          IconButton(key: const Key('ssDrawFit'), onPressed: _draw.resetViewport, icon: const Icon(Icons.fit_screen_outlined), color: SsMasterTheme.textSecondary),
          const Spacer(),
          _buildGridMenu(),
          const SizedBox(width: 8),
          IconButton(
            key: const Key('ssDrawGridToggle'),
            onPressed: () => _draw.setGridVisible(!_draw.gridVisible),
            icon: Icon(Icons.grid_on, color: _draw.gridVisible ? SsMasterTheme.neonBlue : SsMasterTheme.textSecondary),
          ),
          IconButton(
            key: const Key('ssDrawSnapToggle'),
            onPressed: () => _draw.setSnapEnabled(!_draw.snapEnabled),
            icon: Icon(Icons.push_pin_outlined, color: _draw.snapEnabled ? SsMasterTheme.neonBlue : SsMasterTheme.textSecondary),
          ),
          const SizedBox(width: 16),
          Material(
            color: Colors.transparent,
            child: InkWell(
              key: const Key('ssDrawNext'),
              borderRadius: BorderRadius.circular(12),
              onTap: canProceed ? () => unawaited(_goNext()) : null,
              child: Ink(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  gradient: canProceed ? const LinearGradient(colors: [SsMasterTheme.neonBlue, SsMasterTheme.neonPurple]) : null,
                  color: canProceed ? null : SsMasterTheme.panelBorder,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.upload_file_outlined, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text('평면도 업로드로  →', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolGroup extends StatelessWidget {
  const _ToolGroup({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: SsMasterTheme.textMuted)),
        const SizedBox(height: 4),
        Row(mainAxisSize: MainAxisSize.min, children: children),
      ],
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.toolKey, required this.icon, required this.label, required this.selected, required this.onTap});
  final String toolKey;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: Key('ssDrawTool_$toolKey'),
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          width: 64,
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
    );
  }
}

/// 선택한 벽/문/창을 바로 고치는 작은 패널(§ 선택/이동/삭제/수정) — MASTER가 금지한 "공간 인식 결과" 패널과는
/// 다른, 선택된 요소 하나만 다루는 작은 플로팅 패널이다.
class _SelectionPanel extends StatelessWidget {
  const _SelectionPanel({required this.controller});
  final SsDrawEditorController controller;

  @override
  Widget build(BuildContext context) {
    final sel = controller.selection;
    final id = int.tryParse(sel.objectId);
    if (id == null) return const SizedBox.shrink();
    final isWall = sel.objectType == '벽';
    return Container(
      key: const Key('ssDrawSelectionPanel'),
      width: 220,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: SsMasterTheme.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: SsMasterTheme.panelBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${sel.objectType} 수정', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          if (isWall) ..._wallFields(id) else ..._openingFields(id),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const Key('ssDrawDeleteSelected'),
              onPressed: controller.deleteSelected,
              icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
              label: const Text('삭제', style: TextStyle(color: Colors.redAccent)),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _wallFields(int id) {
    final w = controller.scene.wall(id);
    if (w == null) return const [];
    return [
      Text('길이 ${SsLength.mm(w.lengthMm).format(SsLengthUnit.mm)}', style: const TextStyle(color: SsMasterTheme.textSecondary, fontSize: 12)),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              key: const Key('ssDrawWallExterior'),
              onPressed: () => controller.setWallType(id, SsDrawWallType.exterior),
              child: Text('외벽', style: TextStyle(color: w.type == SsDrawWallType.exterior ? SsMasterTheme.neonBlue : SsMasterTheme.textSecondary)),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: OutlinedButton(
              key: const Key('ssDrawWallInterior'),
              onPressed: () => controller.setWallType(id, SsDrawWallType.interior),
              child: Text('내벽', style: TextStyle(color: w.type == SsDrawWallType.interior ? SsMasterTheme.neonBlue : SsMasterTheme.textSecondary)),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          const Text('두께', style: TextStyle(color: SsMasterTheme.textSecondary, fontSize: 12)),
          IconButton(
            key: const Key('ssDrawWallThinner'),
            iconSize: 18,
            onPressed: () => controller.setWallThicknessMm(id, (w.thicknessMm - 20).clamp(60, 400)),
            icon: const Icon(Icons.remove, color: Colors.white),
          ),
          Text('${w.thicknessMm.round()}mm', style: const TextStyle(color: Colors.white, fontSize: 12)),
          IconButton(
            key: const Key('ssDrawWallThicker'),
            iconSize: 18,
            onPressed: () => controller.setWallThicknessMm(id, (w.thicknessMm + 20).clamp(60, 400)),
            icon: const Icon(Icons.add, color: Colors.white),
          ),
        ],
      ),
    ];
  }

  List<Widget> _openingFields(int id) {
    final o = controller.scene.opening(id);
    if (o == null) return const [];
    return [
      Text('폭 ${SsLength.mm(o.widthMm).format(SsLengthUnit.mm)}', style: const TextStyle(color: SsMasterTheme.textSecondary, fontSize: 12)),
      const SizedBox(height: 8),
      Row(
        children: [
          IconButton(
            key: const Key('ssDrawOpeningNarrower'),
            iconSize: 18,
            onPressed: () => controller.setOpeningWidthMm(id, (o.widthMm - 100).clamp(400, 3000)),
            icon: const Icon(Icons.remove, color: Colors.white),
          ),
          IconButton(
            key: const Key('ssDrawOpeningWider'),
            iconSize: 18,
            onPressed: () => controller.setOpeningWidthMm(id, (o.widthMm + 100).clamp(400, 3000)),
            icon: const Icon(Icons.add, color: Colors.white),
          ),
        ],
      ),
    ];
  }
}

class _SsDrawPainter extends CustomPainter {
  _SsDrawPainter({
    required this.scene,
    required this.draftStart,
    required this.draftEnd,
    required this.selectedType,
    required this.selectedId,
    required this.viewport,
    required this.gridMm,
    required this.gridVisible,
  });

  final SsDrawScene scene;
  final SsDrawPoint? draftStart;
  final SsDrawPoint? draftEnd;
  final String selectedType;
  final String selectedId;
  final WorkspaceViewportTransform viewport;
  final double gridMm;
  final bool gridVisible;

  Offset _toScreen(SsDrawPoint p) => viewport.apply(Offset(p.xMm * _pxPerMm, p.yMm * _pxPerMm));

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF081628));
    if (gridVisible) _paintGrid(canvas, size);
    for (final w in scene.walls) {
      _paintWall(canvas, w, selectedType == '벽' && selectedId == '${w.id}');
    }
    for (final o in scene.openings) {
      final w = scene.wall(o.wallId);
      if (w == null) continue;
      _paintOpening(canvas, w, o, selectedId == '${o.id}' && (selectedType == '문' || selectedType == '창'));
    }
    final start = draftStart, end = draftEnd;
    if (start != null && end != null) {
      final paint = Paint()
        ..color = Colors.white70
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawLine(_toScreen(start), _toScreen(end), paint);
    }
  }

  void _paintGrid(Canvas canvas, Size size) {
    final stepPx = gridMm * _pxPerMm * viewport.scale;
    if (stepPx < 4) return;
    final paint = Paint()
      ..color = const Color(0xFF17304F)
      ..strokeWidth = 1;
    final originX = viewport.offset.dx % stepPx;
    final originY = viewport.offset.dy % stepPx;
    for (var x = originX; x < size.width; x += stepPx) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = originY; y < size.height; y += stepPx) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _paintWall(Canvas canvas, SsDrawWall w, bool selected) {
    final paint = Paint()
      ..color = selected ? SsMasterTheme.neonBlue : Colors.white
      ..strokeWidth = (w.thicknessMm * _pxPerMm * viewport.scale).clamp(3.0, 60.0)
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(_toScreen(w.a), _toScreen(w.b), paint);
  }

  void _paintOpening(Canvas canvas, SsDrawWall w, SsDrawOpening o, bool selected) {
    final center = w.pointAt(o.alongMm);
    final dx = w.b.xMm - w.a.xMm, dy = w.b.yMm - w.a.yMm;
    final len = w.lengthMm;
    if (len <= 0) return;
    final ux = dx / len, uy = dy / len;
    final halfMm = o.widthMm / 2;
    final startDoc = SsDrawPoint(center.xMm - ux * halfMm, center.yMm - uy * halfMm);
    final endDoc = SsDrawPoint(center.xMm + ux * halfMm, center.yMm + uy * halfMm);
    final wallWidthPx = (w.thicknessMm * _pxPerMm * viewport.scale).clamp(3.0, 60.0);
    final gapPaint = Paint()
      ..color = const Color(0xFF081628)
      ..strokeWidth = wallWidthPx + 2
      ..strokeCap = StrokeCap.butt;
    canvas.drawLine(_toScreen(startDoc), _toScreen(endDoc), gapPaint);
    final color = o.kind == SsDrawOpeningKind.door ? SsMasterTheme.neonOrange : SsMasterTheme.neonCyan;
    final markPaint = Paint()
      ..color = selected ? SsMasterTheme.neonBlue : color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(_toScreen(startDoc), _toScreen(endDoc), markPaint);
    if (o.kind == SsDrawOpeningKind.door) {
      final swingX = -uy, swingY = ux;
      final leafEndDoc = SsDrawPoint(startDoc.xMm + swingX * o.widthMm, startDoc.yMm + swingY * o.widthMm);
      canvas.drawLine(_toScreen(startDoc), _toScreen(leafEndDoc), markPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SsDrawPainter oldDelegate) =>
      oldDelegate.scene != scene ||
      oldDelegate.draftStart != draftStart ||
      oldDelegate.draftEnd != draftEnd ||
      oldDelegate.selectedId != selectedId ||
      oldDelegate.selectedType != selectedType ||
      oldDelegate.viewport != viewport ||
      oldDelegate.gridMm != gridMm ||
      oldDelegate.gridVisible != gridVisible;
}
