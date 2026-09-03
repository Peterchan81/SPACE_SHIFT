// SPACE SHIFT — Vision-Guided Full Pixel Wall Extraction POC.
// extractPixelWalls()의 순수 로직(합성 이미지)만 검증한다 — 실제
// 이미지 2 의존 테스트는 real_pixel_wall_v4_e2e_test.dart에 있다.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_extractor.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_types.dart';

Uint8List _encodeSyntheticFloorPlan() {
  // 300x200 백지에 사각형 방 하나(검은 4변, 두께 6px)를 그린 합성 도면.
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

  thickLine(30, 30, 270, 30); // top
  thickLine(30, 170, 270, 170); // bottom
  thickLine(30, 30, 30, 170); // left
  thickLine(270, 30, 270, 170); // right
  // interior partition wall with a small (noise-like) 3px gap near x=150.
  thickLine(150, 30, 150, 95);
  thickLine(150, 101, 150, 170);

  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  test('사각형 방 하나 — 4개 외벽이 구조 벽으로 검출된다', () {
    final bytes = _encodeSyntheticFloorPlan();
    final result = extractPixelWalls(bytes);

    expect(result.isSuccess, isTrue);
    expect(result.candidates, isNotEmpty);
    // run-length 스캔은 축 정렬만 만든다 — 대각선이 원천적으로 없어야 한다.
    for (final c in result.candidates) {
      expect(
        c.orientation == PixelWallOrientation.horizontal || c.orientation == PixelWallOrientation.vertical,
        isTrue,
      );
    }
    final exterior = result.candidates.where((c) => c.isExterior).toList();
    expect(exterior.length, greaterThanOrEqualTo(4));
    for (final w in exterior) {
      expect(w.category, PixelWallCategory.structural);
    }
  });

  test('작은 3px gap으로 끊긴 내벽은 하나로 병합된다(노이즈 성격의 좁은 gap)', () {
    final bytes = _encodeSyntheticFloorPlan();
    final result = extractPixelWalls(bytes);

    final verticalInterior = result.candidates.where(
      (c) => c.orientation == PixelWallOrientation.vertical && !c.isExterior,
    );
    expect(verticalInterior, isNotEmpty);
    // 병합되지 않았다면 x=150 부근에 짧은 두 조각(길이 65px, 69px)이
    // 따로 남는다 — 병합되면 실제 벽 길이(30~170, 140px 근처)를 가진
    // 하나의 candidate가 있어야 한다.
    final lengths = verticalInterior.map((c) => (c.end.y - c.start.y).abs() * result.analysisHeightPx).toList();
    expect(lengths.any((l) => l > 100), isTrue, reason: '병합된 벽 하나는 원래 방 높이에 가까워야 한다: $lengths');
  });

  test('방 후보(RoomCandidate)가 flood-fill로 최소 1개 검출된다', () {
    final bytes = _encodeSyntheticFloorPlan();
    final result = extractPixelWalls(bytes);
    expect(result.rooms, isNotEmpty);
  });
}
