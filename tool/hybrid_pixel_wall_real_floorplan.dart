// SS CAD TEST — Hybrid Geometry Recovery 1단계 진단.
//
// 실제 평면도.PNG에 대해 pixel_wall_v4(§4 조사에서 확인된, 이미
// endpoint snap/T-L-X junction split/중복 병합/문 gap bridging을 구현한
// 규칙 기반 엔진)만 돌려(semantic=null, GPT 좌표 전혀 관여하지 않음)
// topology 품질을 먼저 확인한다. GPT 좌표를 그대로 CAD로 확정하던 기존
// 접근과 대조하기 위한 진단 스크립트 — 아직 DXF는 만들지 않는다.
//
// 실행: flutter test tool/hybrid_pixel_wall_real_floorplan.dart (네트워크 없음)
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_pipeline.dart';

const String kRealFloorplanPath = r'C:\Users\user\Desktop\스크린샷\평면도.PNG';
const String kOverlayOutPath =
    r'C:\Users\user\AppData\Local\Temp\claude\c--ASON-Floorplan-CAD-Test\ba23118b-7f08-48d9-a2c2-f01e24e298e4\scratchpad\pixel_wall_v4_real_overlay.png';

void main() {
  test('pixel_wall_v4 geometry-only run against real floor plan', () {
    final file = File(kRealFloorplanPath);
    if (!file.existsSync()) {
      print('SKIP: 실제 평면도 파일 없음');
      return;
    }
    final bytes = file.readAsBytesSync();

    final result = runPixelWallPipeline(imageBytes: bytes, semantic: null);
    final cad = buildCadFloorPlanFromSpatialModel(result.model);

    print('=== FLOOR DOMAIN ===');
    print('closed=${result.floorDomainClosed} failureReason=${result.floorDomainFailureReason}');
    final topo = result.floorDomain.topology;
    if (topo != null) {
      print('status=${topo.status.name} disconnectedComponents=${topo.disconnectedComponents} '
          'danglingEdgeCount=${topo.danglingEdgeCount} openLoop=${topo.openLoop}');
      print('repairActions=${topo.repairActions}');
      print('unresolvedReasons=${topo.unresolvedReasons}');
    } else {
      print('topology diagnostics: null(구 chain walker 경로)');
    }
    print('graphVertexCount=${result.floorDomain.graphVertexCount} '
        'graphEdgeCount=${result.floorDomain.graphEdgeCount} '
        'graphFaceCount=${result.floorDomain.graphFaceCount} '
        'tJunctionCount=${result.floorDomain.tJunctionCount}');

    print('\n=== CAD WALLS (${cad.walls.length}) ===');
    for (final w in cad.walls) {
      final pxLen = cad.pixelDistance(w.start, w.end);
      print('id=${w.id} type=${w.wallType.name} conf=${w.confidence.toStringAsFixed(2)} '
          'reviewNeeded=${w.reviewNeeded} start=(${w.start.x.toStringAsFixed(4)},${w.start.y.toStringAsFixed(4)}) '
          'end=(${w.end.x.toStringAsFixed(4)},${w.end.y.toStringAsFixed(4)}) pxLen=${pxLen.toStringAsFixed(1)}');
    }

    print('\n=== OPENINGS (${cad.openings.length}) ===');
    for (final o in cad.openings) {
      print('id=${o.id} type=${o.type.name} conf=${o.confidence.toStringAsFixed(2)} '
          'wallId=${o.wallId} reviewNeeded=${o.reviewNeeded}');
    }
    print('door=${result.doorOpeningCount} window=${result.windowOpeningCount} unknown=${result.unknownOpeningCount} '
        'imageBreakOnlyGaps=${result.imageBreakOnlyGapCount}');

    print('\n=== ROOMS (${cad.rooms.length}) ===');
    for (final r in cad.rooms) {
      print('id=${r.id} name=${r.name} conf=${r.confidence.toStringAsFixed(2)} pts=${r.polygon.length}');
    }

    print('\n=== WARNINGS (${cad.warnings.length}) ===');
    for (final w in cad.warnings) {
      print('- $w');
    }

    // 오버레이
    final decoded = img.decodeImage(bytes)!;
    final w = decoded.width, h = decoded.height;
    final overlay = img.Image.from(decoded);
    for (final wall in cad.walls) {
      final x1 = (wall.start.x * w).round();
      final y1 = (wall.start.y * h).round();
      final x2 = (wall.end.x * w).round();
      final y2 = (wall.end.y * h).round();
      final color = wall.wallType == CadWallType.exterior ? img.ColorRgb8(255, 0, 0) : img.ColorRgb8(0, 120, 255);
      img.drawLine(overlay, x1: x1, y1: y1, x2: x2, y2: y2, color: color, thickness: 3);
    }
    for (final o in cad.openings) {
      final cx = (o.center.x * w).round();
      final cy = (o.center.y * h).round();
      img.fillCircle(overlay, x: cx, y: cy, radius: 8, color: img.ColorRgb8(255, 165, 0));
    }
    File(kOverlayOutPath).writeAsBytesSync(img.encodePng(overlay));
    print('\n오버레이 저장: $kOverlayOutPath');
  });
}
