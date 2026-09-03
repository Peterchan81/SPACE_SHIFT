import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/cad_floor_plan.dart';
import '../../models/floor_plan_geometry.dart';
import '../../models/ss_spatial_model.dart';
import '../../services/vision_guided_spatial_model_builder.dart';
import 'detailed_proposal_vision_service.dart';
import 'real_image2_source.dart';

enum _ViewMode { original, finalCad, overlay }

/// SPACE SHIFT — Image 2 GPT Detailed CAD Geometry POC 비교 화면.
///
/// ORIGINAL / FINAL CAD / OVERLAY 세 모드를 제공한다. Overlay 모드는
/// 실제 원본 이미지 위에 FloorDomain/벽/공간 경계/문/창을 겹쳐 그려서,
/// SS가 실제 픽셀에서 얼마나 정확히 geometry를 재구성했는지 육안으로
/// 바로 비교할 수 있게 한다.
class Image2OverlayScreen extends StatefulWidget {
  const Image2OverlayScreen({super.key});

  @override
  State<Image2OverlayScreen> createState() => _Image2OverlayScreenState();
}

class _Image2OverlayScreenState extends State<Image2OverlayScreen> {
  final Uint8List? _realImageBytes = loadRealImage2Bytes();
  _ViewMode _mode = _ViewMode.overlay;

  bool _showFloorDomain = true;
  bool _showWalls = true;
  bool _showSpaces = true;
  bool _showOpenings = true;

  late final Future<({SSSpatialModel model, CadFloorPlan cad})>? _future = _realImageBytes == null
      ? null
      : _run(_realImageBytes);

  Future<({SSSpatialModel model, CadFloorPlan cad})> _run(Uint8List bytes) async {
    final builder = VisionGuidedSpatialModelBuilder(visionService: const DetailedProposalVisionService());
    final model = await builder.build(bytes);
    final cad = buildCadFloorPlanFromSpatialModel(model);
    return (model: model, cad: cad);
  }

  @override
  Widget build(BuildContext context) {
    if (_realImageBytes == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('SPACE SHIFT — Image 2 GPT Detailed CAD Geometry POC')),
        body: const _BlockedPanel(),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('SPACE SHIFT — Image 2 GPT Detailed CAD Geometry POC (독립, production 미연결)')),
      body: SafeArea(
        child: FutureBuilder(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('오류: ${snapshot.error}'));
            }
            final result = snapshot.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SourceBar(realBytes: _realImageBytes),
                _StatusBar(model: result.model, cad: result.cad),
                _ModeBar(
                  mode: _mode,
                  onModeChanged: (m) => setState(() => _mode = m),
                  showFloorDomain: _showFloorDomain,
                  showWalls: _showWalls,
                  showSpaces: _showSpaces,
                  showOpenings: _showOpenings,
                  onToggle: (key, value) => setState(() {
                    switch (key) {
                      case 'floorDomain':
                        _showFloorDomain = value;
                      case 'walls':
                        _showWalls = value;
                      case 'spaces':
                        _showSpaces = value;
                      case 'openings':
                        _showOpenings = value;
                    }
                  }),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: AspectRatio(
                      aspectRatio: result.cad.sourceWidthPx / result.cad.sourceHeightPx,
                      child: Container(
                        decoration: BoxDecoration(border: Border.all(color: Colors.black26)),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (_mode == _ViewMode.original || _mode == _ViewMode.overlay)
                              Image.memory(_realImageBytes, fit: BoxFit.fill),
                            if (_mode == _ViewMode.finalCad || _mode == _ViewMode.overlay)
                              CustomPaint(
                                painter: _CadOverlayPainter(
                                  cad: result.cad,
                                  model: result.model,
                                  dimOriginal: _mode == _ViewMode.overlay,
                                  showFloorDomain: _showFloorDomain,
                                  showWalls: _showWalls,
                                  showSpaces: _showSpaces,
                                  showOpenings: _showOpenings,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BlockedPanel extends StatelessWidget {
  const _BlockedPanel();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.block, color: Colors.red, size: 48),
          const SizedBox(height: 12),
          const Text('IMAGE 2 GPT DETAILED CAD POC: BLOCKED — ACTUAL SOURCE FILE REQUIRED',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          Text('찾던 경로: $kRealImage2Path', style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ],
      ),
    );
  }
}

class _SourceBar extends StatelessWidget {
  const _SourceBar({required this.realBytes});
  final Uint8List realBytes;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFE8F5E9),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(
        'SOURCE: ACTUAL IMAGE 2 (${realBytes.lengthInBytes} bytes, $kRealImage2Path)',
        style: const TextStyle(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.model, required this.cad});
  final SSSpatialModel model;
  final CadFloorPlan cad;

  @override
  Widget build(BuildContext context) {
    final doorCount = cad.openings.where((o) => o.type == OpeningType.door).length;
    final windowCount = cad.openings.where((o) => o.type == OpeningType.window).length;
    final reviewCount = model.spaces.where((s) => s.reviewNeeded).length +
        model.walls.where((w) => w.reviewNeeded).length +
        model.openings.where((o) => o.reviewNeeded).length;

    Widget chip(String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );

    return Container(
      width: double.infinity,
      color: const Color(0xFFF5F5F5),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Wrap(
        spacing: 10,
        runSpacing: 6,
        children: [
          chip('SPACES ${cad.rooms.length}', Colors.blue),
          chip('WALLS ${cad.walls.length}', Colors.black87),
          chip('DOORS $doorCount', Colors.green),
          chip('WINDOWS $windowCount', Colors.teal),
          chip('SCALE: UNKNOWN', Colors.orange),
          chip('TOPOLOGY NOTES ${model.warnings.length}', model.warnings.isNotEmpty ? Colors.deepOrange : Colors.green),
          chip('REVIEW NEEDED $reviewCount', reviewCount > 0 ? Colors.deepOrange : Colors.green),
        ],
      ),
    );
  }
}

class _ModeBar extends StatelessWidget {
  const _ModeBar({
    required this.mode,
    required this.onModeChanged,
    required this.showFloorDomain,
    required this.showWalls,
    required this.showSpaces,
    required this.showOpenings,
    required this.onToggle,
  });

  final _ViewMode mode;
  final ValueChanged<_ViewMode> onModeChanged;
  final bool showFloorDomain;
  final bool showWalls;
  final bool showSpaces;
  final bool showOpenings;
  final void Function(String key, bool value) onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SegmentedButton<_ViewMode>(
            segments: const [
              ButtonSegment(value: _ViewMode.original, label: Text('ORIGINAL')),
              ButtonSegment(value: _ViewMode.finalCad, label: Text('FINAL CAD')),
              ButtonSegment(value: _ViewMode.overlay, label: Text('OVERLAY')),
            ],
            selected: {mode},
            onSelectionChanged: (s) => onModeChanged(s.first),
          ),
          const SizedBox(width: 16),
          FilterChip(label: const Text('FloorDomain'), selected: showFloorDomain, onSelected: (v) => onToggle('floorDomain', v)),
          FilterChip(label: const Text('Walls'), selected: showWalls, onSelected: (v) => onToggle('walls', v)),
          FilterChip(label: const Text('Spaces'), selected: showSpaces, onSelected: (v) => onToggle('spaces', v)),
          FilterChip(label: const Text('Doors/Windows'), selected: showOpenings, onSelected: (v) => onToggle('openings', v)),
        ],
      ),
    );
  }
}

class _CadOverlayPainter extends CustomPainter {
  _CadOverlayPainter({
    required this.cad,
    required this.model,
    required this.dimOriginal,
    required this.showFloorDomain,
    required this.showWalls,
    required this.showSpaces,
    required this.showOpenings,
  });

  final CadFloorPlan cad;
  final SSSpatialModel model;
  final bool dimOriginal;
  final bool showFloorDomain;
  final bool showWalls;
  final bool showSpaces;
  final bool showOpenings;

  @override
  void paint(Canvas canvas, Size size) {
    final reviewSpaceIds = model.spaces.where((s) => s.reviewNeeded).map((s) => s.id).toSet();
    final reviewWallIds = model.walls.where((w) => w.reviewNeeded).map((w) => w.id).toSet();
    final reviewOpeningIds = model.openings.where((o) => o.reviewNeeded).map((o) => o.id).toSet();
    final alpha = dimOriginal ? 0.85 : 1.0;

    if (showFloorDomain && model.floorDomain != null) {
      final path = Path()..addPolygon([for (final p in model.floorDomain!) Offset(p.x * size.width, p.y * size.height)], true);
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.purple.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }

    if (showSpaces) {
      for (final room in cad.rooms) {
        final flagged = reviewSpaceIds.contains(room.id);
        final path = Path()..addPolygon([for (final p in room.polygon) Offset(p.x * size.width, p.y * size.height)], true);
        canvas.drawPath(
          path,
          Paint()
            ..color = (flagged ? Colors.orange : Colors.lightBlue).withValues(alpha: dimOriginal ? 0.15 : 0.3)
            ..style = PaintingStyle.fill,
        );
        canvas.drawPath(
          path,
          Paint()
            ..color = (flagged ? Colors.orange : Colors.blue).withValues(alpha: alpha)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
      }
    }

    if (showWalls) {
      for (final wall in cad.walls) {
        final flagged = reviewWallIds.contains(wall.id);
        canvas.drawLine(
          Offset(wall.start.x * size.width, wall.start.y * size.height),
          Offset(wall.end.x * size.width, wall.end.y * size.height),
          Paint()
            ..color = (flagged ? Colors.deepOrange : Colors.red).withValues(alpha: alpha)
            ..strokeWidth = wall.wallType == CadWallType.exterior ? 3 : 2,
        );
      }
    }

    if (showOpenings) {
      for (final opening in cad.openings) {
        final flagged = reviewOpeningIds.contains(opening.id);
        final color = flagged
            ? Colors.deepOrange
            : (opening.type == OpeningType.door ? Colors.green : Colors.cyan);
        canvas.drawCircle(
          Offset(opening.center.x * size.width, opening.center.y * size.height),
          4,
          Paint()..color = color.withValues(alpha: alpha),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CadOverlayPainter oldDelegate) => true;
}
