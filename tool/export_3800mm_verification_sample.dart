// SS CAD TEST — "실측 기반 Metric CAD → DXF → 실제 CAD에서 열기" 검증용
// 샘플 파일 생성기.
//
// 실제 GPT 분석 결과 대신, 좌표를 직접 지정한 사각형 방 하나(벽 4개 +
// 문 1개 + 창 1개)를 만든다 — 그래야 "위쪽 벽을 3800mm로 실측했다"고
// 가정했을 때 다른 세 벽/문/창이 각각 정확히 몇 mm여야 하는지 사람이
// 손으로도 검산할 수 있다.
//
// 이 모델 계층이 'package:flutter/foundation.dart'(@immutable)에
// 의존해 순수 dart:io VM(`dart run`)으로는 컴파일되지 않으므로,
// flutter 엔진 바인딩을 제공하는 flutter_test 하네스를 그대로
// 빌려 쓴다 — 실행: flutter test tool/export_3800mm_verification_sample.dart
// → 결과 DXF를 실제 CAD 프로그램(예: LibreCAD/AutoCAD/무료 DXF 뷰어)에서
//   열어 위쪽 벽 치수를 재보면 정확히 3800mm가 나와야 한다.
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/scale_calibration.dart';
import 'package:ason_space/services/e2e_dxf_exporter.dart';

void main() {
  test('generate 3800mm verification sample DXF', _generate);
}

void _generate() {
  const sourceWidthPx = 4000;
  const sourceHeightPx = 3000;

  const topWall = CadWall(
    id: 'wall-top',
    start: Point2(0.1, 0.1),
    end: Point2(0.7, 0.1),
    thicknessNormalized: 0.01,
    wallType: CadWallType.exterior,
    confidence: 1.0,
  );
  const rightWall = CadWall(
    id: 'wall-right',
    start: Point2(0.7, 0.1),
    end: Point2(0.7, 0.5),
    thicknessNormalized: 0.01,
    wallType: CadWallType.exterior,
    confidence: 1.0,
  );
  const bottomWall = CadWall(
    id: 'wall-bottom',
    start: Point2(0.7, 0.5),
    end: Point2(0.1, 0.5),
    thicknessNormalized: 0.01,
    wallType: CadWallType.exterior,
    confidence: 1.0,
  );
  const leftWall = CadWall(
    id: 'wall-left',
    start: Point2(0.1, 0.5),
    end: Point2(0.1, 0.1),
    thicknessNormalized: 0.01,
    wallType: CadWallType.exterior,
    confidence: 1.0,
  );

  // widthNormalized는 diagonalPx(=5000px) × mmPerPixel(=3800/2400) 기준으로
  // 문≈900mm, 창≈1200mm가 되도록 역산한 값이다(현실적인 크기로 검산하기
  // 쉽게 하기 위해서일 뿐, 실제 GPT 분석에서는 이렇게 손으로 정하지 않는다).
  const door = CadOpening(
    id: 'door-1',
    type: OpeningType.door,
    center: Point2(0.4, 0.5),
    widthNormalized: 0.1137,
    confidence: 1.0,
    wallId: 'wall-bottom',
  );
  const window = CadOpening(
    id: 'window-1',
    type: OpeningType.window,
    center: Point2(0.1, 0.3),
    widthNormalized: 0.1516,
    confidence: 1.0,
    wallId: 'wall-left',
  );

  const room = CadRoom(
    id: 'room-1',
    polygon: [
      Point2(0.1, 0.1),
      Point2(0.7, 0.1),
      Point2(0.7, 0.5),
      Point2(0.1, 0.5),
    ],
    areaNormalized: 0.6 * 0.4,
    confidence: 1.0,
  );

  final plan = CadFloorPlan(
    sourceWidthPx: sourceWidthPx,
    sourceHeightPx: sourceHeightPx,
    walls: const [topWall, rightWall, bottomWall, leftWall],
    openings: const [door, window],
    rooms: const [room],
    warnings: const [],
  );

  // 사용자가 "치수 보정"에서 위쪽 벽(topWall)을 실측해 3800mm라고
  // 입력했다고 가정 — FloorPlanWorkspaceScreen._onApplyCalibrationLength
  // 와 정확히 같은 계산(resolveScaleFromSamples, 샘플 1개)이다.
  final pixelLength = plan.pixelDistance(topWall.start, topWall.end);
  final sample = ScaleReferenceSample(
    wallId: topWall.id,
    pixelLength: pixelLength,
    measuredMm: 3800,
  );
  final resolved = resolveScaleFromSamples([sample]);
  final scale = FloorPlanScale(
    mmPerPixel: resolved.mmPerPixel,
    referenceStart: topWall.start,
    referenceEnd: topWall.end,
    referenceLengthMm: 3800,
    source: ScaleSource.measured,
  );

  final result = const E2eDxfExporter().export(plan, scale: scale);

  final outPath = r'C:\Users\user\AppData\Local\Temp\claude\c--ASON-Floorplan-CAD-Test\ba23118b-7f08-48d9-a2c2-f01e24e298e4\scratchpad\ss_cad_test_3800mm_verification.dxf';
  File(outPath).writeAsStringSync(result.dxfContent);

  double lenMm(CadWall w) => plan.metricWall(w, scale).lengthMm;

  print('DXF written to: $outPath');
  print('notice: ${result.notice}');
  print('--- 검산용 기대 길이(mm) ---');
  print('wall-top    (실측 확정 3800mm 기준): ${lenMm(topWall).toStringAsFixed(2)}');
  print('wall-right  : ${lenMm(rightWall).toStringAsFixed(2)}');
  print('wall-bottom : ${lenMm(bottomWall).toStringAsFixed(2)}');
  print('wall-left   : ${lenMm(leftWall).toStringAsFixed(2)}');
  print('door width  : ${plan.metricOpening(door, scale).widthMm.toStringAsFixed(2)}');
  print('window width: ${plan.metricOpening(window, scale).widthMm.toStringAsFixed(2)}');
}
