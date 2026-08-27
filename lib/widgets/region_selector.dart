import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/region_selection.dart';

/// 공간 작업실(4번 화면)의 핵심 위젯.
///
/// 사진 위에서 사용자가 마우스(웹) 또는 손가락(태블릿)으로 사각형 영역을
/// 그리고, 이동하고, 크기를 조절할 수 있게 한다. 부모(WorkspaceScreen)가
/// 실제 선택 상태([selection])를 들고 있고, 이 위젯은 제스처를 정규화된
/// 좌표로 변환해 [onChanged]로 알려주기만 하는 제어 컴포넌트(controlled
/// component)다.
///
/// 포인터 처리는 일반 [GestureDetector](pan 계열 recognizer)가 아니라
/// [Listener]로 직접 구현한다. 이 화면은 세로로 스크롤되는 컨테이너
/// 안에 놓이는데, GestureDetector의 Pan recognizer를 쓰면 조상
/// Scrollable의 드래그 recognizer와 제스처 아레나에서 경쟁하다가 선택
/// 동작이 씹히는 경우가 있었다. Listener는 제스처 아레나에 참여하지
/// 않고 원시 포인터 이벤트를 그대로 받기 때문에 항상 안정적으로 동작한다.
class RegionSelector extends StatelessWidget {
  const RegionSelector({
    super.key,
    required this.imageBytes,
    required this.selection,
    required this.onChanged,
    this.onDragActiveChanged,
    this.overlayColor = const Color(0xFFA855F7),
  });

  /// 배경에 표시할 공간 사진.
  final Uint8List imageBytes;

  /// 현재 선택 영역(정규화 좌표). 아직 선택하지 않았다면 null.
  final RegionSelection? selection;

  /// 사용자가 영역을 새로 그리거나, 옮기거나, 크기를 바꿀 때마다 호출된다.
  final ValueChanged<RegionSelection> onChanged;

  /// 드래그가 시작/종료될 때 호출된다. 부모가 이 시점 동안 바깥 스크롤을
  /// 잠시 잠가(NeverScrollableScrollPhysics) 페이지가 함께 스크롤되는
  /// 것을 막는 데 사용할 수 있다.
  final ValueChanged<bool>? onDragActiveChanged;

  /// 선택 영역 오버레이/테두리/핸들에 사용할 색.
  final Color overlayColor;

  static const double _minSelectionPx = 32;
  static const double _handleTouchSize = 28;
  static const double _handleVisualSize = 14;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(imageBytes, fit: BoxFit.cover),
              _CreationLayer(
                size: size,
                selectionRect: selection == null
                    ? null
                    : _toRect(selection!, size),
                minSize: _minSelectionPx,
                onCreate: (rect) => onChanged(_toSelection(rect, size)),
                onMoveSelection: (rect) =>
                    onChanged(_toSelection(rect, size)),
                onDragActiveChanged: onDragActiveChanged,
              ),
              if (selection != null)
                _SelectionOverlay(
                  rect: _toRect(selection!, size),
                  color: overlayColor,
                  handleTouchSize: _handleTouchSize,
                  handleVisualSize: _handleVisualSize,
                  minSize: _minSelectionPx,
                  bounds: size,
                  onResize: (rect) => onChanged(_toSelection(rect, size)),
                  onDragActiveChanged: onDragActiveChanged,
                ),
            ],
          );
        },
      ),
    );
  }

  static Rect _toRect(RegionSelection selection, Size size) {
    return Rect.fromLTWH(
      selection.x * size.width,
      selection.y * size.height,
      selection.width * size.width,
      selection.height * size.height,
    );
  }

  static RegionSelection _toSelection(Rect rect, Size size) {
    if (size.width == 0 || size.height == 0) {
      return const RegionSelection(x: 0, y: 0, width: 0.2, height: 0.2);
    }
    return RegionSelection(
      x: (rect.left / size.width).clamp(0.0, 1.0),
      y: (rect.top / size.height).clamp(0.0, 1.0),
      width: (rect.width / size.width).clamp(0.02, 1.0),
      height: (rect.height / size.height).clamp(0.02, 1.0),
    );
  }
}

/// 아직 선택 영역이 없는 빈 공간을 드래그해 새 영역을 만들거나,
/// 기존 영역의 안쪽을 드래그해 통째로 이동시키는 레이어.
/// (크기 조절 핸들은 [_SelectionOverlay]가 별도로 그 위에 그린다.)
class _CreationLayer extends StatefulWidget {
  const _CreationLayer({
    required this.size,
    required this.selectionRect,
    required this.minSize,
    required this.onCreate,
    required this.onMoveSelection,
    this.onDragActiveChanged,
  });

  final Size size;
  final Rect? selectionRect;
  final double minSize;
  final ValueChanged<Rect> onCreate;
  final ValueChanged<Rect> onMoveSelection;
  final ValueChanged<bool>? onDragActiveChanged;

  @override
  State<_CreationLayer> createState() => _CreationLayerState();
}

class _CreationLayerState extends State<_CreationLayer> {
  Offset? _dragOrigin;
  bool _isMoving = false;
  int? _activePointer;

  void _onPointerDown(PointerDownEvent event) {
    if (_activePointer != null) return;
    _activePointer = event.pointer;

    final rect = widget.selectionRect;
    final position = event.localPosition;
    if (rect != null && rect.contains(position)) {
      _isMoving = true;
      _dragOrigin = null;
    } else {
      _isMoving = false;
      _dragOrigin = position;
      // 드래그를 시작하자마자 작은 영역을 만들어 즉시 시각 피드백을 준다.
      widget.onCreate(Rect.fromLTWH(position.dx, position.dy, 1, 1));
    }
    widget.onDragActiveChanged?.call(true);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;

    if (_isMoving) {
      final rect = widget.selectionRect;
      if (rect == null) return;
      final moved = rect.shift(event.delta);
      double left = moved.left;
      double top = moved.top;
      if (left < 0) left = 0;
      if (top < 0) top = 0;
      if (left + moved.width > widget.size.width) {
        left = widget.size.width - moved.width;
      }
      if (top + moved.height > widget.size.height) {
        top = widget.size.height - moved.height;
      }
      widget.onMoveSelection(Rect.fromLTWH(left, top, moved.width, moved.height));
      return;
    }

    final origin = _dragOrigin;
    if (origin == null) return;
    final rect = Rect.fromPoints(origin, event.localPosition);
    widget.onCreate(_clampToBounds(rect, widget.size, widget.minSize));
  }

  void _endDrag(int pointer) {
    if (pointer != _activePointer) return;
    _activePointer = null;
    _dragOrigin = null;
    _isMoving = false;
    widget.onDragActiveChanged?.call(false);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: (event) => _endDrag(event.pointer),
      onPointerCancel: (event) => _endDrag(event.pointer),
      child: const SizedBox.expand(),
    );
  }
}

Rect _clampToBounds(Rect rect, Size size, double minSize) {
  double left = rect.left;
  double top = rect.top;
  double right = rect.right;
  double bottom = rect.bottom;
  if (right < left) {
    final t = left;
    left = right;
    right = t;
  }
  if (bottom < top) {
    final t = top;
    top = bottom;
    bottom = t;
  }
  left = left.clamp(0.0, size.width);
  top = top.clamp(0.0, size.height);
  right = right.clamp(0.0, size.width);
  bottom = bottom.clamp(0.0, size.height);

  double width = right - left;
  double height = bottom - top;
  if (width < minSize) {
    if (left + minSize <= size.width) {
      right = left + minSize;
    } else {
      left = size.width - minSize;
      right = size.width;
    }
  }
  if (height < minSize) {
    if (top + minSize <= size.height) {
      bottom = top + minSize;
    } else {
      top = size.height - minSize;
      bottom = size.height;
    }
  }
  return Rect.fromLTRB(left, top, right, bottom);
}

/// 선택 영역의 반투명 오버레이 + 테두리 + 네 모서리 크기 조절 핸들.
class _SelectionOverlay extends StatelessWidget {
  const _SelectionOverlay({
    required this.rect,
    required this.color,
    required this.handleTouchSize,
    required this.handleVisualSize,
    required this.minSize,
    required this.bounds,
    required this.onResize,
    this.onDragActiveChanged,
  });

  final Rect rect;
  final Color color;
  final double handleTouchSize;
  final double handleVisualSize;
  final double minSize;
  final Size bounds;
  final ValueChanged<Rect> onResize;
  final ValueChanged<bool>? onDragActiveChanged;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fromRect(
          rect: rect,
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.28),
                border: Border.all(color: color, width: 2.5),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
        _handle(
          center: rect.topLeft,
          onDrag: (delta) => onResize(
            _clampToBounds(
              Rect.fromLTRB(
                rect.left + delta.dx,
                rect.top + delta.dy,
                rect.right,
                rect.bottom,
              ),
              bounds,
              minSize,
            ),
          ),
        ),
        _handle(
          center: rect.topRight,
          onDrag: (delta) => onResize(
            _clampToBounds(
              Rect.fromLTRB(
                rect.left,
                rect.top + delta.dy,
                rect.right + delta.dx,
                rect.bottom,
              ),
              bounds,
              minSize,
            ),
          ),
        ),
        _handle(
          center: rect.bottomLeft,
          onDrag: (delta) => onResize(
            _clampToBounds(
              Rect.fromLTRB(
                rect.left + delta.dx,
                rect.top,
                rect.right,
                rect.bottom + delta.dy,
              ),
              bounds,
              minSize,
            ),
          ),
        ),
        _handle(
          center: rect.bottomRight,
          onDrag: (delta) => onResize(
            _clampToBounds(
              Rect.fromLTRB(
                rect.left,
                rect.top,
                rect.right + delta.dx,
                rect.bottom + delta.dy,
              ),
              bounds,
              minSize,
            ),
          ),
        ),
      ],
    );
  }

  Widget _handle({
    required Offset center,
    required ValueChanged<Offset> onDrag,
  }) {
    return Positioned(
      left: center.dx - handleTouchSize / 2,
      top: center.dy - handleTouchSize / 2,
      width: handleTouchSize,
      height: handleTouchSize,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeUpLeftDownRight,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => onDragActiveChanged?.call(true),
          onPointerMove: (event) => onDrag(event.delta),
          onPointerUp: (_) => onDragActiveChanged?.call(false),
          onPointerCancel: (_) => onDragActiveChanged?.call(false),
          child: Center(
            child: Container(
              width: handleVisualSize,
              height: handleVisualSize,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2.5),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
