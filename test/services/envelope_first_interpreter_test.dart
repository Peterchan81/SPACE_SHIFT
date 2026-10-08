// EnvelopeFirstInterpreter(PC2 Envelope-first 실험) 단위 테스트.
//
// 검증 항목(WO 지시 9번 "이번 PASS 기준"과 직접 대응):
// A. 비정형(노치/돌출) 외곽이 bounding box로 뭉개지지 않고 보존된다.
// B. 실제 내벽 + 문으로 나뉜 두 공간이 올바르게 분리되고, 문이 두
//    공간을 연결한다(adjacentSpaceIds/connectsSpaceIds).
// C. 실제 벽과 같은 두께의 얇은 외곽선으로 그려진 가구는 독립 SPACE로
//    번호 매겨지지 않고 InterpretedObject로 재분류된다.
// D. 벽/방 evidence가 전혀 없어도 문/창 evidence(kind 포함)는 조용히
//    버려지지 않는다.
// E. 실제 CV 파이프라인(Otsu/run-length/flood-fill)을 거친 비정형 외곽
//    (L자 돌출) 평면도에서도 노치가 사라지지 않는다.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:ason_space/models/drawing_understanding.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/services/envelope_first_interpreter.dart';
import 'package:ason_space/services/floor_plan_analysis_engine.dart';

const _interpreter = EnvelopeFirstInterpreter();

FloorPlanAnalysisDebugStats _stats({
  int walls = 0,
  int rooms = 0,
  int openings = 0,
}) => FloorPlanAnalysisDebugStats(
  sourceWidthPx: 800,
  sourceHeightPx: 600,
  analysisWidthPx: 800,
  analysisHeightPx: 600,
  rawHorizontalRuns: 0,
  rawVerticalRuns: 0,
  mergedWallCount: walls,
  roomCandidateCount: rooms,
  openingCandidateCount: openings,
  durationMs: 1,
);

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

void main() {
  group('A — 비정형(노치) 외곽 보존', () {
    test('우측 상단이 잘린 L자 건물 외곽이 사각형으로 뭉개지지 않는다', () {
      // 실제 벽만으로 L자 외곽을 그린다(WO 지시 1번 "직각만 가정하지
      // 않는다 / 돌출·후퇴 부분을 유지한다"의 최소 재현) — 우측 상단
      // 모서리(x>0.5, y<0.5 부근)를 노치로 잘라낸다.
      const walls = [
        WallSegment(
          id: 'top',
          start: Point2(0.1, 0.1),
          end: Point2(0.5, 0.1),
          thicknessNormalized: 0.02,
          confidence: 0.8,
          isExterior: true,
        ),
        WallSegment(
          id: 'notch-v',
          start: Point2(0.5, 0.1),
          end: Point2(0.5, 0.5),
          thicknessNormalized: 0.02,
          confidence: 0.8,
          isExterior: true,
        ),
        WallSegment(
          id: 'notch-h',
          start: Point2(0.5, 0.5),
          end: Point2(0.9, 0.5),
          thicknessNormalized: 0.02,
          confidence: 0.8,
          isExterior: true,
        ),
        WallSegment(
          id: 'right',
          start: Point2(0.9, 0.5),
          end: Point2(0.9, 0.9),
          thicknessNormalized: 0.02,
          confidence: 0.8,
          isExterior: true,
        ),
        WallSegment(
          id: 'bottom',
          start: Point2(0.1, 0.9),
          end: Point2(0.9, 0.9),
          thicknessNormalized: 0.02,
          confidence: 0.8,
          isExterior: true,
        ),
        WallSegment(
          id: 'left',
          start: Point2(0.1, 0.1),
          end: Point2(0.1, 0.9),
          thicknessNormalized: 0.02,
          confidence: 0.8,
          isExterior: true,
        ),
      ];
      // 실제 앱에서는 벽 evidence와 방(flood-fill) evidence가 항상 함께
      // 온다(detectRooms가 벽으로 둘러싸인 실제 바닥을 이미 채워서
      // 넘긴다) — 이 interpreter는 그 "바닥 채움" 신호로 Envelope를
      // 재구성하므로, 벽 evidence만 단독으로는(속이 빈 윤곽선일 뿐이라)
      // 재구성할 floor 자체가 없다. 단위 테스트도 이 실제 계약을 그대로
      // 재현한다 — L자 내부를 대략적으로 덮는 방 후보 하나(정확한 모양은
      // 중요하지 않다, 최종 SPACE 분할은 오직 wallOnly 격자로만 한다).
      // 벽 중심선과 정확히 같은 좌표를 쓴다(실제 detectRooms는 벽으로
      // 쓰인 것과 같은 픽셀 마스크에서 flood-fill하므로 항상 이렇게
      // 딱 맞물린다 — 테스트에서 임의로 다른 좌표를 쓰면 방 폴리곤과
      // 벽 사이에 인위적인 틈이 생겨 유니온이 끊어질 수 있다).
      const room = RoomCandidate(
        id: 'room-l',
        polygon: [
          Point2(0.1, 0.1),
          Point2(0.5, 0.1),
          Point2(0.5, 0.5),
          Point2(0.9, 0.5),
          Point2(0.9, 0.9),
          Point2(0.1, 0.9),
        ],
        areaNormalized: 0.5,
        confidence: 0.7,
      );
      final result = FloorPlanAnalysisResult(
        sourceWidthPx: 800,
        sourceHeightPx: 600,
        walls: walls,
        openings: const [],
        rooms: const [room],
        warnings: const [],
        debugStats: _stats(walls: walls.length, rooms: 1),
      );

      final interpretation = _interpreter.interpret(result);

      expect(interpretation.spaces, hasLength(1));
      final space = interpretation.spaces.single;
      // 사각형이었다면 4개 꼭짓점이지만, L자는 6개다 — bounding box로
      // 뭉개지지 않았다는 직접적인 증거.
      expect(space.polygon.length, greaterThanOrEqualTo(6));
      expect(_isSimplePolygon(space.polygon), isTrue);
      // 잘려나간 우측 상단 모서리(0.7, 0.3 부근)는 폴리곤 내부에 없어야
      // 한다.
      expect(_containsPoint(space.polygon, const Point2(0.7, 0.3)), isFalse);
      // 반대로 L자의 두 "팔" 안쪽 점은 내부여야 한다.
      expect(_containsPoint(space.polygon, const Point2(0.2, 0.3)), isTrue);
      expect(_containsPoint(space.polygon, const Point2(0.7, 0.7)), isTrue);
    });
  });

  group('B — 벽/문으로 나뉜 두 공간', () {
    test('내벽으로 나뉜 두 공간이 분리되고, 문이 둘을 연결한다', () {
      const outerWalls = [
        WallSegment(
          id: 'n',
          start: Point2(0.1, 0.1),
          end: Point2(0.9, 0.1),
          thicknessNormalized: 0.02,
          confidence: 0.8,
          isExterior: true,
        ),
        WallSegment(
          id: 's',
          start: Point2(0.1, 0.9),
          end: Point2(0.9, 0.9),
          thicknessNormalized: 0.02,
          confidence: 0.8,
          isExterior: true,
        ),
        WallSegment(
          id: 'w',
          start: Point2(0.1, 0.1),
          end: Point2(0.1, 0.9),
          thicknessNormalized: 0.02,
          confidence: 0.8,
          isExterior: true,
        ),
        WallSegment(
          id: 'e',
          start: Point2(0.9, 0.1),
          end: Point2(0.9, 0.9),
          thicknessNormalized: 0.02,
          confidence: 0.8,
          isExterior: true,
        ),
        WallSegment(
          id: 'mid',
          start: Point2(0.5, 0.1),
          end: Point2(0.5, 0.9),
          thicknessNormalized: 0.02,
          confidence: 0.7,
        ),
      ];
      const door = OpeningCandidate(
        id: 'door-mid',
        type: OpeningType.door,
        center: Point2(0.5, 0.5),
        widthNormalized: 0.05,
        confidence: 0.5,
        wallId: 'mid',
      );
      // 벽 중심선과 정확히 같은 좌표를 쓴다(테스트 A와 같은 이유).
      const rooms = [
        RoomCandidate(
          id: 'room-left',
          polygon: [
            Point2(0.1, 0.1),
            Point2(0.5, 0.1),
            Point2(0.5, 0.9),
            Point2(0.1, 0.9),
          ],
          areaNormalized: 0.25,
          confidence: 0.7,
        ),
        RoomCandidate(
          id: 'room-right',
          polygon: [
            Point2(0.5, 0.1),
            Point2(0.9, 0.1),
            Point2(0.9, 0.9),
            Point2(0.5, 0.9),
          ],
          areaNormalized: 0.25,
          confidence: 0.7,
        ),
      ];
      final result = FloorPlanAnalysisResult(
        sourceWidthPx: 800,
        sourceHeightPx: 600,
        walls: outerWalls,
        openings: const [door],
        rooms: rooms,
        warnings: const [],
        debugStats: _stats(walls: outerWalls.length, rooms: 2, openings: 1),
      );

      final interpretation = _interpreter.interpret(result);

      expect(interpretation.spaces, hasLength(2));
      final a = interpretation.spaces[0];
      final b = interpretation.spaces[1];
      expect(a.adjacentSpaceIds, contains(b.id));
      expect(b.adjacentSpaceIds, contains(a.id));

      final opening = interpretation.openings.single;
      expect(opening.kind, DrawingSemanticType.doorSymbol);
      expect(opening.connectsSpaceIds.toSet(), {a.id, b.id});
    });
  });

  group('C — 가구가 독립 SPACE로 번호 매겨지지 않는다', () {
    test('실제 벽과 같은 두께의 얇은 외곽선 가구는 SPACE가 아니라 object다', () {
      const outerWalls = [
        WallSegment(
          id: 'n',
          start: Point2(0.1, 0.1),
          end: Point2(0.9, 0.1),
          thicknessNormalized: 0.02,
          confidence: 0.8,
          isExterior: true,
        ),
        WallSegment(
          id: 's',
          start: Point2(0.1, 0.9),
          end: Point2(0.9, 0.9),
          thicknessNormalized: 0.02,
          confidence: 0.8,
          isExterior: true,
        ),
        WallSegment(
          id: 'w',
          start: Point2(0.1, 0.1),
          end: Point2(0.1, 0.9),
          thicknessNormalized: 0.02,
          confidence: 0.8,
          isExterior: true,
        ),
        WallSegment(
          id: 'e',
          start: Point2(0.9, 0.1),
          end: Point2(0.9, 0.9),
          thicknessNormalized: 0.02,
          confidence: 0.8,
          isExterior: true,
        ),
        // 가구(붙박이장 등) — 실제 벽과 똑같은 두께의 닫힌 사각형
        // 외곽선. 방 한가운데, 어느 외벽에도 닿지 않는다.
        WallSegment(
          id: 'furniture-1',
          start: Point2(0.4, 0.4),
          end: Point2(0.6, 0.4),
          thicknessNormalized: 0.02,
          confidence: 0.6,
        ),
        WallSegment(
          id: 'furniture-2',
          start: Point2(0.6, 0.4),
          end: Point2(0.6, 0.6),
          thicknessNormalized: 0.02,
          confidence: 0.6,
        ),
        WallSegment(
          id: 'furniture-3',
          start: Point2(0.6, 0.6),
          end: Point2(0.4, 0.6),
          thicknessNormalized: 0.02,
          confidence: 0.6,
        ),
        WallSegment(
          id: 'furniture-4',
          start: Point2(0.4, 0.6),
          end: Point2(0.4, 0.4),
          thicknessNormalized: 0.02,
          confidence: 0.6,
        ),
      ];
      const room = RoomCandidate(
        id: 'room-main',
        polygon: [
          Point2(0.12, 0.12),
          Point2(0.88, 0.12),
          Point2(0.88, 0.88),
          Point2(0.12, 0.88),
        ],
        areaNormalized: 0.6,
        confidence: 0.7,
      );
      final result = FloorPlanAnalysisResult(
        sourceWidthPx: 800,
        sourceHeightPx: 600,
        walls: outerWalls,
        openings: const [],
        rooms: const [room],
        warnings: const [],
        debugStats: _stats(walls: outerWalls.length, rooms: 1),
      );

      final interpretation = _interpreter.interpret(result);

      expect(
        interpretation.spaces,
        hasLength(1),
        reason: '가구 내부가 별도 SPACE로 번호 매겨지면 안 된다.',
      );
      expect(interpretation.objects, isNotEmpty);
      expect(
        interpretation.objects.every(
          (o) => o.semanticType == DrawingSemanticType.furniture,
        ),
        isTrue,
      );
    });
  });

  group('D — 벽/방 evidence가 없어도 문/창 evidence는 보존된다', () {
    test('문 evidence만 있고 벽/방이 전혀 없어도 kind(door)가 유지된다', () {
      const door = OpeningCandidate(
        id: 'door-only',
        type: OpeningType.door,
        center: Point2(0.5, 0.5),
        widthNormalized: 0.05,
        confidence: 0.5,
      );
      final result = FloorPlanAnalysisResult(
        sourceWidthPx: 800,
        sourceHeightPx: 600,
        walls: const [],
        openings: const [door],
        rooms: const [],
        warnings: const [],
        debugStats: _stats(openings: 1),
      );

      final interpretation = _interpreter.interpret(result);

      expect(interpretation.spaces, isEmpty);
      expect(interpretation.openings, hasLength(1));
      expect(
        interpretation.openings.single.kind,
        DrawingSemanticType.doorSymbol,
      );
    });
  });

  group('E — 실제 CV 파이프라인: 비정형(노치) 외곽 + 다중 방', () {
    test('L자 돌출 건물 외곽이 실제 이미지 파이프라인을 거쳐도 사라지지 않는다', () {
      final image = img.Image(width: 600, height: 450);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));
      final black = img.ColorRgb8(0, 0, 0);

      // 우측 상단(x>350, y<200)이 잘려나간 L자 외곽 + 중앙 세로 내벽으로
      // 방 2개.
      img.fillRect(
        image,
        x1: 30,
        y1: 20,
        x2: 350,
        y2: 30,
        color: black,
      ); // top(left).
      img.fillRect(
        image,
        x1: 350,
        y1: 20,
        x2: 360,
        y2: 200,
        color: black,
      ); // notch vertical.
      img.fillRect(
        image,
        x1: 350,
        y1: 190,
        x2: 570,
        y2: 200,
        color: black,
      ); // notch horizontal.
      img.fillRect(
        image,
        x1: 560,
        y1: 190,
        x2: 570,
        y2: 430,
        color: black,
      ); // right.
      img.fillRect(
        image,
        x1: 30,
        y1: 420,
        x2: 570,
        y2: 430,
        color: black,
      ); // bottom.
      img.fillRect(
        image,
        x1: 30,
        y1: 20,
        x2: 40,
        y2: 430,
        color: black,
      ); // left.
      img.fillRect(
        image,
        x1: 295,
        y1: 20,
        x2: 305,
        y2: 430,
        color: black,
      ); // 내벽.

      final bytes = Uint8List.fromList(img.encodePng(image));
      final wallStage = detectWallsAndOpenings(WallStageInput(bytes));
      expect(wallStage.isSuccess, isTrue);
      final roomStage = detectRooms(
        RoomStageInput(
          mask: wallStage.mask!,
          width: wallStage.analysisWidthPx,
          height: wallStage.analysisHeightPx,
        ),
      );

      final result = FloorPlanAnalysisResult(
        sourceWidthPx: wallStage.sourceWidthPx,
        sourceHeightPx: wallStage.sourceHeightPx,
        walls: wallStage.walls,
        openings: wallStage.openings,
        rooms: roomStage.rooms,
        warnings: const [],
        debugStats: _stats(
          walls: wallStage.walls.length,
          rooms: roomStage.rooms.length,
          openings: wallStage.openings.length,
        ),
      );

      final interpretation = _interpreter.interpret(result);

      expect(interpretation.spaces, hasLength(2));
      final combinedVertexCount = interpretation.spaces
          .map((s) => s.polygon.length)
          .reduce((a, b) => a + b);
      // 두 방 모두 완전한 사각형(4점)이었다면 8이다 — 노치가 살아
      // 있으면 노치와 맞닿은 방(오른쪽 절반)의 폴리곤이 6점 이상이 돼
      // 합계가 8보다 커야 한다.
      expect(
        combinedVertexCount,
        greaterThan(8),
        reason: 'L자 노치가 사각형으로 뭉개졌다면 두 방 다 4점(합계 8)이었을 것이다.',
      );
      for (final space in interpretation.spaces) {
        expect(_isSimplePolygon(space.polygon), isTrue);
      }
    });
  });
}

bool _containsPoint(List<Point2> polygon, Point2 point) {
  var inside = false;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final a = polygon[i], b = polygon[j];
    if (((a.y > point.y) != (b.y > point.y)) &&
        point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x) {
      inside = !inside;
    }
  }
  return inside;
}
