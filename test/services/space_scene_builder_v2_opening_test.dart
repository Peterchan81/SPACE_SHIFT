// SPACE SHIFT — PC2 WO097 REAL DOOR/OPENING GEOMETRY ONLY.
//
// CadOpening(door)이 실제 SpaceSceneV2 벽 geometry에서 바닥~문높이 구간의
// triangle을 만들지 않고(실제로 통과 가능한 빈 공간), 문 위쪽 벽(상인방)은
// 그대로 유지되는지 확인한다. window/unknown 타입과, wallId가 연결되지
// 않거나 기하학적으로 유효하지 않은 door는 이번 WO 범위에서 벽에
// 반영되지 않아야 한다(§6/§7 — 신뢰할 수 없으면 지어내지 않는다).
import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/space_scene_v2.dart';
import 'package:ason_space/services/space_scene_builder_v2.dart';

// sourceWidthPx == sourceHeightPx(정사각형)라 diagonalPx = 1000*sqrt(2)
// 이고, world mm 변환이 x/y 모두 *1000*5(anisotropic 없음)라 테스트
// 좌표 계산이 단순해진다.
const _scale = FloorPlanScale(
  mmPerPixel: 5.0,
  referenceStart: Point2(0, 0),
  referenceEnd: Point2(1, 0),
  referenceLengthMm: 5000,
  source: ScaleSource.measured,
);
const _diagonalPx = 1000 * 1.4142135623730951;

CadWall _horizontalWall(String id) => const CadWall(
  id: 'w',
  start: Point2(0.1, 0.5),
  end: Point2(0.9, 0.5),
  thicknessNormalized: 0.02,
  wallType: CadWallType.interior,
  confidence: 0.9,
);

/// [widthMm]짜리 문을 만든다 — widthNormalized는 diagonalPx 기준이라
/// (CadFloorPlan.realMmForNormalizedLength와 동일한 공식) 역산한다.
CadOpening _door(String id, {required double centerX, required double widthMm, String? wallId = 'w'}) {
  return CadOpening(
    id: id,
    type: OpeningType.door,
    center: Point2(centerX, 0.5),
    widthNormalized: widthMm / (_diagonalPx * _scale.mmPerPixel),
    confidence: 0.9,
    wallId: wallId,
  );
}

SpaceWallMeshV2 _wallMeshFor(SpaceSceneV2 scene, String id) =>
    scene.wallMeshes.singleWhere((w) => w.identity.wallId == id);

CadFloorPlan _plan(List<CadOpening> openings) => CadFloorPlan(
  sourceWidthPx: 1000,
  sourceHeightPx: 1000,
  walls: [_horizontalWall('w')],
  openings: openings,
  rooms: const [],
  warnings: const [],
);

void main() {
  group('WO097 — door opening이 실제로 벽을 뚫는다', () {
    test('문 구간(바닥~문높이)에는 triangle이 없고, 문 위(상인방)에는 남는다', () {
      // 벽 world X 범위: start=500mm, end=4500mm(길이 4000mm).
      // 문 중심 x=0.5 -> world X=2500mm, 폭 1000mm -> 구간 [2000,3000]mm.
      final scene = buildSpaceSceneV2(
        plan: _plan([_door('d1', centerX: 0.5, widthMm: 1000)]),
        scale: _scale,
        ceilingHeightMm: 2400,
      );
      final wall = _wallMeshFor(scene, 'w');

      // 문 구간의 낮은 높이(문높이 2000mm 미만)에는 완전히 뚫려 있어야
      // 한다 — 그 구간에 온전히 들어가는 triangle이 하나도 없어야 한다.
      final gapTriangleAtLowHeight = wall.triangles.any(
        (t) => [t.a, t.b, t.c].every((v) => v.x > 2010 && v.x < 2990 && v.y < 1990),
      );
      expect(gapTriangleAtLowHeight, isFalse, reason: '문 구간은 바닥부터 문 높이까지 완전히 비어 있어야 한다.');

      // 문 위(상인방, y>=2000)에는 같은 x 구간에 벽이 남아 있어야 한다
      // (§5 "문 위쪽 벽은 유지").
      final headerTriangle = wall.triangles.any(
        (t) => [t.a, t.b, t.c].every((v) => v.x >= 1999 && v.x <= 3001 && v.y >= 1999),
      );
      expect(headerTriangle, isTrue, reason: '문 위쪽 벽(상인방)이 남아 있어야 한다.');

      // 문 구간 밖(예: x~1000, 벽 시작 쪽)은 여전히 바닥부터 천장까지
      // 꽉 찬 벽이어야 한다.
      final tallSolidNearStart = wall.triangles.any(
        (t) => [t.a, t.b, t.c].any((v) => (v.x - 1000).abs() < 700 && v.y > 2350),
      );
      expect(tallSolidNearStart, isTrue, reason: '문에서 먼 구간은 전체 높이 그대로 유지돼야 한다.');
    });

    test('벽 identity(높이/길이/두께/시작·끝점)는 문 유무와 무관하게 동일하다', () {
      final withoutDoor = buildSpaceSceneV2(plan: _plan(const []), scale: _scale, ceilingHeightMm: 2400);
      final withDoor = buildSpaceSceneV2(
        plan: _plan([_door('d1', centerX: 0.5, widthMm: 1000)]),
        scale: _scale,
        ceilingHeightMm: 2400,
      );
      final a = _wallMeshFor(withoutDoor, 'w');
      final b = _wallMeshFor(withDoor, 'w');
      expect(b.identity.dimensions!.heightMm, a.identity.dimensions!.heightMm);
      expect(b.identity.dimensions!.widthMm, a.identity.dimensions!.widthMm);
      expect(b.identity.dimensions!.thicknessMm, a.identity.dimensions!.thicknessMm);
      expect(b.startMm.x, a.startMm.x);
      expect(b.endMm.x, a.endMm.x);
    });

    test('정확한 triangle 개수 — 벽 2(bottom-only) + 상인방 1(top+bottom cap 포함)', () {
      final scene = buildSpaceSceneV2(
        plan: _plan([_door('d1', centerX: 0.5, widthMm: 1000)]),
        scale: _scale,
        ceilingHeightMm: 2400,
      );
      final wall = _wallMeshFor(scene, 'w');
      // 좌/우 solid segment: 10 triangle씩(top+4 side, §7과 동일 구성).
      // 상인방(문 위): top+bottom cap+4 side = 6 quad = 12 triangle.
      expect(wall.triangles, hasLength(10 + 10 + 12));
    });

    test('겹치는 문 2개는 하나의 구간으로 합쳐진다(중복/겹침 geometry 없음)', () {
      // 두 문이 world X로 [1800,2600]과 [2400,3200]에 걸쳐 겹친다 ->
      // 병합되면 [1800,3200] 구간 하나만 뚫린다(상인방도 1개).
      final scene = buildSpaceSceneV2(
        plan: _plan([
          _door('d1', centerX: 0.44, widthMm: 800), // center world X=2200, span [1800,2600].
          _door('d2', centerX: 0.56, widthMm: 800), // center world X=2800, span [2400,3200].
        ]),
        scale: _scale,
        ceilingHeightMm: 2400,
      );
      final wall = _wallMeshFor(scene, 'w');
      // 병합된 통구간 전체가 낮은 높이에서 뚫려 있어야 한다.
      final gapTriangle = wall.triangles.any(
        (t) => [t.a, t.b, t.c].every((v) => v.x > 1810 && v.x < 3190 && v.y < 1990),
      );
      expect(gapTriangle, isFalse);
      // 겹치는 두 구간이 병합되지 않았다면 상인방이 2개(겹쳐서 12+12=24)
      // 였을 것 — 병합되면 상인방 1개(12) + 좌우 solid 2개(20) = 32.
      expect(wall.triangles, hasLength(32));
    });
  });

  group('WO097 §6/§7 — 신뢰할 수 없는 opening은 벽을 바꾸지 않는다', () {
    test('wallId가 어떤 벽과도 연결되지 않은 door는 무시된다(벽 그대로)', () {
      final scene = buildSpaceSceneV2(
        plan: _plan([_door('orphan', centerX: 0.5, widthMm: 1000, wallId: 'no-such-wall')]),
        scale: _scale,
        ceilingHeightMm: 2400,
      );
      final wall = _wallMeshFor(scene, 'w');
      expect(wall.triangles, hasLength(10));
      expect(scene.warnings.any((w) => w.contains('벽 연결 정보 없음/불일치')), isTrue);
    });

    test('WO102부터 window 타입 opening도 실제로 벽을 뚫는다(frame+glass 별도 mesh)', () {
      // WO097 당시엔 "창턱/창 높이 데이터가 없어 보류"했지만, WO102 §5가
      // 그 sill/head를 명시적 가정값(kAssumedWindowSillHeightMm 등)으로
      // 관리하도록 요구해 이제 실제로 반영된다 — 이 테스트는 그 새 동작을
      // 검증한다(더 자세한 검증은 space_scene_builder_v2_wo102_window_test.dart).
      final windowOpening = CadOpening(
        id: 'win1',
        type: OpeningType.window,
        center: const Point2(0.5, 0.5),
        widthNormalized: 1000 / (_diagonalPx * _scale.mmPerPixel),
        confidence: 0.95,
        wallId: 'w',
      );
      final scene = buildSpaceSceneV2(plan: _plan([windowOpening]), scale: _scale, ceilingHeightMm: 2400);
      final wall = _wallMeshFor(scene, 'w');
      expect(wall.triangles, isNot(hasLength(10)), reason: '창이 벽에 실제로 반영돼 geometry가 바뀌어야 한다.');
      expect(scene.windowMeshes, hasLength(1));
      expect(scene.warnings.any((w) => w.contains('창 개구부') && w.contains('반영했습니다')), isTrue);
    });

    test('폭이 0 이하인 degenerate door는 무시된다(벽 그대로, 정직한 경고)', () {
      final degenerate = CadOpening(
        id: 'zero-width',
        type: OpeningType.door,
        center: const Point2(0.5, 0.5),
        widthNormalized: 0,
        confidence: 0.9,
        wallId: 'w',
      );
      final scene = buildSpaceSceneV2(plan: _plan([degenerate]), scale: _scale, ceilingHeightMm: 2400);
      final wall = _wallMeshFor(scene, 'w');
      expect(wall.triangles, hasLength(10));
      expect(scene.warnings.any((w) => w.contains('벽 범위를 벗어난 위치·폭')), isTrue);
    });

    test('문 중심이 벽 범위를 완전히 벗어나면(투영이 밖) 무시된다', () {
      // 벽은 xในimage [0.1,0.9]인데 문 중심이 x=2.0(완전히 밖) ->
      // clamp 후 남는 폭이 minMeaningfulOpeningMm보다 작아 제외된다.
      final farAway = _door('far', centerX: 2.0, widthMm: 500);
      final scene = buildSpaceSceneV2(plan: _plan([farAway]), scale: _scale, ceilingHeightMm: 2400);
      final wall = _wallMeshFor(scene, 'w');
      expect(wall.triangles, hasLength(10));
    });
  });
}
