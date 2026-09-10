// SPACE SHIFT — WO098 3D INTERACTION ROOT TEST ONLY.
//
// 목적: [Space3DViewGpuV2]의 마우스/터치 interaction(회전/zoom/pan/선택)이
// 실제로 동작하는지, 복잡한 아파트 평면도/CAD와 완전히 분리한 단순
// scene으로 먼저 증명한다. 평면도/CAD 파이프라인([CadFloorPlan],
// [buildSpaceSceneV2] 등)은 이 파일 어디에서도 쓰지 않는다 — [SpaceSceneV2]
// mesh(바닥 1개 + 벽 4개 + 비대칭 오브젝트 1개)를 순수 좌표로 직접
// 만든다. 비대칭 오브젝트(기울어진 각뿔)와 벽마다 다른 색은, 회전 시
// "정말로 다른 면이 보이는가"를 사용자가 한눈에 구분할 수 있게 하기
// 위한 의도적 설계다(대칭 큐브는 회전해도 똑같아 보여 검증에 못 쓴다).
//
// 별도 entry point로 존재한다 — 실제 앱(main.dart)의 어떤 화면도 이
// 파일을 import하지 않는다. `flutter run -t lib/debug/wo098_interaction_root_test.dart`
// (또는 build)로만 실행한다.
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../models/space_scene_v2.dart';
import '../widgets/workspace/space_3d_view_gpu_v2.dart';

void main() {
  runApp(const _Wo098InteractionTestApp());
}

class _Wo098InteractionTestApp extends StatelessWidget {
  const _Wo098InteractionTestApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'WO098 3D Interaction Root Test',
      home: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: Space3DViewGpuV2(
                  scene: _buildSimpleTestScene(),
                  // §2 — perspective로 고정해 이번 WO에서 건드리지 않는
                  // 아이소 cutaway(clip plane) 경로를 아예 타지 않는다
                  // (cameraMode가 isometric이 아니면 기존 코드가 이미
                  // clippingPlanes를 비운다 — cutaway 코드 자체를 수정하지
                  // 않고도 이번 테스트에서 완전히 배제된다).
                  cameraMode: Space3DCameraMode.perspective,
                ),
              ),
              const Positioned(
                left: 12,
                bottom: 12,
                child: _InstructionCard(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InstructionCard extends StatelessWidget {
  const _InstructionCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Text(
        'WO098 3D INTERACTION ROOT TEST\n'
        '좌클릭 드래그 = 회전 / 마우스 휠 = zoom / 우클릭·중클릭 드래그 = pan\n'
        '(콘솔에 [WO098 orbit] 로그로 카메라 position/azimuth/polar 확인 가능)',
        style: TextStyle(color: Colors.white, fontSize: 13, height: 1.5),
      ),
    );
  }
}

const Color _floorColor = Color(0xFFD9CBB2);
const Color _northWallColor = Color(0xFFE05B5B); // 빨강 — Z=0.
const Color _southWallColor = Color(0xFF5B87E0); // 파랑 — Z=roomSizeMm.
const Color _eastWallColor = Color(0xFF5BE07C); // 초록 — X=roomSizeMm.
const Color _westWallColor = Color(0xFFE0D65B); // 노랑 — X=0.
const Color _objectColor = Color(0xFFE05BD0); // 마젠타 — 비대칭 오브젝트.

const double _roomSizeMm = 6000;
const double _wallHeightMm = 2400;
const double _wallThicknessMm = 150;

List<SpaceTriangleV2> _quad(Vector3 a, Vector3 b, Vector3 c, Vector3 d, Color color) {
  return [
    SpaceTriangleV2(a: a, b: b, c: c, color: color),
    SpaceTriangleV2(a: a, b: c, c: d, color: color),
  ];
}

/// 축정렬 상자(6면, 12 triangle) — 회전/zoom/pan 검증용 벽/바닥은 굳이
/// 실제 CAD 벽처럼 얇은 5면 shell일 필요가 없어 가장 단순한 형태로
/// 직접 만든다.
List<SpaceTriangleV2> _axisBox({
  required double minX,
  required double minY,
  required double minZ,
  required double maxX,
  required double maxY,
  required double maxZ,
  required Color color,
}) {
  Vector3 v(double x, double y, double z) => Vector3(x, y, z);
  final p000 = v(minX, minY, minZ);
  final p100 = v(maxX, minY, minZ);
  final p110 = v(maxX, maxY, minZ);
  final p010 = v(minX, maxY, minZ);
  final p001 = v(minX, minY, maxZ);
  final p101 = v(maxX, minY, maxZ);
  final p111 = v(maxX, maxY, maxZ);
  final p011 = v(minX, maxY, maxZ);
  return [
    ..._quad(p000, p100, p101, p001, color), // 바닥면.
    ..._quad(p010, p011, p111, p110, color), // 윗면.
    ..._quad(p000, p001, p011, p010, color), // -X면.
    ..._quad(p100, p110, p111, p101, color), // +X면.
    ..._quad(p000, p010, p110, p100, color), // -Z면.
    ..._quad(p001, p101, p111, p011, color), // +Z면.
  ];
}

/// §1 "눈에 띄는 비대칭 오브젝트" — 밑면 정사각형 + 꼭짓점이 한쪽으로
/// 치우친 각뿔(기울어진 피라미드). 회전시켰을 때 보는 방향에 따라
/// 실루엣이 뚜렷이 달라져("정면"에서 보면 기울어진 게 보이지만 "옆"에서
/// 보면 대칭처럼 보이는 등) 실제로 카메라가 도는지 사용자가 눈으로
/// 바로 판단할 수 있다.
List<SpaceTriangleV2> _leaningPyramid({required Vector3 baseCenter, required double baseSize, required double heightMm, required double leanMm, required Color color}) {
  final half = baseSize / 2;
  final b0 = Vector3(baseCenter.x - half, baseCenter.y, baseCenter.z - half);
  final b1 = Vector3(baseCenter.x + half, baseCenter.y, baseCenter.z - half);
  final b2 = Vector3(baseCenter.x + half, baseCenter.y, baseCenter.z + half);
  final b3 = Vector3(baseCenter.x - half, baseCenter.y, baseCenter.z + half);
  final apex = Vector3(baseCenter.x + leanMm, baseCenter.y + heightMm, baseCenter.z);
  return [
    ..._quad(b0, b3, b2, b1, color), // 밑면.
    SpaceTriangleV2(a: b0, b: b1, c: apex, color: color),
    SpaceTriangleV2(a: b1, b: b2, c: apex, color: color),
    SpaceTriangleV2(a: b2, b: b3, c: apex, color: color),
    SpaceTriangleV2(a: b3, b: b0, c: apex, color: color),
  ];
}

SpaceObjectIdentityV2 _identity(String id, SpaceElementKindV2 kind, Color color) {
  return SpaceObjectIdentityV2(objectId: id, sourceKind: kind, sourceId: id, color: color);
}

SpaceSceneV2 _buildSimpleTestScene() {
  const t = _wallThicknessMm;
  const s = _roomSizeMm;
  const h = _wallHeightMm;

  final floorTriangles = _quad(
    Vector3(0, 0, 0),
    Vector3(0, 0, s),
    Vector3(s, 0, s),
    Vector3(s, 0, 0),
    _floorColor,
  );
  final floor = SpaceFloorMeshV2(
    identity: _identity('floor:test', SpaceElementKindV2.floor, _floorColor),
    triangles: floorTriangles,
    polygonMm: [Vector3(0, 0, 0), Vector3(0, 0, s), Vector3(s, 0, s), Vector3(s, 0, 0)],
  );

  SpaceWallMeshV2 wall(String id, Color color, {required double minX, required double minZ, required double maxX, required double maxZ, required Vector3 startMm, required Vector3 endMm}) {
    return SpaceWallMeshV2(
      identity: _identity(id, SpaceElementKindV2.wall, color),
      triangles: _axisBox(minX: minX, minY: 0, minZ: minZ, maxX: maxX, maxY: h, maxZ: maxZ, color: color),
      startMm: startMm,
      endMm: endMm,
      isExterior: true,
    );
  }

  final walls = [
    // North(Z=0, 빨강), South(Z=s, 파랑), West(X=0, 노랑), East(X=s, 초록).
    wall('wall:north', _northWallColor, minX: -t / 2, minZ: -t / 2, maxX: s + t / 2, maxZ: t / 2, startMm: Vector3(0, 0, 0), endMm: Vector3(s, 0, 0)),
    wall('wall:south', _southWallColor, minX: -t / 2, minZ: s - t / 2, maxX: s + t / 2, maxZ: s + t / 2, startMm: Vector3(0, 0, s), endMm: Vector3(s, 0, s)),
    wall('wall:west', _westWallColor, minX: -t / 2, minZ: -t / 2, maxX: t / 2, maxZ: s + t / 2, startMm: Vector3(0, 0, 0), endMm: Vector3(0, 0, s)),
    wall('wall:east', _eastWallColor, minX: s - t / 2, minZ: -t / 2, maxX: s + t / 2, maxZ: s + t / 2, startMm: Vector3(s, 0, 0), endMm: Vector3(s, 0, s)),
  ];

  final objectTriangles = _leaningPyramid(
    baseCenter: Vector3(s * 0.7, 0, s * 0.3),
    baseSize: 900,
    heightMm: 1100,
    leanMm: 450,
    color: _objectColor,
  );
  final asymmetricObject = SpaceFloorMeshV2(
    identity: _identity('object:asymmetric', SpaceElementKindV2.furniture, _objectColor),
    triangles: objectTriangles,
    polygonMm: const [],
  );

  return SpaceSceneV2(
    wallMeshes: walls,
    floorMeshes: [floor, asymmetricObject],
    openings: const [],
    minBounds: Vector3(-t / 2, 0, -t / 2),
    maxBounds: Vector3(s + t / 2, h, s + t / 2),
    warnings: const [],
  );
}
