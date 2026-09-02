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

/// 2D 정확도 개선 WO(8/9번) — 사각형 외곽 안에 한쪽 모서리를 막는 내부
/// 벽을 더해, 남는 실내 공간이 L자(오목 다각형)가 되는 synthetic floor
/// plan. 실제 픽셀 경계 추적(contour)이 "경계 사각형 근사"가 아니라
/// 진짜 L자 모양을 만드는지 끝까지(이미지 → 분석 → polygon) 검증하는
/// 데 쓴다.
Uint8List _buildLShapedFloorPlan() {
  final image = img.Image(width: 400, height: 300);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  final black = img.ColorRgb8(0, 0, 0);

  // 우측 상단은 실제 발코니 노치처럼 건물 바깥(배경)에 열려 있어야
  // 한다 — 그래서 top/right 외벽을 노치 구간까지 채우지 않고, 얇은 벽
  // 2개(세로/가로, 외벽과 같은 10px 두께)만으로 "실내 L자 vs 바깥 노치"
  // 경계를 긋는다. Windows 실기 FAIL 재조사 — 가구/해칭처럼 두꺼운 채움
  // 블록은 이제 벽으로도 방 경계로도 인정되지 않으므로, 이 테스트도
  // 두꺼운 블록이 아니라 실제 벽 두께로 노치를 표현해야 한다. 노치
  // 구간을 "막힌 두 번째 방"이 아니라 "이미지 바깥과 이어진 exterior"로
  // 만들어야, flood-fill이 그 구간을 이미지 경계에 닿았다는 이유로
  // 방 후보에서 자동으로 제외한다(closed=false 취급과 동일한 원리).
  img.fillRect(image, x1: 10, y1: 10, x2: 200, y2: 20, color: black); // top(왼쪽만).
  img.fillRect(
    image,
    x1: 10,
    y1: 280,
    x2: 390,
    y2: 290,
    color: black,
  ); // bottom
  img.fillRect(image, x1: 10, y1: 10, x2: 20, y2: 290, color: black); // left
  img.fillRect(
    image,
    x1: 380,
    y1: 150,
    x2: 390,
    y2: 290,
    color: black,
  ); // right(아래쪽만).
  img.fillRect(image, x1: 195, y1: 10, x2: 205, y2: 150, color: black); // 세로 컷.
  img.fillRect(image, x1: 200, y1: 145, x2: 390, y2: 155, color: black); // 가로 컷.

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

  group('Windows 실기 FAIL 재조사 — 가구/해칭이 방을 잘못 쪼개지 않는다', () {
    // 실기 재현: 옷장/붙박이장처럼 두껍게 채워지거나 촘촘히 해칭된
    // 가구 심볼은 실제 벽보다 훨씬 두꺼워 _mergeRunsToBands의
    // maxThicknessPx(두께 6% 초과) 필터에 걸려 "벽 후보"에서는 정상적으로
    // 제외된다. 그런데 예전 코드는 방 검출(flood-fill) 단계에 Otsu
    // 이진화 직후의 raw mask를 그대로 넘겨, 벽으로 인정되지 않은 이
    // 두꺼운 블록도 여전히 flood-fill 연결을 막아 실제로는 하나인 방을
    // 둘로 잘못 쪼갰다(실기 재현: 14개 공간 중 다수가 이런 식의 노이즈
    // 분할). 벽으로 확정된 band만으로 다시 채운 mask를 쓰도록 고친
    // 뒤에는, 벽 판정에서 제외된 두꺼운 블록이 방 안에 있어도 방
    // 전체가 하나로 유지돼야 한다.
    Uint8List buildRoomWithThickFurnitureBlock() {
      final image = img.Image(width: 400, height: 300);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));
      final black = img.ColorRgb8(0, 0, 0);

      img.fillRect(image, x1: 10, y1: 10, x2: 390, y2: 20, color: black);
      img.fillRect(image, x1: 10, y1: 280, x2: 390, y2: 290, color: black);
      img.fillRect(image, x1: 10, y1: 10, x2: 20, y2: 290, color: black);
      img.fillRect(image, x1: 380, y1: 10, x2: 390, y2: 290, color: black);

      // 붙박이장 내부 해칭이 다운샘플/이진화 후 "두꺼운 채움 블록"으로
      // 뭉개진 것을 흉내낸다 — 폭 40px(두께 6% 한계 24px를 크게 초과)로
      // 위/아래 외벽에 완전히 맞닿아, 실내를 좌우로 완전히 가로막는다.
      img.fillRect(image, x1: 150, y1: 20, x2: 190, y2: 280, color: black);

      return _encodePng(image);
    }

    test('벽 두께 한계를 넘는 채움 블록은 벽 후보에서 제외된다', () {
      final wallStage = detectWallsAndOpenings(
        WallStageInput(buildRoomWithThickFurnitureBlock()),
      );
      expect(wallStage.isSuccess, isTrue);
      // 실제 외벽 4개만 남아야 한다 — 두꺼운 블록이 벽으로 오인되면 안 된다.
      expect(wallStage.walls, hasLength(4));
    });

    test('그 블록이 방을 둘로 쪼개지 않고 하나의 방으로 유지된다', () {
      final wallStage = detectWallsAndOpenings(
        WallStageInput(buildRoomWithThickFurnitureBlock()),
      );
      final roomStage = detectRooms(
        RoomStageInput(
          mask: wallStage.mask!,
          width: wallStage.analysisWidthPx,
          height: wallStage.analysisHeightPx,
        ),
      );
      expect(
        roomStage.rooms,
        hasLength(1),
        reason: '벽으로 인정되지 않은 두꺼운 블록이 flood-fill 연결을 끊으면 안 된다.',
      );
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

  group('M/N — 2D 정확도 개선 WO(8/9번): 실제 픽셀 경계(contour) 추적', () {
    test('사각형 방은 (근사) 4개 모서리를 가진 polygon을 만든다 — 경계 '
        '사각형과 크게 다르지 않아야 한다', () {
      final wallStage = detectWallsAndOpenings(
        WallStageInput(_buildRectangularFloorPlan()),
      );
      final roomStage = detectRooms(
        RoomStageInput(
          mask: wallStage.mask!,
          width: wallStage.analysisWidthPx,
          height: wallStage.analysisHeightPx,
        ),
      );
      expect(roomStage.rooms, hasLength(1));
      final room = roomStage.rooms.single;
      // 직사각형이므로 방향이 바뀌는 진짜 꼭짓점은 4개뿐이어야 한다.
      expect(room.polygon.length, 4);
      for (final p in room.polygon) {
        expect(p.x, inInclusiveRange(0.0, 1.0));
        expect(p.y, inInclusiveRange(0.0, 1.0));
      }
    });

    test('L자 모양 실내는 bounding box(4점)가 아니라 실제 윤곽(6점 이상)을 '
        '만든다 — "CAD가 원본과 대응하지 않는다" 문제의 핵심 수정 대상', () {
      final wallStage = detectWallsAndOpenings(
        WallStageInput(_buildLShapedFloorPlan()),
      );
      final roomStage = detectRooms(
        RoomStageInput(
          mask: wallStage.mask!,
          width: wallStage.analysisWidthPx,
          height: wallStage.analysisHeightPx,
        ),
      );
      expect(roomStage.rooms, hasLength(1));
      final room = roomStage.rooms.single;

      // L자는 실제 꼭짓점이 6개다(직사각형이 4개인 것과 대비) — 이것이
      // bounding box 근사가 아니라 실제 contour를 추적했다는 증거다.
      expect(room.polygon.length, greaterThanOrEqualTo(6));

      // 막힌 모서리(우측 상단, 이미지 기준 x>0.5·y<0.5 부근)는 실제
      // room polygon에 포함되지 않아야 한다 — bounding box였다면
      // 포함됐을 자리다.
      expect(room.containsPoint(const Point2(0.85, 0.2)), isFalse);
      // 반대로 L자의 실제 남은 공간(좌측 하단 넓은 영역)은 포함된다.
      expect(room.containsPoint(const Point2(0.3, 0.7)), isTrue);

      // 실제 면적(픽셀 카운트 기반)은 항상 정직하므로, "막힌 모서리
      // 만큼 bounding box보다 작다"는 것도 함께 확인한다.
      final minX = room.polygon.map((p) => p.x).reduce(min);
      final maxX = room.polygon.map((p) => p.x).reduce(max);
      final minY = room.polygon.map((p) => p.y).reduce(min);
      final maxY = room.polygon.map((p) => p.y).reduce(max);
      final boundingBoxArea = (maxX - minX) * (maxY - minY);
      expect(room.areaNormalized, lessThan(boundingBoxArea));
    });
  });

  group('3D 근본 수정 — 안장점(saddle point) 경계 추적 안전성', () {
    // 실기 재현: 벽 표면에 거대한 삼각형이 생기는 사고를 조사하며 찾은
    // 실제 버그 — 대각선으로만 맞닿은 두 방 조각이 같은 격자 정점을
    // 공유하는 "안장점"(marching-squares 고전적 ambiguous case)에서,
    // 예전 구현은 그 정점의 두 번째 edge를 Map 덮어쓰기로 조용히
    // 버렸다. 그 결과 경계 추적이 방의 실제 모양과 무관한 정점으로
    // "점프"해, 이후 ear-clipping이 방 밖으로 길게 뻗는 삼각형을 만들
    // 수 있었다 — 지금은 안장점을 만나면 즉시 안전한 bounding box로
    // 폴백한다.
    test('대각선으로만 닿는 두 조각(안장점)이 있으면 잘못된 윤곽 대신 '
        'bounding box로 안전하게 폴백한다', () {
      const w = 6, h = 6;
      final mask = Uint8List(w * h)..fillRange(0, w * h, 1);
      void room(int x, int y) => mask[y * w + x] = 0;

      // 6x6 캔버스, 테두리(1px)는 벽. 내부 4x4 링 모양 방에 두 개의
      // 대각선 "팔"(A, D)이 정점 하나를 공유하고, 그 반대편 대각선
      // (B, C)은 벽으로 남는다 — 전형적인 saddle 구성.
      for (var x = 1; x <= 4; x++) {
        room(x, 1);
        room(x, 4);
      }
      for (var y = 1; y <= 4; y++) {
        room(1, y);
        room(4, y);
      }
      room(2, 2); // A
      room(3, 3); // D
      // B=(3,2), C=(2,3)은 벽으로 남긴다 — 이 둘이 room이 됐다면 애초에
      // saddle이 아니라 꽉 찬 사각형이다.

      final result = detectRooms(
        RoomStageInput(mask: mask, width: w, height: h),
      );
      expect(result.rooms, hasLength(1));
      final room0 = result.rooms.single;

      // 폴백된 bounding box는 정확히 minX=1,maxX=4,minY=1,maxY=4 (원시
      // 픽셀 인덱스 기준)여야 한다 — 안장점을 무시하고 "채워서" 만든
      // 잘못된 큰 정사각형(수정 전 실제 버그 동작)이 아니다.
      expect(room0.polygon.length, 4);
      final xs = room0.polygon.map((p) => p.x).toSet();
      final ys = room0.polygon.map((p) => p.y).toSet();
      expect(xs, containsAll(<double>[1 / w, 4 / w]));
      expect(ys, containsAll(<double>[1 / h, 4 / h]));
    });

    test('원거리 통로로만 연결된 안장점 방도 자기교차 없는 안전한 결과를 '
        '만든다', () {
      const w = 10, h = 10;
      final mask = Uint8List(w * h)..fillRange(0, w * h, 1);
      void room(int x, int y) => mask[y * w + x] = 0;

      for (var y = 1; y <= 6; y++) {
        for (var x = 1; x <= 6; x++) {
          room(x, y);
        }
      }
      room(7, 1);
      room(8, 1);
      room(8, 2);
      room(8, 3);
      room(8, 4);
      room(8, 5);
      room(8, 6);
      room(8, 7);
      room(7, 7); // 메인 블록 모서리(6,6)와 대각선으로만 맞닿는 원거리 팔.

      final result = detectRooms(
        RoomStageInput(mask: mask, width: w, height: h),
      );
      expect(result.rooms, hasLength(1));
      final room0 = result.rooms.single;

      // 안전한 결과의 최소 조건: 자기교차 없는 단순 다각형이어야 한다
      // (자기교차하면 뒤이은 ear-clipping이 방 밖으로 뻗는 거대한
      // 삼각형을 만들 수 있다 — 이번 사고의 핵심 위험).
      expect(_isSimplePolygon(room0.polygon), isTrue);
    });
  });
}

/// 인접하지 않은 두 변이 교차하지 않는지 확인한다(테스트 전용 — 실제
/// 자기교차 방지 로직은 [space_scene_builder.dart]의 `_isSelfIntersecting`
/// 이 담당하고, 여기서는 그 결과를 검증만 한다).
bool _isSimplePolygon(List<Point2> polygon) {
  final n = polygon.length;
  double orientation(Point2 a, Point2 b, Point2 c) =>
      (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
  bool segmentsIntersect(Point2 p1, Point2 p2, Point2 p3, Point2 p4) {
    final d1 = orientation(p3, p4, p1);
    final d2 = orientation(p3, p4, p2);
    final d3 = orientation(p1, p2, p3);
    final d4 = orientation(p1, p2, p4);
    return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
        ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
  }

  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      if (j == (i + 1) % n || (j + 1) % n == i) continue;
      if (segmentsIntersect(
        polygon[i],
        polygon[(i + 1) % n],
        polygon[j],
        polygon[(j + 1) % n],
      )) {
        return false;
      }
    }
  }
  return true;
}
