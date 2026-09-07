// SPACE SHIFT — WO088-7 WALL CENTERLINE POC — IMAGE 4. dart run 전용.
// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

import 'package:ason_space/vision_cad_poc/centerline_v1/centerline_junction.dart';
import 'package:ason_space/vision_cad_poc/centerline_v1/centerline_model.dart';
import 'package:ason_space/vision_cad_poc/drafting_v1/structural_layer.dart' show buildStructuralMask;

const _imagePath = r'C:\ASON\SPACE_SHIFT\test\image4.PNG';

void main() {
  final bytes = File(_imagePath).readAsBytesSync();
  final structural = buildStructuralMask(bytes);
  final w = structural.w, h = structural.h;
  print('=== IMAGE 4 ===');
  print('analysis: ${w}x$h, lumThreshold=${structural.lumThreshold}, chromaThreshold=${structural.chromaThreshold}');

  final evidence = extractLineEvidence(structural.structuralMask, w, h);
  print('\n=== §4 SOLID/DASHED ===');
  print('solid candidate count=${evidence.solidBands.length}');
  print('dashed/reference candidate count=${evidence.dashedBands.length}');
  print('pattern(tile/grid texture, 벽 아님으로 분리) candidate count=${evidence.patternBands.length}');

  final pairs = pairWallBoundaries(evidence.solidBands);
  final pairedCount = pairs.where((p) => !p.singleBoundary).length;
  final singleCount = pairs.where((p) => p.singleBoundary).length;
  print('\n=== §5 BOUNDARY PAIRING ===');
  print('paired(양쪽 경계 확정)=$pairedCount, single-boundary fallback=$singleCount, 합계=${pairs.length}');

  final centerlines = buildCenterlines(pairs);
  final horizCount = centerlines.where((c) => c.horizontal).length;
  final vertCount = centerlines.where((c) => !c.horizontal).length;
  final reviewCount = centerlines.where((c) => c.reviewNeeded).length;
  print('\n=== §6 CENTERLINE ===');
  print('총 centerline=${centerlines.length}, horizontal=$horizCount, vertical=$vertCount, reviewNeeded=$reviewCount');

  final spacedLines = centerlines.where((c) => c.boundarySpacingPx != null).toList();
  if (spacedLines.isNotEmpty) {
    final avgSpacing = spacedLines.map((c) => c.boundarySpacingPx!).reduce((a, b) => a + b) / spacedLines.length;
    final avgDeviation = spacedLines.map((c) => (c.aToCenterPx! - c.centerToBPx!).abs()).reduce((a, b) => a + b) / spacedLines.length;
    final maxDeviation = spacedLines.map((c) => (c.aToCenterPx! - c.centerToBPx!).abs()).reduce(math.max);
    print('\n=== §12 ACCURACY(px 기준, mm 아님) ===');
    print('평균 boundary spacing=${avgSpacing.toStringAsFixed(2)}px');
    print('평균 |A→center - center→B| 비대칭=${avgDeviation.toStringAsFixed(3)}px');
    print('최대 |A→center - center→B| 비대칭=${maxDeviation.toStringAsFixed(3)}px');
  }

  final junctions = buildCenterlineJunctions(centerlines);
  final byKind = <JunctionKind, int>{};
  for (final j in junctions) {
    byKind[j.kind] = (byKind[j.kind] ?? 0) + 1;
  }
  print('\n=== §8 JUNCTION ===');
  for (final k in JunctionKind.values) {
    print('${k.name}=${byKind[k] ?? 0}');
  }

  // ---- 중복/겹침 centerline 점검(§11.9) ----
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
  print('\n중복/겹침 의심 centerline 쌍 수=$duplicateCount');

  // ---- 이미지 산출물 A~F ----
  final original = img.decodeImage(bytes)!;

  // A. ORIGINAL (그대로 복사 저장 — 비교 편의용).
  File(r'C:\ASON\SPACE_SHIFT\test\image4_wo7_A_original.png').writeAsBytesSync(img.encodePng(original));

  // B. SOLID / DASHED EVIDENCE.
  final imgB = img.Image.from(original);
  for (final band in evidence.solidBands) {
    img.drawLine(imgB, x1: band.start.x.round(), y1: band.start.y.round(), x2: band.end.x.round(), y2: band.end.y.round(), color: img.ColorRgb8(0, 90, 220), thickness: 2);
  }
  for (final band in evidence.dashedBands) {
    img.drawLine(imgB, x1: band.start.x.round(), y1: band.start.y.round(), x2: band.end.x.round(), y2: band.end.y.round(), color: img.ColorRgb8(255, 140, 0), thickness: 2);
  }
  for (final band in evidence.patternBands) {
    img.drawLine(imgB, x1: band.start.x.round(), y1: band.start.y.round(), x2: band.end.x.round(), y2: band.end.y.round(), color: img.ColorRgb8(0, 200, 0), thickness: 1);
  }
  File(r'C:\ASON\SPACE_SHIFT\test\image4_wo7_B_solid_dashed.png').writeAsBytesSync(img.encodePng(imgB));

  // C. WALL BOUNDARY ONLY(흰 배경).
  final imgC = img.Image(width: w, height: h);
  img.fill(imgC, color: img.ColorRgb8(255, 255, 255));
  for (final p in pairs) {
    final aBand = evidence.solidBands.firstWhere((band) => band.id == p.boundaryAId);
    img.drawLine(imgC, x1: aBand.start.x.round(), y1: aBand.start.y.round(), x2: aBand.end.x.round(), y2: aBand.end.y.round(), color: img.ColorRgb8(0, 0, 0), thickness: 1);
    if (p.boundaryBId != null) {
      final bBand = evidence.solidBands.firstWhere((band) => band.id == p.boundaryBId);
      img.drawLine(imgC, x1: bBand.start.x.round(), y1: bBand.start.y.round(), x2: bBand.end.x.round(), y2: bBand.end.y.round(), color: img.ColorRgb8(0, 0, 0), thickness: 1);
    }
  }
  File(r'C:\ASON\SPACE_SHIFT\test\image4_wo7_C_wall_boundary_only.png').writeAsBytesSync(img.encodePng(imgC));

  img.Color colorForCenterline(Centerline c) => c.reviewNeeded ? img.ColorRgb8(255, 140, 0) : img.ColorRgb8(220, 0, 40);

  // D. ORIGINAL + CENTERLINE.
  final imgD = img.Image.from(original);
  for (final c in centerlines) {
    img.drawLine(imgD, x1: c.start.x.round(), y1: c.start.y.round(), x2: c.end.x.round(), y2: c.end.y.round(), color: colorForCenterline(c), thickness: 2);
  }
  File(r'C:\ASON\SPACE_SHIFT\test\image4_wo7_D_original_plus_centerline.png').writeAsBytesSync(img.encodePng(imgD));

  // E. CENTERLINE ONLY(흰 배경).
  final imgE = img.Image(width: w, height: h);
  img.fill(imgE, color: img.ColorRgb8(255, 255, 255));
  for (final c in centerlines) {
    img.drawLine(imgE, x1: c.start.x.round(), y1: c.start.y.round(), x2: c.end.x.round(), y2: c.end.y.round(), color: colorForCenterline(c), thickness: 2);
  }
  File(r'C:\ASON\SPACE_SHIFT\test\image4_wo7_E_centerline_only.png').writeAsBytesSync(img.encodePng(imgE));

  // F. CENTERLINE + JUNCTION.
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
    img.drawLine(imgF, x1: c.start.x.round(), y1: c.start.y.round(), x2: c.end.x.round(), y2: c.end.y.round(), color: img.ColorRgb8(60, 60, 60), thickness: 2);
  }
  for (final j in junctions) {
    img.fillCircle(imgF, x: j.point.x.round(), y: j.point.y.round(), radius: j.kind == JunctionKind.xJunction || j.kind == JunctionKind.tJunction ? 4 : 3, color: colorForJunction(j.kind));
  }
  File(r'C:\ASON\SPACE_SHIFT\test\image4_wo7_F_centerline_junction.png').writeAsBytesSync(img.encodePng(imgF));

  print('\n산출물 저장 완료:');
  print('  test/image4_wo7_A_original.png');
  print('  test/image4_wo7_B_solid_dashed.png');
  print('  test/image4_wo7_C_wall_boundary_only.png');
  print('  test/image4_wo7_D_original_plus_centerline.png');
  print('  test/image4_wo7_E_centerline_only.png');
  print('  test/image4_wo7_F_centerline_junction.png');
}
