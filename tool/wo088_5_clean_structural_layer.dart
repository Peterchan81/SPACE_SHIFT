// SPACE SHIFT — WO088-5 CLEAN STRUCTURAL LAYER A/B (PRE-CLEAN BEFORE WALL
// EXTRACTION). dart run 전용(Flutter 의존 없음).
// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

import 'package:ason_space/vision_cad_poc/drafting_v1/drafting_model.dart';
import 'package:ason_space/vision_cad_poc/drafting_v1/line_confirmation.dart';
import 'package:ason_space/vision_cad_poc/drafting_v1/pre_clean.dart';
import 'package:ason_space/vision_cad_poc/drafting_v1/structural_layer.dart';

const _imagePath = r'C:\ASON\SPACE_SHIFT\test\image3.png';
const _wingX0 = 560, _wingY0 = 0, _wingX1 = 840, _wingY1 = 350;

List<RawStructuralLine> _extractAll(dynamic mask, int w, int h, double minRunPx, double maxThicknessPx) {
  final axisLines = extractAxisAlignedLines(mask, w, h, minRunPx: minRunPx, maxThicknessPx: maxThicknessPx);
  final axisOutsideWing = axisLines.where((l) {
    final midX = (l.start.x + l.end.x) / 2, midY = (l.start.y + l.end.y) / 2;
    return !(midX >= _wingX0 && midX <= _wingX1 && midY >= _wingY0 && midY <= _wingY1);
  }).toList();
  final wingLines = extractLocalDeskewedLines(mask, w, h, x0: _wingX0, y0: _wingY0, x1: _wingX1, y1: _wingY1, minRunPx: minRunPx, maxThicknessPx: maxThicknessPx);
  return [...axisOutsideWing, ...wingLines];
}

void main() {
  final bytes = File(_imagePath).readAsBytesSync();
  final structural = buildStructuralMask(bytes);
  final w = structural.w, h = structural.h;
  final diagonal = math.sqrt(w * w + h * h);
  final minRunPx = math.max(6.0, diagonal * 0.02);
  const maxThicknessPx = 20.0;

  // ---- WO088-4 baseline(A) — 이미 검증된 결과를 그대로 재사용해 비교 대상으로 삼는다 ----
  final linesA = _extractAll(structural.structuralMask, w, h, minRunPx, maxThicknessPx);
  final modelA = buildDraftingModel(linesA);
  print('=== A (WO088-4 baseline) ===');
  print('lines=${linesA.length} corners=${modelA.corners.length}');

  // ---- WO088-5 PRE-CLEAN(B), 1차 시도: pixel/component-level elongation ----
  // 실패로 판정되어 폐기(§14 STOP → 원인분석 → 대체 접근). 근거:
  // 실제 벽은 corner에서 서로 물려 "하나의 연결된 mesh"를 이룬다 —
  // 그 mesh 전체의 bounding box는 이미지 자체의 종횡비에 가까워
  // elongation이 낮게(약 1.5) 나온다. threshold를 낮추면 노이즈 blob까지
  // 통째로 다시 허용되고, 높이면 진짜 벽 mesh 전체가 통째로 제거된다 —
  // 이 metric 자체가 "연결된 벽 네트워크"에는 적용 불가능하다(실측
  // 확인: 억제 251/290 컴포넌트, kept pixel 531/39617 — 벽 mesh 전체가
  // 사라짐). 아래 preClean() 호출은 이 실패를 재현/기록하기 위해서만
  // 남겨둔다 — production 경로에서는 쓰지 않는다.
  final failedPixelLevelPreClean = preClean(structural.structuralMask, w, h);
  print('\n=== PRE-CLEAN 1차 시도(component-level elongation) — 실패 기록 ===');
  print('연결 요소 총 ${failedPixelLevelPreClean.componentCount}개, 억제 ${failedPixelLevelPreClean.suppressedComponentCount}개');
  final keptPixels1 = failedPixelLevelPreClean.cleanMask.fold(0, (s, v) => s + v);
  print('kept pixel=$keptPixels1 / ${structural.structuralMask.fold(0, (s, v) => s + v)} — 벽 mesh 전체가 "하나의 컴포넌트"라 통째로 제거됨(FAIL, 원인: connectivity가 elongation을 무의미하게 만듦)');

  // ---- WO088-5 PRE-CLEAN(B), 2차 접근(채택): line-candidate-level evidence ----
  // structural mask(WO088-4, 변경 없음)에서 run-length로 개별 직선
  // segment를 먼저 뽑은 뒤(이미 mesh를 개별 벽 조각으로 분해한 상태),
  // 그 "조각" 각각에 대해 §9 evidence(길이/junction 연결/반복패턴)를
  // 적용한다 — mesh 전체가 아니라 이미 분해된 개별 조각에 적용하므로
  // 위 1차 시도의 실패 원인(연결성 때문에 elongation 무의미화)이 생기지
  // 않는다.
  final linesB = _extractAll(structural.structuralMask, w, h, minRunPx, maxThicknessPx);
  final verdicts = confirmWalls(linesB, imageW: w, imageH: h);
  final confirmedLines = verdicts.where((v) => v.confirmed).map((v) => v.line).toList();
  // §16 — reviewNeeded(suppressed)로 판정된 것도 화면에서 사라지면 안
  // 된다(삭제가 아니라 구분 표시). confirmed+suppressed 전체로 모델을
  // 만들고, 렌더링 시 colorForWall()이 verdict를 참조해 구분 색을 쓴다.
  final modelB = buildDraftingModel(linesB);
  final verdictById = {for (final v in verdicts) v.line.id: v};

  print('\n=== B (WO088-5 Pre-Clean + Line Confirmation) ===');
  print('raw lines(clean mask에서 추출)=${linesB.length}');
  print('confirmed=${verdicts.where((v) => v.confirmed).length} suppressed=${verdicts.where((v) => !v.confirmed).length}');
  print('  substantialLength=${verdicts.where((v) => v.confirmReason == WallConfirmReason.substantialLength).length}');
  print('  junctionConnected=${verdicts.where((v) => v.confirmReason == WallConfirmReason.junctionConnected).length}');
  print('  suppressed(repeatedPatternCluster)=${verdicts.where((v) => v.suppressReason == WallSuppressReason.repeatedPatternCluster).length}');
  print('  suppressed(isolatedShort)=${verdicts.where((v) => v.suppressReason == WallSuppressReason.isolatedShort).length}');
  print('drafting model B: walls=${modelB.walls.length} corners=${modelB.corners.length} Origin=(${modelB.originPixel.x.toStringAsFixed(1)},${modelB.originPixel.y.toStringAsFixed(1)})');

  // ---- 이미지 산출물 ----
  final original = img.decodeImage(bytes)!;

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

  // 3. PRE-CLEAN / NOISE CLASSIFICATION 시각화 — line-candidate 단위로
  // 유지(파랑)/억제(빨강) 구분(§14 STOP 이후 채택된 line-level evidence
  // 접근의 실제 판정 결과를 그대로 시각화한다 — pixel-component 1차
  // 시도는 실패로 기록만 하고 시각화에는 쓰지 않는다).
  final classificationImg = img.Image(width: w, height: h);
  img.fill(classificationImg, color: img.ColorRgb8(255, 255, 255));
  for (final v in verdicts) {
    final color = v.confirmed ? img.ColorRgb8(0, 90, 220) : img.ColorRgb8(220, 40, 40);
    img.drawLine(classificationImg, x1: v.line.start.x.round(), y1: v.line.start.y.round(), x2: v.line.end.x.round(), y2: v.line.end.y.round(), color: color, thickness: 2);
  }
  File(r'C:\ASON\SPACE_SHIFT\test\image3_preclean_classification.png').writeAsBytesSync(img.encodePng(classificationImg));

  // 4. CLEAN STRUCTURAL LAYER — confirmed line만 다시 raster화한 binary
  // mask(§ Layer 3 산출물 — line-level evidence로 확정된 것만 남긴 결과).
  final cleanLayerMask = List<int>.filled(w * h, 0);
  for (final l in confirmedLines) {
    final steps = math.max((l.end.x - l.start.x).abs(), (l.end.y - l.start.y).abs()).round().clamp(1, 1 << 20);
    for (var s = 0; s <= steps; s++) {
      final t = s / steps;
      final x = (l.start.x + (l.end.x - l.start.x) * t).round();
      final y = (l.start.y + (l.end.y - l.start.y) * t).round();
      if (x >= 0 && y >= 0 && x < w && y < h) cleanLayerMask[y * w + x] = 1;
    }
  }
  saveMask(r'C:\ASON\SPACE_SHIFT\test\image3_clean_structural_layer.png', cleanLayerMask);

  // 6. B — Clean Structural Overlay(원본 + 추출된 line, confirmed/suppressed 색 구분).
  final overlayB = img.Image.from(original);
  for (final v in verdicts) {
    final color = v.confirmed ? img.ColorRgb8(0, 90, 220) : img.ColorRgb8(160, 160, 160);
    img.drawLine(overlayB, x1: v.line.start.x.round(), y1: v.line.start.y.round(), x2: v.line.end.x.round(), y2: v.line.end.y.round(), color: color, thickness: v.confirmed ? 3 : 1);
  }
  File(r'C:\ASON\SPACE_SHIFT\test\image3_clean_structural_overlay_B.png').writeAsBytesSync(img.encodePng(overlayB));

  // 8. B — Clean Drafting Coordinate Overlay(원본 위).
  img.Color colorForWall(DraftWall wall) {
    final v = verdictById[wall.id];
    if (v != null && !v.confirmed) return img.ColorRgb8(160, 160, 160);
    return switch (wall.classification) {
      WallAngleClass.orthogonalConfirmed => img.ColorRgb8(0, 87, 220),
      WallAngleClass.orthogonalCandidate => img.ColorRgb8(0, 150, 136),
      WallAngleClass.diagonalConfirmed => img.ColorRgb8(200, 0, 160),
      WallAngleClass.reviewNeeded => img.ColorRgb8(255, 140, 0),
    };
  }

  final draftOverlayB = img.Image.from(original);
  for (final wall in modelB.walls) {
    final sx = (wall.startVirtual.x + modelB.originPixel.x).round();
    final sy = (-wall.startVirtual.y + modelB.originPixel.y).round();
    final ex = (wall.endVirtual.x + modelB.originPixel.x).round();
    final ey = (-wall.endVirtual.y + modelB.originPixel.y).round();
    img.drawLine(draftOverlayB, x1: sx, y1: sy, x2: ex, y2: ey, color: colorForWall(wall), thickness: 2);
  }
  final oxB = modelB.originPixel.x.round(), oyB = modelB.originPixel.y.round();
  img.drawLine(draftOverlayB, x1: oxB, y1: oyB, x2: oxB + 70, y2: oyB, color: img.ColorRgb8(220, 0, 0), thickness: 3);
  img.drawLine(draftOverlayB, x1: oxB, y1: oyB, x2: oxB, y2: oyB - 70, color: img.ColorRgb8(0, 160, 0), thickness: 3);
  img.fillCircle(draftOverlayB, x: oxB, y: oyB, radius: 6, color: img.ColorRgb8(220, 0, 0));
  File(r'C:\ASON\SPACE_SHIFT\test\image3_clean_drafting_overlay_B.png').writeAsBytesSync(img.encodePng(draftOverlayB));

  // 9. B — CLEAN DRAFT ONLY(최종, 가장 중요) — confirmed walls만 실선,
  // 배경 최소화, Origin/코너 표시. reviewNeeded(있다면)는 별도 표시.
  var minX = 0.0, maxX = 0.0, minY = 0.0, maxY = 0.0;
  for (final wl in modelB.walls) {
    for (final p in [wl.startVirtual, wl.endVirtual]) {
      minX = math.min(minX, p.x);
      maxX = math.max(maxX, p.x);
      minY = math.min(minY, p.y);
      maxY = math.max(maxY, p.y);
    }
  }
  const canvasW = 1000, canvasH = 780;
  final rangeX = (maxX - minX) * 1.14, rangeY = (maxY - minY) * 1.14;
  final scale = math.min(canvasW / rangeX, canvasH / rangeY);
  final originCanvasX = -minX * scale + (canvasW - (maxX - minX) * scale) / 2;
  final originCanvasY = maxY * scale + (canvasH - (maxY - minY) * scale) / 2;
  (int, int) toCanvas(double vx, double vy) => ((vx * scale + originCanvasX).round(), (-vy * scale + originCanvasY).round());

  final draftOnly = img.Image(width: canvasW, height: canvasH);
  img.fill(draftOnly, color: img.ColorRgb8(255, 255, 255));
  for (final wall in modelB.walls) {
    final s = toCanvas(wall.startVirtual.x, wall.startVirtual.y);
    final e = toCanvas(wall.endVirtual.x, wall.endVirtual.y);
    img.drawLine(draftOnly, x1: s.$1, y1: s.$2, x2: e.$1, y2: e.$2, color: colorForWall(wall), thickness: 3);
  }
  for (final c in modelB.corners) {
    final p = toCanvas(c.point.x, c.point.y);
    img.fillCircle(draftOnly, x: p.$1, y: p.$2, radius: 3, color: img.ColorRgb8(0, 150, 0));
  }
  final o = toCanvas(0, 0);
  img.drawLine(draftOnly, x1: o.$1, y1: o.$2, x2: o.$1 + 60, y2: o.$2, color: img.ColorRgb8(220, 0, 0), thickness: 2);
  img.drawLine(draftOnly, x1: o.$1, y1: o.$2, x2: o.$1, y2: o.$2 - 60, color: img.ColorRgb8(0, 140, 0), thickness: 2);
  img.fillCircle(draftOnly, x: o.$1, y: o.$2, radius: 6, color: img.ColorRgb8(220, 0, 0));
  File(r'C:\ASON\SPACE_SHIFT\test\image3_clean_draft_only_B.png').writeAsBytesSync(img.encodePng(draftOnly));

  print('\n산출물 저장 완료:');
  print('  test/image3_preclean_classification.png');
  print('  test/image3_clean_structural_layer.png');
  print('  test/image3_clean_structural_overlay_B.png');
  print('  test/image3_clean_drafting_overlay_B.png');
  print('  test/image3_clean_draft_only_B.png');
}
