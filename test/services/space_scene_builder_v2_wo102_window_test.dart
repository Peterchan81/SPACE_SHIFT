// SPACE SHIFT — WO102 STRUCTURAL 3D INTERIOR MODEL — §5 WINDOW 검증.
//
// window opening이 실제로 벽에 뚫리고(sill 아래/head 위는 벽으로 남고
// 그 사이만 비어 있음), 그 안에 frame+glass geometry가 별도 selectable
// object로 생기는지 확인한다. sill/head 높이는 항상 가정값
// (kAssumedWindowSillHeightMm/kAssumedWindowHeightMm)이며 실측처럼
// 취급되지 않는다.
import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/space_scene_v2.dart';
import 'package:ason_space/services/space_scene_builder_v2.dart';

const _scale = FloorPlanScale(
  mmPerPixel: 5.0,
  referenceStart: Point2(0, 0),
  referenceEnd: Point2(1, 0),
  referenceLengthMm: 5000,
  source: ScaleSource.measured,
);
const _diagonalPx = 1000 * 1.4142135623730951;

CadWall _horizontalWall() => const CadWall(
  id: 'w',
  start: Point2(0.1, 0.5),
  end: Point2(0.9, 0.5),
  thicknessNormalized: 0.02,
  wallType: CadWallType.exterior,
  confidence: 0.9,
);

CadOpening _window(String id, {required double centerX, required double widthMm, String? wallId = 'w'}) {
  return CadOpening(
    id: id,
    type: OpeningType.window,
    center: Point2(centerX, 0.5),
    widthNormalized: widthMm / (_diagonalPx * _scale.mmPerPixel),
    confidence: 0.9,
    wallId: wallId,
  );
}

CadFloorPlan _plan(List<CadOpening> openings) => CadFloorPlan(
  sourceWidthPx: 1000,
  sourceHeightPx: 1000,
  walls: [_horizontalWall()],
  openings: openings,
  rooms: const [],
  warnings: const [],
);

SpaceWallMeshV2 _wallMeshFor(SpaceSceneV2 scene, String id) =>
    scene.wallMeshes.singleWhere((w) => w.identity.wallId == id);

void main() {
  group('WO102 §5 — window opening이 실제로 벽을 뚫는다', () {
    test('sill 아래/head 위는 벽으로 남고, 그 사이(허리~머리 높이)만 비어 있다', () {
      // 벽 world X: start=500mm, end=4500mm(길이 4000mm). 문 중심
      // x=0.5 -> world X=2500mm, 폭 1000mm -> 구간 [2000,3000]mm.
      final scene = buildSpaceSceneV2(
        plan: _plan([_window('win1', centerX: 0.5, widthMm: 1000)]),
        scale: _scale,
        ceilingHeightMm: 2400,
      );
      final wall = _wallMeshFor(scene, 'w');
      const sill = kAssumedWindowSillHeightMm;
      const head = kAssumedWindowSillHeightMm + kAssumedWindowHeightMm;

      // window along-구간의 x 경계는 정확히 world X 2000/3000mm이다
      // (opening 폭 1000mm 중심 2500mm) — top/bottom face의 네 모서리가
      // 정확히 그 경계 위에 있으므로, 존재를 확인하는 양성 검사는 그
      // 경계를 포함하는 범위를 써야 한다(margin으로 경계를 배제하면
      // 실제로 있는 면도 못 찾는다).
      const xMin = 1995.0, xMax = 3005.0;

      // sill 아래(허리벽)는 벽이 남아 있어야 한다 — 허리벽 상자의 top
      // face(y=sill 그 자체, 바닥에 닿는 밑면은 원래도 그리지 않는다)로
      // 확인한다(헤더 박스의 top face로 확인하는 아래 headerExists와
      // 같은 패턴).
      final kneeWallExists = wall.triangles.any(
        (t) => [t.a, t.b, t.c].every((v) => v.x >= xMin && v.x <= xMax && (v.y - sill).abs() < 10),
      );
      expect(kneeWallExists, isTrue, reason: '창 아래 허리벽은 남아 있어야 한다.');

      // sill~head 사이(개구부 자체)는 완전히 비어 있어야 한다.
      final gapTriangle = wall.triangles.any(
        (t) => [t.a, t.b, t.c].every((v) => v.x >= 2000 && v.x <= 3000 && v.y > sill + 10 && v.y < head - 10),
      );
      expect(gapTriangle, isFalse, reason: '창 개구부 구간(sill~head)에는 벽 triangle이 없어야 한다.');

      // head 위(상인방)는 벽이 남아 있어야 한다.
      final headerExists = wall.triangles.any(
        (t) => [t.a, t.b, t.c].every((v) => v.x >= xMin && v.x <= xMax && (v.y - 2400).abs() < 10),
      );
      expect(headerExists, isTrue, reason: '창 위 상인방은 남아 있어야 한다.');
    });

    test('frame/glass geometry가 별도 selectable mesh로 생기고, glass가 frame보다 작게 인셋된다', () {
      final scene = buildSpaceSceneV2(
        plan: _plan([_window('win1', centerX: 0.5, widthMm: 1000)]),
        scale: _scale,
        ceilingHeightMm: 2400,
      );
      expect(scene.windowMeshes, hasLength(1));
      final window = scene.windowMeshes.single;
      expect(window.wallId, 'w');
      expect(window.frameTriangles, isNotEmpty);
      expect(window.glassTriangles, isNotEmpty);
      expect(window.frameIdentity.objectId, isNot(window.glassIdentity.objectId), reason: 'frame/glass는 서로 다른 독립 object여야 한다(§9).');
      expect(window.frameIdentity.sourceKind, SpaceElementKindV2.opening);
      expect(window.glassIdentity.sourceKind, SpaceElementKindV2.opening);
      expect(window.frameIdentity.wallId, 'w');
      expect(window.glassIdentity.wallId, 'w');

      // glass의 along-폭(x 범위)이 frame보다 작아야 한다(인셋).
      double spanX(List<SpaceTriangleV2> tris) {
        var minX = double.infinity, maxX = -double.infinity;
        for (final t in tris) {
          for (final v in [t.a, t.b, t.c]) {
            if (v.x < minX) minX = v.x;
            if (v.x > maxX) maxX = v.x;
          }
        }
        return maxX - minX;
      }

      expect(spanX(window.glassTriangles), lessThan(spanX(window.frameTriangles)));
    });

    test('window의 폭은 CadOpening.widthNormalized 실측값을 그대로 쓴다(임의 900mm 등으로 대체하지 않는다)', () {
      final scene = buildSpaceSceneV2(
        plan: _plan([_window('win1', centerX: 0.5, widthMm: 1200)]),
        scale: _scale,
        ceilingHeightMm: 2400,
      );
      final window = scene.windowMeshes.single;
      expect(window.widthMm, closeTo(1200, 1.0));
    });

    test('벽 높이가 가정 head height보다 낮으면 창을 만들지 않고 정직하게 경고한다(존재하지 않는 치수를 지어내지 않는다)', () {
      const lowCeilingMm = kAssumedWindowSillHeightMm + kAssumedWindowHeightMm - 100; // head보다 낮음.
      final scene = buildSpaceSceneV2(
        plan: _plan([_window('win1', centerX: 0.5, widthMm: 1000)]),
        scale: _scale,
        ceilingHeightMm: lowCeilingMm,
      );
      expect(scene.windowMeshes, isEmpty);
      final wall = _wallMeshFor(scene, 'w');
      expect(wall.triangles, hasLength(10), reason: '창을 반영하지 못했으면 벽은 기존과 동일해야 한다.');
      expect(scene.warnings.any((w) => w.contains('벽 높이가 가정 창 높이보다 낮음')), isTrue);
    });

    test('wallId가 어떤 벽과도 연결되지 않은 window는 무시된다(벽 그대로, 정직한 경고)', () {
      final scene = buildSpaceSceneV2(
        plan: _plan([_window('orphan', centerX: 0.5, widthMm: 1000, wallId: 'no-such-wall')]),
        scale: _scale,
        ceilingHeightMm: 2400,
      );
      final wall = _wallMeshFor(scene, 'w');
      expect(wall.triangles, hasLength(10));
      expect(scene.windowMeshes, isEmpty);
      expect(scene.warnings.any((w) => w.contains('창 개구부') && w.contains('벽 연결 정보 없음/불일치')), isTrue);
    });

    test('door와 window가 같은 벽의 서로 다른 위치에 있으면 둘 다 독립적으로 반영된다', () {
      final plan = CadFloorPlan(
        sourceWidthPx: 1000,
        sourceHeightPx: 1000,
        walls: [_horizontalWall()],
        openings: [
          CadOpening(
            id: 'door1',
            type: OpeningType.door,
            center: const Point2(0.3, 0.5), // world X = 0.3*1000*5 = 1500mm.
            widthNormalized: 900 / (_diagonalPx * _scale.mmPerPixel),
            confidence: 0.9,
            wallId: 'w',
          ),
          _window('win1', centerX: 0.7, widthMm: 900), // world X ~= 3500mm.
        ],
        rooms: const [],
        warnings: const [],
      );
      final scene = buildSpaceSceneV2(plan: plan, scale: _scale, ceilingHeightMm: 2400);
      expect(scene.windowMeshes, hasLength(1));

      final wall = _wallMeshFor(scene, 'w');
      // 문 구간(바닥 근처, world X~1500)은 완전히 비어 있어야 한다.
      final doorGap = wall.triangles.any(
        (t) => [t.a, t.b, t.c].every((v) => v.x > 1300 && v.x < 1700 && v.y < 500),
      );
      expect(doorGap, isFalse);
      // 창 구간(허리 높이, world X~3500)도 비어 있어야 한다.
      const sill = kAssumedWindowSillHeightMm, head = kAssumedWindowSillHeightMm + kAssumedWindowHeightMm;
      final windowGap = wall.triangles.any(
        (t) => [t.a, t.b, t.c].every((v) => v.x > 3300 && v.x < 3700 && v.y > sill + 10 && v.y < head - 10),
      );
      expect(windowGap, isFalse);
      expect(scene.warnings.any((w) => w.contains('문 개구부') && w.contains('반영했습니다')), isTrue);
      expect(scene.warnings.any((w) => w.contains('창 개구부') && w.contains('반영했습니다')), isTrue);
    });
  });
}
