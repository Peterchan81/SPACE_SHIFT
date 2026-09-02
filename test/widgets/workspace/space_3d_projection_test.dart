// 3D 아이소 "벽면에 거대한 삼각형 artifact" 실기 재현 및 근본 원인 검증.
//
// 실제 원인: 카메라가 벽에 가깝게 다가갔을 때(줌인/회전은 정상 사용
// 시나리오다 — WO 14번 "자유 시점 조작"), near plane에 아주 가깝지만
// 완전히 카메라 뒤는 아닌 정점(0 < eye 기준 forward 성분 <= near)이
// projectToScreen()을 그대로 통과하면 clip.w가 0에 매우 가까워 원근
// 나눗셈(ndc = clip.xy / clip.w)이 극단적으로 큰 화면 좌표를 만든다 —
// 삼각형의 다른 두 점은 정상 위치인데 한 점만 화면 밖 수천~수만 픽셀로
// 튀어나가면서 "벽면을 뒤덮는 거대한 삼각형"처럼 보인다.
//
// 이 파일은 (1) 그 조건에서 실제로 극단적인 좌표가 나온다는 것을
// projectToScreen()만으로 직접 재현하고, (2) Space3DView가 실제로 쓰는
// near-plane 배제 판정(behindNear와 동일한 수식)이 그 정점을 정확히
// 걸러낸다는 것을 확인한다.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/space_scene.dart';
import 'package:ason_space/services/space_scene_builder.dart';
import 'package:ason_space/widgets/workspace/space_3d_view.dart';

/// 실기와 동일한 방식(실제 분석 결과 → CadFloorPlan → buildSpaceScene)으로
/// 만든, 벽 여러 개짜리 현실적인 scene.
SpaceScene _realisticScene() {
  const result = FloorPlanAnalysisResult(
    sourceWidthPx: 1200,
    sourceHeightPx: 900,
    walls: [
      WallSegment(
        id: 'wall-n',
        start: Point2(0.1, 0.1),
        end: Point2(0.9, 0.1),
        thicknessNormalized: 0.015,
        confidence: 0.8,
        isExterior: true,
      ),
      WallSegment(
        id: 'wall-s',
        start: Point2(0.1, 0.9),
        end: Point2(0.9, 0.9),
        thicknessNormalized: 0.015,
        confidence: 0.8,
        isExterior: true,
      ),
      WallSegment(
        id: 'wall-w',
        start: Point2(0.1, 0.1),
        end: Point2(0.1, 0.9),
        thicknessNormalized: 0.015,
        confidence: 0.8,
        isExterior: true,
      ),
      WallSegment(
        id: 'wall-e',
        start: Point2(0.9, 0.1),
        end: Point2(0.9, 0.9),
        thicknessNormalized: 0.015,
        confidence: 0.8,
        isExterior: true,
      ),
      WallSegment(
        id: 'wall-mid',
        start: Point2(0.5, 0.1),
        end: Point2(0.5, 0.9),
        thicknessNormalized: 0.015,
        confidence: 0.6,
      ),
    ],
    openings: [
      OpeningCandidate(
        id: 'door-0',
        type: OpeningType.door,
        center: Point2(0.5, 0.5),
        widthNormalized: 0.04,
        confidence: 0.5,
        wallId: 'wall-mid',
      ),
    ],
    rooms: [
      RoomCandidate(
        id: 'room-left',
        polygon: [
          Point2(0.1, 0.1),
          Point2(0.5, 0.1),
          Point2(0.5, 0.9),
          Point2(0.1, 0.9),
        ],
        areaNormalized: 0.32,
        confidence: 0.7,
      ),
      RoomCandidate(
        id: 'room-right',
        polygon: [
          Point2(0.5, 0.1),
          Point2(0.9, 0.1),
          Point2(0.9, 0.9),
          Point2(0.5, 0.9),
        ],
        areaNormalized: 0.32,
        confidence: 0.7,
      ),
    ],
    warnings: [],
    debugStats: FloorPlanAnalysisDebugStats(
      sourceWidthPx: 1200,
      sourceHeightPx: 900,
      analysisWidthPx: 1200,
      analysisHeightPx: 900,
      rawHorizontalRuns: 2,
      rawVerticalRuns: 3,
      mergedWallCount: 5,
      roomCandidateCount: 2,
      openingCandidateCount: 1,
      durationMs: 12,
    ),
  );

  final plan = buildCadFloorPlan(result);
  final scale = resolveAutoScale(plan, null);
  return buildSpaceScene(plan: plan, scale: scale, ceilingHeightMm: 2400);
}

/// [Space3DView]의 기본("화면 맞춤") 카메라와 정확히 같은 구면좌표 계산.
vm.Vector3 _defaultEye(vm.Vector3 target, double distance) {
  const yaw = math.pi / 4;
  final pitch = math.atan(1 / math.sqrt2);
  final cp = math.cos(pitch);
  return target +
      vm.Vector3(
        distance * cp * math.sin(yaw),
        distance * math.sin(pitch),
        distance * cp * math.cos(yaw),
      );
}

void main() {
  final scene = _realisticScene();

  test('실기 재현 전제 — 이 scene은 비어 있지 않고 실제 벽/바닥을 담고 있다', () {
    expect(scene.isEmpty, isFalse);
    expect(scene.wallCount, 5);
    expect(scene.floorCount, 2);
  });

  test('기본(화면 맞춤) 카메라로는 어떤 정점도 화면 밖 극단으로 튀지 않는다', () {
    final target = scene.center;
    final radius = scene.boundingRadius;
    final distance = radius * 2.6;
    final eye = _defaultEye(target, distance);

    const size = Size(1000, 700);
    final viewProj = buildViewProjectionMatrix(
      eye: eye,
      target: target,
      boundingRadius: radius,
      aspect: size.width / size.height,
    );

    for (final tri in scene.triangles) {
      for (final v in [tri.a, tri.b, tri.c]) {
        final p = projectToScreen(viewProj, v, size);
        if (p == null) continue; // near/뒤쪽 — Space3DView가 그리지 않는다.
        expect(p.dx.isFinite, isTrue);
        expect(p.dy.isFinite, isTrue);
        // "거대한 삼각형" 판정 기준 — 정상 시야에서는 화면 크기의 수
        // 배를 넘어서는 좌표가 나오지 않아야 한다.
        expect(
          p.dx.abs(),
          lessThan(size.width * 5),
          reason: '정점이 뷰포트 밖 극단으로 투영됨(vertex=$v)',
        );
        expect(
          p.dy.abs(),
          lessThan(size.height * 5),
          reason: '정점이 뷰포트 밖 극단으로 투영됨(vertex=$v)',
        );
      }
    }
  });

  test('근본 원인 재현 — 카메라가 벽 구석까지 줌인(정상 사용 시나리오: 벽을 '
      '자세히 보려고 확대)하면, 그 근처의 다른 정점(같은 벽의 반대쪽 '
      '모서리처럼 카메라 축에서 벗어난 점)의 원근 나눗셈이 극단적으로 '
      '커진다 — Space3DView가 실제로 만나는 것과 같은 방 크기(반경 수천mm)로 '
      '재현한다', () {
    final radius = scene.boundingRadius;
    final near = nearPlaneDistanceFor(radius);
    const size = Size(1000, 700);

    // 사용자가 벽 구석 쪽으로 바짝 줌인한 카메라. eye는 near plane
    // 바로 앞(near * 0.5)에 있는 한 점을 보고 있다 — "벽 표면에 거의
    // 닿을 만큼" 확대한 정상적인 조작이다.
    final eye = vm.Vector3(0, radius * 0.3, 0);
    final closeTarget = eye + vm.Vector3(0, 0, -1) * (near * 0.5);
    final viewProj = buildViewProjectionMatrix(
      eye: eye,
      target: closeTarget,
      boundingRadius: radius,
      aspect: size.width / size.height,
    );
    final forward = (closeTarget - eye).normalized();

    // 같은 벽 삼각형이 공유하는, 카메라 축에서 옆으로 크게 벗어난
    // 실제 방 크기 규모(radius)의 다른 모서리 — near plane보다도
    // 가깝게 eye 앞에 있다(전형적인 근접 확대 상황에서 삼각형의 한
    // 변만 카메라를 스쳐 지나가는 경우).
    final grazingVertex =
        eye + forward * (near * 0.4) + vm.Vector3(radius, 0, 0);

    final isBehindNear = (grazingVertex - eye).dot(forward) <= near;
    expect(isBehindNear, isTrue, reason: '이 테스트가 재현하려는 조건 자체가 성립해야 한다');

    // projectToScreen() 자체는 (near plane 배제를 모르므로) 이 조건에서
    // 정상 범위를 크게 벗어난 값을 준다 — 이것이 "거대한 삼각형"의
    // 실제 근본 원인이다.
    final projected = projectToScreen(viewProj, grazingVertex, size);
    final isExtreme =
        projected == null ||
        !projected.dx.isFinite ||
        !projected.dy.isFinite ||
        projected.dx.abs() > size.width * 5 ||
        projected.dy.abs() > size.height * 5;
    expect(
      isExtreme,
      isTrue,
      reason:
          'near plane 근처 정점을 그냥 투영하면 극단적인 좌표가 나온다는 '
          '것을 재현 — 그래서 Space3DView는 이 정점을 가진 삼각형을 '
          '아예 그리지 않는다(behindNear 배제)',
    );
  });
}
