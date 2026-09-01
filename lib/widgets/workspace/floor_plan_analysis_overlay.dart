import 'dart:math' as math;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';

import '../../models/floor_plan_geometry.dart';
import '../../theme/space_shift_colors.dart';

/// 컨테이너 크기와 이미지의 자연 크기로부터, `BoxFit.contain`이 실제로
/// 그리는 사각형(letterbox 여백 포함)을 계산한다.
///
/// [FloorPlanPreview]의 `Image.memory(fit: BoxFit.contain)`와 이 오버레이가
/// "같은 공식"으로 각자 계산하므로, 같은 컨테이너 크기·같은 원본 이미지
/// 비율을 입력하면 항상 동일한 사각형이 나온다 — 두 위젯을 같은 크기의
/// Stack에 겹쳐 두는 것만으로 좌표가 정확히 맞는다(WO 6번, letterbox
/// 오프셋까지 계산).
@immutable
class ContainFitTransform {
  const ContainFitTransform(this.rect);

  final Rect rect;

  factory ContainFitTransform.compute(Size container, Size image) {
    if (image.width <= 0 ||
        image.height <= 0 ||
        container.width <= 0 ||
        container.height <= 0) {
      return ContainFitTransform(
        Rect.fromLTWH(0, 0, container.width, container.height),
      );
    }
    final containerAspect = container.width / container.height;
    final imageAspect = image.width / image.height;
    double width;
    double height;
    if (imageAspect > containerAspect) {
      width = container.width;
      height = width / imageAspect;
    } else {
      height = container.height;
      width = height * imageAspect;
    }
    final left = (container.width - width) / 2;
    final top = (container.height - height) / 2;
    return ContainFitTransform(Rect.fromLTWH(left, top, width, height));
  }

  /// 정규화 좌표(0.0~1.0) → 화면 픽셀 좌표.
  Offset mapNormalized(Point2 p) =>
      Offset(rect.left + p.x * rect.width, rect.top + p.y * rect.height);

  /// 화면 픽셀 좌표 → 정규화 좌표. letterbox 여백(이미지 바깥) 탭은 null.
  Point2? inverse(Offset local) {
    if (!rect.contains(local)) return null;
    return Point2(
      (local.dx - rect.left) / rect.width,
      (local.dy - rect.top) / rect.height,
    );
  }
}

/// 중앙 2D 평면도 위에 분석 결과(벽/공간/문·창 후보)를 그리고, 탭으로
/// 선택할 수 있게 하는 오버레이(WO 10/11번).
///
/// 원본 도면을 가리지 않도록 벽은 얇은 선, 공간은 옅은 반투명 채움,
/// 문/창은 작은 점 marker로만 그린다.
class FloorPlanAnalysisOverlay extends StatelessWidget {
  const FloorPlanAnalysisOverlay({
    super.key,
    required this.result,
    required this.selectedIds,
    required this.onSelect,
  });

  final FloorPlanAnalysisResult result;

  /// 현재 선택된 작업(task)에 속한 geometry id들 — 벽 후보는 "외벽"/"내벽"
  /// 그룹 전체가, 문/창은 "문 후보"/"창 후보" 그룹 전체가, 공간은 그
  /// 공간 하나만 함께 강조된다(작업 목록과 동일한 선택 단위, WO 12번).
  final Set<String> selectedIds;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final imageSize = Size(
      result.sourceWidthPx.toDouble(),
      result.sourceHeightPx.toDouble(),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final container = Size(constraints.maxWidth, constraints.maxHeight);
        final transform = ContainFitTransform.compute(container, imageSize);

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapUp: (details) => _handleTap(details.localPosition, transform),
          child: CustomPaint(
            size: container,
            painter: _AnalysisOverlayPainter(
              result: result,
              transform: transform,
              selectedIds: selectedIds,
            ),
          ),
        );
      },
    );
  }

  void _handleTap(Offset local, ContainFitTransform transform) {
    final point = transform.inverse(local);
    if (point == null) return;

    final shortSide = math.min(transform.rect.width, transform.rect.height);
    if (shortSide <= 0) return;
    final tolerance = 14.0 / shortSide;

    for (final opening in result.openings) {
      if (opening.center.distanceTo(point) <= tolerance * 1.4) {
        onSelect(opening.id);
        return;
      }
    }

    String? nearestWallId;
    var bestDistance = double.infinity;
    for (final wall in result.walls) {
      final distance = _distanceToSegment(point, wall.start, wall.end);
      if (distance <= tolerance && distance < bestDistance) {
        bestDistance = distance;
        nearestWallId = wall.id;
      }
    }
    if (nearestWallId != null) {
      onSelect(nearestWallId);
      return;
    }

    for (final room in result.rooms) {
      if (room.containsPoint(point)) {
        onSelect(room.id);
        return;
      }
    }
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

class _AnalysisOverlayPainter extends CustomPainter {
  _AnalysisOverlayPainter({
    required this.result,
    required this.transform,
    required this.selectedIds,
  });

  final FloorPlanAnalysisResult result;
  final ContainFitTransform transform;
  final Set<String> selectedIds;

  @override
  void paint(Canvas canvas, Size size) {
    for (final room in result.rooms) {
      final selected = selectedIds.contains(room.id);
      final path = Path()
        ..addPolygon(room.polygon.map(transform.mapNormalized).toList(), true);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.fill
          ..color = SpaceShiftColors.selectionAccent.withValues(
            alpha: selected ? 0.16 : 0.06,
          ),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2 : 1
          ..color = SpaceShiftColors.selectionAccent.withValues(alpha: 0.5),
      );
    }

    final referenceDim = math.max(transform.rect.width, transform.rect.height);
    for (final wall in result.walls) {
      final selected = selectedIds.contains(wall.id);
      final p1 = transform.mapNormalized(wall.start);
      final p2 = transform.mapNormalized(wall.end);
      final strokeWidth = math.max(
        2.0,
        wall.thicknessNormalized * referenceDim,
      );
      canvas.drawLine(
        p1,
        p2,
        Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = selected ? strokeWidth + 2 : strokeWidth
          ..color = selected
              ? SpaceShiftColors.selectionAccent
              : (wall.isExterior
                        ? SpaceShiftColors.textPrimary
                        : SpaceShiftColors.textSecondary)
                    .withValues(alpha: 0.8),
      );
    }

    for (final opening in result.openings) {
      final selected = selectedIds.contains(opening.id);
      final center = transform.mapNormalized(opening.center);
      final radius = selected ? 8.0 : 6.0;
      final color = opening.status == FloorPlanObjectStatus.needsReview
          ? const Color(0xFFF59E0B)
          : SpaceShiftColors.selectionAccent;
      canvas.drawCircle(center, radius, Paint()..color = color);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AnalysisOverlayPainter oldDelegate) {
    return oldDelegate.result != result ||
        !setEquals(oldDelegate.selectedIds, selectedIds) ||
        oldDelegate.transform.rect != transform.rect;
  }
}
