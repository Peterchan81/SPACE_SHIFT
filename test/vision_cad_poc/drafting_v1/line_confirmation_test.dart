// SPACE SHIFT — WO088-5 §9 LINE → WALL 판정 강화.
//
// confirmWalls()의 3가지 evidence(substantialLength/junctionConnected/
// repeatedPatternCluster)와 그 어느 것도 만족하지 못하는 isolatedShort
// fallback을 합성 데이터로 검증한다.

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/vision_cad_poc/drafting_v1/line_confirmation.dart';
import 'package:ason_space/vision_cad_poc/drafting_v1/structural_layer.dart';

RawStructuralLine _line(String id, double x1, double y1, double x2, double y2) =>
    RawStructuralLine(id: id, start: (x: x1, y: y1), end: (x: x2, y: y2), thicknessPx: 2, method: 'axisAligned');

void main() {
  group('confirmWalls', () {
    test('이미지 대각선 대비 충분히 긴 선은 substantialLength로 확정된다', () {
      // 대각선 sqrt(400^2+300^2)=500, 6% = 30px 이상이면 확정.
      final lines = [_line('long', 10, 10, 200, 10)]; // 길이 190.
      final verdicts = confirmWalls(lines, imageW: 400, imageH: 300);
      expect(verdicts.single.confirmed, isTrue);
      expect(verdicts.single.confirmReason, WallConfirmReason.substantialLength);
    });

    test('짧아도 다른 벽과 corner에서 연결되면 junctionConnected로 확정된다', () {
      final lines = [
        _line('short', 10, 10, 20, 10), // 길이 10, substantialLength 미달.
        _line('other', 20, 10, 20, 100), // 'short'의 끝점(20,10)에서 시작 — junction.
      ];
      final verdicts = confirmWalls(lines, imageW: 1000, imageH: 1000);
      final shortVerdict = verdicts.firstWhere((v) => v.line.id == 'short');
      expect(shortVerdict.confirmed, isTrue);
      expect(shortVerdict.confirmReason, WallConfirmReason.junctionConnected);
    });

    test('짧고 고립된(연결 없는) 단일 선은 isolatedShort로 억제된다', () {
      final lines = [_line('isolated', 10, 10, 20, 10)];
      final verdicts = confirmWalls(lines, imageW: 1000, imageH: 1000);
      expect(verdicts.single.confirmed, isFalse);
      expect(verdicts.single.suppressReason, WallSuppressReason.isolatedShort);
    });

    test('같은 방향의 짧고 고립된 선이 국소적으로 여러 개 뭉쳐 있으면(계단/사다리형 hatch 근사) repeatedPatternCluster로 그룹 전체가 억제된다', () {
      // y 간격을 기본 cornerTolerancePx(10)보다 크게 잡아(15) 이웃 rung의
      // 끝점끼리 junctionConnected로 먼저 확정돼 버리지 않게 한다 —
      // repeatedPatternCluster 분기가 실제로 시험되도록 두 조건을
      // 명확히 분리한 합성 데이터.
      final lines = [
        for (var i = 0; i < 4; i++) _line('rung-$i', 100, 100.0 + i * 15, 130, 100.0 + i * 15),
      ];
      final verdicts = confirmWalls(lines, imageW: 1000, imageH: 1000, repeatedPatternMinCount: 4);
      expect(verdicts.every((v) => !v.confirmed), isTrue);
      expect(verdicts.every((v) => v.suppressReason == WallSuppressReason.repeatedPatternCluster), isTrue);
    });

    test('같은 자리에 몰려 있어도 개수가 기준 미만이면 repeatedPatternCluster로 판정하지 않는다(isolatedShort로 남는다)', () {
      final lines = [
        _line('a', 100, 100, 130, 100),
        _line('b', 100, 115, 130, 115),
      ];
      final verdicts = confirmWalls(lines, imageW: 1000, imageH: 1000, repeatedPatternMinCount: 4);
      expect(verdicts.every((v) => v.suppressReason == WallSuppressReason.isolatedShort), isTrue);
    });
  });
}
