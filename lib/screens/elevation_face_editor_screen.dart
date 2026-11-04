/// SS014 — MASTER UI 10(3D 아이소 작업) 중 "ISO에서 면(벽) 하나를 골라 정면도로 전환해 정밀하게
/// 디자인"하는 화면. [IsoEditorScreen](SS013)의 "정면도·측면도 편집으로 이동" 버튼이 이 화면을
/// projectId+wallId로 연다([SsStage.elevationFaceEditor]). 실제 구조/마감재/가구/조명/설비
/// 편집·Undo/Redo·저장은 전부 SS013의 [SsIsoEditorController]를 그대로 쓴다(새 편집 엔진을 만들지
/// 않는다) — 이 화면이 더하는 것은 "정면도로 투영해 보여주고, 그 위에서 문/창을 좌우로 옮기는" 2D
/// 캔버스([SsElevationEditorController]/[SsWallElevationLayout])뿐이다.
///
/// 저장은 [IsoEditorScreen]과 완전히 같은 칸([SsDataSlot.cadData]/[SsDataSlot.isoData])에 쓴다 —
/// 새 데이터 칸을 만들지 않아야 "같은 3D 모델에 정확히 반영"된다(§완료조건).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/ss_editing.dart' show SsSelection;
import '../core/ss_elevation_editor_controller.dart';
import '../core/ss_iso_editor_controller.dart';
import '../core/ss_project.dart';
import '../core/ss_project_store.dart';
import '../core/ss_router.dart' show SsStageHeader;
import '../core/ss_stage.dart';
import '../models/cad_floor_plan.dart';
import '../models/floor_plan_geometry.dart';
import '../models/space_scene_v2.dart';
import '../models/ss_cad_scene.dart';
import '../models/ss_iso_design_extras.dart';
import '../models/ss_spatial_model_json.dart';
import '../services/ss_project_store_provider.dart';
import '../theme/ss_master_theme.dart';
import 'cad_floor_plan_from_spatial_model_shim.dart' show cadFloorPlanFromSpatialModelCompat;

class ElevationFaceEditorScreen extends StatefulWidget {
  const ElevationFaceEditorScreen({super.key, this.projectId, this.wallId, this.projectStore});

  final String? projectId;

  /// [IsoEditorScreen]에서 "정면도·측면도 편집으로 이동"을 누를 때 선택했던 벽 id. 없거나 이
  /// 프로젝트에서 찾을 수 없으면 첫 번째 벽을 기본으로 보여준다(§완료조건 "ISO의 한 면을 선택해
  /// 정면도에서 편집").
  final String? wallId;

  final SsProjectStore? projectStore;

  @override
  State<ElevationFaceEditorScreen> createState() => _ElevationFaceEditorScreenState();
}

enum _ElevationLoad { loading, loaded, missingCad, missingWall, error }

class _ElevationFaceEditorScreenState extends State<ElevationFaceEditorScreen> {
  _ElevationLoad _state = _ElevationLoad.loading;
  SsAutosaveController? _autosave;
  SsIsoEditorController? _iso;
  SsElevationEditorController? _controller;
  Map<String, Object?>? _previousIsoPayload;

  static const CadFloorPlan _emptyPlan = CadFloorPlan(sourceWidthPx: 1000, sourceHeightPx: 800, walls: [], openings: [], rooms: [], warnings: []);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final pid = widget.projectId;
    if (pid == null) {
      _setUpWithoutProject();
      return;
    }
    try {
      final store = widget.projectStore ?? await SsProjectStoreProvider.instance.store();
      final project = await store.load(pid);
      if (project == null) {
        if (!mounted) return;
        setState(() => _state = _ElevationLoad.error);
        return;
      }
      final cadSlot = project.data[SsDataSlot.cadData];
      if (cadSlot == null) {
        if (!mounted) return;
        setState(() => _state = _ElevationLoad.missingCad);
        return;
      }
      final cadScene = _cadSceneFromPayload(cadSlot.payload);
      if (cadScene == null) {
        if (!mounted) return;
        setState(() => _state = _ElevationLoad.error);
        return;
      }
      final isoSlot = project.data[SsDataSlot.isoData];
      final extras = SsIsoDesignExtras.tryFromJson(isoSlot?.payload['design']);
      if (!mounted) return;
      final wallId = _resolveWallId(cadScene.plan, widget.wallId);
      if (wallId == null) {
        setState(() => _state = _ElevationLoad.missingWall);
        return;
      }
      _setControllers(cadScene, extras, wallId);
      setState(() {
        _autosave = SsAutosaveController(store: store, project: project);
        _previousIsoPayload = isoSlot?.payload;
        _state = _ElevationLoad.loaded;
      });
    } catch (e, st) {
      // 네트워크를 쓰지 않는 화면이므로 네트워크 오류로 오분류하지 않는다 — 실제 원인은 로그로
      // 남기고 사용자에게는 일반 안내만 보인다.
      debugPrint('ElevationFaceEditorScreen._load 실패 (${e.runtimeType}): $e\n$st');
      if (!mounted) return;
      setState(() => _state = _ElevationLoad.error);
    }
  }

  void _setUpWithoutProject() {
    const scene = SsCadScene(plan: _emptyPlan);
    final wallId = _resolveWallId(scene.plan, widget.wallId);
    if (wallId == null) {
      setState(() => _state = _ElevationLoad.missingWall);
      return;
    }
    _setControllers(scene, SsIsoDesignExtras.empty, wallId);
    setState(() => _state = _ElevationLoad.loaded);
  }

  String? _resolveWallId(CadFloorPlan plan, String? requested) {
    if (requested != null && plan.walls.any((w) => w.id == requested)) return requested;
    return plan.walls.isEmpty ? null : plan.walls.first.id;
  }

  /// [IsoEditorScreen]·[CadEditorScreen]과 같은 payload 두 형식을 모두 읽는다(같은
  /// [SsDataSlot.cadData] 칸을 공유하기 때문).
  SsCadScene? _cadSceneFromPayload(Map<String, Object?> payload) {
    if (payload['kind'] == 'ssCadScene') return SsCadScene.tryFromJson(payload['scene']);
    final model = ssSpatialModelFromJson(payload['model']);
    if (model == null) return null;
    return SsCadScene(plan: cadFloorPlanFromSpatialModelCompat(model));
  }

  void _setControllers(SsCadScene cad, SsIsoDesignExtras extras, String wallId) {
    _controller?.dispose();
    _iso?.history.removeListener(_onCommitted);
    _iso?.dispose();
    final iso = SsIsoEditorController(initialState: SsIsoEditorState(cad: cad, extras: extras));
    iso.selectObjectIdentity(SpaceObjectIdentityV2(objectId: 'wall:$wallId', sourceKind: SpaceElementKindV2.wall, sourceId: wallId, wallId: wallId));
    iso.history.addListener(_onCommitted);
    _iso = iso;
    _controller = SsElevationEditorController(iso: iso, initialWallId: wallId);
  }

  /// History에 실제로 커밋된 편집만 자동저장한다 — [IsoEditorScreen._onCommitted]와 똑같이 같은 두
  /// 칸([SsDataSlot.cadData]/[SsDataSlot.isoData])을 한 커밋에 함께 써서, 정면도에서 편집해도
  /// "같은 3D 모델"의 revision이 ISO 화면과 똑같이 올라간다.
  void _onCommitted() {
    final autosave = _autosave;
    final iso = _iso;
    if (autosave == null || iso == null) return;
    final withCad = autosave.project.withStageData(SsDataSlot.cadData, {'kind': 'ssCadScene', 'scene': iso.cad.toJson()}, label: '정면도 편집');
    final scene3d = iso.scene3d;
    final prior = _previousIsoPayload ?? const <String, Object?>{};
    final withIso = withCad.withStageData(SsDataSlot.isoData, {
      ...prior,
      'kind': 'ssIsoScene',
      'camera': prior['camera'],
      'warnings': scene3d.warnings,
      'furnitureCount': iso.cad.furniture.length,
      'wallCount': scene3d.wallCount,
      'floorCount': scene3d.floorCount,
      'design': iso.extras.toJson(),
    }, label: '정면도 편집');
    autosave.update(withIso);
    setState(() {});
  }

  Future<void> _backToIso() async {
    await _autosave?.saveNow();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _iso?.history.removeListener(_onCommitted);
    _controller?.dispose();
    _iso?.dispose();
    _autosave?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _ElevationLoad.loading:
        return const Center(child: CircularProgressIndicator(key: Key('ssElevationLoading')));
      case _ElevationLoad.error:
        return const Center(
          child: Text('프로젝트를 불러오지 못했습니다. ISO 디자인에서 다시 열어주세요.', key: Key('ssElevationLoadError'), style: TextStyle(color: SsMasterTheme.textSecondary)),
        );
      case _ElevationLoad.missingCad:
        return const Center(child: Text('먼저 3D ISO 디자인을 완료해주세요.', key: Key('ssElevationMissingCad'), style: TextStyle(color: SsMasterTheme.textSecondary)));
      case _ElevationLoad.missingWall:
        return const Center(
          child: Text('아직 벽이 없습니다. ISO 디자인에서 벽을 만든 뒤 다시 시도하세요.', key: Key('ssElevationMissingWall'), style: TextStyle(color: SsMasterTheme.textSecondary)),
        );
      case _ElevationLoad.loaded:
        break;
    }
    final controller = _controller!;
    final iso = _iso!;
    return Padding(
      key: const Key('ssElevationScreen'),
      padding: const EdgeInsets.all(16),
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: SsStageHeader(stage: SsStage.elevationFaceEditor)),
                ElevatedButton.icon(
                  key: const Key('ssElevationBackToIso'),
                  onPressed: () => unawaited(_backToIso()),
                  icon: const Icon(Icons.view_in_ar_outlined, size: 16),
                  label: const Text('ISO로 돌아가기'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildViewSwitch(controller),
            const SizedBox(height: 10),
            _buildRibbon(iso),
            const SizedBox(height: 10),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [Expanded(flex: 3, child: _buildCanvasPanel(controller, iso)), const SizedBox(width: 14), SizedBox(width: 300, child: _buildRightPanel(iso))],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// View Cube와 같은 역할 — 정면도/측면도/평면도 중 지금 보는 것을 바꾼다(§완료조건 "View Cube
  /// 또는 동등한 직관적 View 전환"). 측면도를 고르면, 지금 정면 벽과 거의 수직인 다른 벽들 중
  /// 하나를 더 골라야 한다(존재하지 않는 "측면"을 지어내지 않는다).
  Widget _buildViewSwitch(SsElevationEditorController controller) {
    return Container(
      decoration: BoxDecoration(color: SsMasterTheme.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: SsMasterTheme.panelBorder)),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (final v in SsElevationView.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    key: Key('ssElevationView_${v.name}'),
                    label: Text(v.label, style: TextStyle(fontSize: 12, color: controller.view == v ? Colors.white : SsMasterTheme.textSecondary)),
                    selected: controller.view == v,
                    selectedColor: SsMasterTheme.neonBlue,
                    backgroundColor: SsMasterTheme.background,
                    onSelected: (_) => controller.setView(v),
                  ),
                ),
            ],
          ),
          if (controller.view == SsElevationView.side) ...[
            const SizedBox(height: 6),
            if (controller.sideWallCandidates.isEmpty)
              const Text('이 벽과 수직인 다른 벽이 없습니다.', key: Key('ssElevationNoSideWalls'), style: TextStyle(color: SsMasterTheme.textSecondary, fontSize: 12))
            else
              Wrap(
                spacing: 6,
                children: [
                  for (final w in controller.sideWallCandidates)
                    ActionChip(key: Key('ssElevationSideWall_${w.id}'), label: Text(w.id), onPressed: () => controller.focusWall(w.id)),
                ],
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildRibbon(SsIsoEditorController iso) {
    return Container(
      key: const Key('ssElevationRibbon'),
      height: 64,
      decoration: BoxDecoration(color: SsMasterTheme.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: SsMasterTheme.panelBorder)),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _ribbonButton(key: const Key('ssElevationAddWall'), icon: Icons.view_agenda_outlined, label: '벽체 생성', onTap: iso.addDefaultWall),
            _ribbonButton(key: const Key('ssElevationDeleteWall'), icon: Icons.delete_sweep_outlined, label: '벽체 철거', enabled: iso.selection.objectType == '벽', onTap: iso.deleteSelectedWall),
            _ribbonButton(
              key: const Key('ssElevationAddDoor'),
              icon: Icons.sensor_door_outlined,
              label: '문 추가',
              enabled: iso.selection.objectType == '벽',
              onTap: () => iso.addOpeningOnSelectedWall(OpeningType.door),
            ),
            _ribbonButton(
              key: const Key('ssElevationAddWindow'),
              icon: Icons.window_outlined,
              label: '창 추가',
              enabled: iso.selection.objectType == '벽',
              onTap: () => iso.addOpeningOnSelectedWall(OpeningType.window),
            ),
            _ribbonButton(
              key: const Key('ssElevationDeleteSelected'),
              icon: Icons.delete_outline,
              label: '선택 삭제',
              enabled: iso.selection.objectType == '문' || iso.selection.objectType == '창',
              onTap: iso.deleteSelectedOpening,
            ),
            _ribbonButton(key: const Key('ssElevationAddFurniture'), icon: Icons.chair_outlined, label: '가구 추가', onTap: () => iso.addFurniture(iso.pendingFurnitureKind)),
            for (final kind in SsIsoLightKind.values) _ribbonButton(key: Key('ssElevationAddLight_${kind.name}'), icon: Icons.lightbulb_outline, label: kind.label, onTap: () => iso.addLight(kind)),
            for (final kind in SsIsoEquipmentKind.values) _ribbonButton(key: Key('ssElevationAddEquipment_${kind.name}'), icon: Icons.plumbing_outlined, label: kind.label, onTap: () => iso.addEquipment(kind)),
          ],
        ),
      ),
    );
  }

  Widget _ribbonButton({required Key key, required IconData icon, required String label, VoidCallback? onTap, bool enabled = true}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(8),
          onTap: enabled ? onTap : null,
          child: Container(
            width: 64,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: enabled ? SsMasterTheme.textSecondary : SsMasterTheme.textMuted),
                const SizedBox(height: 2),
                Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 9, color: enabled ? SsMasterTheme.textSecondary : SsMasterTheme.textMuted)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 정면도/측면도 캔버스([SsWallElevationLayout]) 또는 평면도(간단한 2D 상단 뷰). Galaxy Tab
  /// 터치/스타일러스 모두 같은 제스처(탭=선택, 드래그=선택한 문/창 이동)를 쓴다.
  Widget _buildCanvasPanel(SsElevationEditorController controller, SsIsoEditorController iso) {
    return Container(
      key: const Key('ssElevationCanvasBox'),
      decoration: BoxDecoration(color: const Color(0xFF081628), borderRadius: BorderRadius.circular(16), border: Border.all(color: SsMasterTheme.panelBorder)),
      clipBehavior: Clip.antiAlias,
      child: controller.view == SsElevationView.plan ? _buildPlanView(controller, iso) : _buildElevationView(controller, iso),
    );
  }

  Widget _buildPlanView(SsElevationEditorController controller, SsIsoEditorController iso) {
    if (iso.plan.walls.isEmpty) {
      return const Center(child: Text('벽이 없습니다.', key: Key('ssElevationPlanEmpty'), style: TextStyle(color: SsMasterTheme.textSecondary)));
    }
    return LayoutBuilder(
      key: const Key('ssElevationPlanView'),
      builder: (context, constraints) => CustomPaint(
        size: Size(constraints.maxWidth, constraints.maxHeight),
        painter: _PlanMiniPainter(plan: iso.plan, highlightWallId: controller.focusedWallId),
      ),
    );
  }

  Widget _buildElevationView(SsElevationEditorController controller, SsIsoEditorController iso) {
    final layout = controller.layout;
    if (layout == null) {
      return const Center(
        child: Text('이 벽의 치수를 알 수 없습니다(축척 미확정).', key: Key('ssElevationNoLayout'), style: TextStyle(color: SsMasterTheme.textSecondary)),
      );
    }
    return LayoutBuilder(
      key: const Key('ssElevationFrontView'),
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          onTapUp: (d) {
            final tr = _ElevationPainter.transformFor(size, layout);
            if (tr.scale <= 0) return;
            controller.selectOpeningAtAlongMm((d.localPosition.dx - tr.left) / tr.scale);
          },
          onPanUpdate: (d) {
            final tr = _ElevationPainter.transformFor(size, layout);
            if (tr.scale <= 0) return;
            iso.moveSelectedOpeningAlongWallByMm(d.delta.dx / tr.scale);
          },
          child: CustomPaint(size: size, painter: _ElevationPainter(layout: layout, selectedOpeningId: _selectedOpeningId(iso), wallColor: _wallColorFor(iso, layout.wallId))),
        );
      },
    );
  }

  String? _selectedOpeningId(SsIsoEditorController iso) => (iso.selection.objectType == '문' || iso.selection.objectType == '창') ? iso.selection.objectId : null;

  Color _wallColorFor(SsIsoEditorController iso, String wallId) {
    for (final w in iso.plan.walls) {
      if (w.id == wallId) return w.materialOverride ?? const Color(0xFFE7E4DC);
    }
    return const Color(0xFFE7E4DC);
  }

  Widget _buildRightPanel(SsIsoEditorController iso) {
    final sel = iso.selection;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _panel(title: '선택 요소 치수', child: _buildSelectionProperties(iso, sel)),
          if (sel.objectType == '벽') ...[const SizedBox(height: 10), _panel(title: '마감재', child: _buildMaterialSwatches(iso))],
        ],
      ),
    );
  }

  Widget _panel({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: SsMasterTheme.panel, borderRadius: BorderRadius.circular(14), border: Border.all(color: SsMasterTheme.panelBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [Text(title, style: const TextStyle(color: SsMasterTheme.textPrimary, fontWeight: FontWeight.w800, fontSize: 13)), const SizedBox(height: 8), child],
      ),
    );
  }

  Widget _row(String label, String value, {Key? valueKey}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: SsMasterTheme.textSecondary, fontSize: 12)),
          Flexible(child: Text(value, key: valueKey, textAlign: TextAlign.end, style: const TextStyle(color: SsMasterTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  Widget _editableMmRow(String label, double? valueMm, Key fieldKey, ValueChanged<double> onSubmit) {
    final textController = TextEditingController(text: valueMm == null ? '' : valueMm.round().toString());
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: SsMasterTheme.textSecondary, fontSize: 12))),
          SizedBox(
            width: 90,
            child: TextField(
              key: fieldKey,
              controller: textController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: SsMasterTheme.textPrimary, fontSize: 12),
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

  Widget _buildSelectionProperties(SsIsoEditorController iso, SsSelection sel) {
    if (sel.isEmpty) {
      return const Text('정면도에서 벽이나 문/창을 선택하세요.', key: Key('ssElevationNoSelection'), style: TextStyle(color: SsMasterTheme.textSecondary, fontSize: 12));
    }
    final props = sel.properties;
    final rows = <Widget>[_row('종류', sel.objectType, valueKey: const Key('ssElevationSelectedType'))];
    if (sel.objectType == '벽') {
      rows.add(_editableMmRow('길이', (props['lengthMm'] as num?)?.toDouble(), const Key('ssElevationWallLength'), iso.setSelectedWallLengthMm));
      rows.add(_editableMmRow('두께', (props['thicknessMm'] as num?)?.toDouble(), const Key('ssElevationWallThickness'), iso.setSelectedWallThicknessMm));
      rows.add(_editableMmRow('높이', (props['heightMm'] as num?)?.toDouble(), const Key('ssElevationWallHeight'), iso.setSelectedWallHeightMm));
    } else if (sel.objectType == '문' || sel.objectType == '창') {
      final widthMm = props['widthMm'] as num?;
      rows.add(_row('폭', widthMm == null ? '알 수 없음' : '${widthMm.round()}mm', valueKey: const Key('ssElevationOpeningWidth')));
      rows.add(const SizedBox(height: 6));
      rows.add(
        Row(
          children: [
            IconButton(key: const Key('ssElevationOpeningMoveLeft'), onPressed: () => iso.moveSelectedOpeningAlongWallByMm(-50), icon: const Icon(Icons.arrow_left, size: 18), color: SsMasterTheme.textSecondary),
            IconButton(key: const Key('ssElevationOpeningMoveRight'), onPressed: () => iso.moveSelectedOpeningAlongWallByMm(50), icon: const Icon(Icons.arrow_right, size: 18), color: SsMasterTheme.textSecondary),
            IconButton(key: const Key('ssElevationOpeningDelete'), onPressed: iso.deleteSelectedOpening, icon: const Icon(Icons.delete_outline, size: 18), color: SsMasterTheme.textSecondary),
          ],
        ),
      );
    } else if (sel.objectType == '가구') {
      final widthMm = props['widthMm'] as num?;
      final depthMm = props['depthMm'] as num?;
      rows.add(_row('폭', widthMm == null ? '알 수 없음' : '${widthMm.round()}mm', valueKey: const Key('ssElevationFurnitureWidth')));
      rows.add(_row('깊이', depthMm == null ? '알 수 없음' : '${depthMm.round()}mm', valueKey: const Key('ssElevationFurnitureDepth')));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }

  Widget _buildMaterialSwatches(SsIsoEditorController iso) {
    void apply(SsIsoMaterialPreset preset) => iso.setSelectedWallMaterial(preset.label, Color(preset.colorValue));
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final preset in kSsIsoMaterialPresets)
          InkWell(
            key: Key('ssElevationMaterial_${preset.label}'),
            onTap: () => apply(preset),
            borderRadius: BorderRadius.circular(8),
            child: Column(
              children: [
                Container(width: 40, height: 32, decoration: BoxDecoration(color: Color(preset.colorValue), borderRadius: BorderRadius.circular(6), border: Border.all(color: SsMasterTheme.panelBorder))),
                const SizedBox(height: 3),
                Text(preset.label, style: const TextStyle(color: SsMasterTheme.textSecondary, fontSize: 9)),
              ],
            ),
          ),
      ],
    );
  }
}

/// 정면도 캔버스의 along-mm ↔ 화면 px 변환 — 탭/드래그 처리와 실제 그리기가 같은 계산을 쓰게
/// [transformFor]를 static으로 공유한다(두 곳에서 서로 다른 스케일을 쓰면 탭한 위치와 실제로
/// 그려진 문/창 위치가 어긋난다).
class _ElevationPainter extends CustomPainter {
  _ElevationPainter({required this.layout, required this.selectedOpeningId, required this.wallColor});

  final SsWallElevationLayout layout;
  final String? selectedOpeningId;
  final Color wallColor;

  static const double margin = 36;

  static ({double scale, double left, double top}) transformFor(Size size, SsWallElevationLayout layout) {
    final availableW = size.width - margin * 2;
    final availableH = size.height - margin * 2;
    if (availableW <= 0 || availableH <= 0 || layout.lengthMm <= 0 || layout.heightMm <= 0) {
      return (scale: 0, left: margin, top: margin);
    }
    final scale = math.min(availableW / layout.lengthMm, availableH / layout.heightMm);
    final wallWpx = layout.lengthMm * scale;
    final wallHpx = layout.heightMm * scale;
    return (scale: scale, left: margin + (availableW - wallWpx) / 2, top: margin + (availableH - wallHpx) / 2);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final tr = transformFor(size, layout);
    if (tr.scale <= 0) return;
    final wallWpx = layout.lengthMm * tr.scale;
    final wallHpx = layout.heightMm * tr.scale;
    final wallRect = Rect.fromLTWH(tr.left, tr.top, wallWpx, wallHpx);
    canvas.drawRect(wallRect, Paint()..color = wallColor);
    canvas.drawRect(
      wallRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF3A4A5E),
    );

    for (final o in layout.openings) {
      final r = Rect.fromLTRB(
        tr.left + o.startMm * tr.scale,
        tr.top + (layout.heightMm - o.topMm) * tr.scale,
        tr.left + o.endMm * tr.scale,
        tr.top + (layout.heightMm - o.bottomMm) * tr.scale,
      );
      final isSelected = o.openingId == selectedOpeningId;
      canvas.drawRect(r, Paint()..color = o.type == OpeningType.door ? const Color(0xFF8A5A3A) : const Color(0xFFAEC6D6));
      canvas.drawRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSelected ? 3 : 1
          ..color = isSelected ? const Color(0xFF4FC3F7) : const Color(0xFF1F2A36),
      );
    }

    _text(canvas, '${layout.lengthMm.round()}mm', Offset(tr.left + wallWpx / 2 - 24, tr.top + wallHpx + 8));
    _text(canvas, '${layout.heightMm.round()}mm', Offset(math.max(0, tr.left - 34), tr.top + wallHpx / 2 - 8));
  }

  void _text(Canvas canvas, String s, Offset o) {
    final tp = TextPainter(text: TextSpan(text: s, style: const TextStyle(color: Color(0xFF9AB0C4), fontSize: 11)), textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, o);
  }

  @override
  bool shouldRepaint(covariant _ElevationPainter oldDelegate) => true;
}

/// 평면도 전환(§완료조건 "필요 시 측면도/평면도 전환") — 전체 CAD 편집기를 다시 만들지 않고, 지금
/// 정면으로 보는 벽이 평면도에서 어디인지만 강조해 보여주는 가벼운 미리보기.
class _PlanMiniPainter extends CustomPainter {
  _PlanMiniPainter({required this.plan, required this.highlightWallId});

  final CadFloorPlan plan;
  final String? highlightWallId;

  @override
  void paint(Canvas canvas, Size size) {
    for (final w in plan.walls) {
      final isHighlighted = w.id == highlightWallId;
      canvas.drawLine(
        Offset(w.start.x * size.width, w.start.y * size.height),
        Offset(w.end.x * size.width, w.end.y * size.height),
        Paint()
          ..color = isHighlighted ? const Color(0xFF4FC3F7) : const Color(0xFF5B6B7C)
          ..strokeWidth = isHighlighted ? 5 : 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PlanMiniPainter oldDelegate) => oldDelegate.plan != plan || oldDelegate.highlightWallId != highlightWallId;
}
