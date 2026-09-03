import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/ss_spatial_model.dart';
import '../e2e_v2/real_image2_source.dart';
import 'gpt_graph_schema.dart';
import 'gpt_wall_graph_processor.dart';

const _capturePath = 'lib/vision_cad_poc/gpt_vision_v3/captured/pass_b_repaired.json';

/// SPACE SHIFT — Canonical Wall Graph First POC 화면.
///
/// 이 화면은 이번 라운드의 실제 결과를 있는 그대로 보여준다 —
/// 목표(하나의 공유 wall graph, 13/13 loop, valid FloorDomain)를
/// 달성하지 못했다는 사실을 숨기지 않는다(설계 22번 — 실패를
/// bbox/임의 diagonal로 조용히 감추지 않는다). [GptWallGraphProcessor]
/// 자체는 합성 데이터로 단위 테스트를 통과했다 — 이번 결과가 나쁜
/// 이유는 GPT가 이번 라운드에 준 corner/wall 그래프가 13개 방에
/// 비해 지나치게 부실했기 때문이다(정직한 원인 분리).
class GptWallGraphScreen extends StatefulWidget {
  const GptWallGraphScreen({super.key});

  @override
  State<GptWallGraphScreen> createState() => _GptWallGraphScreenState();
}

class _GptWallGraphScreenState extends State<GptWallGraphScreen> {
  final Uint8List? _realImageBytes = loadRealImage2Bytes();
  bool _showFloorDomain = true;
  bool _showWalls = true;
  bool _showCorners = true;

  late final GptWallGraphResult? _result = _run();

  GptWallGraphResult? _run() {
    if (_realImageBytes == null) return null;
    final file = File(_capturePath);
    if (!file.existsSync()) return null;
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final graph = GptWallGraphResponse.fromJson(json);
    const processor = GptWallGraphProcessor();
    return processor.process(graph: graph, imageWidthPx: 443, imageHeightPx: 300, imageBytes: _realImageBytes);
  }

  @override
  Widget build(BuildContext context) {
    if (_realImageBytes == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('SPACE SHIFT — Canonical Wall Graph First POC')),
        body: Center(child: Text('ACTUAL IMAGE 2: BLOCKED\n$kRealImage2Path', textAlign: TextAlign.center)),
      );
    }
    if (_result == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('SPACE SHIFT — Canonical Wall Graph First POC')),
        body: const Center(child: Text('캡처된 GPT graph 응답이 없습니다.\ntool/gpt_vision_v3_call.dart 를 먼저 실행하세요.', textAlign: TextAlign.center)),
      );
    }

    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('SPACE SHIFT — Canonical Wall Graph First POC (독립, production 미연결)')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HonestyBar(result: result),
            _StatusBar(result: result),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Wrap(
                spacing: 8,
                children: [
                  FilterChip(label: const Text('FloorDomain'), selected: _showFloorDomain, onSelected: (v) => setState(() => _showFloorDomain = v)),
                  FilterChip(label: const Text('Walls'), selected: _showWalls, onSelected: (v) => setState(() => _showWalls = v)),
                  FilterChip(label: const Text('Corners'), selected: _showCorners, onSelected: (v) => setState(() => _showCorners = v)),
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
                                painter: _OverlayPainter(result: result, showFloorDomain: _showFloorDomain, showWalls: _showWalls, showCorners: _showCorners),
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

class _HonestyBar extends StatelessWidget {
  const _HonestyBar({required this.result});
  final GptWallGraphResult result;

  @override
  Widget build(BuildContext context) {
    final pass = result.closedLoopCount == 13 && result.floorDomainClosed;
    return Container(
      width: double.infinity,
      color: pass ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(
        pass
            ? 'PRIMARY GOAL 달성: 하나의 공유 wall graph에서 13/13 space loop + valid FloorDomain'
            : 'PRIMARY GOAL 미달성: 이번 라운드 GPT 응답(총 3회 호출, PASS A/B/C)이 13개 방에 비해 '
                '지나치게 부실했습니다(corner/wall 개수 부족) — 결과를 bbox나 임의 대각선으로 감추지 않고 '
                '있는 그대로 표시합니다. Processor 자체는 합성 데이터 단위 테스트에서 정상 동작을 확인했습니다.',
        style: TextStyle(color: pass ? Colors.green : Colors.red, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.result});
  final GptWallGraphResult result;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6), border: Border.all(color: color)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
    final reviewCount = result.model.spaces.where((s) => s.reviewNeeded).length + result.model.walls.where((w) => w.reviewNeeded).length;
    final closed = result.closedLoopCount;
    final total = result.spaceLoopResults.length;

    return Container(
      width: double.infinity,
      color: const Color(0xFFF5F5F5),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Wrap(
        spacing: 10,
        runSpacing: 6,
        children: [
          chip('SPACES $total/13', total == 13 ? Colors.green : Colors.orange),
          chip('SPACE LOOPS $closed/$total', closed == total ? Colors.green : Colors.red),
          chip('GPT WALLS ${result.gptWallCount}', Colors.black87),
          chip('CANONICAL WALLS ${result.canonicalWalls.length}', Colors.black87),
          chip('DUPLICATES REMOVED ${result.duplicatesRemoved}', Colors.blueGrey),
          chip('FLOOR DOMAIN ${result.floorDomainClosed ? "VALID" : "INVALID"}', result.floorDomainClosed ? Colors.green : Colors.red),
          chip('TOPOLOGY ERRORS ${result.model.warnings.length}', result.model.warnings.isEmpty ? Colors.green : Colors.deepOrange),
          chip('REVIEW NEEDED $reviewCount', reviewCount > 0 ? Colors.deepOrange : Colors.green),
        ],
      ),
    );
  }
}

class _DetailPanel extends StatelessWidget {
  const _DetailPanel({required this.result});
  final GptWallGraphResult result;

  @override
  Widget build(BuildContext context) {
    final deltas = [for (final w in result.canonicalWalls) if (w.refinedDeltaPx != null) w.refinedDeltaPx!];
    final mean = deltas.isEmpty ? 0 : deltas.reduce((a, b) => a + b) / deltas.length;
    final max = deltas.isEmpty ? 0 : deltas.reduce((a, b) => a > b ? a : b);
    final high = result.canonicalWalls.where((w) => w.geometryConfidence?.name == 'high').length;

    return Container(
      color: const Color(0xFFFAFAFA),
      padding: const EdgeInsets.all(12),
      child: ListView(
        children: [
          const Text('Refinement 지표', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          Text('mean delta: ${mean.toStringAsFixed(1)}px  ·  max delta: ${max.toStringAsFixed(1)}px'),
          Text('HIGH confidence: $high/${result.canonicalWalls.length}'),
          if (!result.floorDomainClosed)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('FloorDomain: ${result.floorDomainFailureReason}', style: const TextStyle(fontSize: 11, color: Colors.red)),
            ),
          const Divider(height: 24),
          const Text('공간별 상태', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          for (final entry in result.spaceLoopResults.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '${entry.key}: ${entry.value.closed ? "CLOSED" : "FAILED — ${entry.value.failureReason}"}',
                style: TextStyle(fontSize: 10, color: entry.value.closed ? Colors.green.shade800 : Colors.red),
              ),
            ),
        ],
      ),
    );
  }
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter({required this.result, required this.showFloorDomain, required this.showWalls, required this.showCorners});
  final GptWallGraphResult result;
  final bool showFloorDomain;
  final bool showWalls;
  final bool showCorners;

  @override
  void paint(Canvas canvas, Size size) {
    if (showFloorDomain && result.model.floorDomain != null) {
      final path = Path()..addPolygon([for (final p in result.model.floorDomain!) Offset(p.x * size.width, p.y * size.height)], true);
      canvas.drawPath(path, Paint()..color = Colors.purple..style = PaintingStyle.stroke..strokeWidth = 2.5);
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
