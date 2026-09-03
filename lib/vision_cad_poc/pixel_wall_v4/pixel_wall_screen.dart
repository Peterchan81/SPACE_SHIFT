import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/ss_spatial_model.dart';
import '../e2e_v2/real_image2_source.dart';
import 'gpt_semantic_schema.dart';
import 'pixel_wall_pipeline.dart';
import 'pixel_wall_types.dart';
import 'semantic_zone_mapper.dart';

const _semanticCapturePath = 'lib/vision_cad_poc/pixel_wall_v4/captured/semantic_v4.json';

/// SPACE SHIFT — Vision-Guided Full Pixel Wall Extraction POC 화면.
///
/// 4개 탭(ORIGINAL / PIXEL WALLS / CANONICAL CAD / OVERLAY) — 잘못된
/// debug diagonal을 CANONICAL CAD 탭에서 숨겨 성공처럼 보이게 하지
/// 않는다: CANONICAL CAD도 실제 pixel candidate를 그대로 그린다(가짜
/// 문/창/치수선 없음).
class PixelWallScreen extends StatefulWidget {
  const PixelWallScreen({super.key});

  @override
  State<PixelWallScreen> createState() => _PixelWallScreenState();
}

class _PixelWallScreenState extends State<PixelWallScreen> {
  final Uint8List? _bytes = loadRealImage2Bytes();
  late final PixelWallPipelineResult? _result = _run();

  PixelWallPipelineResult? _run() {
    if (_bytes == null) return null;
    GptSemanticResponse? semantic;
    final file = File(_semanticCapturePath);
    if (file.existsSync()) {
      try {
        final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        semantic = GptSemanticResponse.fromJson(json);
      } catch (_) {
        semantic = null;
      }
    }
    return runPixelWallPipeline(imageBytes: _bytes, semantic: semantic);
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('SPACE SHIFT — Pixel Wall Extraction POC')),
        body: Center(child: Text('ACTUAL IMAGE 2: BLOCKED\n$kRealImage2Path', textAlign: TextAlign.center)),
      );
    }
    final result = _result!;
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('SPACE SHIFT — Vision-Guided Full Pixel Wall Extraction POC'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'ORIGINAL'),
              Tab(text: 'PIXEL WALLS'),
              Tab(text: 'CANONICAL CAD'),
              Tab(text: 'OVERLAY'),
            ],
          ),
        ),
        body: Column(
          children: [
            _StatusBar(result: result),
            Expanded(
              child: TabBarView(
                children: [
                  _ImagePane(bytes: _bytes),
                  _ImagePane(bytes: _bytes, painter: _PixelWallsPainter(result: result)),
                  _CanonicalCadPane(result: result),
                  _ImagePane(bytes: _bytes, painter: _CanonicalOverlayPainter(result: result)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.result});
  final PixelWallPipelineResult result;

  @override
  Widget build(BuildContext context) {
    final e = result.extraction;
    Widget chip(String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6), border: Border.all(color: color)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
    final reviewCount = result.model.spaces.where((s) => s.reviewNeeded).length + result.model.walls.where((w) => w.reviewNeeded).length;
    return Container(
      width: double.infinity,
      color: const Color(0xFFF5F5F5),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          chip('CANDIDATES ${e.candidates.length}', Colors.black87),
          chip('STRUCTURAL ${e.structuralCount}', Colors.blueGrey),
          chip('REVIEW ${e.reviewNeededCount}', e.reviewNeededCount > 0 ? Colors.deepOrange : Colors.green),
          chip('HIGH ${e.highCount}', Colors.green),
          chip('MEDIUM ${e.mediumCount}', Colors.orange),
          chip('LOW ${e.lowCount}', Colors.red),
          chip('REJECTED ${e.rejected.length}', Colors.grey),
          chip('PHYSICAL ROOMS ${result.physicalRooms.length}', Colors.black87),
          chip('PHYSICAL ROOM 매칭 ${result.matchedPhysicalRoomCount}', Colors.green),
          chip('SEMANTIC ZONES ${result.semanticZoneCount}', Colors.indigo),
          chip('GPT 미매칭 ${result.unmatchedGptSpaceCount}', result.unmatchedGptSpaceCount > 0 ? Colors.deepOrange : Colors.green),
          chip('UNKNOWN PHYSICAL ROOM ${result.unmatchedPhysicalRoomCount}', result.unmatchedPhysicalRoomCount > 0 ? Colors.deepOrange : Colors.green),
          chip('FLOOR DOMAIN ${result.floorDomainClosed ? "VALID" : "INVALID"}', result.floorDomainClosed ? Colors.green : Colors.red),
          if (!result.floorDomainClosed) chip('미해결 gap ${result.floorDomain.unresolvedGaps.length}', Colors.red),
          chip('TOPOLOGY ERRORS ${result.model.warnings.length}', result.model.warnings.isEmpty ? Colors.green : Colors.deepOrange),
          chip('REVIEW NEEDED $reviewCount', reviewCount > 0 ? Colors.deepOrange : Colors.green),
          if (!result.floorDomainClosed)
            chip('사유: ${result.floorDomainFailureReason}', Colors.red),
        ],
      ),
    );
  }
}

class _ImagePane extends StatelessWidget {
  const _ImagePane({required this.bytes, this.painter});
  final Uint8List bytes;
  final CustomPainter? painter;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Center(
        child: AspectRatio(
          aspectRatio: 443 / 301,
          child: Container(
            decoration: BoxDecoration(border: Border.all(color: Colors.black26)),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(bytes, fit: BoxFit.fill),
                if (painter != null) CustomPaint(painter: painter),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Color _tierColor(PixelWallConfidenceTier tier) {
  switch (tier) {
    case PixelWallConfidenceTier.high:
      return Colors.greenAccent.shade700;
    case PixelWallConfidenceTier.medium:
      return Colors.orange;
    case PixelWallConfidenceTier.low:
      return Colors.redAccent;
  }
}

class _PixelWallsPainter extends CustomPainter {
  _PixelWallsPainter({required this.result});
  final PixelWallPipelineResult result;

  @override
  void paint(Canvas canvas, Size size) {
    for (final r in result.extraction.rejected) {
      canvas.drawLine(
        Offset(r.start.x * size.width, r.start.y * size.height),
        Offset(r.end.x * size.width, r.end.y * size.height),
        Paint()
          ..color = Colors.grey.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
    }
    for (final c in result.extraction.candidates) {
      final color = switch (c.noiseCategory) {
        PixelWallNoiseCategory.text => Colors.blueGrey,
        PixelWallNoiseCategory.furniture => Colors.brown,
        PixelWallNoiseCategory.fixture => Colors.teal,
        PixelWallNoiseCategory.doorArc => Colors.pink,
        PixelWallNoiseCategory.windowDetail => Colors.cyan,
        PixelWallNoiseCategory.unknown => Colors.purple,
        PixelWallNoiseCategory.trueStructural => _tierColor(c.confidenceTier),
      };
      canvas.drawLine(
        Offset(c.start.x * size.width, c.start.y * size.height),
        Offset(c.end.x * size.width, c.end.y * size.height),
        Paint()
          ..color = color
          ..strokeWidth = c.isExterior ? 3.5 : 2.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PixelWallsPainter oldDelegate) => false;
}

/// CANONICAL CAD 탭 — 흰 배경에 구조 벽만 깨끗하게 그린다. 가짜 문/창/
/// 치수선을 추가하지 않는다(§ 명시 요구). reviewNeeded 벽도 색만 다르게
/// 그대로 보여준다 — 나쁜 결과를 숨기지 않는다.
class _CanonicalCadPane extends StatelessWidget {
  const _CanonicalCadPane({required this.result});
  final PixelWallPipelineResult result;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Center(
        child: AspectRatio(
          aspectRatio: 443 / 301,
          child: Container(
            color: Colors.white,
            child: CustomPaint(painter: _CanonicalCadPainter(result: result), child: const SizedBox.expand()),
          ),
        ),
      ),
    );
  }
}

/// [space]의 label을 중심점(폴리곤이 있으면 centroid, 없으면 GPT
/// approxRegion 중심 — semanticZone인데 geometry 근거조차 없는 경우)에
/// 그린다. semanticZone은 실제 벽처럼 실선을 그리지 않는다(§11/§12) —
/// 아주 약한 점선 참고 사각형만(폴리곤이 있을 때) 선택적으로 보여준다.
void _paintSpaceLabel(Canvas canvas, Size size, SpaceSemantic space) {
  if (space.polygon.isEmpty) return;
  var cx = 0.0, cy = 0.0;
  for (final p in space.polygon) {
    cx += p.x;
    cy += p.y;
  }
  cx /= space.polygon.length;
  cy /= space.polygon.length;

  if (space.kind == SpaceSemanticKind.semanticZone) {
    final path = Path()..addPolygon([for (final p in space.polygon) Offset(p.x * size.width, p.y * size.height)], true);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.indigo.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  final textPainter = TextPainter(
    text: TextSpan(
      text: space.kind == SpaceSemanticKind.semanticZone ? '${space.label} (zone)' : space.label,
      style: TextStyle(
        color: space.kind == SpaceSemanticKind.semanticZone ? Colors.indigo : (space.reviewNeeded ? Colors.deepOrange : Colors.black87),
        fontSize: 10,
        fontWeight: FontWeight.w600,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  textPainter.paint(canvas, Offset(cx * size.width - textPainter.width / 2, cy * size.height - textPainter.height / 2));
}

/// §3/§11 — 확실히 벽이 아니라고 분류된(text/furniture/fixture/doorArc/
/// windowDetail) candidate는 이미 pixel_wall_pipeline.dart가
/// result.model.walls에서 제외했다. 이 painter는 그 "깨끗한" 목록만
/// 그린다 — CANONICAL CAD에 노이즈가 다시 섞이지 않는다.
class _CanonicalCadPainter extends CustomPainter {
  _CanonicalCadPainter({required this.result});
  final PixelWallPipelineResult result;

  @override
  void paint(Canvas canvas, Size size) {
    for (final wall in result.model.walls) {
      canvas.drawLine(
        Offset(wall.start.x * size.width, wall.start.y * size.height),
        Offset(wall.end.x * size.width, wall.end.y * size.height),
        Paint()
          ..color = wall.reviewNeeded ? Colors.orange : const Color(0xFF1A1A1A)
          ..strokeWidth = wall.kind == SSWallKind.exterior ? 4 : 2.5,
      );
    }
    if (result.floorDomainClosed && result.model.floorDomain != null) {
      final path = Path()..addPolygon([for (final p in result.model.floorDomain!) Offset(p.x * size.width, p.y * size.height)], true);
      canvas.drawPath(path, Paint()..color = Colors.blue..style = PaintingStyle.stroke..strokeWidth = 1.5);
    }
    for (final space in result.spaceSemantics) {
      _paintSpaceLabel(canvas, size, space);
    }
    for (final room in result.physicalRooms) {
      if (room.claimedBySpaceIds.isNotEmpty) continue;
      final path = Path()..addPolygon([for (final p in room.polygon) Offset(p.x * size.width, p.y * size.height)], true);
      canvas.drawPath(path, Paint()..color = Colors.grey..style = PaintingStyle.stroke..strokeWidth = 1);
    }
  }

  @override
  bool shouldRepaint(covariant _CanonicalCadPainter oldDelegate) => false;
}

class _CanonicalOverlayPainter extends CustomPainter {
  _CanonicalOverlayPainter({required this.result});
  final PixelWallPipelineResult result;

  @override
  void paint(Canvas canvas, Size size) {
    for (final wall in result.model.walls) {
      canvas.drawLine(
        Offset(wall.start.x * size.width, wall.start.y * size.height),
        Offset(wall.end.x * size.width, wall.end.y * size.height),
        Paint()
          ..color = (wall.reviewNeeded ? Colors.orange : Colors.redAccent).withValues(alpha: 0.9)
          ..strokeWidth = wall.kind == SSWallKind.exterior ? 3 : 2,
      );
    }
    if (result.floorDomainClosed && result.model.floorDomain != null) {
      final path = Path()..addPolygon([for (final p in result.model.floorDomain!) Offset(p.x * size.width, p.y * size.height)], true);
      canvas.drawPath(path, Paint()..color = Colors.blueAccent..style = PaintingStyle.stroke..strokeWidth = 1.5);
    }
    // §12 — SemanticZone은 기본 Overlay에 fake CAD line으로 그리지 않는다.
    // 실제 physical wall/FloorDomain만 원본 위에 표시한다(label 없음).
  }

  @override
  bool shouldRepaint(covariant _CanonicalOverlayPainter oldDelegate) => false;
}
