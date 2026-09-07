// SPACE SHIFT — WO088-5 CLEAN STRUCTURAL LAYER.
//
// preClean()의 component-level elongation 판정을 검증한다. 중요: 이
// 테스트는 "실제 벽 mesh 전체에는 이 접근이 적용되지 않는다"는, WO088-5
// 조사에서 실측으로 확인된 한계를 그대로 고정한다(§14 STOP 이후 대체
// 접근으로 전환한 근거) — 누군가 이 함수를 나중에 production 벽 추출
// 경로에 다시 연결하기 전에 이 한계를 반드시 알아야 한다.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/vision_cad_poc/drafting_v1/pre_clean.dart';

Uint8List _blankMask(int w, int h) => Uint8List(w * h);

void _drawHLine(Uint8List mask, int w, int x0, int x1, int y) {
  for (var x = x0; x <= x1; x++) {
    mask[y * w + x] = 1;
  }
}

void _drawVLine(Uint8List mask, int w, int y0, int y1, int x) {
  for (var y = y0; y <= y1; y++) {
    mask[y * w + x] = 1;
  }
}

void main() {
  group('preClean — 고립된 elongated/blob 구분(정상 동작 사례)', () {
    test('고립된 긴 얇은 선(다른 무엇과도 안 닿음)은 유지된다', () {
      const w = 100, h = 100;
      final mask = _blankMask(w, h);
      _drawHLine(mask, w, 10, 80, 50); // 길이 70, 두께 1 -> elongation 매우 큼.
      final result = preClean(mask, w, h);
      final keptCount = result.cleanMask.fold(0, (s, v) => s + v);
      expect(keptCount, 71, reason: '고립된 긴 선은 전부 유지돼야 한다');
      expect(result.suppressedMask.fold(0, (s, v) => s + v), 0);
    });

    test('고립된 작은 정사각형 blob(아이콘 근사)은 억제된다', () {
      const w = 100, h = 100;
      final mask = _blankMask(w, h);
      for (var y = 40; y <= 50; y++) {
        _drawHLine(mask, w, 40, 50, y); // 11x11 정사각형 blob, elongation=1.
      }
      final result = preClean(mask, w, h);
      expect(result.cleanMask.fold(0, (s, v) => s + v), 0, reason: '정사각형 blob은 elongation이 낮아 억제돼야 한다');
      expect(result.suppressedMask.fold(0, (s, v) => s + v), greaterThan(0));
    });
  });

  group('preClean — WO088-5 실측으로 확인된 한계(문서화된 실패 모드)', () {
    test('서로 맞물린 벽 mesh(사각형 외곽+내부 파티션)는 전체가 통째로 억제된다 — 이 함수를 production 벽 mesh에 직접 쓰면 안 되는 이유', () {
      const w = 100, h = 60;
      final mask = _blankMask(w, h);
      // 사각형 외곽(전체가 corner에서 서로 물려 하나의 connected mesh).
      _drawHLine(mask, w, 10, 90, 10);
      _drawHLine(mask, w, 10, 90, 50);
      _drawVLine(mask, w, 10, 50, 10);
      _drawVLine(mask, w, 10, 50, 90);
      // 내부 파티션 — 위아래 벽과 맞물려 같은 mesh에 합류.
      _drawVLine(mask, w, 10, 50, 50);

      final result = preClean(mask, w, h);
      final totalOnes = mask.fold(0, (s, v) => s + v);
      final kept = result.cleanMask.fold(0, (s, v) => s + v);
      // 전체 mesh의 bounding box(90-10=80 x 50-10=40)는 elongation
      // 80/40=2.0 < 기본 threshold(4.0)이므로 전부 억제된다 — 이것이
      // WO088-5에서 실측으로 확인된 실패 모드다. 이 assert가 깨지면
      // (즉 kept > 0으로 바뀌면) preClean() 구현이 바뀐 것이니 이
      // WO088-5 보고서의 "1차 시도 실패" 근거도 재검토해야 한다.
      expect(kept, 0, reason: '연결된 벽 mesh 전체가 하나의 컴포넌트로 병합되어 elongation이 낮게 나오는 문서화된 한계');
      expect(result.suppressedMask.fold(0, (s, v) => s + v), totalOnes);
    });
  });
}
