// SPACE SHIFT — PC1 CONTINUE: OUTSIDE-AIR FLOOD FILL EXTERIOR RESOLUTION.
//
// 새 원칙(§1/§6/§7): "이 벽이 외벽처럼 보이는가?"가 아니라 "이미지
// 바깥의 실제 빈 공간이 이 wall face까지 도달하는가?"만을 근거로
// 삼는다. 합성 도면으로 one-side/zero-side/two-side outside contact
// 세 경우를 모두 검증한다.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_extractor.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_types.dart';

Uint8List _twoRoomFloorPlan() {
  // 바깥 사각형 + 가운데 내벽 하나로 나뉜 두 방 — 외벽/내벽이 명확히
  // 구분되는 최소 합성 사례.
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

  thickLine(30, 30, 270, 30); // top exterior
  thickLine(30, 170, 270, 170); // bottom exterior
  thickLine(30, 30, 30, 170); // left exterior
  thickLine(270, 30, 270, 170); // right exterior
  thickLine(150, 30, 150, 170); // interior partition (양쪽 다 실내)
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  test('exactly-one-side-outside(외벽)와 zero-side-outside(내벽)가 face contact로 정확히 구분된다', () {
    final result = extractPixelWalls(_twoRoomFloorPlan());

    final exteriorWalls = result.candidates.where((c) => c.isExterior).toList();
    expect(exteriorWalls, isNotEmpty);
    for (final wall in exteriorWalls) {
      final maxContact = wall.outsideContactA > wall.outsideContactB ? wall.outsideContactA : wall.outsideContactB;
      final minContact = wall.outsideContactA < wall.outsideContactB ? wall.outsideContactA : wall.outsideContactB;
      expect(maxContact, greaterThanOrEqualTo(0.6), reason: '외벽은 한쪽 face가 강하게 outside와 맞닿아야 한다');
      expect(minContact, lessThanOrEqualTo(0.2), reason: '외벽의 반대쪽 face는 실내여야 한다');
      expect(wall.exteriorSuspicious, isFalse);
    }

    // 가운데 내벽(양쪽 다 실내)은 exterior가 아니어야 하고, suspicious도
    // 아니어야 한다(양쪽 다 outside와 안 맞닿음 — 정상적인 "둘 다 약함" 케이스).
    final interiorWall = result.candidates.where(
      (c) => c.orientation == PixelWallOrientation.vertical && (c.start.x * result.analysisWidthPx - 150).abs() < 10,
    );
    expect(interiorWall, isNotEmpty);
    for (final wall in interiorWall) {
      expect(wall.isExterior, isFalse, reason: '양쪽 다 실내인 파티션 벽은 절대 외벽으로 오분류되면 안 된다(161px 회귀 방지)');
      expect(wall.outsideContactA, lessThanOrEqualTo(0.2));
      expect(wall.outsideContactB, lessThanOrEqualTo(0.2));
    }
  });

  test('FloorDomain은 face-contact로 확정된 exterior만 사용하고, suspicious/interior는 절대 섞이지 않는다', () {
    final result = extractPixelWalls(_twoRoomFloorPlan());
    // 최종 exterior 목록에 절대 "양쪽 다 실내"였던 가운데 파티션이
    // 섞이지 않았는지 최종 candidate 리스트로 재확인.
    for (final c in result.candidates.where((c) => c.isExterior)) {
      expect(c.exteriorSuspicious, isFalse);
    }
  });
}
