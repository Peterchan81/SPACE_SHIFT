// FloorPlanAnalysisEngine(grayscale/Otsu 이진화/run-length 벽 검출/방
// flood fill)에 대한 단위 테스트.
//
// 실제 이미지 파일 대신, 저작권 문제 없이 테스트에서만 쓰는 synthetic
// floor plan(사각형 외곽 + 내부 벽)을 image 패키지로 직접 그려서 검증한다
// (WO 20번 — 사용자 파일을 무단 commit하지 않는다).
//
// 1. 사각형 평면도 → 외곽(외벽) 벽 후보가 검출된다.
// 2. 내부 칸막이가 있는 평면도 → 내벽 후보가 검출된다.
// 3. 빈(흰색) 이미지 → 벽 후보가 없다.
// 4. 노이즈 이미지 → 벽이 과도하게 생성되지 않는다.
// 5. 좌표 정규화 → 모든 좌표가 0.0~1.0 범위 안에 있다.
// 6. 사각형 평면도 → 닫힌 공간(방) 후보가 검출된다.

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/services/floor_plan_analysis_engine.dart';

Uint8List _encodePng(img.Image image) =>
    Uint8List.fromList(img.encodePng(image));

/// 400x300 흰 배경에 두께 10px 검은 사각형 테두리(외벽)를 그린 synthetic
/// floor plan. [withInteriorWall]이면 x=200에 내부 칸막이도 추가한다.
Uint8List _buildRectangularFloorPlan({bool withInteriorWall = false}) {
  final image = img.Image(width: 400, height: 300);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  final black = img.ColorRgb8(0, 0, 0);

  img.fillRect(image, x1: 10, y1: 10, x2: 390, y2: 20, color: black); // top
  img.fillRect(
    image,
    x1: 10,
    y1: 280,
    x2: 390,
    y2: 290,
    color: black,
  ); // bottom
  img.fillRect(image, x1: 10, y1: 10, x2: 20, y2: 290, color: black); // left
  img.fillRect(image, x1: 380, y1: 10, x2: 390, y2: 290, color: black); // right

  if (withInteriorWall) {
    img.fillRect(image, x1: 195, y1: 20, x2: 205, y2: 280, color: black);
  }

  return _encodePng(image);
}

Uint8List _buildBlankImage() {
  final image = img.Image(width: 400, height: 300);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  return _encodePng(image);
}

/// 랜덤한 작은 점들만 있는(긴 직선이 없는) 노이즈 이미지.
Uint8List _buildNoiseImage() {
  final image = img.Image(width: 400, height: 300);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  final black = img.ColorRgb8(0, 0, 0);
  final random = Random(42);
  for (var i = 0; i < 800; i++) {
    final x = random.nextInt(398);
    final y = random.nextInt(298);
    image.setPixel(x, y, black);
  }
  return _encodePng(image);
}

void main() {
  group('detectWallsAndOpenings — 사각형 평면도', () {
    late WallStageResult result;

    setUpAll(() {
      result = detectWallsAndOpenings(
        WallStageInput(_buildRectangularFloorPlan()),
      );
    });

    test('성공적으로 디코드되고 벽 후보가 생성된다', () {
      expect(result.isSuccess, isTrue);
      expect(result.walls, isNotEmpty);
    });

    test('외곽을 이루는 벽은 isExterior=true로 표시된다', () {
      expect(result.walls.any((w) => w.isExterior), isTrue);
    });

    test('모든 벽 좌표는 0.0~1.0 정규화 범위 안에 있다', () {
      for (final wall in result.walls) {
        expect(wall.start.x, inInclusiveRange(0.0, 1.0));
        expect(wall.start.y, inInclusiveRange(0.0, 1.0));
        expect(wall.end.x, inInclusiveRange(0.0, 1.0));
        expect(wall.end.y, inInclusiveRange(0.0, 1.0));
        expect(wall.confidence, inInclusiveRange(0.0, 1.0));
      }
    });

    test('원본 이미지 크기를 정확히 보고한다', () {
      expect(result.sourceWidthPx, 400);
      expect(result.sourceHeightPx, 300);
    });

    test('닫힌 사각형이므로 방(공간) 후보가 하나 검출된다', () {
      final roomStage = detectRooms(
        RoomStageInput(
          mask: result.mask!,
          width: result.analysisWidthPx,
          height: result.analysisHeightPx,
        ),
      );
      expect(roomStage.rooms, hasLength(1));
      expect(roomStage.rooms.single.closed, isTrue);
    });
  });

  group('detectWallsAndOpenings — 내부 칸막이가 있는 평면도', () {
    test('내벽(isExterior=false) 후보가 검출된다', () {
      final result = detectWallsAndOpenings(
        WallStageInput(_buildRectangularFloorPlan(withInteriorWall: true)),
      );
      expect(result.walls.any((w) => !w.isExterior), isTrue);
    });

    test('내부 칸막이로 나뉘어 방 후보가 2개 검출된다', () {
      final wallStage = detectWallsAndOpenings(
        WallStageInput(_buildRectangularFloorPlan(withInteriorWall: true)),
      );
      final roomStage = detectRooms(
        RoomStageInput(
          mask: wallStage.mask!,
          width: wallStage.analysisWidthPx,
          height: wallStage.analysisHeightPx,
        ),
      );
      expect(roomStage.rooms, hasLength(2));
    });
  });

  test('빈(흰색) 이미지는 벽 후보가 없다', () {
    final result = detectWallsAndOpenings(WallStageInput(_buildBlankImage()));
    expect(result.isSuccess, isTrue);
    expect(result.walls, isEmpty);
  });

  test('노이즈(짧은 무작위 점) 이미지는 벽을 과도하게 생성하지 않는다', () {
    final result = detectWallsAndOpenings(WallStageInput(_buildNoiseImage()));
    expect(result.walls.length, lessThan(10));
  });

  test('읽을 수 없는 바이트는 unreadableImage 실패를 반환한다', () {
    final result = detectWallsAndOpenings(
      WallStageInput(Uint8List.fromList([1, 2, 3, 4, 5])),
    );
    expect(result.isSuccess, isFalse);
    expect(
      result.failureReason,
      FloorPlanAnalysisFailureReason.unreadableImage,
    );
  });

  test('너무 작은 이미지는 tooSmall 실패를 반환한다', () {
    final tiny = img.Image(width: 50, height: 50);
    img.fill(tiny, color: img.ColorRgb8(255, 255, 255));
    final result = detectWallsAndOpenings(WallStageInput(_encodePng(tiny)));
    expect(result.isSuccess, isFalse);
    expect(result.failureReason, FloorPlanAnalysisFailureReason.tooSmall);
  });
}
