/// SS013 — MASTER UI 10(3D 아이소 작업) 전문 디자인 에디터. SS012(IsoConversionScreen)가
/// [SsDataSlot.isoData]/[SsDataSlot.cadData]에 남긴 결과를 실제로 Orbit/Pan/Zoom하며 벽/문/창/가구/
/// 마감재/조명/설비를 편집하는 작업환경을 연다. 3D 렌더링·피킹·카메라 조작은 전부 이미 검증된
/// [Space3DViewGpuV2]를 그대로 쓴다(새 3D 엔진을 만들지 않는다).
library;

import 'dart:async';

import 'package:flutter/material.dart';

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
import '../widgets/workspace/space_3d_view_gpu_v2.dart';
import 'cad_floor_plan_from_spatial_model_shim.dart' show cadFloorPlanFromSpatialModelCompat;

class IsoEditorScreen extends StatefulWidget {
  const IsoEditorScreen({super.key, this.projectId, this.projectStore});

  final String? projectId;
  final SsProjectStore? projectStore;

  @override
  State<IsoEditorScreen> createState() => _IsoEditorScreenState();
}

enum _IsoEditorLoad { loading, loaded, missingCad, error }

class _IsoEditorScreenState extends State<IsoEditorScreen> {
  _IsoEditorLoad _state = _IsoEditorLoad.loading;
  SsAutosaveController? _autosave;
  SsIsoEditorController? _controller;
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
      _setController(SsIsoEditorController(initialState: const SsIsoEditorState(cad: SsCadScene(plan: _emptyPlan))));
      setState(() => _state = _IsoEditorLoad.loaded);
      return;
    }
    try {
      final store = widget.projectStore ?? await SsProjectStoreProvider.instance.store();
      final project = await store.load(pid);
      if (project == null) {
        if (!mounted) return;
        setState(() => _state = _IsoEditorLoad.error);
        return;
      }
      final cadSlot = project.data[SsDataSlot.cadData];
      if (cadSlot == null) {
        if (!mounted) return;
        setState(() => _state = _IsoEditorLoad.missingCad);
        return;
      }
      final cadScene = _cadSceneFromPayload(cadSlot.payload);
      if (cadScene == null) {
        if (!mounted) return;
        setState(() => _state = _IsoEditorLoad.error);
        return;
      }
      final isoSlot = project.data[SsDataSlot.isoData];
      final extras = SsIsoDesignExtras.tryFromJson(isoSlot?.payload['design']);
      if (!mounted) return;
      _setController(SsIsoEditorController(initialState: SsIsoEditorState(cad: cadScene, extras: extras)));
      setState(() {
        _autosave = SsAutosaveController(store: store, project: project);
        _previousIsoPayload = isoSlot?.payload;
        _state = _IsoEditorLoad.loaded;
      });
    } catch (e, st) {
      // 네트워크를 쓰지 않는 화면이므로 네트워크 오류로 오분류하지 않는다 — 실제 원인은 로그로 남기고
      // 사용자에게는 일반 안내만 보인다.
      debugPrint('IsoEditorScreen._load 실패 (${e.runtimeType}): $e\n$st');
      if (!mounted) return;
      setState(() => _state = _IsoEditorLoad.error);
    }
  }

  /// SS011([CadEditorScreen])과 같은 payload 두 형식(레거시 spatial model / 신규 ssCadScene)을
  /// 모두 읽는다 — 같은 [SsDataSlot.cadData] 칸을 공유하기 때문.
  SsCadScene? _cadSceneFromPayload(Map<String, Object?> payload) {
    if (payload['kind'] == 'ssCadScene') return SsCadScene.tryFromJson(payload['scene']);
    final model = ssSpatialModelFromJson(payload['model']);
    if (model == null) return null;
    return SsCadScene(plan: cadFloorPlanFromSpatialModelCompat(model));
  }

  void _setController(SsIsoEditorController c) {
    _controller?.history.removeListener(_onCommitted);
    _controller?.dispose();
    _controller = c..history.addListener(_onCommitted);
  }

  /// History에 실제로 커밋된 편집만 자동저장한다 — [SsDataSlot.cadData](구조/가구)와
  /// [SsDataSlot.isoData](조명/설비/마감재 라벨 등 SS013 전용 데이터)를 같은 커밋에 함께 써서, 두 칸
  /// revision이 항상 같이 올라가게 한다(§완료조건 "변경사항은 3D 모델에 구조화된 데이터로 저장" —
  /// 기존 [SsProject.staleNotices]가 엉뚱하게 "업데이트 필요"를 띄우지 않는다).
  void _onCommitted() {
    final autosave = _autosave;
    final controller = _controller;
    if (autosave == null || controller == null) return;
    final withCad = autosave.project.withStageData(SsDataSlot.cadData, {'kind': 'ssCadScene', 'scene': controller.cad.toJson()}, label: '3D 편집');
    final scene3d = controller.scene3d;
    final prior = _previousIsoPayload ?? const <String, Object?>{};
    final withIso = withCad.withStageData(SsDataSlot.isoData, {
      ...prior,
      'kind': 'ssIsoScene',
      'camera': prior['camera'],
      'warnings': scene3d.warnings,
      'furnitureCount': controller.cad.furniture.length,
      'wallCount': scene3d.wallCount,
      'floorCount': scene3d.floorCount,
      'design': controller.extras.toJson(),
    }, label: '3D 편집');
    autosave.update(withIso);
    setState(() {});
  }

  Future<void> _saveNow() async {
    await _autosave?.saveNow();
  }

  Future<void> _goToElevationEditor() async {
    final wallId = _controller?.selectedWallIdForElevationHandoff;
    if (wallId == null) return;
    await Navigator.of(context).pushNamed(SsStage.elevationFaceEditor.routeName, arguments: {'projectId': widget.projectId, 'wallId': wallId});
    // SS014 완료조건 "데이터 충돌 시 최신 상태를 명확히 표시" — 정면도 화면은 새 데이터 칸을 만들지
    // 않고 이 화면과 똑같은 [SsDataSlot.cadData]/[SsDataSlot.isoData] 칸에 직접 저장한다(§완료조건
    // "같은 3D 모델에 정확히 반영"). 그 화면이 저장소에 쓴 뒤 돌아오면, 지금 메모리에 남아있는(정면도
    // 편집 전) 오래된 복사본을 계속 쓰지 않고 저장소에서 다시 읽어 최신 상태로 맞춘다. 사용자가 보던
    // 벽은 그대로 다시 선택해(§완료조건 "선택 상태 유지") Space3DViewGpuV2의 카메라도 그대로 둔다
    // (같은 State 트리 안에서 scene만 새로 넘기므로 Orbit 카메라는 바뀌지 않는다).
    if (!mounted) return;
    await _reloadAfterElevationReturn(wallId);
  }

  Future<void> _reloadAfterElevationReturn(String wallId) async {
    final pid = widget.projectId;
    if (pid == null) return;
    try {
      final store = widget.projectStore ?? await SsProjectStoreProvider.instance.store();
      final project = await store.load(pid);
      if (project == null || !mounted) return;
      final cadSlot = project.data[SsDataSlot.cadData];
      if (cadSlot == null) return;
      final cadScene = _cadSceneFromPayload(cadSlot.payload);
      if (cadScene == null) return;
      final isoSlot = project.data[SsDataSlot.isoData];
      final extras = SsIsoDesignExtras.tryFromJson(isoSlot?.payload['design']);
      _setController(SsIsoEditorController(initialState: SsIsoEditorState(cad: cadScene, extras: extras)));
      _controller!.selectObjectIdentity(SpaceObjectIdentityV2(objectId: 'wall:$wallId', sourceKind: SpaceElementKindV2.wall, sourceId: wallId, wallId: wallId));
      if (!mounted) return;
      _autosave?.dispose();
      setState(() {
        _autosave = SsAutosaveController(store: store, project: project);
        _previousIsoPayload = isoSlot?.payload;
      });
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('정면도에서 편집한 내용이 반영되었습니다', key: Key('ssIsoElevationSyncNotice')), duration: Duration(seconds: 2)),
      );
    } catch (e, st) {
      debugPrint('IsoEditorScreen._reloadAfterElevationReturn 실패 (${e.runtimeType}): $e\n$st');
    }
  }

  @override
  void dispose() {
    _controller?.history.removeListener(_onCommitted);
    _controller?.dispose();
    _autosave?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_state == _IsoEditorLoad.error) {
      return const Center(child: Text('프로젝트를 불러오지 못했습니다. 프로젝트 관리에서 다시 열어주세요.', key: Key('ssIsoEditorLoadError'), style: TextStyle(color: SsMasterTheme.textSecondary)));
    }
    if (_state == _IsoEditorLoad.loading) {
      return const Center(child: CircularProgressIndicator(key: Key('ssIsoEditorLoading')));
    }
    if (_state == _IsoEditorLoad.missingCad) {
      return const Center(child: Text('먼저 CAD 편집을 완료해주세요.', key: Key('ssIsoEditorMissingCad'), style: TextStyle(color: SsMasterTheme.textSecondary)));
    }
    final controller = _controller!;
    return Padding(
      key: const Key('ssIsoEditorScreen'),
      padding: const EdgeInsets.all(16),
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: SsStageHeader(stage: SsStage.isoEditor)), _buildUndoRedo(controller)]),
            const SizedBox(height: 10),
            _buildRibbon(controller),
            const SizedBox(height: 10),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [Expanded(flex: 3, child: _buildCanvasPanel(controller)), const SizedBox(width: 14), SizedBox(width: 300, child: _buildRightPanel(controller))],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUndoRedo(SsIsoEditorController controller) {
    return Row(
      children: [
        IconButton(key: const Key('ssIsoUndo'), tooltip: '실행취소', onPressed: controller.canUndo ? controller.undo : null, icon: const Icon(Icons.undo), color: SsMasterTheme.textSecondary),
        IconButton(key: const Key('ssIsoRedo'), tooltip: '다시실행', onPressed: controller.canRedo ? controller.redo : null, icon: const Icon(Icons.redo), color: SsMasterTheme.textSecondary),
        const SizedBox(width: 8),
        ElevatedButton.icon(key: const Key('ssIsoSaveButton'), onPressed: () => unawaited(_saveNow()), icon: const Icon(Icons.save_outlined, size: 16), label: const Text('저장')),
      ],
    );
  }

  /// CAD 스타일 상단 Ribbon — MASTER UI 10 그룹(구조/개구부/가구/조명/설비)을 그대로 둔다. 전체
  /// 가로가 넓어도(태블릿) 내용이 넘치면 가로 스크롤(과도한 치수/도구 나열로 ISO 화면을 가리지 않음).
  Widget _buildRibbon(SsIsoEditorController controller) {
    return Container(
      key: const Key('ssIsoRibbon'),
      height: 76,
      decoration: BoxDecoration(color: SsMasterTheme.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: SsMasterTheme.panelBorder)),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _ribbonGroup('선택', [
              _ribbonButton(key: const Key('ssIsoToolSelect'), icon: Icons.near_me_outlined, label: '선택', selected: controller.tool == SsIsoTool.select, onTap: () => controller.setTool(SsIsoTool.select)),
            ]),
            _ribbonGroup('구조', [
              _ribbonButton(key: const Key('ssIsoToolAddWall'), icon: Icons.view_agenda_outlined, label: '벽체 생성', onTap: controller.addDefaultWall),
              _ribbonButton(key: const Key('ssIsoToolDeleteWall'), icon: Icons.delete_sweep_outlined, label: '벽체 철거', enabled: controller.selection.objectType == '벽', onTap: controller.deleteSelectedWall),
            ]),
            _ribbonGroup('개구부', [
              _ribbonButton(key: const Key('ssIsoToolAddDoor'), icon: Icons.sensor_door_outlined, label: '문', enabled: controller.selection.objectType == '벽', onTap: () => controller.addOpeningOnSelectedWall(OpeningType.door)),
              _ribbonButton(key: const Key('ssIsoToolAddWindow'), icon: Icons.window_outlined, label: '창', enabled: controller.selection.objectType == '벽', onTap: () => controller.addOpeningOnSelectedWall(OpeningType.window)),
            ]),
            _ribbonGroup('가구', [
              _ribbonButton(key: const Key('ssIsoToolAddFurniture'), icon: Icons.chair_outlined, label: '가구 추가', onTap: () => controller.addFurniture(controller.pendingFurnitureKind)),
              _ribbonButton(key: const Key('ssIsoToolDeleteSelected'), icon: Icons.delete_outline, label: '삭제', enabled: !controller.selection.isEmpty, onTap: controller.deleteSelected),
            ]),
            _ribbonGroup('조명', [
              for (final kind in SsIsoLightKind.values) _ribbonButton(key: Key('ssIsoAddLight_${kind.name}'), icon: Icons.lightbulb_outline, label: kind.label, onTap: () => controller.addLight(kind)),
            ]),
            _ribbonGroup('설비', [
              for (final kind in SsIsoEquipmentKind.values) _ribbonButton(key: Key('ssIsoAddEquipment_${kind.name}'), icon: Icons.plumbing_outlined, label: kind.label, onTap: () => controller.addEquipment(kind)),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _ribbonGroup(String title, List<Widget> buttons) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: const TextStyle(color: SsMasterTheme.textMuted, fontSize: 10, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Row(mainAxisSize: MainAxisSize.min, children: buttons),
          const SizedBox(height: 2),
        ],
      ),
    );
  }

  Widget _ribbonButton({required Key key, required IconData icon, required String label, VoidCallback? onTap, bool selected = false, bool enabled = true}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(8),
          onTap: enabled ? onTap : null,
          child: Container(
            width: 56,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(gradient: selected ? SsMasterTheme.selectedItem : null, borderRadius: BorderRadius.circular(8)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: enabled ? (selected ? Colors.white : SsMasterTheme.textSecondary) : SsMasterTheme.textMuted),
                const SizedBox(height: 2),
                Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 9, color: enabled ? (selected ? Colors.white : SsMasterTheme.textSecondary) : SsMasterTheme.textMuted)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 메인 3D 캔버스 — Orbit/Pan/Zoom/탭 선택은 전부 기존 [Space3DViewGpuV2]가 한다. geometry가
  /// 하나도 없으면(아직 벽/공간이 없는 CAD) 그 GPU 위젯을 "빈 화면"으로 띄우는 대신, 존재하지 않는
  /// 3D를 지어내지 않고 정직하게 안내만 보인다.
  Widget _buildCanvasPanel(SsIsoEditorController controller) {
    final scene = controller.scene3d;
    return Container(
      key: const Key('ssIsoCanvasBox'),
      decoration: BoxDecoration(color: const Color(0xFF081628), borderRadius: BorderRadius.circular(16), border: Border.all(color: SsMasterTheme.panelBorder)),
      clipBehavior: Clip.antiAlias,
      child: scene.isEmpty
          ? const Center(
              child: Text(
                '3D 모델이 비어 있습니다. 리본의 "벽체 생성"으로 시작하세요.',
                key: Key('ssIsoEditorEmptyScene'),
                textAlign: TextAlign.center,
                style: TextStyle(color: SsMasterTheme.textSecondary),
              ),
            )
          : Space3DViewGpuV2(key: const Key('ssIsoEditorSpace3D'), scene: scene, selectedObjectId: controller.selectedObjectId3d, onObjectSelected: controller.selectObjectIdentity),
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

  /// 선택 객체에 필요한 속성만 보인다(§완료조건 "compact panel") — 종류마다 다른 필드만 그린다.
  Widget _buildRightPanel(SsIsoEditorController controller) {
    final sel = controller.selection;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _panel(title: '선택 속성', child: _buildSelectionProperties(controller, sel)),
          if (sel.objectType == '벽') ...[
            const SizedBox(height: 10),
            ElevatedButton.icon(
              key: const Key('ssIsoGoToElevationButton'),
              onPressed: _goToElevationEditor,
              icon: const Icon(Icons.door_front_door_outlined, size: 16),
              label: const Text('정면도·측면도 편집으로 이동'),
            ),
          ],
          if (sel.objectType == '벽' || sel.objectType == '바닥' || sel.objectType == '천장') ...[const SizedBox(height: 10), _panel(title: '마감재', child: _buildMaterialSwatches(controller, sel))],
        ],
      ),
    );
  }

  Widget _buildSelectionProperties(SsIsoEditorController controller, dynamic sel) {
    if (sel.isEmpty as bool) {
      return const Text('3D에서 벽/바닥/천장/가구를 선택하세요.', key: Key('ssIsoNoSelection'), style: TextStyle(color: SsMasterTheme.textSecondary, fontSize: 12));
    }
    final props = sel.properties as Map<String, Object?>;
    final rows = <Widget>[_row('종류', sel.objectType as String, valueKey: const Key('ssIsoSelectedType'))];
    if (sel.objectType == '벽') {
      final lengthMm = props['lengthMm'] as num?;
      final thicknessMm = props['thicknessMm'] as num?;
      final heightMm = props['heightMm'] as num?;
      rows.add(_row('길이', lengthMm == null ? '알 수 없음' : '${lengthMm.round()}mm', valueKey: const Key('ssIsoWallLength')));
      rows.add(_row('두께', thicknessMm == null ? '알 수 없음' : '${thicknessMm.round()}mm', valueKey: const Key('ssIsoWallThickness')));
      rows.add(_row('높이', heightMm == null ? '미지정' : '${heightMm.round()}mm', valueKey: const Key('ssIsoWallHeight')));
    } else if (sel.objectType == '바닥' || sel.objectType == '천장') {
      final areaM2 = props['areaM2'] as num?;
      rows.add(_row('면적', areaM2 == null ? '알 수 없음' : '${areaM2.toStringAsFixed(1)} m²', valueKey: const Key('ssIsoSurfaceArea')));
    } else if (sel.objectType == '가구') {
      final widthMm = props['widthMm'] as num?;
      final depthMm = props['depthMm'] as num?;
      final rotation = props['rotation'] as num?;
      rows.add(_row('폭', widthMm == null ? '알 수 없음' : '${widthMm.round()}mm', valueKey: const Key('ssIsoFurnitureWidth')));
      rows.add(_row('깊이', depthMm == null ? '알 수 없음' : '${depthMm.round()}mm', valueKey: const Key('ssIsoFurnitureDepth')));
      rows.add(_row('회전', '${(rotation ?? 0).round()}°', valueKey: const Key('ssIsoFurnitureRotation')));
      rows.add(const SizedBox(height: 6));
      rows.add(
        Row(
          children: [
            IconButton(key: const Key('ssIsoFurnitureMoveLeft'), onPressed: () => controller.moveSelectedFurnitureByMm(-100, 0), icon: const Icon(Icons.arrow_left, size: 18), color: SsMasterTheme.textSecondary),
            IconButton(key: const Key('ssIsoFurnitureMoveRight'), onPressed: () => controller.moveSelectedFurnitureByMm(100, 0), icon: const Icon(Icons.arrow_right, size: 18), color: SsMasterTheme.textSecondary),
            IconButton(key: const Key('ssIsoFurnitureRotate'), onPressed: () => controller.rotateSelectedFurniture(90), icon: const Icon(Icons.rotate_right, size: 18), color: SsMasterTheme.textSecondary),
          ],
        ),
      );
    } else if (sel.objectType == '조명' || sel.objectType == '설비') {
      rows.add(_row('종류', '${props['kind'] ?? ''}', valueKey: const Key('ssIsoLightOrEquipmentKind')));
    }
    final materialLabel = props['materialLabel'] as String?;
    if (materialLabel != null) rows.add(_row('마감재', materialLabel, valueKey: const Key('ssIsoSelectedMaterialLabel')));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }

  Widget _buildMaterialSwatches(SsIsoEditorController controller, dynamic sel) {
    void apply(SsIsoMaterialPreset preset) {
      final color = Color(preset.colorValue);
      if (sel.objectType == '벽') {
        controller.setSelectedWallMaterial(preset.label, color);
      } else if (sel.objectType == '바닥') {
        controller.setSelectedFloorMaterial(preset.label, color);
      } else if (sel.objectType == '천장') {
        controller.setSelectedCeilingMaterial(preset.label, color);
      }
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final preset in kSsIsoMaterialPresets)
          InkWell(
            key: Key('ssIsoMaterial_${preset.label}'),
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
