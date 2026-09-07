// SPACE SHIFT — WO088-8C COORDINATE-BASED EXACT WALL CENTERLINE MICRO POC.
// dart run 전용.
// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'package:ason_space/vision_cad_poc/centerline_v1/centerline_junction.dart';
import 'package:ason_space/vision_cad_poc/centerline_v1/centerline_model.dart';
import 'package:ason_space/vision_cad_poc/centerline_v1/exact_axis_fit.dart';
import 'package:ason_space/vision_cad_poc/drafting_v1/structural_layer.dart' show buildStructuralMask;

const _imagePath = r'C:\ASON\SPACE_SHIFT\test\image4.PNG';

// §4 실측 발견: Image 4 파일 자체에 그림 전체를 둘러싸는 얇은(2~3px)
// 거의 무채색(rgb≈41,41,40) 테두리 프레임이 존재한다(픽셀 probe로 확인,
// 원본 A 이미지에는 육안으로 보이는 테두리선이 없음 — 이미지 파일 export
// 시 추가된 캔버스 프레임으로 판단됨). 이 프레임은 실제 벽 mesh와
// 맞닿아 있어 "가장 큰 연결요소" 기준(WO088-8A)만으로는 분리되지 않고,
// wall evidence band로 잡혀 그대로 두면 건물 외곽을 넘어 캔버스 끝까지
// 뻗는 line evidence가 된다. 이 필터는 Image 4 전용 매직넘버가 아니라
// "캔버스 경계에 거의 붙어 있고(≤2px) 그 축의 전체 길이의 95% 이상을
// 뒤덮는 band는 건축 벽이 아니라 사진/캔버스 테두리다"라는 일반적
// 기하 조건이다 — 실제 건물 외벽은 이미지 경계까지 딱 붙어서 전체
// 캔버스를 감싸는 사각형을 이루지 않는다(항상 여백이 있음, image4_A
// 원본에서 실측 확인).
const double _canvasFrameEdgeMarginPx = 2.0;
const double _canvasFrameSpanFraction = 0.95;

List<RawRunBand> _excludeCanvasFrameBands(List<RawRunBand> bands, int w, int h) {
  return bands.where((b) {
    final canvasSpan = b.horizontal ? w : h;
    final nearEdge = b.crossPx <= _canvasFrameEdgeMarginPx || b.crossPx >= canvasSpan - 1 - _canvasFrameEdgeMarginPx;
    final spansWholeCanvas = b.lengthPx >= canvasSpan * _canvasFrameSpanFraction;
    return !(nearEdge && spansWholeCanvas);
  }).toList();
}

List<int> _largestComponentMask(List<int> mask, int w, int h) {
  final labels = List<int>.filled(w * h, -1);
  var nextLabel = 0;
  final counts = <int, int>{};
  for (var start = 0; start < w * h; start++) {
    if (mask[start] != 1 || labels[start] != -1) continue;
    final label = nextLabel++;
    final stack = <int>[start];
    labels[start] = label;
    var count = 0;
    while (stack.isNotEmpty) {
      final idx = stack.removeLast();
      count++;
      final x = idx % w, y = idx ~/ w;
      for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)]) {
        final nx = x + dx, ny = y + dy;
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
        final nIdx = ny * w + nx;
        if (mask[nIdx] == 1 && labels[nIdx] == -1) {
          labels[nIdx] = label;
          stack.add(nIdx);
        }
      }
    }
    counts[label] = count;
  }
  final largest = (counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
  return [for (final l in labels) l == largest ? 1 : 0];
}

void main() {
  final bytes = File(_imagePath).readAsBytesSync();
  final original = img.decodeImage(bytes)!;
  final structural = buildStructuralMask(bytes);
  final w = structural.w, h = structural.h;
  print('=== IMAGE 4 investigation ===');
  print('analysis: ${w}x$h');

  // ---- §4 Wall Evidence: 최대 연결요소(WO088-8A/8B와 동일 방식, 재사용) ----
  final wallMask = _largestComponentMask(structural.structuralMask, w, h);
  print('wall evidence pixel=${wallMask.fold(0, (s, v) => s + v)}');

  // ---- skeleton(evidence 후보점 집합, 최종 centerline 아님) ----
  final skeleton = zhangSuenSkeleton(wallMask, w, h);
  final skeletonPoints = skeletonToPoints(skeleton, w, h);
  print('skeleton candidate point count=${skeletonPoints.length}');

  // ---- §5/§7 wall run 분할(WO088-7 재사용) + robust exact axis fitting(신규) ----
  final evidence = extractLineEvidence(Uint8List.fromList(wallMask), w, h);
  print('solid band(wall run 후보, 필터 전)=${evidence.solidBands.length}');

  final solidBands = _excludeCanvasFrameBands(evidence.solidBands, w, h);
  final excludedFrameCount = evidence.solidBands.length - solidBands.length;
  print('캔버스 프레임(건축 벽 아님, §4 실측)으로 제외=$excludedFrameCount');
  print('solid band(wall run 후보, 필터 후)=${solidBands.length}');

  final fits = buildExactCenterlines(solidBands, skeletonPoints);
  final centerlines = fits.map((f) => f.centerline).toList();
  final horizCount = centerlines.where((c) => c.horizontal).length;
  final vertCount = centerlines.where((c) => !c.horizontal).length;
  final reviewCount = centerlines.where((c) => c.reviewNeeded).length;

  print('\n=== §15 CENTERLINE FITTING ===');
  print('wall evidence group count(캔버스 프레임 제외 후)=${solidBands.length}');
  print('centerline count=${centerlines.length}');
  print('horizontal=$horizCount vertical=$vertCount diagonal=0(§6 — 이번 evidence는 전부 axis-aligned)');
  print('reviewNeeded=$reviewCount');

  final wellFit = fits.where((f) => f.quality.sampleCount >= 3).toList();
  if (wellFit.isNotEmpty) {
    final meanRes = wellFit.map((f) => f.quality.residualMean).reduce((a, b) => a + b) / wellFit.length;
    final maxRes = wellFit.map((f) => f.quality.residualMax).reduce(math.max);
    print('robust-fit(skeleton evidence >=3점) 라인 수=${wellFit.length}');
    print('residual mean(평균, of means)=${meanRes.toStringAsFixed(3)}px, residual max(전체 중 최댓값)=${maxRes.toStringAsFixed(3)}px');
  }
  final fallbackCount = fits.where((f) => f.quality.sampleCount < 3).length;
  print('skeleton evidence 부족(<3점) fallback 라인 수=$fallbackCount');

  // 중복 centerline 점검.
  var duplicateCount = 0;
  for (var i = 0; i < centerlines.length; i++) {
    for (var j = i + 1; j < centerlines.length; j++) {
      final a = centerlines[i], b = centerlines[j];
      if (a.horizontal != b.horizontal) continue;
      if ((a.crossPx - b.crossPx).abs() > 2) continue;
      final overlap = math.min(a.alongMaxPx, b.alongMaxPx) - math.max(a.alongMinPx, b.alongMinPx);
      if (overlap > 5) duplicateCount++;
    }
  }
  print('duplicate centerline count=$duplicateCount');

  // ---- §7-10 Junction — line-line 교점(WO088-7 buildCenterlineJunctions 재사용) ----
  final junctions = buildCenterlineJunctions(centerlines);
  final byKind = <JunctionKind, int>{};
  for (final j in junctions) {
    byKind[j.kind] = (byKind[j.kind] ?? 0) + 1;
  }
  print('\n=== §9 JUNCTION(line intersection 기반) ===');
  for (final k in JunctionKind.values) {
    print('${k.name}=${byKind[k] ?? 0}');
  }

  // ---- 정확한 수평/수직 검증: 모든 centerline이 시작/끝 cross 값이 완전히 동일한지 ----
  final tiltedCount = centerlines.where((c) => c.horizontal ? c.start.y != c.end.y : c.start.x != c.end.x).length;
  print('\npixel-tilt(시작/끝 cross 값 불일치) centerline 수=$tiltedCount (0이어야 mathematical line)');

  // ---- 이미지 산출물 A~F ----
  File(r'C:\ASON\SPACE_SHIFT\test\image4_wo8C_A_original.png').writeAsBytesSync(img.encodePng(original));

  // B. WALL EVIDENCE.
  final imgB = img.Image(width: w, height: h);
  img.fill(imgB, color: img.ColorRgb8(255, 255, 255));
  for (var i = 0; i < w * h; i++) {
    if (wallMask[i] == 1) imgB.setPixelRgb(i % w, i ~/ w, 0, 0, 0);
  }
  File(r'C:\ASON\SPACE_SHIFT\test\image4_wo8C_B_wall_evidence.png').writeAsBytesSync(img.encodePng(imgB));

  // C. CENTER AXIS SAMPLE — skeleton evidence가 가장 많은(=wobble이 잘
  // 드러나는) confident 가로벽 2개 + 세로벽 2개를 4배 확대한 패널로
  // 쌓아 "evidence 후보점(파랑) + 계산된 exact axis(빨강)"를 함께 보여준다.
  final byEvidence = [...fits]..sort((a, b) => b.quality.sampleCount.compareTo(a.quality.sampleCount));
  final sampleFits = [
    ...byEvidence.where((f) => !f.centerline.reviewNeeded && f.centerline.horizontal).take(2),
    ...byEvidence.where((f) => !f.centerline.reviewNeeded && !f.centerline.horizontal).take(2),
  ];
  const zoom = 4;
  const panelPad = 16;
  final panels = <img.Image>[];
  for (final f in sampleFits) {
    final c = f.centerline;
    final along0 = c.alongMinPx - 6, along1 = c.alongMaxPx + 6;
    final cross0 = c.crossPx - 14, cross1 = c.crossPx + 14;
    final panelW = ((along1 - along0) * zoom).round();
    final panelH = (((cross1 - cross0) * zoom) + 20).round();
    final panel = img.Image(width: math.max(panelW, 60), height: panelH);
    img.fill(panel, color: img.ColorRgb8(255, 255, 255));
    int px(double along, double cross) {
      final x = c.horizontal ? along : cross;
      return ((x - (c.horizontal ? along0 : cross0)) * zoom).round();
    }

    int py(double along, double cross) {
      final y = c.horizontal ? cross : along;
      return ((y - (c.horizontal ? cross0 : along0)) * zoom).round() + 20;
    }

    for (final p in skeletonPoints) {
      final along = c.horizontal ? p.x : p.y;
      final cross = c.horizontal ? p.y : p.x;
      if (along < along0 || along > along1) continue;
      if (cross < cross0 || cross > cross1) continue;
      img.fillCircle(panel, x: px(along, cross), y: py(along, cross), radius: 3, color: img.ColorRgb8(0, 90, 220));
    }
    img.drawLine(
      panel,
      x1: px(c.alongMinPx, c.crossPx),
      y1: py(c.alongMinPx, c.crossPx),
      x2: px(c.alongMaxPx, c.crossPx),
      y2: py(c.alongMaxPx, c.crossPx),
      color: img.ColorRgb8(220, 0, 40),
      thickness: 2,
    );
    final axisLabel = c.horizontal ? 'Y = ${c.crossPx.toStringAsFixed(1)}' : 'X = ${c.crossPx.toStringAsFixed(1)}';
    img.drawString(
      panel,
      '$axisLabel  (evidence=${f.quality.sampleCount}, residual mean=${f.quality.residualMean.toStringAsFixed(2)}px max=${f.quality.residualMax.toStringAsFixed(2)}px)',
      font: img.arial14,
      x: 4,
      y: 2,
      color: img.ColorRgb8(0, 0, 0),
    );
    panels.add(panel);
  }
  final imgC = img.Image(
    width: panels.isEmpty ? 200 : panels.map((p) => p.width).reduce(math.max) + panelPad * 2,
    height: panels.isEmpty ? 60 : panels.fold(panelPad, (s, p) => s + p.height + panelPad),
  );
  img.fill(imgC, color: img.ColorRgb8(255, 255, 255));
  var offsetY = panelPad;
  for (final p in panels) {
    img.compositeImage(imgC, p, dstX: panelPad, dstY: offsetY);
    offsetY += p.height + panelPad;
  }
  File(r'C:\ASON\SPACE_SHIFT\test\image4_wo8C_C_center_axis_sample.png').writeAsBytesSync(img.encodePng(imgC));

  img.Color colorForCenterline(Centerline c) => c.reviewNeeded ? img.ColorRgb8(255, 140, 0) : img.ColorRgb8(220, 0, 40);

  // D. ORIGINAL + MATHEMATICAL CENTERLINE(아주 얇게).
  final imgD = img.Image.from(original);
  for (final c in centerlines) {
    img.drawLine(imgD, x1: c.start.x.round(), y1: c.start.y.round(), x2: c.end.x.round(), y2: c.end.y.round(), color: colorForCenterline(c), thickness: 1);
  }
  File(r'C:\ASON\SPACE_SHIFT\test\image4_wo8C_D_original_plus_centerline.png').writeAsBytesSync(img.encodePng(imgD));

  // E. CENTERLINE ONLY.
  final imgE = img.Image(width: w, height: h);
  img.fill(imgE, color: img.ColorRgb8(255, 255, 255));
  for (final c in centerlines) {
    img.drawLine(imgE, x1: c.start.x.round(), y1: c.start.y.round(), x2: c.end.x.round(), y2: c.end.y.round(), color: colorForCenterline(c), thickness: 1);
  }
  File(r'C:\ASON\SPACE_SHIFT\test\image4_wo8C_E_centerline_only.png').writeAsBytesSync(img.encodePng(imgE));

  // F. CENTERLINE + CORNER/JUNCTION.
  img.Color colorForJunction(JunctionKind k) => switch (k) {
    JunctionKind.lJunction => img.ColorRgb8(0, 150, 0),
    JunctionKind.tJunction => img.ColorRgb8(0, 90, 220),
    JunctionKind.xJunction => img.ColorRgb8(160, 0, 200),
    JunctionKind.straightContinuation => img.ColorRgb8(0, 180, 180),
    JunctionKind.endpoint => img.ColorRgb8(120, 120, 120),
    JunctionKind.reviewNeeded => img.ColorRgb8(220, 0, 0),
  };
  final imgF = img.Image(width: w, height: h);
  img.fill(imgF, color: img.ColorRgb8(255, 255, 255));
  for (final c in centerlines) {
    img.drawLine(imgF, x1: c.start.x.round(), y1: c.start.y.round(), x2: c.end.x.round(), y2: c.end.y.round(), color: img.ColorRgb8(60, 60, 60), thickness: 1);
  }
  for (final j in junctions) {
    img.fillCircle(imgF, x: j.point.x.round(), y: j.point.y.round(), radius: j.kind == JunctionKind.xJunction || j.kind == JunctionKind.tJunction ? 4 : 3, color: colorForJunction(j.kind));
  }
  File(r'C:\ASON\SPACE_SHIFT\test\image4_wo8C_F_centerline_junction.png').writeAsBytesSync(img.encodePng(imgF));

  print('\n산출물 저장 완료:');
  print('  test/image4_wo8C_A_original.png');
  print('  test/image4_wo8C_B_wall_evidence.png');
  print('  test/image4_wo8C_C_center_axis_sample.png');
  print('  test/image4_wo8C_D_original_plus_centerline.png');
  print('  test/image4_wo8C_E_centerline_only.png');
  print('  test/image4_wo8C_F_centerline_junction.png');
}
