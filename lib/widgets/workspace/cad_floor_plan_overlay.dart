import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/cad_floor_plan.dart';
import '../../models/cad_workspace_state.dart' show CadEditTool;
import '../../models/floor_plan_geometry.dart';
import '../../models/ss_spatial_model.dart';
import '../../theme/space_shift_colors.dart';
import 'floor_plan_analysis_overlay.dart' show ContainFitTransform;

/// 중앙 2D 평면도 위에 편집 가능한 CAD geometry(벽/공간/문·창)를
/// 그리는 기본 화면.
///
/// [FloorPlanAnalysisOverlay](분석 확인/debug 모드에서만 쓰는 confidence
/// color overlay)와 달리, 이 위젯은 평소 화면에 보이는 CAD 스타일이다 —
/// 짙은 회색/검정 벽선 + white/light 배경, 선택된 객체만 accent로
/// 강조한다(WO 5번). 번호 marker는 절대 그리지 않는다 — 분석 geometry는
/// 사용자 작업이 아니기 때문이다(WO 1/2번).
///
/// 벽은 얇은 선이 아니라 중심선 + 두께로 계산한 폭이 있는 폴리곤으로
/// 그린다(WO 4번). 선택된 벽은 끝점 handle 두 개가 나타나 드래그로 옮길
/// 수 있고(WO 7번), 그 결과는 [onWallEndpointChanged]로 부모에게 알려
/// undo 가능한 mutation으로 처리한다.
///
/// 끝점 드래그는 캔버스 전체를 덮는 탭 감지기와 완전히 분리된, 각 끝점
/// 위치에만 있는 작은 별도 [GestureDetector]가 담당한다 — 하나의
/// GestureDetector에 tap과 pan을 모두 붙이면 제스처 arena에서 서로
/// 충돌해 탭이 씹히는 문제가 있어, 처음부터 히트테스트 영역을 나눴다.
class CadFloorPlanOverlay extends StatefulWidget {
  const CadFloorPlanOverlay({
    super.key,
    required this.floorPlan,
    required this.selectedId,
    required this.onSelect,
    required this.onWallEndpointChanged,
    this.calibrating = false,
    this.onCalibrationDragEnd,
    this.structureEditing = false,
    this.tool = CadEditTool.select,
    this.onAddWallDrag,
    this.onAddOpeningTap,
    this.onOpeningMoved,
  });

  final CadFloorPlan floorPlan;
  final String? selectedId;
  final ValueChanged<String?> onSelect;

  /// 사용자가 선택된 벽의 끝점을 드래그로 옮길 때마다 호출된다.
  /// [isStart]가 true면 시작점, false면 끝점을 옮긴 것이다.
  final void Function(String wallId, bool isStart, Point2 newPosition)
  onWallEndpointChanged;

  /// true면 geometry 선택 대신 "치수 보정" 드래그 선택 모드로 동작한다
  /// (실기 FAIL 재수정 WO 11/12번 — 기준점 2개를 따로따로 탭하는 대신,
  /// 펜/마우스로 벽 구간을 직접 drag해서 고른다).
  final bool calibrating;

  /// 드래그가 끝났을 때 호출된다 — [nearestWallId]는 드래그 시작점 근처의
  /// 실제 [CadWall]을 찾았으면 그 id(우선), 못 찾았으면 null(호출부가
  /// 두 점 사이 직선 거리로 폴백, WO 15번).
  final void Function(Point2 dragStart, Point2 dragEnd, String? nearestWallId)?
  onCalibrationDragEnd;

  /// CANONICAL 2D CONFIRMATION → 3D PIPELINE WO §4 — "구조 확인/보정"
  /// 모드. [calibrating]과 동시에 true가 될 수 없다(호출부가 보장).
  /// true면 [tool]에 따라 탭/드래그가 선택 대신 벽/문/창 추가나 이동으로
  /// 이어진다.
  final bool structureEditing;
  final CadEditTool tool;

  /// [CadEditTool.addWall] — 드래그 시작/끝점(정규화 좌표).
  final void Function(Point2 start, Point2 end)? onAddWallDrag;

  /// [CadEditTool.addDoor]/[CadEditTool.addWindow] — 탭 위치(정규화
  /// 좌표)와 어떤 도구였는지.
  final void Function(Point2 point, OpeningType type)? onAddOpeningTap;

  /// 선택된 문/창을 드래그했을 때, 드래그로 계산된 새 위치(정규화
  /// 좌표) — 실제 host wall 위로 투영/제한하는 것은 호출부 책임이다.
  final void Function(String openingId, Point2 draggedPoint)? onOpeningMoved;

  @override
  State<CadFloorPlanOverlay> createState() => _CadFloorPlanOverlayState();
}

class _CadFloorPlanOverlayState extends State<CadFloorPlanOverlay> {
  /// 지금 진행 중인 치수 보정 드래그의 시작/현재 위치(정규화 좌표) —
  /// painter 미리보기 선용. 드래그가 끝나면 비운다.
  Point2? _dragStart;
  Point2? _dragCurrent;

  CadWall? get _selectedWall {
    final id = widget.selectedId;
    if (id == null) return null;
    for (final wall in widget.floorPlan.walls) {
      if (wall.id == id) return wall;
    }
    return null;
  }

  CadOpening? get _selectedOpening {
    final id = widget.selectedId;
    if (id == null) return null;
    for (final opening in widget.floorPlan.openings) {
      if (opening.id == id) return opening;
    }
    return null;
  }

  /// CANONICAL 2D CONFIRMATION WO §4 — [CadEditTool.addWall]은 탭 두
  /// 번이 아니라 드래그 한 번(기존 치수 보정과 같은 제스처)으로 벽을
  /// 긋는다 — 이미 검증된 pan 제스처 하나를 재사용해 새 recognizer를
  /// 늘리지 않는다.
  bool get _usesDragGesture =>
      widget.calibrating || (widget.structureEditing && widget.tool == CadEditTool.addWall);

  @override
  Widget build(BuildContext context) {
    final imageSize = Size(
      widget.floorPlan.sourceWidthPx.toDouble(),
      widget.floorPlan.sourceHeightPx.toDouble(),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final container = Size(constraints.maxWidth, constraints.maxHeight);
        final transform = ContainFitTransform.compute(container, imageSize);
        final selectedWall = _selectedWall;
        final selectedOpening = widget.structureEditing ? _selectedOpening : null;
        final dragStart = _dragStart;
        final dragCurrent = _dragCurrent;
        final previewPoints =
            _usesDragGesture && dragStart != null && dragCurrent != null
            ? [dragStart, dragCurrent]
            : const <Point2>[];
        final useDrag = _usesDragGesture;

        return Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapUp: useDrag
                  ? null
                  : (details) => _handleTapDispatch(details.localPosition, transform),
              onPanStart: useDrag
                  ? (details) => _onDragStart(details, transform)
                  : null,
              onPanUpdate: useDrag
                  ? (details) => _onDragUpdate(details, transform)
                  : null,
              onPanEnd: useDrag ? (details) => _onDragEnd(transform) : null,
              child: CustomPaint(
                size: container,
                painter: _CadOverlayPainter(
                  floorPlan: widget.floorPlan,
                  transform: transform,
                  selectedId: widget.selectedId,
                  calibrationPoints: previewPoints,
                  showRoomLabels: widget.structureEditing,
                ),
              ),
            ),
            if (selectedWall != null && !widget.calibrating && widget.tool == CadEditTool.select) ...[
              _EndpointHandle(
                screenPosition: transform.mapNormalized(selectedWall.start),
                onDragDelta: (delta) => _moveEndpoint(
                  selectedWall,
                  isStart: true,
                  delta: delta,
                  transform: transform,
                ),
              ),
              _EndpointHandle(
                screenPosition: transform.mapNormalized(selectedWall.end),
                onDragDelta: (delta) => _moveEndpoint(
                  selectedWall,
                  isStart: false,
                  delta: delta,
                  transform: transform,
                ),
              ),
            ],
            if (selectedOpening != null)
              _EndpointHandle(
                screenPosition: transform.mapNormalized(selectedOpening.center),
                onDragDelta: (delta) => _moveOpening(selectedOpening, delta, transform),
              ),
          ],
        );
      },
    );
  }

  void _moveEndpoint(
    CadWall wall, {
    required bool isStart,
    required Offset delta,
    required ContainFitTransform transform,
  }) {
    final current = isStart ? wall.start : wall.end;
    final updated = Point2(
      (current.x + delta.dx / transform.rect.width).clamp(0.0, 1.0),
      (current.y + delta.dy / transform.rect.height).clamp(0.0, 1.0),
    );
    widget.onWallEndpointChanged(wall.id, isStart, updated);
  }

  /// CANONICAL 2D CONFIRMATION WO §4 — 이 세 메서드는 원래 "치수 보정"
  /// 전용이었지만, [CadEditTool.addWall]도 정확히 같은 드래그 제스처를
  /// 쓰므로 이름을 일반화해 재사용한다(§ [_usesDragGesture]). 어떤
  /// 모드였는지는 [_onDragEnd]에서 분기한다.
  void _onDragStart(
    DragStartDetails details,
    ContainFitTransform transform,
  ) {
    final point = transform.inverse(details.localPosition);
    if (point == null) return;
    setState(() {
      _dragStart = point;
      _dragCurrent = point;
    });
  }

  void _onDragUpdate(
    DragUpdateDetails details,
    ContainFitTransform transform,
  ) {
    final point = transform.inverse(details.localPosition);
    if (point == null || _dragStart == null) return;
    setState(() => _dragCurrent = point);
  }

  void _onDragEnd(ContainFitTransform transform) {
    final start = _dragStart;
    final end = _dragCurrent;
    setState(() {
      _dragStart = null;
      _dragCurrent = null;
    });
    if (start == null || end == null) return;
    // 실사용 실기 재현 — 짧은 오탭(사실상 제자리 클릭)은 의미 있는 벽
    // 선택으로 취급하지 않는다(길이 0에 가까운 구간을 "선택한 벽 길이"로
    // 잘못 보여주는 사고 방지).
    if (start.distanceTo(end) < 0.002) return;
    if (widget.calibrating) {
      widget.onCalibrationDragEnd?.call(start, end, _nearestWallId(start));
    } else if (widget.structureEditing && widget.tool == CadEditTool.addWall) {
      widget.onAddWallDrag?.call(start, end);
    }
  }

  /// 선택된 문/창을 드래그했을 때 새 위치를 계산해 알린다 — host wall
  /// 위로 투영/제한하는 것은 호출부([FloorPlanWorkspaceScreen])가
  /// 한다(이 위젯은 순수 좌표 변환만 담당한다).
  void _moveOpening(CadOpening opening, Offset delta, ContainFitTransform transform) {
    final updated = Point2(
      opening.center.x + delta.dx / transform.rect.width,
      opening.center.y + delta.dy / transform.rect.height,
    );
    widget.onOpeningMoved?.call(opening.id, updated);
  }

  /// [point] 근처(기존 [_handleTap]과 같은 tolerance)의 실제 [CadWall]을
  /// 찾는다 — 치수 보정 드래그는 실제 CadWall 객체 선택을 우선한다(WO
  /// 15번). 못 찾으면 null(호출부가 두 점 직선 거리로 폴백).
  String? _nearestWallId(Point2 point) {
    const tolerance = 0.03;
    String? nearestId;
    var bestDistance = double.infinity;
    for (final wall in widget.floorPlan.walls) {
      final distance = _distanceToSegment(point, wall.start, wall.end);
      if (distance <= tolerance && distance < bestDistance) {
        bestDistance = distance;
        nearestId = wall.id;
      }
    }
    return nearestId;
  }

  /// CANONICAL 2D CONFIRMATION WO §4 — 탭 한 번의 의미는 현재 도구에
  /// 달려 있다: 평소(select)엔 기존 선택 동작 그대로, addDoor/addWindow
  /// 에서는 탭 위치에 문/창을 붙이려는 시도로 해석한다(실제로 벽 근처
  /// 인지는 호출부가 [HintedGeometryExtractor] 없이도 판단할 수 있는
  /// "가까운 CadWall이 있는가"만 이 위젯이 먼저 걸러준다 — 완전히 벽과
  /// 무관한 허공을 탭해도 콜백 자체는 호출되므로, 실제 반영 여부/경고는
  /// 호출부 책임이다).
  void _handleTapDispatch(Offset local, ContainFitTransform transform) {
    final point = transform.inverse(local);
    if (point == null) {
      if (widget.tool == CadEditTool.select) widget.onSelect(null);
      return;
    }
    if (widget.structureEditing && widget.tool == CadEditTool.addDoor) {
      widget.onAddOpeningTap?.call(point, OpeningType.door);
      return;
    }
    if (widget.structureEditing && widget.tool == CadEditTool.addWindow) {
      widget.onAddOpeningTap?.call(point, OpeningType.window);
      return;
    }
    final shortSide = math.min(transform.rect.width, transform.rect.height);
    if (shortSide <= 0) return;
    widget.onSelect(
      cadFloorPlanHitTest(widget.floorPlan, point, tolerance: 14.0 / shortSide),
    );
  }
}

/// [floorPlan]에서 [point](정규화 좌표, 0.0~1.0) 근처의 CAD geometry id를
/// opening → wall → room 우선순위로 찾는다(기존 [_handleTap]의 판정
/// 로직을 그대로 추출한 것 — 로직 중복 없이 재사용). 못 찾으면 null.
///
/// WO089 CORE EDITING — [WorkspaceDrawingLayer]가 이 오버레이 위에 얹혀
/// "선택" 도구의 탭을 먼저 받는다(사용자가 그린 도형을 먼저 히트테스트
/// 하기 위함). 그 레이어 자신의 도형에서 아무것도 안 맞으면, 이 함수로
/// 기존 CAD 벽/문·창/공간 선택을 그대로 위임해 원래 탭 선택 동작이
/// 깨지지 않게 한다(§28 — 새 GestureDetector를 얹으면서 기존 탭이
/// 씹히는 문제를 조사해서 고친 결과).
String? cadFloorPlanHitTest(
  CadFloorPlan floorPlan,
  Point2 point, {
  required double tolerance,
}) {
  for (final opening in floorPlan.openings) {
    if (opening.center.distanceTo(point) <= tolerance * 1.4) {
      return opening.id;
    }
  }

  String? nearestWallId;
  var bestDistance = double.infinity;
  for (final wall in floorPlan.walls) {
    final distance = _distanceToSegment(point, wall.start, wall.end);
    if (distance <= tolerance && distance < bestDistance) {
      bestDistance = distance;
      nearestWallId = wall.id;
    }
  }
  if (nearestWallId != null) return nearestWallId;

  for (final room in floorPlan.rooms) {
    if (room.containsPoint(point)) return room.id;
  }

  return null;
}

/// 벽 끝점 하나를 드래그하기 위한, 화면 위치에 고정된 작은 히트테스트
/// 영역. 실제 원(●) 그림은 [_CadOverlayPainter]가 그리고, 이 위젯은
/// 손가락/펜으로 누르기 충분한 크기(44x44)의 투명한 드래그 감지 영역만
/// 담당한다.
class _EndpointHandle extends StatelessWidget {
  const _EndpointHandle({
    required this.screenPosition,
    required this.onDragDelta,
  });

  final Offset screenPosition;
  final ValueChanged<Offset> onDragDelta;

  static const double _hitSize = 44;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: screenPosition.dx - _hitSize / 2,
      top: screenPosition.dy - _hitSize / 2,
      width: _hitSize,
      height: _hitSize,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) => onDragDelta(details.delta),
      ),
    );
  }
}

double _distanceToSegment(Point2 p, Point2 a, Point2 b) {
  final abx = b.x - a.x;
  final aby = b.y - a.y;
  final lengthSquared = abx * abx + aby * aby;
  if (lengthSquared == 0) return p.distanceTo(a);

  var t = ((p.x - a.x) * abx + (p.y - a.y) * aby) / lengthSquared;
  t = t.clamp(0.0, 1.0);
  final projection = Point2(a.x + t * abx, a.y + t * aby);
  return p.distanceTo(projection);
}

/// 가구/설비 후보([SSObjectCandidate]) 윤곽 전용 — 실제 벽(실선)과
/// 혼동되지 않도록 닫힌 폴리곤을 점선으로 그린다.
void _drawDashedPolygon(Canvas canvas, List<Offset> points, Color color) {
  if (points.length < 2) return;
  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2
    ..color = color;
  const dashLength = 5.0;
  const gapLength = 4.0;
  for (var i = 0; i < points.length; i++) {
    final a = points[i];
    final b = points[(i + 1) % points.length];
    final segment = b - a;
    final total = segment.distance;
    if (total == 0) continue;
    final direction = segment / total;
    var drawn = 0.0;
    while (drawn < total) {
      final segmentEnd = math.min(drawn + dashLength, total);
      canvas.drawLine(a + direction * drawn, a + direction * segmentEnd, paint);
      drawn = segmentEnd + gapLength;
    }
  }
}

class _CadOverlayPainter extends CustomPainter {
  _CadOverlayPainter({
    required this.floorPlan,
    required this.transform,
    required this.selectedId,
    required this.calibrationPoints,
    this.showRoomLabels = false,
  });

  final CadFloorPlan floorPlan;
  final ContainFitTransform transform;
  final String? selectedId;
  final List<Point2> calibrationPoints;

  /// CANONICAL 2D CONFIRMATION WO §4 — "구조 확인/보정" 모드에서만 방
  /// 라벨 텍스트를 그린다(평소 CAD 표시는 여전히 AI Clean 이미지가
  /// 담당하므로, 이 벡터 오버레이가 이중으로 라벨을 겹쳐 그리지 않는다).
  final bool showRoomLabels;

  static const _wallFill = Color(0xFFEDF0F3);
  static const _wallStroke = Color(0xFF334155);
  static const _guideLine = Color(0xFFCBD5E1);
  static const _objectOutline = Color(0xFF94A3B8);

  /// CANONICAL 2D CONFIRMATION WO §4 — "door: swing 또는 명확한 door
  /// symbol / window: 명확한 window symbol" 요구사항 — 문/창을 같은
  /// 흰 원으로 그리던 이전 방식은 둘을 구분할 수 없었다. 색으로 즉시
  /// 구분한다(기존 image2_overlay_screen.dart POC와 같은 톤 — door=
  /// 초록, window=청록 — 이 앱 안에서 이미 쓰던 관례를 재사용).
  static const _doorColor = Color(0xFF2E7D32);
  static const _windowColor = Color(0xFF0097A7);

  /// WO084/085 §9 — 자동으로 확정되지 않아 사람이 다시 봐야 하는 벽/문·창/
  /// 공간(reviewNeeded)을 문/창을 door/window로 단정한 것처럼 보이지
  /// 않도록 별도 색으로 구분한다. 선택 강조색과는 겹치지 않는다.
  static const _reviewNeededAccent = Color(0xFFE65100);

  @override
  void paint(Canvas canvas, Size size) {
    // PC2 2D CAD 재조사 WO — "어디까지가 공간 1이고 어디까지가 공간
    // 2인지 한눈에" 보이도록, 검출된 각 공간 polygon을 아주 연한
    // 반투명 fill로 채운다. 색은 공간마다 다르되([roomAccentColorFor]
    // — 우측 목록/도면 위 번호 marker와 같은 순서·같은 roomId를
    // 공유) 벽선 가독성을 해치지 않도록 항상 낮은 alpha만 쓴다. 벽은
    // 이 fill보다 나중에(위에) 그려 항상 fill 위로 선명하게 보인다.
    for (var i = 0; i < floorPlan.rooms.length; i++) {
      final room = floorPlan.rooms[i];
      final selected = room.id == selectedId;
      final path = Path()
        ..addPolygon(room.polygon.map(transform.mapNormalized).toList(), true);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.fill
          ..color = SpaceShiftColors.roomAccentColorFor(
            i,
          ).withValues(alpha: selected ? 0.22 : 0.12),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2 : (room.reviewNeeded ? 1.5 : 1)
          ..color = selected
              ? SpaceShiftColors.selectionAccent
              : (room.reviewNeeded ? _reviewNeededAccent : _guideLine),
      );
      if (showRoomLabels && room.polygon.isNotEmpty) {
        _drawRoomLabel(canvas, room, i);
      }
    }

    // SS 건축도면 이해 엔진 V1 WO — "공간"으로 인정되지 않고 가구/설비
    // 후보로 분류된 닫힌 영역은 번호를 매기거나 채우지 않되, 완전히
    // 숨기지도 않는다(WO 11번 — 가구/설비는 공간과 별도의 의미 객체).
    // 회색 점선 윤곽만으로 "SS가 이 영역을 방이 아니라 가구/설비로
    // 판단했다"는 것을 개발자/사용자가 눈으로 바로 확인할 수 있게 한다.
    for (final object in floorPlan.objectCandidates) {
      final points = object.polygon.map(transform.mapNormalized).toList();
      _drawDashedPolygon(canvas, points, _objectOutline);
    }

    for (final wall in floorPlan.walls) {
      final selected = wall.id == selectedId;
      final polygon = wall.boundaryPolygon
          .map(transform.mapNormalized)
          .toList();
      final path = Path()..addPolygon(polygon, true);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.fill
          ..color = selected
              ? SpaceShiftColors.selectionAccent.withValues(alpha: 0.12)
              : _wallFill,
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2.5 : 1.5
          ..color = selected
              ? SpaceShiftColors.selectionAccent
              : (wall.reviewNeeded ? _reviewNeededAccent : _wallStroke),
      );

      if (selected) {
        final startHandle = transform.mapNormalized(wall.start);
        final endHandle = transform.mapNormalized(wall.end);
        final handlePaint = Paint()..color = SpaceShiftColors.selectionAccent;
        final handleBorder = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white;
        for (final handle in [startHandle, endHandle]) {
          canvas.drawCircle(handle, 7, handlePaint);
          canvas.drawCircle(handle, 7, handleBorder);
        }
      }
    }

    for (final opening in floorPlan.openings) {
      final selected = opening.id == selectedId;
      final center = transform.mapNormalized(opening.center);
      // CANONICAL 2D CONFIRMATION WO §4 — door/window를 색으로 즉시
      // 구분한다(둘 다 흰 원으로만 그리면 "명확한 door/window symbol"
      // 요구를 만족하지 못한다). unknown은 기존처럼 중립색 유지.
      final typeColor = switch (opening.type) {
        OpeningType.door => _doorColor,
        OpeningType.window => _windowColor,
        OpeningType.unknown => _wallStroke,
      };
      final paint = Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.white;
      final border = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 2.5 : 2
        ..color = selected
            ? SpaceShiftColors.selectionAccent
            : (opening.reviewNeeded ? _reviewNeededAccent : typeColor);
      final radius = selected ? 8.0 : 6.0;
      canvas.drawCircle(center, radius, paint);
      canvas.drawCircle(center, radius, border);
      // 문/창 종류를 색맹/흑백 캡처에서도 구분할 수 있도록 작은 내부
      // 점을 하나 더 찍는다(문=속이 찬 원, 창=속이 빈 사각형 느낌의
      // 대각선 — 아주 단순한 기호지만 "swing 또는 명확한 symbol"이라는
      // 요구의 최소 구현이다).
      if (!selected) {
        if (opening.type == OpeningType.door) {
          canvas.drawCircle(center, radius * 0.4, Paint()..color = typeColor);
        } else if (opening.type == OpeningType.window) {
          canvas.drawLine(
            center + Offset(-radius * 0.5, 0),
            center + Offset(radius * 0.5, 0),
            Paint()
              ..strokeWidth = 2
              ..color = typeColor,
          );
        }
      }
    }

    if (calibrationPoints.isNotEmpty) {
      final points = calibrationPoints.map(transform.mapNormalized).toList();
      if (points.length == 2) {
        canvas.drawLine(
          points[0],
          points[1],
          Paint()
            ..strokeWidth = 2
            ..color = SpaceShiftColors.selectionAccent,
        );
      }
      for (final p in points) {
        canvas.drawCircle(
          p,
          6,
          Paint()..color = SpaceShiftColors.selectionAccent,
        );
        canvas.drawCircle(
          p,
          6,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Colors.white,
        );
      }
    }
  }

  /// [room]의 polygon 중심(단순 정점 평균 — 오목한 모양이면 다소 어긋날
  /// 수 있지만 라벨 위치용으로는 충분하다)에 이름을 그린다. 실제 이름이
  /// 없으면 거짓으로 지어내지 않고 "공간 N"으로 표시한다(WO084 원칙과
  /// 동일한 정직성 — [CadRoom.name] 문서 참고).
  void _drawRoomLabel(Canvas canvas, CadRoom room, int index) {
    final points = room.polygon.map(transform.mapNormalized).toList();
    final centroid = points.fold<Offset>(Offset.zero, (sum, p) => sum + p) / points.length.toDouble();
    final label = room.name ?? '공간 ${index + 1}';
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: SpaceShiftColors.textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          backgroundColor: Color(0xCCFFFFFF),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, centroid - Offset(painter.width / 2, painter.height / 2));
  }

  @override
  bool shouldRepaint(covariant _CadOverlayPainter oldDelegate) {
    return oldDelegate.floorPlan != floorPlan ||
        oldDelegate.selectedId != selectedId ||
        oldDelegate.transform.rect != transform.rect ||
        oldDelegate.calibrationPoints != calibrationPoints ||
        oldDelegate.showRoomLabels != showRoomLabels;
  }
}
