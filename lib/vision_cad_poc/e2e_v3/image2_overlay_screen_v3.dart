import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/cad_floor_plan.dart';
import '../../models/floor_plan_geometry.dart';
import '../../models/ss_spatial_model.dart';
import '../../services/vision_guided_spatial_model_builder.dart';
import '../e2e_v2/real_image2_source.dart';
import 'detailed_proposal_vision_service_v3.dart';
import 'image2_quality_metrics.dart';
import 'vision_cad_proposal_v3.dart';

enum _ViewMode { original, finalCad, overlay }

/// SPACE SHIFT — Image 2 GPT Direct CAD Geometry Proposal Benchmark 화면.
///
/// v2(e2e_v2) 대비: 기본 표시가 BLACK/ORIGINAL + FINAL WALL CENTER +
/// FLOOR DOMAIN + CORNERS이고, Spaces/Doors/Windows는 toggle이다(이번
/// 지시 14번). 우측에 품질 지표(mean/max delta, confidence 분포,
/// unmatched)를 함께 보여준다(이번 지시 15번).
class Image2OverlayScreenV3 extends StatefulWidget {
  const Image2OverlayScreenV3({super.key});

  @override
  State<Image2OverlayScreenV3> createState() => _Image2OverlayScreenV3State();
}

class _Image2OverlayScreenV3State extends State<Image2OverlayScreenV3> {
  final Uint8List? _realImageBytes = loadRealImage2Bytes();
  _ViewMode _mode = _ViewMode.overlay;

  bool _showFloorDomain = true;
  bool _showWalls = true;
  bool _showCorners = true;
  bool _showSpaces = false;
  bool _showOpenings = false;

  late final Future<
      ({SSSpatialModel model, CadFloorPlan cad, Image2QualityMetrics metrics})>? _future =
      _realImageBytes == null ? null : _run(_realImageBytes);

  Future<({SSSpatialModel model, CadFloorPlan cad, Image2QualityMetrics metrics})> _run(
    Uint8List bytes,
  ) async {
    final builder = VisionGuidedSpatialModelBuilder(visionService: const DetailedProposalVisionServiceV3());
    final model = await builder.build(bytes);
    final cad = buildCadFloorPlanFromSpatialModel(model);
    final metrics = const Image2QualityMetricsComputer().compute(buildImage2VisionProposalV3(), bytes);
    return (model: model, cad: cad, metrics: metrics);
  }

  @override
  Widget build(BuildContext context) {
    if (_realImageBytes == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('SPACE SHIFT — Image 2 GPT Direct CAD Geometry Proposal Benchmark')),
        body: const _BlockedPanel(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('SPACE SHIFT — Image 2 GPT Direct CAD Geometry Proposal Benchmark (독립, production 미연결)'),
      ),
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
                  showCorners: _showCorners,
                  showSpaces: _showSpaces,
                  showOpenings: _showOpenings,
                  onToggle: (key, value) => setState(() {
                    switch (key) {
                      case 'floorDomain':
                        _showFloorDomain = value;
                      case 'walls':
                        _showWalls = value;
                      case 'corners':
                        _showCorners = value;
                      case 'spaces':
                        _showSpaces = value;
                      case 'openings':
                        _showOpenings = value;
                    }
                  }),
                ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
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
                                        showCorners: _showCorners,
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
                      Expanded(flex: 2, child: _QualityPanel(metrics: result.metrics, model: result.model)),
                    ],
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
          const Text('GPT DIRECT GEOMETRY → SS CAD: BLOCKED — ACTUAL SOURCE FILE REQUIRED',
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
          chip('SPACES ${cad.rooms.length}/13', cad.rooms.length >= 13 ? Colors.green : Colors.orange),
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
    required this.showCorners,
    required this.showSpaces,
    required this.showOpenings,
    required this.onToggle,
  });

  final _ViewMode mode;
  final ValueChanged<_ViewMode> onModeChanged;
  final bool showFloorDomain;
  final bool showWalls;
  final bool showCorners;
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
          FilterChip(label: const Text('Wall center'), selected: showWalls, onSelected: (v) => onToggle('walls', v)),
          FilterChip(label: const Text('Corners'), selected: showCorners, onSelected: (v) => onToggle('corners', v)),
          FilterChip(label: const Text('Spaces'), selected: showSpaces, onSelected: (v) => onToggle('spaces', v)),
          FilterChip(label: const Text('Doors/Windows'), selected: showOpenings, onSelected: (v) => onToggle('openings', v)),
        ],
      ),
    );
  }
}

class _QualityPanel extends StatelessWidget {
  const _QualityPanel({required this.metrics, required this.model});
  final Image2QualityMetrics metrics;
  final SSSpatialModel model;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFFAFAFA),
      padding: const EdgeInsets.all(12),
      child: ListView(
        children: [
          const Text('품질 지표 (proposal → 실제 픽셀 refine)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          Text('mean delta: ${metrics.meanDeltaPx.toStringAsFixed(1)}px'),
          Text('max delta: ${metrics.maxDeltaPx.toStringAsFixed(1)}px'),
          Text('HIGH: ${metrics.highCount}   MEDIUM: ${metrics.mediumCount}   LOW: ${metrics.lowCount}'),
          Text('unmatched: ${metrics.unmatchedCount}'),
          const Divider(height: 24),
          const Text('벽별 delta', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          for (final m in metrics.wallMetrics)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '${m.boundaryId}: ${m.found ? "${m.deltaPx!.toStringAsFixed(1)}px (${m.geometryConfidence?.name})" : "not found"}',
                style: const TextStyle(fontSize: 10),
              ),
            ),
          const Divider(height: 24),
          const Text('review needed', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          for (final s in model.spaces)
            if (s.reviewNeeded)
              Text('SPACE ${s.label ?? s.id}: ${s.reviewReasons.join(" / ")}', style: const TextStyle(fontSize: 10)),
          for (final w in model.walls)
            if (w.reviewNeeded) Text('WALL ${w.id}: ${w.reviewReasons.join(" / ")}', style: const TextStyle(fontSize: 10)),
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
    required this.showCorners,
    required this.showSpaces,
    required this.showOpenings,
  });

  final CadFloorPlan cad;
  final SSSpatialModel model;
  final bool dimOriginal;
  final bool showFloorDomain;
  final bool showWalls;
  final bool showCorners;
  final bool showSpaces;
  final bool showOpenings;

  @override
  void paint(Canvas canvas, Size size) {
    final reviewWallIds = model.walls.where((w) => w.reviewNeeded).map((w) => w.id).toSet();
    final reviewSpaceIds = model.spaces.where((s) => s.reviewNeeded).map((s) => s.id).toSet();
    final alpha = dimOriginal ? 0.9 : 1.0;

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
        canvas.drawPath(path, Paint()..color = (flagged ? Colors.orange : Colors.lightBlue).withValues(alpha: 0.2));
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

    if (showCorners) {
      final corners = <Offset>{};
      for (final wall in cad.walls) {
        corners.add(Offset(wall.start.x * size.width, wall.start.y * size.height));
        corners.add(Offset(wall.end.x * size.width, wall.end.y * size.height));
      }
      final cornerPaint = Paint()..color = Colors.blue.withValues(alpha: alpha);
      for (final c in corners) {
        canvas.drawCircle(c, 3.5, cornerPaint);
      }
    }

    if (showOpenings) {
      for (final opening in cad.openings) {
        final color = opening.type == OpeningType.door ? Colors.green : Colors.cyan;
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
