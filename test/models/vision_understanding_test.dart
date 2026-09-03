// Vision Guided CAD POC — Vision JSON 계약(vision_understanding.dart)
// 단위 테스트.
//
// 1. NormalizedPoint/GeometryHint 각 kind의 JSON 직렬화/역직렬화 왕복.
// 2. 각 entity(FloorDomain/Space/Boundary/Opening/Object/StructuralElement/
//    Dimension)의 JSON 왕복.
// 3. VisionUnderstanding 전체 왕복.
// 4. 정규화 좌표 타당성 검증(isPlausible).

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/vision_understanding.dart';

void main() {
  group('NormalizedPoint', () {
    test('JSON 왕복', () {
      const p = NormalizedPoint(0.42, 0.73);
      final json = p.toJson();
      final restored = NormalizedPoint.fromJson(json);
      expect(restored.x, closeTo(0.42, 1e-9));
      expect(restored.y, closeTo(0.73, 1e-9));
    });

    test('isPlausible — 정상 범위/약간의 오버슈트는 true, 명백한 이상값은 false', () {
      expect(const NormalizedPoint(0.5, 0.5).isPlausible, isTrue);
      expect(const NormalizedPoint(-0.05, 1.05).isPlausible, isTrue);
      expect(const NormalizedPoint(5.0, 0.5).isPlausible, isFalse);
      expect(const NormalizedPoint(double.nan, 0.5).isPlausible, isFalse);
    });
  });

  group('GeometryHint — kind별 JSON 왕복', () {
    test('point', () {
      final hint = const GeometryHint.point(NormalizedPoint(0.1, 0.2));
      final restored = GeometryHint.fromJson(hint.toJson());
      expect(restored.kind, GeometryHintKind.point);
      expect(restored.point.x, closeTo(0.1, 1e-9));
      expect(restored.point.y, closeTo(0.2, 1e-9));
    });

    test('segment', () {
      final hint = const GeometryHint.segment(
        NormalizedPoint(0.1, 0.1),
        NormalizedPoint(0.9, 0.1),
      );
      final restored = GeometryHint.fromJson(hint.toJson());
      expect(restored.kind, GeometryHintKind.segment);
      expect(restored.start.x, closeTo(0.1, 1e-9));
      expect(restored.end.x, closeTo(0.9, 1e-9));
    });

    test('polygon', () {
      final hint = const GeometryHint.polygon([
        NormalizedPoint(0.1, 0.1),
        NormalizedPoint(0.9, 0.1),
        NormalizedPoint(0.9, 0.9),
        NormalizedPoint(0.1, 0.9),
      ]);
      final restored = GeometryHint.fromJson(hint.toJson());
      expect(restored.kind, GeometryHintKind.polygon);
      expect(restored.points, hasLength(4));
    });

    test('boundingBox', () {
      final hint = const GeometryHint.boundingBox(minX: 0.1, minY: 0.2, maxX: 0.3, maxY: 0.4);
      final restored = GeometryHint.fromJson(hint.toJson());
      expect(restored.kind, GeometryHintKind.boundingBox);
      expect(restored.boundingBox!.minX, closeTo(0.1, 1e-9));
      expect(restored.boundingBox!.maxY, closeTo(0.4, 1e-9));
    });

    test('allPoints — kind와 무관하게 탐색용 점 목록을 만든다', () {
      expect(
        const GeometryHint.point(NormalizedPoint(0.5, 0.5)).allPoints,
        hasLength(1),
      );
      expect(
        const GeometryHint.segment(
          NormalizedPoint(0, 0),
          NormalizedPoint(1, 1),
        ).allPoints,
        hasLength(2),
      );
      expect(
        const GeometryHint.boundingBox(
          minX: 0,
          minY: 0,
          maxX: 1,
          maxY: 1,
        ).allPoints,
        hasLength(2),
      );
    });
  });

  group('Entity JSON 왕복', () {
    test('VisionFloorDomain', () {
      final entity = VisionFloorDomain(
        id: 'floor-1',
        confidence: VisionConfidence.medium,
        geometryHint: const GeometryHint.polygon([
          NormalizedPoint(0, 0),
          NormalizedPoint(1, 0),
          NormalizedPoint(1, 1),
          NormalizedPoint(0, 1),
        ]),
        notes: const ['approximate'],
      );
      final restored = VisionFloorDomain.fromJson(entity.toJson());
      expect(restored.id, 'floor-1');
      expect(restored.confidence, VisionConfidence.medium);
      expect(restored.source, VisionSource.vision);
      expect(restored.geometryHint!.points, hasLength(4));
      expect(restored.notes, ['approximate']);
    });

    test('VisionSpace', () {
      final entity = VisionSpace(
        id: 'space-1',
        confidence: VisionConfidence.high,
        geometryHint: const GeometryHint.boundingBox(minX: 0, minY: 0, maxX: 0.3, maxY: 0.3),
        label: '안방',
        semanticType: VisionSpaceSemanticType.bedroomMaster,
        adjacentSpaceIds: const ['space-2'],
      );
      final restored = VisionSpace.fromJson(entity.toJson());
      expect(restored.label, '안방');
      expect(restored.semanticType, VisionSpaceSemanticType.bedroomMaster);
      expect(restored.adjacentSpaceIds, ['space-2']);
      expect(restored.confidence, VisionConfidence.high);
    });

    test('VisionBoundary', () {
      final entity = VisionBoundary(
        id: 'b-1',
        confidence: VisionConfidence.low,
        geometryHint: const GeometryHint.segment(NormalizedPoint(0, 0), NormalizedPoint(1, 0)),
        boundaryType: VisionBoundaryType.interiorWall,
        adjacentSpaceIds: const ['space-1', 'space-2'],
      );
      final restored = VisionBoundary.fromJson(entity.toJson());
      expect(restored.boundaryType, VisionBoundaryType.interiorWall);
      expect(restored.adjacentSpaceIds, ['space-1', 'space-2']);
    });

    test('VisionOpening', () {
      final entity = VisionOpening(
        id: 'o-1',
        confidence: VisionConfidence.medium,
        geometryHint: const GeometryHint.point(NormalizedPoint(0.5, 0.5)),
        openingType: VisionOpeningType.door,
        attachedBoundaryId: 'b-1',
        connectedSpaceIds: const ['space-1', 'space-2'],
      );
      final restored = VisionOpening.fromJson(entity.toJson());
      expect(restored.openingType, VisionOpeningType.door);
      expect(restored.attachedBoundaryId, 'b-1');
      expect(restored.connectedSpaceIds, ['space-1', 'space-2']);
    });

    test('VisionObject — UNKNOWN confidence까지 왕복', () {
      final entity = VisionObject(
        id: 'obj-1',
        confidence: VisionConfidence.unknown,
        geometryHint: const GeometryHint.boundingBox(minX: 0, minY: 0, maxX: 0.1, maxY: 0.1),
        objectType: VisionObjectType.bathtub,
        containingSpaceId: 'space-3',
      );
      final restored = VisionObject.fromJson(entity.toJson());
      expect(restored.confidence, VisionConfidence.unknown);
      expect(restored.objectType, VisionObjectType.bathtub);
      expect(restored.containingSpaceId, 'space-3');
    });

    test('VisionStructuralElement', () {
      final entity = VisionStructuralElement(
        id: 's-1',
        confidence: VisionConfidence.low,
        geometryHint: const GeometryHint.boundingBox(minX: 0, minY: 0, maxX: 0.1, maxY: 0.1),
        structuralType: VisionStructuralType.stair,
      );
      final restored = VisionStructuralElement.fromJson(entity.toJson());
      expect(restored.structuralType, VisionStructuralType.stair);
    });

    test('VisionDimension — parsedValueMm이 null이면 null로 왕복(임의 생성 금지)', () {
      final entity = VisionDimension(
        id: 'd-1',
        confidence: VisionConfidence.low,
        geometryHint: null,
        rawText: '2,400',
      );
      final restored = VisionDimension.fromJson(entity.toJson());
      expect(restored.rawText, '2,400');
      expect(restored.parsedValueMm, isNull);
      expect(restored.geometryHint, isNull);
    });
  });

  group('VisionUnderstanding 전체 왕복', () {
    test('모든 entity 목록이 보존된다', () {
      final understanding = VisionUnderstanding(
        floorDomain: VisionFloorDomain(
          id: 'floor-1',
          confidence: VisionConfidence.medium,
          geometryHint: const GeometryHint.polygon([
            NormalizedPoint(0, 0),
            NormalizedPoint(1, 0),
            NormalizedPoint(1, 1),
            NormalizedPoint(0, 1),
          ]),
        ),
        spaces: [
          VisionSpace(
            id: 'space-1',
            confidence: VisionConfidence.high,
            geometryHint: const GeometryHint.boundingBox(minX: 0, minY: 0, maxX: 0.5, maxY: 0.5),
            label: '거실',
          ),
        ],
        boundaries: [
          VisionBoundary(
            id: 'b-1',
            confidence: VisionConfidence.high,
            geometryHint: const GeometryHint.segment(
              NormalizedPoint(0.5, 0),
              NormalizedPoint(0.5, 1),
            ),
            boundaryType: VisionBoundaryType.interiorWall,
          ),
        ],
        openings: const [],
        objects: [
          VisionObject(
            id: 'obj-1',
            confidence: VisionConfidence.medium,
            geometryHint: const GeometryHint.boundingBox(minX: 0.1, minY: 0.1, maxX: 0.2, maxY: 0.2),
            objectType: VisionObjectType.sofa,
          ),
        ],
        structuralElements: const [],
        dimensions: const [],
        scaleConfirmed: false,
        notes: const ['no printed dimensions in this drawing'],
      );

      final restored = VisionUnderstanding.fromJson(understanding.toJson());
      expect(restored.spaces, hasLength(1));
      expect(restored.boundaries, hasLength(1));
      expect(restored.objects, hasLength(1));
      expect(restored.scaleConfirmed, isFalse);
      expect(restored.notes, ['no printed dimensions in this drawing']);
    });
  });
}
