/// SS011 — MASTER UI 8(CAD 편집·치수·파일 내보내기)의 편집 상태 하나.
///
/// 새로 발명하지 않고 기존 기반을 그대로 쓴다:
/// - Undo/Redo/History → [SsHistory]([SsCadScene] 버전, ss_history.dart).
/// - 선택 표시 → [SsSelection](ss_editing.dart).
/// - 벽 길이/문창 폭 mm 편집·snap·기본 벽/문/창 생성 → 기존
///   services/cad_editing_ops.dart 함수를 그대로 호출(새로 다시 만들지 않는다).
/// - 다중 실측 축척(Calibration) → 기존 models/scale_calibration.dart.
library;

import 'package:flutter/foundation.dart';

import '../models/cad_floor_plan.dart';
import '../models/floor_plan_geometry.dart';
import '../models/scale_calibration.dart';
import '../models/ss_cad_scene.dart';
import '../services/cad_editing_ops.dart';
import 'ss_editing.dart';
import 'ss_history.dart';

/// 캔버스 위 탭/드래그가 어떤 편집으로 이어지는지 결정하는 도구.
enum SsCadTool { select, addWall, addDoor, addWindow, addFurniture, measure, calibrate }

class SsCadEditorController extends ChangeNotifier {
  SsCadEditorController({required SsCadScene initialScene}) : history = SsHistory<SsCadScene>(original: initialScene, label: '시작') {
    history.addListener(notifyListeners);
  }

  /// Undo/Redo/History(§7) — 화면이 커밋 단위 변경(자동저장용)을 들으려면 이 객체를
  /// 직접 구독한다(이 컨트롤러 전체를 구독하면 드래그 미리보기 같은 갱신까지 섞인다).
  final SsHistory<SsCadScene> history;

  SsCadTool tool = SsCadTool.select;
  bool snapEnabled = true;

  SsSelection selection = SsSelection.none;

  /// §거리 측정 — 선택 도구와 별개로 두 점을 찍어 거리를 잰다.
  Point2? measureStart;
  Point2? measureEnd;

  /// §Calibration — 드래그로 고른 실측 대상(벽을 찾았으면 그 벽 전체, 못 찾았으면
  /// 드래그 두 점 폴백, 기존 floor_plan_workspace_screen과 같은 생각).
  Point2? calibrationStart;
  Point2? calibrationEnd;
  String? calibrationWallId;
  final List<ScaleReferenceSample> _scaleSamples = [];
  List<ScaleReferenceSample> get scaleSamples => List.unmodifiable(_scaleSamples);

  SsCadScene get scene => history.current;
  CadFloorPlan get plan => scene.plan;
  FloorPlanScale? get scale => scene.scale;
  bool get canUndo => history.canUndo;
  bool get canRedo => history.canRedo;
  bool get hasCalibrationSelection => calibrationStart != null && calibrationEnd != null;

  static const double _wallHitTolerance = 0.03;

  void setTool(SsCadTool t) {
    if (tool == t) return;
    tool = t;
    measureStart = null;
    measureEnd = null;
    cancelCalibration();
    if (t != SsCadTool.select) selection = SsSelection.none;
    notifyListeners();
  }

  void setSnapEnabled(bool v) {
    snapEnabled = v;
    notifyListeners();
  }

  // ---------------- 선택 ----------------

  CadWall? _findWall(String id) {
    for (final w in plan.walls) {
      if (w.id == id) return w;
    }
    return null;
  }

  CadOpening? _findOpening(String id) {
    for (final o in plan.openings) {
      if (o.id == id) return o;
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
    for (final f in scene.furniture) {
      if (f.id == id) return f;
    }
    return null;
  }

  CadWall? get _selectedWall => selection.objectType == '벽' ? _findWall(selection.objectId) : null;
  SsCadFurniture? get _selectedFurniture => selection.objectType == '가구' ? _findFurniture(selection.objectId) : null;

  void selectWall(String id) {
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
      },
    );
    notifyListeners();
  }

  void selectOpening(String id) {
    final opening = _findOpening(id);
    if (opening == null) return;
    final s = scale;
    selection = SsSelection(
      objectType: opening.type == OpeningType.door ? '문' : '창',
      objectId: id,
      properties: {'widthMm': s == null ? null : plan.realMmForNormalizedLength(opening.widthNormalized, s)},
    );
    notifyListeners();
  }

  void selectRoom(String id) {
    final room = _findRoom(id);
    if (room == null) return;
    selection = SsSelection(objectType: '공간', objectId: id, properties: {'areaM2': roomAreaM2(plan, room, scale)});
    notifyListeners();
  }

  void selectFurniture(String id) {
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
      },
    );
    notifyListeners();
  }

  void clearSelection() {
    if (selection.isEmpty) return;
    selection = SsSelection.none;
    notifyListeners();
  }

  /// 탭 위치(정규화 좌표) 근처의 벽/문·창/공간/가구 중 가장 가까운 것을 고른다.
  /// 아무것도 없으면 선택을 비운다.
  void selectAt(Point2 p) {
    SsCadFurniture? bestFurniture;
    var bestFurnitureDist = 0.05;
    for (final f in scene.furniture) {
      final d = f.center.distanceTo(p);
      if (d < bestFurnitureDist) {
        bestFurnitureDist = d;
        bestFurniture = f;
      }
    }
    if (bestFurniture != null) {
      selectFurniture(bestFurniture.id);
      return;
    }

    CadOpening? bestOpening;
    var bestOpeningDist = 0.03;
    for (final o in plan.openings) {
      final d = o.center.distanceTo(p);
      if (d < bestOpeningDist) {
        bestOpeningDist = d;
        bestOpening = o;
      }
    }
    if (bestOpening != null) {
      selectOpening(bestOpening.id);
      return;
    }

    final wall = nearestCadWall(plan, p, tolerance: _wallHitTolerance);
    if (wall != null) {
      selectWall(wall.id);
      return;
    }

    for (final room in plan.rooms) {
      if (room.containsPoint(p)) {
        selectRoom(room.id);
        return;
      }
    }

    clearSelection();
  }

  // ---------------- 벽 ----------------

  void addWallDrag(Point2 start, Point2 end) {
    final s = snapEnabled ? snapToNearbyEndpoint(plan, start) : start;
    final e = snapEnabled ? snapToNearbyEndpoint(plan, end) : end;
    if (s.distanceTo(e) < 0.01) return;
    final thicknessNormalized = plan.normalizedLengthFromMm(kAssumedUserWallThicknessMm, scale) ?? 0.01;
    final wall = CadWall(
      id: 'user-wall-${DateTime.now().microsecondsSinceEpoch}',
      start: s,
      end: e,
      thicknessNormalized: thicknessNormalized,
      wallType: CadWallType.interior,
      confidence: 1.0,
      source: CadElementSource.userCreated,
      edited: true,
    );
    _push(scene.copyWith(plan: plan.copyWithWalls([...plan.walls, wall])), label: '벽체 생성');
    selectWall(wall.id);
  }

  /// 드래그 없이 "벽체 생성" 버튼만 눌렀을 때 — 기존 위치에 기본 벽 하나를 놓는다
  /// (기존 [createDefaultWall] 그대로, 사용자가 끝점을 드래그해 옮긴다는 전제).
  void addDefaultWall() {
    final wall = createDefaultWall(plan, isExterior: false);
    _push(scene.copyWith(plan: plan.copyWithWalls([...plan.walls, wall])), label: '벽체 생성');
    selectWall(wall.id);
  }

  void moveSelectedWallEndpoint(bool isStart, Point2 newPosition) {
    final wall = _selectedWall;
    if (wall == null) return;
    final snapped = snapEnabled ? snapToNearbyEndpoint(plan, newPosition, excludeWallId: wall.id) : newPosition;
    final edited = wall.copyWith(
      start: isStart ? snapped : null,
      end: isStart ? null : snapped,
      edited: true,
      source: CadElementSource.userEdited,
    );
    _push(scene.copyWith(plan: plan.copyWithWalls([for (final w in plan.walls) if (w.id == wall.id) edited else w])), label: '벽체 이동');
    selectWall(wall.id);
  }

  void duplicateSelectedWall() {
    final wall = _selectedWall;
    if (wall == null) return;
    Point2 off(Point2 p) => Point2((p.x + 0.03).clamp(0.0, 1.0), (p.y + 0.03).clamp(0.0, 1.0));
    final copy = CadWall(
      id: 'user-wall-${DateTime.now().microsecondsSinceEpoch}',
      start: off(wall.start),
      end: off(wall.end),
      thicknessNormalized: wall.thicknessNormalized,
      wallType: wall.wallType,
      confidence: 1.0,
      source: CadElementSource.userCreated,
      edited: true,
      heightMm: wall.heightMm,
    );
    _push(scene.copyWith(plan: plan.copyWithWalls([...plan.walls, copy])), label: '벽체 복사');
    selectWall(copy.id);
  }

  void setSelectedWallLengthMm(double lengthMm) {
    final wall = _selectedWall;
    final s = scale;
    if (wall == null || s == null || lengthMm <= 0) return;
    final edited = wallWithLengthMm(plan, wall, lengthMm, s);
    _push(scene.copyWith(plan: plan.copyWithWalls([for (final w in plan.walls) if (w.id == wall.id) edited else w])), label: '벽체 길이 수정');
    selectWall(wall.id);
  }

  void setSelectedWallThicknessMm(double thicknessMm) {
    final wall = _selectedWall;
    final s = scale;
    if (wall == null || s == null || thicknessMm <= 0) return;
    final normalized = plan.normalizedLengthFromMm(thicknessMm, s);
    if (normalized == null) return;
    final edited = wall.copyWith(thicknessNormalized: normalized, edited: true, source: CadElementSource.userEdited);
    _push(scene.copyWith(plan: plan.copyWithWalls([for (final w in plan.walls) if (w.id == wall.id) edited else w])), label: '벽체 두께 수정');
    selectWall(wall.id);
  }

  void setSelectedWallHeightMm(double heightMm) {
    final wall = _selectedWall;
    if (wall == null || heightMm <= 0) return;
    final edited = wall.copyWith(heightMm: heightMm, edited: true, source: CadElementSource.userEdited);
    _push(scene.copyWith(plan: plan.copyWithWalls([for (final w in plan.walls) if (w.id == wall.id) edited else w])), label: '벽체 높이 수정');
    selectWall(wall.id);
  }

  // ---------------- 문/창 ----------------

  void addOpeningOnSelectedWall(OpeningType type) {
    final wall = _selectedWall;
    if (wall == null) return;
    final created = createOpeningOnWall(plan, wall, type: type, scale: scale);
    _push(_withOpenings([...plan.openings, created]), label: type == OpeningType.door ? '문 추가' : '창문 추가');
    selectOpening(created.id);
  }

  void addOpeningAtPoint(Point2 point, OpeningType type) {
    final wall = nearestCadWall(plan, point, tolerance: _wallHitTolerance);
    if (wall == null) return;
    final projected = wall.projectPoint(point);
    final assumedWidthMm = type == OpeningType.door ? kAssumedDoorWidthMm : kAssumedWindowWidthMm;
    final widthNormalized = plan.normalizedLengthFromMm(assumedWidthMm, scale) ?? 0.02;
    final opening = CadOpening(
      id: 'user-${type.name}-${DateTime.now().microsecondsSinceEpoch}',
      type: type,
      center: projected.point,
      widthNormalized: widthNormalized,
      confidence: 1.0,
      wallId: wall.id,
      source: CadElementSource.userCreated,
      edited: true,
    );
    _push(_withOpenings([...plan.openings, opening]), label: type == OpeningType.door ? '문 추가' : '창문 추가');
    selectOpening(opening.id);
  }

  void setSelectedOpeningWidthMm(double widthMm) {
    final opening = (selection.objectType == '문' || selection.objectType == '창') ? _findOpening(selection.objectId) : null;
    final s = scale;
    if (opening == null || s == null || widthMm <= 0) return;
    final edited = openingWithWidthMm(plan, opening, widthMm, s);
    _push(_withOpenings([for (final o in plan.openings) if (o.id == opening.id) edited else o]), label: '${selection.objectType} 폭 수정');
    selectOpening(opening.id);
  }

  SsCadScene _withOpenings(List<CadOpening> openings) => scene.copyWith(
    plan: CadFloorPlan(
      sourceWidthPx: plan.sourceWidthPx,
      sourceHeightPx: plan.sourceHeightPx,
      walls: plan.walls,
      openings: openings,
      rooms: plan.rooms,
      warnings: plan.warnings,
      objectCandidates: plan.objectCandidates,
    ),
  );

  // ---------------- 가구/주요 객체 ----------------

  void addFurnitureAt(SsCadFurnitureKind kind, Point2 center) {
    final f = SsCadFurniture(
      id: 'furniture-${DateTime.now().microsecondsSinceEpoch}',
      kind: kind,
      center: center,
      widthNormalized: 0.08,
      depthNormalized: 0.05,
    );
    _push(scene.copyWith(furniture: [...scene.furniture, f]), label: '가구 넣기');
    selectFurniture(f.id);
  }

  void addFurniture(SsCadFurnitureKind kind) => addFurnitureAt(kind, const Point2(0.5, 0.5));

  void moveSelectedFurniture(Point2 newCenter) {
    final f = _selectedFurniture;
    if (f == null) return;
    final updated = f.copyWith(
      center: Point2(newCenter.x.clamp(0.0, 1.0), newCenter.y.clamp(0.0, 1.0)),
    );
    _push(scene.copyWith(furniture: [for (final x in scene.furniture) if (x.id == f.id) updated else x]), label: '가구 이동');
    selectFurniture(f.id);
  }

  void rotateSelectedFurniture(double deltaDegrees) {
    final f = _selectedFurniture;
    if (f == null) return;
    final updated = f.copyWith(rotationDegrees: (f.rotationDegrees + deltaDegrees) % 360);
    _push(scene.copyWith(furniture: [for (final x in scene.furniture) if (x.id == f.id) updated else x]), label: '가구 회전');
    selectFurniture(f.id);
  }

  void setSelectedFurnitureWidthMm(double widthMm) {
    final f = _selectedFurniture;
    final s = scale;
    final normalized = s == null ? null : plan.normalizedLengthFromMm(widthMm, s);
    if (f == null || normalized == null) return;
    final updated = f.copyWith(widthNormalized: normalized);
    _push(scene.copyWith(furniture: [for (final x in scene.furniture) if (x.id == f.id) updated else x]), label: '가구 크기 조정');
    selectFurniture(f.id);
  }

  void setSelectedFurnitureDepthMm(double depthMm) {
    final f = _selectedFurniture;
    final s = scale;
    final normalized = s == null ? null : plan.normalizedLengthFromMm(depthMm, s);
    if (f == null || normalized == null) return;
    final updated = f.copyWith(depthNormalized: normalized);
    _push(scene.copyWith(furniture: [for (final x in scene.furniture) if (x.id == f.id) updated else x]), label: '가구 크기 조정');
    selectFurniture(f.id);
  }

  void duplicateSelectedFurniture() {
    final f = _selectedFurniture;
    if (f == null) return;
    final copy = SsCadFurniture(
      id: 'furniture-${DateTime.now().microsecondsSinceEpoch}',
      kind: f.kind,
      center: Point2((f.center.x + 0.03).clamp(0.0, 1.0), (f.center.y + 0.03).clamp(0.0, 1.0)),
      widthNormalized: f.widthNormalized,
      depthNormalized: f.depthNormalized,
      rotationDegrees: f.rotationDegrees,
      label: f.label,
    );
    _push(scene.copyWith(furniture: [...scene.furniture, copy]), label: '가구 복사');
    selectFurniture(copy.id);
  }

  // ---------------- 삭제(공용) ----------------

  /// 지금 선택된 대상(벽/문/창/공간/가구)을 삭제한다. 벽을 지우면 그 벽에 붙어
  /// 있던 문/창도 함께 지운다(허공에 뜬 개구부를 남기지 않는다).
  void deleteSelected() {
    if (selection.isEmpty) return;
    final id = selection.objectId;
    switch (selection.objectType) {
      case '벽':
        _push(
          scene.copyWith(
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
          label: '벽체 삭제',
        );
      case '문':
      case '창':
        _push(_withOpenings(plan.openings.where((o) => o.id != id).toList()), label: '${selection.objectType} 삭제');
      case '공간':
        _push(
          scene.copyWith(
            plan: CadFloorPlan(
              sourceWidthPx: plan.sourceWidthPx,
              sourceHeightPx: plan.sourceHeightPx,
              walls: plan.walls,
              openings: plan.openings,
              rooms: plan.rooms.where((r) => r.id != id).toList(),
              warnings: plan.warnings,
              objectCandidates: plan.objectCandidates,
            ),
          ),
          label: '공간 삭제',
        );
      case '가구':
        _push(scene.copyWith(furniture: scene.furniture.where((f) => f.id != id).toList()), label: '가구 삭제');
    }
    selection = SsSelection.none;
  }

  /// 지금 선택된 벽/가구를 복사한다(다른 종류는 아직 지원하지 않는다).
  void duplicateSelected() {
    switch (selection.objectType) {
      case '벽':
        duplicateSelectedWall();
      case '가구':
        duplicateSelectedFurniture();
    }
  }

  // ---------------- 거리 측정 ----------------

  void measureTapAt(Point2 p) {
    if (measureStart == null || measureEnd != null) {
      measureStart = p;
      measureEnd = null;
    } else {
      measureEnd = p;
    }
    notifyListeners();
  }

  double? get measureDistanceMm {
    final a = measureStart;
    final b = measureEnd;
    final s = scale;
    if (a == null || b == null || s == null) return null;
    return plan.realMmBetween(a, b, s);
  }

  void clearMeasurement() {
    measureStart = null;
    measureEnd = null;
    notifyListeners();
  }

  // ---------------- Calibration(실제 치수 보존) ----------------

  void startCalibrationDrag(Point2 dragStart, Point2 dragEnd) {
    final wall = nearestCadWall(plan, dragStart, tolerance: _wallHitTolerance) ?? nearestCadWall(plan, dragEnd, tolerance: _wallHitTolerance);
    calibrationStart = wall?.start ?? dragStart;
    calibrationEnd = wall?.end ?? dragEnd;
    calibrationWallId = wall?.id;
    notifyListeners();
  }

  void cancelCalibration() {
    calibrationStart = null;
    calibrationEnd = null;
    calibrationWallId = null;
  }

  void applyCalibrationLengthMm(double lengthMm) {
    final start = calibrationStart;
    final end = calibrationEnd;
    if (start == null || end == null || lengthMm <= 0) return;
    final pixelLength = plan.pixelDistance(start, end);
    if (pixelLength <= 0) return;
    final sample = ScaleReferenceSample(wallId: calibrationWallId, pixelLength: pixelLength, measuredMm: lengthMm);
    final wallId = calibrationWallId;
    _scaleSamples
      ..removeWhere((s) => wallId != null && s.wallId == wallId)
      ..add(sample);
    final result = resolveScaleFromSamples(_scaleSamples);
    final newScale = FloorPlanScale(
      mmPerPixel: result.mmPerPixel,
      referenceStart: start,
      referenceEnd: end,
      referenceLengthMm: lengthMm,
      source: ScaleSource.measured,
    );
    cancelCalibration();
    _push(scene.copyWith(scale: newScale), label: '치수 보정');
  }

  // ---------------- Undo / Redo ----------------

  void _push(SsCadScene next, {required String label}) => history.push(next, label: label);

  void undo() {
    selection = SsSelection.none;
    history.undo();
  }

  void redo() {
    selection = SsSelection.none;
    history.redo();
  }

  @override
  void dispose() {
    history.removeListener(notifyListeners);
    history.dispose();
    super.dispose();
  }
}
