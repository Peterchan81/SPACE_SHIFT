import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/cad_floor_plan.dart';
import '../models/floor_plan_geometry.dart';
import '../models/ss_spatial_model.dart';

/// Vision Guided CAD POC — "Original ↔ Vision Guided CAD" 비교 화면
/// 본체. Production 화면([floor_plan_preview.dart]/[space_3d_view.dart]
/// 등)을 재사용하지 않고 이 POC 전용으로 새로 그린다 — production
/// pipeline과 완전히 분리한다(WO 절대 금지 — 기존 렌더러를 건드리지
/// 않는다).
///
/// 화면에 그리는 [CadFloorPlan]은 [SSSpatialModel]을
/// `buildCadFloorPlanFromSpatialModel`로 변환한 바로 그 결과다 — 화면
/// 전용의 별도 geometry를 새로 만들지 않는다(WO 절대 금지 8번).
/// [spatialModel]은 오직 reviewNeeded/제외된 항목 등 CadFloorPlan이
/// 담지 못하는 진단 정보를 보여주기 위해 함께 전달한다.
class VisionCadPreview extends StatelessWidget {
  const VisionCadPreview({
    super.key,
    required this.originalImageBytes,
    required this.cad,
    required this.spatialModel,
  });

  final List<int> originalImageBytes;
  final CadFloorPlan cad;
  final SSSpatialModel spatialModel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SummaryBar(cad: cad, spatialModel: spatialModel),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 900;
              final panels = [
                Expanded(
                  child: _Panel(
                    title: 'Original (합성 이미지 2)',
                    child: Image.memory(
                      Uint8List.fromList(originalImageBytes),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                Expanded(
                  child: _Panel(
                    title: 'Vision Guided CAD',
                    child: AspectRatio(
                      aspectRatio: cad.sourceWidthPx / cad.sourceHeightPx,
                      child: CustomPaint(painter: _CadPainter(cad, spatialModel)),
                    ),
                  ),
                ),
              ];
              return wide
                  ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: panels)
                  : Column(children: panels);
            },
          ),
        ),
        _ReviewPanel(spatialModel: spatialModel),
      ],
    );
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.cad, required this.spatialModel});

  final CadFloorPlan cad;
  final SSSpatialModel spatialModel;

  @override
  Widget build(BuildContext context) {
    final reviewCount =
        spatialModel.spaces.where((s) => s.reviewNeeded).length +
        spatialModel.walls.where((w) => w.reviewNeeded).length +
        spatialModel.openings.where((o) => o.reviewNeeded).length;
    return Container(
      color: const Color(0xFFF5F5F5),
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _chip('SPACE ${cad.rooms.length}', Colors.blue),
          _chip('WALL ${cad.walls.length}', Colors.black87),
          _chip('OPENING ${cad.openings.length}', Colors.green),
          _chip('축척 미확정 (scale unknown)', Colors.orange),
          if (reviewCount > 0) _chip('REVIEW NEEDED $reviewCount', Colors.deepOrange),
          if (spatialModel.warnings.isNotEmpty) _chip('WARNINGS ${spatialModel.warnings.length}', Colors.red),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              decoration: BoxDecoration(border: Border.all(color: Colors.black26)),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewPanel extends StatelessWidget {
  const _ReviewPanel({required this.spatialModel});

  final SSSpatialModel spatialModel;

  @override
  Widget build(BuildContext context) {
    final lines = <String>[
      for (final s in spatialModel.spaces)
        if (s.reviewNeeded) 'SPACE ${s.label ?? s.id}: ${s.reviewReasons.join(' / ')}',
      for (final w in spatialModel.walls)
        if (w.reviewNeeded) 'WALL ${w.id}: ${w.reviewReasons.join(' / ')}',
      for (final o in spatialModel.openings)
        if (o.reviewNeeded) 'OPENING ${o.id}: ${o.reviewReasons.join(' / ')}',
      for (final warning in spatialModel.warnings) 'EXCLUDED/NOTE: $warning',
    ];
    if (lines.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      constraints: const BoxConstraints(maxHeight: 160),
      color: const Color(0xFFFFF8E1),
      padding: const EdgeInsets.all(8),
      child: ListView(
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(line, style: const TextStyle(fontSize: 11)),
            ),
        ],
      ),
    );
  }
}

class _CadPainter extends CustomPainter {
  _CadPainter(this.cad, this.spatialModel);

  final CadFloorPlan cad;
  final SSSpatialModel spatialModel;

  @override
  void paint(Canvas canvas, Size size) {
    final reviewSpaceIds = spatialModel.spaces.where((s) => s.reviewNeeded).map((s) => s.id).toSet();
    final reviewWallIds = spatialModel.walls.where((w) => w.reviewNeeded).map((w) => w.id).toSet();
    final reviewOpeningIds = spatialModel.openings.where((o) => o.reviewNeeded).map((o) => o.id).toSet();

    final roomFill = Paint()..style = PaintingStyle.fill;
    final roomStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final room in cad.rooms) {
      final path = Path()..addPolygon([for (final p in room.polygon) Offset(p.x * size.width, p.y * size.height)], true);
      final flagged = reviewSpaceIds.contains(room.id);
      roomFill.color = (flagged ? Colors.orange : Colors.lightBlue).withValues(alpha: 0.18);
      roomStroke.color = flagged ? Colors.orange : Colors.blueGrey;
      canvas.drawPath(path, roomFill);
      canvas.drawPath(path, roomStroke);

      final centroid = _centroid(room.polygon);
      final textPainter = TextPainter(
        text: TextSpan(
          text: room.name ?? room.id,
          style: const TextStyle(color: Colors.black87, fontSize: 11, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(centroid.x * size.width - textPainter.width / 2, centroid.y * size.height - textPainter.height / 2),
      );
    }

    final wallPaint = Paint()..style = PaintingStyle.stroke;
    for (final wall in cad.walls) {
      final flagged = reviewWallIds.contains(wall.id);
      wallPaint.color = flagged ? Colors.deepOrange : Colors.black;
      wallPaint.strokeWidth = wall.wallType == CadWallType.exterior ? 4 : 2.5;
      canvas.drawLine(
        Offset(wall.start.x * size.width, wall.start.y * size.height),
        Offset(wall.end.x * size.width, wall.end.y * size.height),
        wallPaint,
      );
    }

    final openingPaint = Paint()..style = PaintingStyle.fill;
    for (final opening in cad.openings) {
      final flagged = reviewOpeningIds.contains(opening.id);
      openingPaint.color = flagged
          ? Colors.deepOrange
          : (opening.type == OpeningType.door ? Colors.green : Colors.blue);
      canvas.drawCircle(
        Offset(opening.center.x * size.width, opening.center.y * size.height),
        5,
        openingPaint,
      );
    }
  }

  ({double x, double y}) _centroid(List<dynamic> polygon) {
    var sx = 0.0, sy = 0.0;
    for (final p in polygon) {
      sx += p.x as double;
      sy += p.y as double;
    }
    return (x: sx / polygon.length, y: sy / polygon.length);
  }

  @override
  bool shouldRepaint(covariant _CadPainter oldDelegate) => oldDelegate.cad != cad;
}
