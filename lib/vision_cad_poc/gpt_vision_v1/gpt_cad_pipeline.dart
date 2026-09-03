import 'dart:convert';
import 'dart:typed_data';

import '../../models/floor_plan_geometry.dart';
import '../../models/ss_spatial_model.dart';
import '../../services/topology_validator.dart';
import 'gpt_cad_json_validator.dart';
import 'gpt_cad_schema.dart';
import 'gpt_local_refinement.dart';
import 'gpt_vision_api_service.dart';
import 'gpt_wall_topology_solver.dart';

/// SPACE SHIFT — Real GPT Vision → Detailed CAD JSON → SS Refinement POC.
///
/// 전체 파이프라인을 하나로 잇는다: API 호출 → JSON 파싱/검증 → 실제
/// 픽셀 local refinement → wall topology → Space 유도 →
/// [SSSpatialModel](기존 모델 재사용) → [TopologyValidator](기존, 재사용).
/// 실패는 종류별로 분리해서 보고한다(설계 23번) — 같은 detector를
/// 무한 반복 수정하지 않기 위함이다.
enum GptPipelineFailureKind { none, authRequired, jsonParseError, validationError }

class GptPipelineResult {
  const GptPipelineResult({
    required this.failureKind,
    this.failureMessage,
    this.proposal,
    this.refinement,
    this.model,
  });

  final GptPipelineFailureKind failureKind;
  final String? failureMessage;
  final GptCadProposal? proposal;
  final GptLocalRefinementResult? refinement;
  final SSSpatialModel? model;

  bool get succeeded => failureKind == GptPipelineFailureKind.none && model != null;
}

class GptCadPipeline {
  const GptCadPipeline({
    required this.apiService,
    this.jsonValidator = const GptCadJsonValidator(),
    this.refinementStep = const GptLocalRefinement(),
    this.wallTopologySolver = const GptWallTopologySolver(),
    this.topologyValidator = const TopologyValidator(),
  });

  final GptVisionApiService apiService;
  final GptCadJsonValidator jsonValidator;
  final GptLocalRefinement refinementStep;
  final GptWallTopologySolver wallTopologySolver;
  final TopologyValidator topologyValidator;

  Future<GptPipelineResult> run(Uint8List imageBytes) async {
    String raw;
    try {
      raw = await apiService.requestCadJson(imageBytes);
    } on GptVisionAuthRequiredException catch (e) {
      return GptPipelineResult(failureKind: GptPipelineFailureKind.authRequired, failureMessage: e.message);
    }

    return runWithRawJson(raw, imageBytes);
  }

  /// API 호출 없이, 이미 받은 raw JSON 문자열로 나머지 파이프라인만
  /// 실행한다 — 수동으로 붙여넣은 테스트 JSON을 파서/솔버에 통과시켜
  /// 볼 때 쓴다(§21의 debug view와 동일한 목적, 실제 API 호출이 아님을
  /// 항상 명확히 구분해야 한다).
  GptPipelineResult runWithRawJson(String raw, Uint8List imageBytes) {
    GptCadProposal proposal;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('top-level JSON must be an object');
      }
      proposal = GptCadProposal.fromJson(decoded);
    } catch (e) {
      return GptPipelineResult(failureKind: GptPipelineFailureKind.jsonParseError, failureMessage: e.toString());
    }

    try {
      jsonValidator.validate(proposal);
    } on GptCadValidationException catch (e) {
      return GptPipelineResult(
        failureKind: GptPipelineFailureKind.validationError,
        failureMessage: e.toString(),
        proposal: proposal,
      );
    }

    final refinement = refinementStep.refine(proposal, imageBytes);
    final model = _buildModel(proposal, refinement);
    final validated = topologyValidator.validate(model);

    return GptPipelineResult(
      failureKind: GptPipelineFailureKind.none,
      proposal: proposal,
      refinement: refinement,
      model: validated,
    );
  }

  SSSpatialModel _buildModel(GptCadProposal proposal, GptLocalRefinementResult refinement) {
    final cornersById = {for (final c in proposal.corners) c.id: c};
    final warnings = <String>[...proposal.reviewReasons];

    Point2 cornerPoint(String id) {
      final refined = refinement.refinedCornerPositions[id];
      if (refined != null) return Point2(refined.x, refined.y);
      final c = cornersById[id]!;
      return Point2(c.x / proposal.image.widthPx, c.y / proposal.image.heightPx);
    }

    final walls = <SSWall>[];
    final boundaries = <SSBoundary>[];
    for (final wall in proposal.walls) {
      for (var i = 0; i < wall.cornerIds.length - 1; i++) {
        final segId = wall.cornerIds.length == 2 ? wall.id : '${wall.id}-seg$i';
        final start = cornerPoint(wall.cornerIds[i]);
        final end = cornerPoint(wall.cornerIds[i + 1]);
        final seg = refinement.segments.where((s) => s.wallId == wall.id && s.segmentIndex == i).firstOrNull;
        final reviewNeeded = seg == null || !seg.found || wall.confidence < 0.5;
        final reasons = <String>[
          if (seg == null || !seg.found) 'no pixel evidence found near this wall segment',
          if (wall.confidence < 0.5) 'GPT vision confidence was low (${wall.confidence.toStringAsFixed(2)})',
        ];
        walls.add(SSWall(
          id: segId,
          start: start,
          end: end,
          thicknessNormalized: (wall.thicknessPxHint ?? 8) / proposal.image.widthPx,
          kind: wall.type == GptWallType.exterior ? SSWallKind.exterior : SSWallKind.interior,
          confidence: wall.confidence,
          source: SSEntitySource.vision,
          reviewNeeded: reviewNeeded,
          reviewReasons: reasons,
        ));
        boundaries.add(SSBoundary(
          id: segId,
          spaceId: '',
          start: start,
          end: end,
          type: SSBoundaryType.wall,
          confidence: wall.confidence,
          isExterior: wall.type == GptWallType.exterior,
          wallId: segId,
          source: SSEntitySource.vision,
          reviewNeeded: reviewNeeded,
          reviewReasons: reasons,
        ));
      }
    }

    final spaces = <SSSpace>[];
    for (final space in proposal.spaces) {
      final loop = wallTopologySolver.deriveSpaceLoop(space, proposal.walls);
      List<Point2> polygon;
      var reviewNeeded = space.confidence < 0.5;
      final reasons = <String>[...space.reviewReasons];
      if (loop.closed) {
        polygon = loop.orderedCornerIds.map(cornerPoint).toList();
      } else {
        // 설계 10번: 유도에 실패해도 space를 지우지 않는다 — 참조된
        // corner들의 bounding box로 저확신 상태를 유지한 채 보존한다.
        reviewNeeded = true;
        reasons.add('wall topology could not derive a closed loop: ${loop.failureReason}');
        final refCorners = <Point2>[];
        for (final wallId in space.boundaryWallIds) {
          final wall = proposal.walls.where((w) => w.id == wallId).firstOrNull;
          if (wall == null) continue;
          for (final cid in wall.cornerIds) {
            if (cornersById.containsKey(cid)) refCorners.add(cornerPoint(cid));
          }
        }
        if (refCorners.isEmpty) {
          warnings.add('space "${space.id}" could not be resolved to any geometry — excluded');
          continue;
        }
        final minX = refCorners.map((p) => p.x).reduce((a, b) => a < b ? a : b);
        final maxX = refCorners.map((p) => p.x).reduce((a, b) => a > b ? a : b);
        final minY = refCorners.map((p) => p.y).reduce((a, b) => a < b ? a : b);
        final maxY = refCorners.map((p) => p.y).reduce((a, b) => a > b ? a : b);
        polygon = [Point2(minX, minY), Point2(maxX, minY), Point2(maxX, maxY), Point2(minX, maxY)];
      }
      if (reviewNeeded && space.confidence < 0.5) {
        reasons.add('GPT vision confidence was low (${space.confidence.toStringAsFixed(2)})');
      }
      final area = _polygonArea(polygon);
      spaces.add(SSSpace(
        id: space.id,
        polygon: polygon,
        areaNormalized: area,
        closed: loop.closed,
        confidence: space.confidence,
        spaceConfidence: space.confidence >= 0.8
            ? SSSpaceConfidence.high
            : space.confidence >= 0.5
                ? SSSpaceConfidence.medium
                : SSSpaceConfidence.low,
        label: space.label,
        source: SSEntitySource.vision,
        reviewNeeded: reviewNeeded,
        reviewReasons: reasons,
      ));
    }

    Point2 pointOnWall(String wallId, double t) {
      final wall = proposal.walls.firstWhere((w) => w.id == wallId);
      final segCount = wall.cornerIds.length - 1;
      final scaledT = (t * segCount).clamp(0, segCount.toDouble());
      final segIndex = scaledT.floor().clamp(0, segCount - 1);
      final localT = scaledT - segIndex;
      final start = cornerPoint(wall.cornerIds[segIndex]);
      final end = cornerPoint(wall.cornerIds[segIndex + 1]);
      return Point2(start.x + (end.x - start.x) * localT, start.y + (end.y - start.y) * localT);
    }

    final openings = <SSOpening>[];
    for (final door in proposal.doors) {
      final center = pointOnWall(door.hostWallId, (door.startT + door.endT) / 2);
      openings.add(SSOpening(
        id: door.id,
        kind: SSOpeningKind.door,
        center: center,
        widthNormalized: (door.endT - door.startT).abs(),
        confidence: door.confidence,
        wallId: door.hostWallId,
        connectsSpaceIds: door.connectsSpaceIds,
        source: SSEntitySource.vision,
        reviewNeeded: door.confidence < 0.5,
        reviewReasons: door.confidence < 0.5 ? ['GPT vision confidence was low'] : const [],
      ));
    }
    for (final win in proposal.windows) {
      final center = pointOnWall(win.hostWallId, (win.startT + win.endT) / 2);
      openings.add(SSOpening(
        id: win.id,
        kind: SSOpeningKind.window,
        center: center,
        widthNormalized: (win.endT - win.startT).abs(),
        confidence: win.confidence,
        wallId: win.hostWallId,
        source: SSEntitySource.vision,
        reviewNeeded: win.confidence < 0.5,
        reviewReasons: win.confidence < 0.5 ? ['GPT vision confidence was low'] : const [],
      ));
    }
    for (final o in proposal.openings) {
      final center = pointOnWall(o.hostWallId, (o.startT + o.endT) / 2);
      openings.add(SSOpening(
        id: o.id,
        kind: SSOpeningKind.openPassage,
        center: center,
        widthNormalized: (o.endT - o.startT).abs(),
        confidence: o.confidence,
        wallId: o.hostWallId,
        connectsSpaceIds: o.connectsSpaceIds,
        source: SSEntitySource.vision,
        reviewNeeded: o.confidence < 0.5,
        reviewReasons: o.confidence < 0.5 ? ['GPT vision confidence was low'] : const [],
      ));
    }

    final objects = <SSObjectCandidate>[];
    for (final obj in proposal.objects) {
      final box = obj.bboxPx;
      objects.add(SSObjectCandidate(
        id: obj.id,
        polygon: [
          Point2(box[0] / proposal.image.widthPx, box[1] / proposal.image.heightPx),
          Point2(box[2] / proposal.image.widthPx, box[1] / proposal.image.heightPx),
          Point2(box[2] / proposal.image.widthPx, box[3] / proposal.image.heightPx),
          Point2(box[0] / proposal.image.widthPx, box[3] / proposal.image.heightPx),
        ],
        kind: SSObjectKind.unknown,
        containingSpaceId: obj.containingSpaceId,
        source: SSEntitySource.vision,
        reviewNeeded: obj.confidence < 0.5,
        reviewReasons: obj.confidence < 0.5 ? ['GPT vision confidence was low'] : const [],
      ));
    }

    final floorDomain = proposal.floorDomain.orderedCornerIds.map(cornerPoint).toList();

    return SSSpatialModel(
      sourceWidthPx: proposal.image.widthPx,
      sourceHeightPx: proposal.image.heightPx,
      spaces: spaces,
      walls: walls,
      openings: openings,
      objects: objects,
      warnings: warnings,
      boundaries: boundaries,
      floorDomain: floorDomain,
    );
  }

  double _polygonArea(List<Point2> polygon) {
    if (polygon.length < 3) return 0;
    var sum = 0.0;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      sum += polygon[j].x * polygon[i].y - polygon[i].x * polygon[j].y;
    }
    return sum.abs() / 2;
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
