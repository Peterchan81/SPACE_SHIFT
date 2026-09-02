import 'package:ason_space/models/drawing_understanding.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/services/architectural_drawing_interpreter.dart';
import 'package:flutter_test/flutter_test.dart';

FloorPlanAnalysisDebugStats stats({int walls = 0, int rooms = 0}) =>
    FloorPlanAnalysisDebugStats(
      sourceWidthPx: 1000,
      sourceHeightPx: 800,
      analysisWidthPx: 1000,
      analysisHeightPx: 800,
      rawHorizontalRuns: walls,
      rawVerticalRuns: 0,
      mergedWallCount: walls,
      roomCandidateCount: rooms,
      openingCandidateCount: 0,
      durationMs: 1,
    );

const outerRoom = RoomCandidate(
  id: 'outer',
  polygon: [
    Point2(0.1, 0.1),
    Point2(0.9, 0.1),
    Point2(0.9, 0.9),
    Point2(0.1, 0.9),
  ],
  areaNormalized: 0.64,
  confidence: 0.9,
);

List<WallSegment> rectangle(
  String prefix,
  double left,
  double top,
  double right,
  double bottom,
) => [
  WallSegment(
    id: '$prefix-top',
    start: Point2(left, top),
    end: Point2(right, top),
    thicknessNormalized: 0.01,
    confidence: 0.9,
  ),
  WallSegment(
    id: '$prefix-right',
    start: Point2(right, top),
    end: Point2(right, bottom),
    thicknessNormalized: 0.01,
    confidence: 0.9,
  ),
  WallSegment(
    id: '$prefix-bottom',
    start: Point2(right, bottom),
    end: Point2(left, bottom),
    thicknessNormalized: 0.01,
    confidence: 0.9,
  ),
  WallSegment(
    id: '$prefix-left',
    start: Point2(left, bottom),
    end: Point2(left, top),
    thicknessNormalized: 0.01,
    confidence: 0.9,
  ),
];

void main() {
  const interpreter = ArchitecturalDrawingInterpreter();

  test('primitive JSON preserves geometry and semantic candidates', () {
    const primitive = DetectedPrimitive(
      id: 'p1',
      geometry: PrimitiveGeometry(
        type: PrimitiveGeometryType.segment,
        points: [Point2(0.1, 0.2), Point2(0.3, 0.4)],
        thicknessNormalized: 0.01,
      ),
      sourceDetector: 'fixture',
      candidateTypes: [DrawingSemanticType.wall, DrawingSemanticType.unknown],
      confidence: 0.7,
    );
    final restored = DetectedPrimitive.fromJson(primitive.toJson());
    expect(restored.id, primitive.id);
    expect(restored.geometry.points.last.x, 0.3);
    expect(restored.candidateTypes, contains(DrawingSemanticType.unknown));
  });

  test('detached closed contour becomes object, not wall graph or space', () {
    final outerWalls = rectangle('outer', 0.1, 0.1, 0.9, 0.9);
    final furnitureWalls = rectangle('desk', 0.4, 0.4, 0.55, 0.55);
    const furnitureRegion = RoomCandidate(
      id: 'desk-region',
      polygon: [
        Point2(0.4, 0.4),
        Point2(0.55, 0.4),
        Point2(0.55, 0.55),
        Point2(0.4, 0.55),
      ],
      areaNormalized: 0.0225,
      confidence: 0.8,
    );
    final result = FloorPlanAnalysisResult(
      sourceWidthPx: 1000,
      sourceHeightPx: 800,
      walls: [...outerWalls, ...furnitureWalls],
      openings: const [],
      rooms: const [outerRoom, furnitureRegion],
      warnings: const [],
      debugStats: stats(walls: 8, rooms: 2),
    );
    final model = interpreter.interpret(result);
    expect(
      model.wallGraph.walls.map((wall) => wall.id),
      isNot(contains('desk-top')),
    );
    expect(model.spaces.map((space) => space.id), ['outer']);
    expect(model.objects.single.id, 'object-desk-region');
    expect(model.objects.single.containingSpaceId, 'outer');
  });

  test('opening requires a validated parent wall and creates relations', () {
    final walls = rectangle('outer', 0.1, 0.1, 0.9, 0.9);
    final result = FloorPlanAnalysisResult(
      sourceWidthPx: 1000,
      sourceHeightPx: 800,
      walls: walls,
      openings: const [
        OpeningCandidate(
          id: 'door',
          type: OpeningType.door,
          center: Point2(0.5, 0.1),
          widthNormalized: 0.08,
          confidence: 0.8,
          wallId: 'outer-top',
        ),
        OpeningCandidate(
          id: 'orphan',
          type: OpeningType.unknown,
          center: Point2(0.5, 0.5),
          widthNormalized: 0.04,
          confidence: 0.5,
          wallId: 'missing',
        ),
      ],
      rooms: const [outerRoom],
      warnings: const [],
      debugStats: stats(walls: 4, rooms: 1),
    );
    final model = interpreter.interpret(result);
    expect(model.openings.map((opening) => opening.id), ['door', 'orphan']);
    expect(model.openings.first.parentWallId, 'outer-top');
    expect(model.openings.last.parentWallId, isNull);
    expect(model.openings.last.connectsSpaceIds, isEmpty);
    expect(model.spaces.single.boundaryOpeningIds, contains('door'));
    final orphan = model.semanticPrimitives.firstWhere(
      (item) => item.sourcePrimitiveId == 'primitive-opening-orphan',
    );
    expect(orphan.semanticType, DrawingSemanticType.unknown);
  });

  test(
    'space-first fix: a sub-region without validated wall support is never '
    'silently dropped — it stays a space unless it is furniture-sized',
    () {
      // 사용자 실기 재현 — 벽이 약하게(또는 전혀) 검출된 큰 공간이
      // "가구도 아니고 검증된 벽도 없다"는 이유로 spaces/objects
      // 어디에도 들어가지 못하고 사라지던 실제 사고. 컨테이너 면적의
      // 절반(25% 문턱보다 훨씬 큼)을 차지하는 후보를 벽 evidence 없이
      // 넣어, objectLike로도 재분류되지 않고 반드시 space로 남는지
      // 확인한다.
      const halfRoom = RoomCandidate(
        id: 'half',
        polygon: [
          Point2(0.1, 0.1),
          Point2(0.5, 0.1),
          Point2(0.5, 0.9),
          Point2(0.1, 0.9),
        ],
        areaNormalized: 0.32,
        confidence: 0.7,
      );
      final result = FloorPlanAnalysisResult(
        sourceWidthPx: 1000,
        sourceHeightPx: 800,
        walls: const [],
        openings: const [],
        rooms: const [outerRoom, halfRoom],
        warnings: const [],
        debugStats: stats(rooms: 2),
      );
      final model = interpreter.interpret(result);
      expect(model.spaces.map((space) => space.id).toSet(), {
        'outer',
        'half',
      });
      expect(model.objects, isEmpty);
    },
  );

  test(
    'a sub-region larger than the furniture-size threshold is never '
    'reclassified as an object even without wall/opening support',
    () {
      // objectLike 판정이 "컨테이너 안에 있고 벽 evidence가 약하다"만
      // 보면, 실제로는 벽이 약하게 검출된 큰 방(컨테이너의 절반 가까이)
      // 까지 가구로 오분류할 위험이 있다 — 상대 크기 조건이 반드시
      // 함께 있어야 한다는 회귀 테스트.
      const bigSubRegion = RoomCandidate(
        id: 'big-sub',
        polygon: [
          Point2(0.15, 0.15),
          Point2(0.85, 0.15),
          Point2(0.85, 0.5),
          Point2(0.15, 0.5),
        ],
        areaNormalized: 0.245, // outer(0.64)의 약 38% — 25% 문턱보다 큼.
        confidence: 0.7,
      );
      final result = FloorPlanAnalysisResult(
        sourceWidthPx: 1000,
        sourceHeightPx: 800,
        walls: const [],
        openings: const [],
        rooms: const [outerRoom, bigSubRegion],
        warnings: const [],
        debugStats: stats(rooms: 2),
      );
      final model = interpreter.interpret(result);
      expect(model.objects, isEmpty);
      expect(
        model.spaces.map((space) => space.id),
        containsAll(['outer', 'big-sub']),
      );
    },
  );

  test(
    'two spaces sharing an edge with no wall evidence get a virtual '
    'boundary segment and are recorded as adjacent',
    () {
      const roomA = RoomCandidate(
        id: 'room-a',
        polygon: [
          Point2(0.1, 0.1),
          Point2(0.5, 0.1),
          Point2(0.5, 0.9),
          Point2(0.1, 0.9),
        ],
        areaNormalized: 0.32,
        confidence: 0.8,
      );
      const roomB = RoomCandidate(
        id: 'room-b',
        polygon: [
          Point2(0.5, 0.1),
          Point2(0.9, 0.1),
          Point2(0.9, 0.9),
          Point2(0.5, 0.9),
        ],
        areaNormalized: 0.32,
        confidence: 0.8,
      );
      final result = FloorPlanAnalysisResult(
        sourceWidthPx: 1000,
        sourceHeightPx: 800,
        walls: const [],
        openings: const [],
        rooms: const [roomA, roomB],
        warnings: const [],
        debugStats: stats(rooms: 2),
      );
      final model = interpreter.interpret(result);
      final a = model.spaces.firstWhere((space) => space.id == 'room-a');
      final sharedSegment = a.boundarySegments.firstWhere(
        (segment) => segment.oppositeSpaceId == 'room-b',
        orElse: () => throw StateError('no shared virtual boundary found'),
      );
      expect(sharedSegment.type, BoundarySegmentType.virtual);
      expect(a.adjacentSpaceIds, contains('room-b'));
    },
  );

  test(
    'rejected linear evidence is dimension candidate and diagnostics cover every stage',
    () {
      final result = FloorPlanAnalysisResult(
        sourceWidthPx: 1000,
        sourceHeightPx: 800,
        walls: const [],
        openings: const [],
        rooms: const [outerRoom],
        rejectedWalls: const [
          RejectedWallCandidate(
            id: 'dim',
            start: Point2(0.2, 0.95),
            end: Point2(0.8, 0.95),
            thicknessNormalized: 0.002,
            reason: RejectedWallReason.tooThick,
          ),
        ],
        warnings: const [],
        debugStats: stats(rooms: 1),
      );
      final model = interpreter.interpret(result);
      expect(model.dimensions.single.id, 'dimension-dim');
      expect(model.wallGraph.walls, isEmpty);
      expect(
        model.diagnostics.map((item) => item.stage).toSet(),
        DrawingDiagnosticStage.values.toSet(),
      );
      expect(model.traces.every((trace) => trace.reasons.isNotEmpty), isTrue);
    },
  );
}
