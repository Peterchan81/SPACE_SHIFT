// SPACE SHIFT — WO088-4 PHASE A: STRUCTURAL LINE PREPROCESSING A/B.
// dart run 전용(Flutter 의존 없음) — lib/vision_cad_poc/drafting_v1/
// structural_layer.dart(마찬가지로 Flutter-free)만 사용한다.
// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

import 'package:ason_space/vision_cad_poc/drafting_v1/drafting_model.dart';
import 'package:ason_space/vision_cad_poc/drafting_v1/structural_layer.dart';

const _imagePath = r'C:\ASON\SPACE_SHIFT\test\image3.png';

void main() {
  final bytes = File(_imagePath).readAsBytesSync();
  final result = buildStructuralMask(bytes);
  final w = result.w, h = result.h;

  print('=== PHASE A: mask 통계 ===');
  print('analysis: ${w}x$h');
  print('lumThreshold(Otsu)=${result.lumThreshold}, chromaThreshold(Otsu)=${result.chromaThreshold}');
  int count(List<int> m) => m.fold(0, (s, v) => s + v);
  final aCount = count(result.baselineMask);
  final bCount = count(result.structuralMask);
  print('A(baseline, luminance-only dark) pixel count = $aCount (${(aCount * 100 / (w * h)).toStringAsFixed(1)}%)');
  print('B(structural, dark+low-chroma) pixel count = $bCount (${(bCount * 100 / (w * h)).toStringAsFixed(1)}%)  [-${(100 - bCount * 100 / aCount).toStringAsFixed(1)}% vs A]');

  // 산출물 1: grayscale.
  final grayImg = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final l = result.grayscale[y * w + x];
      grayImg.setPixel(x, y, img.ColorRgb8(l, l, l));
    }
  }
  File(r'C:\ASON\SPACE_SHIFT\test\image3_grayscale.png').writeAsBytesSync(img.encodePng(grayImg));

  // 산출물 2: structural mask(B) 시각화 — 비교를 위해 A도 함께 저장.
  void saveMask(String path, List<int> mask) {
    final im = img.Image(width: w, height: h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final v = mask[y * w + x];
        im.setPixel(x, y, v == 1 ? img.ColorRgb8(0, 0, 0) : img.ColorRgb8(255, 255, 255));
      }
    }
    File(path).writeAsBytesSync(img.encodePng(im));
  }

  saveMask(r'C:\ASON\SPACE_SHIFT\test\image3_baseline_mask_A.png', result.baselineMask);
  saveMask(r'C:\ASON\SPACE_SHIFT\test\image3_structural_mask.png', result.structuralMask);

  // 산출물 3: 원본+구조선 overlay(선 추출은 아래에서 수행 후 그린다).
  final diagonal = math.sqrt(w * w + h * h);
  final minRunPx = math.max(6.0, diagonal * 0.02);
  const maxThicknessPx = 20.0;

  final axisLines = extractAxisAlignedLines(result.structuralMask, w, h, minRunPx: minRunPx, maxThicknessPx: maxThicknessPx);

  // 우측 계단형/사선 wing — WO088-3에서 이미 식별된 bbox를 그대로
  // 재사용(같은 이미지에 대한 이미 검증된 관찰, 새 magic number 아님).
  const wingX0 = 560, wingY0 = 0, wingX1 = 840, wingY1 = 350;
  final wingAngle = estimateLocalDominantAngle(result.structuralMask, w, h, x0: wingX0, y0: wingY0, x1: wingX1, y1: wingY1);
  print('\n=== PHASE B 사전조사: 우측 wing 지역 각도 ===');
  print('wing bbox($wingX0,$wingY0)-($wingX1,$wingY1) local dominant angle = $wingAngle°');

  final wingLines = extractLocalDeskewedLines(
    result.structuralMask, w, h,
    x0: wingX0, y0: wingY0, x1: wingX1, y1: wingY1,
    minRunPx: minRunPx, maxThicknessPx: maxThicknessPx,
  );

  // wing bbox 내부에서 나온 axis-aligned 중복 후보는 제거(같은 벽을
  // 두 번 세지 않기 위해 — 아주 단순한 bbox 기준 제외).
  final axisLinesOutsideWing = axisLines.where((l) {
    final midX = (l.start.x + l.end.x) / 2;
    final midY = (l.start.y + l.end.y) / 2;
    return !(midX >= wingX0 && midX <= wingX1 && midY >= wingY0 && midY <= wingY1);
  }).toList();

  final allLines = [...axisLinesOutsideWing, ...wingLines];
  print('\n=== PHASE A/B 비교: structural line 개수 ===');
  print('B(structural mask) axis-aligned lines(wing 영역 제외) = ${axisLinesOutsideWing.length}');
  print('B(structural mask) wing local-deskew lines = ${wingLines.length}');
  print('B 합계 = ${allLines.length}');

  // A(baseline mask)에도 동일 추출기를 적용해 "몇 개가 나오는지"만
  // 참고 비교(전처리 자체의 효과를 보기 위함 — production 결과 61/41과는
  // 다른 별도 지표다, production은 이 파일의 추출기를 쓰지 않는다).
  final axisLinesA = extractAxisAlignedLines(result.baselineMask, w, h, minRunPx: minRunPx, maxThicknessPx: maxThicknessPx);
  print('A(baseline mask)에 동일 추출기 적용 시 axis-aligned lines = ${axisLinesA.length} (참고용 — phantom/텍스처 라인 포함 가능성 있음)');

  // 산출물 4: 원본+구조선 overlay.
  final overlayBase = img.decodeImage(bytes)!;
  final overlay = img.Image.from(overlayBase);
  for (final l in allLines) {
    final color = l.method == 'axisAligned' ? img.ColorRgb8(0, 90, 220) : img.ColorRgb8(200, 0, 160);
    img.drawLine(overlay, x1: l.start.x.round(), y1: l.start.y.round(), x2: l.end.x.round(), y2: l.end.y.round(), color: color, thickness: 2);
  }
  File(r'C:\ASON\SPACE_SHIFT\test\image3_structural_line_overlay.png').writeAsBytesSync(img.encodePng(overlay));

  // A/B 공정 비교용 — baseline mask(A)에도 같은 추출기를 적용한 overlay.
  final overlayA = img.Image.from(img.decodeImage(bytes)!);
  for (final l in axisLinesA) {
    img.drawLine(overlayA, x1: l.start.x.round(), y1: l.start.y.round(), x2: l.end.x.round(), y2: l.end.y.round(), color: img.ColorRgb8(220, 0, 0), thickness: 2);
  }
  File(r'C:\ASON\SPACE_SHIFT\test\image3_baseline_line_overlay_A.png').writeAsBytesSync(img.encodePng(overlayA));

  // ---- PHASE B: Drafting Coordinate Model ----
  final model = buildDraftingModel(allLines);
  final ortho = model.walls.where((w) => w.classification == WallAngleClass.orthogonalConfirmed).length;
  final diag = model.walls.where((w) => w.classification == WallAngleClass.diagonalConfirmed).length;
  final review = model.walls.where((w) => w.classification == WallAngleClass.reviewNeeded).length;
  print('\n=== PHASE B: Drafting Model ===');
  print('Origin(px, 원본/회전없음 분석 캔버스 기준) = (${model.originPixel.x.toStringAsFixed(1)}, ${model.originPixel.y.toStringAsFixed(1)})');
  print('walls=${model.walls.length} orthogonalConfirmed=$ortho diagonalConfirmed=$diag reviewNeeded=$review corners=${model.corners.length}');

  img.Color colorFor(DraftWall w) => switch (w.classification) {
    WallAngleClass.orthogonalConfirmed => img.ColorRgb8(0, 87, 220),
    WallAngleClass.orthogonalCandidate => img.ColorRgb8(0, 150, 136),
    WallAngleClass.diagonalConfirmed => img.ColorRgb8(200, 0, 160),
    WallAngleClass.reviewNeeded => img.ColorRgb8(255, 140, 0),
  };

  // 산출물 5: 원본 + Coordinate Draft overlay(Origin/axis/wall/corner, 원본
  // px 좌표계 그대로 겹쳐 그린다 — virtual은 px 역변환으로 되돌린다).
  final draftOverlay = img.Image.from(img.decodeImage(bytes)!);
  for (final wall in model.walls) {
    final sx = (wall.startVirtual.x + model.originPixel.x).round();
    final sy = (-wall.startVirtual.y + model.originPixel.y).round();
    final ex = (wall.endVirtual.x + model.originPixel.x).round();
    final ey = (-wall.endVirtual.y + model.originPixel.y).round();
    img.drawLine(draftOverlay, x1: sx, y1: sy, x2: ex, y2: ey, color: colorFor(wall), thickness: 2);
  }
  for (final c in model.corners) {
    final cx = (c.point.x + model.originPixel.x).round();
    final cy = (-c.point.y + model.originPixel.y).round();
    img.fillCircle(draftOverlay, x: cx, y: cy, radius: 3, color: img.ColorRgb8(0, 170, 0));
  }
  final ox = model.originPixel.x.round(), oy = model.originPixel.y.round();
  img.drawLine(draftOverlay, x1: ox, y1: oy, x2: ox + 70, y2: oy, color: img.ColorRgb8(220, 0, 0), thickness: 3);
  img.drawLine(draftOverlay, x1: ox, y1: oy, x2: ox, y2: oy - 70, color: img.ColorRgb8(0, 160, 0), thickness: 3);
  img.fillCircle(draftOverlay, x: ox, y: oy, radius: 6, color: img.ColorRgb8(220, 0, 0));
  File(r'C:\ASON\SPACE_SHIFT\test\image3_drafting_coordinate_overlay.png').writeAsBytesSync(img.encodePng(draftOverlay));

  // 산출물 6: Coordinate Draft Only(순수 virtual 좌표, 원본 없음).
  var minX = 0.0, maxX = 0.0, minY = 0.0, maxY = 0.0;
  for (final wl in model.walls) {
    for (final p in [wl.startVirtual, wl.endVirtual]) {
      minX = math.min(minX, p.x);
      maxX = math.max(maxX, p.x);
      minY = math.min(minY, p.y);
      maxY = math.max(maxY, p.y);
    }
  }
  const canvasW = 900, canvasH = 700;
  final rangeX = (maxX - minX) * 1.16, rangeY = (maxY - minY) * 1.16;
  final draftScale = math.min(canvasW / rangeX, canvasH / rangeY);
  final originCanvasX = -minX * draftScale + (canvasW - (maxX - minX) * draftScale) / 2;
  final originCanvasY = maxY * draftScale + (canvasH - (maxY - minY) * draftScale) / 2;
  (int x, int y) toDraftCanvas(double vx, double vy) => ((vx * draftScale + originCanvasX).round(), (-vy * draftScale + originCanvasY).round());

  final draftOnly = img.Image(width: canvasW, height: canvasH);
  img.fill(draftOnly, color: img.ColorRgb8(16, 20, 24));
  for (final wall in model.walls) {
    final s = toDraftCanvas(wall.startVirtual.x, wall.startVirtual.y);
    final e = toDraftCanvas(wall.endVirtual.x, wall.endVirtual.y);
    img.drawLine(draftOnly, x1: s.$1, y1: s.$2, x2: e.$1, y2: e.$2, color: colorFor(wall), thickness: 3);
  }
  for (final c in model.corners) {
    final p = toDraftCanvas(c.point.x, c.point.y);
    img.fillCircle(draftOnly, x: p.$1, y: p.$2, radius: 3, color: img.ColorRgb8(120, 255, 120));
  }
  final o = toDraftCanvas(0, 0);
  img.drawLine(draftOnly, x1: o.$1, y1: o.$2, x2: o.$1 + 50, y2: o.$2, color: img.ColorRgb8(255, 90, 90), thickness: 2);
  img.drawLine(draftOnly, x1: o.$1, y1: o.$2, x2: o.$1, y2: o.$2 - 50, color: img.ColorRgb8(140, 255, 140), thickness: 2);
  img.fillCircle(draftOnly, x: o.$1, y: o.$2, radius: 5, color: img.ColorRgb8(255, 90, 90));
  File(r'C:\ASON\SPACE_SHIFT\test\image3_drafting_coordinate_draft_only.png').writeAsBytesSync(img.encodePng(draftOnly));

  print('\n산출물 저장 완료:');
  print('  test/image3_grayscale.png');
  print('  test/image3_baseline_mask_A.png');
  print('  test/image3_structural_mask.png (B)');
  print('  test/image3_structural_line_overlay.png (B)');
  print('  test/image3_baseline_line_overlay_A.png (A, 비교용)');
  print('  test/image3_drafting_coordinate_overlay.png');
  print('  test/image3_drafting_coordinate_draft_only.png');
}
