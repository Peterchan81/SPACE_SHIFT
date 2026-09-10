// SS CAD TEST — Wall Detection Coverage WO §1: 실패 원인 조사.
// floor_plan_analysis_engine.dart와 정확히 같은 grayscale/Otsu 이진화를
// 재현해 마스크를 이미지로 저장하고, pixel_wall_v4의 noiseCategory 분포를
// 출력한다 — 새 알고리즘을 만들기 전에 무엇이 실제로 벽을 놓치게 하는지
// 눈으로 확인하기 위해서다.
// 실행: flutter test tool/diagnose_wall_detection_real_floorplan.dart
// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:ason_space/services/floor_plan_analysis_engine.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_extractor.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_types.dart';

const String kRealFloorplanPath = r'C:\Users\user\Desktop\스크린샷\평면도.PNG';
const String kOutDir = r'C:\Users\user\AppData\Local\Temp\claude\c--ASON-Floorplan-CAD-Test\ba23118b-7f08-48d9-a2c2-f01e24e298e4\scratchpad';

void main() {
  test('grayscale/Otsu mask dump + noiseCategory breakdown', () {
    final file = File(kRealFloorplanPath);
    if (!file.existsSync()) {
      print('SKIP: 실제 평면도 파일 없음');
      return;
    }
    final bytes = file.readAsBytesSync();
    final decoded = img.decodeImage(bytes)!;
    final w = decoded.width, h = decoded.height;

    // floor_plan_analysis_engine.dart의 grayscale+histogram+Otsu와 동일한 계산.
    final luminance = Uint8List(w * h);
    final histogram = List<int>.filled(256, 0);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final l = decoded.getPixel(x, y).luminance.round().clamp(0, 255);
        luminance[y * w + x] = l;
        histogram[l]++;
      }
    }
    final threshold = otsuThreshold(histogram, w * h);
    print('Otsu threshold=$threshold (0~255, luminance<=threshold => "dark"/wall candidate)');

    // 히스토그램 요약(밝기 분포 확인 — 색상 채움이 임계값에 어떤 영향을 주는지).
    final buckets = List<int>.filled(8, 0);
    for (var i = 0; i < 256; i++) {
      buckets[i ~/ 32] += histogram[i];
    }
    print('밝기 분포(32단위 버킷, 0=어두움~7=밝음): $buckets');

    final maskImg = img.Image(width: w, height: h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final dark = luminance[y * w + x] <= threshold;
        maskImg.setPixel(x, y, dark ? img.ColorRgb8(0, 0, 0) : img.ColorRgb8(255, 255, 255));
      }
    }
    File('$kOutDir/otsu_mask.png').writeAsBytesSync(img.encodePng(maskImg));
    print('저장: $kOutDir/otsu_mask.png');

    // pixel_wall_v4 raw candidate noiseCategory 분포.
    final extraction = extractPixelWalls(bytes);
    print('\n=== raw WallSegment(engine) 대비 candidate 분포 ===');
    print('총 candidate: ${extraction.candidates.length}');
    final byCategory = <PixelWallCategory, int>{};
    for (final c in extraction.candidates) {
      byCategory[c.category] = (byCategory[c.category] ?? 0) + 1;
    }
    print('category: $byCategory');

    final byOrientationLen = <String, List<double>>{'horizontal': [], 'vertical': []};
    for (final c in extraction.candidates) {
      final pxLen = c.orientation == PixelWallOrientation.horizontal
          ? (c.end.x - c.start.x).abs() * extraction.analysisWidthPx
          : (c.end.y - c.start.y).abs() * extraction.analysisHeightPx;
      byOrientationLen[c.orientation.name]!.add(pxLen);
    }
    for (final entry in byOrientationLen.entries) {
      entry.value.sort();
      print('${entry.key}: n=${entry.value.length} lengths(px)=${entry.value.map((v) => v.toStringAsFixed(0)).toList()}');
    }

    // 원본 위에 raw candidate(분류 전) 전부를 얇게 겹쳐 그린다 — noise 필터링
    // "전"의 원시 검출 결과가 실제 벽 위치와 얼마나 겹치는지 확인용.
    final overlay = img.Image.from(decoded);
    for (final c in extraction.candidates) {
      final x1 = (c.start.x * w).round();
      final y1 = (c.start.y * h).round();
      final x2 = (c.end.x * w).round();
      final y2 = (c.end.y * h).round();
      final color = c.category == PixelWallCategory.structural ? img.ColorRgb8(0, 200, 0) : img.ColorRgb8(255, 0, 255);
      img.drawLine(overlay, x1: x1, y1: y1, x2: x2, y2: y2, color: color, thickness: 2);
    }
    File('$kOutDir/raw_candidates_overlay.png').writeAsBytesSync(img.encodePng(overlay));
    print('저장: $kOutDir/raw_candidates_overlay.png (녹색=structural, 자홍=reviewNeeded)');
  });
}
