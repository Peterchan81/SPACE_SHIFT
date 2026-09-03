// SPACE SHIFT — Vision-Guided Full Pixel Wall Extraction POC.
// 일회성 조사 스크립트(§3) — 구현 전 실제 이미지 픽셀 특성을 확인한다.
// package:image만 사용(Flutter 의존 없음)해서 순수 dart run으로 실행.

import 'dart:io';

import 'package:image/image.dart' as img;

const path = r'C:\Users\user\Desktop\스크린샷\평면도1.PNG';

void main() {
  final bytes = File(path).readAsBytesSync();
  final image = img.decodeImage(bytes)!;
  final w = image.width, h = image.height;
  print('Resolution: ${w}x$h');

  final lum = List<int>.filled(w * h, 0);
  final hist = List<int>.filled(256, 0);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final l = image.getPixel(x, y).luminance.round().clamp(0, 255);
      lum[y * w + x] = l;
      hist[l]++;
    }
  }

  // Otsu.
  var sumAll = 0.0;
  for (var i = 0; i < 256; i++) {
    sumAll += i * hist[i];
  }
  var sumBg = 0.0, wBg = 0, maxVar = -1.0, threshold = 128;
  final total = w * h;
  for (var t = 0; t < 256; t++) {
    wBg += hist[t];
    if (wBg == 0) continue;
    final wFg = total - wBg;
    if (wFg == 0) break;
    sumBg += t * hist[t];
    final mBg = sumBg / wBg;
    final mFg = (sumAll - sumBg) / wFg;
    final varBetween = wBg * wFg * (mBg - mFg) * (mBg - mFg);
    if (varBetween > maxVar) {
      maxVar = varBetween;
      threshold = t;
    }
  }
  print('Otsu threshold: $threshold');

  // Histogram distribution summary (percentiles).
  var cum = 0;
  final percentiles = <int>[];
  for (var i = 0; i < 256; i++) {
    cum += hist[i];
    if (percentiles.length < 10 && cum >= total * (percentiles.length + 1) / 10) {
      percentiles.add(i);
    }
  }
  print('Luminance decile boundaries: $percentiles');
  print('Dark pixel ratio (<=threshold): ${(hist.sublist(0, threshold + 1).reduce((a, b) => a + b) / total * 100).toStringAsFixed(1)}%');

  bool isDark(int x, int y) {
    if (x < 0 || y < 0 || x >= w || y >= h) return false;
    return lum[y * w + x] <= threshold;
  }

  // Sample known wall crossings (from e2e_v3 axes) to measure real thickness.
  // V04 (안방|거실 방향) x ≈ 0.358*443 ≈ 158~159, scan a horizontal slice.
  void sampleVerticalThicknessAt(int xCenter, int ySample, String label) {
    var left = xCenter, right = xCenter;
    while (left > 0 && isDark(left - 1, ySample)) {
      left--;
    }
    while (right < w - 1 && isDark(right + 1, ySample)) {
      right++;
    }
    final found = isDark(xCenter, ySample);
    print('$label: x=$xCenter y=$ySample dark=$found band=[$left,$right] thickness=${right - left + 1}');
  }

  void sampleHorizontalThicknessAt(int yCenter, int xSample, String label) {
    var top = yCenter, bottom = yCenter;
    while (top > 0 && isDark(xSample, top - 1)) {
      top--;
    }
    while (bottom < h - 1 && isDark(xSample, bottom + 1)) {
      bottom++;
    }
    final found = isDark(xSample, yCenter);
    print('$label: y=$yCenter x=$xSample dark=$found band=[$top,$bottom] thickness=${bottom - top + 1}');
  }

  // 안방|거실 vertical wall around x=158, sample at several y within range 172..280.
  for (final y in [180, 220, 260]) {
    sampleVerticalThicknessAt(158, y, 'masterBedroom|living wall candidate');
  }
  // 거실|침실2 vertical wall around x=265.
  for (final y in [180, 220, 260]) {
    sampleVerticalThicknessAt(265, y, 'living|bedroom2 wall candidate');
  }
  // 침실2|침실1 vertical wall around x=311.
  for (final y in [180, 220, 260]) {
    sampleVerticalThicknessAt(311, y, 'bedroom2|bedroom1 wall candidate');
  }
  // Row-divider horizontal wall around y=172.
  for (final x in [80, 200, 350]) {
    sampleHorizontalThicknessAt(172, x, 'row-divider wall candidate');
  }
  // Top exterior facade around y=17 (0.0382*300ish).
  for (final x in [200, 300]) {
    sampleHorizontalThicknessAt(17, x, 'top exterior facade candidate');
  }

  // Furniture/fixture stroke sample: check a bathroom fixture area for
  // comparison (approx bath1 region from e2e_v3: x~300-350,y~90-150).
  var darkCountInBathArea = 0, totalInBathArea = 0;
  for (var y = 90; y < 150; y++) {
    for (var x = 300; x < 353; x++) {
      totalInBathArea++;
      if (isDark(x, y)) darkCountInBathArea++;
    }
  }
  print('Bath fixture area dark ratio: ${(darkCountInBathArea / totalInBathArea * 100).toStringAsFixed(1)}%');

  // Text label stroke sample near a room label (rough guess area).
  // Just report overall connected-run-length stats for horizontal scans
  // across the whole image to see typical "wall-like" run lengths vs noise.
  final runLengths = <int>[];
  for (var y = 0; y < h; y++) {
    var runStart = -1;
    for (var x = 0; x <= w; x++) {
      final dark = x < w && isDark(x, y);
      if (dark) {
        runStart = runStart == -1 ? x : runStart;
      } else if (runStart != -1) {
        runLengths.add(x - runStart);
        runStart = -1;
      }
    }
  }
  runLengths.sort();
  print('Horizontal dark run-length stats: count=${runLengths.length}, '
      'min=${runLengths.first}, p50=${runLengths[runLengths.length ~/ 2]}, '
      'p90=${runLengths[(runLengths.length * 0.9).floor()]}, max=${runLengths.last}');

  // Distribution of "thin" runs (likely text/furniture strokes, 1-4px) vs
  // "thick structural" runs.
  final thin = runLengths.where((r) => r <= 4).length;
  final short = runLengths.where((r) => r > 4 && r <= 15).length;
  final long = runLengths.where((r) => r > 15).length;
  print('Run length buckets: thin(<=4px)=$thin short(5-15px)=$short long(>15px)=$long');
}
