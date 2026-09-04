// SPACE SHIFT — PC1 CONTINUE: FLOOR DOMAIN FIRST + PHYSICAL ROOM / SEMANTIC
// ZONE SPLIT.
//
// 전체 조립 순서(§2 고정): false-positive cleanup → wall consolidation →
// exterior classification(모두 pixel_wall_extractor.dart 내부에서 이미
// 처리됨) → FLOOR DOMAIN closure(wall_system.dart) → PhysicalRoom 추출
// (extraction.rooms, 강제로 13개 만들지 않음) → SemanticZone 매칭
// (semantic_zone_mapper.dart) → SSSpatialModel(하위 호환/TopologyValidator
// 재사용) 조립.
//
// "13 semantic spaces = 13 closed physical polygons" 가정은 폐기했다
// (§1) — 벽 없이 이어진 영역은 여러 SemanticZone이 하나의 PhysicalRoom을
// 공유한다.

import 'dart:typed_data';

import '../../models/floor_plan_geometry.dart';
import '../../models/ss_spatial_model.dart';
import '../../services/topology_validator.dart';
import 'floor_domain_builder.dart';
import 'gpt_semantic_schema.dart';
import 'pixel_wall_classifier.dart';
import 'pixel_wall_extractor.dart';
import 'pixel_wall_types.dart';
import 'semantic_zone_mapper.dart';
import 'wall_system.dart';

class PixelWallPipelineResult {
  const PixelWallPipelineResult({
    required this.extraction,
    required this.model,
    required this.floorDomain,
    required this.spaceSemantics,
    required this.physicalRooms,
    required this.matchedPhysicalRoomCount,
    required this.semanticZoneCount,
    required this.unmatchedGptSpaceCount,
    required this.unmatchedPhysicalRoomCount,
    required this.wallSystems,
  });

  final PixelWallExtractionResult extraction;
  final SSSpatialModel model;
  final FloorDomainResult floorDomain;
  final List<SpaceSemantic> spaceSemantics;
  final List<PhysicalRoomInfo> physicalRooms;
  final int matchedPhysicalRoomCount;
  final int semanticZoneCount;
  final int unmatchedGptSpaceCount;
  final int unmatchedPhysicalRoomCount;
  final List<WallSystem> wallSystems;

  bool get floorDomainClosed => floorDomain.isValid;
  String? get floorDomainFailureReason => floorDomain.failureReason;
}

/// noiseCategory가 확실히 "벽이 아님"으로 분류된 candidate — CANONICAL
/// CAD/최종 SSWall 목록에서 제외한다(§3/§11). trueStructural/unknown은
/// 근거가 불확실할 뿐 배제하지 않는다(조용히 삭제 금지 원칙 유지).
bool _isConfirmedNonWall(PixelWallCandidate c) {
  return c.noiseCategory == PixelWallNoiseCategory.text ||
      c.noiseCategory == PixelWallNoiseCategory.furniture ||
      c.noiseCategory == PixelWallNoiseCategory.fixture ||
      c.noiseCategory == PixelWallNoiseCategory.doorArc ||
      c.noiseCategory == PixelWallNoiseCategory.windowDetail;
}

PixelWallPipelineResult runPixelWallPipeline({
  required Uint8List imageBytes,
  GptSemanticResponse? semantic,
}) {
  final extraction = extractPixelWalls(imageBytes);
  final w = extraction.analysisWidthPx;
  final h = extraction.analysisHeightPx;

  // --- §3 FALSE POSITIVE CLEANUP: 두께/길이만이 아니라 GPT 의미 ROI
  // (가구/애매 영역/문·창 힌트)까지 결합해 reviewNeeded 후보를 세분화.
  var classified = classifyNoiseCategories(candidates: extraction.candidates, semantic: semantic);
  classified = applyTextHeuristic(candidates: classified, analysisWidthPx: w, analysisHeightPx: h);

  // --- §6 FLOOR DOMAIN FIRST, PC2 PLANAR GRAPH INTEGRATION: 더 이상
  // 개별 candidate의 isExterior 태그로 endpoint-to-endpoint 체인을 걷지
  // 않는다(buildFloorDomain, 옛 chain walker — 자체 테스트 전용으로만
  // 격리되어 남아 있음). 대신 전체 구조 벽으로 PlanarGraph(T/L/X-junction
  // split + half-edge/DCEL face 추출 포함)를 만들고, 그 그래프가 스스로
  // 찾아낸 "바깥쪽 face"를 FloorDomain 경계로 쓴다(planar_wall_graph.dart
  // 근본 원칙과 동일). wallSystems는 결과 표시(PIXEL WALLS 탭 등)를 위해
  // 그대로 계산해 둔다.
  final wallSystems = buildWallSystems(candidates: classified, w: w, h: h);
  final floorDomain = buildFloorDomainFromPlanarGraph(candidates: classified, w: w, h: h);

  // --- §7/§8 PhysicalRoom 추출 + SemanticZone 매칭: pixel flood-fill이
  // 먼저이고 GPT는 라벨만 얹는다. 강제로 13개 폐합 polygon을 만들지
  // 않는다 — 열린 구조는 여러 라벨이 하나의 PhysicalRoom을 공유한다.
  final roomsForMapping = [
    for (final r in extraction.rooms) (id: r.id, polygon: r.polygon, areaNormalized: r.areaNormalized, confidence: r.confidence),
  ];
  final mapping = semantic == null
      ? ZoneMappingResult(
          spaces: const [],
          physicalRooms: [
            for (final r in roomsForMapping)
              PhysicalRoomInfo(id: r.id, polygon: r.polygon, areaNormalized: r.areaNormalized, confidence: r.confidence, claimedBySpaceIds: const []),
          ],
        )
      : mapSemanticZones(gptSpaces: semantic.spaces, rooms: roomsForMapping);

  final matchedPhysicalRoomCount = mapping.spaces.where((s) => s.kind == SpaceSemanticKind.physicalRoom).length;
  final semanticZoneCount = mapping.spaces.where((s) => s.kind == SpaceSemanticKind.semanticZone).length;
  final unmatchedGptSpaceCount = mapping.spaces.where((s) => s.polygon.isEmpty && s.kind == SpaceSemanticKind.semanticZone).length;
  final unmatchedPhysicalRoomCount = mapping.physicalRooms.where((r) => r.claimedBySpaceIds.isEmpty).length;

  // --- SSSpatialModel 조립(하위 호환 — TopologyValidator/기존 화면
  // 패턴 재사용). physicalRoom은 실제 닫힌 polygon, semanticZone은
  // "참고용" clip 영역(비어 있을 수 있음, reviewNeeded=true)으로 담는다.
  final spaces = <SSSpace>[
    for (final s in mapping.spaces)
      SSSpace(
        id: s.id,
        polygon: s.polygon,
        areaNormalized: 0,
        closed: s.kind == SpaceSemanticKind.physicalRoom,
        confidence: s.confidence,
        label: s.label,
        source: s.kind == SpaceSemanticKind.physicalRoom ? SSEntitySource.geometry : SSEntitySource.vision,
        reviewNeeded: s.reviewNeeded,
        reviewReasons: s.reviewReasons,
      ),
    for (final r in mapping.physicalRooms)
      if (r.claimedBySpaceIds.isEmpty)
        SSSpace(
          id: 'unknown-physical-room-${r.id}',
          polygon: r.polygon,
          areaNormalized: r.areaNormalized,
          closed: true,
          confidence: r.confidence,
          source: SSEntitySource.geometry,
          reviewNeeded: true,
          reviewReasons: const ['GPT 의미 지도의 어떤 공간과도 매칭되지 않은 PhysicalRoom(UNKNOWN PHYSICAL ROOM)'],
        ),
  ];

  final walls = <SSWall>[
    for (final c in classified)
      if (!_isConfirmedNonWall(c))
        SSWall(
          id: c.id,
          start: c.start,
          end: c.end,
          thicknessNormalized: c.thicknessNormalized,
          kind: c.isExterior ? SSWallKind.exterior : SSWallKind.interior,
          confidence: c.baseConfidence,
          source: SSEntitySource.geometry,
          reviewNeeded: c.category == PixelWallCategory.reviewNeeded,
          reviewReasons: c.category == PixelWallCategory.reviewNeeded
              ? ['짧고 junction 근거가 약한 pixel 후보(noise=${c.noiseCategory.name}) — 구조 벽 확정 보류']
              : const [],
        ),
  ];

  final openings = <SSOpening>[
    for (var i = 0; i < extraction.openings.length; i++)
      SSOpening(
        id: 'opening-$i',
        kind: extraction.openings[i].type == OpeningType.door
            ? SSOpeningKind.door
            : extraction.openings[i].type == OpeningType.window
            ? SSOpeningKind.window
            : SSOpeningKind.unknown,
        center: extraction.openings[i].center,
        widthNormalized: extraction.openings[i].widthNormalized,
        confidence: extraction.openings[i].confidence,
        wallId: extraction.openings[i].wallId,
        reviewNeeded: true,
        reviewReasons: const ['gap 기반 자동 추출 — 사람 확인 필요'],
      ),
  ];

  final rawModel = SSSpatialModel(
    sourceWidthPx: extraction.sourceWidthPx,
    sourceHeightPx: extraction.sourceHeightPx,
    spaces: spaces,
    walls: walls,
    openings: openings,
    objects: const [],
    warnings: floorDomain.isValid ? const [] : ['FloorDomain INVALID: ${floorDomain.failureReason}'],
    floorDomain: floorDomain.loop,
  );

  final validated = const TopologyValidator().validate(rawModel);

  return PixelWallPipelineResult(
    extraction: extraction.copyWithCandidates(classified),
    model: validated,
    floorDomain: floorDomain,
    spaceSemantics: mapping.spaces,
    physicalRooms: mapping.physicalRooms,
    matchedPhysicalRoomCount: matchedPhysicalRoomCount,
    semanticZoneCount: semanticZoneCount,
    unmatchedGptSpaceCount: unmatchedGptSpaceCount,
    unmatchedPhysicalRoomCount: unmatchedPhysicalRoomCount,
    wallSystems: wallSystems,
  );
}
