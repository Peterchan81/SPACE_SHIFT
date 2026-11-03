// SS010 — buildCadConversionInput 단위 테스트: SS009(평면도 확인·보정)의 'ssSpatialModel' 보정
// 결과와 SS005(직접 그리기)의 'directDraw' 결과를 모두 CAD 변환 엔진의 공통 입력으로 통일하는지,
// 확정된 데이터가 전혀 없으면 null을 돌려주는지 확인한다.
import 'package:ason_space/core/ss_project.dart';
import 'package:ason_space/core/ss_stage.dart' show SsSourceType;
import 'package:ason_space/models/cad_floor_plan.dart' show ScaleSource;
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/ss_draw_scene.dart';
import 'package:ason_space/models/ss_spatial_model.dart';
import 'package:ason_space/models/ss_spatial_model_json.dart';
import 'package:ason_space/services/cad_conversion_input_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sampleModel = SSSpatialModel(
    sourceWidthPx: 800,
    sourceHeightPx: 600,
    spaces: [],
    walls: [
      SSWall(id: 'w1', start: Point2(0, 0), end: Point2(1, 0), thicknessNormalized: 0.02, kind: SSWallKind.exterior, confidence: 0.9),
    ],
    openings: [],
    objects: [],
    warnings: [],
  );

  test('SS009 ssSpatialModel 보정 결과에서 입력을 만든다(scale은 변환 단계에서 새로 추정)', () {
    var project = SsProject.create(id: 'p1', name: '업로드', sourceType: SsSourceType.floorPlanUpload, now: DateTime(2026, 1, 1));
    project = project.withSource({'imageBase64': 'x'}, label: '원본');
    project = project.withStageData(SsDataSlot.recognitionData, {'model': ssSpatialModelToJson(sampleModel)}, label: 'AI 인식');
    project = project.withStageData(
      SsDataSlot.userCorrections,
      {'kind': 'ssSpatialModel', 'model': ssSpatialModelToJson(sampleModel)},
      label: '평면도 최종 확정',
    );

    final input = buildCadConversionInput(project);

    expect(input, isNotNull);
    expect(input!.knownScale, isNull);
    expect(input.model.walls, hasLength(1));
  });

  test('SS005 직접 그리기 결과에서 입력을 만들고 실측 scale을 함께 돌려준다', () {
    final scene = SsDrawScene.empty.addWall(const SsDrawPoint(0, 0), const SsDrawPoint(3000, 0));
    var project = SsProject.create(id: 'p2', name: '직접 그리기', sourceType: SsSourceType.directDraw, now: DateTime(2026, 1, 1));
    project = project.withStageData(SsDataSlot.userCorrections, {'kind': 'directDraw', 'scene': scene.toJson()}, label: '평면도 수정');

    final input = buildCadConversionInput(project);

    expect(input, isNotNull);
    expect(input!.knownScale, isNotNull);
    expect(input.knownScale!.source, ScaleSource.measured);
    expect(input.model.walls, hasLength(1));
  });

  test('확정된 공간 데이터가 전혀 없으면 null을 돌려준다', () {
    final project = SsProject.create(id: 'p3', name: '빈 프로젝트', sourceType: SsSourceType.directDraw, now: DateTime(2026, 1, 1));
    expect(buildCadConversionInput(project), isNull);
  });
}
