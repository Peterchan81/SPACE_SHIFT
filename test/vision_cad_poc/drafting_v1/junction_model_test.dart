// SPACE SHIFT — WO088-6 5mm SNAP + JUNCTION MODEL.
//
// 특히 "axis-preserving snap" 회귀 테스트(마지막 그룹)가 중요하다 —
// WO088-6 최초 구현은 junction 좌표를 모든 멤버 끝점의 (x,y) 평균으로
// 계산해, 직교하는 벽끼리 좌표가 섞여 원래 완전히 수평/수직이던 벽이
// snap 후 육안으로 보일 만큼 기울어지는 버그가 실제 Image 3 결과에서
// 발견됐다(test/image3_wo6_C_snapped_5mm.png 최초본). 이 테스트는 그
// 버그가 재발하지 않는지 고정한다.

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/vision_cad_poc/drafting_v1/drafting_model.dart';
import 'package:ason_space/vision_cad_poc/drafting_v1/junction_model.dart';
import 'package:ason_space/vision_cad_poc/drafting_v1/real_mm_grid.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/virtual_cad_scale.dart';

RealMmWall _wall(String id, double x1, double y1, double x2, double y2) => RealMmWall(
  id: id,
  rawStart: RealMmPoint(x1, y1),
  rawEnd: RealMmPoint(x2, y2),
  classification: WallAngleClass.orthogonalConfirmed,
  method: 'axisAligned',
);

RealMmDraft _draft(List<RealMmWall> walls) => RealMmDraft(scale: const RealWorldScale.verified(mmPerVirtualUnit: 1.0), walls: walls);

void main() {
  group('buildJunctionDraft — 기본 junction 분류', () {
    test('L자 코너(가로+세로 벽 하나씩) — degree 2, lJunction', () {
      final draft = _draft([
        _wall('h', 0, 0, 1000, 0),
        _wall('v', 1000, 0, 1000, 800),
      ]);
      final result = buildJunctionDraft(draft, junctionMergeToleranceMm: 5);
      final corner = result.junctions.values.firstWhere((j) => j.degree == 2);
      expect(corner.type, JunctionType.lJunction);
    });

    test('T자(세로벽 끝점이 가로벽 몸통에 닿음) — tJunction으로 승격되고 through-wall은 분리되지 않는다', () {
      final draft = _draft([
        _wall('through', 0, 0, 1000, 0),
        _wall('stub', 500, 0, 500, 400),
      ]);
      final result = buildJunctionDraft(draft, junctionMergeToleranceMm: 5);
      final tJunction = result.junctions.values.firstWhere((j) => j.type == JunctionType.tJunction);
      expect(tJunction.touchedWallBodyId, 'through');
      // through-wall은 여전히 하나의 wall로 남아 있어야 한다(§7 — split하지 않음).
      expect(result.walls.where((w) => w.id == 'through'), hasLength(1));
    });

    test('4방향이 만나면 xJunction', () {
      final draft = _draft([
        _wall('h1', 0, 0, 500, 0),
        _wall('h2', 500, 0, 1000, 0),
        _wall('v1', 500, -400, 500, 0),
        _wall('v2', 500, 0, 500, 400),
      ]);
      final result = buildJunctionDraft(draft, junctionMergeToleranceMm: 5);
      final x = result.junctions.values.firstWhere((j) => j.degree == 4);
      expect(x.type, JunctionType.xJunction);
    });

    test('고립된 끝(다른 벽과 mergeTolerance/reviewBand 밖) — end', () {
      final draft = _draft([_wall('solo', 0, 0, 1000, 0)]);
      final result = buildJunctionDraft(draft, junctionMergeToleranceMm: 5, reviewBandMultiplier: 3);
      expect(result.junctions.values.every((j) => j.type == JunctionType.end), isTrue);
    });
  });

  group('buildJunctionDraft — §8 grid snap과 junction merge 분리', () {
    test('raw 거리가 mergeTolerance보다 멀면 snap 좌표가 우연히 같아져도 병합하지 않는다(preventedNearMissMerges로 집계)', () {
      // mergeTolerance=5mm. 두 점은 raw로 12mm 떨어져 있어 병합 안 됨.
      // 5mm grid에서 둘 다 (100,0)/(112,0)이 각각 100/110으로 스냅되어
      // 실제로는 우연히 같아지지 않도록, 정확히 같은 칸으로 떨어지는
      // 값을 의도적으로 고른다: 102와 108은 각각 100/110으로 다르게
      // 스냅되므로, 같은 칸이 되도록 101과 104를 쓴다(둘 다 5mm grid에서
      // 100 또는 105로... 101->100, 104->105로 다르다). 같은 칸이
      // 되도록 102(->100)와 103(->105)도 다르다. 정확히 "같은 칸,
      // mergeTolerance 밖" 조건을 만들려면 grid 절반(2.5mm) 근처에서
      // mergeTolerance보다 먼 두 raw 값을 같은 배수 쪽으로 스냅되게
      // 고른다: 100.4와 109.6은 각각 100/110으로 다르다. 대신 grid=5
      // 에서 "같은 칸" 폭은 5mm이므로, mergeTolerance를 grid보다 작게
      // (예: 2mm) 설정하면 같은 칸(예: 100~102.4 모두 100으로 스냅)
      // 안에서도 raw 거리가 2mm를 넘는 두 점을 쉽게 만들 수 있다.
      final draft = _draft([
        _wall('a', 0, 0, 100.3, 0),
        _wall('b', 500, 0, 102.4, 0),
      ]);
      final result = buildJunctionDraft(draft, gridMm: 5, junctionMergeToleranceMm: 1.0);
      // a의 끝점(100.3,0)과 b의 끝점(102.4,0) — raw거리 2.1mm > mergeTolerance(1.0mm)
      // 이므로 병합되지 않아야 하지만, 둘 다 5mm grid에서 100으로 스냅된다.
      expect(result.stats.preventedNearMissMerges, greaterThan(0));
      // 병합되지 않았으므로 서로 다른 Junction이어야 한다.
      final aEndJunction = result.walls.firstWhere((w) => w.id == 'a').endJunctionId;
      final bEndJunction = result.walls.firstWhere((w) => w.id == 'b').endJunctionId;
      expect(aEndJunction, isNot(bEndJunction));
    });
  });

  group('buildJunctionDraft — §9 axis-preserving snap(회귀 테스트, 핵심)', () {
    test('사각형(4벽) + 한쪽 벽 body에 닿는 T자 파티션 — snap 후에도 4개 외곽벽이 완전히 수평/수직을 유지한다', () {
      // 실제 Image 3에서 발견된 실패 패턴의 최소 재현: 사각형 외곽 +
      // T-junction으로 붙는 파티션이 있을 때, 파티션이 닿는 지점의
      // 국소 평균 때문에 그 벽의 다른 쪽 끝(반대편 코너)까지 영향을
      // 받아 미세하게 기울어지면 안 된다.
      final draft = _draft([
        _wall('top', 0, 0, 1000, 0),
        _wall('bottom', 0, 800, 1000, 800),
        _wall('left', 0, 0, 0, 800),
        _wall('right', 1000, 0, 1000, 800),
        _wall('partition', 500, 0, 500, 800), // top/bottom 둘 다에 T로 닿음.
      ]);
      final result = buildJunctionDraft(draft, gridMm: 5, junctionMergeToleranceMm: 5);

      RealMmWall wallOf(String id) => draft.walls.firstWhere((w) => w.id == id);
      RealMmPoint snappedStartOf(String id) {
        final jw = result.walls.firstWhere((w) => w.id == id);
        return result.snappedPointOf(jw.startJunctionId);
      }

      RealMmPoint snappedEndOf(String id) {
        final jw = result.walls.firstWhere((w) => w.id == id);
        return result.snappedPointOf(jw.endJunctionId);
      }

      for (final id in ['top', 'bottom']) {
        expect(snappedStartOf(id).yMm, snappedEndOf(id).yMm, reason: '$id 벽은 가로벽이므로 두 끝 y좌표가 snap 후에도 정확히 같아야 한다(기울어지면 안 됨)');
      }
      for (final id in ['left', 'right', 'partition']) {
        expect(snappedStartOf(id).xMm, snappedEndOf(id).xMm, reason: '$id 벽은 세로벽이므로 두 끝 x좌표가 snap 후에도 정확히 같아야 한다(기울어지면 안 됨)');
      }
      // wallOf는 회귀 의도를 남기기 위한 참고용(실제 assert에는 미사용).
      expect(wallOf('top').rawStart.yMm, 0);
    });
  });

  group('buildJunctionDraft — 벽 손실 감지', () {
    test('아주 짧은 벽의 양 끝이 snap 후 같은 grid 칸으로 뭉개지면 wallsLostToZeroLength로 집계된다', () {
      final draft = _draft([
        _wall('tiny', 100, 100, 101, 100), // 길이 1mm, 5mm grid에서 둘 다 100으로 스냅될 가능성.
      ]);
      final result = buildJunctionDraft(draft, gridMm: 5, junctionMergeToleranceMm: 5);
      expect(result.stats.wallsLostToZeroLength, 1);
    });
  });
}
