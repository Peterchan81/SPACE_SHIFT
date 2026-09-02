// SpaceScene V2 — Stage A~D 단계별 자동 검증(NOMPASS V2 WO 16번).
// 벽은 항상 CadWall에서 직접 만든 안정적인 직육면체이고(WO 9번), 바닥은
// 벽과 완전히 분리된 pipeline(WO 11번)이라는 두 원칙을 각 단계에서
// 직접 확인한다.
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

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

CadWall _wall(
  String id,
  Point2 start,
  Point2 end, {
  double thickness = 0.02,
  bool exterior = true,
}) {
  return CadWall(
    id: id,
    start: start,
    end: end,
    thicknessNormalized: thickness,
    wallType: exterior ? CadWallType.exterior : CadWallType.interior,
    confidence: 0.9,
  );
}

/// scene 안의 어떤 삼각형 edge도 scene 전체 대각선을 넘지 않는지 확인한다
/// — "거대 삼각형/쐐기" 사고 재발을 막는 공통 assertion(Stage E/F와 동일
/// 기준).
void expectNoGiantTriangles(
  List<vm.Vector3> minMax,
  Iterable<SpaceTriangleV2> tris,
) {
  final diagonal = (minMax[1] - minMax[0]).length;
  for (final t in tris) {
    final longest = [
      (t.b - t.a).length,
      (t.c - t.b).length,
      (t.a - t.c).length,
    ].reduce((x, y) => x > y ? x : y);
    expect(longest, lessThanOrEqualTo(diagonal * 1.01 + 1));
  }
}

void main() {
  group('Stage A — 벽 1개', () {
    test('안정적인 직육면체(8 vertex, 10 triangle, 찢김 0)를 만든다', () {
      final plan = CadFloorPlan(
        sourceWidthPx: 1000,
        sourceHeightPx: 1000,
        walls: [
          _wall('wall-0', const Point2(0.1, 0.1), const Point2(0.9, 0.1)),
        ],
        openings: const [],
        rooms: const [],
        warnings: const [],
      );
      final scene = buildSpaceSceneV2(
        plan: plan,
        scale: _scale,
        ceilingHeightMm: 2400,
      );

      expect(scene.wallMeshes, hasLength(1));
      final wall = scene.wallMeshes.single;
      expect(
        wall.triangles,
        hasLength(10),
        reason: '5 quad(top/outer/inner/start cap/end cap) x 2 triangle.',
      );
      expect(wall.identity.dimensions!.heightMm, closeTo(2400, 1e-6));
      expect(
        wall.identity.dimensions!.widthMm,
        closeTo(4000, 1e-6),
      ); // 0.8*1000*5mm.
      expect(
        wall.identity.dimensions!.thicknessMm,
        closeTo(100, 1e-6),
      ); // 0.02*1000(h축)*5mm.

      final uniqueVertices = <String>{};
      for (final t in wall.triangles) {
        for (final v in [t.a, t.b, t.c]) {
          uniqueVertices.add('${v.x.round()},${v.y.round()},${v.z.round()}');
        }
      }
      expect(
        uniqueVertices,
        hasLength(8),
        reason: '직육면체는 정확히 8개의 서로 다른 vertex를 가진다.',
      );

      for (final t in wall.triangles) {
        expect(t.normal.length, closeTo(1.0, 1e-6));
      }
      expect(scene.warnings.where((w) => w.contains('비정상')), isEmpty);
    });

    test('길이가 0인 벽은 조용히 제외된다(찢어진 geometry 대신)', () {
      final plan = CadFloorPlan(
        sourceWidthPx: 1000,
        sourceHeightPx: 1000,
        walls: [
          _wall('degenerate', const Point2(0.5, 0.5), const Point2(0.5, 0.5)),
        ],
        openings: const [],
        rooms: const [],
        warnings: const [],
      );
      final scene = buildSpaceSceneV2(
        plan: plan,
        scale: _scale,
        ceilingHeightMm: 2400,
      );
      expect(scene.wallMeshes, isEmpty);
      expect(scene.isEmpty, isTrue);
    });
  });

  group('Stage B — 사각형 방 1개', () {
    test('바닥 1개 + 벽 4개를 만든다', () {
      const corners = [
        Point2(0.1, 0.1),
        Point2(0.9, 0.1),
        Point2(0.9, 0.9),
        Point2(0.1, 0.9),
      ];
      final plan = CadFloorPlan(
        sourceWidthPx: 1000,
        sourceHeightPx: 1000,
        walls: [
          _wall('n', const Point2(0.1, 0.1), const Point2(0.9, 0.1)),
          _wall('s', const Point2(0.1, 0.9), const Point2(0.9, 0.9)),
          _wall('w', const Point2(0.1, 0.1), const Point2(0.1, 0.9)),
          _wall('e', const Point2(0.9, 0.1), const Point2(0.9, 0.9)),
        ],
        openings: const [],
        rooms: const [
          CadRoom(
            id: 'room-0',
            polygon: corners,
            areaNormalized: 0.64,
            confidence: 0.9,
          ),
        ],
        warnings: const [],
      );
      final scene = buildSpaceSceneV2(
        plan: plan,
        scale: _scale,
        ceilingHeightMm: 2400,
      );

      expect(scene.wallMeshes, hasLength(4));
      expect(scene.floorMeshes, hasLength(1));
      final floor = scene.floorMeshes.single;
      expect(floor.triangles, isNotEmpty);
      for (final t in floor.triangles) {
        expect(t.normal.y, greaterThan(0), reason: '바닥 법선은 항상 +Y로 고정된다.');
      }
      expect(scene.warnings.where((w) => w.contains('비정상')), isEmpty);
    });
  });

  group('Stage C — 방 2개 + 공유 내벽', () {
    test('내벽이 정상적으로 두 방 사이에 생성된다', () {
      final plan = CadFloorPlan(
        sourceWidthPx: 1000,
        sourceHeightPx: 1000,
        walls: [
          _wall('n', const Point2(0.1, 0.1), const Point2(0.9, 0.1)),
          _wall('s', const Point2(0.1, 0.9), const Point2(0.9, 0.9)),
          _wall('w', const Point2(0.1, 0.1), const Point2(0.1, 0.9)),
          _wall('e', const Point2(0.9, 0.1), const Point2(0.9, 0.9)),
          _wall(
            'mid',
            const Point2(0.5, 0.1),
            const Point2(0.5, 0.9),
            exterior: false,
          ),
        ],
        openings: const [],
        rooms: const [
          CadRoom(
            id: 'left',
            polygon: [
              Point2(0.1, 0.1),
              Point2(0.5, 0.1),
              Point2(0.5, 0.9),
              Point2(0.1, 0.9),
            ],
            areaNormalized: 0.32,
            confidence: 0.9,
          ),
          CadRoom(
            id: 'right',
            polygon: [
              Point2(0.5, 0.1),
              Point2(0.9, 0.1),
              Point2(0.9, 0.9),
              Point2(0.5, 0.9),
            ],
            areaNormalized: 0.32,
            confidence: 0.9,
          ),
        ],
        warnings: const [],
      );
      final scene = buildSpaceSceneV2(
        plan: plan,
        scale: _scale,
        ceilingHeightMm: 2400,
      );

      expect(scene.wallMeshes, hasLength(5));
      expect(scene.floorMeshes, hasLength(2));
      expectNoGiantTriangles(
        [scene.minBounds, scene.maxBounds],
        scene.wallMeshes
            .expand((w) => w.triangles)
            .followedBy(scene.floorMeshes.expand((f) => f.triangles)),
      );
      expect(scene.warnings.where((w) => w.contains('비정상')), isEmpty);
    });
  });

  group('Stage D — L자 구조', () {
    test('오목한 L자 방 junction이 찢어지지 않고 정상 삼각분할된다', () {
      // L자(6점, 오목 코너 1개) — 우측 상단이 잘려나간 형태.
      const lShape = [
        Point2(0.1, 0.1),
        Point2(0.9, 0.1),
        Point2(0.9, 0.5),
        Point2(0.5, 0.5),
        Point2(0.5, 0.9),
        Point2(0.1, 0.9),
      ];
      final plan = CadFloorPlan(
        sourceWidthPx: 1000,
        sourceHeightPx: 1000,
        walls: [
          for (var i = 0; i < lShape.length; i++)
            _wall('w$i', lShape[i], lShape[(i + 1) % lShape.length]),
        ],
        openings: const [],
        rooms: const [
          CadRoom(
            id: 'l-room',
            polygon: lShape,
            areaNormalized: 0.48,
            confidence: 0.9,
          ),
        ],
        warnings: const [],
      );
      final scene = buildSpaceSceneV2(
        plan: plan,
        scale: _scale,
        ceilingHeightMm: 2400,
      );

      expect(scene.wallMeshes, hasLength(6));
      expect(scene.floorMeshes, hasLength(1));
      // n점 단순 다각형은 항상 n-2개의 삼각형으로 나뉜다(6점 → 4개).
      expect(scene.floorMeshes.single.triangles, hasLength(4));
      expectNoGiantTriangles(
        [scene.minBounds, scene.maxBounds],
        scene.wallMeshes
            .expand((w) => w.triangles)
            .followedBy(scene.floorMeshes.expand((f) => f.triangles)),
      );
      expect(scene.warnings.where((w) => w.contains('비정상')), isEmpty);
    });
  });

  group('Floor isolation(WO 11번) — invalid floor가 벽을 깨뜨리지 않는다', () {
    test('자기교차하는 room polygon은 바닥 없이 건너뛰고, 벽은 정상 생성된다', () {
      final plan = CadFloorPlan(
        sourceWidthPx: 1000,
        sourceHeightPx: 1000,
        walls: [
          _wall('n', const Point2(0.1, 0.1), const Point2(0.9, 0.1)),
          _wall('s', const Point2(0.1, 0.9), const Point2(0.9, 0.9)),
          _wall('w', const Point2(0.1, 0.1), const Point2(0.1, 0.9)),
          _wall('e', const Point2(0.9, 0.1), const Point2(0.9, 0.9)),
        ],
        openings: const [],
        rooms: const [
          // bowtie(자기교차) — 유효하지 않은 polygon.
          CadRoom(
            id: 'broken',
            polygon: [
              Point2(0.1, 0.1),
              Point2(0.9, 0.9),
              Point2(0.9, 0.1),
              Point2(0.1, 0.9),
            ],
            areaNormalized: 0.5,
            confidence: 0.9,
          ),
        ],
        warnings: const [],
      );
      final scene = buildSpaceSceneV2(
        plan: plan,
        scale: _scale,
        ceilingHeightMm: 2400,
      );

      expect(
        scene.wallMeshes,
        hasLength(4),
        reason: '바닥이 깨져도 벽 4개는 정상 생성돼야 한다.',
      );
      expect(scene.floorMeshes, isEmpty);
    });

    test('유효한 room과 무효한 room이 섞여 있으면 유효한 쪽만 바닥이 생긴다', () {
      final plan = CadFloorPlan(
        sourceWidthPx: 1000,
        sourceHeightPx: 1000,
        walls: [
          _wall('n', const Point2(0.1, 0.1), const Point2(0.9, 0.1)),
          _wall('s', const Point2(0.1, 0.9), const Point2(0.9, 0.9)),
        ],
        openings: const [],
        rooms: const [
          CadRoom(
            id: 'broken',
            polygon: [
              Point2(0.1, 0.1),
              Point2(0.9, 0.9),
              Point2(0.9, 0.1),
              Point2(0.1, 0.9),
            ],
            areaNormalized: 0.5,
            confidence: 0.9,
          ),
          CadRoom(
            id: 'ok',
            polygon: [
              Point2(0.1, 0.1),
              Point2(0.5, 0.1),
              Point2(0.5, 0.5),
              Point2(0.1, 0.5),
            ],
            areaNormalized: 0.16,
            confidence: 0.9,
          ),
        ],
        warnings: const [],
      );
      final scene = buildSpaceSceneV2(
        plan: plan,
        scale: _scale,
        ceilingHeightMm: 2400,
      );
      expect(scene.floorMeshes, hasLength(1));
      expect(scene.floorMeshes.single.roomId, 'ok');
      expect(scene.wallMeshes, hasLength(2));
    });
  });
}
