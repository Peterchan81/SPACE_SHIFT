import 'package:flutter/foundation.dart';

import 'floor_plan_geometry.dart';

enum DrawingDiagnosticStage {
  raw,
  geometry,
  semantic,
  wallGraph,
  openings,
  spaces,
  objects,
  annotations,
  finalModel,
}

enum DrawingSemanticType {
  wall,
  opening,
  doorSymbol,
  windowSymbol,
  furniture,
  fixture,
  stair,
  structural,
  dimension,
  annotation,
  unknown,
}

enum PrimitiveGeometryType { segment, polygon, point }

@immutable
class PrimitiveGeometry {
  const PrimitiveGeometry({
    required this.type,
    required this.points,
    this.thicknessNormalized,
    this.closed = false,
  });

  final PrimitiveGeometryType type;
  final List<Point2> points;
  final double? thicknessNormalized;
  final bool closed;

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'points': [
      for (final point in points) {'x': point.x, 'y': point.y},
    ],
    if (thicknessNormalized != null) 'thicknessNormalized': thicknessNormalized,
    'closed': closed,
  };

  factory PrimitiveGeometry.fromJson(Map<String, dynamic> json) =>
      PrimitiveGeometry(
        type: PrimitiveGeometryType.values.byName(json['type'] as String),
        points: [
          for (final raw in json['points'] as List)
            Point2(
              (raw as Map<String, dynamic>)['x'] as double,
              raw['y'] as double,
            ),
        ],
        thicknessNormalized: json['thicknessNormalized'] as double?,
        closed: json['closed'] as bool? ?? false,
      );
}

@immutable
class DetectedPrimitive {
  const DetectedPrimitive({
    required this.id,
    required this.geometry,
    required this.sourceDetector,
    required this.candidateTypes,
    required this.confidence,
    this.parentSourceIds = const [],
  });

  final String id;
  final PrimitiveGeometry geometry;
  final String sourceDetector;
  final List<DrawingSemanticType> candidateTypes;
  final double confidence;
  final List<String> parentSourceIds;

  Map<String, dynamic> toJson() => {
    'id': id,
    'geometry': geometry.toJson(),
    'sourceDetector': sourceDetector,
    'candidateTypes': candidateTypes.map((value) => value.name).toList(),
    'confidence': confidence,
    'parentSourceIds': parentSourceIds,
  };

  factory DetectedPrimitive.fromJson(Map<String, dynamic> json) =>
      DetectedPrimitive(
        id: json['id'] as String,
        geometry: PrimitiveGeometry.fromJson(
          json['geometry'] as Map<String, dynamic>,
        ),
        sourceDetector: json['sourceDetector'] as String,
        candidateTypes: [
          for (final name in json['candidateTypes'] as List)
            DrawingSemanticType.values.byName(name as String),
        ],
        confidence: (json['confidence'] as num).toDouble(),
        parentSourceIds: (json['parentSourceIds'] as List? ?? const [])
            .cast<String>(),
      );
}

@immutable
class SemanticPrimitive {
  const SemanticPrimitive({
    required this.id,
    required this.sourcePrimitiveId,
    required this.semanticType,
    required this.confidence,
    required this.reasons,
    this.evidenceIds = const [],
  });

  final String id;
  final String sourcePrimitiveId;
  final DrawingSemanticType semanticType;
  final double confidence;
  final List<String> reasons;
  final List<String> evidenceIds;
}

@immutable
class EvidenceTrace {
  const EvidenceTrace({
    required this.id,
    required this.stage,
    required this.sourceIds,
    required this.classification,
    required this.confidence,
    required this.reasons,
  });

  final String id;
  final DrawingDiagnosticStage stage;
  final List<String> sourceIds;
  final DrawingSemanticType classification;
  final double confidence;
  final List<String> reasons;
}

enum WallJunctionType { end, l, t, x }

@immutable
class WallGraphJunction {
  const WallGraphJunction({
    required this.id,
    required this.position,
    required this.type,
    required this.wallIds,
  });

  final String id;
  final Point2 position;
  final WallJunctionType type;
  final List<String> wallIds;
}

@immutable
class ArchitecturalWall {
  const ArchitecturalWall({
    required this.id,
    required this.sourcePrimitiveId,
    required this.segment,
    required this.confidence,
    required this.reasons,
    this.junctionIds = const [],
  });

  final String id;
  final String sourcePrimitiveId;
  final WallSegment segment;
  final double confidence;
  final List<String> reasons;
  final List<String> junctionIds;
}

@immutable
class ArchitecturalWallGraph {
  const ArchitecturalWallGraph({
    required this.walls,
    required this.junctions,
    required this.connectedComponents,
  });

  final List<ArchitecturalWall> walls;
  final List<WallGraphJunction> junctions;
  final List<List<String>> connectedComponents;

  bool containsWall(String id) => walls.any((wall) => wall.id == id);
}

@immutable
class InterpretedOpening {
  const InterpretedOpening({
    required this.id,
    required this.sourcePrimitiveId,
    required this.kind,
    required this.center,
    required this.widthNormalized,
    required this.parentWallId,
    required this.confidence,
    required this.reasons,
    this.connectsSpaceIds = const [],
  });

  final String id;
  final String sourcePrimitiveId;
  final DrawingSemanticType kind;
  final Point2 center;
  final double widthNormalized;
  final String? parentWallId;
  final double confidence;
  final List<String> reasons;
  final List<String> connectsSpaceIds;
}

/// Space-first 재작업 WO — [InterpretedSpace]의 경계를 이루는 한 구간의
/// 건축적 의미. 폴리곤 변(edge) 하나가 항상 "벽"인 것은 아니다 — 실제
/// 검출된 벽 evidence가 그 구간에 있으면 wall, 문/창 evidence가 있으면
/// door/window, 벽 evidence 없이 다른 SPACE와 맞닿아 있으면(예: 벽 없이
/// 트인 거실↔주방) openPassage, 그마저도 없으면(분석이 확신할 수 없는
/// 구간) virtual/unknown으로 정직하게 남긴다 — "이 구간이 뭔지 확실하지
/// 않다"를 숨기지 않는다.
enum BoundarySegmentType {
  wall,
  door,
  window,
  openPassage,
  column,
  virtual,
  unknown,
}

@immutable
class InterpretedBoundarySegment {
  const InterpretedBoundarySegment({
    required this.id,
    required this.start,
    required this.end,
    required this.type,
    required this.confidence,
    required this.reasons,
    this.wallId,
    this.openingId,
    this.oppositeSpaceId,
    this.isExterior = false,
  });

  final String id;
  final Point2 start;
  final Point2 end;
  final BoundarySegmentType type;
  final double confidence;
  final List<String> reasons;

  /// 이 구간의 근거가 된 [ArchitecturalWall]/[InterpretedOpening] id(있으면).
  final String? wallId;
  final String? openingId;

  /// 이 구간 반대편에 있는 다른 [InterpretedSpace]의 id(있으면 — 즉
  /// 이 구간이 두 공간을 나눈다는 뜻).
  final String? oppositeSpaceId;

  /// 반대편이 건물 바깥(SPACE가 아님)인지 — [oppositeSpaceId]가 null이고
  /// 이 값이 true면 외부 경계, false면 아직 반대편을 특정하지 못한
  /// 미상 구간이다.
  final bool isExterior;
}

@immutable
class InterpretedSpace {
  const InterpretedSpace({
    required this.id,
    required this.sourcePrimitiveId,
    required this.polygon,
    required this.areaNormalized,
    required this.boundaryWallIds,
    required this.boundaryOpeningIds,
    required this.adjacentSpaceIds,
    required this.boundaryConfidence,
    required this.topologyValid,
    required this.reasons,
    this.boundarySegments = const [],
    this.containedObjectIds = const [],
  });

  final String id;
  final String sourcePrimitiveId;
  final List<Point2> polygon;
  final double areaNormalized;
  final List<String> boundaryWallIds;
  final List<String> boundaryOpeningIds;
  final List<String> adjacentSpaceIds;
  final double boundaryConfidence;
  final bool topologyValid;
  final List<String> reasons;

  /// Space-first 재작업 WO — 이 공간의 폴리곤 변을 하나씩 해석한 결과
  /// (wall/door/window/openPassage/column/virtual/unknown). [boundaryWallIds]
  /// (검증된 벽 그래프 멤버십만)보다 더 완전한 표현이다 — 벽 evidence가
  /// 없는 구간도 빠뜨리지 않고 virtual/unknown으로 채운다.
  final List<InterpretedBoundarySegment> boundarySegments;

  /// 이 공간 내부에 있는 [InterpretedObject](가구/설비) id 목록.
  final List<String> containedObjectIds;
}

@immutable
class InterpretedObject {
  const InterpretedObject({
    required this.id,
    required this.sourcePrimitiveId,
    required this.semanticType,
    required this.polygon,
    required this.confidence,
    required this.reasons,
    this.containingSpaceId,
  });

  final String id;
  final String sourcePrimitiveId;
  final DrawingSemanticType semanticType;
  final List<Point2> polygon;
  final double confidence;
  final List<String> reasons;
  final String? containingSpaceId;
}

@immutable
class DimensionEvidence {
  const DimensionEvidence({
    required this.id,
    required this.sourcePrimitiveId,
    required this.confidence,
    required this.reasons,
    this.text,
  });

  final String id;
  final String sourcePrimitiveId;
  final double confidence;
  final List<String> reasons;
  final String? text;
}

@immutable
class AnnotationEvidence {
  const AnnotationEvidence({
    required this.id,
    required this.sourcePrimitiveId,
    required this.confidence,
    required this.reasons,
  });

  final String id;
  final String sourcePrimitiveId;
  final double confidence;
  final List<String> reasons;
}

@immutable
class DrawingDiagnosticOutput {
  const DrawingDiagnosticOutput({
    required this.stage,
    required this.entityIds,
    required this.summary,
  });

  final DrawingDiagnosticStage stage;
  final List<String> entityIds;
  final String summary;
}

@immutable
class ArchitecturalInterpretation {
  const ArchitecturalInterpretation({
    required this.primitives,
    required this.semanticPrimitives,
    required this.wallGraph,
    required this.openings,
    required this.spaces,
    required this.objects,
    required this.dimensions,
    required this.annotations,
    required this.traces,
    required this.diagnostics,
    required this.warnings,
  });

  final List<DetectedPrimitive> primitives;
  final List<SemanticPrimitive> semanticPrimitives;
  final ArchitecturalWallGraph wallGraph;
  final List<InterpretedOpening> openings;
  final List<InterpretedSpace> spaces;
  final List<InterpretedObject> objects;
  final List<DimensionEvidence> dimensions;
  final List<AnnotationEvidence> annotations;
  final List<EvidenceTrace> traces;
  final List<DrawingDiagnosticOutput> diagnostics;
  final List<String> warnings;
}

abstract class SemanticEvidenceProvider {
  const SemanticEvidenceProvider();

  Future<List<SemanticPrimitive>> classify(List<DetectedPrimitive> primitives);
}

class NoOpSemanticEvidenceProvider extends SemanticEvidenceProvider {
  const NoOpSemanticEvidenceProvider();

  @override
  Future<List<SemanticPrimitive>> classify(
    List<DetectedPrimitive> primitives,
  ) async => const [];
}
