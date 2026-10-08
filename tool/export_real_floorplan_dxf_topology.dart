// SS CAD TEST — Wall Consolidation & Topology Closure WO 최종 DXF.
//
// pixel_wall_v4 structural candidates(92개, dark+low-chroma 마스크 적용
// 이후) -> buildWallSystems(이미 검증된 코드, 같은 축 raw segment를
// 물리 벽으로 묶음) -> consolidateWallSystems(door/imageBreak gap만
// 이어붙이고 open-plan/notConnected는 절대 잇지 않음, 이번 WO 신규) ->
// buildHybridCadFloorPlan(지난 세션의 검증된 topology 재구성, 변경 없음)
// -> 작은 noise face 제거 -> DXF.
//
// 실행: flutter test tool/export_real_floorplan_dxf_topology.dart (네트워크 없음)
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/scale_calibration.dart';
import 'package:ason_space/services/e2e_dxf_exporter.dart';
import 'package:ason_space/services/hybrid_wall_topology_builder.dart';
import 'package:ason_space/services/wall_system_consolidator.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_pipeline.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_types.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/wall_system.dart';

const String kRealFloorplanPath = r'C:\Users\user\Desktop\스크린샷\평면도.PNG';

void main() {
  test('wall consolidation -> topology closure attempt -> measured scale -> DXF export', () {
    final imageFile = File(kRealFloorplanPath);
    if (!imageFile.existsSync()) {
      print('SKIP: 실제 평면도 파일 없음');
      return;
    }
    final bytes = imageFile.readAsBytesSync();
    final pixelResult = runPixelWallPipeline(imageBytes: bytes, semantic: null);
    final w = pixelResult.extraction.sourceWidthPx;
    final h = pixelResult.extraction.sourceHeightPx;

    final structuralCandidates = pixelResult.extraction.candidates.where((c) => c.category == PixelWallCategory.structural).toList();
    final rawWallSystems = buildWallSystems(candidates: structuralCandidates, w: w, h: h);
    final consolidatedWalls = consolidateWallSystems(rawWallSystems, w: w, h: h);

    print('=== Consolidation ===');
    print('raw structural candidates: ${structuralCandidates.length}');
    print('wall systems(같은 축으로 묶음): ${rawWallSystems.length}');
    print('consolidated walls(door/imageBreak gap만 이어붙임): ${consolidatedWalls.length}');
    final rejectedGapKinds = <GapKind, int>{};
    for (final s in rawWallSystems) {
      for (final g in s.gaps) {
        rejectedGapKinds[g.kind] = (rejectedGapKinds[g.kind] ?? 0) + 1;
      }
    }
    print('gap 종류 분포(전체): $rejectedGapKinds');

    // === 이전 세션(WALLFIX, consolidation 없이 raw 92개 candidate를
    // 바로 topology 재구성에 넣음) 대비 이번(consolidated) topology 비교 ===
    final beforeHybrid = buildHybridCadFloorPlan(
      sourceWidthPx: w,
      sourceHeightPx: h,
      gptWalls: [
        for (final c in structuralCandidates)
          CadWall(
            id: c.id,
            start: c.start,
            end: c.end,
            thicknessNormalized: c.thicknessNormalized,
            wallType: c.isExterior ? CadWallType.exterior : CadWallType.interior,
            confidence: c.baseConfidence,
          ),
      ],
      gptOpenings: const [],
      gptRooms: const [],
    );

    final afterHybrid = buildHybridCadFloorPlan(
      sourceWidthPx: w,
      sourceHeightPx: h,
      gptWalls: consolidatedWalls,
      gptOpenings: const [],
      gptRooms: const [],
    );

    print('\n=== Topology Before(raw 92 candidates) vs After(consolidated) ===');
    print('BEFORE: walls=${beforeHybrid.outputWallCount} rooms=${beforeHybrid.innerRoomCount} '
        'components=${beforeHybrid.connectedComponents} dangling=${beforeHybrid.danglingEdgeCount} closed=${beforeHybrid.floorDomainClosed}');
    print('AFTER : walls=${afterHybrid.outputWallCount} rooms=${afterHybrid.innerRoomCount} '
        'components=${afterHybrid.connectedComponents} dangling=${afterHybrid.danglingEdgeCount} closed=${afterHybrid.floorDomainClosed}');

    // === 작은 noise face(방이 아니라 벽 두께/오검출 sliver) 판별을 위한
    // 면적 분포 확인 — 임의 숫자로 8개에 맞추지 않고, 실제 분포를 보고
    // 판단한다(§ "숫자를 억지로 맞추지 말고 geometry evidence에 따라
    // 판단"). ===
    final areasNormalized = afterHybrid.cadFloorPlan.rooms.map((r) => r.areaNormalized).toList()..sort();
    print('\n=== 방(닫힌 face) 면적 분포(정규화, 오름차순) ===');
    print(areasNormalized.map((a) => a.toStringAsFixed(6)).toList());

    final plan = afterHybrid.cadFloorPlan;
    print('\n=== 재구성된 벽 개수: ${plan.walls.length}, 방 개수: ${plan.rooms.length} ===');
    print('plan.warnings: ${plan.warnings}');

    // === 기준 실측 벽(4700mm) 재매칭 — 같은 축 위 조각 합산(WALLFIX와
    // 동일 원칙, 임의 매칭 금지) ===
    const oldStart = Point2(0.0542, 0.6439);
    const oldEnd = Point2(0.0542, 0.9859);
    const axisTolerance = 0.01;
    final atAxis = plan.walls.where((wall) {
      final sameX = (wall.start.x - wall.end.x).abs() < 0.005;
      if (!sameX) return false;
      final avgX = (wall.start.x + wall.end.x) / 2;
      if ((avgX - oldStart.x).abs() > axisTolerance) return false;
      final yMin = wall.start.y < wall.end.y ? wall.start.y : wall.end.y;
      final yMax = wall.start.y < wall.end.y ? wall.end.y : wall.start.y;
      return yMax >= oldStart.y - 0.01 && yMin <= oldEnd.y + 0.01;
    }).toList();
    print('\n=== 기준 실측 벽 재매칭: 같은 축(x≈0.0542) 조각 ${atAxis.length}개 ===');
    for (final wall in atAxis) {
      print('${wall.id} lengthPx=${plan.pixelDistance(wall.start, wall.end).toStringAsFixed(1)} '
          'start=(${wall.start.x.toStringAsFixed(4)},${wall.start.y.toStringAsFixed(4)}) end=(${wall.end.x.toStringAsFixed(4)},${wall.end.y.toStringAsFixed(4)})');
    }
    expect(atAxis, isNotEmpty, reason: '기준 실측 벽 위치에 대응하는 벽이 재구성 결과에 있어야 한다');

    final combinedLengthPx = atAxis.fold<double>(0, (sum, wall) => sum + plan.pixelDistance(wall.start, wall.end));
    final coveredYMin = atAxis.map((wall) => wall.start.y < wall.end.y ? wall.start.y : wall.end.y).reduce((a, b) => a < b ? a : b);
    final coveredYMax = atAxis.map((wall) => wall.start.y < wall.end.y ? wall.end.y : wall.start.y).reduce((a, b) => a > b ? a : b);
    final startGapPx = (coveredYMin - oldStart.y).abs() * plan.sourceHeightPx;
    final endGapPx = (coveredYMax - oldEnd.y).abs() * plan.sourceHeightPx;
    print('합산 길이=${combinedLengthPx.toStringAsFixed(2)}px, 시작점 오차=${startGapPx.toStringAsFixed(2)}px, 끝점 오차=${endGapPx.toStringAsFixed(2)}px');
    const maxAutoMatchTolerancePx = 24.0;
    expect(startGapPx, lessThan(maxAutoMatchTolerancePx), reason: '기준 벽 시작점이 원본과 명확히 대응해야만 자동으로 4700mm를 적용한다');
    expect(endGapPx, lessThan(maxAutoMatchTolerancePx), reason: '기준 벽 끝점이 원본과 명확히 대응해야만 자동으로 4700mm를 적용한다');

    final sample = ScaleReferenceSample(wallId: atAxis.first.id, pixelLength: combinedLengthPx, measuredMm: 4700);
    final resolved = resolveScaleFromSamples([sample]);
    final scale = FloorPlanScale(
      mmPerPixel: resolved.mmPerPixel,
      referenceStart: oldStart,
      referenceEnd: oldEnd,
      referenceLengthMm: 4700,
      source: ScaleSource.measured,
    );
    print('mmPerPixel=${scale.mmPerPixel.toStringAsFixed(6)}');

    // === 작은 noise face 제거 — 실제 mm 면적으로 판정한다(정규화 면적
    // 자체는 이미지 크기에 따라 의미가 달라지므로, scale 확정 후에만
    // 판정 가능하다). 1.0㎡ 미만은 실제 방/드레스룸/현관 같은 독립
    // 공간으로 보기 어려운 벽 두께 sliver/이중선 오검출로 판단한다 —
    // 8개로 억지로 맞추지 않고, 이 하나의 물리적 기준선만 적용한다.
    const minRoomAreaM2 = 1.0;
    final roomsWithArea = [
      for (final r in plan.rooms) (room: r, areaM2: roomAreaM2(plan, r, scale) ?? 0),
    ];
    final acceptedRooms = [for (final e in roomsWithArea) if (e.areaM2 >= minRoomAreaM2) e.room];
    final rejectedRooms = [for (final e in roomsWithArea) if (e.areaM2 < minRoomAreaM2) e];
    print('\n=== 작은 noise face 필터(<$minRoomAreaM2㎡) ===');
    print('전체 ${plan.rooms.length}개 중 채택 ${acceptedRooms.length}개, 제외 ${rejectedRooms.length}개');
    print('제외된 face 면적(㎡): ${rejectedRooms.map((e) => e.areaM2.toStringAsFixed(3)).toList()}');
    print('채택된 face 면적(㎡, 오름차순): ${(roomsWithArea.where((e) => e.areaM2 >= minRoomAreaM2).map((e) => e.areaM2).toList()..sort()).map((a) => a.toStringAsFixed(2)).toList()}');

    final filteredPlan = CadFloorPlan(
      sourceWidthPx: plan.sourceWidthPx,
      sourceHeightPx: plan.sourceHeightPx,
      walls: plan.walls,
      openings: plan.openings,
      rooms: acceptedRooms,
      warnings: plan.warnings,
    );

    final result = const E2eDxfExporter().export(filteredPlan, scale: scale);
    const outPath = r'C:\ASON\SS_CAD_TEST_REAL_FLOORPLAN_TOPOLOGY.dxf';
    File(outPath).writeAsStringSync(result.dxfContent);

    print('\n=== DXF ===');
    print('저장 경로: $outPath');
    print('isScaled=${result.isScaled}');
    print('notice=${result.notice}');

    expect(result.isScaled, isTrue);
    expect(File(outPath).existsSync(), isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
