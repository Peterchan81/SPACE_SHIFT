import 'package:flutter/material.dart';

import '../../models/cad_floor_plan.dart';
import '../../models/floor_plan_geometry.dart';
import '../../models/ss_spatial_model.dart';
import '../../models/vision_understanding.dart';
import '../../services/e2e_dxf_exporter.dart';
import '../../services/e2e_geometry_solver.dart';
import 'vision_cad_proposal.dart';

/// SPACE SHIFT — Image 2 AI → Real CAD End-to-End POC 비교 화면.
///
/// 왼쪽: 실제 원본 이미지 2 (BLOCKED — 파일시스템에서 찾을 수 없음,
/// 합성 이미지로 대체하지 않는다는 사용자 지시를 그대로 따른다).
/// 가운데: Vision Proposal(연한 선 — 정리 전).
/// 오른쪽: Final SS CAD(명확한 선 — [SSGeometrySolver] + 기존
/// [TopologyValidator]를 거친 뒤 [buildCadFloorPlanFromSpatialModel]로
/// 만든, 화면과 DXF가 반드시 공유하는 바로 그 Canonical CAD Model).
class Image2E2eScreen extends StatefulWidget {
  const Image2E2eScreen({super.key});

  @override
  State<Image2E2eScreen> createState() => _Image2E2eScreenState();
}

class _Image2E2eScreenState extends State<Image2E2eScreen> {
  late final VisionUnderstanding _proposal = buildImage2VisionProposal();
  late final SSGeometrySolverResult _solverResult = const SSGeometrySolver().solve(_proposal);
  late final CadFloorPlan _cad = buildCadFloorPlanFromSpatialModel(_solverResult.model);

  String? _selectedWallId;
  final _mmController = TextEditingController();
  FloorPlanScale? _scale;
  String? _calibrationError;

  @override
  void dispose() {
    _mmController.dispose();
    super.dispose();
  }

  void _applyCalibration() {
    final wallId = _selectedWallId;
    final mm = double.tryParse(_mmController.text);
    if (wallId == null || mm == null || mm <= 0) {
      setState(() => _calibrationError = '벽과 유효한 mm 값을 입력하세요.');
      return;
    }
    final wall = _cad.walls.firstWhere((w) => w.id == wallId);
    final pxLen = _cad.pixelDistance(wall.start, wall.end);
    if (pxLen <= 0) {
      setState(() => _calibrationError = '선택한 벽의 길이를 계산할 수 없습니다.');
      return;
    }
    setState(() {
      _scale = FloorPlanScale(
        mmPerPixel: mm / pxLen,
        referenceStart: wall.start,
        referenceEnd: wall.end,
        referenceLengthMm: mm,
      );
      _calibrationError = null;
    });
  }

  void _showDxfPreview() {
    final result = const E2eDxfExporter().export(_cad, scale: _scale);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('DXF Export Preview — ${result.notice}'),
        content: SizedBox(
          width: 600,
          height: 500,
          child: SingleChildScrollView(
            child: SelectableText(result.dxfContent, style: const TextStyle(fontFamily: 'monospace', fontSize: 10)),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final model = _solverResult.model;
    final doorCount = _cad.openings.where((o) => o.type == OpeningType.door).length;
    final windowCount = _cad.openings.where((o) => o.type == OpeningType.window).length;
    final reviewCount = model.spaces.where((s) => s.reviewNeeded).length +
        model.walls.where((w) => w.reviewNeeded).length +
        model.openings.where((o) => o.reviewNeeded).length;
    final topologyIssues = model.warnings.length;

    return Scaffold(
      appBar: AppBar(title: const Text('SPACE SHIFT — Image 2 AI → Real CAD E2E POC (독립, production 미연결)')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatusBar(
              spaceCount: _cad.rooms.length,
              wallCount: _cad.walls.length,
              doorCount: doorCount,
              windowCount: windowCount,
              topologyIssues: topologyIssues,
              reviewCount: reviewCount,
              scale: _scale,
              onExportDxf: _showDxfPreview,
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _BlockedActualImagePanel()),
                  Expanded(
                    child: _Panel(
                      title: 'VISION PROPOSAL (정리 전, 연한 선)',
                      child: CustomPaint(painter: _ProposalPainter(_proposal), size: Size.infinite),
                    ),
                  ),
                  Expanded(
                    child: _Panel(
                      title: 'FINAL SS CAD (Solver + Topology Validator 적용됨)',
                      child: CustomPaint(painter: _CadPainter(_cad, model), size: Size.infinite),
                    ),
                  ),
                ],
              ),
            ),
            _CalibrationBar(
              cad: _cad,
              selectedWallId: _selectedWallId,
              mmController: _mmController,
              error: _calibrationError,
              scale: _scale,
              onWallSelected: (id) => setState(() => _selectedWallId = id),
              onApply: _applyCalibration,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.spaceCount,
    required this.wallCount,
    required this.doorCount,
    required this.windowCount,
    required this.topologyIssues,
    required this.reviewCount,
    required this.scale,
    required this.onExportDxf,
  });

  final int spaceCount;
  final int wallCount;
  final int doorCount;
  final int windowCount;
  final int topologyIssues;
  final int reviewCount;
  final FloorPlanScale? scale;
  final VoidCallback onExportDxf;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
    );

    return Container(
      width: double.infinity,
      color: const Color(0xFFF5F5F5),
      padding: const EdgeInsets.all(10),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          chip('SPACES $spaceCount', Colors.blue),
          chip('WALLS $wallCount', Colors.black87),
          chip('DOORS $doorCount', Colors.green),
          chip('WINDOWS $windowCount', Colors.teal),
          chip(scale == null ? 'SCALE: UNKNOWN' : 'SCALE: ${scale!.source.label}', scale == null ? Colors.orange : Colors.green),
          chip('TOPOLOGY NOTES $topologyIssues', topologyIssues > 0 ? Colors.deepOrange : Colors.green),
          chip('REVIEW NEEDED $reviewCount', reviewCount > 0 ? Colors.deepOrange : Colors.green),
          ElevatedButton(onPressed: onExportDxf, child: const Text('DXF Export Preview')),
        ],
      ),
    );
  }
}

class _CalibrationBar extends StatelessWidget {
  const _CalibrationBar({
    required this.cad,
    required this.selectedWallId,
    required this.mmController,
    required this.error,
    required this.scale,
    required this.onWallSelected,
    required this.onApply,
  });

  final CadFloorPlan cad;
  final String? selectedWallId;
  final TextEditingController mmController;
  final String? error;
  final FloorPlanScale? scale;
  final ValueChanged<String?> onWallSelected;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFFF8E1),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '축척 미확정 — 실제 길이 1곳을 입력하면 전체 도면의 길이와 면적을 보정할 수 있습니다. '
            '(POC 테스트용 — 4000mm 등 기본값을 미리 채워 넣지 않습니다.)',
            style: TextStyle(fontSize: 11, color: Colors.black54),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: selectedWallId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '기준 벽 선택', isDense: true),
                  items: [
                    for (final w in cad.walls)
                      DropdownMenuItem(value: w.id, child: Text(w.id, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: onWallSelected,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 160,
                child: TextField(
                  controller: mmController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '실제 길이 (mm)', isDense: true),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(onPressed: onApply, child: const Text('적용')),
              if (scale != null) ...[
                const SizedBox(width: 12),
                Text('mmPerPixel=${scale!.mmPerPixel.toStringAsFixed(4)}', style: const TextStyle(fontSize: 11)),
              ],
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(error!, style: const TextStyle(color: Colors.red, fontSize: 11)),
            ),
        ],
      ),
    );
  }
}

class _BlockedActualImagePanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'ACTUAL ORIGINAL IMAGE 2',
      child: Container(
        color: const Color(0xFFFFEBEE),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.block, color: Colors.red, size: 48),
            SizedBox(height: 12),
            Text(
              'ACTUAL IMAGE 2: BLOCKED',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            SizedBox(height: 8),
            Text(
              '실제 사용자 원본 이미지 파일을 이 PC의 파일시스템에서 찾을 수 없습니다.\n'
              '채팅에 첨부된 이미지의 원본 바이트를 파일로 추출할 도구가 없습니다.\n'
              '합성 이미지로 대체하지 않았습니다(사용자 지시).',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
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
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 6),
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

({double minX, double maxX, double minY, double maxY}) _sharedViewBox() {
  final proposal = buildImage2VisionProposal();
  final points = <NormalizedPoint>[
    ...?proposal.floorDomain.geometryHint?.allPoints,
  ];
  final minX = points.map((p) => p.x).reduce((a, b) => a < b ? a : b) - 0.03;
  final maxX = points.map((p) => p.x).reduce((a, b) => a > b ? a : b) + 0.03;
  final minY = points.map((p) => p.y).reduce((a, b) => a < b ? a : b) - 0.03;
  final maxY = points.map((p) => p.y).reduce((a, b) => a > b ? a : b) + 0.03;
  return (minX: minX, maxX: maxX, minY: minY, maxY: maxY);
}

Offset _toCanvas(double x, double y, Size size, ({double minX, double maxX, double minY, double maxY}) box) {
  final nx = (x - box.minX) / (box.maxX - box.minX);
  final ny = (y - box.minY) / (box.maxY - box.minY);
  return Offset(nx * size.width, ny * size.height);
}

class _ProposalPainter extends CustomPainter {
  _ProposalPainter(this.proposal);
  final VisionUnderstanding proposal;

  @override
  void paint(Canvas canvas, Size size) {
    final box = _sharedViewBox();

    final domainPaint = Paint()
      ..color = Colors.grey.shade400
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final domainPoints = proposal.floorDomain.geometryHint?.points ?? const [];
    if (domainPoints.isNotEmpty) {
      final path = Path()..addPolygon([for (final p in domainPoints) _toCanvas(p.x, p.y, size, box)], true);
      canvas.drawPath(path, domainPaint);
    }

    final spaceFill = Paint()
      ..color = Colors.blue.withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;
    final spaceStroke = Paint()
      ..color = Colors.blue.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    for (final space in proposal.spaces) {
      final points = space.geometryHint?.points ?? const [];
      if (points.isEmpty) continue;
      final path = Path()..addPolygon([for (final p in points) _toCanvas(p.x, p.y, size, box)], true);
      canvas.drawPath(path, spaceFill);
      canvas.drawPath(path, spaceStroke);
    }

    final wallPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (final boundary in proposal.boundaries) {
      final hint = boundary.geometryHint;
      if (hint == null || hint.kind != GeometryHintKind.segment) continue;
      canvas.drawLine(
        _toCanvas(hint.start.x, hint.start.y, size, box),
        _toCanvas(hint.end.x, hint.end.y, size, box),
        wallPaint,
      );
    }

    for (final opening in proposal.openings) {
      final hint = opening.geometryHint;
      if (hint == null) continue;
      final point = hint.kind == GeometryHintKind.point ? hint.point : hint.allPoints.first;
      final color = switch (opening.openingType) {
        VisionOpeningType.door => Colors.green.withValues(alpha: 0.5),
        VisionOpeningType.window => Colors.teal.withValues(alpha: 0.5),
        VisionOpeningType.openPassage => Colors.orange.withValues(alpha: 0.5),
      };
      canvas.drawCircle(_toCanvas(point.x, point.y, size, box), 3, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _ProposalPainter oldDelegate) => false;
}

class _CadPainter extends CustomPainter {
  _CadPainter(this.cad, this.model);
  final CadFloorPlan cad;
  final SSSpatialModel model;

  @override
  void paint(Canvas canvas, Size size) {
    final box = _sharedViewBox();
    final reviewSpaceIds = model.spaces.where((s) => s.reviewNeeded).map((s) => s.id).toSet();
    final reviewWallIds = model.walls.where((w) => w.reviewNeeded).map((w) => w.id).toSet();
    final reviewOpeningIds = model.openings.where((o) => o.reviewNeeded).map((o) => o.id).toSet();

    if (model.floorDomain != null) {
      final path = Path()
        ..addPolygon([for (final p in model.floorDomain!) _toCanvas(p.x, p.y, size, box)], true);
      canvas.drawPath(path, Paint()..color = Colors.black87..style = PaintingStyle.stroke..strokeWidth = 2.5);
    }

    for (var i = 0; i < cad.rooms.length; i++) {
      final room = cad.rooms[i];
      final flagged = reviewSpaceIds.contains(room.id);
      final path = Path()..addPolygon([for (final p in room.polygon) _toCanvas(p.x, p.y, size, box)], true);
      canvas.drawPath(path, Paint()..color = (flagged ? Colors.orange : Colors.lightBlue).withValues(alpha: 0.15));
      canvas.drawPath(path, Paint()..color = flagged ? Colors.orange : Colors.blueGrey..style = PaintingStyle.stroke..strokeWidth = 1);

      final centroid = _centroid(room.polygon);
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${i + 1}. ${room.name ?? "공간 ${i + 1}"}',
          style: const TextStyle(color: Colors.black87, fontSize: 10, fontWeight: FontWeight.w700),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final c = _toCanvas(centroid.x, centroid.y, size, box);
      textPainter.paint(canvas, Offset(c.dx - textPainter.width / 2, c.dy - textPainter.height / 2));
    }

    for (final wall in cad.walls) {
      final flagged = reviewWallIds.contains(wall.id);
      canvas.drawLine(
        _toCanvas(wall.start.x, wall.start.y, size, box),
        _toCanvas(wall.end.x, wall.end.y, size, box),
        Paint()
          ..color = flagged ? Colors.deepOrange : Colors.black
          ..strokeWidth = wall.wallType == CadWallType.exterior ? 3.5 : 2,
      );
    }

    for (final opening in cad.openings) {
      final flagged = reviewOpeningIds.contains(opening.id);
      final color = flagged
          ? Colors.deepOrange
          : (opening.type == OpeningType.door ? Colors.green : Colors.teal);
      canvas.drawCircle(_toCanvas(opening.center.x, opening.center.y, size, box), 4, Paint()..color = color);
    }
  }

  ({double x, double y}) _centroid(List<Point2> polygon) {
    var sx = 0.0, sy = 0.0;
    for (final p in polygon) {
      sx += p.x;
      sy += p.y;
    }
    return (x: sx / polygon.length, y: sy / polygon.length);
  }

  @override
  bool shouldRepaint(covariant _CadPainter oldDelegate) => false;
}
