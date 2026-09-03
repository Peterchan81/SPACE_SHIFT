// SPACE SHIFT — PC1 CONTINUE: PHYSICAL ROOM / SEMANTIC ZONE SPLIT.
//
// §1 핵심 가정 수정 — "13 semantic spaces = 13 closed physical polygons"를
// 폐기한다. GPT의 13개 라벨 각각을 pixel flood-fill이 실제로 찾은
// PhysicalRoom에 1:1로 매칭할 수 있으면 physicalRoom, 여러 라벨이 벽 없이
// 하나의 열린 영역을 공유하면(예: 안방/거실/침실2/침실1이 실제로 하나로
// 이어진 open-plan) 그 라벨들은 SemanticZone으로 남긴다 — 없는 벽을
// 만들어 억지로 닫지 않는다(§9 "NO FAKE WALL FOR 13/13").

import 'dart:math' as math;

import '../../models/floor_plan_geometry.dart';
import 'gpt_semantic_schema.dart';

enum SpaceSemanticKind { physicalRoom, semanticZone }

/// §10 SpaceSemantic — GPT 라벨 하나가 최종적으로 어떤 종류의 geometry로
/// 표현되는지에 대한 판정 결과. [polygon]은 physicalRoom이면 실제
/// flood-fill 폴리곤 그대로, semanticZone이면 "참고용" 근사 사각형(벽
/// 경계 아님, CANONICAL CAD에 실선으로 그리지 않는다 — §11/§12)이거나,
/// 근거가 전혀 없으면 빈 리스트다(가짜 bbox로 대체하지 않는다).
class SpaceSemantic {
  const SpaceSemantic({
    required this.id,
    required this.label,
    required this.kind,
    required this.polygon,
    required this.confidence,
    required this.reviewNeeded,
    required this.reviewReasons,
    this.physicalRoomId,
  });

  final String id;
  final String label;
  final SpaceSemanticKind kind;
  final List<Point2> polygon;
  final double confidence;
  final bool reviewNeeded;
  final List<String> reviewReasons;

  /// kind가 physicalRoom이거나, semanticZone이 어떤 물리 room 내부에
  /// 있는지 알 때만 채워진다(있으면).
  final String? physicalRoomId;
}

class PhysicalRoomInfo {
  const PhysicalRoomInfo({required this.id, required this.polygon, required this.areaNormalized, required this.confidence, required this.claimedBySpaceIds});
  final String id;
  final List<Point2> polygon;
  final double areaNormalized;
  final double confidence;

  /// 이 물리적 room을 참조하는 semantic space id들(0=미매칭 "UNKNOWN
  /// PHYSICAL ROOM", 1=1:1 physicalRoom, 2+=open-plan으로 공유되는
  /// semanticZone들).
  final List<String> claimedBySpaceIds;
}

class ZoneMappingResult {
  const ZoneMappingResult({required this.spaces, required this.physicalRooms});
  final List<SpaceSemantic> spaces;
  final List<PhysicalRoomInfo> physicalRooms;
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

/// [a](GPT ROI)가 [b](물리 room bbox) 안에 얼마나 포함되는지.
double _containment(GptApproxRegion a, GptApproxRegion b) {
  final ix0 = math.max(a.x0, b.x0);
  final iy0 = math.max(a.y0, b.y0);
  final ix1 = math.min(a.x1, b.x1);
  final iy1 = math.min(a.y1, b.y1);
  final iw = ix1 - ix0;
  final ih = iy1 - iy0;
  if (iw <= 0 || ih <= 0) return 0;
  return (iw * ih) / math.max(a.area, 0.0001);
}

const double _minContainmentToClaim = 0.2;

ZoneMappingResult mapSemanticZones({
  required List<GptSemanticSpace> gptSpaces,
  required List<({String id, List<Point2> polygon, double areaNormalized, double confidence})> rooms,
}) {
  final roomBboxes = {for (final r in rooms) r.id: _bboxOf(r.polygon)};

  // 각 room을 "포함 비율 0.35 이상"으로 참조하는 space id들을 모은다.
  final claimsByRoom = {for (final r in rooms) r.id: <String>[]};
  final bestRoomForSpace = <String, String>{};
  for (final space in gptSpaces) {
    String? bestRoom;
    var bestScore = 0.0;
    for (final r in rooms) {
      final score = _containment(space.approxRegion, roomBboxes[r.id]!);
      if (score > bestScore) {
        bestScore = score;
        bestRoom = r.id;
      }
    }
    if (bestRoom != null && bestScore >= _minContainmentToClaim) {
      claimsByRoom[bestRoom]!.add(space.id);
      bestRoomForSpace[space.id] = bestRoom;
    }
  }

  final spaces = <SpaceSemantic>[];
  for (final space in gptSpaces) {
    final roomId = bestRoomForSpace[space.id];
    if (roomId == null) {
      spaces.add(
        SpaceSemantic(
          id: space.id,
          label: space.label,
          kind: SpaceSemanticKind.semanticZone,
          polygon: const [],
          confidence: 0,
          reviewNeeded: true,
          reviewReasons: const ['pixel로 검출된 어떤 PhysicalRoom과도 겹치지 않음 — geometry 근거 없음'],
        ),
      );
      continue;
    }
    final claimants = claimsByRoom[roomId]!;
    final room = rooms.firstWhere((r) => r.id == roomId);
    if (claimants.length == 1) {
      // 이 room을 이 space 하나만 참조 — 실제 닫힌 PhysicalRoom으로 인정.
      spaces.add(
        SpaceSemantic(
          id: space.id,
          label: space.label,
          kind: SpaceSemanticKind.physicalRoom,
          polygon: room.polygon,
          confidence: room.confidence,
          reviewNeeded: false,
          reviewReasons: const [],
          physicalRoomId: roomId,
        ),
      );
    } else {
      // 여러 space가 벽 없이 하나의 열린 영역을 공유 — SemanticZone.
      // geometry는 "참고용"으로 GPT ROI를 room bbox에 clip한 사각형을
      // 쓴다(벽 경계 아님, §9/§10 — CAD에 실선으로 그리지 않는다).
      final roomBbox = roomBboxes[roomId]!;
      final clipped = GptApproxRegion(
        x0: math.max(space.approxRegion.x0, roomBbox.x0),
        y0: math.max(space.approxRegion.y0, roomBbox.y0),
        x1: math.min(space.approxRegion.x1, roomBbox.x1),
        y1: math.min(space.approxRegion.y1, roomBbox.y1),
      );
      final polygon = (clipped.x1 > clipped.x0 && clipped.y1 > clipped.y0)
          ? [
              Point2(clipped.x0, clipped.y0),
              Point2(clipped.x1, clipped.y0),
              Point2(clipped.x1, clipped.y1),
              Point2(clipped.x0, clipped.y1),
            ]
          : <Point2>[];
      spaces.add(
        SpaceSemantic(
          id: space.id,
          label: space.label,
          kind: SpaceSemanticKind.semanticZone,
          polygon: polygon,
          confidence: room.confidence * 0.5,
          reviewNeeded: true,
          reviewReasons: const ['물리적으로 열린 공간(벽 없음) 내 의미 구역 — 실제 벽 경계가 아니라 대략 참고 영역'],
          physicalRoomId: roomId,
        ),
      );
    }
  }

  final physicalRooms = [
    for (final r in rooms)
      PhysicalRoomInfo(id: r.id, polygon: r.polygon, areaNormalized: r.areaNormalized, confidence: r.confidence, claimedBySpaceIds: claimsByRoom[r.id]!),
  ];

  return ZoneMappingResult(spaces: spaces, physicalRooms: physicalRooms);
}
