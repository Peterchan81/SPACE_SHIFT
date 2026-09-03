import 'dart:math' as math;
import 'dart:typed_data';

import '../models/cad_floor_plan.dart';
import '../models/floor_plan_geometry.dart';
import '../models/ss_spatial_model.dart';
import '../models/vision_understanding.dart';
import 'hinted_geometry_extractor.dart';
import 'topology_validator.dart';
import 'vision_geometry_matcher.dart';
import 'vision_interpretation_service.dart';

/// Vision Guided CAD POC — 전체 파이프라인 orchestrator(설계 7번).
///
/// Vision(무엇 + 대략 어디) → [HintedGeometryExtractor](정확히 어디) →
/// [VisionGeometryMatcher](5가지 경우 중 하나로 조정) → [TopologyValidator]
/// (건축적으로 말이 되는지 11가지 규칙 검증) → [SSSpatialModel](캐노니컬
/// 해석 결과) → [buildCadFloorPlanFromSpatialModel]([CadFloorPlan], 화면/
/// 향후 DXF/SVG/PDF/3D가 전부 공유하는 단 하나의 CAD geometry) 순서로
/// 그대로 이어붙인다. 이 파일 자체는 새 geometry 판단 로직을 갖지
/// 않는다 — 순수하게 앞 단계들을 올바른 순서로 연결하고, VisionSpace의
/// bounding-box hint 4변을 각각 실제 boundary 매칭과 동일한 방식으로
/// 정밀화해 방 폴리곤을 얻는다(Vision의 대략적인 사각형을 그대로 최종
/// 폴리곤으로 쓰지 않는다 — WO 절대 금지 3번).
class VisionGuidedSpatialModelBuilder {
  const VisionGuidedSpatialModelBuilder({
    required this.visionService,
    this.matcher = const VisionGeometryMatcher(),
    this.validator = const TopologyValidator(),
  });

  final VisionInterpretationService visionService;
  final VisionGeometryMatcher matcher;
  final TopologyValidator validator;

  Future<SSSpatialModel> build(Uint8List imageBytes) async {
    final vision = await visionService.interpret(imageBytes);
    final extractor = HintedGeometryExtractor(imageBytes);
    final warnings = <String>[...vision.notes];

    // 1) FloorDomain — Vision hint의 각 변을 실제 벽에 스냅한다.
    final floorDomain = _refineFloorDomain(extractor, vision.floorDomain, warnings);

    // 2) Boundaries → SSWall/SSBoundary.
    final boundaryById = <String, VisionBoundary>{for (final b in vision.boundaries) b.id: b};
    final walls = <SSWall>[];
    final boundaries = <SSBoundary>[];
    final refinedSegmentByBoundaryId = <String, ({Point2 start, Point2 end})>{};

    for (final boundary in vision.boundaries) {
      final hint = boundary.geometryHint;
      if (hint == null || hint.kind != GeometryHintKind.segment) {
        warnings.add('boundary ${boundary.id} has no usable segment hint — skipped');
        continue;
      }
      final candidate = extractor.refineBoundary(hint.start, hint.end);
      final match = matcher.matchBoundary(boundary: boundary, geometryResult: candidate);

      final segment = match.finalGeometryHint?.allPoints ?? hint.allPoints;
      final start = Point2(segment.first.x, segment.first.y);
      final end = Point2(segment.last.x, segment.last.y);
      refinedSegmentByBoundaryId[boundary.id] = (start: start, end: end);

      if (!match.included) {
        warnings.add(
          'boundary ${boundary.id} excluded from CAD (${match.matchCase.name}): '
          '${match.reviewReasons.join('; ')}',
        );
        continue;
      }

      walls.add(
        SSWall(
          id: 'wall-${boundary.id}',
          start: start,
          end: end,
          thicknessNormalized: 0.01,
          kind: boundary.boundaryType == VisionBoundaryType.exteriorWall
              ? SSWallKind.exterior
              : SSWallKind.interior,
          confidence: _confidenceToDouble(match.confidence),
          source: _toEntitySource(match.source),
          reviewNeeded: match.reviewNeeded,
          reviewReasons: match.reviewReasons,
        ),
      );
      boundaries.add(
        SSBoundary(
          id: boundary.id,
          spaceId: '',
          start: start,
          end: end,
          type: boundary.boundaryType == VisionBoundaryType.exteriorWall
              ? SSBoundaryType.wall
              : SSBoundaryType.wall,
          confidence: _confidenceToDouble(match.confidence),
          isExterior: boundary.boundaryType == VisionBoundaryType.exteriorWall,
          wallId: 'wall-${boundary.id}',
          source: _toEntitySource(match.source),
          reviewNeeded: match.reviewNeeded,
          reviewReasons: match.reviewReasons,
        ),
      );
    }

    // 3) Openings — 반드시 host boundary가 먼저 정밀화되어 있어야 gap을
    // 찾을 수 있다.
    final openings = <SSOpening>[];
    for (final opening in vision.openings) {
      final hint = opening.geometryHint;
      final hostId = opening.attachedBoundaryId;
      final host = hostId == null ? null : boundaryById[hostId];
      final hostSegment = hostId == null ? null : refinedSegmentByBoundaryId[hostId];
      if (hint == null || host == null || hostSegment == null) {
        warnings.add('opening ${opening.id} has no usable host boundary — skipped');
        continue;
      }

      final openingHint = hint.kind == GeometryHintKind.point ? hint.point : hint.allPoints.first;
      final geometryResult = extractor.refineOpening(
        boundaryStart: NormalizedPoint(hostSegment.start.x, hostSegment.start.y),
        boundaryEnd: NormalizedPoint(hostSegment.end.x, hostSegment.end.y),
        openingHint: openingHint,
      );
      final match = matcher.matchOpening(opening: opening, geometryResult: geometryResult);

      if (!match.included) {
        warnings.add(
          'opening ${opening.id} excluded from CAD (${match.matchCase.name}): '
          '${match.reviewReasons.join('; ')}',
        );
        continue;
      }

      final center = match.finalGeometryHint?.point ?? openingHint;
      openings.add(
        SSOpening(
          id: opening.id,
          kind: switch (opening.openingType) {
            VisionOpeningType.door => SSOpeningKind.door,
            VisionOpeningType.window => SSOpeningKind.window,
            VisionOpeningType.openPassage => SSOpeningKind.openPassage,
          },
          center: Point2(center.x, center.y),
          widthNormalized: geometryResult.widthNormalized ?? 0.01,
          confidence: _confidenceToDouble(match.confidence),
          wallId: 'wall-$hostId',
          connectsSpaceIds: opening.connectedSpaceIds,
          source: _toEntitySource(match.source),
          reviewNeeded: match.reviewNeeded,
          reviewReasons: match.reviewReasons,
        ),
      );
    }

    // 4) Objects — 존재 여부만 확인한다(정밀 외곽선 재구성 없음).
    final objects = <SSObjectCandidate>[];
    for (final object in vision.objects) {
      final hint = object.geometryHint;
      if (hint == null || hint.boundingBox == null) {
        warnings.add('object ${object.id} has no usable bounding box hint — skipped');
        continue;
      }
      final box = hint.boundingBox!;
      final hasStructure = extractor.regionHasStructure((
        minX: box.minX,
        minY: box.minY,
        maxX: box.maxX,
        maxY: box.maxY,
      ));
      final match = matcher.matchObject(object: object, hasStructure: hasStructure);
      if (!match.included) {
        warnings.add(
          'object ${object.id} excluded from CAD (${match.matchCase.name}): '
          '${match.reviewReasons.join('; ')}',
        );
        continue;
      }
      objects.add(
        SSObjectCandidate(
          id: 'object-${object.id}',
          polygon: [
            Point2(box.minX, box.minY),
            Point2(box.maxX, box.minY),
            Point2(box.maxX, box.maxY),
            Point2(box.minX, box.maxY),
          ],
          kind: switch (object.objectType) {
            VisionObjectType.bed => SSObjectKind.bed,
            VisionObjectType.sofa => SSObjectKind.sofa,
            VisionObjectType.cabinet => SSObjectKind.cabinet,
            VisionObjectType.sink => SSObjectKind.sink,
            VisionObjectType.toilet => SSObjectKind.toilet,
            VisionObjectType.bathtub => SSObjectKind.bathtub,
            VisionObjectType.equipment => SSObjectKind.equipment,
            VisionObjectType.unknown => SSObjectKind.unknown,
          },
          source: _toEntitySource(match.source),
          reviewNeeded: match.reviewNeeded,
          reviewReasons: match.reviewReasons,
        ),
      );
    }

    // 5) Spaces — Vision의 bounding box hint 4변을 boundary와 동일한
    // 방식으로 정밀화해 방 폴리곤을 얻는다(Vision 사각형을 그대로 쓰지
    // 않는다).
    final spaces = <SSSpace>[];
    for (final space in vision.spaces) {
      final hint = space.geometryHint;
      if (hint == null || hint.boundingBox == null) {
        warnings.add('space ${space.id} has no usable bounding box hint — skipped');
        continue;
      }
      final built = _refineSpaceRectangle(extractor, hint.boundingBox!, space, warnings);
      if (built != null) spaces.add(built);
    }

    final model = SSSpatialModel(
      sourceWidthPx: extractor.width,
      sourceHeightPx: extractor.height,
      spaces: spaces,
      walls: walls,
      openings: openings,
      objects: objects,
      warnings: warnings,
      boundaries: boundaries,
      floorDomain: floorDomain,
    );

    return validator.validate(model);
  }

  Future<CadFloorPlan> buildCad(Uint8List imageBytes) async {
    final model = await build(imageBytes);
    return buildCadFloorPlanFromSpatialModel(model);
  }

  List<Point2>? _refineFloorDomain(
    HintedGeometryExtractor extractor,
    VisionFloorDomain floorDomain,
    List<String> warnings,
  ) {
    final hint = floorDomain.geometryHint;
    if (hint == null || hint.kind != GeometryHintKind.polygon || hint.points.length < 3) {
      warnings.add('floor domain has no usable polygon hint');
      return null;
    }
    final refinedPoints = <Point2>[];
    for (var i = 0; i < hint.points.length; i++) {
      final start = hint.points[i];
      final end = hint.points[(i + 1) % hint.points.length];
      final candidate = extractor.refineBoundary(start, end);
      if (candidate == null) {
        refinedPoints.add(Point2(start.x, start.y));
        continue;
      }
      // refineBoundary는 along 좌표 기준으로 정렬된 두 점을 돌려준다 —
      // hint의 원래 방향(start→end)과 같은 순서라는 보장이 없다. 두 점
      // 중 원래 vertex(hint.points[i])에 더 가까운 쪽을 그 vertex의
      // 정밀화된 위치로 선택해야, 인접 변끼리 서로 다른 쪽 끝을 골라
      // 폴리곤이 뒤틀리는(자기교차) 문제를 피한다.
      final points = candidate.geometry.allPoints;
      final first = points.first;
      final last = points.last;
      final distToFirst = math.pow(first.x - start.x, 2) + math.pow(first.y - start.y, 2);
      final distToLast = math.pow(last.x - start.x, 2) + math.pow(last.y - start.y, 2);
      final chosen = distToFirst <= distToLast ? first : last;
      refinedPoints.add(Point2(chosen.x, chosen.y));
    }
    return refinedPoints;
  }

  SSSpace? _refineSpaceRectangle(
    HintedGeometryExtractor extractor,
    ({double minX, double minY, double maxX, double maxY}) box,
    VisionSpace space,
    List<String> warnings,
  ) {
    final top = extractor.refineBoundary(
      NormalizedPoint(box.minX, box.minY),
      NormalizedPoint(box.maxX, box.minY),
    );
    final bottom = extractor.refineBoundary(
      NormalizedPoint(box.minX, box.maxY),
      NormalizedPoint(box.maxX, box.maxY),
    );
    final left = extractor.refineBoundary(
      NormalizedPoint(box.minX, box.minY),
      NormalizedPoint(box.minX, box.maxY),
    );
    final right = extractor.refineBoundary(
      NormalizedPoint(box.maxX, box.minY),
      NormalizedPoint(box.maxX, box.maxY),
    );

    final edges = [top, bottom, left, right];
    final foundCount = edges.where((e) => e != null).length;

    final minY = top?.geometry.allPoints.first.y ?? box.minY;
    final maxY = bottom?.geometry.allPoints.first.y ?? box.maxY;
    final minX = left?.geometry.allPoints.first.x ?? box.minX;
    final maxX = right?.geometry.allPoints.first.x ?? box.maxX;

    if (maxX <= minX || maxY <= minY) {
      warnings.add('space ${space.id} could not be resolved to a valid rectangle — skipped');
      return null;
    }

    final polygon = [
      Point2(minX, minY),
      Point2(maxX, minY),
      Point2(maxX, maxY),
      Point2(minX, maxY),
    ];
    final area = (maxX - minX) * (maxY - minY);

    final reviewNeeded = foundCount < 3 || space.confidence == VisionConfidence.low;
    final reasons = <String>[
      if (foundCount < 3)
        'only $foundCount/4 edges could be confirmed against real wall pixels — '
            'unconfirmed edge(s) fall back to the (imprecise) vision hint',
      if (space.confidence == VisionConfidence.low)
        'vision confidence for this space label was low',
    ];

    return SSSpace(
      id: space.id,
      polygon: polygon,
      areaNormalized: area,
      closed: true,
      confidence: foundCount / 4,
      label: space.label,
      spaceConfidence: foundCount >= 4
          ? SSSpaceConfidence.high
          : foundCount >= 3
          ? SSSpaceConfidence.medium
          : SSSpaceConfidence.low,
      source: foundCount >= 3 ? SSEntitySource.validated : SSEntitySource.vision,
      reviewNeeded: reviewNeeded,
      reviewReasons: reasons,
    );
  }

  double _confidenceToDouble(VisionConfidence c) => switch (c) {
    VisionConfidence.high => 1.0,
    VisionConfidence.medium => 0.7,
    VisionConfidence.low => 0.4,
    VisionConfidence.unknown => 0.0,
  };

  SSEntitySource _toEntitySource(VisionSource s) => switch (s) {
    VisionSource.vision => SSEntitySource.vision,
    VisionSource.geometry => SSEntitySource.geometry,
    VisionSource.ocr => SSEntitySource.ocr,
    VisionSource.user => SSEntitySource.user,
    VisionSource.validated => SSEntitySource.validated,
  };
}
