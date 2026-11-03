// SS010 — CadConversionService 단위 테스트: 기존 TopologyValidator(Geometry Validation)·
// buildCadFloorPlanFromSpatialModel·resolveAutoScale·E2eDxfExporter를 그대로 재사용해 "전처리→
// 공간 구조 분석→벽/문/창 기하학 처리→치수/Scale→CAD/DXF 생성" 순서대로 단계를 알리는지, 입력
// 자체가 비어 있으면 일반 오류가 아니라 전용 CadConversionInputError로 구분하는지 확인한다.
import 'package:ason_space/core/ss_cad_conversion_step.dart';
import 'package:ason_space/models/cad_conversion_result.dart';
import 'package:ason_space/models/cad_floor_plan.dart' show FloorPlanScale, ScaleSource;
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/ss_spatial_model.dart';
import 'package:ason_space/services/cad_conversion_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = CadConversionService(stepDelay: Duration.zero);

  const sampleModel = SSSpatialModel(
    sourceWidthPx: 800,
    sourceHeightPx: 600,
    spaces: [
      SSSpace(
        id: 's1',
        polygon: [Point2(0.1, 0.1), Point2(0.5, 0.1), Point2(0.5, 0.5), Point2(0.1, 0.5)],
        areaNormalized: 0.16,
        closed: true,
        confidence: 0.9,
      ),
    ],
    walls: [
      SSWall(id: 'w1', start: Point2(0.1, 0.1), end: Point2(0.5, 0.1), thicknessNormalized: 0.02, kind: SSWallKind.exterior, confidence: 0.9),
    ],
    openings: [],
    objects: [],
    warnings: [],
  );

  test('확정된 공간모델을 전처리→분석→기하학→치수/Scale→CAD/DXF 순서대로 변환한다', () async {
    final steps = <SsCadConversionStep>[];
    final result = await service.convert(sampleModel, onStep: steps.add);

    expect(steps, SsCadConversionStep.values);
    expect(result.plan.walls, isNotEmpty);
    expect(result.dxfContent, contains('SS-EXTERIOR-WALL'));
    expect(result.dxfContent, contains('EOF'));
  });

  test('벽/공간이 전혀 없으면 입력 수정이 필요하다는 전용 오류를 던진다(일반 오류로 뭉개지 않는다)', () async {
    const emptyModel = SSSpatialModel(
      sourceWidthPx: 100,
      sourceHeightPx: 100,
      spaces: [],
      walls: [],
      openings: [],
      objects: [],
      warnings: [],
    );
    expect(() => service.convert(emptyModel), throwsA(isA<CadConversionInputError>()));
  });

  test('실측 scale이 주어지면 추정하지 않고 그 scale을 그대로 써서 DXF를 만든다', () async {
    const scale = FloorPlanScale(
      mmPerPixel: 1.0,
      referenceStart: Point2(0, 0),
      referenceEnd: Point2(1, 1),
      referenceLengthMm: 1000,
      source: ScaleSource.measured,
    );
    final result = await service.convert(sampleModel, knownScale: scale);
    expect(result.scale, same(scale));
    expect(result.isScaled, isTrue);
  });
}
