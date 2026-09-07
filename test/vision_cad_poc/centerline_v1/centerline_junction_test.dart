// SPACE SHIFT — WO088-7 §15 CENTERLINE JUNCTION 필수 테스트.

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/vision_cad_poc/centerline_v1/centerline_junction.dart';
import 'package:ason_space/vision_cad_poc/centerline_v1/centerline_model.dart';

Centerline _line(String id, bool horizontal, Pt start, Pt end, {bool reviewNeeded = false}) => Centerline(
  id: id,
  start: start,
  end: end,
  horizontal: horizontal,
  sourceBoundaryIds: const ['x'],
  confidence: 1.0,
  reviewNeeded: reviewNeeded,
  evidence: 'test',
);

void main() {
  group('buildCenterlineJunctions', () {
    test('L junction — 두 line이 정확히 양쪽 끝에서 만난다', () {
      final lines = [_line('h', true, (x: 0, y: 0), (x: 100, y: 0)), _line('v', false, (x: 100, y: 0), (x: 100, y: 100))];
      final junctions = buildCenterlineJunctions(lines);
      expect(junctions.any((j) => j.kind == JunctionKind.lJunction), isTrue);
    });

    test('T junction — 한 line의 끝점이 다른 line의 중간(body)에 닿는다', () {
      final lines = [_line('through', true, (x: 0, y: 0), (x: 200, y: 0)), _line('stub', false, (x: 100, y: 0), (x: 100, y: 100))];
      final junctions = buildCenterlineJunctions(lines);
      expect(junctions.any((j) => j.kind == JunctionKind.tJunction), isTrue);
    });

    test('X junction — 두 line 모두 서로의 중간을 지난다', () {
      final lines = [_line('h', true, (x: 0, y: 50), (x: 200, y: 50)), _line('v', false, (x: 100, y: 0), (x: 100, y: 100))];
      final junctions = buildCenterlineJunctions(lines);
      expect(junctions.any((j) => j.kind == JunctionKind.xJunction), isTrue);
    });

    test('endpoint — 다른 어떤 line과도 닿지 않는 고립된 끝은 endpoint로 남는다', () {
      final lines = [_line('solo', true, (x: 0, y: 0), (x: 100, y: 0))];
      final junctions = buildCenterlineJunctions(lines);
      expect(junctions, hasLength(2)); // start, end 각각.
      expect(junctions.every((j) => j.kind == JunctionKind.endpoint), isTrue);
    });

    test('가까워 보이지만 실제로는 연결 증거가 부족한 경우 — reviewNeeded로 남기고 억지로 연결하지 않는다', () {
      // v의 y범위가 h의 y(=0)에서 8px 떨어진 지점에서 시작 — corner
      // evidence tolerance(4px)는 넘지만 review band(15px) 안에는 있음.
      final lines = [_line('h', true, (x: 0, y: 0), (x: 100, y: 0)), _line('v', false, (x: 100, y: 8), (x: 100, y: 100))];
      final junctions = buildCenterlineJunctions(lines);
      expect(junctions.any((j) => j.kind == JunctionKind.reviewNeeded), isTrue);
    });

    test('review band 밖(멀리 떨어진 두 line)은 아예 관계가 없다고 보고 각자 endpoint로 남는다', () {
      final lines = [_line('h', true, (x: 0, y: 0), (x: 100, y: 0)), _line('v', false, (x: 100, y: 500), (x: 100, y: 600))];
      final junctions = buildCenterlineJunctions(lines);
      expect(junctions.any((j) => j.kind == JunctionKind.lJunction || j.kind == JunctionKind.tJunction || j.kind == JunctionKind.xJunction || j.kind == JunctionKind.reviewNeeded), isFalse);
      expect(junctions.every((j) => j.kind == JunctionKind.endpoint), isTrue);
    });

    test('straight continuation — 같은 방향, 같은 축, 끝점이 거의 맞닿은 두 line', () {
      final lines = [_line('a', true, (x: 0, y: 0), (x: 100, y: 0)), _line('b', true, (x: 100, y: 0), (x: 200, y: 0))];
      final junctions = buildCenterlineJunctions(lines);
      expect(junctions.any((j) => j.kind == JunctionKind.straightContinuation), isTrue);
    });

    test('no forced tilt — 이 모듈은 endpoint를 평균내지 않으므로 완전한 수평/수직 line은 어떤 연산에도 기울지 않는다(좌표 자체가 변하지 않음을 확인)', () {
      final h = _line('h', true, (x: 0, y: 42), (x: 100, y: 42));
      final v = _line('v', false, (x: 100, y: 42), (x: 100, y: 142));
      buildCenterlineJunctions([h, v]);
      // buildCenterlineJunctions는 Centerline을 변형하지 않는다 — 원본 그대로.
      expect(h.start.y, 42);
      expect(h.end.y, 42);
      expect(v.start.x, 100);
      expect(v.end.x, 100);
    });
  });
}
