/// SS012 — MASTER UI 9 "Blue neon wireframe ISO" 진행 화면 미리보기. 가구/텍스트/바닥색 없이 선만
/// 네온 블루로 그린다([BlueLineCadPreview]와 같은 생각의 3D 버전) — 실제 생성된 [SpaceSceneV2]
/// geometry([SpaceSceneV2.triangles])의 변(edge)만 등각(isometric) 투영해 그린다. 화면 전용 3D
/// geometry·엔진을 새로 만들지 않는다(§구현 원칙 "기존 엔진 재사용").
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../../models/space_scene_v2.dart';
import '../../theme/ss_master_theme.dart';

class BlueNeonIsoPreview extends StatelessWidget {
  const BlueNeonIsoPreview({super.key, required this.scene});

  final SpaceSceneV2 scene;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(key: const Key('ssIsoConversionWireframe'), painter: _BlueNeonIsoPainter(scene), size: Size.infinite);
  }
}

class _BlueNeonIsoPainter extends CustomPainter {
  _BlueNeonIsoPainter(this.scene);
  final SpaceSceneV2 scene;

  // true isometric 30도 투영(표준 dimetric과 달리 세 축이 120도로 똑같이 보인다).
  static const double _cos30 = 0.8660254037844387;
  static const double _sin30 = 0.5;

  Offset _project(Vector3 v) => Offset((v.x - v.z) * _cos30, (v.x + v.z) * _sin30 - v.y);

  @override
  void paint(Canvas canvas, Size size) {
    if (scene.isEmpty) return;
    final edges = <(Offset, Offset)>{};
    void addEdge(Vector3 a, Vector3 b) => edges.add((_project(a), _project(b)));
    for (final t in scene.triangles) {
      addEdge(t.a, t.b);
      addEdge(t.b, t.c);
      addEdge(t.c, t.a);
    }
    if (edges.isEmpty) return;

    var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
    for (final e in edges) {
      for (final p in [e.$1, e.$2]) {
        if (p.dx < minX) minX = p.dx;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dy > maxY) maxY = p.dy;
      }
    }
    final spanX = maxX - minX;
    final spanY = maxY - minY;
    if (spanX <= 0 || spanY <= 0) return;
    const padding = 24.0;
    final availableW = size.width - padding * 2;
    final availableH = size.height - padding * 2;
    if (availableW <= 0 || availableH <= 0) return;
    final scaleFactor = math.min(availableW / spanX, availableH / spanY);
    final offsetX = padding + (availableW - spanX * scaleFactor) / 2 - minX * scaleFactor;
    final offsetY = padding + (availableH - spanY * scaleFactor) / 2 - minY * scaleFactor;

    Offset toScreen(Offset p) => Offset(offsetX + p.dx * scaleFactor, offsetY + p.dy * scaleFactor);

    final paint = Paint()
      ..color = SsMasterTheme.neonBlue.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    for (final e in edges) {
      canvas.drawLine(toScreen(e.$1), toScreen(e.$2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BlueNeonIsoPainter oldDelegate) => true;
}
