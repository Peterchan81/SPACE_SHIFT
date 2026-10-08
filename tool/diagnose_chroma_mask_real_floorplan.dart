// SS CAD TEST — Wall Detection Coverage WO §1(계속): 기존 buildStructuralMask
// (dark AND low-chroma)가 실제 평면도의 바닥색 오탐(§otsu_mask.png의 검은
// 덩어리)을 실제로 없애는지 먼저 눈으로 확인한다 — production 코드를
// 바꾸기 전 가설 검증.
// 실행: flutter test tool/diagnose_chroma_mask_real_floorplan.dart
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:ason_space/vision_cad_poc/drafting_v1/structural_layer.dart';

const String kRealFloorplanPath = r'C:\Users\user\Desktop\스크린샷\평면도.PNG';
const String kOutDir = r'C:\Users\user\AppData\Local\Temp\claude\c--ASON-Floorplan-CAD-Test\ba23118b-7f08-48d9-a2c2-f01e24e298e4\scratchpad';

void main() {
  test('buildStructuralMask(dark+low-chroma) 결과 저장', () {
    final file = File(kRealFloorplanPath);
    if (!file.existsSync()) {
      print('SKIP');
      return;
    }
    final bytes = file.readAsBytesSync();
    final result = buildStructuralMask(bytes);
    print('lumThreshold=${result.lumThreshold} chromaThreshold=${result.chromaThreshold} w=${result.w} h=${result.h}');

    final maskImg = img.Image(width: result.w, height: result.h);
    for (var y = 0; y < result.h; y++) {
      for (var x = 0; x < result.w; x++) {
        final on = result.structuralMask[y * result.w + x] == 1;
        maskImg.setPixel(x, y, on ? img.ColorRgb8(0, 0, 0) : img.ColorRgb8(255, 255, 255));
      }
    }
    File('$kOutDir/chroma_structural_mask.png').writeAsBytesSync(img.encodePng(maskImg));
    print('저장: $kOutDir/chroma_structural_mask.png');

    // baseline(luminance-only) mask도 같이 저장해 나란히 비교.
    final baselineImg = img.Image(width: result.w, height: result.h);
    for (var y = 0; y < result.h; y++) {
      for (var x = 0; x < result.w; x++) {
        final on = result.grayscale[y * result.w + x] <= result.lumThreshold;
        baselineImg.setPixel(x, y, on ? img.ColorRgb8(0, 0, 0) : img.ColorRgb8(255, 255, 255));
      }
    }
    File('$kOutDir/chroma_baseline_mask.png').writeAsBytesSync(img.encodePng(baselineImg));
    print('저장: $kOutDir/chroma_baseline_mask.png');
  });
}
