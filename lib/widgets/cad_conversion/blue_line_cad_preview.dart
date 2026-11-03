/// SS010 — MASTER UI 7 "Blue line-only CAD" 진행 화면 미리보기. 가구/텍스트/바닥색 없이 벽(외벽
/// 굵게·내벽 얇게)·문/창 기호·공간 번호만 네온 블루 선으로 그린다. [CleanCadPreview](POC 전용, 별도
/// 모델)와 "선만 그린다"는 생각은 같지만, 이 위젯은 production [CadFloorPlan]/[FloorPlanScale]을
/// 그대로 입력으로 받는다 — 화면 전용 geometry를 새로 만들지 않는다(§구현 원칙 "기존 엔진 재사용").
library;

import 'package:flutter/material.dart';

import '../../models/cad_floor_plan.dart';
import '../../models/floor_plan_geometry.dart';
import '../../theme/ss_master_theme.dart';

class BlueLineCadPreview extends StatelessWidget {
  const BlueLineCadPreview({super.key, required this.plan, this.scale});

  final CadFloorPlan plan;
  final FloorPlanScale? scale;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Text(
            _dimensionLabel(),
            key: const Key('ssCadConversionDimensionLabel'),
            style: const TextStyle(color: SsMasterTheme.neonCyan, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: CustomPaint(painter: _BlueLineCadPainter(plan), size: Size.infinite),
          ),
        ),
      ],
    );
  }

  String _dimensionLabel() {
    final s = scale;
    if (s == null || !s.source.isReliable) return '전체 크기 — 추정값(실측 전)';
    final widthMm = plan.sourceWidthPx * s.mmPerPixel;
    final heightMm = plan.sourceHeightPx * s.mmPerPixel;
    return '전체 ${widthMm.round()} x ${heightMm.round()} mm';
  }
}

class _BlueLineCadPainter extends CustomPainter {
  _BlueLineCadPainter(this.plan);

  final CadFloorPlan plan;

  @override
  void paint(Canvas canvas, Size size) {
    const padding = 20.0;
    final availableW = size.width - padding * 2;
    final availableH = size.height - padding * 2;
    if (availableW <= 0 || availableH <= 0) return;
    final scaleFactor = availableW < availableH ? availableW : availableH;
    final offsetX = padding + (availableW - scaleFactor) / 2;
    final offsetY = padding + (availableH - scaleFactor) / 2;

    Offset toScreen(Point2 p) => Offset(offsetX + p.x * scaleFactor, offsetY + p.y * scaleFactor);

    final roomPaint = Paint()
      ..color = SsMasterTheme.neonBlue.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final room in plan.rooms) {
      if (room.polygon.length < 2) continue;
      final first = toScreen(room.polygon.first);
      final path = Path()..moveTo(first.dx, first.dy);
      for (final p in room.polygon.skip(1)) {
        final o = toScreen(p);
        path.lineTo(o.dx, o.dy);
      }
      path.close();
      canvas.drawPath(path, roomPaint);
    }

    final exteriorPaint = Paint()
      ..color = SsMasterTheme.neonCyan
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.square;
    final interiorPaint = Paint()
      ..color = SsMasterTheme.neonBlue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.square;
    for (final wall in plan.walls) {
      canvas.drawLine(
        toScreen(wall.start),
        toScreen(wall.end),
        wall.wallType == CadWallType.exterior ? exteriorPaint : interiorPaint,
      );
    }

    final openingPaint = Paint()
      ..color = SsMasterTheme.neonCyan
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (final opening in plan.openings) {
      final center = toScreen(opening.center);
      if (opening.type == OpeningType.door) {
        canvas.drawArc(Rect.fromCircle(center: center, radius: 8), 0, 1.57, false, openingPaint);
      } else {
        canvas.drawLine(center.translate(-5, -3), center.translate(5, 3), openingPaint);
        canvas.drawLine(center.translate(-5, 3), center.translate(5, -3), openingPaint);
      }
    }

    for (var i = 0; i < plan.rooms.length; i++) {
      final room = plan.rooms[i];
      if (room.polygon.isEmpty) continue;
      var sx = 0.0, sy = 0.0;
      for (final p in room.polygon) {
        sx += p.x;
        sy += p.y;
      }
      final centroid = Point2(sx / room.polygon.length, sy / room.polygon.length);
      final screenCentroid = toScreen(centroid);
      final textPainter = TextPainter(
        text: TextSpan(
          text: displayRoomName(room, i),
          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, screenCentroid - Offset(textPainter.width / 2, textPainter.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _BlueLineCadPainter oldDelegate) => true;
}
