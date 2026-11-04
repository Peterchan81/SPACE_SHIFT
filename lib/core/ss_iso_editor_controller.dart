/// SS013 — MASTER UI 10(3D 아이소 작업) 편집 상태. [SsCadEditorController](SS011)와 같은 생각으로
/// 기존 기반을 그대로 쓴다: Undo/Redo/History → [SsHistory], 선택 표시 → [SsSelection], 벽/문/창
/// 편집 계산 → 기존 services/cad_editing_ops.dart, 3D geometry → [buildIsoEditorScene]
/// (기존 [buildSpaceSceneV2]를 그대로 감싼다). 색/재질은 새 파이프라인을 만들지 않고 기존
/// [CadWall.materialOverride]/[CadRoom.materialOverride]/[CadRoom.ceilingMaterialOverride]에 쓴다.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;

import '../models/cad_floor_plan.dart';
import '../models/floor_plan_geometry.dart';
import '../models/space_scene_v2.dart';
import '../models/ss_cad_scene.dart';
import '../models/ss_iso_design_extras.dart';
import '../services/cad_editing_ops.dart';
import '../services/ss_iso_editor_scene_builder.dart';
import 'ss_editing.dart';
import 'ss_history.dart';

/// MASTER UI 10 리본 그룹에 대응하는 도구. 실제 벽/문/창/가구 "추가"는 드래그 없이 버튼 1번으로
/// 기본값을 놓는다(3D Orbit 화면에서는 2D 평면도처럼 두 점을 찍어 그릴 평면이 없다 — 기존
/// [SsCadEditorController.addDefaultWall]과 같은 생각, 위치는 선택 후 이동/치수 입력으로 정한다).
enum SsIsoTool { select, addWall, addDoor, addWindow, addFurniture, addLight, addEquipment }

/// [SsHistory]가 보관하는 값 하나 — 기존 [SsCadScene](구조/가구) + SS013 전용 추가 데이터.
@immutable
class SsIsoEditorState {
  const SsIsoEditorState({required this.cad, this.extras = SsIsoDesignExtras.empty});
  final SsCadScene cad;
  final SsIsoDesignExtras extras;

  SsIsoEditorState copyWith({SsCadScene? cad, SsIsoDesignExtras? extras}) => SsIsoEditorState(cad: cad ?? this.cad, extras: extras ?? this.extras);
}

class SsIsoEditorController extends ChangeNotifier {
  SsIsoEditorController({required SsIsoEditorState initialState, this.ceilingHeightMm = 2400})
    : history = SsHistory<SsIsoEditorState>(original: initialState, label: '시작') {
    history.addListener(notifyListeners);
  }

  final SsHistory<SsIsoEditorState> history;
  final double ceilingHeightMm;

  SsIsoTool tool = SsIsoTool.select;
  SsCadFurnitureKind pendingFurnitureKind = SsCadFurnitureKind.other;
  SsIsoLightKind pendingLightKind = SsIsoLightKind.downlight;
  SsIsoEquipmentKind pendingEquipmentKind = SsIsoEquipmentKind.sink;

  /// 선택 표시(§기존 [SsEditing]) — objectType은 '벽'/'문'/'창'/'바닥'/'천장'/'가구'/'조명'/'설비' 중 하나.
  SsSelection selection = SsSelection.none;

  /// 지금 선택된 3D objectId(Space3DViewGpuV2.selectedObjectId에 그대로 넘긴다) — [selection]과
  /// 별도로 둔다. 2D 쪽([SsSelection.objectId])은 항상 자연 id(wallId/roomId/...)를 쓰지만, 3D
  /// 하이라이트는 "바닥"과 "천장"처럼 같은 자연 id를 공유하는 두 객체를 구분해야 하기 때문이다.
  String? selectedObjectId3d;

  SsIsoEditorState get state => history.current;
  SsCadScene get cad => state.cad;
  CadFloorPlan get plan => cad.plan;
  FloorPlanScale? get scale => cad.scale;
  SsIsoDesignExtras get extras => state.extras;
  bool get canUndo => history.canUndo;
  bool get canRedo => history.canRedo;

  /// 실제 3D scene — [buildSpaceSceneV2]는 순수 함수라 매번 다시 만들어도 안전하다(기존
  /// [IsoConversionService] 주석과 같은 결론). 캐시를 두지 않아 "캐시가 낡는" 버그 자체가 없다.
  SpaceSceneV2 get scene3d => buildIsoEditorScene(cad: cad, extras: extras, ceilingHeightMm: ceilingHeightMm);

  static const double _wallHitTolerance = 0.03;

  void setTool(SsIsoTool t) {
    if (tool == t) return;
    tool = t;
    notifyListeners();
  }

  void _push(SsIsoEditorState next, {required String label}) => history.push(next, label: label);

  CadWall? _findWall(String id) {
    for (final w in plan.walls) {
      if (w.id == id) return w;
    }
    return null;
  }

  CadRoom? _findRoom(String id) {
    for (final r in plan.rooms) {
      if (r.id == id) return r;
    }
    return null;
  }

  SsCadFurniture? _findFurniture(String id) {
    for (final f in cad.furniture) {
      if (f.id == id) return f;
    }
    return null;
  }

  SsIsoLight? _findLight(String id) {
    for (final l in extras.lights) {
      if (l.id == id) return l;
    }
    return null;
  }

  SsIsoEquipment? _findEquipment(String id) {
    for (final e in extras.equipment) {
      if (e.id == id) return e;
    }
    return null;
  }

  // ---------------- 선택(3D 피킹 → 압축 속성 패널) ----------------

  /// [Space3DViewGpuV2.onObjectSelected] 콜백 — 화면이 그대로 넘긴다. null이면 선택 해제.
  void selectObjectIdentity(SpaceObjectIdentityV2? identity) {
    if (identity == null) {
      clearSelection();
      return;
    }
    selectedObjectId3d = identity.objectId;
    final objectId = identity.objectId;
    if (identity.sourceKind == SpaceElementKindV2.wall && identity.wallId != null) {
      _selectWall(identity.wallId!);
    } else if (identity.sourceKind == SpaceElementKindV2.floor && identity.roomId != null) {
      _selectSurface('바닥', identity.roomId!, objectId);
    } else if (identity.sourceKind == SpaceElementKindV2.ceiling && identity.roomId != null) {
      _selectSurface('천장', identity.roomId!, objectId);
    } else if (objectId.startsWith('isoFurniture:')) {
      _selectFurniture(objectId.substring('isoFurniture:'.length));
    } else if (objectId.startsWith('furniture:')) {
      selection = SsSelection(objectType: '가구(자동)', objectId: objectId, editable: false);
      notifyListeners();
    } else if (objectId.startsWith('isoLight:')) {
      _selectLight(objectId.substring('isoLight:'.length));
    } else if (objectId.startsWith('isoEquipment:')) {
      _selectEquipment(objectId.substring('isoEquipment:'.length));
    } else {
      selection = SsSelection(objectType: '객체', objectId: objectId, editable: false);
      notifyListeners();
    }
  }

  void _selectWall(String id) {
    final wall = _findWall(id);
    if (wall == null) return;
    final s = scale;
    selection = SsSelection(
      objectType: '벽',
      objectId: id,
      properties: {
        'lengthMm': plan.realMmBetween(wall.start, wall.end, s),
        'thicknessMm': s == null ? null : plan.realMmForNormalizedLength(wall.thicknessNormalized, s),
        'heightMm': wall.heightMm,
        'materialLabel': extras.materialLabels['wall:$id'],
      },
    );
    notifyListeners();
  }

  void _selectSurface(String type, String roomId, String objectId3d) {
    final room = _findRoom(roomId);
    if (room == null) return;
    selection = SsSelection(
      objectType: type,
      objectId: roomId,
      properties: {'areaM2': roomAreaM2(plan, room, scale), 'materialLabel': extras.materialLabels[objectId3d]},
    );
    notifyListeners();
  }

  void _selectFurniture(String id) {
    final f = _findFurniture(id);
    if (f == null) return;
    final s = scale;
    selection = SsSelection(
      objectType: '가구',
      objectId: id,
      properties: {
        'widthMm': s == null ? null : plan.realMmForNormalizedLength(f.widthNormalized, s),
        'depthMm': s == null ? null : plan.realMmForNormalizedLength(f.depthNormalized, s),
        'rotation': f.rotationDegrees,
        'kind': f.kind.label,
      },
    );
    notifyListeners();
  }

  void _selectLight(String id) {
    final l = _findLight(id);
    if (l == null) return;
    selection = SsSelection(objectType: '조명', objectId: id, properties: {'kind': l.kind.label});
    notifyListeners();
  }

  void _selectEquipment(String id) {
    final e = _findEquipment(id);
    if (e == null) return;
    selection = SsSelection(objectType: '설비', objectId: id, properties: {'kind': e.kind.label});
    notifyListeners();
  }

  void clearSelection() {
    if (selection.isEmpty && selectedObjectId3d == null) return;
    selection = SsSelection.none;
    selectedObjectId3d = null;
    notifyListeners();
  }

  /// 선택된 벽이 있으면 그 wallId — SS014(정면도·측면도 편집)로 넘길 때 쓴다.
  String? get selectedWallIdForElevationHandoff => selection.objectType == '벽' ? selection.objectId : null;

  // ---------------- 구조(벽/문/창) ----------------

  void addDefaultWall() {
    final wall = createDefaultWall(plan, isExterior: false);
    _push(state.copyWith(cad: cad.copyWith(plan: plan.copyWithWalls([...plan.walls, wall]))), label: '벽체 생성');
    selectObjectIdentity(SpaceObjectIdentityV2(objectId: 'wall:${wall.id}', sourceKind: SpaceElementKindV2.wall, sourceId: wall.id, wallId: wall.id));
  }

  void setSelectedWallLengthMm(double lengthMm) {
    final wall = selection.objectType == '벽' ? _findWall(selection.objectId) : null;
    final s = scale;
    if (wall == null || s == null || lengthMm <= 0) return;
    final edited = wallWithLengthMm(plan, wall, lengthMm, s);
    _push(state.copyWith(cad: cad.copyWith(plan: plan.copyWithWalls([for (final w in plan.walls) if (w.id == wall.id) edited else w]))), label: '벽체 길이 수정');
    _selectWall(wall.id);
  }

  void setSelectedWallThicknessMm(double thicknessMm) {
    final wall = selection.objectType == '벽' ? _findWall(selection.objectId) : null;
    final s = scale;
    final normalized = s == null ? null : plan.normalizedLengthFromMm(thicknessMm, s);
    if (wall == null || normalized == null || thicknessMm <= 0) return;
    final edited = wall.copyWith(thicknessNormalized: normalized, edited: true, source: CadElementSource.userEdited);
    _push(state.copyWith(cad: cad.copyWith(plan: plan.copyWithWalls([for (final w in plan.walls) if (w.id == wall.id) edited else w]))), label: '벽체 두께 수정');
    _selectWall(wall.id);
  }

  void setSelectedWallHeightMm(double heightMm) {
    final wall = selection.objectType == '벽' ? _findWall(selection.objectId) : null;
    if (wall == null || heightMm <= 0) return;
    final edited = wall.copyWith(heightMm: heightMm, edited: true, source: CadElementSource.userEdited);
    _push(state.copyWith(cad: cad.copyWith(plan: plan.copyWithWalls([for (final w in plan.walls) if (w.id == wall.id) edited else w]))), label: '벽체 높이 수정');
    _selectWall(wall.id);
  }

  void addOpeningOnSelectedWall(OpeningType type) {
    final wall = selection.objectType == '벽' ? _findWall(selection.objectId) : null;
    if (wall == null) return;
    final created = createOpeningOnWall(plan, wall, type: type, scale: scale);
    _push(state.copyWith(cad: cad.copyWith(plan: _planWithOpenings([...plan.openings, created]))), label: type == OpeningType.door ? '문 추가' : '창문 추가');
    _selectWall(wall.id);
  }

  CadFloorPlan _planWithOpenings(List<CadOpening> openings) => CadFloorPlan(
    sourceWidthPx: plan.sourceWidthPx,
    sourceHeightPx: plan.sourceHeightPx,
    walls: plan.walls,
    openings: openings,
    rooms: plan.rooms,
    warnings: plan.warnings,
    objectCandidates: plan.objectCandidates,
  );

  void deleteSelectedWall() {
    final id = selection.objectId;
    _push(
      state.copyWith(
        cad: cad.copyWith(
          plan: CadFloorPlan(
            sourceWidthPx: plan.sourceWidthPx,
            sourceHeightPx: plan.sourceHeightPx,
            walls: plan.walls.where((w) => w.id != id).toList(),
            openings: plan.openings.where((o) => o.wallId != id).toList(),
            rooms: plan.rooms,
            warnings: plan.warnings,
            objectCandidates: plan.objectCandidates,
          ),
        ),
      ),
      label: '벽체 철거',
    );
    clearSelection();
  }

  // ---------------- 마감재/색상(벽/바닥/천장) ----------------

  void setSelectedWallMaterial(String materialLabel, Color color) {
    final wall = selection.objectType == '벽' ? _findWall(selection.objectId) : null;
    if (wall == null) return;
    final edited = wall.copyWith(materialOverride: color, edited: true, source: CadElementSource.userEdited);
    final labels = {...extras.materialLabels, 'wall:${wall.id}': materialLabel};
    _push(state.copyWith(cad: cad.copyWith(plan: plan.copyWithWalls([for (final w in plan.walls) if (w.id == wall.id) edited else w])), extras: extras.copyWith(materialLabels: labels)), label: '벽 마감재 변경');
    _selectWall(wall.id);
  }

  void setSelectedFloorMaterial(String materialLabel, Color color) {
    final room = selection.objectType == '바닥' ? _findRoom(selection.objectId) : null;
    if (room == null) return;
    final edited = room.withMaterialOverride(color);
    final labels = {...extras.materialLabels, 'floor:${room.id}': materialLabel};
    _push(state.copyWith(cad: cad.copyWith(plan: _planWithRooms([for (final r in plan.rooms) if (r.id == room.id) edited else r])), extras: extras.copyWith(materialLabels: labels)), label: '바닥 마감재 변경');
    _selectSurface('바닥', room.id, 'floor:${room.id}');
  }

  void setSelectedCeilingMaterial(String materialLabel, Color color) {
    final room = selection.objectType == '천장' ? _findRoom(selection.objectId) : null;
    if (room == null) return;
    final edited = room.withCeilingMaterialOverride(color);
    final labels = {...extras.materialLabels, 'ceiling:${room.id}': materialLabel};
    _push(state.copyWith(cad: cad.copyWith(plan: _planWithRooms([for (final r in plan.rooms) if (r.id == room.id) edited else r])), extras: extras.copyWith(materialLabels: labels)), label: '천장 마감재 변경');
    _selectSurface('천장', room.id, 'ceiling:${room.id}');
  }

  CadFloorPlan _planWithRooms(List<CadRoom> rooms) => CadFloorPlan(
    sourceWidthPx: plan.sourceWidthPx,
    sourceHeightPx: plan.sourceHeightPx,
    walls: plan.walls,
    openings: plan.openings,
    rooms: rooms,
    warnings: plan.warnings,
    objectCandidates: plan.objectCandidates,
  );

  // ---------------- 가구 ----------------

  void addFurniture(SsCadFurnitureKind kind) {
    final f = SsCadFurniture(id: 'iso-furniture-${DateTime.now().microsecondsSinceEpoch}', kind: kind, center: const Point2(0.5, 0.5), widthNormalized: 0.08, depthNormalized: 0.05);
    _push(state.copyWith(cad: cad.copyWith(furniture: [...cad.furniture, f])), label: '가구 추가');
    selectObjectIdentity(SpaceObjectIdentityV2(objectId: 'isoFurniture:${f.id}', sourceKind: SpaceElementKindV2.furniture, sourceId: f.id));
  }

  /// mm 단위 이동 — 3D Orbit 화면에는 평면도 같은 드래그 평면이 없어 선택된 가구를 방향 버튼(상하좌우
  /// 한 칸씩)으로 옮긴다. 정규화 좌표로 바꿔 [SsCadFurniture.center]를 갱신한다(2D CAD 편집기와 같은
  /// 저장 형식이라 CAD 쪽에도 그대로 반영된다).
  void moveSelectedFurnitureByMm(double dxMm, double dzMm) {
    final f = selection.objectType == '가구' ? _findFurniture(selection.objectId) : null;
    final s = scale;
    if (f == null || s == null) return;
    final dxNorm = plan.sourceWidthPx > 0 ? dxMm / (plan.sourceWidthPx * s.mmPerPixel) : 0.0;
    final dzNorm = plan.sourceHeightPx > 0 ? dzMm / (plan.sourceHeightPx * s.mmPerPixel) : 0.0;
    final updated = f.copyWith(center: Point2((f.center.x + dxNorm).clamp(0.0, 1.0), (f.center.y + dzNorm).clamp(0.0, 1.0)));
    _push(state.copyWith(cad: cad.copyWith(furniture: [for (final x in cad.furniture) if (x.id == f.id) updated else x])), label: '가구 이동');
    _selectFurniture(f.id);
  }

  void rotateSelectedFurniture(double deltaDegrees) {
    final f = selection.objectType == '가구' ? _findFurniture(selection.objectId) : null;
    if (f == null) return;
    final updated = f.copyWith(rotationDegrees: (f.rotationDegrees + deltaDegrees) % 360);
    _push(state.copyWith(cad: cad.copyWith(furniture: [for (final x in cad.furniture) if (x.id == f.id) updated else x])), label: '가구 회전');
    _selectFurniture(f.id);
  }

  void deleteSelectedFurniture() {
    final id = selection.objectId;
    _push(state.copyWith(cad: cad.copyWith(furniture: cad.furniture.where((f) => f.id != id).toList())), label: '가구 삭제');
    clearSelection();
  }

  /// 자동 생성된 가구([buildSpaceSceneV2]가 방 종류로부터 만든 것) 등, CAD 모델에 없는 3D 전용 객체는
  /// 지울 수 없으니(모델 자체가 없다) 3D에서만 숨긴다.
  void hideAutoObject() {
    final id = selectedObjectId3d;
    if (id == null) return;
    _push(state.copyWith(extras: extras.copyWith(hiddenObjectIds: {...extras.hiddenObjectIds, id})), label: '객체 숨김');
    clearSelection();
  }

  // ---------------- 조명/설비 ----------------

  void addLight(SsIsoLightKind kind, {String roomId = ''}) {
    final center = roomId.isEmpty ? null : roomCenterMm(plan, scale ?? resolveAutoScale(plan, null), roomId);
    final x = center?.x ?? 0, z = center?.z ?? 0;
    final light = SsIsoLight(id: 'light-${DateTime.now().microsecondsSinceEpoch}', kind: kind, roomId: roomId, xMm: x, yMm: ceilingHeightMm - 150, zMm: z);
    _push(state.copyWith(extras: extras.copyWith(lights: [...extras.lights, light])), label: '조명 추가');
    selectObjectIdentity(SpaceObjectIdentityV2(objectId: 'isoLight:${light.id}', sourceKind: SpaceElementKindV2.light, sourceId: light.id, roomId: roomId));
  }

  void moveSelectedLightByMm(double dxMm, double dzMm) {
    final l = selection.objectType == '조명' ? _findLight(selection.objectId) : null;
    if (l == null) return;
    final updated = l.copyWith(xMm: l.xMm + dxMm, zMm: l.zMm + dzMm);
    _push(state.copyWith(extras: extras.copyWith(lights: [for (final x in extras.lights) if (x.id == l.id) updated else x])), label: '조명 이동');
    _selectLight(l.id);
  }

  void deleteSelectedLight() {
    final id = selection.objectId;
    _push(state.copyWith(extras: extras.copyWith(lights: extras.lights.where((l) => l.id != id).toList())), label: '조명 삭제');
    clearSelection();
  }

  void addEquipment(SsIsoEquipmentKind kind, {String roomId = ''}) {
    final center = roomId.isEmpty ? null : roomCenterMm(plan, scale ?? resolveAutoScale(plan, null), roomId);
    final equipment = SsIsoEquipment(id: 'equipment-${DateTime.now().microsecondsSinceEpoch}', kind: kind, roomId: roomId, xMm: center?.x ?? 0, zMm: center?.z ?? 0);
    _push(state.copyWith(extras: extras.copyWith(equipment: [...extras.equipment, equipment])), label: '설비 추가');
    selectObjectIdentity(SpaceObjectIdentityV2(objectId: 'isoEquipment:${equipment.id}', sourceKind: SpaceElementKindV2.other, sourceId: equipment.id, roomId: roomId));
  }

  void moveSelectedEquipmentByMm(double dxMm, double dzMm) {
    final e = selection.objectType == '설비' ? _findEquipment(selection.objectId) : null;
    if (e == null) return;
    final updated = e.copyWith(xMm: e.xMm + dxMm, zMm: e.zMm + dzMm);
    _push(state.copyWith(extras: extras.copyWith(equipment: [for (final x in extras.equipment) if (x.id == e.id) updated else x])), label: '설비 이동');
    _selectEquipment(e.id);
  }

  void deleteSelectedEquipment() {
    final id = selection.objectId;
    _push(state.copyWith(extras: extras.copyWith(equipment: extras.equipment.where((e) => e.id != id).toList())), label: '설비 삭제');
    clearSelection();
  }

  /// 지금 선택에 맞는 삭제(공용 — 리본의 "삭제" 버튼 하나가 선택 종류에 따라 알맞게 처리한다).
  void deleteSelected() {
    switch (selection.objectType) {
      case '벽':
        deleteSelectedWall();
      case '가구':
        deleteSelectedFurniture();
      case '가구(자동)':
        hideAutoObject();
      case '조명':
        deleteSelectedLight();
      case '설비':
        deleteSelectedEquipment();
    }
  }

  // ---------------- Undo/Redo ----------------

  void undo() {
    clearSelection();
    history.undo();
  }

  void redo() {
    clearSelection();
    history.redo();
  }

  @override
  void dispose() {
    history.removeListener(notifyListeners);
    history.dispose();
    super.dispose();
  }
}

/// [nearestCadWall]/[_wallHitTolerance]는 3D에서는 2D 좌표 피킹이 필요 없어(Space3DViewGpuV2가
/// ray로 직접 알려준다) 이 컨트롤러는 쓰지 않는다 — 혼동을 피하려 상수 자체도 다른 WO가 재사용하지
/// 않도록 private로 둔다(lint용 참고 주석, 실제로는 미사용 경고 방지를 위해 아래에서 한 번 참조한다).
void debugUnusedSsIsoEditorConstantsNotice() => nearestCadWall(const CadFloorPlan(sourceWidthPx: 1, sourceHeightPx: 1, walls: [], openings: [], rooms: [], warnings: []), const Point2(0, 0), tolerance: SsIsoEditorController._wallHitTolerance);
