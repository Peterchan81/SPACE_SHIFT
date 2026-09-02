// SpaceScene V2 렌더러 — NOMPASS V2 WO(13/14/15번): "실제 depth-buffer
// 기반" 렌더링의 핵심 수학(barycentricInvDepthAt)과 tile 격자 크기 계산을
// 단위 테스트하고, [Space3DViewV2] 위젯이 실제 scene을 예외 없이 그리는지
// 스모크 테스트로 확인한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/services/space_scene_builder_v2.dart';
import 'package:ason_space/widgets/workspace/space_3d_view_v2.dart';

void main() {
  group('tileGridSizeFor', () {
    test('너비에 비례한 격자를 만들고 tile이 화면을 완전히 덮는다', () {
      const size = Size(800, 600);
      final (cols, rows, tileSize) = tileGridSizeFor(size);
      expect(cols, greaterThan(0));
      expect(rows, greaterThan(0));
      expect(cols * tileSize, greaterThanOrEqualTo(size.width));
      expect(rows * tileSize, greaterThanOrEqualTo(size.height));
    });

    test('너비가 0에 가까워도 최소 1x1 격자를 보장한다', () {
      final (cols, rows, tileSize) = tileGridSizeFor(const Size(0, 0));
      expect(cols, greaterThanOrEqualTo(1));
      expect(rows, greaterThanOrEqualTo(1));
      expect(tileSize, greaterThan(0));
    });
  });

  group('barycentricInvDepthAt — 실제 depth-buffer 보간 수학', () {
    // 화면 공간의 간단한 직각삼각형: (0,0) (100,0) (0,100).
    const sa = Offset(0, 0);
    const sb = Offset(100, 0);
    const sc = Offset(0, 100);

    test('삼각형 내부 점은 보간된 invW를 돌려준다(세 정점이 같은 값이면 그대로)', () {
      final depth = barycentricInvDepthAt(
        const Offset(20, 20),
        sa,
        sb,
        sc,
        1.0,
        1.0,
        1.0,
      );
      expect(depth, closeTo(1.0, 1e-9));
    });

    test('정점에 가까울수록 그 정점의 invW에 가까워진다(선형 보간)', () {
      // 무게중심 — 세 정점 가중치가 1/3씩.
      final centroidDepth = barycentricInvDepthAt(
        const Offset(100 / 3, 100 / 3),
        sa,
        sb,
        sc,
        3.0, // a=near
        0.0, // b=far
        0.0, // c=far
      );
      // (1/3)*3 + (1/3)*0 + (1/3)*0 = 1.0.
      expect(centroidDepth, closeTo(1.0, 1e-6));
    });

    test('삼각형 밖의 점은 null을 돌려준다', () {
      final depth = barycentricInvDepthAt(
        const Offset(200, 200),
        sa,
        sb,
        sc,
        1.0,
        1.0,
        1.0,
      );
      expect(depth, isNull);
    });

    test('depth buffer 비교 규칙: invW가 큰(카메라에 더 가까운) 쪽이 이긴다', () {
      // 같은 화면 지점을 두 삼각형이 덮을 때, 실제 painter는
      // `if (depthVal > depth[idx])`로 갱신한다 — 그 비교 자체가 "더
      // 가까운 쪽이 이긴다"는 depth test의 정의와 일치하는지 확인한다.
      const p = Offset(20, 20);
      final nearDepth = barycentricInvDepthAt(
        p,
        sa,
        sb,
        sc,
        2.0,
        2.0,
        2.0,
      ); // eye에 가까움.
      final farDepth = barycentricInvDepthAt(
        p,
        sa,
        sb,
        sc,
        0.5,
        0.5,
        0.5,
      ); // 멀리 있음.
      expect(
        nearDepth! > farDepth!,
        isTrue,
        reason: '더 가까운 삼각형의 invW가 더 커야 depth test가 옳다.',
      );
    });
  });

  group('Space3DViewV2 — 위젯 스모크 테스트', () {
    testWidgets('실제 SpaceSceneV2를 예외 없이 그리고 카메라 UX 버튼을 보여준다', (tester) async {
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
          CadWall(
            id: 'n',
            start: const Point2(0.1, 0.1),
            end: const Point2(0.9, 0.1),
            thicknessNormalized: 0.02,
            wallType: CadWallType.exterior,
            confidence: 0.9,
          ),
          CadWall(
            id: 's',
            start: const Point2(0.1, 0.9),
            end: const Point2(0.9, 0.9),
            thicknessNormalized: 0.02,
            wallType: CadWallType.exterior,
            confidence: 0.9,
          ),
          CadWall(
            id: 'w',
            start: const Point2(0.1, 0.1),
            end: const Point2(0.1, 0.9),
            thicknessNormalized: 0.02,
            wallType: CadWallType.exterior,
            confidence: 0.9,
          ),
          CadWall(
            id: 'e',
            start: const Point2(0.9, 0.1),
            end: const Point2(0.9, 0.9),
            thicknessNormalized: 0.02,
            wallType: CadWallType.exterior,
            confidence: 0.9,
          ),
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
      const scale = FloorPlanScale(
        mmPerPixel: 5.0,
        referenceStart: Point2(0, 0),
        referenceEnd: Point2(1, 0),
        referenceLengthMm: 5000,
        source: ScaleSource.measured,
      );
      final scene = buildSpaceSceneV2(
        plan: plan,
        scale: scale,
        ceilingHeightMm: 2400,
      );
      expect(scene.isEmpty, isFalse);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 300,
              child: Space3DViewV2(scene: scene),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('화면 맞춤'), findsOneWidget);
      expect(find.text('전체 화면'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // 궤도 드래그 — 카메라가 바뀌어도 예외 없이 다시 그려져야 한다.
      await tester.drag(find.byType(Space3DViewV2), const Offset(60, -30));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('SpaceTriangleV2 normal/centroid', () {
    test('법선은 항상 단위벡터이고 centroid는 세 점의 평균이다', () {
      final plan = CadFloorPlan(
        sourceWidthPx: 1000,
        sourceHeightPx: 1000,
        walls: [
          CadWall(
            id: 'n',
            start: const Point2(0.1, 0.1),
            end: const Point2(0.9, 0.1),
            thicknessNormalized: 0.02,
            wallType: CadWallType.exterior,
            confidence: 0.9,
          ),
        ],
        openings: const [],
        rooms: const [],
        warnings: const [],
      );
      const scale = FloorPlanScale(
        mmPerPixel: 5.0,
        referenceStart: Point2(0, 0),
        referenceEnd: Point2(1, 0),
        referenceLengthMm: 5000,
        source: ScaleSource.measured,
      );
      final scene = buildSpaceSceneV2(
        plan: plan,
        scale: scale,
        ceilingHeightMm: 2400,
      );
      for (final tri in scene.wallMeshes.single.triangles) {
        expect(tri.normal.length, closeTo(1.0, 1e-6));
        final expectedCentroid = (tri.a + tri.b + tri.c) / 3.0;
        expect((tri.centroid - expectedCentroid).length, lessThan(1e-6));
      }
    });
  });
}
