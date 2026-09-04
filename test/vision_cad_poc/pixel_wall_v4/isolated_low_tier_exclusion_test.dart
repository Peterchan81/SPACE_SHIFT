// SPACE SHIFT — PC1 CONTINUE: LOCAL STRUCTURAL GAP RECOVERY.
//
// 실측 발견: exterior로 분류된 candidate 중 정확히 "LOW confidence
// tier + junction 지지 0"인 것이 실제로는 화살표/포인터 기호(현관
// 라벨 위쪽 안내선)였다 — 이 도면의 다른 모든 진짜 exterior candidate는
// 최소 MEDIUM 이상이거나 junction≥1이었다. 이 조합을 일반 규칙으로
// 적용해 exterior/structural에서 검토 대상으로 내린다(좌표 하드코딩
// 아님 — 이미지 전체에 동일하게 적용됨).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_extractor.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_types.dart';

Uint8List _floorPlanWithIsolatedShortLine() {
  final image = img.Image(width: 300, height: 200);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  void thickLine(int x1, int y1, int x2, int y2) {
    for (var t = -3; t <= 3; t++) {
      if (y1 == y2) {
        img.drawLine(image, x1: x1, y1: y1 + t, x2: x2, y2: y2 + t, color: img.ColorRgb8(0, 0, 0));
      } else {
        img.drawLine(image, x1: x1 + t, y1: y1, x2: x2 + t, y2: y2, color: img.ColorRgb8(0, 0, 0));
      }
    }
  }

  thickLine(30, 30, 270, 30);
  thickLine(30, 170, 270, 170);
  thickLine(30, 30, 30, 170);
  thickLine(270, 30, 270, 170);
  // 진짜 벽과 완전히 동떨어진, 아주 짧고 얇은 고립선(화살표/포인터
  // 기호를 흉내) — 어떤 실제 벽과도 맞닿지 않는다(junction=0 예상).
  for (var y = 5; y < 20; y++) {
    image.setPixel(150, y, img.ColorRgb8(0, 0, 0));
    image.setPixel(151, y, img.ColorRgb8(0, 0, 0));
  }
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  test('LOW tier + junction 0 조합의 고립된 짧은 선(화살표 등)은 exterior로 확정되지 않는다', () {
    final result = extractPixelWalls(_floorPlanWithIsolatedShortLine());
    final isolatedLine = result.candidates.where(
      (c) => c.orientation == PixelWallOrientation.vertical && (c.start.x * result.analysisWidthPx - 150).abs() < 5 && c.start.y * result.analysisHeightPx < 25,
    );
    for (final c in isolatedLine) {
      if (c.confidenceTier == PixelWallConfidenceTier.low && c.junctionSupport == 0) {
        expect(c.isExterior, isFalse, reason: 'LOW+junction0 조합의 고립선은 exterior로 확정되면 안 된다');
        expect(c.category, PixelWallCategory.reviewNeeded);
      }
    }

    // 진짜 외벽 4개는 회귀 없이 그대로 유지돼야 한다.
    final exteriorWalls = result.candidates.where((c) => c.isExterior).toList();
    expect(exteriorWalls.length, greaterThanOrEqualTo(4));
  });
}
