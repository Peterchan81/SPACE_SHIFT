// SS CAD TEST — 실제 평면도(평면도.PNG) GPT 3회 구조 분석 결과를 그대로
// 굳혀(freeze) 실측 보정 + DXF export까지 완료한다.
//
// 여기 하드코딩된 walls/openings/rooms는 tool/real_floorplan_gpt_analysis.dart
// 를 실행해 얻은 실제 GPT 3회 통합 결과를 한 글자도 바꾸지 않고 그대로
// 옮긴 것이다(재호출하지 않는다 — GPT 결과는 호출마다 달라질 수 있어,
// 사용자가 오버레이 이미지로 이미 확인한 바로 그 결과와 다른 실행 결과가
// 섞여 들어가는 것을 막기 위해서다).
//
// 실행: flutter test tool/export_real_floorplan_dxf.dart (네트워크 호출 없음)
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/scale_calibration.dart';
import 'package:ason_space/services/e2e_dxf_exporter.dart';

double _rectArea(List<Point2> polygon) {
  final xs = polygon.map((p) => p.x);
  final ys = polygon.map((p) => p.y);
  return (xs.reduce((a, b) => a > b ? a : b) - xs.reduce((a, b) => a < b ? a : b)) *
      (ys.reduce((a, b) => a > b ? a : b) - ys.reduce((a, b) => a < b ? a : b));
}

void main() {
  test('freeze real GPT 3-run result -> measured scale -> DXF export', () {
    const sourceWidthPx = 840;
    const sourceHeightPx = 497;

    // === GPT 3회 통합 실제 결과 (tool/real_floorplan_gpt_analysis.dart 실행 그대로) ===
    const walls = [
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

    const openings = [
      CadOpening(id: 'vision-door-1', type: OpeningType.door, center: Point2(0.5488, 0.7002), widthNormalized: 0.0246, confidence: 0.35, wallId: 'vision-wall-9'),
    ];

    final rooms = [
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

    final plan = CadFloorPlan(
      sourceWidthPx: sourceWidthPx,
      sourceHeightPx: sourceHeightPx,
      walls: walls,
      openings: openings,
      rooms: rooms,
      warnings: const [],
    );

    // === 사용자가 확정한 기준 실측 벽: vision-wall-4 = 4700mm(실측1.PNG) ===
    final calibrationWall = walls.firstWhere((w) => w.id == 'vision-wall-4');
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

    print('=== 적용 scale ===');
    print('calibration wall: ${calibrationWall.id}, pixelLength=${pixelLength.toStringAsFixed(2)}px, measuredMm=4700');
    print('mmPerPixel=${scale.mmPerPixel.toStringAsFixed(6)}');

    print('\n=== 벽별 실제 mm 길이(metricWall) ===');
    for (final w in walls) {
      final m = plan.metricWall(w, scale);
      print('${w.id} (${w.wallType.name}, conf=${w.confidence}) lengthMm=${m.lengthMm.toStringAsFixed(1)}');
    }

    final result = const E2eDxfExporter().export(plan, scale: scale);
    const outPath = r'C:\ASON\SS_CAD_TEST_REAL_FLOORPLAN.dxf';
    File(outPath).writeAsStringSync(result.dxfContent);

    print('\n=== DXF ===');
    print('저장 경로: $outPath');
    print('isScaled=${result.isScaled}');
    print('notice=${result.notice}');

    expect(result.isScaled, isTrue);
    expect(File(outPath).existsSync(), isTrue);
  });
}
