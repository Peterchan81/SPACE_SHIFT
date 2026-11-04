// SS015 — IsoRenderService 단위 테스트: 기존 buildIsoEditorScene을 그대로 재사용해 "이미지 품질
// 처리→재질/조명 적용→공간 분위기 렌더링→최종 이미지 생성→3D 아이소 모델 반영" 순서대로 단계를
// 알리는지, 입력 자체가 비어 있으면 일반 오류가 아니라 전용 IsoRenderInputError로 구분하는지,
// 재생성 시 이전 Orbit 카메라를 보존하는지, 미리보기/최종 품질을 결과에 그대로 남기는지 확인한다.
import 'package:ason_space/core/ss_iso_render_step.dart';
import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/iso_render_result.dart';
import 'package:ason_space/models/ss_cad_scene.dart';
import 'package:ason_space/models/ss_iso_camera_state.dart';
import 'package:ason_space/services/iso_render_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _scale = FloorPlanScale(
  mmPerPixel: 5.0,
  referenceStart: Point2(0, 0),
  referenceEnd: Point2(1, 0),
  referenceLengthMm: 5000,
  source: ScaleSource.measured,
);

CadWall _wall(String id, Point2 start, Point2 end) => CadWall(
  id: id,
  start: start,
  end: end,
  thicknessNormalized: 0.02,
  wallType: CadWallType.exterior,
  confidence: 0.9,
);

const _corners = [Point2(0.1, 0.1), Point2(0.9, 0.1), Point2(0.9, 0.9), Point2(0.1, 0.9)];

CadFloorPlan _samplePlan() => CadFloorPlan(
  sourceWidthPx: 1000,
  sourceHeightPx: 1000,
  walls: [
    _wall('n', const Point2(0.1, 0.1), const Point2(0.9, 0.1)),
    _wall('s', const Point2(0.1, 0.9), const Point2(0.9, 0.9)),
    _wall('w', const Point2(0.1, 0.1), const Point2(0.1, 0.9)),
    _wall('e', const Point2(0.9, 0.1), const Point2(0.9, 0.9)),
  ],
  openings: const [],
  rooms: const [CadRoom(id: 'room-0', polygon: _corners, areaNormalized: 0.64, confidence: 0.9)],
  warnings: const [],
);

void main() {
  const service = IsoRenderService(stepDelay: Duration.zero);

  test('완성된 ISO 디자인을 이미지 품질→재질/조명→분위기→최종 이미지→모델 반영 순서대로 렌더링한다', () async {
    final steps = <SsIsoRenderStep>[];
    final scene = SsCadScene(plan: _samplePlan(), scale: _scale);
    final result = await service.render(scene, onStep: steps.add);

    expect(steps, SsIsoRenderStep.values);
    expect(result.scene.wallMeshes, isNotEmpty);
    expect(result.scene.floorMeshes, isNotEmpty);
    expect(result.camera, isNotNull);
    expect(result.camera.distanceMm, greaterThan(0));
    expect(result.quality, SsIsoRenderQuality.full);
  });

  test('벽/공간이 전혀 없으면 입력 수정이 필요하다는 전용 오류를 던진다(일반 오류로 뭉개지 않는다)', () async {
    const emptyPlan = CadFloorPlan(sourceWidthPx: 100, sourceHeightPx: 100, walls: [], openings: [], rooms: [], warnings: []);
    const emptyScene = SsCadScene(plan: emptyPlan);
    expect(() => service.render(emptyScene), throwsA(isA<IsoRenderInputError>()));
  });

  test('이전 Orbit 카메라가 있으면 재생성해도 그대로 보존한다(사용자 디자인 데이터를 잃지 않는다)', () async {
    const previousCamera = SsIsoCameraState(targetXMm: 10, targetYMm: 20, targetZMm: 30, distanceMm: 7777, azimuthRadians: 0.3, polarRadians: 0.6);
    final scene = SsCadScene(plan: _samplePlan(), scale: _scale);
    final result = await service.render(scene, previousCamera: previousCamera);
    expect(result.camera, same(previousCamera));
  });

  test('미리보기 품질로 요청하면 결과에 그 품질이 그대로 남는다(미리보기/최종 렌더링 구분)', () async {
    final scene = SsCadScene(plan: _samplePlan(), scale: _scale);
    final result = await service.render(scene, quality: SsIsoRenderQuality.preview);
    expect(result.quality, SsIsoRenderQuality.preview);
  });
}
