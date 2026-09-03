// SPACE SHIFT — Image 2 AI → Real CAD End-to-End POC. DXF exporter 테스트.

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/services/e2e_dxf_exporter.dart';
import 'package:ason_space/services/e2e_geometry_solver.dart';
import 'package:ason_space/vision_cad_poc/e2e/vision_cad_proposal.dart';

void main() {
  const exporter = E2eDxfExporter();
  const solver = SSGeometrySolver();

  CadFloorPlan buildPlan() {
    final result = solver.solve(buildImage2VisionProposal());
    return buildCadFloorPlanFromSpatialModel(result.model);
  }

  test('scale이 없으면 UNSCALED/NORMALIZED POC로 명시되고 좌표는 정규화 단위 그대로다', () {
    final plan = buildPlan();
    final result = exporter.export(plan);
    expect(result.isScaled, isFalse);
    expect(result.notice, contains('UNSCALED'));
    expect(result.dxfContent, contains('UNSCALED'));
  });

  test('exterior/interior wall이 올바른 레이어에 들어간다', () {
    final plan = buildPlan();
    final result = exporter.export(plan);
    expect(result.dxfContent, contains('SS-EXTERIOR-WALL'));
    expect(result.dxfContent, contains('SS-INTERIOR-WALL'));
    expect(result.dxfContent, contains('SS-SPACE'));
  });

  test('LINE entity 개수가 (외벽+내벽) + 공간별 폴리곤 변 수와 일치한다', () {
    final plan = buildPlan();
    final result = exporter.export(plan);
    final lineCount = 'LINE'.allMatches(result.dxfContent).length;
    final expectedWallLines = plan.walls.length;
    final expectedSpaceLines = plan.rooms.fold<int>(0, (sum, r) => sum + r.polygon.length);
    expect(lineCount, expectedWallLines + expectedSpaceLines);
  });

  test('유효한 DXF 골격(SECTION/ENTITIES/EOF)을 갖는다', () {
    final plan = buildPlan();
    final result = exporter.export(plan);
    expect(result.dxfContent, contains('SECTION'));
    expect(result.dxfContent, contains('ENTITIES'));
    expect(result.dxfContent.trim(), endsWith('0\nEOF'));
  });

  test('실측 scale이 주어지면 좌표가 mm 단위로 바뀌고 SCALED로 표시된다', () {
    final plan = buildPlan();
    final wall = plan.walls.first;
    final pxLen = plan.pixelDistance(wall.start, wall.end);
    final scale = FloorPlanScale(
      mmPerPixel: 4000 / pxLen,
      referenceStart: wall.start,
      referenceEnd: wall.end,
      referenceLengthMm: 4000,
    );
    final result = exporter.export(plan, scale: scale);
    expect(result.isScaled, isTrue);
    expect(result.notice, contains('SCALED'));
    expect(result.dxfContent, isNot(contains('UNSCALED')));
  });
}
