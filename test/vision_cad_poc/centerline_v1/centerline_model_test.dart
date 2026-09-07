// SPACE SHIFT — WO088-7 WALL CENTERLINE POC — §15 필수 테스트.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/vision_cad_poc/centerline_v1/centerline_model.dart';

RawRunBand _band(String id, bool horizontal, double crossPx, double alongMin, double alongMax, {LineKind kind = LineKind.solid, double coverage = 1.0}) =>
    RawRunBand(id: id, horizontal: horizontal, crossPx: crossPx, alongMinPx: alongMin, alongMaxPx: alongMax, coverageRatio: coverage, kind: kind);

void main() {
  group('pairWallBoundaries + buildCenterlines', () {
    test('평행한 두 boundary -> centerline이 정확히 중간(midpoint)에 생성된다', () {
      final pairs = pairWallBoundaries([_band('a', true, 100, 0, 200), _band('b', true, 112, 0, 200)]);
      expect(pairs, hasLength(1));
      final lines = buildCenterlines(pairs);
      expect(lines.single.crossPx, closeTo(106, 1e-9)); // (100+112)/2.
      expect(lines.single.reviewNeeded, isFalse);
    });

    test('horizontal wall — centerline이 수평(양 끝 y 동일)이다', () {
      final pairs = pairWallBoundaries([_band('a', true, 100, 0, 200), _band('b', true, 112, 0, 200)]);
      final line = buildCenterlines(pairs).single;
      expect(line.horizontal, isTrue);
      expect(line.start.y, line.end.y);
    });

    test('vertical wall — centerline이 수직(양 끝 x 동일)이다', () {
      final pairs = pairWallBoundaries([_band('a', false, 50, 0, 300), _band('b', false, 60, 0, 300)]);
      final line = buildCenterlines(pairs).single;
      expect(line.horizontal, isFalse);
      expect(line.start.x, line.end.x);
    });

    test('두께가 다른 벽 두 개(unequal thickness) — 각자 올바른 중간값으로 계산된다(서로 섞이지 않음)', () {
      final pairs = pairWallBoundaries([
        _band('a1', true, 0, 0, 200),
        _band('a2', true, 8, 0, 200), // 두께 8.
        _band('b1', true, 300, 0, 200),
        _band('b2', true, 320, 0, 200), // 두께 20.
      ]);
      final lines = buildCenterlines(pairs);
      expect(lines, hasLength(2));
      expect(lines.map((l) => l.crossPx), containsAll([closeTo(4, 1e-9), closeTo(310, 1e-9)]));
    });

    test('짝을 찾지 못한 단일 boundary — reviewNeeded=true로 그 경계선 자체가 centerline이 된다', () {
      final pairs = pairWallBoundaries([_band('solo', true, 100, 0, 200)]);
      final line = buildCenterlines(pairs).single;
      expect(line.reviewNeeded, isTrue);
      expect(line.crossPx, 100);
    });

    test('along 범위가 거의 겹치지 않으면 짝짓지 않는다(서로 다른 벽으로 취급)', () {
      final pairs = pairWallBoundaries([_band('a', true, 100, 0, 50), _band('b', true, 112, 200, 250)]);
      expect(pairs.every((p) => p.singleBoundary), isTrue);
    });

    test('중복 centerline 방지 — 이미 짝지어진 band는 다른 pair에 재사용되지 않는다', () {
      // a, b, c가 전부 서로 짝지어질 수 있는 간격이어도 a-b가 먼저 짝지어지면
      // c는 남은 것끼리만(또는 단독으로) 처리돼야지 a/b와 중복 짝을 만들면 안 된다.
      final pairs = pairWallBoundaries([_band('a', true, 100, 0, 200), _band('b', true, 110, 0, 200), _band('c', true, 120, 0, 200)]);
      final usedIds = <String>{};
      for (final p in pairs) {
        expect(usedIds.contains(p.boundaryAId), isFalse);
        usedIds.add(p.boundaryAId);
        if (p.boundaryBId != null) {
          expect(usedIds.contains(p.boundaryBId), isFalse);
          usedIds.add(p.boundaryBId!);
        }
      }
      expect(usedIds, hasLength(3));
    });
  });

  group('extractLineEvidence — §4 solid/dashed 실제 픽셀 mask 기준 분류', () {
    test('연속된 실선은 solid로, 규칙적으로 끊긴 파선은 dashed로 분류되고 solidBands에 섞이지 않는다', () {
      const w = 100, h = 60;
      final mask = Uint8List(w * h);
      // 연속 실선(row 10, x=5..85 전부 채움).
      for (var x = 5; x < 85; x++) {
        mask[10 * w + x] = 1;
      }
      // 파선(row 30, 4px 켜짐/6px 꺼짐 반복 — 명확한 dash 패턴).
      for (var x = 5; x < 85; x++) {
        if ((x - 5) % 10 < 4) mask[30 * w + x] = 1;
      }
      final evidence = extractLineEvidence(mask, w, h, minMeaningfulLengthPx: 10);
      expect(evidence.solidBands.any((b) => (b.crossPx - 10).abs() < 2), isTrue, reason: '연속 실선은 solid로 분류돼야 한다');
      expect(evidence.dashedBands.any((b) => (b.crossPx - 30).abs() < 2), isTrue, reason: '규칙적으로 끊긴 선은 dashed로 분류돼야 한다');
      expect(evidence.solidBands.any((b) => (b.crossPx - 30).abs() < 2), isFalse, reason: 'dashed로 분류된 선이 solidBands에 섞이면 안 된다(wall evidence로 직접 확정되지 않음)');
    });
  });
}
