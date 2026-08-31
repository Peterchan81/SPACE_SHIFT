import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/space_task.dart';

enum _DragMode { none, drawing, moving, resizeTL, resizeTR, resizeBL, resizeBR }

/// 공간 작업실의 사진 Canvas.
///
/// 사용자가 손가락 또는 S-Pen으로 사진 위를 드래그해 새 영역을 그리거나
/// (Drag), 이미 그려둔 영역의 몸통을 눌러 옮기거나(이동) 모서리 손잡이를
/// 눌러 크기를 바꿀 수 있다(크기 변경). 등록된 작업들의 영역은 반투명
/// Overlay로 항상 표시되며, 눌러서(Tap) 다시 선택할 수 있다.
///
/// 모든 좌표는 이 위젯의 표시 영역을 기준으로 0.0~1.0 사이로 정규화되어
/// [onEditingRectChanged]를 통해 오간다.
class SpaceCanvas extends StatefulWidget {
  const SpaceCanvas({
    super.key,
    required this.imageBytes,
    required this.tasks,
    required this.editingRect,
    required this.onEditingRectChanged,
    this.activeTaskId,
    this.onTaskTap,
  });

  /// 작업 Canvas로 사용하는 원본 공간 사진.
  final Uint8List imageBytes;

  /// 이미 등록된 작업 목록. 각 작업의 [SpaceTask.rect]를 Overlay로 표시한다.
  final List<SpaceTask> tasks;

  /// 현재 그리는 중이거나 재선택 중인 영역. 없으면 null.
  final NormalizedRect? editingRect;

  /// [editingRect]가 바뀔 때마다 호출된다. 영역 취소 시 null이 전달된다.
  final ValueChanged<NormalizedRect?> onEditingRectChanged;

  /// [editingRect]가 이미 등록된 작업을 재선택한 것이라면 그 작업의 id.
  final String? activeTaskId;

  /// 등록된 작업 영역을 탭했을 때 호출된다.
  final ValueChanged<String>? onTaskTap;

  @override
  State<SpaceCanvas> createState() => _SpaceCanvasState();
}

class _SpaceCanvasState extends State<SpaceCanvas> {
  static const double _minSize = 0.04;
  static const double _handleTouchRadius = 24;

  _DragMode _mode = _DragMode.none;
  Offset? _dragStartLocal;
  NormalizedRect? _dragStartRect;
  Size _boxSize = Size.zero;

  NormalizedRect _clampRect(NormalizedRect rect) {
    final width = rect.width.clamp(_minSize, 1.0);
    final height = rect.height.clamp(_minSize, 1.0);
    final left = rect.left.clamp(0.0, 1.0 - width);
    final top = rect.top.clamp(0.0, 1.0 - height);
    return NormalizedRect(left: left, top: top, width: width, height: height);
  }

  Offset _toNormalized(Offset local) {
    if (_boxSize.width == 0 || _boxSize.height == 0) return Offset.zero;
    return Offset(
      (local.dx / _boxSize.width).clamp(0.0, 1.0),
      (local.dy / _boxSize.height).clamp(0.0, 1.0),
    );
  }

  Offset _handleCenter(NormalizedRect rect, _DragMode corner) {
    switch (corner) {
      case _DragMode.resizeTL:
        return Offset(rect.left * _boxSize.width, rect.top * _boxSize.height);
      case _DragMode.resizeTR:
        return Offset(rect.right * _boxSize.width, rect.top * _boxSize.height);
      case _DragMode.resizeBL:
        return Offset(
          rect.left * _boxSize.width,
          rect.bottom * _boxSize.height,
        );
      case _DragMode.resizeBR:
        return Offset(
          rect.right * _boxSize.width,
          rect.bottom * _boxSize.height,
        );
      case _DragMode.moving:
      case _DragMode.drawing:
      case _DragMode.none:
        return Offset.zero;
    }
  }

  // 이 캔버스는 SingleChildScrollView 안에 놓인다. 세로 성분이 섞인 드래그를
  // GestureDetector.onPan*(제스처 아레나 기반)으로 처리하면 조상 스크롤
  // 위젯의 세로 드래그 인식기와 아레나에서 경쟁하다가 스크롤 쪽이 이겨
  // onPanStart 자체가 호출되지 않는 경우가 있다(특히 대각선 드래그).
  // Listener의 raw pointer 콜백은 아레나에 참여하지 않고 즉시 전달되므로
  // 이 문제를 근본적으로 피할 수 있다. 대신 Tap과 Drag 구분은 여기서 직접
  // 이동 거리(_tapSlop)로 판정한다.
  static const double _tapSlop = 8.0;

  Offset? _pointerDownLocal;
  _DragMode? _pendingMode;
  bool _dragCommitted = false;

  void _handleTapUpAt(Offset local) {
    final normalized = _toNormalized(local);
    for (final task in widget.tasks.reversed) {
      if (task.rect.contains(normalized.dx, normalized.dy)) {
        widget.onTaskTap?.call(task.id);
        return;
      }
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    final local = event.localPosition;
    final rect = widget.editingRect;

    _pointerDownLocal = local;
    _dragCommitted = false;

    if (rect != null) {
      for (final corner in const [
        _DragMode.resizeTL,
        _DragMode.resizeTR,
        _DragMode.resizeBL,
        _DragMode.resizeBR,
      ]) {
        if ((local - _handleCenter(rect, corner)).distance <=
            _handleTouchRadius) {
          _pendingMode = corner;
          _dragStartLocal = local;
          _dragStartRect = rect;
          return;
        }
      }
      final normalized = _toNormalized(local);
      if (rect.contains(normalized.dx, normalized.dy)) {
        _pendingMode = _DragMode.moving;
        _dragStartLocal = local;
        _dragStartRect = rect;
        return;
      }
    }

    _pendingMode = _DragMode.drawing;
    _dragStartLocal = local;
    _dragStartRect = null;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    final downLocal = _pointerDownLocal;
    if (downLocal == null) return;
    final current = event.localPosition;

    if (!_dragCommitted) {
      if ((current - downLocal).distance < _tapSlop) return;
      _dragCommitted = true;
      _mode = _pendingMode ?? _DragMode.drawing;
    }

    _applyDrag(current);
  }

  void _handlePointerUp(PointerEvent event) {
    if (!_dragCommitted) {
      _handleTapUpAt(event.localPosition);
    }
    _mode = _DragMode.none;
    _pointerDownLocal = null;
    _pendingMode = null;
    _dragStartLocal = null;
    _dragStartRect = null;
    _dragCommitted = false;
  }

  void _applyDrag(Offset current) {
    final startLocal = _dragStartLocal;
    if (startLocal == null || _mode == _DragMode.none) return;

    switch (_mode) {
      case _DragMode.drawing:
        final start = _toNormalized(startLocal);
        final end = _toNormalized(current);
        widget.onEditingRectChanged(
          _clampRect(
            NormalizedRect(
              left: start.dx < end.dx ? start.dx : end.dx,
              top: start.dy < end.dy ? start.dy : end.dy,
              width: (end.dx - start.dx).abs(),
              height: (end.dy - start.dy).abs(),
            ),
          ),
        );
        break;
      case _DragMode.moving:
        final base = _dragStartRect!;
        final deltaX = (current.dx - startLocal.dx) / _boxSize.width;
        final deltaY = (current.dy - startLocal.dy) / _boxSize.height;
        widget.onEditingRectChanged(
          _clampRect(
            NormalizedRect(
              left: base.left + deltaX,
              top: base.top + deltaY,
              width: base.width,
              height: base.height,
            ),
          ),
        );
        break;
      case _DragMode.resizeTL:
      case _DragMode.resizeTR:
      case _DragMode.resizeBL:
      case _DragMode.resizeBR:
        final base = _dragStartRect!;
        final point = _toNormalized(current);
        double left = base.left, top = base.top;
        double right = base.right, bottom = base.bottom;
        if (_mode == _DragMode.resizeTL || _mode == _DragMode.resizeBL) {
          left = point.dx;
        }
        if (_mode == _DragMode.resizeTR || _mode == _DragMode.resizeBR) {
          right = point.dx;
        }
        if (_mode == _DragMode.resizeTL || _mode == _DragMode.resizeTR) {
          top = point.dy;
        }
        if (_mode == _DragMode.resizeBL || _mode == _DragMode.resizeBR) {
          bottom = point.dy;
        }
        widget.onEditingRectChanged(
          _clampRect(
            NormalizedRect(
              left: left < right ? left : right,
              top: top < bottom ? top : bottom,
              width: (right - left).abs(),
              height: (bottom - top).abs(),
            ),
          ),
        );
        break;
      case _DragMode.none:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          color: Colors.white,
          child: LayoutBuilder(
            builder: (context, constraints) {
              _boxSize = Size(constraints.maxWidth, constraints.maxHeight);
              return Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(widget.imageBytes, fit: BoxFit.cover),
                  Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: _handlePointerDown,
                    onPointerMove: _handlePointerMove,
                    onPointerUp: _handlePointerUp,
                    onPointerCancel: _handlePointerUp,
                    child: CustomPaint(
                      painter: _SpaceCanvasPainter(
                        tasks: widget.tasks,
                        editingRect: widget.editingRect,
                        activeTaskId: widget.activeTaskId,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SpaceCanvasPainter extends CustomPainter {
  _SpaceCanvasPainter({
    required this.tasks,
    required this.editingRect,
    required this.activeTaskId,
  });

  final List<SpaceTask> tasks;
  final NormalizedRect? editingRect;
  final String? activeTaskId;

  Rect _toPixelRect(NormalizedRect rect, Size size) {
    return Rect.fromLTWH(
      rect.left * size.width,
      rect.top * size.height,
      rect.width * size.width,
      rect.height * size.height,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < tasks.length; i++) {
      final task = tasks[i];
      if (task.id == activeTaskId) continue;
      final color = spaceRainbowPalette[i % spaceRainbowPalette.length];
      final rect = _toPixelRect(task.rect, size);
      canvas.drawRect(
        rect,
        Paint()
          ..color = color.withValues(alpha: 0.22)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRect(
        rect,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    final editing = editingRect;
    if (editing != null) {
      const accent = Color(0xFF2196F3);
      final rect = _toPixelRect(editing, size);
      canvas.drawRect(
        rect,
        Paint()
          ..color = accent.withValues(alpha: 0.16)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRect(
        rect,
        Paint()
          ..color = accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );

      final handlePaintFill = Paint()..color = Colors.white;
      final handlePaintBorder = Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      for (final corner in [
        rect.topLeft,
        rect.topRight,
        rect.bottomLeft,
        rect.bottomRight,
      ]) {
        canvas.drawCircle(corner, 10, handlePaintFill);
        canvas.drawCircle(corner, 10, handlePaintBorder);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SpaceCanvasPainter oldDelegate) {
    return oldDelegate.tasks != tasks ||
        oldDelegate.editingRect != editingRect ||
        oldDelegate.activeTaskId != activeTaskId;
  }
}
