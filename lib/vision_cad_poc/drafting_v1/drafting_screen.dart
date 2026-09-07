// SPACE SHIFT — WO088-4 PHASE B: DRAFTING COORDINATE POC 화면.
//
// §15 4개 view: 원본 / 원본+Structural Line / 원본+Coordinate Draft /
// Coordinate Draft Only. CAD/CadFloorPlan 렌더링 경로를 전혀 참조하지
// 않는다(§23) — 완전히 독립된 POC 화면이다.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'drafting_model.dart';
import 'real_image3_source.dart';
import 'structural_layer.dart';

enum DraftViewMode { original, structuralLine, coordinateDraft, draftOnly }

// WO088-3에서 이미 식별/검증된 우측 계단형 외곽 bbox — 새 magic number가
// 아니라 이전 root-cause 조사에서 나온 관찰을 그대로 재사용한다.
const _wingX0 = 560, _wingY0 = 0, _wingX1 = 840, _wingY1 = 350;

class _AnalysisResult {
  _AnalysisResult({required this.w, required this.h, required this.rawLines, required this.model, required this.structuralMaskPngBytes});
  final int w, h;
  final List<RawStructuralLine> rawLines;
  final DraftingModel model;
  final Uint8List? structuralMaskPngBytes;
}

_AnalysisResult _analyze(Uint8List bytes) {
  final result = buildStructuralMask(bytes);
  final w = result.w, h = result.h;
  final diagonal = math.sqrt(w * w + h * h);
  final minRunPx = math.max(6.0, diagonal * 0.02);
  const maxThicknessPx = 20.0;

  final axisLines = extractAxisAlignedLines(result.structuralMask, w, h, minRunPx: minRunPx, maxThicknessPx: maxThicknessPx);
  final axisLinesOutsideWing = axisLines.where((l) {
    final midX = (l.start.x + l.end.x) / 2, midY = (l.start.y + l.end.y) / 2;
    return !(midX >= _wingX0 && midX <= _wingX1 && midY >= _wingY0 && midY <= _wingY1);
  }).toList();
  final wingLines = extractLocalDeskewedLines(
    result.structuralMask, w, h,
    x0: _wingX0, y0: _wingY0, x1: _wingX1, y1: _wingY1,
    minRunPx: minRunPx, maxThicknessPx: maxThicknessPx,
  );
  final rawLines = [...axisLinesOutsideWing, ...wingLines];
  final model = buildDraftingModel(rawLines);
  return _AnalysisResult(w: w, h: h, rawLines: rawLines, model: model, structuralMaskPngBytes: null);
}

class DraftingScreen extends StatefulWidget {
  const DraftingScreen({super.key});

  @override
  State<DraftingScreen> createState() => _DraftingScreenState();
}

class _DraftingScreenState extends State<DraftingScreen> {
  final Uint8List? _bytes = loadRealImage3Bytes();
  late final _AnalysisResult? _analysis = _bytes == null ? null : _analyze(_bytes);
  DraftViewMode _mode = DraftViewMode.coordinateDraft;
  String? _selectedWallId;

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    final analysis = _analysis;
    if (bytes == null || analysis == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('WO088-4 DRAFTING COORDINATE POC')),
        body: Center(child: Text('SOURCE BLOCKED\n$kRealImage3Path', textAlign: TextAlign.center)),
      );
    }

    final ortho = analysis.model.walls.where((w) => w.classification == WallAngleClass.orthogonalConfirmed).length;
    final diag = analysis.model.walls.where((w) => w.classification == WallAngleClass.diagonalConfirmed).length;
    final review = analysis.model.walls.where((w) => w.classification == WallAngleClass.reviewNeeded).length;
    final selected = _selectedWallId == null ? null : analysis.model.walls.where((w) => w.id == _selectedWallId).firstOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('WO088-4 DRAFTING COORDINATE POC')),
      body: Column(
        children: [
          SegmentedButton<DraftViewMode>(
            segments: const [
              ButtonSegment(value: DraftViewMode.original, label: Text('원본')),
              ButtonSegment(value: DraftViewMode.structuralLine, label: Text('원본+Structural Line')),
              ButtonSegment(value: DraftViewMode.coordinateDraft, label: Text('원본+Coordinate Draft')),
              ButtonSegment(value: DraftViewMode.draftOnly, label: Text('Coordinate Draft Only')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Wrap(
              spacing: 12,
              children: [
                Text('walls: ${analysis.model.walls.length}'),
                Text('orthogonalConfirmed: $ortho'),
                Text('diagonalConfirmed: $diag'),
                Text('reviewNeeded: $review'),
                Text('corners: ${analysis.model.corners.length}'),
                Text('Origin(px): (${analysis.model.originPixel.x.toStringAsFixed(0)}, ${analysis.model.originPixel.y.toStringAsFixed(0)})'),
                if (selected != null) Text('선택 벽 각도: ${selected.angleDeg.toStringAsFixed(1)}° (${selected.classification.name})'),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: analysis.w / analysis.h,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return GestureDetector(
                      onTapUp: (details) {
                        if (_mode == DraftViewMode.original) return;
                        final local = details.localPosition;
                        setState(() => _selectedWallId = _hitTestWall(analysis, local, constraints.maxWidth, constraints.maxHeight, _mode));
                      },
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (_mode != DraftViewMode.draftOnly)
                            Container(color: Colors.white, child: Image.memory(bytes, fit: BoxFit.fill))
                          else
                            Container(color: const Color(0xFF101418)),
                          if (_mode == DraftViewMode.structuralLine)
                            CustomPaint(painter: _StructuralLinePainter(analysis: analysis, selectedWallId: _selectedWallId)),
                          if (_mode == DraftViewMode.coordinateDraft)
                            CustomPaint(painter: _CoordinateDraftOverlayPainter(analysis: analysis, selectedWallId: _selectedWallId)),
                          if (_mode == DraftViewMode.draftOnly)
                            CustomPaint(painter: _DraftOnlyPainter(analysis: analysis, selectedWallId: _selectedWallId)),
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

  String? _hitTestWall(_AnalysisResult analysis, Offset local, double canvasW, double canvasH, DraftViewMode mode) {
    DraftWall? closest;
    var bestDist = double.infinity;
    if (mode == DraftViewMode.structuralLine) {
      for (final l in analysis.rawLines) {
        final midX = (l.start.x + l.end.x) / 2 / analysis.w * canvasW;
        final midY = (l.start.y + l.end.y) / 2 / analysis.h * canvasH;
        final d = (midX - local.dx) * (midX - local.dx) + (midY - local.dy) * (midY - local.dy);
        if (d < bestDist) {
          bestDist = d;
          closest = analysis.model.walls.firstWhere((w) => w.id == l.id, orElse: () => analysis.model.walls.first);
        }
      }
      return closest?.id;
    }
    // coordinateDraft 모드는 원본 px 좌표계 그대로 겹쳐 그리므로 동일 방식 사용.
    for (final w in analysis.model.walls) {
      // originPixel로부터 역변환해 원본 px 중점을 구한다.
      final midXVirtual = (w.startVirtual.x + w.endVirtual.x) / 2;
      final midYVirtual = (w.startVirtual.y + w.endVirtual.y) / 2;
      final midXPx = midXVirtual + analysis.model.originPixel.x;
      final midYPx = -midYVirtual + analysis.model.originPixel.y;
      final midX = midXPx / analysis.w * canvasW;
      final midY = midYPx / analysis.h * canvasH;
      final d = (midX - local.dx) * (midX - local.dx) + (midY - local.dy) * (midY - local.dy);
      if (d < bestDist) {
        bestDist = d;
        closest = w;
      }
    }
    return closest?.id;
  }
}

Color _wallColor(DraftWall w, bool selected) {
  if (selected) return Colors.purple;
  switch (w.classification) {
    case WallAngleClass.orthogonalConfirmed:
      return const Color(0xFF0057DC);
    case WallAngleClass.orthogonalCandidate:
      return Colors.teal;
    case WallAngleClass.diagonalConfirmed:
      return const Color(0xFFC800A0);
    case WallAngleClass.reviewNeeded:
      return Colors.orange;
  }
}

class _StructuralLinePainter extends CustomPainter {
  _StructuralLinePainter({required this.analysis, required this.selectedWallId});
  final _AnalysisResult analysis;
  final String? selectedWallId;

  @override
  void paint(Canvas canvas, Size size) {
    for (final l in analysis.rawLines) {
      final wall = analysis.model.walls.firstWhere((w) => w.id == l.id, orElse: () => analysis.model.walls.first);
      final color = _wallColor(wall, l.id == selectedWallId);
      canvas.drawLine(
        Offset(l.start.x / analysis.w * size.width, l.start.y / analysis.h * size.height),
        Offset(l.end.x / analysis.w * size.width, l.end.y / analysis.h * size.height),
        Paint()
          ..color = color
          ..strokeWidth = l.id == selectedWallId ? 4 : 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StructuralLinePainter oldDelegate) => oldDelegate.selectedWallId != selectedWallId;
}

/// px(virtual) -> canvas 변환. Origin은 항상 원본 이미지 px 좌표 기준으로
/// 계산돼 있으므로, "원본+Coordinate Draft" 모드에서는 그 px 좌표를 다시
/// 원본 이미지와 같은 캔버스 비율로 나누기만 하면 원본과 정확히 겹친다.
Offset _pxToCanvas(({double x, double y}) px, int w, int h, Size size) => Offset(px.x / w * size.width, px.y / h * size.height);

class _CoordinateDraftOverlayPainter extends CustomPainter {
  _CoordinateDraftOverlayPainter({required this.analysis, required this.selectedWallId});
  final _AnalysisResult analysis;
  final String? selectedWallId;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = analysis.model.originPixel;
    // Origin/axis를 원본 이미지 px 좌표 그대로 그린다(virtual -> px 역변환:
    // pxX = virtualX + originX, pxY = -virtualY + originY).
    Offset pxOf(({double x, double y}) virtual) => _pxToCanvas((x: virtual.x + origin.x, y: -virtual.y + origin.y), analysis.w, analysis.h, size);

    for (final wall in analysis.model.walls) {
      final selected = wall.id == selectedWallId;
      canvas.drawLine(
        pxOf(wall.startVirtual),
        pxOf(wall.endVirtual),
        Paint()
          ..color = _wallColor(wall, selected)
          ..strokeWidth = selected ? 4 : 2,
      );
      if (selected) {
        final mid = Offset((pxOf(wall.startVirtual).dx + pxOf(wall.endVirtual).dx) / 2, (pxOf(wall.startVirtual).dy + pxOf(wall.endVirtual).dy) / 2);
        _drawLabel(canvas, mid, '${wall.angleDeg.toStringAsFixed(1)}°', Colors.purple);
      }
    }
    for (final c in analysis.model.corners) {
      canvas.drawCircle(pxOf(c.point), 3, Paint()..color = Colors.green);
    }

    // Origin marker + X/Y axis(원본 위에 겹쳐 그림 — 원본과 정렬 확인용).
    final originCanvas = _pxToCanvas(origin, analysis.w, analysis.h, size);
    canvas.drawCircle(originCanvas, 5, Paint()..color = Colors.red);
    canvas.drawLine(originCanvas, Offset(originCanvas.dx + 60, originCanvas.dy), Paint()..color = Colors.red..strokeWidth = 2);
    canvas.drawLine(originCanvas, Offset(originCanvas.dx, originCanvas.dy - 60), Paint()..color = Colors.green..strokeWidth = 2);
    _drawLabel(canvas, originCanvas + const Offset(-14, 10), '(0,0)', Colors.red);
  }

  @override
  bool shouldRepaint(covariant _CoordinateDraftOverlayPainter oldDelegate) => oldDelegate.selectedWallId != selectedWallId;
}

/// Coordinate Draft Only — 원본 없이 순수 virtual 좌표만으로 그린다(진짜
/// CAD 제도판처럼). virtual bbox를 캔버스에 맞춰 균일 축척으로 fit한다.
class _DraftOnlyPainter extends CustomPainter {
  _DraftOnlyPainter({required this.analysis, required this.selectedWallId});
  final _AnalysisResult analysis;
  final String? selectedWallId;

  @override
  void paint(Canvas canvas, Size size) {
    final walls = analysis.model.walls;
    if (walls.isEmpty) return;
    var minX = 0.0, maxX = 0.0, minY = 0.0, maxY = 0.0;
    for (final w in walls) {
      for (final p in [w.startVirtual, w.endVirtual]) {
        minX = math.min(minX, p.x);
        maxX = math.max(maxX, p.x);
        minY = math.min(minY, p.y);
        maxY = math.max(maxY, p.y);
      }
    }
    final marginFrac = 0.08;
    final rangeX = (maxX - minX).clamp(1, double.infinity) * (1 + marginFrac * 2);
    final rangeY = (maxY - minY).clamp(1, double.infinity) * (1 + marginFrac * 2);
    final scale = math.min(size.width / rangeX, size.height / rangeY);
    final originX = -minX * scale + (size.width - (maxX - minX) * scale) / 2;
    // 캔버스 Y는 아래로 증가하므로, virtual(+Y 위쪽)을 뒤집어야 한다.
    final originY = maxY * scale + (size.height - (maxY - minY) * scale) / 2;

    Offset toCanvas(({double x, double y}) v) => Offset(v.x * scale + originX, -v.y * scale + originY);

    // grid(가상 눈금) — 100 virtual-unit 간격, 화면 zoom과 무관한 고정 간격.
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    for (var gx = (minX ~/ 100) * 100; gx <= maxX; gx += 100) {
      final a = toCanvas((x: gx.toDouble(), y: minY));
      final b = toCanvas((x: gx.toDouble(), y: maxY));
      canvas.drawLine(a, b, gridPaint);
    }
    for (var gy = (minY ~/ 100) * 100; gy <= maxY; gy += 100) {
      final a = toCanvas((x: minX, y: gy.toDouble()));
      final b = toCanvas((x: maxX, y: gy.toDouble()));
      canvas.drawLine(a, b, gridPaint);
    }

    for (final wall in walls) {
      final selected = wall.id == selectedWallId;
      canvas.drawLine(toCanvas(wall.startVirtual), toCanvas(wall.endVirtual), Paint()..color = _wallColor(wall, selected)..strokeWidth = selected ? 4 : 3);
    }
    for (final c in analysis.model.corners) {
      canvas.drawCircle(toCanvas(c.point), 3, Paint()..color = Colors.greenAccent);
    }

    final originCanvas = toCanvas((x: 0, y: 0));
    canvas.drawCircle(originCanvas, 5, Paint()..color = Colors.redAccent);
    canvas.drawLine(originCanvas, originCanvas + const Offset(50, 0), Paint()..color = Colors.redAccent..strokeWidth = 2);
    canvas.drawLine(originCanvas, originCanvas + const Offset(0, -50), Paint()..color = Colors.lightGreenAccent..strokeWidth = 2);
    _drawLabel(canvas, originCanvas + const Offset(-14, 10), '(0,0)', Colors.redAccent);
    _drawLabel(canvas, originCanvas + const Offset(52, -4), '+X', Colors.redAccent);
    _drawLabel(canvas, originCanvas + const Offset(4, -60), '+Y', Colors.lightGreenAccent);
  }

  @override
  bool shouldRepaint(covariant _DraftOnlyPainter oldDelegate) => oldDelegate.selectedWallId != selectedWallId;
}

void _drawLabel(Canvas canvas, Offset at, String text, Color color) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, at);
}
