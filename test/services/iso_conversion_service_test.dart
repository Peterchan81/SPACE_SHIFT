// SS012 — IsoConversionService 단위 테스트: 기존 buildSpaceSceneV2를 그대로 재사용해 "전처리→공간
// 구조 분석→건축 요소 3D 모델링→재질/색상 적용→ISO 모델 생성" 순서대로 단계를 알리는지, 입력 자체가
// 비어 있으면 일반 오류가 아니라 전용 IsoConversionInputError로 구분하는지, 재생성 시 이전 Orbit
// 카메라를 보존하는지, CAD의 가구 배치를 그대로 통과시키는지 확인한다.
import 'package:ason_space/core/ss_iso_conversion_step.dart';
import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/iso_conversion_result.dart';
import 'package:ason_space/models/ss_cad_scene.dart';
import 'package:ason_space/models/ss_iso_camera_state.dart';
import 'package:ason_space/services/iso_conversion_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _scale = FloorPlanScale(
  mmPerPixel: 5.0,
  referenceStart: Point2(0, 0),
  referenceEnd: Point2(1, 0),
  referenceLengthMm: 5000,
  source: ScaleSource.measured,
);

CadWall _wall(String id, Point2 start, Point2 end, {bool exterior = true}) => CadWall(
  id: id,
  start: start,
  end: end,
  thicknessNormalized: 0.02,
  wallType: exterior ? CadWallType.exterior : CadWallType.interior,
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
  const service = IsoConversionService(stepDelay: Duration.zero);

  test('CAD 장면을 전처리→분석→모델링→재질/색상→ISO 생성 순서대로 변환한다', () async {
    final steps = <SsIsoConversionStep>[];
    final scene = SsCadScene(plan: _samplePlan(), scale: _scale);
    final result = await service.convert(scene, onStep: steps.add);

    expect(steps, SsIsoConversionStep.values);
    expect(result.scene.wallMeshes, isNotEmpty);
    expect(result.scene.floorMeshes, isNotEmpty);
    expect(result.camera, isNotNull);
    expect(result.camera.distanceMm, greaterThan(0));
  });

  test('벽/공간이 전혀 없으면 입력 수정이 필요하다는 전용 오류를 던진다(일반 오류로 뭉개지 않는다)', () async {
    const emptyPlan = CadFloorPlan(sourceWidthPx: 100, sourceHeightPx: 100, walls: [], openings: [], rooms: [], warnings: []);
    const emptyScene = SsCadScene(plan: emptyPlan);
    expect(() => service.convert(emptyScene), throwsA(isA<IsoConversionInputError>()));
  });

  test('이전 Orbit 카메라가 있으면 재생성해도 그대로 보존한다(사용자 디자인 데이터를 잃지 않는다)', () async {
    const previousCamera = SsIsoCameraState(targetXMm: 10, targetYMm: 20, targetZMm: 30, distanceMm: 7777, azimuthRadians: 0.3, polarRadians: 0.6);
    final scene = SsCadScene(plan: _samplePlan(), scale: _scale);
    final result = await service.convert(scene, previousCamera: previousCamera);
    expect(result.camera, same(previousCamera));
  });

  test('CAD에 놓인 가구는 그대로 결과에 통과시킨다(재생성해도 소실하지 않는다)', () async {
    const furniture = SsCadFurniture(id: 'f1', kind: SsCadFurnitureKind.sofa, center: Point2(0.5, 0.5), widthNormalized: 0.1, depthNormalized: 0.1);
    final scene = SsCadScene(plan: _samplePlan(), scale: _scale, furniture: const [furniture]);
    final result = await service.convert(scene);
    expect(result.furniture, hasLength(1));
    expect(result.furniture.single.id, 'f1');
  });
}
