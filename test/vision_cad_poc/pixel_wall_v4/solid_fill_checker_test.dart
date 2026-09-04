// SPACE SHIFT — PC1 CONTINUE: EXTERIOR GRAPH ROOT-CAUSE RECOVERY.
//
// 116px ROI를 정밀 조사(darkness profile 직접 측정)한 결과, 애초
// 의심했던 "가구/설비 아이콘이 구조 벽으로 오분류"라는 가설은 부분적
// 으로만 맞았다 — 실제로는 해당 candidate의 대부분 구간(y=183~275)이
// 폭 7~8px의 진짜 벽이었고, 단 2~3곳의 짧은 구간(y=171~179, 239~243)
// 에서만 가구/T-junction으로 폭이 넓어졌다. 즉 "116px gap"의 진짜
// 원인은 false structural이 아니라, 이 실제 벽이 x=31.3 시스템과는
// 별개의 물리적으로 다른 벽(안방 자신의 좌측 경계 등)이라 서로 연결될
// 필요가 없었다는 것 — 완료 보고에 상세 기록.
//
// 그래도 "run-length 두께 측정이 자기 두께 바깥의 밝기를 전혀 보지
// 않는다"는 root cause 자체는 실재하는 일반적 결함이라, [_SolidFillChecker]
// 를 pixel_wall_extractor.dart에 추가했다(향후 진짜 순수 아이콘 사례에
// 대비). 이 테스트는 그 안전장치가 진짜 얇은 벽을 오탐하지 않는다는
// 최소 회귀 방지만 검증한다 — "완전히 채워진 도형만 있는" 합성 이미지로
// 체커의 trigger 조건을 재현하려는 시도는 mergeRunsToBands가 이미
// 폭 전체를 정확한 두께로 보고해(가짜 gap 자체가 발생하지 않음) 의미
// 있는 양성 사례를 안정적으로 합성하기 어려웠다(실제 버그는 "부분적
// 두께 언더에스티메이트"라는, 실제 시나리오에서만 드물게 나타나는
// 조합이었기 때문).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_extractor.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_types.dart';

Uint8List _thinWallImage() {
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
  // 순수 얇은 내벽(두께 6px) — 위아래는 항상 밝은 바닥.
  thickLine(150, 40, 150, 160);
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  test('진짜 얇은 내벽은 구조 벽으로 유지된다(solid-fill 안전장치가 오탐하지 않음)', () {
    final result = extractPixelWalls(_thinWallImage());
    final centerWall = result.candidates.where(
      (c) => c.orientation == PixelWallOrientation.vertical && (c.start.x * result.analysisWidthPx - 150).abs() < 10 && !c.isExterior,
    );
    expect(centerWall, isNotEmpty);
    for (final c in centerWall) {
      expect(c.category, PixelWallCategory.structural, reason: '진짜 얇은 벽이 solid-fill로 오탐되면 안 된다');
    }
  });
}
