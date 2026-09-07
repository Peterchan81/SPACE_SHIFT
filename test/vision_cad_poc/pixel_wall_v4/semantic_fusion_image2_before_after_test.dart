// SPACE SHIFT — WO087 EXISTING SEMANTIC PRODUCTION WIRING.
//
// §17 REAL IMAGE 2 — 반드시 비교. 같은 이미지에 대해 A(geometry-only,
// production의 현재 기본 provider와 동일한 상태)와 B(캡처된 실제 GPT
// semantic fixture + geometry)를 [SemanticProvider] 경로로 나란히
// 실행해 정직하게 비교한다. 실제 API를 다시 호출하지 않는다(§6 —
// 기존에 검증된 captured fixture를 deterministic regression에 쓴다).
//
// 숫자가 달라졌다는 이유만으로 "개선"이라 하지 않는다 — 여기서 확인하는
// 것은 정확히: (1) geometry 자체(그래프/벽/개구부 개수)는 A/B 동일해야
// 한다(semantic은 geometry 계산에 관여하지 않는다), (2) room 라벨만
// B에서 실제로 늘어나야 한다, (3) opening door/window 확정 개수는 이
// 특정 fixture에 doorArc/windowDetail 근거가 0건이므로 A/B 동일(0)이어야
// 한다 — 근거가 없는데 억지로 늘리면 그게 바로 이 WO가 금지하는
// "PASS를 위한 조작"이다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/vision_cad_poc/e2e_v2/real_image2_source.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_pipeline.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/semantic_provider.dart';

const _capturePath = 'lib/vision_cad_poc/pixel_wall_v4/captured/semantic_v4.json';

void main() {
  test('실제 이미지 2 — geometry-only(A) vs semantic fixture+geometry(B) 정직한 비교', () async {
    final bytes = loadRealImage2Bytes();
    if (bytes == null || !File(_capturePath).existsSync()) {
      // ignore: avoid_print
      print('SKIP: 실제 이미지 2 또는 캡처된 semantic_v4.json 없음');
      return;
    }

    final before = await runPixelWallPipelineWithSemanticProvider(
      imageBytes: bytes,
      provider: const UnavailableSemanticProvider(), // production의 현재 기본값과 동일.
    );
    final after = await runPixelWallPipelineWithSemanticProvider(
      imageBytes: bytes,
      provider: const CapturedFixtureSemanticProvider(_capturePath),
    );

    // ignore: avoid_print
    print('''
=== 실제 이미지 2 — BEFORE(geometry-only) vs AFTER(semantic fixture+geometry) ===
semanticStatus: before=${before.semanticStatus.name} after=${after.semanticStatus.name}
Physical walls: before=${before.model.walls.length} after=${after.model.walls.length}
WallEdges: before=${before.model.wallEdges.length} after=${after.model.wallEdges.length}
PhysicalRooms: before=${before.physicalRooms.length} after=${after.physicalRooms.length}
GRAPH vertices: before=${before.floorDomain.graphVertexCount} after=${after.floorDomain.graphVertexCount}
GRAPH edges: before=${before.floorDomain.graphEdgeCount} after=${after.floorDomain.graphEdgeCount}
T-junctions: before=${before.floorDomain.tJunctionCount} after=${after.floorDomain.tJunctionCount}
FloorDomain valid: before=${before.floorDomain.isValid} after=${after.floorDomain.isValid}
FloorDomain topology status: before=${before.floorDomain.topology?.status.name} after=${after.floorDomain.topology?.status.name}
Opening candidates: before=${before.openingValidation.valid.length} after=${after.openingValidation.valid.length}
Doors confirmed: before=${before.doorOpeningCount} after=${after.doorOpeningCount}
Windows confirmed: before=${before.windowOpeningCount} after=${after.windowOpeningCount}
Unknown openings: before=${before.unknownOpeningCount} after=${after.unknownOpeningCount}
Room label matched to real polygon(physicalRoom kind, confirmedLabel): before=${before.matchedPhysicalRoomCount} after=${after.matchedPhysicalRoomCount}
Room label as semanticZone(suggestedLabel, reviewNeeded): before=${before.semanticZoneCount} after=${after.semanticZoneCount}
Unmatched GPT space: before=${before.unmatchedGptSpaceCount} after=${after.unmatchedGptSpaceCount}
Unmatched physical room("공간 N" 그대로): before=${before.unmatchedPhysicalRoomCount} after=${after.unmatchedPhysicalRoomCount}
''');

    // (1) geometry 자체는 semantic 유무와 무관하게 동일해야 한다 —
    // semantic evidence가 벽/그래프 계산에 절대 관여하지 않는다는 것을
    // 실측으로 고정한다.
    expect(after.model.walls.length, before.model.walls.length);
    expect(after.model.wallEdges.length, before.model.wallEdges.length);
    expect(after.floorDomain.graphVertexCount, before.floorDomain.graphVertexCount);
    expect(after.floorDomain.graphEdgeCount, before.floorDomain.graphEdgeCount);
    expect(after.floorDomain.tJunctionCount, before.floorDomain.tJunctionCount);
    expect(after.floorDomain.isValid, before.floorDomain.isValid);
    expect(after.physicalRooms.length, before.physicalRooms.length);
    expect(after.openingValidation.valid.length, before.openingValidation.valid.length);

    // (2) semanticStatus는 정확히 반영돼야 한다.
    expect(before.semanticStatus, SemanticProviderStatus.unavailable);
    expect(after.semanticStatus, SemanticProviderStatus.success);

    // (3) room 라벨은 B에서 실제로 늘어나야 한다(§9 room label — 이미
    // 존재하는 mapSemanticZones가 실제로 동작함을 증명) — before는
    // semantic이 전혀 없으므로 실제 라벨 매칭이 0이어야 하고, after는
    // 실제 캡처된 Image 2 GPT 응답으로 최소 1개 이상 physicalRoom으로
    // 확정 매칭돼야 한다(과거 세션에서 6개 확인됨 — 정확한 수는 fixture
    // 내용에 달려 있으므로 "0보다 크다"만 고정하고 정확한 값을
    // threshold처럼 반복 조정하지 않는다).
    expect(before.matchedPhysicalRoomCount, 0);
    expect(after.matchedPhysicalRoomCount, greaterThan(0));

    // (4) 이 특정 fixture에는 doorArc/windowDetail 근거가 0건이다(과거
    // 세션에서 확인됨) — 그래서 door/window 확정 개수는 A/B 모두 0이어야
    // 정직하다. 근거 없이 억지로 늘리면 안 된다(§10 — PASS를 위해
    // 추측하지 않는다).
    expect(before.doorOpeningCount, 0);
    expect(after.doorOpeningCount, 0);
    expect(before.windowOpeningCount, 0);
    expect(after.windowOpeningCount, 0);

    // (5) topology는 semantic evidence로 억지로 닫히지 않는다(§11 —
    // 실제 pixel evidence 부족은 semantic으로 메울 수 없다).
    expect(after.floorDomain.topology?.status, before.floorDomain.topology?.status);
  });
}
