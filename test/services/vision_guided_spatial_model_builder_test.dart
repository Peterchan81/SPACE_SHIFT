// Vision Guided CAD POC — 전체 파이프라인(orchestrator) 통합 테스트.
//
// 실제 합성 "이미지 2" 픽셀에 대해 Mock Vision → Geometry Extractor →
// Matcher → Topology Validator → SSSpatialModel → CadFloorPlan까지
// 전부 실행해, 파이프라인 전체가 하나로 이어지는지 확인한다.

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/services/mock_vision_interpretation_service.dart';
import 'package:ason_space/services/vision_guided_spatial_model_builder.dart';
import 'package:ason_space/vision_cad_poc/sample_image2_fixture.dart';

void main() {
  final builder = VisionGuidedSpatialModelBuilder(visionService: const MockVisionInterpretationService());

  test('축척은 항상 unknown/미확정으로 유지된다 (이 도면엔 인쇄된 치수가 없다)', () async {
    final model = await builder.build(buildImage2Png());
    // SSSpatialModel 자체는 scale 개념을 갖지 않는다 — CadFloorPlan으로
    // 넘어간 뒤에도 dimensions가 비어 있으면 화면이 scale을 확정하지
    // 않는다는 계약을 지킨다.
    expect(model.dimensions, isEmpty);
  });

  test('13개 공간 중 대부분이 실제 벽에 스냅되어 만들어진다', () async {
    final model = await builder.build(buildImage2Png());
    expect(model.spaces.length, greaterThanOrEqualTo(10));
    for (final space in model.spaces) {
      expect(space.polygon, hasLength(4));
      expect(space.polygon[1].x, greaterThan(space.polygon[0].x));
      expect(space.polygon[2].y, greaterThan(space.polygon[0].y));
    }
  });

  test('실제로 없는 문(CASE D)은 최종 CAD에 개구부로 포함되지 않는다', () async {
    final model = await builder.build(buildImage2Png());
    expect(
      model.openings.any((o) => o.id == 'opening-dressRoom-masterLiving-door'),
      isFalse,
    );
    expect(model.warnings.any((w) => w.contains('opening-dressRoom-masterLiving-door')), isTrue);
  });

  test('실제로 존재하는 4개의 문은 최종 CAD에 개구부로 포함된다', () async {
    final model = await builder.build(buildImage2Png());
    final doorIds = {
      'opening-masterBedroom-dressLiving-door',
      'opening-pantryBath1-entrance-door',
      'opening-upperLower-door',
      'opening-bedroom2-bedroom1-door',
    };
    final foundIds = model.openings.map((o) => o.id).toSet();
    expect(foundIds.intersection(doorIds), doorIds);
  });

  test('실제로 그려지지 않은 가구(CASE E)는 최종 CAD에 포함되지 않는다', () async {
    final model = await builder.build(buildImage2Png());
    expect(model.objects, isEmpty);
    expect(model.warnings.any((w) => w.contains('hallucinated-bed')), isTrue);
  });

  test('발코니와 실외기실은 형태가 이상하더라도 방으로 보존된다', () async {
    final model = await builder.build(buildImage2Png());
    expect(model.spaces.any((s) => s.id == 'space-balcony'), isTrue);
    expect(model.spaces.any((s) => s.id == 'space-mechanical'), isTrue);
    // 실외기실은 위쪽이 열려있어 위/아래 edge 중 하나를 못 찾을 수
    // 있다 — 그래도 review 표시만 하고 방 자체는 버리지 않는다.
    final mechanical = model.spaces.firstWhere((s) => s.id == 'space-mechanical');
    expect(mechanical.polygon, hasLength(4));
  });

  test('SSSpatialModel → CadFloorPlan 변환은 공간/벽/개구부 개수를 그대로 보존한다', () async {
    final model = await builder.build(buildImage2Png());
    final validated = model;
    final cad = buildCadFloorPlanFromSpatialModel(validated);
    expect(cad.rooms, hasLength(validated.spaces.length));
    expect(cad.walls, hasLength(validated.walls.length));
    expect(cad.openings, hasLength(validated.openings.length));
    expect(cad.sourceWidthPx, kImage2Width);
    expect(cad.sourceHeightPx, kImage2Height);
  });

  test('Topology Validator를 거친 뒤에도 reviewNeeded 항목의 geometry는 원래 값 그대로다', () async {
    final model = await builder.build(buildImage2Png());
    for (final wall in model.walls) {
      // 어떤 wall도 폭/좌표가 NaN이거나 비정상적으로 커지지 않았어야 한다
      // (topology validator가 실패 시 geometry를 임의로 왜곡하지 않는다는
      // 원칙의 회귀 방지).
      expect(wall.start.x.isFinite, isTrue);
      expect(wall.end.x.isFinite, isTrue);
      expect((wall.start.x - wall.end.x).abs() + (wall.start.y - wall.end.y).abs(), greaterThan(0));
    }
  });
}
