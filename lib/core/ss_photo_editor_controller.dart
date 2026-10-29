/// SS006 — MASTER UI 4-2(실제 공간 이미지 AI 디자인 에디터)의 도구 상태 하나.
///
/// [DirectDrawScreen]/[SsDrawEditorController](SS005)와 같은 기반을 그대로 쓴다:
/// - Undo/Redo/History → [SsHistory]([SsPhotoScene] 버전).
/// - 선택 표시 → [SsSelection](ss_editing.dart) — 선택한 객체명/속성을 그대로 요약해 보여준다(§ 3초 법칙).
///
/// 실제 AI 재생성(배경 복원·재질 변경 결과 픽셀)은 SS007이 한다 — 여기서는 "무엇을 바꿀지" 편집 지시를
/// 만들고 Undo/Redo로 되돌릴 수 있게 하는 것까지가 범위다(§ 구현 범위). 화면 Pan/Zoom/Pinch Zoom은
/// 화면(PhotoDesignEditorScreen)이 Flutter 표준 InteractiveViewer로 처리하므로 이 컨트롤러는 다루지 않는다.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Offset;

import '../models/ss_photo_scene.dart';
import 'ss_editing.dart';
import 'ss_history.dart';

/// 상단 도구모음의 도구(MASTER UI 4-2 기준: 선택/이동/지우기/복원/재질변경/색상변경/구멍뚫기/가구추가).
enum SsPhotoTool { select, move, erase, restore, retexture, colorChange, opening, furnitureAdd }

class SsPhotoEditorController extends ChangeNotifier {
  SsPhotoEditorController({required SsPhotoScene initialScene}) : history = SsHistory<SsPhotoScene>(original: initialScene, label: '원본') {
    history.addListener(notifyListeners);
  }

  /// Undo/Redo/History(§7) — 화면이 커밋 단위 변경(자동저장용)을 들으려면 이 객체를 직접 구독한다.
  final SsHistory<SsPhotoScene> history;

  SsPhotoTool tool = SsPhotoTool.select;
  SsSelection selection = SsSelection.none;

  /// Before/After(§ 원본↔현재 비교) — true이면 편집 오버레이를 숨기고 원본 그대로를 보여준다.
  bool showOriginal = false;

  SsPhotoScene? _liveScene;
  SsPhotoScene? _dragBaseScene;

  /// 지금 보여줄 장면 — 드래그 중이면 아직 History에 쌓이지 않은 미리보기.
  SsPhotoScene get scene => _liveScene ?? history.current;
  bool get canUndo => history.canUndo;
  bool get canRedo => history.canRedo;
  bool get isDragging => _dragBaseScene != null;

  // ---------------- 도구 ----------------

  void setTool(SsPhotoTool t) {
    if (tool == t) return;
    tool = t;
    if (t != SsPhotoTool.select && t != SsPhotoTool.move) selection = SsSelection.none;
    notifyListeners();
  }

  void toggleBeforeAfter() {
    showOriginal = !showOriginal;
    notifyListeners();
  }

  // ---------------- 선택 ----------------

  /// [p]는 사진 위 정규화 좌표(0.0~1.0). 보이는 객체 중 포함하는 것을 고른다(나중에 추가한 것이 위에 있다고 본다).
  void selectAt(Offset p) {
    for (final o in scene.visibleObjects.reversed) {
      if (p.dx >= o.x && p.dx <= o.x + o.width && p.dy >= o.y && p.dy <= o.y + o.height) {
        selection = SsSelection(objectType: o.category.label, objectId: '${o.id}', properties: {'이름': o.name});
        notifyListeners();
        return;
      }
    }
    clearSelection();
  }

  void clearSelection() {
    if (selection.isEmpty) return;
    selection = SsSelection.none;
    notifyListeners();
  }

  int? get _selectedObjectId => selection.isEmpty ? null : int.tryParse(selection.objectId);

  // ---------------- 삭제 / AI 배경 복원 / 복원 / 재생성 요청 ----------------

  /// 선택한 객체를 지운다(픽셀은 SS007에서 — 여기선 "삭제 지시"만 남긴다). [aiRestoreBackground]가
  /// true이면(MASTER UI 토글 기본값) 빈 자리를 AI로 자연스럽게 복원하라는 지시도 함께 남긴다.
  void deleteSelected({bool aiRestoreBackground = true}) {
    final id = _selectedObjectId;
    if (id == null) return;
    final obj = scene.object(id);
    if (obj == null) return;
    history.push(scene.updateObject(id, (o) => o.copyWith(removed: true, aiRestoreBackground: aiRestoreBackground)), label: '${obj.name} 삭제');
    selection = SsSelection.none;
    notifyListeners();
  }

  /// id로 바로 되살린다(삭제된 객체는 선택 대상이 아니므로 목록에서 바로 부를 때 쓴다).
  void restoreObjectById(int id) {
    final obj = scene.object(id);
    if (obj == null || !obj.removed) return;
    history.push(scene.updateObject(id, (o) => o.copyWith(removed: false)), label: '${obj.name} 복원');
    notifyListeners();
  }

  /// 선택된 객체가 있으면 그것을, 없으면 가장 최근 삭제한 객체를 되살린다(MASTER UI 상단 "복원" 도구).
  void restoreSelected() {
    final id = _selectedObjectId;
    if (id != null) {
      restoreObjectById(id);
      return;
    }
    final removed = scene.removedObjects;
    if (removed.isEmpty) return;
    restoreObjectById(removed.last.id);
  }

  /// "AI가 잘못 수정한 경우 영역 재선택 및 재생성"(§ 구현 범위) — 선택한 객체를 다시 만들어 달라고
  /// 표시한다. 실제 재생성은 SS007이 하고, 여기서는 History에 지시를 남긴다.
  void requestRegenerate() {
    final id = _selectedObjectId;
    if (id == null) return;
    final obj = scene.object(id);
    if (obj == null) return;
    history.push(scene.updateObject(id, (o) => o.copyWith(pendingRegenerate: true)), label: '${obj.name} 재생성 요청');
    notifyListeners();
  }

  // ---------------- 이동 ----------------

  void beginDrag() {
    if (selection.isEmpty) return;
    _dragBaseScene = scene;
  }

  /// [dx]/[dy]는 드래그 시작점부터의 누적 변위(정규화, 0.0~1.0 기준) — [beginDrag] 때의 장면을 기준으로 적용한다.
  void updateDrag(double dx, double dy) {
    final base = _dragBaseScene;
    final id = _selectedObjectId;
    if (base == null || id == null) return;
    final o = base.object(id);
    if (o == null) return;
    final nx = (o.x + dx).clamp(0.0, 1.0 - o.width);
    final ny = (o.y + dy).clamp(0.0, 1.0 - o.height);
    _liveScene = base.updateObject(id, (o) => o.copyWith(x: nx, y: ny));
    notifyListeners();
  }

  void endDrag() {
    final live = _liveScene;
    final id = _selectedObjectId;
    _dragBaseScene = null;
    _liveScene = null;
    if (live != null) {
      final name = id == null ? null : live.object(id)?.name;
      history.push(live, label: name == null ? '객체 이동' : '$name 이동');
    }
    notifyListeners();
  }

  // ---------------- 가구 추가/교체 ----------------

  void addFurnitureAt(Offset p, {required String name, SsPhotoObjectCategory category = SsPhotoObjectCategory.furniture}) {
    const w = 0.18, h = 0.18;
    final x = (p.dx - w / 2).clamp(0.0, 1.0 - w);
    final y = (p.dy - h / 2).clamp(0.0, 1.0 - h);
    history.push(scene.addObject(name: name, category: category, x: x, y: y, width: w, height: h), label: '$name 추가');
  }

  /// 선택한 가구를 다른 가구로 교체(위치/크기는 유지, 이름만 바뀌고 재생성 대기 상태가 된다).
  void replaceSelectedFurniture(String newName) {
    final id = _selectedObjectId;
    if (id == null) return;
    final obj = scene.object(id);
    if (obj == null) return;
    history.push(scene.updateObject(id, (o) => o.copyWith(name: newName, removed: false, pendingRegenerate: true)), label: '$newName(으)로 교체');
  }

  // ---------------- 재질/색상 ----------------

  void setFinish(SsPhotoSurface surface, {required String swatchId, required int colorValue}) {
    history.push(scene.setFinish(surface, swatchId: swatchId, colorValue: colorValue), label: '${surface.label} 재질 변경');
  }

  // ---------------- 조명 ----------------

  void setLighting(SsPhotoLighting lighting) {
    history.push(scene.setLighting(lighting), label: '조명 변경(${lighting.label})');
  }

  // ---------------- 개구부 ----------------

  void addOpeningAt(SsPhotoOpeningKind kind, Offset p) {
    const w = 0.12, h = 0.16;
    final x = (p.dx - w / 2).clamp(0.0, 1.0 - w);
    final y = (p.dy - h / 2).clamp(0.0, 1.0 - h);
    history.push(scene.addOpening(kind, x: x, y: y, width: w, height: h), label: '${kind.label} 추가');
  }

  void removeOpening(int id) {
    final o = scene.opening(id);
    if (o == null) return;
    history.push(scene.removeOpening(id), label: '${o.kind.label} 삭제');
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
