// SS CAD TEST — Wall Detection Coverage WO 최종 DXF.
//
// lib/services/floor_plan_analysis_engine.dart에 dark+low-chroma 마스크를
// 추가한 뒤(색상 채움 바닥이 "벽"으로 오탐되던 문제 수정 —
// vision_cad_poc/drafting_v1/structural_layer.dart가 이미 검증해 둔
// 원칙을 그대로 재사용, 새 threshold 로직을 만들지 않음), 실제 pixel
// 증거 기반 벽 검출(Approach B)이 GPT hint 기반(Approach A)보다 실제로
// 얼마나 더 많은 건물을 복원하는지 비교하고, 더 나은 쪽을 채택한다.
//
// 이전 SS_CAD_TEST_REAL_FLOORPLAN_HYBRID.dxf(Approach A, 벽 14/방 0)는
// 덮어쓰지 않는다 — 이번 결과는 별도 파일(WALLFIX)로 저장한다.
//
// 실행: flutter test tool/export_real_floorplan_dxf_wallfix.dart (네트워크 없음)
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
  test('wall-detection-coverage fix -> topology reconstruction -> measured scale -> DXF export', () {
    const sourceWidthPx = 840;
    const sourceHeightPx = 497;

    // === GPT 3회 통합 실제 결과(직전 세션과 완전히 동일 — 재호출하지 않음) ===
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

    // === Approach A: GPT hint topology(직전 세션의 HYBRID 결과와 동일 로직) ===
    final hybridA = buildHybridCadFloorPlan(
      sourceWidthPx: sourceWidthPx,
      sourceHeightPx: sourceHeightPx,
      gptWalls: gptWalls,
      gptOpenings: gptOpenings,
      gptRooms: gptRooms,
    );

    // === Approach B: pixel_wall_v4 structural candidates, 이번엔
    // floor_plan_analysis_engine.dart의 dark+low-chroma 마스크 수정이
    // 적용된 상태로 재검출됨(§ Wall Detection Coverage WO). ===
    final imageFile = File(kRealFloorplanPath);
    HybridTopologyResult? hybridB;
    int structuralCandidateCount = 0;
    int totalCandidateCount = 0;
    if (imageFile.existsSync()) {
      final bytes = imageFile.readAsBytesSync();
      final pixelResult = runPixelWallPipeline(imageBytes: bytes, semantic: null);
      totalCandidateCount = pixelResult.extraction.candidates.length;
      final structuralCandidates = pixelResult.extraction.candidates.where((c) => c.category == PixelWallCategory.structural).toList();
      structuralCandidateCount = structuralCandidates.length;
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
    } else {
      print('Approach B SKIP: 실제 평면도 파일 없음');
    }

    print('=== Wall Detection Coverage 수정 전/후 (pixel_wall_v4 raw candidate) ===');
    print('BEFORE(직전 세션, chroma 필터 없음): structural 80 / 전체 104');
    print('AFTER (이번 세션, dark+low-chroma 필터 적용): structural $structuralCandidateCount / 전체 $totalCandidateCount');

    // 채택 기준 — 직전 세션은 connectedComponents/danglingEdgeCount(절대
    // 개수)만으로 비교해, 그래프 크기가 작을수록 유리한 착시로 방 0개인
    // 빈약한 결과를 잘못 채택했다(HYBRID.dxf). 이번에는 "실제로 얼마나
    // 많은 건물을 복원했는가"를 직접 재는 innerRoomCount(닫힌 face =
    // 실제 방)를 1순위로 삼는다 — 방은 축 정렬 edge들이 실제로 닫힌
    // loop를 이뤄야만 생기므로(extractFaces), 노이즈를 더해서 이 수치를
    // 거짓으로 부풀릴 수 없다(§5 "잘못된 벽을 대량 추가해 수치만 좋아지는
    // 방식 금지"와 부합). floorDomainClosed(완전 폐합)가 있으면 그것부터
    // 최우선.
    final candidates = [
      ('A(GPT-hint topology)', hybridA),
      if (hybridB != null) ('B(pixel-evidence topology, wallfix)', hybridB),
    ];
    print('\n=== Approach 비교 ===');
    for (final (name, h) in candidates) {
      print('$name: walls=${h.outputWallCount} rooms=${h.innerRoomCount} '
          'components=${h.connectedComponents} dangling=${h.danglingEdgeCount} closed=${h.floorDomainClosed}');
    }
    final chosen = candidates.reduce((best, cur) {
      final b = best.$2, c = cur.$2;
      if (c.floorDomainClosed != b.floorDomainClosed) return c.floorDomainClosed ? cur : best;
      if (c.innerRoomCount != b.innerRoomCount) return c.innerRoomCount > b.innerRoomCount ? cur : best;
      if (c.connectedComponents != b.connectedComponents) return c.connectedComponents < b.connectedComponents ? cur : best;
      return c.danglingEdgeCount < b.danglingEdgeCount ? cur : best;
    });
    print('채택: ${chosen.$1}');

    final hybrid = chosen.$2;
    final plan = hybrid.cadFloorPlan;

    print('\n=== BEFORE(직전 세션 HYBRID) vs AFTER(이번 WALLFIX) ===');
    print('BEFORE: walls=14 rooms=0 components=4 dangling=14 closed=false');
    print('AFTER : walls=${hybrid.outputWallCount} rooms=${hybrid.innerRoomCount} '
        'components=${hybrid.connectedComponents} dangling=${hybrid.danglingEdgeCount} closed=${hybrid.floorDomainClosed}');
    print('graph: vertices=${hybrid.graphVertexCount} edges=${hybrid.graphEdgeCount} tJunctions=${hybrid.tJunctionCount}');

    // 실제 물리 벽(가상 door bridge 아닌 것) 총 길이(px) — "wall coverage"의
    // 직접적인 수치화(§6).
    double totalPhysicalLengthPx = 0;
    for (final w in plan.walls) {
      totalPhysicalLengthPx += plan.pixelDistance(w.start, w.end);
    }
    print('총 물리 벽 길이 합계: ${totalPhysicalLengthPx.toStringAsFixed(0)}px (BEFORE 참고치: vision-wall 9개 원본 합계 ~1381px)');

    print('\n=== plan.warnings ===');
    for (final w in plan.warnings) {
      print('- $w');
    }

    // === 기준 실측 벽 재매칭(§9 — 임의 매칭 금지, 위치 근접도로만) ===
    // 촘촘해진 wall coverage 때문에 원래 vision-wall-4(y 0.6439~0.9859
    // 한 구간)가 이번엔 실제 새 T-junction(원본 GPT는 놓쳤던 진짜 벽
    // 교차)에서 여러 조각으로 쪼개질 수 있다 — "가장 가까운 edge 하나"
    // 만 보면 그 조각 하나만 잡혀 길이가 달라진다. 같은 x축 위(수직벽)에
    // 있고 원래 벽의 y범위 안에 있는 조각들을 전부 모아 합산 길이로
    // 판정한다(wall_system.dart의 "같은 축 위 조각들을 하나의 물리
    // 벽으로 본다" 원칙과 동일 — 새 로직을 만들지 않고 같은 판단 기준만
    // 재사용).
    const oldStart = Point2(0.0542, 0.6439);
    const oldEnd = Point2(0.0542, 0.9859);
    const axisTolerance = 0.01; // 정규화 좌표 — 원본 x=0.0542 대비 벽 두께 수준.
    final isVerticalAtAxis = plan.walls.where((w) {
      final sameX = (w.start.x - w.end.x).abs() < 0.005;
      if (!sameX) return false;
      final avgX = (w.start.x + w.end.x) / 2;
      if ((avgX - oldStart.x).abs() > axisTolerance) return false;
      final yMin = w.start.y < w.end.y ? w.start.y : w.end.y;
      final yMax = w.start.y < w.end.y ? w.end.y : w.start.y;
      // 원래 벽 구간([0.6439,0.9859])과 조금이라도 겹치면 후보.
      return yMax >= oldStart.y - 0.01 && yMin <= oldEnd.y + 0.01;
    }).toList();

    print('\n=== 기준 실측 벽 재매칭: 같은 축(x≈0.0542) 조각 ${isVerticalAtAxis.length}개 ===');
    for (final w in isVerticalAtAxis) {
      print('${w.id} lengthPx=${plan.pixelDistance(w.start, w.end).toStringAsFixed(1)} '
          'start=(${w.start.x.toStringAsFixed(4)},${w.start.y.toStringAsFixed(4)}) end=(${w.end.x.toStringAsFixed(4)},${w.end.y.toStringAsFixed(4)})');
    }
    expect(isVerticalAtAxis, isNotEmpty, reason: '기준 실측 벽(vision-wall-4) 위치에 대응하는 벽이 재구성 결과에 하나도 없으면 자동 적용을 멈춰야 한다');

    final combinedLengthPx = isVerticalAtAxis.fold<double>(0, (sum, w) => sum + plan.pixelDistance(w.start, w.end));
    final coveredYMin = isVerticalAtAxis.map((w) => w.start.y < w.end.y ? w.start.y : w.end.y).reduce((a, b) => a < b ? a : b);
    final coveredYMax = isVerticalAtAxis.map((w) => w.start.y < w.end.y ? w.end.y : w.start.y).reduce((a, b) => a > b ? a : b);
    print('합산 길이=${combinedLengthPx.toStringAsFixed(2)}px (원본 169.97px), '
        'y커버리지=[$coveredYMin,$coveredYMax] (원본 [0.6439,0.9859])');
    // 합쳐진 조각들이 원본 벽의 시작/끝 y와 각각 8~24px(pixel_wall_v4
    // 자체 junction 허용 오차) 안에서 대응해야 자동 채택한다.
    final startGapPx = (coveredYMin - oldStart.y).abs() * plan.sourceHeightPx;
    final endGapPx = (coveredYMax - oldEnd.y).abs() * plan.sourceHeightPx;
    print('시작점 오차=${startGapPx.toStringAsFixed(2)}px, 끝점 오차=${endGapPx.toStringAsFixed(2)}px');
    const maxAutoMatchTolerancePx = 24.0;
    expect(startGapPx, lessThan(maxAutoMatchTolerancePx), reason: '기준 벽 시작점이 원본과 명확히 대응해야만 자동으로 4700mm를 적용한다');
    expect(endGapPx, lessThan(maxAutoMatchTolerancePx), reason: '기준 벽 끝점이 원본과 명확히 대응해야만 자동으로 4700mm를 적용한다');

    final sample = ScaleReferenceSample(wallId: isVerticalAtAxis.first.id, pixelLength: combinedLengthPx, measuredMm: 4700);
    final resolved = resolveScaleFromSamples([sample]);
    final scale = FloorPlanScale(
      mmPerPixel: resolved.mmPerPixel,
      referenceStart: oldStart,
      referenceEnd: oldEnd,
      referenceLengthMm: 4700,
      source: ScaleSource.measured,
    );
    print('mmPerPixel=${scale.mmPerPixel.toStringAsFixed(6)} (합산 pixelLength=${combinedLengthPx.toStringAsFixed(2)}px)');

    final result = const E2eDxfExporter().export(plan, scale: scale);
    const outPath = r'C:\ASON\SS_CAD_TEST_REAL_FLOORPLAN_WALLFIX.dxf';
    File(outPath).writeAsStringSync(result.dxfContent);

    print('\n=== DXF ===');
    print('저장 경로: $outPath');
    print('isScaled=${result.isScaled}');
    print('notice=${result.notice}');

    expect(result.isScaled, isTrue);
    expect(File(outPath).existsSync(), isTrue);
  });
}
