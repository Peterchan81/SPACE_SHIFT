// SPACE SHIFT — WO088-1 IMAGE 2 COORDINATE-BASED 2D STRUCTURE POC.
//
// §6/§11 — 원본 위에 좌표 기반 구조를 overlay하고, [원본]/[원본+Overlay]/
// [Coordinate Only] 3개 모드로 비교한다. CAD 렌더링 화면은 비교 대상이
// 아니다(§11) — CadFloorPlan을 이 파일 어디에서도 import하지 않는다.
//
// §9 최소 편집 — 벽을 탭해 선택한 뒤 삭제할 수 있고, "추가" 모드에서
// 두 점을 탭하면 새 벽이 userEdited로 추가된다(§9 "완전한 편집 UI가
// 과도하면 모델 + 최소 POC 편집만 구현" — corner 드래그 이동은 다음
// 단계로 남긴다).

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/floor_plan_geometry.dart';
import '../e2e_v2/real_image2_source.dart';
import '../pixel_wall_v4/pixel_wall_extractor.dart';
import '../pixel_wall_v4/virtual_cad_scale.dart';
import 'coord_real_scale.dart';
import 'coord_structure_model.dart';

enum CoordViewMode { original, overlay, coordinateOnly }

class CoordStructureScreen extends StatefulWidget {
  const CoordStructureScreen({super.key});

  @override
  State<CoordStructureScreen> createState() => _CoordStructureScreenState();
}

class _CoordStructureScreenState extends State<CoordStructureScreen> {
  final Uint8List? _bytes = loadRealImage2Bytes();
  late final PixelWallExtractionResult? _extraction = _buildExtraction();
  late CoordStructureModel? _model = _buildInitial();
  CoordViewMode _mode = CoordViewMode.overlay;
  bool _showGrid = false;
  String? _selectedWallId;
  bool _addMode = false;
  Point2? _pendingAddStart;

  // §4/§5 WO088-2 REAL SCALE ANCHOR — 사용자가 도면 위 두 점을 찍고 실제
  // 길이(mm)를 입력하면 확정된다. 확정 전에는 항상 unknown이다(§3B —
  // 임의 mm 값을 만들지 않는다).
  RealWorldScale _scale = const RealWorldScale.unknown();
  bool _anchorMode = false;
  Point2? _pendingAnchorStart;
  bool _showRealScale = false;

  PixelWallExtractionResult? _buildExtraction() {
    final bytes = _bytes;
    if (bytes == null) return null;
    return extractPixelWalls(bytes);
  }

  CoordStructureModel? _buildInitial() {
    final extraction = _extraction;
    if (extraction == null) return null;
    return buildCoordStructureFromExtraction(extraction);
  }

  void _onCanvasTap(Point2 tapped) {
    final model = _model;
    if (model == null) return;
    if (_anchorMode) {
      final pendingStart = _pendingAnchorStart;
      if (pendingStart == null) {
        setState(() => _pendingAnchorStart = tapped);
      } else {
        _promptAnchorRealLength(pendingStart, tapped);
      }
      return;
    }
    if (_addMode) {
      final pendingStart = _pendingAddStart;
      if (pendingStart == null) {
        setState(() => _pendingAddStart = tapped);
      } else {
        final newWall = CoordWallSegment(
          id: 'user-${DateTime.now().microsecondsSinceEpoch}',
          start: pendingStart,
          end: tapped,
          thicknessNormalized: 0.02,
          isExterior: false,
          confidence: 1.0,
          reviewNeeded: false,
          source: CoordEvidenceSource.userEdited,
        );
        setState(() {
          _model = model.copyWithWalls([...model.walls, newWall]);
          _pendingAddStart = null;
          _addMode = false;
        });
      }
      return;
    }
    CoordWallSegment? closest;
    var bestDist = double.infinity;
    for (final w in model.walls) {
      final midX = (w.start.x + w.end.x) / 2;
      final midY = (w.start.y + w.end.y) / 2;
      final d = (midX - tapped.x) * (midX - tapped.x) + (midY - tapped.y) * (midY - tapped.y);
      if (d < bestDist) {
        bestDist = d;
        closest = w;
      }
    }
    setState(() => _selectedWallId = closest?.id);
  }

  void _deleteSelected() {
    final model = _model;
    final selectedId = _selectedWallId;
    if (model == null || selectedId == null) return;
    setState(() {
      _model = model.copyWithWalls(model.walls.where((w) => w.id != selectedId).toList());
      _selectedWallId = null;
    });
  }

  // §4/§6 USER SCALE ANCHOR — "문은 보통 900/1000mm"를 자동 확정하지
  // 않는다: 900/1000mm는 사용자가 직접 고를 수 있는 후보일 뿐이고,
  // 직접입력이 항상 함께 제공된다. 취소하면 anchor 자체를 확정하지
  // 않는다(scale은 그대로 unknown으로 남는다).
  Future<void> _promptAnchorRealLength(Point2 a, Point2 b) async {
    final controller = TextEditingController();
    final result = await showDialog<double>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('실제 길이 입력 (mm)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('선택한 두 점 사이의 실제 길이를 지정하세요.'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(onPressed: () => Navigator.of(context).pop(900.0), child: const Text('문 900mm')),
                  OutlinedButton(onPressed: () => Navigator.of(context).pop(1000.0), child: const Text('문 1000mm')),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: '직접 입력(mm)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('취소')),
            TextButton(
              onPressed: () => Navigator.of(context).pop(double.tryParse(controller.text)),
              child: const Text('적용'),
            ),
          ],
        );
      },
    );
    setState(() => _pendingAnchorStart = null);
    if (result == null) return;
    final extraction = _extraction;
    if (extraction == null) return;
    final newScale = calibrateCoordScaleFromAnchor(
      a: a,
      b: b,
      realWorldMm: result,
      sourceWidthPx: extraction.analysisWidthPx,
      sourceHeightPx: extraction.analysisHeightPx,
      anchorDescription: '사용자 선택 anchor = ${result.toStringAsFixed(0)}mm',
    );
    setState(() {
      _scale = newScale;
      _anchorMode = false;
      if (newScale.isCalibrated) _showRealScale = true;
    });
  }

  /// §10 REAL SCALE OVERLAY — 확정된 anchor로 전체 coordinate model을
  /// mm로 변환해(coord_real_scale.dart, 새 산술 없이 재사용) wallId ->
  /// lengthMm 조회 테이블만 뽑아낸다(overlay 텍스트 라벨용).
  Map<String, double> _wallLengthMmById() {
    final extraction = _extraction;
    final model = _model;
    if (extraction == null || model == null) return const {};
    final metric = buildMetricCoordStructure(model, _scale, sourceWidthPx: extraction.analysisWidthPx, sourceHeightPx: extraction.analysisHeightPx);
    return {for (final w in metric.walls) w.id: w.lengthMm};
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    final model = _model;
    if (bytes == null || model == null) {
      return const Scaffold(body: Center(child: Text('SOURCE BLOCKED: 실제 Image 2를 찾을 수 없음')));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('WO088-2 COORD + REAL SCALE POC'),
        actions: [
          IconButton(
            icon: Icon(_showGrid ? Icons.grid_on : Icons.grid_off),
            onPressed: () => setState(() => _showGrid = !_showGrid),
          ),
          IconButton(
            icon: Icon(_addMode ? Icons.add_box : Icons.add_box_outlined),
            tooltip: '벽 추가(두 점 탭)',
            onPressed: () => setState(() {
              _addMode = !_addMode;
              _pendingAddStart = null;
            }),
          ),
          IconButton(
            icon: Icon(_anchorMode ? Icons.straighten : Icons.straighten_outlined),
            tooltip: 'Scale Anchor 설정(두 점 탭 + 실제 길이 입력)',
            onPressed: () => setState(() {
              _anchorMode = !_anchorMode;
              _pendingAnchorStart = null;
            }),
          ),
          if (_scale.isCalibrated)
            IconButton(
              icon: Icon(_showRealScale ? Icons.straighten : Icons.straighten_outlined, color: Colors.green),
              tooltip: '실측(mm) 라벨 표시 전환',
              onPressed: () => setState(() => _showRealScale = !_showRealScale),
            ),
          if (_selectedWallId != null) IconButton(icon: const Icon(Icons.delete), onPressed: _deleteSelected),
        ],
      ),
      body: Column(
        children: [
          SegmentedButton<CoordViewMode>(
            segments: const [
              ButtonSegment(value: CoordViewMode.original, label: Text('원본')),
              ButtonSegment(value: CoordViewMode.overlay, label: Text('원본+Overlay')),
              ButtonSegment(value: CoordViewMode.coordinateOnly, label: Text('Coordinate Only')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Wrap(
              spacing: 12,
              children: [
                Text('walls: ${model.walls.length}'),
                Text('exterior: ${model.walls.where((w) => w.isExterior).length}'),
                Text('reviewNeeded: ${model.walls.where((w) => w.reviewNeeded).length}'),
                Text('corners: ${model.corners.length}'),
                Text('openings: ${model.openings.length}'),
                Text('regions: ${model.regions.length}'),
                Text(
                  _scale.isCalibrated
                      ? 'SCALE: 1 unit = ${_scale.mmPerVirtualUnit!.toStringAsFixed(3)}mm (${_scale.anchorDescription ?? ""})'
                      : 'SCALE: 미확정 (Anchor 설정 필요)',
                  style: TextStyle(color: _scale.isCalibrated ? Colors.green.shade800 : Colors.deepOrange, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return GestureDetector(
                      onTapUp: (details) {
                        final local = details.localPosition;
                        _onCanvasTap(Point2(local.dx / constraints.maxWidth, local.dy / constraints.maxHeight));
                      },
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (_mode != CoordViewMode.coordinateOnly)
                            Container(color: Colors.white, child: Image.memory(bytes, fit: BoxFit.contain))
                          else
                            Container(color: Colors.black87),
                          if (_mode != CoordViewMode.original)
                            CustomPaint(
                              painter: _CoordOverlayPainter(
                                model: model,
                                showGrid: _showGrid,
                                selectedWallId: _selectedWallId,
                                pendingAnchorStart: _pendingAnchorStart,
                                wallLengthMm: _showRealScale && _scale.isCalibrated ? _wallLengthMmById() : const {},
                              ),
                              child: const SizedBox.expand(),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoordOverlayPainter extends CustomPainter {
  _CoordOverlayPainter({
    required this.model,
    required this.showGrid,
    required this.selectedWallId,
    this.pendingAnchorStart,
    this.wallLengthMm = const {},
  });

  final CoordStructureModel model;
  final bool showGrid;
  final String? selectedWallId;

  /// §4 anchor 두 번째 점을 아직 안 찍었을 때, 첫 번째 점을 시각적으로
  /// 표시한다(사용자가 어디를 찍었는지 잊지 않도록).
  final Point2? pendingAnchorStart;

  /// §10 REAL SCALE OVERLAY — 비어 있으면(anchor 미확정 또는 토글 off)
  /// 아무 mm 라벨도 그리지 않는다.
  final Map<String, double> wallLengthMm;

  @override
  void paint(Canvas canvas, Size size) {
    if (showGrid) {
      final gridPaint = Paint()
        ..color = Colors.grey.withValues(alpha: 0.4)
        ..strokeWidth = 0.5;
      for (final v in gridLines()) {
        canvas.drawLine(Offset(v * size.width, 0), Offset(v * size.width, size.height), gridPaint);
        canvas.drawLine(Offset(0, v * size.height), Offset(size.width, v * size.height), gridPaint);
      }
    }

    for (final region in model.regions) {
      if (region.polygon.length < 3) continue;
      final path = Path()..addPolygon([for (final p in region.polygon) Offset(p.x * size.width, p.y * size.height)], true);
      canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = Colors.green.withValues(alpha: 0.7));
    }

    for (final wall in model.walls) {
      final selected = wall.id == selectedWallId;
      final color = selected
          ? Colors.purple
          : wall.reviewNeeded
          ? Colors.orange
          : wall.isExterior
          ? Colors.red
          : Colors.blue;
      canvas.drawLine(
        Offset(wall.start.x * size.width, wall.start.y * size.height),
        Offset(wall.end.x * size.width, wall.end.y * size.height),
        Paint()
          ..color = color
          ..strokeWidth = selected ? 4 : 2,
      );

      final lengthMm = wallLengthMm[wall.id];
      if (lengthMm != null) {
        final midX = (wall.start.x + wall.end.x) / 2 * size.width;
        final midY = (wall.start.y + wall.end.y) / 2 * size.height;
        final tp = TextPainter(
          text: TextSpan(text: '${lengthMm.toStringAsFixed(0)}mm', style: const TextStyle(color: Colors.black, fontSize: 9, backgroundColor: Colors.white70)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(midX - tp.width / 2, midY - tp.height / 2));
      }
    }

    if (pendingAnchorStart != null) {
      canvas.drawCircle(
        Offset(pendingAnchorStart!.x * size.width, pendingAnchorStart!.y * size.height),
        6,
        Paint()..color = Colors.amber,
      );
    }

    for (final corner in model.corners) {
      canvas.drawCircle(Offset(corner.point.x * size.width, corner.point.y * size.height), 3, Paint()..color = Colors.green);
    }

    for (final opening in model.openings) {
      final color = switch (opening.kind) {
        CoordOpeningKind.door => Colors.deepPurpleAccent,
        CoordOpeningKind.window => Colors.cyan,
        CoordOpeningKind.unknown => Colors.grey,
      };
      canvas.drawCircle(Offset(opening.center.x * size.width, opening.center.y * size.height), 5, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _CoordOverlayPainter oldDelegate) =>
      oldDelegate.model != model ||
      oldDelegate.showGrid != showGrid ||
      oldDelegate.selectedWallId != selectedWallId ||
      oldDelegate.pendingAnchorStart != pendingAnchorStart ||
      oldDelegate.wallLengthMm != wallLengthMm;
}
