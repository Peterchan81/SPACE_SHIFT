// Vision Guided CAD POC — TopologyValidator 11개 규칙 단위 테스트.
//
// 각 규칙을 실제로 위반하는 최소 SSSpatialModel을 직접 구성해, 검증기가
// (a) 위반을 정확히 잡아내고 (b) geometry는 절대 바꾸지 않은 채
// confidence만 낮추고 reviewNeeded=true + 이유를 남기는지 확인한다.

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/ss_spatial_model.dart';
import 'package:ason_space/services/topology_validator.dart';

void main() {
  const validator = TopologyValidator();

  SSSpace space(String id, List<Point2> polygon) => SSSpace(
    id: id,
    polygon: polygon,
    areaNormalized: 0.1,
    closed: true,
    confidence: 1.0,
  );

  test('규칙 1 — FloorDomain이 자기교차하면 warnings에 기록되고 geometry는 그대로다', () {
    final selfIntersecting = [
      const Point2(0, 0),
      const Point2(1, 1),
      const Point2(1, 0),
      const Point2(0, 1),
    ];
    final model = SSSpatialModel(
      sourceWidthPx: 100,
      sourceHeightPx: 100,
      spaces: const [],
      walls: const [],
      openings: const [],
      objects: const [],
      warnings: const [],
      floorDomain: selfIntersecting,
    );
    final result = validator.validate(model);
    expect(result.warnings.any((w) => w.contains('rule 1')), isTrue);
    expect(result.floorDomain, selfIntersecting);
  });

  test('규칙 2 — 외곽 경계가 닫힌 루프를 이루지 않으면(dangling endpoint) 경고한다', () {
    final boundaries = [
      const SSBoundary(
        id: 'e1',
        spaceId: 's1',
        start: Point2(0, 0),
        end: Point2(1, 0),
        type: SSBoundaryType.wall,
        confidence: 1.0,
        isExterior: true,
      ),
      const SSBoundary(
        id: 'e2',
        spaceId: 's1',
        start: Point2(1, 0),
        end: Point2(1, 1),
        type: SSBoundaryType.wall,
        confidence: 1.0,
        isExterior: true,
      ),
      // e3의 끝점이 e1의 시작점과 만나지 않아 루프가 끊긴다.
      const SSBoundary(
        id: 'e3',
        spaceId: 's1',
        start: Point2(1, 1),
        end: Point2(0.5, 0.9),
        type: SSBoundaryType.wall,
        confidence: 1.0,
        isExterior: true,
      ),
    ];
    final model = SSSpatialModel(
      sourceWidthPx: 100,
      sourceHeightPx: 100,
      spaces: const [],
      walls: const [],
      openings: const [],
      objects: const [],
      warnings: const [],
      boundaries: boundaries,
    );
    final result = validator.validate(model);
    expect(result.warnings.any((w) => w.contains('rule 2')), isTrue);
  });

  test('규칙 3 — 공간 폴리곤이 자기교차하면 review 표시, 폴리곤은 안 바뀐다', () {
    final polygon = [
      const Point2(0, 0),
      const Point2(1, 1),
      const Point2(1, 0),
      const Point2(0, 1),
    ];
    final model = SSSpatialModel(
      sourceWidthPx: 100,
      sourceHeightPx: 100,
      spaces: [space('s1', polygon)],
      walls: const [],
      openings: const [],
      objects: const [],
      warnings: const [],
    );
    final result = validator.validate(model);
    final s1 = result.spaces.single;
    expect(s1.reviewNeeded, isTrue);
    expect(s1.reviewReasons.any((r) => r.contains('rule 3')), isTrue);
    expect(s1.polygon, polygon);
  });

  test('규칙 4 — 공간이 FloorDomain 밖으로 나가면 review 표시된다', () {
    final domain = [
      const Point2(0, 0),
      const Point2(0.5, 0),
      const Point2(0.5, 0.5),
      const Point2(0, 0.5),
    ];
    final outsideSpace = space('s1', [
      const Point2(0.4, 0.4),
      const Point2(0.9, 0.4),
      const Point2(0.9, 0.9),
      const Point2(0.4, 0.9),
    ]);
    final model = SSSpatialModel(
      sourceWidthPx: 100,
      sourceHeightPx: 100,
      spaces: [outsideSpace],
      walls: const [],
      openings: const [],
      objects: const [],
      warnings: const [],
      floorDomain: domain,
    );
    final result = validator.validate(model);
    final s1 = result.spaces.single;
    expect(s1.reviewNeeded, isTrue);
    expect(s1.reviewReasons.any((r) => r.contains('rule 4')), isTrue);
  });

  test('규칙 5 — 벽 전체가 가구 footprint 안에 들어있으면 review + confidence 하락', () {
    final furniture = SSObjectCandidate(
      id: 'obj-1',
      polygon: const [
        Point2(0, 0),
        Point2(1, 0),
        Point2(1, 1),
        Point2(0, 1),
      ],
      kind: SSObjectKind.bed,
    );
    const wall = SSWall(
      id: 'w1',
      start: Point2(0.2, 0.2),
      end: Point2(0.8, 0.2),
      thicknessNormalized: 0.02,
      kind: SSWallKind.interior,
      confidence: 1.0,
    );
    final model = SSSpatialModel(
      sourceWidthPx: 100,
      sourceHeightPx: 100,
      spaces: const [],
      walls: const [wall],
      openings: const [],
      objects: [furniture],
      warnings: const [],
    );
    final result = validator.validate(model);
    final w1 = result.walls.single;
    expect(w1.reviewNeeded, isTrue);
    expect(w1.reviewReasons.any((r) => r.contains('rule 5')), isTrue);
    expect(w1.confidence, lessThan(wall.confidence));
    expect(w1.start, wall.start);
    expect(w1.end, wall.end);
  });

  test('규칙 6 — 벽의 한쪽 끝만 가구 안에서 끝나면 review 표시된다', () {
    final furniture = SSObjectCandidate(
      id: 'obj-1',
      polygon: const [
        Point2(0, 0),
        Point2(0.3, 0),
        Point2(0.3, 0.3),
        Point2(0, 0.3),
      ],
      kind: SSObjectKind.cabinet,
    );
    const wall = SSWall(
      id: 'w1',
      start: Point2(0.1, 0.1),
      end: Point2(0.9, 0.1),
      thicknessNormalized: 0.02,
      kind: SSWallKind.interior,
      confidence: 1.0,
    );
    final model = SSSpatialModel(
      sourceWidthPx: 100,
      sourceHeightPx: 100,
      spaces: const [],
      walls: const [wall],
      openings: const [],
      objects: [furniture],
      warnings: const [],
    );
    final result = validator.validate(model);
    final w1 = result.walls.single;
    expect(w1.reviewNeeded, isTrue);
    expect(w1.reviewReasons.any((r) => r.contains('rule 6')), isTrue);
  });

  test('규칙 7 — 어떤 벽에도 붙어있지 않은 opening은 review 표시된다', () {
    const opening = SSOpening(
      id: 'o1',
      kind: SSOpeningKind.door,
      center: Point2(0.5, 0.5),
      widthNormalized: 0.02,
      confidence: 1.0,
    );
    final model = SSSpatialModel(
      sourceWidthPx: 100,
      sourceHeightPx: 100,
      spaces: const [],
      walls: const [],
      openings: const [opening],
      objects: const [],
      warnings: const [],
    );
    final result = validator.validate(model);
    final o1 = result.openings.single;
    expect(o1.reviewNeeded, isTrue);
    expect(o1.reviewReasons.any((r) => r.contains('rule 7')), isTrue);
    expect(o1.confidence, lessThan(opening.confidence));
  });

  test('규칙 8 — 존재하지 않는 공간 id를 참조하면 review 표시된다', () {
    const opening = SSOpening(
      id: 'o1',
      kind: SSOpeningKind.door,
      center: Point2(0.5, 0.1),
      widthNormalized: 0.02,
      confidence: 1.0,
      wallId: 'w1',
      connectsSpaceIds: ['does-not-exist'],
    );
    const wall = SSWall(
      id: 'w1',
      start: Point2(0, 0.1),
      end: Point2(1, 0.1),
      thicknessNormalized: 0.02,
      kind: SSWallKind.interior,
      confidence: 1.0,
    );
    final model = SSSpatialModel(
      sourceWidthPx: 100,
      sourceHeightPx: 100,
      spaces: [space('s1', const [Point2(0, 0), Point2(1, 0), Point2(1, 1), Point2(0, 1)])],
      walls: const [wall],
      openings: const [opening],
      objects: const [],
      warnings: const [],
    );
    final result = validator.validate(model);
    final o1 = result.openings.single;
    expect(o1.reviewNeeded, isTrue);
    expect(o1.reviewReasons.any((r) => r.contains('rule 8')), isTrue);
  });

  test('규칙 9 — 창문이 두 실내 공간을 잇는 통로처럼 쓰이면 review 표시된다', () {
    const opening = SSOpening(
      id: 'o1',
      kind: SSOpeningKind.window,
      center: Point2(0.5, 0.1),
      widthNormalized: 0.02,
      confidence: 1.0,
      wallId: 'w1',
      connectsSpaceIds: ['s1', 's2'],
    );
    const wall = SSWall(
      id: 'w1',
      start: Point2(0, 0.1),
      end: Point2(1, 0.1),
      thicknessNormalized: 0.02,
      kind: SSWallKind.interior,
      confidence: 1.0,
    );
    final model = SSSpatialModel(
      sourceWidthPx: 100,
      sourceHeightPx: 100,
      spaces: [
        space('s1', const [Point2(0, 0), Point2(0.5, 0), Point2(0.5, 0.5), Point2(0, 0.5)]),
        space('s2', const [Point2(0.5, 0), Point2(1, 0), Point2(1, 0.5), Point2(0.5, 0.5)]),
      ],
      walls: const [wall],
      openings: const [opening],
      objects: const [],
      warnings: const [],
    );
    final result = validator.validate(model);
    final o1 = result.openings.single;
    expect(o1.reviewNeeded, isTrue);
    expect(o1.reviewReasons.any((r) => r.contains('rule 9')), isTrue);
  });

  test('규칙 10 — 두 공간이 상당 부분 겹치면 둘 다 review 표시된다', () {
    final s1 = space('s1', const [
      Point2(0, 0),
      Point2(1, 0),
      Point2(1, 1),
      Point2(0, 1),
    ]);
    final s2 = space('s2', const [
      Point2(0.1, 0.1),
      Point2(0.9, 0.1),
      Point2(0.9, 0.9),
      Point2(0.1, 0.9),
    ]);
    final model = SSSpatialModel(
      sourceWidthPx: 100,
      sourceHeightPx: 100,
      spaces: [s1, s2],
      walls: const [],
      openings: const [],
      objects: const [],
      warnings: const [],
    );
    final result = validator.validate(model);
    expect(result.spaces.every((s) => s.reviewNeeded), isTrue);
    expect(result.spaces.every((s) => s.reviewReasons.any((r) => r.contains('rule 10'))), isTrue);
  });

  test('규칙 11 — opening이 벽 끝점에 딱 붙어있으면(벽 연결성 파괴) review 표시된다', () {
    const wall = SSWall(
      id: 'w1',
      start: Point2(0, 0.1),
      end: Point2(1, 0.1),
      thicknessNormalized: 0.02,
      kind: SSWallKind.interior,
      confidence: 1.0,
    );
    const opening = SSOpening(
      id: 'o1',
      kind: SSOpeningKind.door,
      center: Point2(0.001, 0.1),
      widthNormalized: 0.05,
      confidence: 1.0,
      wallId: 'w1',
    );
    final model = SSSpatialModel(
      sourceWidthPx: 100,
      sourceHeightPx: 100,
      spaces: const [],
      walls: const [wall],
      openings: const [opening],
      objects: const [],
      warnings: const [],
    );
    final result = validator.validate(model);
    final o1 = result.openings.single;
    expect(o1.reviewNeeded, isTrue);
    expect(o1.reviewReasons.any((r) => r.contains('rule 11')), isTrue);
  });

  test('정상적인 모델은 어떤 규칙도 위반하지 않고 그대로 통과한다', () {
    final domain = [
      const Point2(0, 0),
      const Point2(1, 0),
      const Point2(1, 1),
      const Point2(0, 1),
    ];
    final s1 = space('s1', const [
      Point2(0, 0),
      Point2(0.5, 0),
      Point2(0.5, 1),
      Point2(0, 1),
    ]);
    final s2 = space('s2', const [
      Point2(0.5, 0),
      Point2(1, 0),
      Point2(1, 1),
      Point2(0.5, 1),
    ]);
    const wall = SSWall(
      id: 'w1',
      start: Point2(0.5, 0),
      end: Point2(0.5, 1),
      thicknessNormalized: 0.02,
      kind: SSWallKind.interior,
      confidence: 1.0,
    );
    const opening = SSOpening(
      id: 'o1',
      kind: SSOpeningKind.door,
      center: Point2(0.5, 0.5),
      widthNormalized: 0.05,
      confidence: 1.0,
      wallId: 'w1',
      connectsSpaceIds: ['s1', 's2'],
    );
    final model = SSSpatialModel(
      sourceWidthPx: 100,
      sourceHeightPx: 100,
      spaces: [s1, s2],
      walls: const [wall],
      openings: const [opening],
      objects: const [],
      warnings: const [],
      floorDomain: domain,
    );
    final result = validator.validate(model);
    expect(result.spaces.every((s) => !s.reviewNeeded), isTrue);
    expect(result.walls.every((w) => !w.reviewNeeded), isTrue);
    expect(result.openings.every((o) => !o.reviewNeeded), isTrue);
    expect(result.warnings, model.warnings);
  });
}
