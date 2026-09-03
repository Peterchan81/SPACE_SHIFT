// SPACE SHIFT — Image 2 AI → Real CAD End-to-End POC.
// SS Geometry Solver 단위 테스트 — 실제 Vision proposal(이미지 2 실제
// 분석)에 대해 정규화가 실제로 동작하는지, 그리고 이미 검증된
// TopologyValidator가 그대로 재사용되는지 확인한다.

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/services/e2e_geometry_solver.dart';
import 'package:ason_space/vision_cad_poc/e2e/vision_cad_proposal.dart';

void main() {
  const solver = SSGeometrySolver();

  test('13개 공간이 모두 보존된다', () {
    final result = solver.solve(buildImage2VisionProposal());
    expect(result.model.spaces, hasLength(13));
  });

  test('축이 거의 맞는 벽은 완전히 수평/수직으로 정렬된다', () {
    final result = solver.solve(buildImage2VisionProposal());
    for (final wall in result.model.walls) {
      final dx = (wall.start.x - wall.end.x).abs();
      final dy = (wall.start.y - wall.end.y).abs();
      // 대각선(발코니/실외기실 돌출부 근사 표현) 2개를 제외하면 모든
      // 벽은 완전히 수평(dy=0) 또는 완전히 수직(dx=0)이어야 한다.
      final isAxisAligned = dx == 0 || dy == 0;
      final isKnownDiagonal = wall.id.contains('balcony') || wall.id.contains('mech');
      expect(isAxisAligned || isKnownDiagonal, isTrue, reason: '${wall.id}: dx=$dx dy=$dy');
    }
  });

  test('mid-row 벽은 하나의 연속된 경계로 유지된다(같은 y선 위 다른 벽과 잘못 병합되지 않음)', () {
    final result = solver.solve(buildImage2VisionProposal());
    final midRowWalls = result.model.walls.where((w) => w.id.startsWith('wall-int-mid-row'));
    expect(midRowWalls, isNotEmpty);
    for (final w in midRowWalls) {
      expect(w.start.y, equals(w.end.y));
    }
  });

  test('실외기실/부부거실처럼 vision confidence가 낮은 공간은 reviewNeeded=true다', () {
    final result = solver.solve(buildImage2VisionProposal());
    final mechanical = result.model.spaces.firstWhere((s) => s.id == 'space-mechanical');
    final masterLiving = result.model.spaces.firstWhere((s) => s.id == 'space-masterLiving');
    expect(mechanical.reviewNeeded, isTrue);
    expect(masterLiving.reviewNeeded, isTrue);
  });

  test('confidence가 medium/high인 공간은 그 자체만으로 reviewNeeded가 아니다', () {
    final result = solver.solve(buildImage2VisionProposal());
    final living = result.model.spaces.firstWhere((s) => s.id == 'space-living');
    expect(living.reviewNeeded, isFalse);
  });

  test('FloorDomain polygon이 보존된다(발코니/실외기실 돌출 포함)', () {
    final result = solver.solve(buildImage2VisionProposal());
    expect(result.model.floorDomain, isNotNull);
    expect(result.model.floorDomain!.length, greaterThanOrEqualTo(12));
  });

  test('TopologyValidator가 재사용되어 warnings/reviewNeeded가 채워질 수 있다', () {
    final result = solver.solve(buildImage2VisionProposal());
    // 최소한 topology validator가 실행되었다는 것을 warnings 또는
    // reviewNeeded 존재로 확인한다(정확히 몇 개인지는 solver 세부
    // 구현에 따라 달라질 수 있으므로 존재 여부만 확인).
    final anyReview = result.model.spaces.any((s) => s.reviewNeeded) ||
        result.model.walls.any((w) => w.reviewNeeded) ||
        result.model.openings.any((o) => o.reviewNeeded);
    expect(anyReview, isTrue);
  });

  test('정규화 로그가 실제로 수행한 작업을 설명한다', () {
    final result = solver.solve(buildImage2VisionProposal());
    expect(result.normalizationLog, isNotEmpty);
    expect(result.normalizationLog.any((l) => l.contains('vertex snap')), isTrue);
    expect(result.normalizationLog.any((l) => l.contains('collinear')), isTrue);
  });

  test('문/창은 근처 벽에 부착되어 wallId가 채워진다', () {
    final result = solver.solve(buildImage2VisionProposal());
    final attachedCount = result.model.openings.where((o) => o.wallId != null).length;
    expect(attachedCount, greaterThan(result.model.openings.length ~/ 2));
  });

  test('Point2는 정확히 축 정렬되어 있어 직각 검증이 가능하다(부동소수점 오차 없음)', () {
    final result = solver.solve(buildImage2VisionProposal());
    final vertical = result.model.walls.firstWhere((w) => w.id == 'wall-int-living-bed2');
    expect(vertical.start.x, equals(vertical.end.x));
  });
}
