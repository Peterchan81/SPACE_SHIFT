import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/floor_plan_geometry.dart';
import '../../models/workspace_drawing_entity.dart';
import '../../models/workspace_task_item.dart';
import '../../models/workspace_viewport_transform.dart';
import 'floor_plan_analysis_overlay.dart' show ContainFitTransform;

/// WO089 CORE EDITING — 도구별로 정확히 하나의 통합 gesture 아키텍처만
/// 쓴다(§28 "하나의 일관된 input architecture로 해결한다"). `onScale*`
/// 콜백 하나만 쓰고 `onTap*`은 절대 같이 쓰지 않는다 — Flutter의
/// TapGestureRecognizer와 ScaleGestureRecognizer를 한 GestureDetector에
/// 같이 걸면 tap이 씹히는 경우가 실측으로 알려져 있어(최소 이동만
/// 있어도 scale이 먼저 이김), "탭처럼 보이는 제스처"를 onScaleEnd에서
/// 이동 거리로 직접 판정한다. `ScaleUpdateDetails.pointerCount`가
/// 2 이상이면(핀치) 도구와 무관하게 항상 viewport pan/zoom으로
/// 처리한다 — 그 외 1개 포인터일 때만 현재 도구에 따라 분기한다.
class WorkspaceDrawingLayer extends StatefulWidget {
  const WorkspaceDrawingLayer({
    super.key,
    required this.tool,
    required this.drawings,
    required this.selectedDrawingId,
    required this.viewport,
    required this.documentSize,
    required this.onCreateDrawing,
    required this.onSelectDrawing,
    required this.onViewportChanged,
    this.onCanvasSizeChanged,
    this.onSelectTapMiss,
  });

  final WorkspaceSelectionTool tool;
  final List<WorkspaceDrawingEntity> drawings;
  final int? selectedDrawingId;
  final WorkspaceViewportTransform viewport;

  /// 평면도 이미지의 실제 픽셀 크기 — [ContainFitTransform]이 이 크기를
  /// 기준으로 contain-fit 영역을 계산한다. 평면도가 아직 없으면(§19
  /// blank workspace) 캔버스 크기 그대로를 넘겨 1:1 매핑되게 한다.
  final Size documentSize;

  /// 새 도형이 완성됐을 때 호출된다. 넘어오는 [WorkspaceDrawingEntity.id]는
  /// 항상 0(placeholder)이다 — 실제 고유 id는 호출부(부모, undo/redo
  /// 이력을 갖고 있는 쪽)가 부여해야 하므로, 이 위젯은 id 발급에 관여하지
  /// 않는다.
  final ValueChanged<WorkspaceDrawingEntity> onCreateDrawing;
  final ValueChanged<int?> onSelectDrawing;
  final ValueChanged<WorkspaceViewportTransform> onViewportChanged;

  /// §13 확대/축소 버튼이 실제 캔버스 중심을 기준으로 zoom할 수 있도록,
  /// 이 레이어가 실측한 크기를 부모에게 보고한다(선택적 — 버튼 zoom을
  /// 쓰지 않는 호출부는 생략 가능).
  final ValueChanged<Size>? onCanvasSizeChanged;

  /// WO089 CORE EDITING — "선택" 도구로 탭했지만 이 레이어의 [drawings]
  /// 중 어떤 것도 맞지 않았을 때 호출된다(문서 좌표, null이면 화면
  /// 밖/변환 불가). 이 레이어가 [WorkspaceCanvas]에서 기존
  /// CadFloorPlanOverlay 위에 얹혀 모든 탭을 먼저 받기 때문에, 자기
  /// 도형에 없으면 이 콜백으로 부모에게 넘겨 기존 CAD 벽/문·창/공간
  /// 탭 선택이 계속 동작하게 한다(생략하면 아무 것도 못 찾았을 때
  /// 그냥 무시된다).
  final ValueChanged<Point2?>? onSelectTapMiss;

  @override
  State<WorkspaceDrawingLayer> createState() => _WorkspaceDrawingLayerState();
}

/// 화면(손가락) 기준 히트 테스트/드래그 판정 최소 이동량(논리 픽셀) —
/// 이보다 적게 움직였으면 "탭"으로 취급한다.
const double _tapSlopPx = 8.0;

/// 화면 기준 히트 테스트 허용 두께(논리 픽셀) — 확대 배율과 무관하게
/// 항상 같은 손가락 굵기로 느껴지도록, 실제 판정 시 현재 배율로 나눠
/// 문서 좌표 허용치로 변환한다.
const double _hitTestPx = 16.0;

class _WorkspaceDrawingLayerState extends State<WorkspaceDrawingLayer> {
  WorkspaceViewportTransform? _gestureStartViewport;
  Offset? _gestureStartFocalScreen;
  Offset? _lastFocalScreen;

  // line/circle 드래그 미리보기.
  Point2? _dragStartDoc;
  Point2? _dragCurrentDoc;

  // freeRegion 드래그 누적.
  final List<Point2> _freeRegionPoints = [];

  // curve 3-tap 누적(start/control/end) — 별도 드래그 제스처들 사이에도
  // 유지된다(3번의 개별 탭으로 완성).
  final List<Point2> _curveStagePoints = [];
  Point2? _curveLivePreviewDoc;

  ContainFitTransform get _fit => ContainFitTransform.compute(
    _lastConstraints ?? const Size(1, 1),
    widget.documentSize,
  );

  Size? _lastConstraints;

  Point2? _screenToDocument(Offset screenLocal) {
    final fitted = widget.viewport.invert(screenLocal);
    return _fit.inverse(fitted);
  }

  Offset _documentToScreen(Point2 doc) {
    final fitted = _fit.mapNormalized(doc);
    return widget.viewport.apply(fitted);
  }

  /// 현재 배율(fit rect 폭 x viewport scale) 기준으로, 화면상
  /// [_hitTestPx]가 문서 좌표로 몇인지 역산한다.
  double get _hitToleranceNormalized {
    final effectiveWidthPx = _fit.rect.width * widget.viewport.scale;
    if (effectiveWidthPx <= 0) return 0.05;
    return _hitTestPx / effectiveWidthPx;
  }

  void _resetDragState() {
    _dragStartDoc = null;
    _dragCurrentDoc = null;
    _freeRegionPoints.clear();
  }

  void _onScaleStart(ScaleStartDetails details) {
    _gestureStartViewport = widget.viewport;
    _gestureStartFocalScreen = details.localFocalPoint;
    _lastFocalScreen = details.localFocalPoint;

    if (details.pointerCount >= 2 ||
        widget.tool == WorkspaceSelectionTool.move) {
      return; // pan/zoom은 update에서 처리.
    }

    final doc = _screenToDocument(details.localFocalPoint);
    if (doc == null) return;

    switch (widget.tool) {
      case WorkspaceSelectionTool.line:
      case WorkspaceSelectionTool.circle:
        setState(() {
          _dragStartDoc = doc;
          _dragCurrentDoc = doc;
        });
      case WorkspaceSelectionTool.freeform:
        setState(() {
          _freeRegionPoints
            ..clear()
            ..add(doc);
        });
      case WorkspaceSelectionTool.curve:
      case WorkspaceSelectionTool.select:
      case WorkspaceSelectionTool.move:
      case WorkspaceSelectionTool.zoomIn:
      case WorkspaceSelectionTool.zoomOut:
      case WorkspaceSelectionTool.erase:
        break;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final isPan =
        details.pointerCount >= 2 || widget.tool == WorkspaceSelectionTool.move;
    if (isPan) {
      final startViewport = _gestureStartViewport;
      final startFocal = _gestureStartFocalScreen;
      if (startViewport == null || startFocal == null) return;
      final fittedFocalAtStart = startViewport.invert(startFocal);
      final newScale = (startViewport.scale * details.scale).clamp(
        WorkspaceViewportTransform.minScale,
        WorkspaceViewportTransform.maxScale,
      );
      final newOffset = details.localFocalPoint - fittedFocalAtStart * newScale;
      widget.onViewportChanged(
        WorkspaceViewportTransform(scale: newScale, offset: newOffset),
      );
      _lastFocalScreen = details.localFocalPoint;
      return;
    }

    _lastFocalScreen = details.localFocalPoint;
    final doc = _screenToDocument(details.localFocalPoint);
    if (doc == null) return;

    switch (widget.tool) {
      case WorkspaceSelectionTool.line:
      case WorkspaceSelectionTool.circle:
        setState(() => _dragCurrentDoc = doc);
      case WorkspaceSelectionTool.freeform:
        if (_freeRegionPoints.isEmpty ||
            _distance(_freeRegionPoints.last, doc) > 0.006) {
          setState(() => _freeRegionPoints.add(doc));
        }
      case WorkspaceSelectionTool.curve:
        setState(() => _curveLivePreviewDoc = doc);
      case WorkspaceSelectionTool.select:
      case WorkspaceSelectionTool.move:
      case WorkspaceSelectionTool.zoomIn:
      case WorkspaceSelectionTool.zoomOut:
      case WorkspaceSelectionTool.erase:
        break;
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    final startFocal = _gestureStartFocalScreen;
    final lastFocal = _lastFocalScreen;
    final wasTap =
        startFocal != null &&
        lastFocal != null &&
        (startFocal - lastFocal).distance <= _tapSlopPx;

    switch (widget.tool) {
      case WorkspaceSelectionTool.select:
        if (wasTap) {
          final doc = _screenToDocument(startFocal);
          _handleSelectTap(doc);
        }
      case WorkspaceSelectionTool.line:
        _commitLineOrCircle(WorkspaceDrawingType.line);
      case WorkspaceSelectionTool.circle:
        _commitLineOrCircle(WorkspaceDrawingType.circle);
      case WorkspaceSelectionTool.freeform:
        _commitFreeRegion();
      case WorkspaceSelectionTool.curve:
        if (wasTap) {
          _handleCurveTap(_screenToDocument(startFocal));
        }
      case WorkspaceSelectionTool.move:
      case WorkspaceSelectionTool.zoomIn:
      case WorkspaceSelectionTool.zoomOut:
      case WorkspaceSelectionTool.erase:
        break;
    }

    _gestureStartViewport = null;
    _gestureStartFocalScreen = null;
    _lastFocalScreen = null;
  }

  void _handleSelectTap(Point2? doc) {
    if (doc == null) {
      widget.onSelectDrawing(null);
      widget.onSelectTapMiss?.call(null);
      return;
    }
    final tol = _hitToleranceNormalized;
    for (final d in widget.drawings.reversed) {
      if (d.visible && d.hitTest(doc, toleranceNormalized: tol)) {
        widget.onSelectDrawing(d.id);
        return;
      }
    }
    widget.onSelectDrawing(null);
    widget.onSelectTapMiss?.call(doc);
  }

  void _commitLineOrCircle(WorkspaceDrawingType type) {
    final start = _dragStartDoc;
    final end = _dragCurrentDoc;
    _resetDragState();
    if (start == null || end == null) {
      setState(() {});
      return;
    }
    if (_distance(start, end) < 0.01) {
      // 너무 짧으면(사실상 탭) 의미 없는 점 도형을 만들지 않는다.
      setState(() {});
      return;
    }
    widget.onCreateDrawing(
      WorkspaceDrawingEntity(
        id: 0, // placeholder — 부모가 실제 id를 부여한다.
        type: type,
        points: [start, end],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    setState(() {});
  }

  void _commitFreeRegion() {
    final points = List<Point2>.of(_freeRegionPoints);
    _resetDragState();
    if (points.length < 2) {
      setState(() {});
      return;
    }
    widget.onCreateDrawing(
      WorkspaceDrawingEntity(
        id: 0,
        type: WorkspaceDrawingType.freeRegion,
        points: points,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    setState(() {});
  }

  void _handleCurveTap(Point2? doc) {
    if (doc == null) return;
    setState(() {
      _curveStagePoints.add(doc);
      if (_curveStagePoints.length == 3) {
        widget.onCreateDrawing(
          WorkspaceDrawingEntity(
            id: 0,
            type: WorkspaceDrawingType.curve,
            points: List.of(_curveStagePoints),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
        _curveStagePoints.clear();
        _curveLivePreviewDoc = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (_lastConstraints != size) {
          _lastConstraints = size;
          final onCanvasSizeChanged = widget.onCanvasSizeChanged;
          if (onCanvasSizeChanged != null) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => onCanvasSizeChanged(size),
            );
          }
        }
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          onScaleEnd: _onScaleEnd,
          child: CustomPaint(
            painter: _WorkspaceDrawingPainter(
              drawings: widget.drawings,
              selectedDrawingId: widget.selectedDrawingId,
              documentToScreen: _documentToScreen,
              previewLine:
                  widget.tool == WorkspaceSelectionTool.line &&
                      _dragStartDoc != null &&
                      _dragCurrentDoc != null
                  ? (_dragStartDoc!, _dragCurrentDoc!)
                  : null,
              previewCircle:
                  widget.tool == WorkspaceSelectionTool.circle &&
                      _dragStartDoc != null &&
                      _dragCurrentDoc != null
                  ? (_dragStartDoc!, _dragCurrentDoc!)
                  : null,
              previewFreeRegion:
                  widget.tool == WorkspaceSelectionTool.freeform &&
                      _freeRegionPoints.length >= 2
                  ? List.of(_freeRegionPoints)
                  : null,
              curveStagePoints: widget.tool == WorkspaceSelectionTool.curve
                  ? List.of(_curveStagePoints)
                  : const [],
              curveLivePreview: widget.tool == WorkspaceSelectionTool.curve
                  ? _curveLivePreviewDoc
                  : null,
            ),
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }
}

double _distance(Point2 a, Point2 b) {
  final dx = a.x - b.x;
  final dy = a.y - b.y;
  return math.sqrt(dx * dx + dy * dy);
}

class _WorkspaceDrawingPainter extends CustomPainter {
  _WorkspaceDrawingPainter({
    required this.drawings,
    required this.selectedDrawingId,
    required this.documentToScreen,
    this.previewLine,
    this.previewCircle,
    this.previewFreeRegion,
    this.curveStagePoints = const [],
    this.curveLivePreview,
  });

  final List<WorkspaceDrawingEntity> drawings;
  final int? selectedDrawingId;
  final Offset Function(Point2) documentToScreen;
  final (Point2, Point2)? previewLine;
  final (Point2, Point2)? previewCircle;
  final List<Point2>? previewFreeRegion;
  final List<Point2> curveStagePoints;
  final Point2? curveLivePreview;

  static const Color _normalColor = Color(0xFF2563EB);
  static const Color _selectedColor = Color(0xFFF97316);
  static const Color _previewColor = Color(0x992563EB);

  @override
  void paint(Canvas canvas, Size size) {
    for (final d in drawings) {
      if (!d.visible) continue;
      final color = d.id == selectedDrawingId ? _selectedColor : _normalColor;
      final strokeWidth = d.id == selectedDrawingId ? 3.0 : 2.0;
      _paintEntity(canvas, d.type, d.points, color, strokeWidth);
    }

    if (previewLine != null) {
      _paintEntity(
        canvas,
        WorkspaceDrawingType.line,
        [previewLine!.$1, previewLine!.$2],
        _previewColor,
        2,
      );
    }
    if (previewCircle != null) {
      _paintEntity(
        canvas,
        WorkspaceDrawingType.circle,
        [previewCircle!.$1, previewCircle!.$2],
        _previewColor,
        2,
      );
    }
    if (previewFreeRegion != null) {
      _paintEntity(
        canvas,
        WorkspaceDrawingType.freeRegion,
        previewFreeRegion!,
        _previewColor,
        2,
      );
    }
    if (curveStagePoints.isNotEmpty) {
      final pts = [...curveStagePoints, ?curveLivePreview];
      final path = Path()
        ..moveTo(
          documentToScreen(pts.first).dx,
          documentToScreen(pts.first).dy,
        );
      for (final p in pts.skip(1)) {
        final s = documentToScreen(p);
        path.lineTo(s.dx, s.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = _previewColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      for (final p in curveStagePoints) {
        canvas.drawCircle(
          documentToScreen(p),
          4,
          Paint()..color = _previewColor,
        );
      }
    }
  }

  void _paintEntity(
    Canvas canvas,
    WorkspaceDrawingType type,
    List<Point2> points,
    Color color,
    double strokeWidth,
  ) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    switch (type) {
      case WorkspaceDrawingType.line:
        if (points.length < 2) return;
        canvas.drawLine(
          documentToScreen(points[0]),
          documentToScreen(points[1]),
          paint,
        );
      case WorkspaceDrawingType.curve:
        if (points.length < 3) return;
        final start = documentToScreen(points[0]);
        final control = documentToScreen(points[1]);
        final end = documentToScreen(points[2]);
        final path = Path()
          ..moveTo(start.dx, start.dy)
          ..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
        canvas.drawPath(path, paint);
      case WorkspaceDrawingType.circle:
        if (points.length < 2) return;
        final center = documentToScreen(points[0]);
        final edge = documentToScreen(points[1]);
        final radius = (edge - center).distance;
        canvas.drawCircle(center, radius, paint);
      case WorkspaceDrawingType.freeRegion:
        if (points.length < 2) return;
        final path = Path()
          ..moveTo(
            documentToScreen(points[0]).dx,
            documentToScreen(points[0]).dy,
          );
        for (final p in points.skip(1)) {
          final s = documentToScreen(p);
          path.lineTo(s.dx, s.dy);
        }
        if (points.length >= 3) path.close();
        canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WorkspaceDrawingPainter oldDelegate) => true;
}
