/// SS005 — 직접 그리기 평면도 에디터의 도구 상태 하나(선택 도구·격자·Snap·Pan/Zoom·Undo/Redo).
///
/// 새로 발명하지 않고 기존 기반을 그대로 쓴다:
/// - Undo/Redo/History → [SsHistory]([SsDrawScene] 버전).
/// - 선택 표시 → [SsSelection](ss_editing.dart).
/// - 길이/단위(mm 기본, cm/m 확장 가능) → [SsLength]/[SsLengthUnit].
/// - 화면 pan/pinch zoom → [WorkspaceViewportTransform](이미 WO089가 만든 변환 하나를 그대로 재사용).
///
/// 입력 구분(§12)은 [SsInput.primaryDrag]를 그대로 따른다 — 손가락 1개 드래그는 도구와 무관하게 항상
/// 화면 이동(Pan)이다(실수로 선이 그려지지 않게). 그래서 터치는 탭 2번으로 벽을 긋고(아래 [beginWallDraft]/
/// [commitWallDraft]를 탭마다 호출), 마우스/스타일러스는 누른 채 드래그로 긋는다 — 화면([DirectDrawScreen])이
/// 입력 종류에 따라 어느 쪽을 부를지 고른다.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Offset;

import '../models/ss_draw_scene.dart';
import '../models/workspace_viewport_transform.dart';
import 'ss_editing.dart';
import 'ss_history.dart';

/// 상단 도구모음의 도구 — SS005 구현범위(벽·문·창·선택·이동·삭제)만 둔다.
enum SsDrawTool { select, move, wall, door, window, delete }

class SsDrawEditorController extends ChangeNotifier {
  SsDrawEditorController({SsDrawScene? initialScene}) : history = SsHistory<SsDrawScene>(original: initialScene ?? SsDrawScene.empty, label: '시작') {
    history.addListener(notifyListeners);
  }

  /// Undo/Redo/History(§7) — 화면([DirectDrawScreen])이 커밋 단위 변경(자동저장용)을 들으려면
  /// 이 객체를 직접 구독한다(이 컨트롤러 전체를 구독하면 드래그 미리보기 같은 화면 갱신까지 섞인다).
  final SsHistory<SsDrawScene> history;

  SsDrawTool tool = SsDrawTool.select;
  bool snapEnabled = true;
  bool gridVisible = true;
  double gridMm = SsLength.gridDefault.mm;
  SsLengthUnit displayUnit = SsLengthUnit.mm;

  WorkspaceViewportTransform viewport = WorkspaceViewportTransform.identity;

  SsSelection selection = SsSelection.none;

  SsDrawPoint? wallDraftStart;
  SsDrawPoint? wallDraftEnd;

  SsDrawScene? _liveScene;
  SsDrawScene? _dragBaseScene;

  static const double _endpointSnapToleranceMm = 150;
  static const double _hitToleranceMm = 150;

  /// 지금 보여줄 평면도 — 드래그 중이면 아직 History에 쌓이지 않은 미리보기.
  SsDrawScene get scene => _liveScene ?? history.current;
  bool get canUndo => history.canUndo;
  bool get canRedo => history.canRedo;
  bool get isDragging => _dragBaseScene != null;

  // ---------------- 도구/옵션 ----------------

  void setTool(SsDrawTool t) {
    if (tool == t) return;
    tool = t;
    wallDraftStart = null;
    wallDraftEnd = null;
    if (t != SsDrawTool.select && t != SsDrawTool.move) selection = SsSelection.none;
    notifyListeners();
  }

  void setSnapEnabled(bool v) {
    snapEnabled = v;
    notifyListeners();
  }

  void setGridVisible(bool v) {
    gridVisible = v;
    notifyListeners();
  }

  void setGridMm(double v) {
    gridMm = v;
    notifyListeners();
  }

  void setDisplayUnit(SsLengthUnit u) {
    displayUnit = u;
    notifyListeners();
  }

  // ---------------- Pan / Zoom / Pinch Zoom ----------------

  void setViewport(WorkspaceViewportTransform v) {
    viewport = v;
    notifyListeners();
  }

  void zoomByFactor(double factor, {required Offset focal}) {
    viewport = viewport.zoomBy(factor, focalPoint: focal);
    notifyListeners();
  }

  void resetViewport() {
    viewport = WorkspaceViewportTransform.identity;
    notifyListeners();
  }

  // ---------------- Snap(§ 격자 100mm 기본 + 벽 끝점) ----------------

  SsDrawPoint snap(SsDrawPoint p) {
    if (!snapEnabled) return p;
    SsDrawPoint? nearest;
    var nearestDist = _endpointSnapToleranceMm;
    for (final w in scene.walls) {
      for (final ep in [w.a, w.b]) {
        final d = p.distanceTo(ep);
        if (d < nearestDist) {
          nearestDist = d;
          nearest = ep;
        }
      }
    }
    if (nearest != null) return nearest;
    final gx = (p.xMm / gridMm).round() * gridMm;
    final gy = (p.yMm / gridMm).round() * gridMm;
    return SsDrawPoint(gx, gy);
  }

  // ---------------- 벽 그리기 ----------------

  void beginWallDraft(SsDrawPoint p) {
    wallDraftStart = snap(p);
    wallDraftEnd = wallDraftStart;
    notifyListeners();
  }

  void updateWallDraft(SsDrawPoint p) {
    if (wallDraftStart == null) return;
    wallDraftEnd = snap(p);
    notifyListeners();
  }

  void commitWallDraft({SsDrawWallType type = SsDrawWallType.interior}) {
    final start = wallDraftStart, end = wallDraftEnd;
    wallDraftStart = null;
    wallDraftEnd = null;
    if (start == null || end == null || start.distanceTo(end) < gridMm / 2) {
      notifyListeners();
      return;
    }
    history.push(scene.addWall(start, end, type: type), label: '벽 추가');
  }

  void cancelWallDraft() {
    wallDraftStart = null;
    wallDraftEnd = null;
    notifyListeners();
  }

  // ---------------- 선택 / 이동 / 삭제 / 수정 ----------------

  void selectAt(SsDrawPoint p) {
    SsDrawOpening? bestOpening;
    var bestOpeningDist = _hitToleranceMm;
    for (final o in scene.openings) {
      final w = scene.wall(o.wallId);
      if (w == null) continue;
      final d = p.distanceTo(w.pointAt(o.alongMm));
      if (d < bestOpeningDist) {
        bestOpeningDist = d;
        bestOpening = o;
      }
    }
    if (bestOpening != null) {
      selection = SsSelection(
        objectType: bestOpening.kind == SsDrawOpeningKind.door ? '문' : '창',
        objectId: '${bestOpening.id}',
        properties: {'widthMm': bestOpening.widthMm},
      );
      notifyListeners();
      return;
    }
    SsDrawWall? bestWall;
    var bestWallDist = _hitToleranceMm;
    for (final w in scene.walls) {
      final (_, dist) = w.project(p);
      if (dist < bestWallDist) {
        bestWallDist = dist;
        bestWall = w;
      }
    }
    selection = bestWall == null
        ? SsSelection.none
        : SsSelection(objectType: '벽', objectId: '${bestWall.id}', properties: {'lengthMm': bestWall.lengthMm, 'thicknessMm': bestWall.thicknessMm});
    notifyListeners();
  }

  void clearSelection() {
    if (selection.isEmpty) return;
    selection = SsSelection.none;
    notifyListeners();
  }

  void beginDrag() {
    if (selection.isEmpty) return;
    _dragBaseScene = scene;
  }

  void updateDrag(double dxMm, double dyMm) {
    final base = _dragBaseScene;
    if (base == null || selection.isEmpty) return;
    final id = int.tryParse(selection.objectId);
    if (id == null) return;
    if (selection.objectType == '벽') {
      final w = base.wall(id);
      if (w == null) return;
      final a = w.a.translated(dxMm, dyMm);
      final b = w.b.translated(dxMm, dyMm);
      _liveScene = base.updateWall(id, (w) => w.copyWith(a: a, b: b));
    } else {
      final o = base.opening(id);
      if (o == null) return;
      final wall = base.wall(o.wallId);
      if (wall == null) return;
      final moved = wall.pointAt(o.alongMm).translated(dxMm, dyMm);
      final (along, _) = wall.project(moved);
      final halfWidth = o.widthMm / 2;
      final maxAlong = wall.lengthMm - halfWidth;
      final clampedAlong = along.clamp(halfWidth, maxAlong < halfWidth ? halfWidth : maxAlong);
      _liveScene = base.updateOpening(id, (o) => o.copyWith(alongMm: clampedAlong));
    }
    notifyListeners();
  }

  void endDrag() {
    final live = _liveScene;
    final type = selection.objectType;
    _dragBaseScene = null;
    _liveScene = null;
    if (live != null) history.push(live, label: '$type 이동');
    notifyListeners();
  }

  /// 벽 위에 문/창을 놓는다. 가까운 벽이 없거나 벽이 너무 짧으면 아무 것도 하지 않고 false.
  bool addOpeningAt(SsDrawOpeningKind kind, SsDrawPoint p) {
    SsDrawWall? bestWall;
    var bestDist = _hitToleranceMm * 2;
    for (final w in scene.walls) {
      final (_, dist) = w.project(p);
      if (dist < bestDist) {
        bestDist = dist;
        bestWall = w;
      }
    }
    final wall = bestWall;
    if (wall == null) return false;
    final widthMm = kind == SsDrawOpeningKind.door ? 900.0 : 1200.0;
    final halfWidth = widthMm / 2;
    if (wall.lengthMm < widthMm) return false;
    final (rawAlong, _) = wall.project(p);
    final along = rawAlong.clamp(halfWidth, wall.lengthMm - halfWidth);
    history.push(scene.addOpening(wall.id, kind, along, widthMm: widthMm), label: kind == SsDrawOpeningKind.door ? '문 추가' : '창문 추가');
    return true;
  }

  void deleteSelected() {
    if (selection.isEmpty) return;
    final id = int.tryParse(selection.objectId);
    if (id == null) return;
    final removedType = selection.objectType;
    if (removedType == '벽') {
      history.push(scene.removeWall(id), label: '벽 삭제');
    } else {
      history.push(scene.removeOpening(id), label: '$removedType 삭제');
    }
    selection = SsSelection.none;
    notifyListeners();
  }

  // ---------------- 수정(속성 패널) ----------------

  void setWallType(int wallId, SsDrawWallType type) {
    history.push(scene.updateWall(wallId, (w) => w.copyWith(type: type)), label: '벽 종류 수정');
    _refreshSelection();
  }

  void setWallThicknessMm(int wallId, double thicknessMm) {
    history.push(scene.updateWall(wallId, (w) => w.copyWith(thicknessMm: thicknessMm)), label: '벽 두께 수정');
    _refreshSelection();
  }

  void setWallLengthMm(int wallId, double lengthMm) {
    final w = scene.wall(wallId);
    if (w == null || lengthMm <= 0) return;
    final len = w.lengthMm;
    if (len <= 0) return;
    final ux = (w.b.xMm - w.a.xMm) / len, uy = (w.b.yMm - w.a.yMm) / len;
    final newB = SsDrawPoint(w.a.xMm + ux * lengthMm, w.a.yMm + uy * lengthMm);
    history.push(scene.updateWall(wallId, (w) => w.copyWith(b: newB)), label: '벽 길이 수정');
    _refreshSelection();
  }

  void setOpeningWidthMm(int openingId, double widthMm) {
    history.push(scene.updateOpening(openingId, (o) => o.copyWith(widthMm: widthMm)), label: '개구부 폭 수정');
    _refreshSelection();
  }

  void _refreshSelection() {
    if (selection.isEmpty) return;
    final id = int.tryParse(selection.objectId);
    if (id == null) return;
    if (selection.objectType == '벽') {
      final w = scene.wall(id);
      selection = w == null
          ? SsSelection.none
          : SsSelection(objectType: '벽', objectId: '$id', properties: {'lengthMm': w.lengthMm, 'thicknessMm': w.thicknessMm});
    } else {
      final o = scene.opening(id);
      selection = o == null ? SsSelection.none : SsSelection(objectType: selection.objectType, objectId: '$id', properties: {'widthMm': o.widthMm});
    }
    notifyListeners();
  }

  // ---------------- Undo / Redo ----------------

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
