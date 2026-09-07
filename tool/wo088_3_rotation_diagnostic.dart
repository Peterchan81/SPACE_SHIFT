// SPACE SHIFT — WO088-3 IMAGE 3 ROTATION -10.5° ROOT-CAUSE INVESTIGATION.
// DIAGNOSTIC ONLY — does not import, call, or modify anything in
// floor_plan_analysis_engine.dart (importing it transitively pulls in
// package:flutter via floor_plan_geometry.dart, which breaks plain `dart
// run` — so even the public otsuThreshold() is independently reimplemented
// here rather than imported, to keep this script self-contained and fully
// decoupled from production code). It reproduces the documented algorithm
// shape (Otsu threshold -> projection-profile variance search over a
// downsampled mask) purely for diagnostic measurement; the production
// rotation estimator itself is never touched, called, or changed.
// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Otsu's method — 표준 교과서 알고리즘의 독립 재구현(진단 전용). 로직은
/// floor_plan_analysis_engine.dart의 otsuThreshold()와 동일한 표준 공식을
/// 따르지만, production 코드를 import/호출하지 않는다.
int otsuThreshold(List<int> histogram, int totalPixels) {
  if (totalPixels == 0) return 128;
  var sumAll = 0.0;
  for (var i = 0; i < 256; i++) {
    sumAll += i * histogram[i];
  }
  var sumBackground = 0.0;
  var weightBackground = 0;
  var maxVariance = -1.0;
  var threshold = 128;
  for (var t = 0; t < 256; t++) {
    weightBackground += histogram[t];
    if (weightBackground == 0) continue;
    final weightForeground = totalPixels - weightBackground;
    if (weightForeground == 0) break;
    sumBackground += t * histogram[t];
    final meanBackground = sumBackground / weightBackground;
    final meanForeground = (sumAll - sumBackground) / weightForeground;
    final betweenVariance = weightBackground * weightForeground * (meanBackground - meanForeground) * (meanBackground - meanForeground);
    if (betweenVariance > maxVariance) {
      maxVariance = betweenVariance;
      threshold = t;
    }
  }
  return threshold;
}

const _imagePath = r'C:\ASON\SPACE_SHIFT\test\image3.png';
const _maskOutPath = r'C:\ASON\SPACE_SHIFT\test\image3_rotation_mask_full.png';
const _probeMaxDim = 220; // matches _kRotationProbeMaxDimension in production.

// ---- faithful reproduction of the production mask (steps 1-3 of the
// documented pipeline, floor_plan_analysis_engine.dart header comment) ----

({Uint8List mask, int w, int h, int threshold}) buildFullMask(Uint8List bytes) {
  final decoded = img.decodeImage(bytes)!;
  const kMaxAnalysisDimension = 900; // same constant as production.
  final longest = math.max(decoded.width, decoded.height);
  final scale = longest > kMaxAnalysisDimension ? kMaxAnalysisDimension / longest : 1.0;
  final aw = math.max(1, (decoded.width * scale).round());
  final ah = math.max(1, (decoded.height * scale).round());
  final analysisImage = scale < 1.0 ? img.copyResize(decoded, width: aw, height: ah, interpolation: img.Interpolation.average) : decoded;
  final w = analysisImage.width, h = analysisImage.height;

  final luminance = Uint8List(w * h);
  final histogram = List<int>.filled(256, 0);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final l = analysisImage.getPixel(x, y).luminance.round().clamp(0, 255);
      luminance[y * w + x] = l;
      histogram[l]++;
    }
  }
  final threshold = otsuThreshold(histogram, w * h);
  final mask = Uint8List(w * h);
  for (var i = 0; i < mask.length; i++) {
    mask[i] = luminance[i] <= threshold ? 1 : 0;
  }
  return (mask: mask, w: w, h: h, threshold: threshold);
}

// ---- independent reproduction of _downsampleMaskForProbe ----

({Uint8List mask, int w, int h}) downsampleForProbe(Uint8List mask, int w, int h) {
  final longest = math.max(w, h);
  if (longest <= _probeMaxDim) return (mask: mask, w: w, h: h);
  final scale = _probeMaxDim / longest;
  final pw = math.max(1, (w * scale).round());
  final ph = math.max(1, (h * scale).round());
  final probe = Uint8List(pw * ph);
  for (var y = 0; y < ph; y++) {
    final sy = math.min(h - 1, (y / scale).round());
    for (var x = 0; x < pw; x++) {
      final sx = math.min(w - 1, (x / scale).round());
      probe[y * pw + x] = mask[sy * w + sx];
    }
  }
  return (mask: probe, w: pw, h: ph);
}

({double x, double y}) rotateAround(double x, double y, double cx, double cy, double angleRad) {
  final dx = x - cx, dy = y - cy;
  final cosA = math.cos(angleRad), sinA = math.sin(angleRad);
  return (x: cx + dx * cosA - dy * sinA, y: cy + dx * sinA + dy * cosA);
}

int bilinearSample(Uint8List mask, int w, int h, double x, double y) {
  final x0 = x.floor(), y0 = y.floor();
  final fx = x - x0, fy = y - y0;
  int at(int xi, int yi) => (xi < 0 || yi < 0 || xi >= w || yi >= h) ? 0 : mask[yi * w + xi];
  final v00 = at(x0, y0), v10 = at(x0 + 1, y0), v01 = at(x0, y0 + 1), v11 = at(x0 + 1, y0 + 1);
  final top = v00 * (1 - fx) + v10 * fx;
  final bottom = v01 * (1 - fx) + v11 * fx;
  return (top * (1 - fy) + bottom * fy) >= 0.5 ? 1 : 0;
}

Uint8List resampleRotated(Uint8List source, int w, int h, double angleRad) {
  final dest = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final src = rotateAround(x.toDouble(), y.toDouble(), w / 2, h / 2, angleRad);
      dest[y * w + x] = bilinearSample(source, w, h, src.x, src.y);
    }
  }
  return dest;
}

double variance(List<int> values) {
  if (values.isEmpty) return 0;
  var sum = 0.0;
  for (final v in values) {
    sum += v;
  }
  final mean = sum / values.length;
  var sq = 0.0;
  for (final v in values) {
    sq += (v - mean) * (v - mean);
  }
  return sq / values.length;
}

double alignmentScore(Uint8List probeMask, int pw, int ph, double angleDeg) {
  final rotated = angleDeg == 0 ? probeMask : resampleRotated(probeMask, pw, ph, angleDeg * math.pi / 180);
  final rowSums = List<int>.filled(ph, 0);
  final colSums = List<int>.filled(pw, 0);
  for (var y = 0; y < ph; y++) {
    for (var x = 0; x < pw; x++) {
      if (rotated[y * pw + x] == 1) {
        rowSums[y]++;
        colSums[x]++;
      }
    }
  }
  return variance(rowSums) + variance(colSums);
}

/// 프로덕션과 동일한 탐색(coarse -45..45 step 3 -> refine ±2.5 step 0.5,
/// zeroScore*1.08 미만이면 0으로 되돌림)을 그대로 재현해 "우리 재구현이
/// 실제로 -10.5°를 재현하는지"를 먼저 검증한다(신뢰성 확인).
(double angle, double score, double zeroScore) productionSearch(Uint8List mask, int w, int h) {
  final probe = downsampleForProbe(mask, w, h);
  final zeroScore = alignmentScore(probe.mask, probe.w, probe.h, 0);
  var bestAngle = 0.0, bestScore = zeroScore;
  void search(double from, double to, double step) {
    var angle = from;
    while (angle <= to + 1e-9) {
      if (angle != 0) {
        final score = alignmentScore(probe.mask, probe.w, probe.h, angle);
        if (score > bestScore) {
          bestScore = score;
          bestAngle = angle;
        }
      }
      angle += step;
    }
  }

  search(-45, 45, 3);
  final coarse = bestAngle;
  search(coarse - 2.5, coarse + 2.5, 0.5);
  if (bestScore < zeroScore * 1.08) return (0, zeroScore, zeroScore);
  return (double.parse(bestAngle.toStringAsFixed(1)), bestScore, zeroScore);
}

/// §6/§8 진단용 — 지정 각도 범위 전체를 촘촘히 스캔해 score curve 전체를
/// 얻는다(production은 coarse+refine만 하지만, 여기서는 -10.5°가 얼마나
/// "뾰족한" peak인지, 다른 국소 peak은 없는지 보기 위해 fine sweep).
List<(double angle, double score)> fineSweep(Uint8List mask, int w, int h, {double from = -20, double to = 20, double step = 0.25}) {
  final probe = downsampleForProbe(mask, w, h);
  final out = <(double, double)>[];
  var angle = from;
  while (angle <= to + 1e-9) {
    out.add((double.parse(angle.toStringAsFixed(2)), alignmentScore(probe.mask, probe.w, probe.h, angle)));
    angle += step;
  }
  return out;
}

/// §7 영역 제외 A/B — [w]x[h] 원본(비다운샘플) mask에서 지정 bbox를
/// 0으로 지운 사본을 만든다.
Uint8List maskWithRegionCleared(Uint8List mask, int w, int h, int x0, int y0, int x1, int y1) {
  final out = Uint8List.fromList(mask);
  for (var y = math.max(0, y0); y < math.min(h, y1); y++) {
    for (var x = math.max(0, x0); x < math.min(w, x1); x++) {
      out[y * w + x] = 0;
    }
  }
  return out;
}

/// §6.B/C 근사 — "장문의 직선 evidence만" 근사하기 위해, 회전 없이(원본
/// 방향 그대로) 각 행/열에서 연속 dark-run 길이가 [minRun] 이상인 픽셀만
/// 남긴다(수평 run 또는 수직 run 중 하나라도 만족하면 통과) — production의
/// band-merge/threshold 로직을 재사용하지 않는 독립적인 근사 필터다.
Uint8List longRunOnlyMask(Uint8List mask, int w, int h, int minRun) {
  final keep = Uint8List(w * h);
  // horizontal runs.
  for (var y = 0; y < h; y++) {
    var runStart = -1;
    for (var x = 0; x <= w; x++) {
      final v = x < w ? mask[y * w + x] : 0;
      if (v == 1) {
        if (runStart == -1) runStart = x;
      } else if (runStart != -1) {
        if (x - runStart >= minRun) {
          for (var xx = runStart; xx < x; xx++) {
            keep[y * w + xx] = 1;
          }
        }
        runStart = -1;
      }
    }
  }
  // vertical runs.
  for (var x = 0; x < w; x++) {
    var runStart = -1;
    for (var y = 0; y <= h; y++) {
      final v = y < h ? mask[y * w + x] : 0;
      if (v == 1) {
        if (runStart == -1) runStart = y;
      } else if (runStart != -1) {
        if (y - runStart >= minRun) {
          for (var yy = runStart; yy < y; yy++) {
            keep[yy * w + x] = 1;
          }
        }
        runStart = -1;
      }
    }
  }
  return keep;
}

int countOnes(Uint8List mask) => mask.fold(0, (s, v) => s + v);

void main() {
  step6WillRunAfterMain();
  step6();
}

void step6WillRunAfterMain() {
  final bytes = File(_imagePath).readAsBytesSync();
  final full = buildFullMask(bytes);
  print('=== WO088-3 STEP 1: 프로덕션과 동일한 mask 재구성 ===');
  print('analysis: ${full.w}x${full.h}, otsuThreshold=${full.threshold}, dark(mask=1) pixel count=${countOnes(full.mask)} / ${full.w * full.h} (${(countOnes(full.mask) * 100 / (full.w * full.h)).toStringAsFixed(1)}%)');

  // 진단용 mask 시각화 저장.
  final maskImg = img.Image(width: full.w, height: full.h);
  for (var y = 0; y < full.h; y++) {
    for (var x = 0; x < full.w; x++) {
      final v = full.mask[y * full.w + x];
      maskImg.setPixel(x, y, v == 1 ? img.ColorRgb8(0, 0, 0) : img.ColorRgb8(255, 255, 255));
    }
  }
  File(_maskOutPath).writeAsBytesSync(img.encodePng(maskImg));
  print('mask 시각화 저장: $_maskOutPath');

  print('\n=== WO088-3 STEP 2: production 탐색 재현(신뢰성 검증) ===');
  final repro = productionSearch(full.mask, full.w, full.h);
  print('재구현 결과 각도=${repro.$1}° (score=${repro.$2.toStringAsFixed(1)}, zeroScore=${repro.$3.toStringAsFixed(1)}, ratio=${(repro.$2 / repro.$3).toStringAsFixed(3)})');
  print('(참고: 이전 probe에서 실제 pixel_wall_extractor.dart 실행 결과는 rotationDegrees=-10.5였다 — 위 값과 비교)');

  print('\n=== WO088-3 STEP 3: fine sweep(-20~20°, 0.25 step) — 전체 evidence(ALL) ===');
  final sweepAll = fineSweep(full.mask, full.w, full.h);
  final sortedAll = [...sweepAll]..sort((a, b) => b.$2.compareTo(a.$2));
  print('top 5 peaks(ALL evidence):');
  for (final p in sortedAll.take(5)) {
    print('  angle=${p.$1}°  score=${p.$2.toStringAsFixed(1)}');
  }
  final zeroEntry = sweepAll.firstWhere((p) => p.$1 == 0.0);
  print('score at 0°: ${zeroEntry.$2.toStringAsFixed(1)} vs best: ${sortedAll.first.$2.toStringAsFixed(1)} (ratio best/zero = ${(sortedAll.first.$2 / zeroEntry.$2).toStringAsFixed(3)})');

  print('\n=== WO088-3 STEP 4: §7 영역 제외 A/B(원본 비다운샘플 mask에서 bbox 0으로 지움) ===');
  // 우측 계단형 외곽 돌출부 근사 bbox(이전 overlay 크롭에서 확인한 좌표 기준).
  final noRightWing = maskWithRegionCleared(full.mask, full.w, full.h, 560, 0, 840, 350);
  final rNoRightWing = productionSearch(noRightWing, full.w, full.h);
  print('A) 우측 계단형 외곽(x:560-840,y:0-350) 제외 -> ${rNoRightWing.$1}° (score=${rNoRightWing.$2.toStringAsFixed(1)}, ratio=${(rNoRightWing.$2 / rNoRightWing.$3).toStringAsFixed(3)})');

  // 욕실/드레스룸/현관 밀집(설비 아이콘/해칭/도어아크) bbox 근사.
  final noFixtureCluster = maskWithRegionCleared(full.mask, full.w, full.h, 280, 150, 560, 340);
  final rNoFixture = productionSearch(noFixtureCluster, full.w, full.h);
  print('B) 욕실/드레스룸/현관 밀집구역(x:280-560,y:150-340) 제외 -> ${rNoFixture.$1}° (score=${rNoFixture.$2.toStringAsFixed(1)}, ratio=${(rNoFixture.$2 / rNoFixture.$3).toStringAsFixed(3)})');

  // 두 영역 모두 제외.
  final noBoth = maskWithRegionCleared(noRightWing, full.w, full.h, 280, 150, 560, 340);
  final rNoBoth = productionSearch(noBoth, full.w, full.h);
  print('C) A+B 모두 제외 -> ${rNoBoth.$1}° (score=${rNoBoth.$2.toStringAsFixed(1)}, ratio=${(rNoBoth.$2 / rNoBoth.$3).toStringAsFixed(3)})');

  print('\n=== WO088-3 STEP 5: §6.B/C "장문 직선 evidence만"(원본 방향 run-length >= 12px 필터, 회전 전) ===');
  final longRun12 = longRunOnlyMask(full.mask, full.w, full.h, 12);
  print('long-run(>=12px) mask pixel count = ${countOnes(longRun12)} / ${countOnes(full.mask)} (원본 mask의 ${(countOnes(longRun12) * 100 / countOnes(full.mask)).toStringAsFixed(1)}%)');
  final rLongRun12 = productionSearch(longRun12, full.w, full.h);
  print('long-run(>=12px)만 사용 -> ${rLongRun12.$1}° (score=${rLongRun12.$2.toStringAsFixed(1)}, ratio=${(rLongRun12.$2 / rLongRun12.$3).toStringAsFixed(3)})');

  final longRun25 = longRunOnlyMask(full.mask, full.w, full.h, 25);
  print('long-run(>=25px) mask pixel count = ${countOnes(longRun25)} / ${countOnes(full.mask)} (원본 mask의 ${(countOnes(longRun25) * 100 / countOnes(full.mask)).toStringAsFixed(1)}%)');
  final rLongRun25 = productionSearch(longRun25, full.w, full.h);
  print('long-run(>=25px)만 사용 -> ${rLongRun25.$1}° (score=${rLongRun25.$2.toStringAsFixed(1)}, ratio=${(rLongRun25.$2 / rLongRun25.$3).toStringAsFixed(3)})');

  // 우측 wing까지 함께 제외한 long-run 버전(가장 "구조 벽만"에 가까운 근사).
  final longRun25NoWing = maskWithRegionCleared(longRun25, full.w, full.h, 560, 0, 840, 350);
  final rLongRun25NoWing = productionSearch(longRun25NoWing, full.w, full.h);
  print('long-run(>=25px) + 우측 wing 제외 -> ${rLongRun25NoWing.$1}° (score=${rLongRun25NoWing.$2.toStringAsFixed(1)}, ratio=${(rLongRun25NoWing.$2 / rLongRun25NoWing.$3).toStringAsFixed(3)})');
}

void step6() {
  final bytes = File(_imagePath).readAsBytesSync();
  final full = buildFullMask(bytes);
  print('\n=== WO088-3 STEP 6: 바닥 텍스처 blob vs 우측 wing 외곽선 분리 테스트 ===');

  // (a) 바닥 텍스처 blob만 제외(거실 하단부 + 우측 침실 바닥 근처) — wing의
  // 실제 벽 외곽선(가늘게 그려진 검은 선)은 전혀 건드리지 않는다.
  final noFloorBlobsOnly = maskWithRegionCleared(full.mask, full.w, full.h, 20, 300, 230, 430);
  final noFloorBlobsOnly2 = maskWithRegionCleared(noFloorBlobsOnly, full.w, full.h, 540, 250, 760, 430);
  final rNoFloorBlobs = productionSearch(noFloorBlobsOnly2, full.w, full.h);
  print('a) 바닥 텍스처 blob만 제외(거실 하단 + 우측 침실 바닥) -> ${rNoFloorBlobs.$1}° (score=${rNoFloorBlobs.$2.toStringAsFixed(1)}, ratio=${(rNoFloorBlobs.$2 / rNoFloorBlobs.$3).toStringAsFixed(3)})');

  // (b) wing의 외곽선 영역(상단 계단형 라인)만 제외 — 바닥 blob은 그대로 둔다.
  final noWingOutlineOnly = maskWithRegionCleared(full.mask, full.w, full.h, 560, 0, 840, 260);
  final rNoWingOutline = productionSearch(noWingOutlineOnly, full.w, full.h);
  print('b) wing 외곽선(상단부, x:560-840,y:0-260)만 제외(바닥 blob은 유지) -> ${rNoWingOutline.$1}° (score=${rNoWingOutline.$2.toStringAsFixed(1)}, ratio=${(rNoWingOutline.$2 / rNoWingOutline.$3).toStringAsFixed(3)})');

  // (c) 둘 다 제외.
  final both = maskWithRegionCleared(noFloorBlobsOnly2, full.w, full.h, 560, 0, 840, 260);
  final rBoth = productionSearch(both, full.w, full.h);
  print('c) (a)+(b) 모두 제외 -> ${rBoth.$1}° (score=${rBoth.$2.toStringAsFixed(1)}, ratio=${(rBoth.$2 / rBoth.$3).toStringAsFixed(3)})');
}
