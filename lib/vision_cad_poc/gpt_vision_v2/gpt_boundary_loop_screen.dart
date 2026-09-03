import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/ss_spatial_model.dart';
import '../e2e_v2/real_image2_source.dart';
import 'gpt_boundary_loop_processor.dart';
import 'gpt_pass_b_schema.dart';

const _captureDir = 'lib/vision_cad_poc/gpt_vision_v2/captured';

/// SPACE SHIFT — GPT Space Boundary Loop Recovery POC 화면.
///
/// 실제 PASS A(전체 의미) → PASS B(공간별 순서 경계, 4/13만 응답) →
/// PASS C(누락 9개 space 보충)까지 실제 OpenAI Vision API를 호출해
/// 캡처한 응답을 그대로 불러와 [GptBoundaryLoopProcessor](신규 —
/// self-chain/cross-space snap/canonical wall merge/FloorDomain
/// 재구성)에 통과시킨다. PASS 상태와 결과를 숨김없이 보여준다.
class GptBoundaryLoopScreen extends StatefulWidget {
  const GptBoundaryLoopScreen({super.key});

  @override
  State<GptBoundaryLoopScreen> createState() => _GptBoundaryLoopScreenState();
}

class _GptBoundaryLoopScreenState extends State<GptBoundaryLoopScreen> {
  final Uint8List? _realImageBytes = loadRealImage2Bytes();
  bool _showFloorDomain = true;
  bool _showWalls = true;
  bool _showCorners = true;
  bool _showFailedOnly = false;

  late final GptBoundaryLoopResult? _result = _run();

  GptBoundaryLoopResult? _run() {
    if (_realImageBytes == null) return null;
    final bFile = File('$_captureDir/pass_b.json');
    final cFile = File('$_captureDir/pass_c.json');
    if (!bFile.existsSync() || !cFile.existsSync()) return null;
    final passBJson = jsonDecode(bFile.readAsStringSync()) as Map<String, dynamic>;
    final passCJson = jsonDecode(cFile.readAsStringSync()) as Map<String, dynamic>;
    final allLoops = [
      ...(passBJson['spaceBoundaryLoops'] as List),
      ...(passCJson['spaceBoundaryLoops'] as List),
    ];
    final passB = GptPassBResponse.fromJson({'spaceBoundaryLoops': allLoops});
    const processor = GptBoundaryLoopProcessor();
    return processor.process(
      passB: passB,
      imageWidthPx: 443,
      imageHeightPx: 300,
      imageBytes: _realImageBytes,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_realImageBytes == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('SPACE SHIFT — GPT Space Boundary Loop Recovery POC')),
        body: Center(child: Text('ACTUAL IMAGE 2: BLOCKED\n$kRealImage2Path', textAlign: TextAlign.center)),
      );
    }
    if (_result == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('SPACE SHIFT — GPT Space Boundary Loop Recovery POC')),
        body: const Center(
          child: Text(
            'PASS B/C 캡처 응답이 없습니다.\ntool/gpt_vision_v2_call.dart 를 먼저 실행하세요.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('SPACE SHIFT — GPT Space Boundary Loop Recovery POC (독립, production 미연결)')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PassStatusBar(),
            _StatusBar(result: result),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Wrap(
                spacing: 8,
                children: [
                  FilterChip(label: const Text('FloorDomain'), selected: _showFloorDomain, onSelected: (v) => setState(() => _showFloorDomain = v)),
                  FilterChip(label: const Text('Walls'), selected: _showWalls, onSelected: (v) => setState(() => _showWalls = v)),
                  FilterChip(label: const Text('Corners'), selected: _showCorners, onSelected: (v) => setState(() => _showCorners = v)),
                  FilterChip(label: const Text('실패한 loop만 강조'), selected: _showFailedOnly, onSelected: (v) => setState(() => _showFailedOnly = v)),
                ],
              ),
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
                        aspectRatio: 443 / 300,
                        child: Container(
                          decoration: BoxDecoration(border: Border.all(color: Colors.black26)),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.memory(_realImageBytes, fit: BoxFit.fill),
                              CustomPaint(
                                painter: _OverlayPainter(
                                  result: result,
                                  showFloorDomain: _showFloorDomain,
                                  showWalls: _showWalls,
                                  showCorners: _showCorners,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(flex: 2, child: _DetailPanel(result: result)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PassStatusBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Widget chip(String label) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      margin: const EdgeInsets.only(right: 6),
      decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.green)),
      child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.green)),
    );
    return Container(
      width: double.infinity,
      color: const Color(0xFFE8F5E9),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          chip('PASS A: DONE (13 spaces, semantic)'),
          chip('PASS B: DONE (4/13 boundary loops)'),
          chip('PASS C: DONE (누락 9/13 보충)'),
          const SizedBox(width: 12),
          const Text(
            '총 3회 실제 API 호출(model gpt-4o) — API 키는 이 Flutter 앱에 포함되지 않음(별도 dev-side 스크립트)',
            style: TextStyle(fontSize: 11, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.result});
  final GptBoundaryLoopResult result;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6), border: Border.all(color: color)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );

    final reviewCount = result.model.spaces.where((s) => s.reviewNeeded).length +
        result.model.walls.where((w) => w.reviewNeeded).length;
    final closed = result.closedLoopCount;
    final total = result.spaceLoops.length;

    return Container(
      width: double.infinity,
      color: const Color(0xFFF5F5F5),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Wrap(
        spacing: 10,
        runSpacing: 6,
        children: [
          chip('SPACES $total/13', total == 13 ? Colors.green : Colors.orange),
          chip('BOUNDARY LOOPS $closed/$total', closed == total ? Colors.green : Colors.deepOrange),
          chip('CANONICAL WALLS ${result.canonicalWalls.length}', Colors.black87),
          chip('FLOOR DOMAIN ${result.floorDomainClosed ? "VALID" : "INVALID"}', result.floorDomainClosed ? Colors.green : Colors.red),
          chip('TOPOLOGY NOTES ${result.model.warnings.length}', result.model.warnings.isEmpty ? Colors.green : Colors.deepOrange),
          chip('REVIEW NEEDED $reviewCount', reviewCount > 0 ? Colors.deepOrange : Colors.green),
        ],
      ),
    );
  }
}

class _DetailPanel extends StatelessWidget {
  const _DetailPanel({required this.result});
  final GptBoundaryLoopResult result;

  @override
  Widget build(BuildContext context) {
    final deltas = [for (final w in result.canonicalWalls) if (w.refinedDeltaPx != null) w.refinedDeltaPx!];
    final mean = deltas.isEmpty ? 0 : deltas.reduce((a, b) => a + b) / deltas.length;
    final max = deltas.isEmpty ? 0 : deltas.reduce((a, b) => a > b ? a : b);
    final high = result.canonicalWalls.where((w) => w.geometryConfidence?.name == 'high').length;
    final unmatched = result.canonicalWalls.where((w) => w.geometryConfidence == null).length;

    return Container(
      color: const Color(0xFFFAFAFA),
      padding: const EdgeInsets.all(12),
      child: ListView(
        children: [
          const Text('Local refinement 지표', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          Text('mean delta: ${mean.toStringAsFixed(1)}px  ·  max delta: ${max.toStringAsFixed(1)}px'),
          Text('HIGH confidence walls: $high/${result.canonicalWalls.length}  ·  unmatched: $unmatched'),
          if (!result.floorDomainClosed)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'FloorDomain: ${result.floorDomainFailureReason}',
                style: const TextStyle(fontSize: 11, color: Colors.red),
              ),
            ),
          const Divider(height: 24),
          const Text('공간별 상태', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          for (final s in result.spaceLoops)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '${s.spaceId}: ${s.closed ? "CLOSED" : "FAILED — ${s.failureReason}"}',
                style: TextStyle(fontSize: 11, color: s.closed ? Colors.green.shade800 : Colors.red),
              ),
            ),
        ],
      ),
    );
  }
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter({required this.result, required this.showFloorDomain, required this.showWalls, required this.showCorners});

  final GptBoundaryLoopResult result;
  final bool showFloorDomain;
  final bool showWalls;
  final bool showCorners;

  @override
  void paint(Canvas canvas, Size size) {
    if (showFloorDomain && result.model.floorDomain != null) {
      final path = Path()..addPolygon([for (final p in result.model.floorDomain!) Offset(p.x * size.width, p.y * size.height)], true);
      canvas.drawPath(path, Paint()..color = Colors.purple..style = PaintingStyle.stroke..strokeWidth = 2.5);
    }

    for (final loop in result.spaceLoops) {
      if (!loop.closed) continue;
      final path = Path()
        ..addPolygon(
          [for (final p in loop.polygon) Offset(p.x / result.model.sourceWidthPx * size.width, p.y / result.model.sourceHeightPx * size.height)],
          true,
        );
      canvas.drawPath(path, Paint()..color = Colors.blue.withValues(alpha: 0.12));
      canvas.drawPath(path, Paint()..color = Colors.blue..style = PaintingStyle.stroke..strokeWidth = 1);
    }

    if (showWalls) {
      for (final wall in result.model.walls) {
        canvas.drawLine(
          Offset(wall.start.x * size.width, wall.start.y * size.height),
          Offset(wall.end.x * size.width, wall.end.y * size.height),
          Paint()
            ..color = (wall.reviewNeeded ? Colors.orange : Colors.red)
            ..strokeWidth = wall.kind == SSWallKind.exterior ? 3 : 2,
        );
      }
    }

    if (showCorners) {
      final points = <Offset>{};
      for (final wall in result.model.walls) {
        points.add(Offset(wall.start.x * size.width, wall.start.y * size.height));
        points.add(Offset(wall.end.x * size.width, wall.end.y * size.height));
      }
      for (final p in points) {
        canvas.drawCircle(p, 3, Paint()..color = Colors.deepPurple);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter oldDelegate) => true;
}
