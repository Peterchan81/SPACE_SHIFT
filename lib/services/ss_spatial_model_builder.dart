import '../models/drawing_understanding.dart';
import '../models/floor_plan_geometry.dart';
import '../models/ss_spatial_model.dart';
import 'envelope_first_interpreter.dart';

/// Converts detector evidence into the stable spatial model consumed by CAD.
///
/// Architectural classification lives behind [DrawingInterpreter] — this
/// adapter deliberately performs no detector-specific inference of its own.
///
/// PC2 Envelope-first 실험 WO — 기본 해석 전략을 space-first
/// ([ArchitecturalDrawingInterpreter], 방 flood-fill 후보를 먼저 보고
/// 가구/설비인지 판별)에서 envelope-first([EnvelopeFirstInterpreter], 건물
/// 외곽을 먼저 잡고 그 안을 내부 경계로 나눔)로 바꾼다. space-first
/// 구현은 삭제하지 않고 그대로 남겨 두며, 이 생성자에 명시적으로
/// 주입하면 언제든 비교할 수 있다.
class SSSpatialModelBuilder {
  const SSSpatialModelBuilder({
    this.interpreter = const EnvelopeFirstInterpreter(),
  });

  final DrawingInterpreter interpreter;

  SSSpatialModel build(FloorPlanAnalysisResult result) {
    final interpretation = interpreter.interpret(result);
    final spaces = [
      for (final space in interpretation.spaces)
        SSSpace(
          id: space.id,
          polygon: space.polygon,
          areaNormalized: space.areaNormalized,
          closed: space.topologyValid,
          confidence: space.boundaryConfidence,
          spaceConfidence: _spaceConfidence(space.boundaryConfidence),
          adjacentSpaceIds: space.adjacentSpaceIds,
          boundaryOpeningIds: space.boundaryOpeningIds,
          boundaryIds: [
            for (final segment in space.boundarySegments) segment.id,
          ],
          containedObjectIds: space.containedObjectIds,
        ),
    ];

    return SSSpatialModel(
      sourceWidthPx: result.sourceWidthPx,
      sourceHeightPx: result.sourceHeightPx,
      spaces: spaces,
      walls: [
        for (final wall in interpretation.wallGraph.walls)
          SSWall(
            id: wall.id,
            start: wall.segment.start,
            end: wall.segment.end,
            thicknessNormalized: wall.segment.thicknessNormalized,
            kind: wall.segment.isExterior
                ? SSWallKind.exterior
                : SSWallKind.interior,
            confidence: wall.confidence,
            separatesSpaceIds: [
              for (final space in interpretation.spaces)
                if (space.boundaryWallIds.contains(wall.id)) space.id,
            ],
          ),
      ],
      openings: [
        for (final opening in interpretation.openings)
          SSOpening(
            id: opening.id,
            kind: _openingKind(opening.kind),
            center: opening.center,
            widthNormalized: opening.widthNormalized,
            confidence: opening.confidence,
            wallId: opening.parentWallId,
            connectsSpaceIds: opening.connectsSpaceIds,
          ),
      ],
      objects: [
        for (final object in interpretation.objects)
          SSObjectCandidate(
            id: object.id,
            polygon: object.polygon,
            kind: SSObjectKind.furnitureOrEquipment,
            containingSpaceId: object.containingSpaceId,
          ),
      ],
      boundaries: [
        for (final space in interpretation.spaces)
          for (final segment in space.boundarySegments)
            SSBoundary(
              id: segment.id,
              spaceId: space.id,
              start: segment.start,
              end: segment.end,
              type: _boundaryType(segment.type),
              confidence: segment.confidence,
              oppositeSpaceId: segment.oppositeSpaceId,
              isExterior: segment.isExterior,
              wallId: segment.wallId,
              openingId: segment.openingId,
            ),
      ],
      warnings: interpretation.warnings,
    );
  }

  SSSpaceConfidence _spaceConfidence(double confidence) {
    if (confidence >= 0.75) return SSSpaceConfidence.high;
    if (confidence >= 0.5) return SSSpaceConfidence.medium;
    return SSSpaceConfidence.low;
  }

  SSOpeningKind _openingKind(DrawingSemanticType kind) => switch (kind) {
    DrawingSemanticType.doorSymbol => SSOpeningKind.door,
    DrawingSemanticType.windowSymbol => SSOpeningKind.window,
    DrawingSemanticType.opening => SSOpeningKind.openPassage,
    _ => SSOpeningKind.unknown,
  };

  SSBoundaryType _boundaryType(BoundarySegmentType type) => switch (type) {
    BoundarySegmentType.wall => SSBoundaryType.wall,
    BoundarySegmentType.door => SSBoundaryType.door,
    BoundarySegmentType.window => SSBoundaryType.window,
    BoundarySegmentType.openPassage => SSBoundaryType.openPassage,
    BoundarySegmentType.column => SSBoundaryType.column,
    BoundarySegmentType.virtual => SSBoundaryType.virtual,
    BoundarySegmentType.unknown => SSBoundaryType.unknown,
  };
}
