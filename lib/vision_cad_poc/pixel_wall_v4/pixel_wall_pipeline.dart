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
import 'semantic_provider.dart';
import 'semantic_zone_mapper.dart';
import 'wall_opening.dart';
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
    required this.openingValidation,
    this.semanticStatus = SemanticProviderStatus.unavailable,
    this.semanticReason,
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

  /// WO087 §16 — 이 결과가 실제 semantic evidence로 만들어졌는지(SUCCESS),
  /// 아니면 semantic 없이 geometry만으로 만들어졌는지(UNAVAILABLE).
  /// [runPixelWallPipeline]을 semantic 없이 직접 호출하는 기존 호출부는
  /// 전부 기본값 unavailable로 정직하게 표시된다.
  final SemanticProviderStatus semanticStatus;
  final String? semanticReason;

  /// DOOR/WINDOW → PARENT WALL + PARAMETRIC OPENING WO — 최종 승인된/
  /// 거부된 opening 전체(§13/§20 보고용).
  final OpeningValidationResult openingValidation;

  bool get floorDomainClosed => floorDomain.isValid;
  String? get floorDomainFailureReason => floorDomain.failureReason;

  int get doorOpeningCount => openingValidation.valid.where((o) => o.kind == OpeningKind.door).length;
  int get windowOpeningCount => openingValidation.valid.where((o) => o.kind == OpeningKind.window).length;
  int get unknownOpeningCount => openingValidation.valid.where((o) => o.kind == OpeningKind.unknownOpening).length;

  /// doorOpening 크기가 아니었던(imageBreak만으로 남은) gap 개수 —
  /// Opening으로 만들어지지 않고 그대로 진단 정보로만 남는다(§7).
  int get imageBreakOnlyGapCount =>
      wallSystems.fold(0, (sum, s) => sum + s.gaps.where((g) => g.kind == GapKind.imageBreak).length);
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

double systemAlongPxOf(PixelWallCandidate c, PixelWallOrientation o, int w, int h) =>
    o == PixelWallOrientation.horizontal ? ((c.start.x + c.end.x) / 2) * w : ((c.start.y + c.end.y) / 2) * h;

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

  // --- DOOR/WINDOW → PARENT WALL + PARAMETRIC OPENING: WallSystem 자체가
  // 이미 "문/창이 있어도 끊기지 않는 연속 구조 벽"(parent WallEdge)이다
  // (§1/§2) — SSWallEdge로 그대로 정규화 좌표에 옮긴다. 물리 벽 조각
  // ([walls], 위)은 그대로 유지하고 별개로 둔다.
  Point2 systemPoint(WallSystem s, double alongPx) => s.orientation == PixelWallOrientation.horizontal
      ? Point2(alongPx / w, s.axisPx / h)
      : Point2(s.axisPx / w, alongPx / h);

  final wallEdges = <SSWallEdge>[
    for (final s in wallSystems)
      SSWallEdge(
        id: s.id,
        start: systemPoint(s, s.startAlongPx),
        end: systemPoint(s, s.endAlongPx),
        thicknessNormalized: s.thicknessPx / (s.orientation == PixelWallOrientation.horizontal ? h : w),
        kind: s.isExterior ? SSWallKind.exterior : SSWallKind.interior,
        confidence: s.segments.fold<double>(0, (sum, c) => sum + c.baseConfidence) / s.segments.length,
        physicalWallIds: [for (final c in s.segments) c.id],
        // EVIDENCE/PROVENANCE — segment가 1개면 직접 관측된 pixel evidence
        // 그대로다(geometry). 2개 이상이면 문/창 gap을 건너 위상적으로
        // "같은 벽"이라고 판단한 것이지, 그 구간 전체가 직접 관측된 것은
        // 아니다(inferredTopology) — 추론값을 관측값처럼 저장하지 않는다.
        source: s.segments.length > 1 ? SSEntitySource.inferredTopology : SSEntitySource.geometry,
      ),
  ];

  // doorOpening 크기 gap만 후보로 삼고(§6/§7 — imageBreak/openPlan/
  // notConnected는 절대 Opening이 되지 않는다), GPT doorArc/windowDetail
  // 근거가 실제로 겹치면 종류를 확정한다(§5 순수 최단거리 매칭 금지 —
  // matchParentWallSystem이 collinearity+extent로만 판정).
  final wallOpenings = buildWallOpenings(wallSystems: wallSystems, allCandidates: classified, w: w, h: h);
  final openingValidation = validateOpenings(
    openings: wallOpenings,
    validParentWallIds: {for (final s in wallSystems) s.id},
  );

  final openings = <SSOpening>[
    for (final o in openingValidation.valid)
      () {
        final system = wallSystems.firstWhere((s) => s.id == o.parentWallId);
        final centerAlongPx = system.startAlongPx + (o.startT + o.endT) / 2 * system.lengthPx;
        final widthPx = (o.endT - o.startT) * system.lengthPx;
        // 이 opening과 가장 가까운 물리 SSWall segment(하위 호환 wallId).
        final nearestSegment = system.segments.reduce(
          (a, b) => (systemAlongPxOf(a, system.orientation, w, h) - centerAlongPx).abs() <
                  (systemAlongPxOf(b, system.orientation, w, h) - centerAlongPx).abs()
              ? a
              : b,
        );
        return SSOpening(
          id: o.id,
          kind: switch (o.kind) {
            OpeningKind.door => SSOpeningKind.door,
            OpeningKind.window => SSOpeningKind.window,
            OpeningKind.unknownOpening => SSOpeningKind.unknown,
          },
          center: systemPoint(system, centerAlongPx),
          widthNormalized: widthPx / (system.orientation == PixelWallOrientation.horizontal ? w : h),
          confidence: o.confidence,
          wallId: nearestSegment.id,
          parentWallId: o.parentWallId,
          startT: o.startT,
          endT: o.endT,
          // EVIDENCE/PROVENANCE — GPT doorArc/windowDetail로 실제 확인된
          // 것만 vision(semantic AI evidence)이다. pixel gap 크기만으로
          // "여기 opening이 있을 것"이라 판단한 것은 직접 관측이 아니라
          // topology 추론이므로 inferredTopology로 정직하게 남긴다.
          source: o.source == OpeningEvidenceSource.semanticAi ? SSEntitySource.vision : SSEntitySource.inferredTopology,
          reviewNeeded: o.reviewNeeded,
          reviewReasons: o.reviewNeeded ? ['pixel gap 근거만 있음 — 문/창 종류 확정을 위한 사람 확인 필요'] : const [],
        );
      }(),
  ];

  final rejectedOpeningWarnings = [
    for (final r in openingValidation.rejected) 'Opening 거부: ${r.reason}(id=${r.opening.id})',
  ];

  final rawModel = SSSpatialModel(
    sourceWidthPx: extraction.sourceWidthPx,
    sourceHeightPx: extraction.sourceHeightPx,
    spaces: spaces,
    walls: walls,
    openings: openings,
    objects: const [],
    warnings: [
      // WO086 §9 — 사용자용 채널에는 기술 메시지 그대로가 아니라
      // TopologyDiagnostics.userMessage(정확한 원인은
      // floorDomain.failureReason/topology로 별도 노출된다, §9 사용자용
      // vs 전문가용 분리).
      if (!floorDomain.isValid) floorDomain.topology?.userMessage ?? 'FloorDomain INVALID: ${floorDomain.failureReason}',
      ...rejectedOpeningWarnings,
    ],
    floorDomain: floorDomain.loop,
    wallEdges: wallEdges,
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
    openingValidation: openingValidation,
    semanticStatus: semantic != null ? SemanticProviderStatus.success : SemanticProviderStatus.unavailable,
    semanticReason: semantic == null ? 'semantic 인자 없이 호출됨(geometry-only)' : null,
  );
}

/// WO087 §15 PRODUCTION WIRING — [SemanticProvider] 하나로 semantic
/// evidence를 구해([provider]가 fixture든, 나중에 실제 live 호출이든)
/// 그대로 [runPixelWallPipeline](변경 없음)에 넘긴다. provider가
/// unavailable을 반환해도(§16 "죽으면 안 된다") geometry-only로 안전하게
/// 계속 진행한다 — 절대 예외를 던지지 않는다.
Future<PixelWallPipelineResult> runPixelWallPipelineWithSemanticProvider({
  required Uint8List imageBytes,
  required SemanticProvider provider,
}) async {
  final semanticResult = await provider.fetch(imageBytes);
  final result = runPixelWallPipeline(imageBytes: imageBytes, semantic: semanticResult.response);
  if (semanticResult.status != SemanticProviderStatus.unavailable) return result;
  // provider가 명시적으로 unavailable을 반환한 경우, semanticReason을
  // "semantic 인자 없이 호출됨"이라는 일반 메시지 대신 provider가 실제로
  // 준 이유로 교체한다 — 왜 semantic이 없는지(fixture 없음/live 미구현
  // 등) 더 정확하게 남긴다.
  return PixelWallPipelineResult(
    extraction: result.extraction,
    model: result.model,
    floorDomain: result.floorDomain,
    spaceSemantics: result.spaceSemantics,
    physicalRooms: result.physicalRooms,
    matchedPhysicalRoomCount: result.matchedPhysicalRoomCount,
    semanticZoneCount: result.semanticZoneCount,
    unmatchedGptSpaceCount: result.unmatchedGptSpaceCount,
    unmatchedPhysicalRoomCount: result.unmatchedPhysicalRoomCount,
    wallSystems: result.wallSystems,
    openingValidation: result.openingValidation,
    semanticStatus: SemanticProviderStatus.unavailable,
    semanticReason: semanticResult.reason,
  );
}
