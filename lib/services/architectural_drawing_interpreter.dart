import 'dart:math' as math;

import '../models/drawing_understanding.dart';
import '../models/floor_plan_geometry.dart';

class ArchitecturalDrawingInterpreter {
  const ArchitecturalDrawingInterpreter();

  ArchitecturalInterpretation interpret(FloorPlanAnalysisResult input) {
    final primitives = _primitives(input);
    final semantics = <String, SemanticPrimitive>{};
    final traces = <EvidenceTrace>[];
    final links = _links(input.walls);
    final provisional = <WallSegment>[];

    for (final wall in input.walls) {
      final source = 'primitive-wall-${wall.id}';
      final junction = (links[wall.id]?.length ?? 0) > 0;
      final boundary = input.rooms.any((room) => _supports(wall, room.polygon));
      final parallel = input.walls.any(
        (other) =>
            other.id != wall.id &&
            other.isHorizontal == wall.isHorizontal &&
            (other.thicknessNormalized - wall.thicknessNormalized).abs() <
                math.max(wall.thicknessNormalized, 0.005),
      );
      final valid =
          wall.lengthNormalized >= 0.03 &&
          (junction || boundary || wall.isExterior);
      final reasons = <String>[
        if (junction) 'connected endpoint or junction',
        if (boundary) 'supports a detected region boundary',
        if (parallel) 'parallel thickness-consistent evidence',
        if (wall.isExterior) 'exterior-boundary detector evidence',
        if (!valid) 'insufficient architectural wall evidence',
      ];
      final type = valid
          ? DrawingSemanticType.wall
          : DrawingSemanticType.annotation;
      final confidence = valid
          ? _clamp(
              0.42 +
                  (junction ? 0.2 : 0) +
                  (boundary ? 0.2 : 0) +
                  (parallel ? 0.1 : 0),
            )
          : 0.55;
      semantics[source] = SemanticPrimitive(
        id: 'semantic-${wall.id}',
        sourcePrimitiveId: source,
        semanticType: type,
        confidence: confidence,
        reasons: reasons,
      );
      traces.add(
        EvidenceTrace(
          id: 'trace-${wall.id}',
          stage: DrawingDiagnosticStage.semantic,
          sourceIds: [source],
          classification: type,
          confidence: confidence,
          reasons: reasons,
        ),
      );
      if (valid) provisional.add(wall);
    }

    final excluded = <String>{};
    final annotationWalls = <String>{};
    for (final component in _components(provisional, links)) {
      final walls = provisional
          .where((wall) => component.contains(wall.id))
          .toList();
      final enclosed = input.rooms.any(
        (room) => walls.every(
          (wall) =>
              _strictInside(room.polygon, wall.start) &&
              _strictInside(room.polygon, wall.end),
        ),
      );
      final hasOpening = input.openings.any(
        (opening) =>
            opening.wallId != null && component.contains(opening.wallId),
      );
      if (!enclosed || hasOpening) continue;
      excluded.addAll(component);
      final closed =
          walls.length >= 3 &&
          walls.every((wall) => (links[wall.id]?.length ?? 0) >= 2);
      for (final wall in walls) {
        final source = 'primitive-wall-${wall.id}';
        semantics[source] = SemanticPrimitive(
          id: 'semantic-${wall.id}',
          sourcePrimitiveId: source,
          semanticType: closed
              ? DrawingSemanticType.furniture
              : DrawingSemanticType.annotation,
          confidence: closed ? 0.82 : 0.62,
          reasons: [
            closed
                ? 'detached closed contour inside a larger space'
                : 'disconnected line does not join wall topology',
            'no opening is attached to this component',
          ],
        );
        if (!closed) annotationWalls.add(wall.id);
      }
    }

    final validWalls = input.walls
        .where(
          (wall) =>
              provisional.any((value) => value.id == wall.id) &&
              !excluded.contains(wall.id),
        )
        .toList();
    final finalLinks = _links(validWalls);
    final junctions = _junctions(validWalls);
    final graph = ArchitecturalWallGraph(
      walls: [
        for (final wall in validWalls)
          ArchitecturalWall(
            id: wall.id,
            sourcePrimitiveId: 'primitive-wall-${wall.id}',
            segment: wall,
            confidence: semantics['primitive-wall-${wall.id}']!.confidence,
            reasons: semantics['primitive-wall-${wall.id}']!.reasons,
            junctionIds: [
              for (final junction in junctions)
                if (junction.wallIds.contains(wall.id)) junction.id,
            ],
          ),
      ],
      junctions: junctions,
      connectedComponents: _components(validWalls, finalLinks),
    );

    final spaces = <InterpretedSpace>[];
    final objects = <InterpretedObject>[];
    for (final room in input.rooms) {
      final source = 'primitive-room-${room.id}';
      final container = _containerFor(room, input.rooms);
      final rawBoundary = input.walls
          .where((wall) => _supports(wall, room.polygon))
          .map((wall) => wall.id)
          .toList();
      final boundary = rawBoundary.where(graph.containsWall).toList();
      final rejectedBoundary = rawBoundary.where(excluded.contains).toList();
      final openingNearby = input.openings.any(
        (opening) => _nearPolygon(opening.center, room.polygon),
      );
      // Space-first 재작업 WO — 가구/설비 판단에 "컨테이너보다 훨씬
      // 작다"는 상대 크기 조건을 반드시 함께 본다(WO 지시 2/5번: 선
      // 굵기/색상뿐 아니라 상대적 크기도 evidence로 쓴다). 이 조건이
      // 없으면, 컨테이너 안에 있고 확정된 벽 evidence가 약한 "실제로는
      // 절반 가까이 되는 큰 공간"까지 가구로 오분류할 위험이 있다 —
      // 소파/침대 같은 실제 가구는 방 면적의 극히 일부일 뿐이다.
      final objectLike =
          container != null &&
          room.areaNormalized < container.areaNormalized * 0.25 &&
          !openingNearby &&
          (rejectedBoundary.isNotEmpty || rawBoundary.isEmpty) &&
          boundary.isEmpty;
      if (objectLike) {
        final reasons = const [
          'closed contour is contained by a larger space',
          'detached contour is not part of the architectural wall graph',
          'no opening supports an independent space',
        ];
        objects.add(
          InterpretedObject(
            id: 'object-${room.id}',
            sourcePrimitiveId: source,
            semanticType: DrawingSemanticType.furniture,
            polygon: room.polygon,
            confidence: 0.84,
            reasons: reasons,
            containingSpaceId: container.id,
          ),
        );
        semantics[source] = SemanticPrimitive(
          id: 'semantic-${room.id}',
          sourcePrimitiveId: source,
          semanticType: DrawingSemanticType.furniture,
          confidence: 0.84,
          reasons: reasons,
        );
        continue;
      }
      // Space-first 재작업 WO(핵심 수정) — 이 지점까지 온 후보는 이미
      // "가구/설비로 볼 근거가 없다"고 판단된 것이다(objectLike가
      // false). 예전 코드는 여기서 다시 한번 "검증된 벽 그래프가
      // 충분한가"(boundary.length>=2)로 걸러, 벽이 약하게(또는 전혀)
      // 검출되지 않은 정당한 공간까지 spaces/objects 어디에도 들어가지
      // 못하고 조용히 사라졌다 — 실사용 실기에서 "실제 공간이
      // 사라진다"는 신고의 핵심 원인이다. SPACE 판단은 "가구가 아니면
      // 기본적으로 SPACE"가 원칙이므로(WO 지시 5번), 여기서부터는
      // 절대 후보를 버리지 않고 항상 spaces에 넣는다 — 다만 벽
      // evidence가 약하면 boundaryConfidence만 낮춰 그 불확실성을
      // 정직하게 남긴다(가짜로 확정 처리하지 않는다).
      final topLevel = container == null;
      final reasons = <String>[
        if (boundary.isNotEmpty) 'validated wall graph forms the boundary',
        if (topLevel) 'top-level closed detector region',
        if (openingNearby) 'an opening is adjacent to this region',
        if (boundary.isEmpty && !topLevel && !openingNearby)
          'no validated wall graph support — kept as space by default '
              '(space-first: never silently drop a non-furniture candidate)',
      ];
      semantics[source] = SemanticPrimitive(
        id: 'semantic-${room.id}',
        sourcePrimitiveId: source,
        semanticType: DrawingSemanticType.unknown,
        confidence: room.confidence,
        reasons: reasons,
      );
      spaces.add(
        InterpretedSpace(
          id: room.id,
          sourcePrimitiveId: source,
          polygon: room.polygon,
          areaNormalized: room.areaNormalized,
          boundaryWallIds: boundary,
          boundaryOpeningIds: const [],
          adjacentSpaceIds: const [],
          boundaryConfidence: boundary.isEmpty
              ? room.confidence * 0.65
              : room.confidence,
          topologyValid: true,
          reasons: reasons,
        ),
      );
    }

    final openings = <InterpretedOpening>[];
    for (final opening in input.openings) {
      final source = 'primitive-opening-${opening.id}';
      if (opening.wallId == null || !graph.containsWall(opening.wallId!)) {
        const reasons = ['opening is not attached to a validated wall'];
        openings.add(
          InterpretedOpening(
            id: opening.id,
            sourcePrimitiveId: source,
            kind: switch (opening.type) {
              OpeningType.door => DrawingSemanticType.doorSymbol,
              OpeningType.window => DrawingSemanticType.windowSymbol,
              OpeningType.unknown => DrawingSemanticType.unknown,
            },
            center: opening.center,
            widthNormalized: opening.widthNormalized,
            parentWallId: null,
            confidence: opening.confidence,
            reasons: reasons,
          ),
        );
        semantics[source] = SemanticPrimitive(
          id: 'semantic-${opening.id}',
          sourcePrimitiveId: source,
          semanticType: DrawingSemanticType.unknown,
          confidence: 0.2,
          reasons: reasons,
        );
        continue;
      }
      final wall = validWalls.firstWhere((value) => value.id == opening.wallId);
      final type = switch (opening.type) {
        OpeningType.door => DrawingSemanticType.doorSymbol,
        OpeningType.window => DrawingSemanticType.windowSymbol,
        OpeningType.unknown => DrawingSemanticType.opening,
      };
      final reasons = const ['opening is attached to a validated wall'];
      openings.add(
        InterpretedOpening(
          id: opening.id,
          sourcePrimitiveId: source,
          kind: type,
          center: opening.center,
          widthNormalized: opening.widthNormalized,
          parentWallId: opening.wallId!,
          confidence: opening.confidence,
          reasons: reasons,
          connectsSpaceIds: _spacesNear(opening.center, wall, spaces),
        ),
      );
      semantics[source] = SemanticPrimitive(
        id: 'semantic-${opening.id}',
        sourcePrimitiveId: source,
        semanticType: type,
        confidence: openings.last.confidence,
        reasons: reasons,
      );
    }

    final relatedSpaces = [
      for (final space in spaces)
        _relations(
          space,
          spaces,
          openings,
          validWalls,
          input.walls,
          objects,
        ),
    ];
    final dimensions = <DimensionEvidence>[
      for (final rejected in input.rejectedWalls)
        DimensionEvidence(
          id: 'dimension-${rejected.id}',
          sourcePrimitiveId: 'primitive-rejected-${rejected.id}',
          confidence: 0.45,
          reasons: const [
            'linear evidence rejected from wall geometry',
            'reserved for OCR or dimension-provider confirmation',
          ],
        ),
    ];
    final annotations = <AnnotationEvidence>[
      for (final id in annotationWalls)
        AnnotationEvidence(
          id: 'annotation-$id',
          sourcePrimitiveId: 'primitive-wall-$id',
          confidence: 0.62,
          reasons: const ['disconnected from architectural wall topology'],
        ),
    ];
    for (final dimension in dimensions) {
      semantics[dimension.sourcePrimitiveId] = SemanticPrimitive(
        id: 'semantic-${dimension.id}',
        sourcePrimitiveId: dimension.sourcePrimitiveId,
        semanticType: DrawingSemanticType.dimension,
        confidence: dimension.confidence,
        reasons: dimension.reasons,
      );
    }
    final semanticList = [
      for (final primitive in primitives)
        semantics[primitive.id] ??
            SemanticPrimitive(
              id: 'semantic-${primitive.id}',
              sourcePrimitiveId: primitive.id,
              semanticType: DrawingSemanticType.unknown,
              confidence: 0,
              reasons: const ['no semantic evidence available'],
            ),
    ];
    final warnings = [...input.warnings];
    if (objects.isNotEmpty) {
      warnings.add(
        '\uac00\uad6c/\uc124\ube44 \ud6c4\ubcf4\ub97c \uacf5\uac04\uc5d0\uc11c \uc81c\uc678\ud588\uc2b5\ub2c8\ub2e4.',
      );
    }
    if (annotations.isNotEmpty || dimensions.isNotEmpty) {
      warnings.add(
        '${annotations.length + dimensions.length} annotation/dimension candidate(s) excluded from walls.',
      );
    }
    return ArchitecturalInterpretation(
      primitives: primitives,
      semanticPrimitives: semanticList,
      wallGraph: graph,
      openings: openings,
      spaces: relatedSpaces,
      objects: objects,
      dimensions: dimensions,
      annotations: annotations,
      traces: traces,
      diagnostics: _diagnostics(
        primitives,
        semanticList,
        graph,
        openings,
        relatedSpaces,
        objects,
        annotations,
        dimensions,
      ),
      warnings: warnings,
    );
  }

  List<DetectedPrimitive> _primitives(FloorPlanAnalysisResult input) => [
    for (final wall in input.walls)
      DetectedPrimitive(
        id: 'primitive-wall-${wall.id}',
        geometry: PrimitiveGeometry(
          type: PrimitiveGeometryType.segment,
          points: [wall.start, wall.end],
          thicknessNormalized: wall.thicknessNormalized,
        ),
        sourceDetector: 'run-length-wall-band',
        candidateTypes: const [
          DrawingSemanticType.wall,
          DrawingSemanticType.annotation,
          DrawingSemanticType.dimension,
          DrawingSemanticType.unknown,
        ],
        confidence: wall.confidence,
      ),
    for (final opening in input.openings)
      DetectedPrimitive(
        id: 'primitive-opening-${opening.id}',
        geometry: PrimitiveGeometry(
          type: PrimitiveGeometryType.point,
          points: [opening.center],
        ),
        sourceDetector: 'wall-gap-opening',
        candidateTypes: const [
          DrawingSemanticType.opening,
          DrawingSemanticType.doorSymbol,
          DrawingSemanticType.windowSymbol,
          DrawingSemanticType.unknown,
        ],
        confidence: opening.confidence,
        parentSourceIds: [
          if (opening.wallId != null) 'primitive-wall-${opening.wallId!}',
        ],
      ),
    for (final room in input.rooms)
      DetectedPrimitive(
        id: 'primitive-room-${room.id}',
        geometry: PrimitiveGeometry(
          type: PrimitiveGeometryType.polygon,
          points: room.polygon,
          closed: room.closed,
        ),
        sourceDetector: 'flood-fill-region',
        candidateTypes: const [
          DrawingSemanticType.unknown,
          DrawingSemanticType.furniture,
          DrawingSemanticType.fixture,
        ],
        confidence: room.confidence,
      ),
    for (final rejected in input.rejectedWalls)
      DetectedPrimitive(
        id: 'primitive-rejected-${rejected.id}',
        geometry: PrimitiveGeometry(
          type: PrimitiveGeometryType.segment,
          points: [rejected.start, rejected.end],
          thicknessNormalized: rejected.thicknessNormalized,
        ),
        sourceDetector: 'rejected-wall-band',
        candidateTypes: const [
          DrawingSemanticType.dimension,
          DrawingSemanticType.annotation,
          DrawingSemanticType.unknown,
        ],
        confidence: 0.4,
      ),
  ];

  Map<String, Set<String>> _links(List<WallSegment> walls) {
    final links = {for (final wall in walls) wall.id: <String>{}};
    for (var i = 0; i < walls.length; i++) {
      for (var j = i + 1; j < walls.length; j++) {
        if (_touch(walls[i], walls[j])) {
          links[walls[i].id]!.add(walls[j].id);
          links[walls[j].id]!.add(walls[i].id);
        }
      }
    }
    return links;
  }

  bool _touch(WallSegment a, WallSegment b) {
    for (final p in [a.start, a.end]) {
      if (_distance(p, b.start, b.end) <= 0.018) return true;
    }
    for (final p in [b.start, b.end]) {
      if (_distance(p, a.start, a.end) <= 0.018) return true;
    }
    return false;
  }

  List<List<String>> _components(
    List<WallSegment> walls,
    Map<String, Set<String>> links,
  ) {
    final unseen = walls.map((wall) => wall.id).toSet();
    final result = <List<String>>[];
    while (unseen.isNotEmpty) {
      final queue = [unseen.first];
      unseen.remove(queue.first);
      final component = <String>[];
      while (queue.isNotEmpty) {
        final id = queue.removeLast();
        component.add(id);
        for (final next in links[id] ?? const <String>{}) {
          if (unseen.remove(next)) queue.add(next);
        }
      }
      result.add(component);
    }
    return result;
  }

  List<WallGraphJunction> _junctions(List<WallSegment> walls) {
    final result = <WallGraphJunction>[];
    final used = <String>{};
    for (final wall in walls) {
      for (final point in [wall.start, wall.end]) {
        final ids = walls
            .where((other) => _distance(point, other.start, other.end) <= 0.018)
            .map((other) => other.id)
            .toSet();
        if (ids.length < 2) continue;
        final sorted = ids.toList()..sort();
        final key =
            sorted.join('|') +
            point.x.toStringAsFixed(2) +
            point.y.toStringAsFixed(2);
        if (!used.add(key)) continue;
        result.add(
          WallGraphJunction(
            id: 'junction-${result.length + 1}',
            position: point,
            type: ids.length == 2
                ? WallJunctionType.l
                : ids.length == 3
                ? WallJunctionType.t
                : WallJunctionType.x,
            wallIds: sorted,
          ),
        );
      }
    }
    return result;
  }

  RoomCandidate? _containerFor(RoomCandidate room, List<RoomCandidate> rooms) {
    RoomCandidate? best;
    for (final candidate in rooms) {
      if (candidate.id == room.id ||
          candidate.areaNormalized <= room.areaNormalized ||
          !_polygonContains(candidate.polygon, room.polygon)) {
        continue;
      }
      if (best == null || candidate.areaNormalized < best.areaNormalized) {
        best = candidate;
      }
    }
    return best;
  }

  bool _supports(WallSegment wall, List<Point2> polygon) {
    final middle = Point2(
      (wall.start.x + wall.end.x) / 2,
      (wall.start.y + wall.end.y) / 2,
    );
    for (var i = 0; i < polygon.length; i++) {
      if (_distance(middle, polygon[i], polygon[(i + 1) % polygon.length]) <=
          math.max(wall.thicknessNormalized * 2, 0.025)) {
        return true;
      }
    }
    return false;
  }

  bool _nearPolygon(Point2 point, List<Point2> polygon) {
    for (var i = 0; i < polygon.length; i++) {
      if (_distance(point, polygon[i], polygon[(i + 1) % polygon.length]) <=
          0.025) {
        return true;
      }
    }
    return false;
  }

  bool _strictInside(List<Point2> polygon, Point2 point) =>
      _contains(polygon, point) && !_nearPolygon(point, polygon);

  bool _polygonContains(List<Point2> outer, List<Point2> inner) =>
      inner.every((point) => _contains(outer, point));

  bool _contains(List<Point2> polygon, Point2 point) {
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

  double _distance(Point2 p, Point2 a, Point2 b) {
    final dx = b.x - a.x, dy = b.y - a.y;
    if (dx == 0 && dy == 0) return p.distanceTo(a);
    final t = (((p.x - a.x) * dx + (p.y - a.y) * dy) / (dx * dx + dy * dy))
        .clamp(0.0, 1.0);
    return p.distanceTo(Point2(a.x + t * dx, a.y + t * dy));
  }

  List<String> _spacesNear(
    Point2 center,
    WallSegment wall,
    List<InterpretedSpace> spaces,
  ) {
    final offset = math.max(wall.thicknessNormalized * 1.5, 0.01);
    final points = wall.isHorizontal
        ? [
            Point2(center.x, center.y - offset),
            Point2(center.x, center.y + offset),
          ]
        : [
            Point2(center.x - offset, center.y),
            Point2(center.x + offset, center.y),
          ];
    return [
      for (final space in spaces)
        if (points.any((point) => _contains(space.polygon, point))) space.id,
    ];
  }

  InterpretedSpace _relations(
    InterpretedSpace space,
    List<InterpretedSpace> spaces,
    List<InterpretedOpening> openings,
    List<WallSegment> validWalls,
    List<WallSegment> allWalls,
    List<InterpretedObject> objects,
  ) {
    final adjacent = <String>{};
    for (final id in space.boundaryWallIds) {
      final wall = validWalls.firstWhere((value) => value.id == id);
      for (final other in spaces) {
        if (other.id != space.id && _supports(wall, other.polygon)) {
          adjacent.add(other.id);
        }
      }
    }
    final openingIds = openings
        .where(
          (opening) =>
              space.boundaryWallIds.contains(opening.parentWallId) ||
              opening.connectsSpaceIds.contains(space.id),
        )
        .map((opening) => opening.id)
        .toList();

    // Space-first 재작업 WO — 폴리곤 변 하나하나를 벽/문/창/열린 통로/
    // 가상 경계로 해석한다(WO 지시 3/6번). 검증된 벽 그래프
    // 멤버십([space.boundaryWallIds])보다 넓게, 전체 벽 evidence(
    // [allWalls])와 다른 SPACE와의 실제 인접 관계까지 함께 본다 — 그
    // 결과로 발견되는 "벽 없이 맞닿은 이웃 공간"도 adjacentSpaceIds에
    // 추가한다(예: 벽 없이 트인 거실↔주방).
    final segments = _boundarySegmentsFor(space, spaces, allWalls, openings);
    for (final segment in segments) {
      if (segment.oppositeSpaceId != null) adjacent.add(segment.oppositeSpaceId!);
    }

    final containedObjectIds = [
      for (final object in objects)
        if (object.containingSpaceId == space.id) object.id,
    ];

    return InterpretedSpace(
      id: space.id,
      sourcePrimitiveId: space.sourcePrimitiveId,
      polygon: space.polygon,
      areaNormalized: space.areaNormalized,
      boundaryWallIds: space.boundaryWallIds,
      boundaryOpeningIds: openingIds,
      adjacentSpaceIds: adjacent.toList(),
      boundaryConfidence: space.boundaryConfidence,
      topologyValid: space.topologyValid,
      reasons: space.reasons,
      boundarySegments: segments,
      containedObjectIds: containedObjectIds,
    );
  }

  /// [space]의 폴리곤 변(edge)을 하나씩 해석한다 — space-first 원칙의
  /// 핵심: 벽 evidence가 없다고 그 구간을 빠뜨리지 않고, 다른 SPACE와의
  /// 인접/이미지 경계 근접 여부까지 함께 봐서 항상 어떤 type이든(최소
  /// unknown) 배정한다.
  List<InterpretedBoundarySegment> _boundarySegmentsFor(
    InterpretedSpace space,
    List<InterpretedSpace> allSpaces,
    List<WallSegment> allWalls,
    List<InterpretedOpening> openings,
  ) {
    final polygon = space.polygon;
    final segments = <InterpretedBoundarySegment>[];
    for (var i = 0; i < polygon.length; i++) {
      final a = polygon[i];
      final b = polygon[(i + 1) % polygon.length];
      final mid = Point2((a.x + b.x) / 2, (a.y + b.y) / 2);
      final id = 'boundary-${space.id}-$i';

      WallSegment? matchedWall;
      var bestDist = double.infinity;
      for (final wall in allWalls) {
        final d = _distance(mid, wall.start, wall.end);
        final tolerance = math.max(wall.thicknessNormalized * 2, 0.02);
        if (d <= tolerance && d < bestDist) {
          matchedWall = wall;
          bestDist = d;
        }
      }

      if (matchedWall != null) {
        InterpretedOpening? matchedOpening;
        for (final opening in openings) {
          if (_distance(opening.center, a, b) <= 0.03) {
            matchedOpening = opening;
            break;
          }
        }
        if (matchedOpening != null) {
          final type = switch (matchedOpening.kind) {
            DrawingSemanticType.doorSymbol => BoundarySegmentType.door,
            DrawingSemanticType.windowSymbol => BoundarySegmentType.window,
            _ => BoundarySegmentType.openPassage,
          };
          segments.add(
            InterpretedBoundarySegment(
              id: id,
              start: a,
              end: b,
              type: type,
              confidence: matchedOpening.confidence,
              reasons: const [
                'opening evidence found along this boundary edge',
              ],
              wallId: matchedWall.id,
              openingId: matchedOpening.id,
              isExterior: matchedWall.isExterior,
            ),
          );
          continue;
        }
        segments.add(
          InterpretedBoundarySegment(
            id: id,
            start: a,
            end: b,
            type: BoundarySegmentType.wall,
            confidence: matchedWall.confidence,
            reasons: const ['wall evidence found along this boundary edge'],
            wallId: matchedWall.id,
            isExterior: matchedWall.isExterior,
          ),
        );
        continue;
      }

      // 벽 evidence가 없다 — 다른 SPACE와 실제로 맞닿아 있는지 본다
      // (edge 중점에서 바깥쪽으로 살짝 벗어난 점이 다른 SPACE 안에
      // 있으면 그 SPACE가 반대편이다).
      final dx = b.x - a.x, dy = b.y - a.y;
      final len = math.sqrt(dx * dx + dy * dy);
      String? oppositeId;
      if (len > 0) {
        const off = 0.015;
        final nx = -dy / len * off, ny = dx / len * off;
        final p1 = Point2(mid.x + nx, mid.y + ny);
        final p2 = Point2(mid.x - nx, mid.y - ny);
        final outward = _contains(space.polygon, p1) ? p2 : p1;
        for (final other in allSpaces) {
          if (other.id == space.id) continue;
          if (_contains(other.polygon, outward)) {
            oppositeId = other.id;
            break;
          }
        }
      }

      final nearImageBorder =
          mid.x <= 0.02 || mid.x >= 0.98 || mid.y <= 0.02 || mid.y >= 0.98;

      if (oppositeId != null) {
        segments.add(
          InterpretedBoundarySegment(
            id: id,
            start: a,
            end: b,
            type: BoundarySegmentType.virtual,
            confidence: 0.4,
            reasons: const [
              'no wall evidence, but this edge borders another detected '
                  'space — kept as a virtual/open boundary rather than '
                  'dropped',
            ],
            oppositeSpaceId: oppositeId,
          ),
        );
      } else {
        segments.add(
          InterpretedBoundarySegment(
            id: id,
            start: a,
            end: b,
            type: BoundarySegmentType.unknown,
            confidence: 0.2,
            reasons: const [
              'no wall evidence and no neighboring space found for this '
                  'edge',
            ],
            isExterior: nearImageBorder,
          ),
        );
      }
    }
    return segments;
  }

  List<DrawingDiagnosticOutput> _diagnostics(
    List<DetectedPrimitive> primitives,
    List<SemanticPrimitive> semantics,
    ArchitecturalWallGraph graph,
    List<InterpretedOpening> openings,
    List<InterpretedSpace> spaces,
    List<InterpretedObject> objects,
    List<AnnotationEvidence> annotations,
    List<DimensionEvidence> dimensions,
  ) => [
    DrawingDiagnosticOutput(
      stage: DrawingDiagnosticStage.raw,
      entityIds: primitives.map((value) => value.id).toList(),
      summary: '${primitives.length} detector evidence item(s)',
    ),
    DrawingDiagnosticOutput(
      stage: DrawingDiagnosticStage.geometry,
      entityIds: primitives.map((value) => value.id).toList(),
      summary: 'normalized segments, points and contours',
    ),
    DrawingDiagnosticOutput(
      stage: DrawingDiagnosticStage.semantic,
      entityIds: semantics.map((value) => value.id).toList(),
      summary: '${semantics.length} semantic classification(s)',
    ),
    DrawingDiagnosticOutput(
      stage: DrawingDiagnosticStage.wallGraph,
      entityIds: graph.walls.map((value) => value.id).toList(),
      summary:
          '${graph.walls.length} validated wall(s), ${graph.junctions.length} junction(s)',
    ),
    DrawingDiagnosticOutput(
      stage: DrawingDiagnosticStage.openings,
      entityIds: openings.map((value) => value.id).toList(),
      summary: '${openings.length} wall-bound opening(s)',
    ),
    DrawingDiagnosticOutput(
      stage: DrawingDiagnosticStage.spaces,
      entityIds: spaces.map((value) => value.id).toList(),
      summary: '${spaces.length} topology-valid space(s)',
    ),
    DrawingDiagnosticOutput(
      stage: DrawingDiagnosticStage.objects,
      entityIds: objects.map((value) => value.id).toList(),
      summary:
          '\uac00\uad6c/\uc124\ube44 \ud6c4\ubcf4\ub97c \uacf5\uac04\uc5d0\uc11c \uc81c\uc678\ud588\uc2b5\ub2c8\ub2e4.',
    ),
    DrawingDiagnosticOutput(
      stage: DrawingDiagnosticStage.annotations,
      entityIds: [
        ...annotations.map((value) => value.id),
        ...dimensions.map((value) => value.id),
      ],
      summary:
          '${annotations.length} annotation and ${dimensions.length} dimension candidate(s)',
    ),
    DrawingDiagnosticOutput(
      stage: DrawingDiagnosticStage.finalModel,
      entityIds: [
        ...graph.walls.map((value) => value.id),
        ...openings.map((value) => value.id),
        ...spaces.map((value) => value.id),
        ...objects.map((value) => value.id),
      ],
      summary: 'interpreted model ready for SS/CAD bridge',
    ),
  ];

  double _clamp(double value) => value.clamp(0.0, 1.0);
}
