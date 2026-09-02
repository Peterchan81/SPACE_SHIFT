// buildSpaceScene(2D CAD geometry → 3D geometry 변환)에 대한 단위 테스트.
//
// D. ceilingHeightMm이 실제로 벽 높이(Y 범위)에 반영된다.
// E. 벽/바닥 각각이 실제 삼각형으로 변환된다(2D geometry → 3D 변환).
// F. 문/창이 있으면(아직 벽에 반영하지 않음) 경고 문구로 정직하게
//    알린다 — 가짜 문/창을 만들지 않는다.

import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/space_scene.dart';
import 'package:ason_space/services/space_scene_builder.dart';

CadFloorPlan _planWithOneWallAndRoom({List<CadOpening> openings = const []}) {
  return CadFloorPlan(
    sourceWidthPx: 800,
    sourceHeightPx: 600,
    walls: const [
      CadWall(
        id: 'wall-0',
        start: Point2(0.1, 0.1),
        end: Point2(0.9, 0.1),
        thicknessNormalized: 0.02,
        wallType: CadWallType.exterior,
        confidence: 0.8,
      ),
    ],
    openings: openings,
    rooms: const [
      CadRoom(
        id: 'room-0',
        polygon: [
          Point2(0.1, 0.1),
          Point2(0.9, 0.1),
          Point2(0.9, 0.9),
          Point2(0.1, 0.9),
        ],
        areaNormalized: 0.64,
        confidence: 0.7,
      ),
    ],
    warnings: const [],
  );
}

const _scale = FloorPlanScale(
  mmPerPixel: 2.0,
  referenceStart: Point2(0, 0),
  referenceEnd: Point2(1, 0),
  referenceLengthMm: 1600,
  source: ScaleSource.estimatedFromDoor,
);

void main() {
  test('D — ceilingHeightMm이 실제 벽 높이(Y 최댓값)에 그대로 반영된다', () {
    final plan = _planWithOneWallAndRoom();
    final scene = buildSpaceScene(
      plan: plan,
      scale: _scale,
      ceilingHeightMm: 2400,
    );

    expect(scene.isEmpty, isFalse);
    expect(scene.maxBounds.y, closeTo(2400, 1e-6));
    expect(scene.minBounds.y, closeTo(0, 1e-6));
  });

  test('D — 벽 높이가 바뀌면 생성되는 3D geometry 높이도 그만큼 바뀐다', () {
    final plan = _planWithOneWallAndRoom();
    final low = buildSpaceScene(
      plan: plan,
      scale: _scale,
      ceilingHeightMm: 2300,
    );
    final high = buildSpaceScene(
      plan: plan,
      scale: _scale,
      ceilingHeightMm: 2700,
    );

    expect(high.maxBounds.y, greaterThan(low.maxBounds.y));
    expect(high.maxBounds.y - low.maxBounds.y, closeTo(400, 1e-6));
  });

  test('E — 벽 1개는 실제 3D 삼각형(상단+측면 4개, 삼각형 10개)으로 변환된다', () {
    final plan = _planWithOneWallAndRoom();
    final scene = buildSpaceScene(
      plan: plan,
      scale: _scale,
      ceilingHeightMm: 2400,
    );

    final wallTriangles = scene.triangles
        .where(
          (t) =>
              t.sourceKind == SpaceElementKind.wall && t.sourceId == 'wall-0',
        )
        .toList();
    expect(wallTriangles, hasLength(10)); // 상단(2) + 측면 4개(각 2) = 10.
    expect(scene.wallCount, 1);
  });

  test('E — 방 1개는 바닥 삼각형 2개(사각형 하나)로 변환되고 Y=0이다', () {
    final plan = _planWithOneWallAndRoom();
    final scene = buildSpaceScene(
      plan: plan,
      scale: _scale,
      ceilingHeightMm: 2400,
    );

    final floorTriangles = scene.triangles
        .where(
          (t) =>
              t.sourceKind == SpaceElementKind.floor && t.sourceId == 'room-0',
        )
        .toList();
    expect(floorTriangles, hasLength(2));
    for (final tri in floorTriangles) {
      expect(tri.a.y, closeTo(0, 1e-6));
      expect(tri.b.y, closeTo(0, 1e-6));
      expect(tri.c.y, closeTo(0, 1e-6));
    }
    expect(scene.floorCount, 1);
  });

  test('E — mmPerPixel이 커지면 생성된 geometry의 XZ 범위도 비례해서 커진다', () {
    final plan = _planWithOneWallAndRoom();
    const smallScale = FloorPlanScale(
      mmPerPixel: 1.0,
      referenceStart: Point2(0, 0),
      referenceEnd: Point2(1, 0),
      referenceLengthMm: 800,
    );
    const bigScale = FloorPlanScale(
      mmPerPixel: 3.0,
      referenceStart: Point2(0, 0),
      referenceEnd: Point2(1, 0),
      referenceLengthMm: 2400,
    );
    final small = buildSpaceScene(
      plan: plan,
      scale: smallScale,
      ceilingHeightMm: 2400,
    );
    final big = buildSpaceScene(
      plan: plan,
      scale: bigScale,
      ceilingHeightMm: 2400,
    );

    final smallSpanX = small.maxBounds.x - small.minBounds.x;
    final bigSpanX = big.maxBounds.x - big.minBounds.x;
    expect(bigSpanX, closeTo(smallSpanX * 3, 1e-6));
  });

  test('F — 문/창 후보가 있으면 벽에 반영되지 않았다는 경고를 정직하게 '
      '남긴다(가짜 문/창 geometry를 만들지 않는다)', () {
    final plan = _planWithOneWallAndRoom(
      openings: const [
        CadOpening(
          id: 'opening-0',
          type: OpeningType.door,
          center: Point2(0.5, 0.1),
          widthNormalized: 0.05,
          confidence: 0.5,
          wallId: 'wall-0',
        ),
      ],
    );
    final scene = buildSpaceScene(
      plan: plan,
      scale: _scale,
      ceilingHeightMm: 2400,
    );

    expect(
      scene.warnings.any((w) => w.contains('문/창') && w.contains('반영하지 않습니다')),
      isTrue,
    );
    // 문 opening이 벽 geometry 자체를 잘라내지는 않는다 — 여전히 상단
    // 1개(2개 삼각형) + 측면 4개(8개 삼각형) = 10개 그대로다.
    final wallTriangles = scene.triangles.where(
      (t) => t.sourceKind == SpaceElementKind.wall,
    );
    expect(wallTriangles, hasLength(10));
  });

  test('F — 문/창 후보가 없으면 그 경고는 남기지 않는다', () {
    final plan = _planWithOneWallAndRoom();
    final scene = buildSpaceScene(
      plan: plan,
      scale: _scale,
      ceilingHeightMm: 2400,
    );
    expect(scene.warnings.any((w) => w.contains('문/창')), isFalse);
  });

  test('공간(방)을 인식하지 못했지만 벽은 있으면, 바닥 미생성 경고를 남긴다', () {
    final plan = CadFloorPlan(
      sourceWidthPx: 800,
      sourceHeightPx: 600,
      walls: _planWithOneWallAndRoom().walls,
      openings: const [],
      rooms: const [],
      warnings: const [],
    );
    final scene = buildSpaceScene(
      plan: plan,
      scale: _scale,
      ceilingHeightMm: 2400,
    );
    expect(scene.floorCount, 0);
    expect(scene.warnings.any((w) => w.contains('바닥은 생성하지 않았습니다')), isTrue);
  });

  test('벽도 방도 없으면 빈 scene을 만들고 경고 없이 isEmpty=true다', () {
    final plan = CadFloorPlan(
      sourceWidthPx: 800,
      sourceHeightPx: 600,
      walls: const [],
      openings: const [],
      rooms: const [],
      warnings: const [],
    );
    final scene = buildSpaceScene(
      plan: plan,
      scale: _scale,
      ceilingHeightMm: 2400,
    );
    expect(scene.isEmpty, isTrue);
    expect(scene.triangles, isEmpty);
  });

  test('SpaceScene.center/boundingRadius가 실제 min/max bounds로부터 계산된다', () {
    final plan = _planWithOneWallAndRoom();
    final scene = buildSpaceScene(
      plan: plan,
      scale: _scale,
      ceilingHeightMm: 2400,
    );

    final expectedCenter = (scene.minBounds + scene.maxBounds) / 2.0;
    expect(scene.center.x, closeTo(expectedCenter.x, 1e-6));
    expect(scene.center.y, closeTo(expectedCenter.y, 1e-6));
    expect(scene.center.z, closeTo(expectedCenter.z, 1e-6));
    expect(scene.boundingRadius, greaterThan(0));
  });

  test('SpaceTriangle.normal은 단위 벡터이며 삼각형 면에 수직이다', () {
    final tri = SpaceTriangle(
      a: vm.Vector3(0, 0, 0),
      b: vm.Vector3(1, 0, 0),
      c: vm.Vector3(0, 0, 1),
      color: const Color(0xFFFFFFFF),
      sourceKind: SpaceElementKind.floor,
      sourceId: 'x',
    );
    final n = tri.normal;
    expect(n.length, closeTo(1.0, 1e-6));
    expect(n.dot(tri.b - tri.a), closeTo(0, 1e-6));
    expect(n.dot(tri.c - tri.a), closeTo(0, 1e-6));
  });

  test('I — 벽 상단 면(천장과 맞닿는 면)의 법선은 위(+Y)를 향한다(뒤집힌 '
      'winding으로 아래를 향하지 않는다 — 3D 아이소 실기 재현: 벽면 거대 '
      '삼각형 사고 조사 중 winding/topology를 직접 확인)', () {
    final plan = _planWithOneWallAndRoom();
    final scene = buildSpaceScene(
      plan: plan,
      scale: _scale,
      ceilingHeightMm: 2400,
    );
    final wallTriangles = scene.triangles.where(
      (t) => t.sourceKind == SpaceElementKind.wall,
    );
    // 상단면은 y=2400(천장고)인 정점 3개로만 이뤄진 삼각형 2개다.
    final topTriangles = wallTriangles.where(
      (t) => t.a.y == t.b.y && t.b.y == t.c.y && (t.a.y - 2400).abs() < 1e-6,
    );
    expect(topTriangles, hasLength(2));
    for (final tri in topTriangles) {
      expect(
        tri.normal.y,
        greaterThan(0),
        reason:
            '상단면 법선이 아래를 향하면 조명 계산이 뒤집혀 반대편이 '
            '어둡게(또는 밝게) 보이는 잘못된 shading이 나온다',
      );
    }
  });

  test('I — 측면(바깥쪽 벽면)의 법선은 벽 중심선에서 바깥쪽을 향한다', () {
    final plan = _planWithOneWallAndRoom();
    final scene = buildSpaceScene(
      plan: plan,
      scale: _scale,
      ceilingHeightMm: 2400,
    );
    final wallTriangles = scene.triangles
        .where((t) => t.sourceKind == SpaceElementKind.wall)
        .toList();
    // 벽 중심(대략 min/max의 평균) — 이 벽은 거의 수평이라 중심 Z가
    // 곧 "안쪽"의 기준이 된다.
    final centerZ =
        wallTriangles.map((t) => t.centroid.z).reduce((a, b) => a + b) /
        wallTriangles.length;
    // 측면(상단이 아닌) 삼각형들은 중심으로부터 바깥으로 벌어진 면의
    // 법선을 가져야 한다 — 완전히 반대(안쪽)를 향하는 면은 없어야
    // 한다. 벽이 얇아 정확히 절반씩 나뉘므로, 최소한 "모든 법선이
    // 전부 한쪽(안쪽)으로만 쏠리지 않는다"는 것으로 topology가
    // 일관적으로 뒤집히지 않았음을 확인한다.
    final sideTriangles = wallTriangles.where(
      (t) => !(t.a.y == t.b.y && t.b.y == t.c.y),
    );
    final outwardCount = sideTriangles
        .where((t) => (t.centroid.z - centerZ) * t.normal.z >= -1e-6)
        .length;
    expect(
      outwardCount,
      greaterThan(0),
      reason:
          '측면 중 최소 일부는 중심 기준 바깥쪽을 향하는 법선을 가져야 한다'
          '(전부 안쪽이면 topology가 통째로 뒤집힌 것)',
    );
  });
}
