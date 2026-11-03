/// SS009 — MASTER UI 6(평면도 확인·보정)의 도구 상태 하나.
///
/// [SsDrawEditorController](SS005)/[SsPhotoEditorController](SS006)와 같은 기반을
/// 그대로 쓴다: Undo/Redo/History → [SsHistory]([SsReviewScene] 버전), 선택 표시 →
/// [SsSelection]. AI 인식 결과([SSSpatialModel], SS008 산출물)는 바꾸지 않고
/// 그대로 들고 있으며, 이 컨트롤러가 만드는 [SsReviewScene]을 겹쳐 최종 모델
/// ([effectiveModel])을 만든다 — 원본 AI 인식 결과와 항상 비교할 수 있다.
library;

import 'package:flutter/foundation.dart';

import '../models/floor_plan_geometry.dart';
import '../models/ss_review_scene.dart';
import '../models/ss_spatial_model.dart';
import 'ss_editing.dart';
import 'ss_history.dart';

/// MASTER UI 6 하단 도구모음(펜/형광펜/지우개/선택) + 보조 추가 도구(벽/문/창 추가,
/// "공간 인식 결과" 패널 헤더에 따로 둔다 — 하단 펜 계열 도구와 혼동을 줄인다).
enum SsReviewTool { select, pen, highlighter, eraser, addWall, addDoor, addWindow }

class SsReviewEditorController extends ChangeNotifier {
  SsReviewEditorController({required this.baseModel, SsReviewScene? initialScene})
      : history = SsHistory<SsReviewScene>(original: initialScene ?? SsReviewScene.empty, label: '시작') {
    history.addListener(notifyListeners);
  }

  /// SS008이 만든 AI 인식 결과 — 보정 레이어가 겹쳐지는 기준이며 이 컨트롤러는 바꾸지 않는다.
  final SSSpatialModel baseModel;

  final SsHistory<SsReviewScene> history;

  SsReviewTool tool = SsReviewTool.select;
  int colorValue = 0xFFEF4444; // 빨강 기본(MASTER UI 6 색상 스와치 첫 번째).
  double strokeWidth = 3;
  SsSelection selection = SsSelection.none;

  Point2? _addWallDraftStart;
  Point2? get addWallDraftStart => _addWallDraftStart;

  List<Point2>? _draftPoints;
  List<Point2>? get draftStrokePoints => _draftPoints;

  SsReviewScene? _liveScene;
  SsReviewScene? _eraseBaseScene;

  /// 지금 보여줄 보정 — 지우개로 지우는 중이면 아직 History에 쌓이지 않은 미리보기.
  SsReviewScene get scene => _liveScene ?? history.current;
  bool get canUndo => history.canUndo;
  bool get canRedo => history.canRedo;

  /// AI 인식 결과([baseModel])에 사용자 보정([scene])을 반영한 최종 모델 — CAD 변환
  /// 직전 확정에 쓰는 값과 같은 함수([applyReviewToSpatialModel])로 만든다.
  SSSpatialModel get effectiveModel => applyReviewToSpatialModel(baseModel, scene);

  // ---------------- 도구/색/굵기 ----------------

  void setTool(SsReviewTool t) {
    if (tool == t) return;
    tool = t;
    _addWallDraftStart = null;
    _draftPoints = null;
    if (t != SsReviewTool.select) selection = SsSelection.none;
    notifyListeners();
  }

  void setColor(int v) {
    colorValue = v;
    notifyListeners();
  }

  void setStrokeWidth(double v) {
    strokeWidth = v.clamp(1, 12);
    notifyListeners();
  }

  // ---------------- 캔버스 포인터(정규화 좌표 0.0~1.0) ----------------

  void pointerDown(Point2 p) {
    switch (tool) {
      case SsReviewTool.pen:
      case SsReviewTool.highlighter:
        _draftPoints = [p];
      case SsReviewTool.eraser:
        _eraseBaseScene = scene;
        _liveScene = scene.eraseNear(p);
      case SsReviewTool.select:
        selectAt(p);
        return; // selectAt이 이미 notifyListeners를 부른다.
      case SsReviewTool.addWall:
        final start = _addWallDraftStart;
        if (start == null) {
          _addWallDraftStart = p;
        } else {
          _addWallDraftStart = null;
          history.push(scene.addWallSegment(start, p), label: '벽 추가');
        }
      case SsReviewTool.addDoor:
        history.push(scene.addOpeningAt(SSOpeningKind.door, p), label: '문 추가');
      case SsReviewTool.addWindow:
        history.push(scene.addOpeningAt(SSOpeningKind.window, p), label: '창문 추가');
    }
    notifyListeners();
  }

  void pointerMove(Point2 p) {
    switch (tool) {
      case SsReviewTool.pen:
      case SsReviewTool.highlighter:
        if (_draftPoints == null) return;
        _draftPoints = [..._draftPoints!, p];
        notifyListeners();
      case SsReviewTool.eraser:
        if (_eraseBaseScene == null) return;
        _liveScene = (_liveScene ?? _eraseBaseScene!).eraseNear(p);
        notifyListeners();
      case SsReviewTool.select:
      case SsReviewTool.addWall:
      case SsReviewTool.addDoor:
      case SsReviewTool.addWindow:
        break;
    }
  }

  void pointerUp() {
    switch (tool) {
      case SsReviewTool.pen:
      case SsReviewTool.highlighter:
        final pts = _draftPoints;
        _draftPoints = null;
        if (pts != null && pts.length >= 2) {
          final annotationTool = tool == SsReviewTool.pen ? SsAnnotationTool.pen : SsAnnotationTool.highlighter;
          history.push(
            scene.addStroke(annotationTool, colorValue: colorValue, strokeWidth: strokeWidth, points: pts),
            label: tool == SsReviewTool.pen ? '펜 표시' : '형광펜 표시',
          );
        }
      case SsReviewTool.eraser:
        final live = _liveScene;
        _eraseBaseScene = null;
        _liveScene = null;
        if (live != null && live != history.current) history.push(live, label: '지우개로 표시 지움');
      case SsReviewTool.select:
      case SsReviewTool.addWall:
      case SsReviewTool.addDoor:
      case SsReviewTool.addWindow:
        break;
    }
    notifyListeners();
  }

  // ---------------- 선택 / 의미 수정 / 삭제 ----------------

  void selectAt(Point2 p) {
    final model = effectiveModel;
    const tol = 0.03;

    SSOpening? bestOpening;
    var bestOpeningDist = tol;
    for (final o in model.openings) {
      final d = o.center.distanceTo(p);
      if (d < bestOpeningDist) {
        bestOpeningDist = d;
        bestOpening = o;
      }
    }
    if (bestOpening != null) {
      selection = SsSelection(
        objectType: bestOpening.kind == SSOpeningKind.window ? '창' : '문',
        objectId: bestOpening.id,
        properties: {'신뢰도': '${(bestOpening.confidence * 100).round()}%'},
      );
      notifyListeners();
      return;
    }

    SSWall? bestWall;
    var bestWallDist = tol;
    for (final w in model.walls) {
      final d = _distanceToSegment(p, w.start, w.end);
      if (d < bestWallDist) {
        bestWallDist = d;
        bestWall = w;
      }
    }
    if (bestWall != null) {
      selection = SsSelection(objectType: '벽', objectId: bestWall.id, properties: {'신뢰도': '${(bestWall.confidence * 100).round()}%'});
      notifyListeners();
      return;
    }

    for (final o in model.objects) {
      if (o.polygon.length >= 3 && _pointInPolygon(p, o.polygon)) {
        selection = SsSelection(objectType: '가구/설비', objectId: o.id, properties: const {});
        notifyListeners();
        return;
      }
    }

    selection = SsSelection.none;
    notifyListeners();
  }

  void clearSelection() {
    if (selection.isEmpty) return;
    selection = SsSelection.none;
    notifyListeners();
  }

  /// 객체 의미 수정 — 선택한 개구부를 문↔창으로 바꾼다.
  void setSelectedOpeningKind(SSOpeningKind kind) {
    if (selection.isEmpty || (selection.objectType != '문' && selection.objectType != '창')) return;
    history.push(scene.setOpeningKind(selection.objectId, kind), label: '${kind == SSOpeningKind.window ? '창' : '문'}(으)로 수정');
    selection = SsSelection(objectType: kind == SSOpeningKind.window ? '창' : '문', objectId: selection.objectId, properties: selection.properties);
    notifyListeners();
  }

  void deleteSelected() {
    if (selection.isEmpty) return;
    final id = selection.objectId;
    switch (selection.objectType) {
      case '벽':
        history.push(scene.removeWallById(id), label: '벽 삭제');
      case '문':
      case '창':
        history.push(scene.removeOpeningById(id), label: '${selection.objectType} 삭제');
      case '가구/설비':
        history.push(scene.removeObjectById(id), label: '가구/설비 삭제');
    }
    selection = SsSelection.none;
    notifyListeners();
  }

  /// "확인 필요" 표시가 남은 선택 요소를 확인했다고 표시한다.
  void markSelectedResolved() {
    if (selection.isEmpty) return;
    markResolvedById(selection.objectId);
  }

  void markResolvedById(String id) {
    history.push(scene.markResolved(id), label: '확인 완료');
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

double _distanceToSegment(Point2 p, Point2 a, Point2 b) {
  final abx = b.x - a.x, aby = b.y - a.y;
  final lenSq = abx * abx + aby * aby;
  if (lenSq <= 0) return p.distanceTo(a);
  final t = (((p.x - a.x) * abx + (p.y - a.y) * aby) / lenSq).clamp(0.0, 1.0);
  final proj = Point2(a.x + t * abx, a.y + t * aby);
  return p.distanceTo(proj);
}

bool _pointInPolygon(Point2 p, List<Point2> polygon) {
  var inside = false;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final a = polygon[i];
    final b = polygon[j];
    final intersects = ((a.y > p.y) != (b.y > p.y)) && (p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x);
    if (intersects) inside = !inside;
  }
  return inside;
}
