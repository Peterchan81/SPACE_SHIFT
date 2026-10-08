// SS CAD TEST — Hybrid Geometry Recovery: 실제 평면도 최종 DXF.
//
// tool/export_real_floorplan_dxf.dart와 완전히 같은 GPT 3회 통합 결과
// (한 글자도 바꾸지 않음, 재호출하지 않음)를 입력으로 쓰되, 이번에는
// GPT 좌표를 그대로 CAD로 확정하지 않고 [buildHybridCadFloorPlan](벽
// endpoint snap/T-L-X junction split/닫힌 방 추출을 pixel_wall_v4 엔진에
// 위임)을 거친 뒤 DXF를 만든다. 기존 파일(SS_CAD_TEST_REAL_FLOORPLAN.dxf)
// 은 덮어쓰지 않고 비교용으로 별도 이름에 저장한다.
//
// 실행: flutter test tool/export_real_floorplan_dxf_hybrid.dart (네트워크 없음)
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/scale_calibration.dart';
import 'package:ason_space/services/e2e_dxf_exporter.dart';
import 'package:ason_space/services/hybrid_wall_topology_builder.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_pipeline.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_types.dart';

const String kRealFloorplanPath = r'C:\Users\user\Desktop\스크린샷\평면도.PNG';

double _rectArea(List<Point2> polygon) {
  final xs = polygon.map((p) => p.x);
  final ys = polygon.map((p) => p.y);
  return (xs.reduce((a, b) => a > b ? a : b) - xs.reduce((a, b) => a < b ? a : b)) *
      (ys.reduce((a, b) => a > b ? a : b) - ys.reduce((a, b) => a < b ? a : b));
}

void main() {
  test('hybrid topology reconstruction -> measured scale -> DXF export', () {
    const sourceWidthPx = 840;
    const sourceHeightPx = 497;

    // === GPT 3회 통합 실제 결과 (export_real_floorplan_dxf.dart와 동일 — BEFORE) ===
    const gptWalls = [
      CadWall(id: 'vision-wall-1', start: Point2(0.3655, 0.2196), end: Point2(0.5702, 0.2196), thicknessNormalized: 0.01, wallType: CadWallType.exterior, confidence: 0.75),
      CadWall(id: 'vision-wall-2', start: Point2(0.9554, 0.3260), end: Point2(0.9554, 0.5835), thicknessNormalized: 0.01, wallType: CadWallType.exterior, confidence: 0.90),
      CadWall(id: 'vision-wall-3', start: Point2(0.0500, 0.9728), end: Point2(0.2631, 0.9728), thicknessNormalized: 0.01, wallType: CadWallType.exterior, confidence: 0.42),
      CadWall(id: 'vision-wall-4', start: Point2(0.0542, 0.6439), end: Point2(0.0542, 0.9859), thicknessNormalized: 0.01, wallType: CadWallType.exterior, confidence: 0.90),
      CadWall(id: 'vision-wall-5', start: Point2(0.0833, 0.5091), end: Point2(0.3524, 0.5091), thicknessNormalized: 0.01, wallType: CadWallType.interior, confidence: 0.73),
      CadWall(id: 'vision-wall-6', start: Point2(0.3302, 0.2696), end: Point2(0.3302, 0.6740), thicknessNormalized: 0.01, wallType: CadWallType.interior, confidence: 0.73),
      CadWall(id: 'vision-wall-7', start: Point2(0.0762, 0.8994), end: Point2(0.5560, 0.8994), thicknessNormalized: 0.01, wallType: CadWallType.exterior, confidence: 0.35, reviewNeeded: true),
      CadWall(id: 'vision-wall-8', start: Point2(0.1000, 0.5070), end: Point2(0.1000, 0.9376), thicknessNormalized: 0.01, wallType: CadWallType.exterior, confidence: 0.35, reviewNeeded: true),
      CadWall(id: 'vision-wall-9', start: Point2(0.5490, 0.6620), end: Point2(0.5490, 0.9195), thicknessNormalized: 0.01, wallType: CadWallType.interior, confidence: 0.35, reviewNeeded: true),
    ];

    const gptOpenings = [
      CadOpening(id: 'vision-door-1', type: OpeningType.door, center: Point2(0.5488, 0.7002), widthNormalized: 0.0246, confidence: 0.35, wallId: 'vision-wall-9'),
    ];

    final gptRooms = [
      CadRoom(id: 'vision-room-1', polygon: const [Point2(0.100, 0.299), Point2(0.301, 0.299), Point2(0.301, 0.499), Point2(0.100, 0.499)], areaNormalized: _rectArea(const [Point2(0.100, 0.299), Point2(0.301, 0.299), Point2(0.301, 0.499), Point2(0.100, 0.499)]), confidence: 0.84, name: '침실'),
      CadRoom(id: 'vision-room-2', polygon: const [Point2(0.054, 0.495), Point2(0.241, 0.495), Point2(0.241, 0.686), Point2(0.054, 0.686)], areaNormalized: _rectArea(const [Point2(0.054, 0.495), Point2(0.241, 0.495), Point2(0.241, 0.686), Point2(0.054, 0.686)]), confidence: 0.90, name: '침실'),
      CadRoom(id: 'vision-room-3', polygon: const [Point2(0.054, 0.509), Point2(0.329, 0.509), Point2(0.329, 0.771), Point2(0.054, 0.771)], areaNormalized: _rectArea(const [Point2(0.054, 0.509), Point2(0.329, 0.509), Point2(0.329, 0.771), Point2(0.054, 0.771)]), confidence: 0.95, name: '거실'),
      CadRoom(id: 'vision-room-4', polygon: const [Point2(0.271, 0.195), Point2(0.630, 0.195), Point2(0.630, 0.528), Point2(0.271, 0.528)], areaNormalized: _rectArea(const [Point2(0.271, 0.195), Point2(0.630, 0.195), Point2(0.630, 0.528), Point2(0.271, 0.528)]), confidence: 0.95),
      CadRoom(id: 'vision-room-5', polygon: const [Point2(0.368, 0.527), Point2(0.633, 0.527), Point2(0.633, 0.764), Point2(0.368, 0.764)], areaNormalized: _rectArea(const [Point2(0.368, 0.527), Point2(0.633, 0.527), Point2(0.633, 0.764), Point2(0.368, 0.764)]), confidence: 0.90, name: '주방 및 식당'),
      CadRoom(id: 'vision-room-6', polygon: const [Point2(0.630, 0.331), Point2(0.735, 0.331), Point2(0.735, 0.437), Point2(0.630, 0.437)], areaNormalized: _rectArea(const [Point2(0.630, 0.331), Point2(0.735, 0.331), Point2(0.735, 0.437), Point2(0.630, 0.437)]), confidence: 0.35, name: '현관'),
      CadRoom(id: 'vision-room-7', polygon: const [Point2(0.729, 0.145), Point2(0.955, 0.145), Point2(0.955, 0.369), Point2(0.729, 0.369)], areaNormalized: _rectArea(const [Point2(0.729, 0.145), Point2(0.955, 0.145), Point2(0.955, 0.369), Point2(0.729, 0.369)]), confidence: 0.90, name: '침실'),
      CadRoom(id: 'vision-room-8', polygon: const [Point2(0.633, 0.429), Point2(0.955, 0.429), Point2(0.955, 0.640), Point2(0.633, 0.640)], areaNormalized: _rectArea(const [Point2(0.633, 0.429), Point2(0.955, 0.429), Point2(0.955, 0.640), Point2(0.633, 0.640)]), confidence: 0.95, name: '침실'),
      CadRoom(id: 'vision-room-9', polygon: const [Point2(0.237, 0.757), Point2(0.480, 0.757), Point2(0.480, 0.973), Point2(0.237, 0.973)], areaNormalized: _rectArea(const [Point2(0.237, 0.757), Point2(0.480, 0.757), Point2(0.480, 0.973), Point2(0.237, 0.973)]), confidence: 0.35, name: '주방 및 식당'),
      CadRoom(id: 'vision-room-10', polygon: const [Point2(0.661, 0.795), Point2(0.942, 0.795), Point2(0.942, 1.000), Point2(0.661, 1.000)], areaNormalized: _rectArea(const [Point2(0.661, 0.795), Point2(0.942, 0.795), Point2(0.942, 1.000), Point2(0.661, 1.000)]), confidence: 0.35, name: '침실'),
      CadRoom(id: 'vision-room-11', polygon: const [Point2(0.460, 0.071), Point2(0.657, 0.071), Point2(0.657, 0.320), Point2(0.460, 0.320)], areaNormalized: _rectArea(const [Point2(0.460, 0.071), Point2(0.657, 0.071), Point2(0.657, 0.320), Point2(0.460, 0.320)]), confidence: 0.35),
      CadRoom(id: 'vision-room-12', polygon: const [Point2(0.271, 0.492), Point2(0.421, 0.492), Point2(0.421, 0.688), Point2(0.271, 0.688)], areaNormalized: _rectArea(const [Point2(0.271, 0.492), Point2(0.421, 0.492), Point2(0.421, 0.688), Point2(0.271, 0.688)]), confidence: 0.35),
    ];

    // === Approach A: GPT의 9개 벽 hint만으로 topology 재구성 ===
    final hybridA = buildHybridCadFloorPlan(
      sourceWidthPx: sourceWidthPx,
      sourceHeightPx: sourceHeightPx,
      gptWalls: gptWalls,
      gptOpenings: gptOpenings,
      gptRooms: gptRooms,
    );

    // === Approach B: pixel_wall_v4의 원본 pixel 증거(구조 벽으로 확정된
    // 것만, category=structural)를 그대로 topology 재구성 입력으로 쓴다
    // — GPT hint가 놓친 벽까지 포함해 훨씬 더 촘촘한 wall coverage를
    // 준다(§3 "AI가 geometry의 최종 truth source가 되어서는 안 된다"를
    // 가장 직접적으로 만족하는 경로 — 좌표 근거가 전부 픽셀이다).
    final imageFile = File(kRealFloorplanPath);
    HybridTopologyResult? hybridB;
    if (imageFile.existsSync()) {
      final bytes = imageFile.readAsBytesSync();
      final pixelResult = runPixelWallPipeline(imageBytes: bytes, semantic: null);
      final structuralCandidates = pixelResult.extraction.candidates.where((c) => c.category == PixelWallCategory.structural).toList();
      final pixelWallsAsCad = [
        for (final c in structuralCandidates)
          CadWall(
            id: c.id,
            start: c.start,
            end: c.end,
            thicknessNormalized: c.thicknessNormalized,
            wallType: c.isExterior ? CadWallType.exterior : CadWallType.interior,
            confidence: c.baseConfidence,
          ),
      ];
      hybridB = buildHybridCadFloorPlan(
        sourceWidthPx: pixelResult.extraction.sourceWidthPx,
        sourceHeightPx: pixelResult.extraction.sourceHeightPx,
        gptWalls: pixelWallsAsCad,
        gptOpenings: gptOpenings,
        gptRooms: gptRooms,
      );
      print('=== Approach B 입력: pixel_wall_v4 structural candidates ${structuralCandidates.length}개(전체 ${pixelResult.extraction.candidates.length}개 중) ===');
    } else {
      print('Approach B SKIP: 실제 평면도 파일 없음');
    }

    // 두 접근 중 닫힌 방(inner face)을 더 많이/제대로 만든 쪽을 최종
    // DXF로 채택한다 — "문/창/방 개수만 늘어난 것을 성공으로 보고하지
    // 않는다"는 원칙에 따라, 채택 기준은 오직 topology 품질
    // (connectedComponents가 작을수록, danglingEdgeCount가 적을수록
    // 좋음)이지 방 개수 자체가 아니다.
    final candidates = [
      ('A(GPT-hint topology)', hybridA),
      if (hybridB != null) ('B(pixel-evidence topology)', hybridB),
    ];
    print('\n=== Approach 비교 ===');
    for (final (name, h) in candidates) {
      print('$name: walls=${h.outputWallCount} rooms=${h.innerRoomCount} '
          'components=${h.connectedComponents} dangling=${h.danglingEdgeCount} closed=${h.floorDomainClosed}');
    }
    final chosen = candidates.reduce((best, cur) {
      final b = best.$2, c = cur.$2;
      // 1순위: floorDomainClosed. 2순위: connectedComponents 적은 쪽.
      // 3순위: danglingEdgeCount 적은 쪽.
      if (c.floorDomainClosed != b.floorDomainClosed) return c.floorDomainClosed ? cur : best;
      if (c.connectedComponents != b.connectedComponents) return c.connectedComponents < b.connectedComponents ? cur : best;
      return c.danglingEdgeCount < b.danglingEdgeCount ? cur : best;
    });
    print('채택: ${chosen.$1}');

    final hybrid = chosen.$2;
    final plan = hybrid.cadFloorPlan;

    print('\n=== BEFORE (GPT 원좌표 그대로) vs AFTER (채택된 hybrid topology) ===');
    print('walls: ${gptWalls.length} -> ${hybrid.outputWallCount} (axis-normalized ${hybrid.axisNormalizedCount}, excluded-non-axis ${hybrid.excludedNonAxisCount})');
    print('rooms: ${gptRooms.length}(독립 사각형) -> ${hybrid.innerRoomCount}(닫힌 wall-topology face)');
    print('graph: vertices=${hybrid.graphVertexCount} edges=${hybrid.graphEdgeCount} tJunctions=${hybrid.tJunctionCount}');
    print('connectedComponents=${hybrid.connectedComponents} danglingEdgeCount=${hybrid.danglingEdgeCount}');
    print('floorDomainClosed=${hybrid.floorDomainClosed} reason=${hybrid.floorDomainFailureReason}');
    print('\n=== plan.warnings ===');
    for (final w in plan.warnings) {
      print('- $w');
    }

    print('\n=== 재구성된 벽 목록 ===');
    for (final w in plan.walls) {
      final pxLen = plan.pixelDistance(w.start, w.end);
      print('${w.id} ${w.wallType.name} conf=${w.confidence.toStringAsFixed(2)} reviewNeeded=${w.reviewNeeded} '
          'start=(${w.start.x.toStringAsFixed(4)},${w.start.y.toStringAsFixed(4)}) end=(${w.end.x.toStringAsFixed(4)},${w.end.y.toStringAsFixed(4)}) pxLen=${pxLen.toStringAsFixed(1)}');
    }

    print('\n=== 재구성된 방 목록 ===');
    for (final r in plan.rooms) {
      print('${r.id} name=${r.name} pts=${r.polygon.length}');
    }

    print('\n=== 재-anchor된 opening ===');
    for (final o in plan.openings) {
      print('${o.id} wallId=${o.wallId} reviewNeeded=${o.reviewNeeded}');
    }

    // === 사용자가 확정한 기준 실측 벽: 원래 vision-wall-4(4700mm)에
    // 가장 가까운 위치의 새 edge를 찾는다(§9 — 어떤 실측값도 임의로
    // 특정 벽에 매칭하지 않는다: 원본 좌표와 명확히 대응하는 경우만
    // 자동 채택하고, 그렇지 않으면 여기서 멈춰야 한다).
    const oldStart = Point2(0.0542, 0.6439);
    const oldEnd = Point2(0.0542, 0.9859);
    double distSum(CadWall w) {
      final dStart = plan.pixelDistance(w.start, oldStart) + plan.pixelDistance(w.end, oldEnd);
      final dSwapped = plan.pixelDistance(w.start, oldEnd) + plan.pixelDistance(w.end, oldStart);
      return dStart < dSwapped ? dStart : dSwapped;
    }
    final sorted = [...plan.walls]..sort((a, b) => distSum(a).compareTo(distSum(b)));
    final calibrationWall = sorted.first;
    final matchDistPx = distSum(calibrationWall);
    print('\n=== 기준 실측 벽 재매칭 ===');
    print('가장 가까운 벽: ${calibrationWall.id}, 두 끝점 거리 합=${matchDistPx.toStringAsFixed(2)}px');
    // pixel_wall_v4 자신의 junction canonicalization 허용 오차 범위
    // (planar_wall_graph.dart dynamicTolerance: 8~24px)를 그대로 재사용한다
    // — 정상적인 endpoint snap(같은 벽이 인접 모서리로 살짝 당겨짐)까지
    // "다른 벽"으로 오판하지 않으면서도, 진짜 다른 벽과의 오매칭은 여전히
    // 막는다(임의 확대가 아니라 원본 알고리즘과 같은 근거).
    const maxAutoMatchTolerancePx = 24.0;
    expect(matchDistPx, lessThan(maxAutoMatchTolerancePx), reason: '기준 벽 위치가 원본과 명확히 대응해야만 자동으로 4700mm를 적용한다');

    final pixelLength = plan.pixelDistance(calibrationWall.start, calibrationWall.end);
    final sample = ScaleReferenceSample(wallId: calibrationWall.id, pixelLength: pixelLength, measuredMm: 4700);
    final resolved = resolveScaleFromSamples([sample]);
    final scale = FloorPlanScale(
      mmPerPixel: resolved.mmPerPixel,
      referenceStart: calibrationWall.start,
      referenceEnd: calibrationWall.end,
      referenceLengthMm: 4700,
      source: ScaleSource.measured,
    );
    print('mmPerPixel=${scale.mmPerPixel.toStringAsFixed(6)} (pixelLength=${pixelLength.toStringAsFixed(2)}px)');

    final result = const E2eDxfExporter().export(plan, scale: scale);
    const outPath = r'C:\ASON\SS_CAD_TEST_REAL_FLOORPLAN_HYBRID.dxf';
    File(outPath).writeAsStringSync(result.dxfContent);

    print('\n=== DXF ===');
    print('저장 경로: $outPath');
    print('isScaled=${result.isScaled}');
    print('notice=${result.notice}');

    expect(result.isScaled, isTrue);
    expect(File(outPath).existsSync(), isTrue);
  });
}
