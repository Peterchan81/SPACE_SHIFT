// SS CAD TEST — 실제 평면도 GPT 3회 구조 분석 결과를 사람이 확인할 수
// 있게 좌표까지 전부 출력하고, 원본 사진 위에 벽 id/문/창/방을 그려
// 겹쳐 보여준다(실측1.PNG의 손글씨 치수와 대조하기 위해).
//
// 실행: flutter test --dart-define=GPT_FLOORPLAN_EDGE_FUNCTION_URL=... \
//   tool/real_floorplan_gpt_analysis.dart
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/services/gpt_floorplan_vision_service.dart';
import 'package:ason_space/services/vision_consolidation.dart';
import 'package:ason_space/services/vision_guided_spatial_model_builder.dart';

const String kRealFloorplanPath = r'C:\Users\user\Desktop\스크린샷\평면도.PNG';
const String kOverlayOutPath =
    r'C:\Users\user\AppData\Local\Temp\claude\c--ASON-Floorplan-CAD-Test\ba23118b-7f08-48d9-a2c2-f01e24e298e4\scratchpad\real_floorplan_gpt_overlay.png';

void main() {
  test('real floorplan GPT analysis + overlay dump', () async {
    final file = File(kRealFloorplanPath);
    if (!file.existsSync()) {
      print('SKIP: 실제 평면도 파일 없음 ($kRealFloorplanPath)');
      return;
    }
    const url = String.fromEnvironment('GPT_FLOORPLAN_EDGE_FUNCTION_URL');
    if (url.isEmpty) {
      print('SKIP: --dart-define=GPT_FLOORPLAN_EDGE_FUNCTION_URL 필요');
      return;
    }

    final bytes = file.readAsBytesSync();
    final builder = VisionGuidedSpatialModelBuilder(
      visionService: createVisionInterpretationService(),
    );

    final consolidated = await buildConsolidatedVisionCadFloorPlan(
      bytes,
      buildOnce: builder.buildCad,
      samples: 3,
    );

    print('=== sourceWidthPx/HeightPx ===');
    print('${consolidated.sourceWidthPx} x ${consolidated.sourceHeightPx}');

    print('\n=== WALLS (${consolidated.walls.length}) ===');
    for (final w in consolidated.walls) {
      final pxLen = consolidated.pixelDistance(w.start, w.end);
      print(
        'id=${w.id} type=${w.wallType.name} conf=${w.confidence.toStringAsFixed(2)} '
        'reviewNeeded=${w.reviewNeeded} '
        'start=(${w.start.x.toStringAsFixed(4)},${w.start.y.toStringAsFixed(4)}) '
        'end=(${w.end.x.toStringAsFixed(4)},${w.end.y.toStringAsFixed(4)}) '
        'pxLen=${pxLen.toStringAsFixed(1)}',
      );
    }

    print('\n=== OPENINGS (${consolidated.openings.length}) ===');
    for (final o in consolidated.openings) {
      print(
        'id=${o.id} type=${o.type.name} conf=${o.confidence.toStringAsFixed(2)} '
        'wallId=${o.wallId} center=(${o.center.x.toStringAsFixed(4)},${o.center.y.toStringAsFixed(4)}) '
        'widthNorm=${o.widthNormalized.toStringAsFixed(4)}',
      );
    }

    print('\n=== ROOMS (${consolidated.rooms.length}) ===');
    for (final r in consolidated.rooms) {
      print(
        'id=${r.id} name=${r.name} conf=${r.confidence.toStringAsFixed(2)} '
        'polygonPts=${r.polygon.length} '
        'polygon=${r.polygon.map((p) => '(${p.x.toStringAsFixed(3)},${p.y.toStringAsFixed(3)})').join(' ')}',
      );
    }

    print('\n=== WARNINGS (${consolidated.warnings.length}) ===');
    for (final w in consolidated.warnings) {
      print('- $w');
    }

    // ── 원본 사진 위에 오버레이 그리기 ──
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      print('오버레이 생성 실패: 이미지 디코드 불가');
      return;
    }
    final w = decoded.width, h = decoded.height;
    final overlay = img.Image.from(decoded);

    for (final wall in consolidated.walls) {
      final x1 = (wall.start.x * w).round();
      final y1 = (wall.start.y * h).round();
      final x2 = (wall.end.x * w).round();
      final y2 = (wall.end.y * h).round();
      final color = wall.wallType == CadWallType.exterior
          ? img.ColorRgb8(255, 0, 0)
          : img.ColorRgb8(0, 120, 255);
      img.drawLine(overlay, x1: x1, y1: y1, x2: x2, y2: y2, color: color, thickness: 4);
      final midX = ((x1 + x2) / 2).round();
      final midY = ((y1 + y2) / 2).round();
      img.drawString(
        overlay,
        wall.id,
        font: img.arial24,
        x: midX,
        y: midY,
        color: img.ColorRgb8(0, 200, 0),
      );
    }
    for (final o in consolidated.openings) {
      final cx = (o.center.x * w).round();
      final cy = (o.center.y * h).round();
      img.fillCircle(overlay, x: cx, y: cy, radius: 10, color: img.ColorRgb8(255, 165, 0));
      img.drawString(overlay, '${o.type.name}:${o.id}', font: img.arial24, x: cx + 12, y: cy, color: img.ColorRgb8(255, 140, 0));
    }
    for (final r in consolidated.rooms) {
      if (r.polygon.isEmpty) continue;
      final cx = (r.polygon.map((p) => p.x).reduce((a, b) => a + b) / r.polygon.length * w).round();
      final cy = (r.polygon.map((p) => p.y).reduce((a, b) => a + b) / r.polygon.length * h).round();
      img.drawString(overlay, r.name ?? r.id, font: img.arial24, x: cx, y: cy, color: img.ColorRgb8(150, 0, 150));
    }

    File(kOverlayOutPath).writeAsBytesSync(img.encodePng(overlay));
    print('\n오버레이 저장: $kOverlayOutPath');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
