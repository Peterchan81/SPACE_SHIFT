// WO093 — "3D 아이소 Cutaway/Dollhouse 표현 수정"의 핵심 판정 로직
// (computeIsoCutawayHiddenWallIds) 단위 테스트.
//
// 실기에서 확인된 문제: 확대하면 앞쪽 벽 때문에 작은 방 내부가 안
// 보이고 벽만 보인다 — 카메라 문제가 아니라 렌더링 방식 문제였다.
// 이 테스트는 그 문제가 실제로 해결됐는지를 순수 geometry 계산만으로
// (three_js/위젯 없이) 검증한다. 모든 카메라 좌표는 직접 손으로
// 벡터/교차 공식을 계산해 검증한 값이다(임의로 고른 값이 아니다).
//
// 공통 시나리오: 8000x8000mm 아파트, 천장고 2400mm — 왼쪽 방 A
// (x:0~4000, 중심 (2000,4000))와 오른쪽 방 B(x:4000~8000, 중심
// (6000,4000))가 중앙 칸막이벽(x=4000)으로 나뉘고, 전체를 감싸는 외벽
// 4개(N/S/W/E)가 있다.
import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/services/iso_cutaway.dart';

const _ceilingHeight = 2400.0;

const _outerNorth = (
  objectId: 'wall-n',
  sx: 0.0,
  sz: 0.0,
  ex: 8000.0,
  ez: 0.0,
  topY: _ceilingHeight,
);
const _outerSouth = (
  objectId: 'wall-s',
  sx: 0.0,
  sz: 8000.0,
  ex: 8000.0,
  ez: 8000.0,
  topY: _ceilingHeight,
);
const _outerWest = (
  objectId: 'wall-w',
  sx: 0.0,
  sz: 0.0,
  ex: 0.0,
  ez: 8000.0,
  topY: _ceilingHeight,
);
const _outerEast = (
  objectId: 'wall-e',
  sx: 8000.0,
  sz: 0.0,
  ex: 8000.0,
  ez: 8000.0,
  topY: _ceilingHeight,
);
const _midWall = (
  objectId: 'wall-mid',
  sx: 4000.0,
  sz: 0.0,
  ex: 4000.0,
  ez: 8000.0,
  topY: _ceilingHeight,
);

final _allWalls = [_outerNorth, _outerSouth, _outerWest, _outerEast, _midWall];

const _roomA = (2000.0, 4000.0);
const _roomB = (6000.0, 4000.0);
final _bothRooms = [_roomA, _roomB];

void main() {
  test('기본(먼) 아이소 시점 — 카메라가 충분히 멀고 높으면, 낮은 벽이 '
      '가로막지 않고 자연스럽게 넘겨다보인다(항상 무조건 숨기는 게 '
      '아니라, 실제로 시야를 가릴 때만 숨긴다)', () {
    // 북서쪽 바깥 멀리·높은 곳(실제 앱의 기본 아이소 카메라와 비슷한
    // 비율 — radius*2.6 거리, center.y+distance*0.7 높이)에서 방 A를
    // 바라본다.
    final hidden = computeIsoCutawayHiddenWallIds(
      cameraX: -6000,
      cameraY: 12000,
      cameraZ: -6000,
      wallSegments: _allWalls,
      roomCentroidsXZ: [_roomA],
    );
    expect(hidden, isEmpty);
  });

  test('B — 확대해서 방 B 가까이(카메라가 낮고 가깝게) 다가가면, 카메라와 '
      '방 사이의 중앙 칸막이벽이 실제로 시야를 가로막아 숨겨진다 — '
      '"확대하면 벽만 보인다" 재현 방지', () {
    final hidden = computeIsoCutawayHiddenWallIds(
      cameraX: 3200,
      cameraY: 1200,
      cameraZ: 4000,
      wallSegments: _allWalls,
      roomCentroidsXZ: [_roomB],
    );
    expect(
      hidden.contains('wall-mid'),
      isTrue,
      reason: '카메라와 방 B 사이를 실제로 막는 칸막이벽은 숨겨져야 방 내부가 보인다',
    );
  });

  test('같은 벽/타겟이라도 카메라를 다시 멀리·높이 빼면(축소) 더 이상 '
      '가로막지 않아 다시 보인다 — 높이를 반영한 판정이라는 확인', () {
    final hiddenZoomedIn = computeIsoCutawayHiddenWallIds(
      cameraX: 3200,
      cameraY: 1200,
      cameraZ: 4000,
      wallSegments: [_midWall],
      roomCentroidsXZ: [_roomB],
    );
    final hiddenZoomedOut = computeIsoCutawayHiddenWallIds(
      cameraX: -8000,
      cameraY: 9000,
      cameraZ: 4000,
      wallSegments: [_midWall],
      roomCentroidsXZ: [(3000.0, 4000.0)],
    );
    expect(hiddenZoomedIn, {'wall-mid'});
    expect(hiddenZoomedOut, isEmpty);
  });

  test('C — 회전해서 반대쪽(동쪽)에서 가까이 보면, 숨겨지는 벽이 '
      '서쪽 벽에서 동쪽 벽으로 바뀐다(고정된 벽이 아니라 카메라 방향 '
      '기준으로 매번 다시 판단한다)', () {
    final hiddenFromWest = computeIsoCutawayHiddenWallIds(
      cameraX: -500,
      cameraY: 1200,
      cameraZ: 4000,
      wallSegments: _allWalls,
      roomCentroidsXZ: _bothRooms,
    );
    final hiddenFromEast = computeIsoCutawayHiddenWallIds(
      cameraX: 8500,
      cameraY: 1200,
      cameraZ: 4000,
      wallSegments: _allWalls,
      roomCentroidsXZ: _bothRooms,
    );

    expect(hiddenFromWest.contains('wall-w'), isTrue);
    expect(hiddenFromWest.contains('wall-e'), isFalse);

    expect(hiddenFromEast.contains('wall-e'), isTrue);
    expect(hiddenFromEast.contains('wall-w'), isFalse);
  });

  test('D — 카메라가 이미 방 안쪽에 있어 가로막는 벽이 전혀 없으면 '
      '아무 벽도 숨기지 않는다(오탐 방지)', () {
    final hidden = computeIsoCutawayHiddenWallIds(
      cameraX: 2000,
      cameraY: 1200,
      cameraZ: 1000,
      wallSegments: _allWalls,
      roomCentroidsXZ: [_roomA],
    );
    expect(hidden, isEmpty);
  });

  group('WO094 — computeRoomCutawayTargets(방 중심 하나만으로는 부족하다)', () {
    // 4000x3000 직사각형 방 — 중심 (2000,1500). WO093은 이 중심 하나만
    // cutaway 목표로 썼다. 아래 벽은 "중심까지의 시선"은 전혀 가로막지
    // 않지만 "방의 먼 구석(모서리 안쪽 샘플)까지의 시선"은 실제로
        // 가로막도록 손으로 계산해 배치했다 — 중심만 보면 이 벽을 숨길
    // 이유가 없어 보이지만, 사용자가 화면에서 실제로 보게 되는 건 방
    // 전체이지 중심 한 점이 아니다.
    const roomPolygon = [(0.0, 0.0), (4000.0, 0.0), (4000.0, 3000.0), (0.0, 3000.0)];
    const roomCentroid = (2000.0, 1500.0);
    const blockingWall = (
      objectId: 'wall-corner-blocker',
      sx: 1000.0,
      sz: 2000.0,
      ex: 1000.0,
      ez: 3000.0,
      topY: _ceilingHeight,
    );
    // 카메라는 방 서쪽 바깥, 중심과 같은 높이(z=1500)에 있다 — 중심까지는
    // z=1500 수평선이라 x=1000 구간(z:2000~3000)의 벽과 절대 만나지
    // 않는다.
    const cameraX = -2000.0, cameraY = 1500.0, cameraZ = 1500.0;

    test('꼭짓점을 안쪽으로 당긴 샘플이 실제로 만들어진다(중심 1개 + 꼭짓점 4개 = 5개)', () {
      final targets = computeRoomCutawayTargets(roomPolygon);
      expect(targets, hasLength(5));
      expect(targets, contains(roomCentroid));
      // (4000,3000) 꼭짓점을 중심 쪽으로 15% 당긴 샘플.
      expect(targets, contains((3700.0, 2775.0)));
    });

    test('중심 좌표 하나만 목표로 쓰면 이 벽은 가로막는 것으로 판정되지 않는다 '
        '(WO093의 한계 재현)', () {
      final hidden = computeIsoCutawayHiddenWallIds(
        cameraX: cameraX,
        cameraY: cameraY,
        cameraZ: cameraZ,
        wallSegments: [blockingWall],
        roomCentroidsXZ: [roomCentroid],
      );
      expect(hidden, isEmpty);
    });

    test('computeRoomCutawayTargets가 만든 여러 목표를 쓰면 방 구석을 가로막는 '
        '이 벽이 정확히 숨겨진다(WO094 개선 확인)', () {
      final targets = computeRoomCutawayTargets(roomPolygon);
      final hidden = computeIsoCutawayHiddenWallIds(
        cameraX: cameraX,
        cameraY: cameraY,
        cameraZ: cameraZ,
        wallSegments: [blockingWall],
        roomCentroidsXZ: targets,
      );
      expect(hidden, {'wall-corner-blocker'});
    });
  });
}
