// SS008 — [ssSpatialModelToJson]/[ssSpatialModelFromJson] 왕복 변환 검증.
import 'package:ason_space/models/floor_plan_geometry.dart' show Point2;
import 'package:ason_space/models/ss_spatial_model.dart';
import 'package:ason_space/models/ss_spatial_model_json.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SSSpatialModel 전체(각 엔티티·선택 필드 포함)를 JSON으로 저장했다가 그대로 복원한다', () {
    const model = SSSpatialModel(
      sourceWidthPx: 1000,
      sourceHeightPx: 800,
      spaces: [
        SSSpace(
          id: 'space-1',
          polygon: [Point2(0.1, 0.1), Point2(0.9, 0.1), Point2(0.9, 0.9), Point2(0.1, 0.9)],
          areaNormalized: 0.6,
          closed: true,
          confidence: 0.8,
          spaceConfidence: SSSpaceConfidence.low,
          adjacentSpaceIds: ['space-2'],
          boundaryOpeningIds: ['door-1'],
          boundaryIds: ['boundary-1'],
          containedObjectIds: ['obj-1'],
          source: SSEntitySource.vision,
          reviewNeeded: true,
          reviewReasons: ['신뢰도 낮음'],
          label: '거실',
          roomType: SSRoomType.other,
        ),
      ],
      walls: [
        SSWall(
          id: 'wall-1',
          start: Point2(0.0, 0.0),
          end: Point2(1.0, 0.0),
          thicknessNormalized: 0.02,
          kind: SSWallKind.exterior,
          confidence: 0.4,
          separatesSpaceIds: ['space-1'],
          reviewNeeded: true,
          reviewReasons: ['두께 불확실'],
        ),
      ],
      openings: [
        SSOpening(
          id: 'door-1',
          kind: SSOpeningKind.door,
          center: Point2(0.5, 0.0),
          widthNormalized: 0.05,
          confidence: 0.7,
          wallId: 'wall-1',
          parentWallId: 'edge-1',
          startT: 0.2,
          endT: 0.3,
          connectsSpaceIds: ['space-1'],
        ),
      ],
      objects: [
        SSObjectCandidate(id: 'obj-1', polygon: [Point2(0.2, 0.2), Point2(0.3, 0.2), Point2(0.3, 0.3)], kind: SSObjectKind.toilet, containingSpaceId: 'space-1'),
      ],
      warnings: ['공간이 완전히 닫히지 않았습니다.'],
      boundaries: [
        SSBoundary(
          id: 'boundary-1',
          spaceId: 'space-1',
          start: Point2(0.0, 0.0),
          end: Point2(1.0, 0.0),
          type: SSBoundaryType.wall,
          confidence: 0.5,
          oppositeSpaceId: 'space-2',
          isExterior: true,
          wallId: 'wall-1',
          openingId: 'door-1',
        ),
      ],
      structuralElements: [
        SSStructuralElement(id: 'col-1', kind: SSStructuralKind.column, polygon: [Point2(0.4, 0.4), Point2(0.45, 0.4), Point2(0.45, 0.45)], confidence: 0.3, reviewNeeded: true),
      ],
      dimensions: [
        SSDimension(id: 'dim-1', rawText: '3600', parsedValueMm: 3600, appliesToBoundaryId: 'boundary-1', confidence: SSSpaceConfidence.high),
      ],
      wallEdges: [
        SSWallEdge(id: 'edge-1', start: Point2(0.0, 0.0), end: Point2(1.0, 0.0), thicknessNormalized: 0.02, kind: SSWallKind.exterior, confidence: 0.6, physicalWallIds: ['wall-1']),
      ],
      floorDomain: [Point2(0.0, 0.0), Point2(1.0, 0.0), Point2(1.0, 1.0), Point2(0.0, 1.0)],
    );

    final json = ssSpatialModelToJson(model);
    final restored = ssSpatialModelFromJson(json);

    expect(restored, isNotNull);
    expect(restored!.sourceWidthPx, 1000);
    expect(restored.sourceHeightPx, 800);

    expect(restored.spaces, hasLength(1));
    final space = restored.spaces.single;
    expect(space.id, 'space-1');
    expect(space.polygon, model.spaces.single.polygon);
    expect(space.spaceConfidence, SSSpaceConfidence.low);
    expect(space.reviewNeeded, isTrue);
    expect(space.reviewReasons, ['신뢰도 낮음']);
    expect(space.label, '거실');
    expect(space.source, SSEntitySource.vision);

    final wall = restored.walls.single;
    expect(wall.id, 'wall-1');
    expect(wall.kind, SSWallKind.exterior);
    expect(wall.confidence, 0.4);
    expect(wall.reviewNeeded, isTrue);

    final opening = restored.openings.single;
    expect(opening.kind, SSOpeningKind.door);
    expect(opening.parentWallId, 'edge-1');
    expect(opening.startT, 0.2);
    expect(opening.endT, 0.3);

    final obj = restored.objects.single;
    expect(obj.kind, SSObjectKind.toilet);
    expect(obj.containingSpaceId, 'space-1');

    final boundary = restored.boundaries.single;
    expect(boundary.type, SSBoundaryType.wall);
    expect(boundary.oppositeSpaceId, 'space-2');
    expect(boundary.isExterior, isTrue);

    final structural = restored.structuralElements.single;
    expect(structural.kind, SSStructuralKind.column);
    expect(structural.reviewNeeded, isTrue);

    final dimension = restored.dimensions.single;
    expect(dimension.parsedValueMm, 3600);
    expect(dimension.confidence, SSSpaceConfidence.high);

    final edge = restored.wallEdges.single;
    expect(edge.physicalWallIds, ['wall-1']);

    expect(restored.floorDomain, model.floorDomain);
    expect(restored.warnings, ['공간이 완전히 닫히지 않았습니다.']);
  });

  test('깨진/필수값 없는 JSON은 null을 돌려준다(가짜 모델을 만들어 내지 않는다)', () {
    expect(ssSpatialModelFromJson(null), isNull);
    expect(ssSpatialModelFromJson(<String, Object?>{'sourceWidthPx': 100}), isNull);
    expect(ssSpatialModelFromJson('not a map'), isNull);
  });
}
