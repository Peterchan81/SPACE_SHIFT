// SPACE SHIFT — Vision-Guided Full Pixel Wall Extraction POC.
//
// 전체 조립: pixel_wall_extractor(순수 픽셀, GPT 무관) → GPT 의미
// 지도로 라벨 매칭(geometry-first, "GPT: WHERE TO LOOK / PIXEL: EXACT
// LOCATION") → SSSpatialModel → TopologyValidator. FloorDomain은 항상
// pixel이 만든 exterior 벽 체인에서만 유도한다(GPT polygon 절대 사용 안 함).

import 'dart:math' as math;
import 'dart:typed_data';

import '../../models/floor_plan_geometry.dart';
import '../../models/ss_spatial_model.dart';
import '../../services/topology_validator.dart';
import 'gpt_semantic_schema.dart';
import 'pixel_wall_extractor.dart';
import 'pixel_wall_types.dart';

class PixelWallPipelineResult {
  const PixelWallPipelineResult({
    required this.extraction,
    required this.model,
    required this.floorDomainClosed,
    required this.floorDomainFailureReason,
    required this.matchedSpaceCount,
    required this.unmatchedGptSpaceCount,
    required this.unmatchedRoomCount,
  });

  final PixelWallExtractionResult extraction;
  final SSSpatialModel model;
  final bool floorDomainClosed;
  final String? floorDomainFailureReason;
  final int matchedSpaceCount;
  final int unmatchedGptSpaceCount;
  final int unmatchedRoomCount;
}

GptApproxRegion _bboxOf(List<Point2> polygon) {
  var minX = 1.0, maxX = 0.0, minY = 1.0, maxY = 0.0;
  for (final p in polygon) {
    minX = math.min(minX, p.x);
    maxX = math.max(maxX, p.x);
    minY = math.min(minY, p.y);
    maxY = math.max(maxY, p.y);
  }
  return GptApproxRegion(x0: minX, y0: minY, x1: maxX, y1: maxY);
}

double _distPx(Point2 a, Point2 b, int w, int h) {
  final dx = (a.x - b.x) * w;
  final dy = (a.y - b.y) * h;
  return math.sqrt(dx * dx + dy * dy);
}

/// 픽셀이 검출한 외벽(candidate) 후보를 실제 접합 순서대로 이어 하나의
/// 닫힌 루프를 만든다 — GPT polygon은 전혀 쓰지 않는다. 체인이 끊기거나
/// 안 닫히면 절대 임의로 잇지 않고 정직하게 실패 사유를 남긴다.
({List<Point2>? loop, String? failureReason}) _chainExteriorLoop(
  List<PixelWallCandidate> exteriorWalls,
  int w,
  int h,
) {
  if (exteriorWalls.isEmpty) {
    return (loop: null, failureReason: '외벽으로 분류된 pixel 벽 후보가 없음');
  }
  const tolerancePx = 14.0;
  final remaining = [...exteriorWalls];
  final first = remaining.removeAt(0);
  final loopPoints = <Point2>[first.start, first.end];
  var current = first.end;

  while (remaining.isNotEmpty) {
    PixelWallCandidate? best;
    var useStart = true;
    var bestDist = double.infinity;
    for (final seg in remaining) {
      final dStart = _distPx(current, seg.start, w, h);
      final dEnd = _distPx(current, seg.end, w, h);
      if (dStart < bestDist) {
        bestDist = dStart;
        best = seg;
        useStart = true;
      }
      if (dEnd < bestDist) {
        bestDist = dEnd;
        best = seg;
        useStart = false;
      }
    }
    if (best == null || bestDist > tolerancePx) break;
    remaining.remove(best);
    final next = useStart ? best.end : best.start;
    loopPoints.add(next);
    current = next;
  }

  if (remaining.isNotEmpty) {
    return (loop: null, failureReason: '외벽 체인이 끊어짐 — ${remaining.length}개 벽이 연결되지 않음');
  }
  final closureDist = _distPx(current, first.start, w, h);
  if (closureDist > tolerancePx) {
    return (
      loop: null,
      failureReason: '체인이 시작점으로 닫히지 않음(거리 ${closureDist.toStringAsFixed(1)}px)',
    );
  }
  return (loop: loopPoints, failureReason: null);
}

PixelWallPipelineResult runPixelWallPipeline({
  required Uint8List imageBytes,
  GptSemanticResponse? semantic,
}) {
  final extraction = extractPixelWalls(imageBytes);
  final w = extraction.analysisWidthPx;
  final h = extraction.analysisHeightPx;

  // --- 공간(space) 매칭: geometry-first — pixel RoomCandidate가 먼저
  // 존재하고, GPT는 그 위에 라벨만 얹는다(반대 순서 아님, §mandate).
  final spaces = <SSSpace>[];
  final assignedRoomIndex = <int>{};
  var matchedCount = 0;
  var unmatchedGptCount = 0;

  if (semantic != null) {
    final roomBboxes = [for (final r in extraction.rooms) _bboxOf(r.polygon)];
    final candidatePairs = <(int space, int room, double iou)>[];
    for (var si = 0; si < semantic.spaces.length; si++) {
      for (var ri = 0; ri < extraction.rooms.length; ri++) {
        final iou = semantic.spaces[si].approxRegion.iouWith(roomBboxes[ri]);
        if (iou > 0.05) candidatePairs.add((si, ri, iou));
      }
    }
    candidatePairs.sort((a, b) => b.$3.compareTo(a.$3));
    final assignedSpaceIndex = <int, int>{}; // spaceIndex -> roomIndex
    for (final pair in candidatePairs) {
      if (assignedSpaceIndex.containsKey(pair.$1)) continue;
      if (assignedRoomIndex.contains(pair.$2)) continue;
      assignedSpaceIndex[pair.$1] = pair.$2;
      assignedRoomIndex.add(pair.$2);
    }

    for (var si = 0; si < semantic.spaces.length; si++) {
      final gptSpace = semantic.spaces[si];
      final roomIndex = assignedSpaceIndex[si];
      if (roomIndex != null) {
        final room = extraction.rooms[roomIndex];
        matchedCount++;
        spaces.add(
          SSSpace(
            id: gptSpace.id,
            polygon: room.polygon,
            areaNormalized: room.areaNormalized,
            closed: true,
            confidence: room.confidence,
            label: gptSpace.label,
            source: SSEntitySource.geometry,
          ),
        );
      } else {
        unmatchedGptCount++;
        spaces.add(
          SSSpace(
            id: gptSpace.id,
            polygon: const [],
            areaNormalized: 0,
            closed: false,
            confidence: 0,
            label: gptSpace.label,
            source: SSEntitySource.vision,
            reviewNeeded: true,
            reviewReasons: const ['GPT 의미 지도와 대응하는 pixel 영역을 찾지 못함(IoU 근거 부족)'],
          ),
        );
      }
    }
  }

  // 어떤 GPT 공간과도 매칭되지 않은 pixel 방 후보 — 절대 삭제하지 않고
  // "UNKNOWN REGION"으로 남긴다(§6 — 조용히 삭제 금지).
  var idCounter = 0;
  for (var ri = 0; ri < extraction.rooms.length; ri++) {
    if (assignedRoomIndex.contains(ri)) continue;
    final room = extraction.rooms[ri];
    spaces.add(
      SSSpace(
        id: 'unknown-region-${idCounter++}',
        polygon: room.polygon,
        areaNormalized: room.areaNormalized,
        closed: true,
        confidence: room.confidence,
        source: SSEntitySource.geometry,
        reviewNeeded: true,
        reviewReasons: const ['GPT 의미 지도의 어떤 공간과도 매칭되지 않은 pixel 검출 영역(UNKNOWN REGION)'],
      ),
    );
  }
  final unmatchedRoomCount = extraction.rooms.length - assignedRoomIndex.length;

  // --- 벽: pixel candidate를 그대로 SSWall로 승격.
  final walls = <SSWall>[
    for (final c in extraction.candidates)
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
            ? const ['짧고 junction 근거가 약한 pixel 후보 — 구조 벽 확정 보류']
            : const [],
      ),
  ];

  // --- FloorDomain: pixel이 만든 exterior 체인만 사용(GPT polygon 금지).
  final exteriorCandidates = extraction.candidates
      .where((c) => c.isExterior && c.category == PixelWallCategory.structural)
      .toList();
  final chainResult = _chainExteriorLoop(exteriorCandidates, w, h);

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
    warnings: const [],
    floorDomain: chainResult.loop,
  );

  final validated = const TopologyValidator().validate(rawModel);

  return PixelWallPipelineResult(
    extraction: extraction,
    model: validated,
    floorDomainClosed: chainResult.loop != null,
    floorDomainFailureReason: chainResult.failureReason,
    matchedSpaceCount: matchedCount,
    unmatchedGptSpaceCount: unmatchedGptCount,
    unmatchedRoomCount: unmatchedRoomCount,
  );
}
