import 'package:flutter/material.dart';

import 'floorplan_semantic_model.dart';

/// POC 5단계 — "구조화된 결과를 이용해서 깨끗한 2D CAD preview 하나를
/// 만든다." 가구/텍스트/바닥색/그림자는 제외하고 외벽/내벽/문/창/구조
/// 객체/SPACE 번호만 그린다. 기존 SS CAD 오버레이([CadFloorPlanOverlay]
/// 등)를 재사용하지 않고 이 POC 전용으로 새로 그린다 — production
/// pipeline과 완전히 분리한다.
class CleanCadPreview extends StatelessWidget {
  const CleanCadPreview({super.key, required this.understanding});

  final FloorplanUnderstanding understanding;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: understanding.scaleConfirmed
                      ? const Color(0xFFE8F5E9)
                      : const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: understanding.scaleConfirmed
                        ? const Color(0xFF66BB6A)
                        : const Color(0xFFFFB74D),
                  ),
                ),
                child: Text(
                  understanding.scaleConfirmed ? '축척 확정' : '축척 미확정',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'SPACE ${understanding.spaces.length} · '
                'STRUCTURAL ${understanding.structuralObjects.length} · '
                'OPENING ${understanding.openings.length}',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: CustomPaint(
              painter: _CleanCadPainter(understanding),
              size: Size.infinite,
            ),
          ),
        ),
        if (understanding.notes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '이해 단계 메모(불확실성 정직 표시)',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                ),
                for (final note in understanding.notes)
                  Text(
                    '- $note',
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CleanCadPainter extends CustomPainter {
  _CleanCadPainter(this.understanding);

  final FloorplanUnderstanding understanding;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);

    final allPoints = <Pt>[
      ...understanding.floorDomain,
      for (final s in understanding.spaces) ...s.polygon,
    ];
    if (allPoints.isEmpty || size.width <= 0 || size.height <= 0) return;

    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final p in allPoints) {
      minX = minX < p.x ? minX : p.x;
      minY = minY < p.y ? minY : p.y;
      maxX = maxX > p.x ? maxX : p.x;
      maxY = maxY > p.y ? maxY : p.y;
    }
    final spanX = (maxX - minX).abs() < 1e-6 ? 1.0 : maxX - minX;
    final spanY = (maxY - minY).abs() < 1e-6 ? 1.0 : maxY - minY;
    const padding = 24.0;
    final scale = ((size.width - padding * 2) / spanX).clamp(
      0.0,
      (size.height - padding * 2) / spanY,
    );
    final offsetX = padding + (size.width - padding * 2 - spanX * scale) / 2;
    final offsetY = padding + (size.height - padding * 2 - spanY * scale) / 2;

    Offset toScreen(Pt p) =>
        Offset(offsetX + (p.x - minX) * scale, offsetY + (p.y - minY) * scale);

    Path polygonPath(List<Pt> polygon) {
      final path = Path();
      if (polygon.isEmpty) return path;
      final first = toScreen(polygon.first);
      path.moveTo(first.dx, first.dy);
      for (final p in polygon.skip(1)) {
        final o = toScreen(p);
        path.lineTo(o.dx, o.dy);
      }
      path.close();
      return path;
    }

    // SPACE 채움(아주 옅은 색) + 번호.
    final fillPaint = Paint()..color = const Color(0xFFF3F1EC);
    for (var i = 0; i < understanding.spaces.length; i++) {
      final space = understanding.spaces[i];
      canvas.drawPath(polygonPath(space.polygon), fillPaint);
    }

    // 구조 객체(계단 등) — 해칭 패턴으로만 표시, 색/그림자 없음.
    final structuralStroke = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final structural in understanding.structuralObjects) {
      final path = polygonPath(structural.polygon);
      canvas.drawPath(path, structuralStroke);
      _drawHatch(canvas, structural.polygon, toScreen, structuralStroke);
    }

    // Boundary(내벽/외벽) — 외벽은 굵게, 내벽은 얇게, virtual/unknown은
    // 점선으로 옅게(가구/텍스트/색은 절대 그리지 않는다).
    final exteriorPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.square;
    final interiorPaint = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.square;
    final virtualPaint = Paint()
      ..color = Colors.black26
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawPath(polygonPath(understanding.floorDomain), exteriorPaint);

    for (final boundary in understanding.boundaries) {
      if (boundary.geometry.length < 2) continue;
      final paint = switch (boundary.type) {
        BoundaryType.exteriorWall => exteriorPaint,
        BoundaryType.interiorWall => interiorPaint,
        BoundaryType.virtual || BoundaryType.unknown => virtualPaint,
      };
      final a = toScreen(boundary.geometry.first);
      final b = toScreen(boundary.geometry.last);
      canvas.drawLine(a, b, paint);
    }

    // Opening(문/창) — 표준 CAD 기호를 흉내낸 아주 단순한 표시(문=호,
    // 창=이중 틱). 가구/재질은 절대 표시하지 않는다.
    final openingPaint = Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final opening in understanding.openings) {
      final center = toScreen(opening.geometry);
      switch (opening.kind) {
        case OpeningKind.door:
          canvas.drawArc(
            Rect.fromCircle(center: center, radius: 10),
            0,
            1.57,
            false,
            openingPaint,
          );
        case OpeningKind.window:
          canvas.drawLine(
            center.translate(-6, -4),
            center.translate(6, 4),
            openingPaint,
          );
          canvas.drawLine(
            center.translate(-6, 4),
            center.translate(6, -4),
            openingPaint,
          );
        case OpeningKind.openPassage:
          canvas.drawCircle(center, 3, openingPaint);
      }
    }

    // SPACE 번호 배지 + 이름(있으면).
    for (var i = 0; i < understanding.spaces.length; i++) {
      final space = understanding.spaces[i];
      final centroid = _centroid(space.polygon);
      final screenCentroid = toScreen(centroid);
      final label = space.name ?? '공간 ${i + 1}';
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${i + 1}. $label',
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        screenCentroid - Offset(textPainter.width / 2, textPainter.height / 2),
      );
    }
  }

  void _drawHatch(
    Canvas canvas,
    List<Pt> polygon,
    Offset Function(Pt) toScreen,
    Paint paint,
  ) {
    if (polygon.length < 3) return;
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final p in polygon) {
      final o = toScreen(p);
      minX = minX < o.dx ? minX : o.dx;
      minY = minY < o.dy ? minY : o.dy;
      maxX = maxX > o.dx ? maxX : o.dx;
      maxY = maxY > o.dy ? maxY : o.dy;
    }
    const step = 6.0;
    for (var x = minX; x < maxX; x += step) {
      canvas.drawLine(Offset(x, minY), Offset(x, maxY), paint);
    }
  }

  Pt _centroid(List<Pt> polygon) {
    var sx = 0.0, sy = 0.0;
    for (final p in polygon) {
      sx += p.x;
      sy += p.y;
    }
    return Pt(sx / polygon.length, sy / polygon.length);
  }

  @override
  bool shouldRepaint(covariant _CleanCadPainter oldDelegate) => false;
}
