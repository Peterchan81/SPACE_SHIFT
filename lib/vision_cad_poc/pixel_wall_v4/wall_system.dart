// SPACE SHIFT — PC1 CONTINUE: FLOOR DOMAIN FIRST + PHYSICAL ROOM / SEMANTIC
// ZONE SPLIT.
//
// "13 semantic spaces = 13 closed physical polygons" 가정을 폐기하고
// (§1), 벽으로 실제로 닫힌 PhysicalRoom과 벽 없이 의미만 다른
// SemanticZone을 구분하는 최소 canonical 모델(§10). 기존
// pixel_wall_v4 파이프라인을 확장하며, 대규모 재작성은 하지 않는다.

import 'dart:math' as math;

import '../../models/floor_plan_geometry.dart';
import 'pixel_wall_types.dart';

/// 같은 물리적 wall axis 위 두 segment 사이 gap의 성격.
enum GapKind {
  /// 아주 작은(수 px) 끊김 — anti-alias/노이즈, 이미 상류에서 대부분
  /// 병합되지만 방어적으로 유지.
  imageBreak,

  /// 문/창 크기 범위의 gap — 물리 벽은 끊겨 있지만 실제로는 출입구.
  doorOpening,

  /// 문 크기를 넘는 넓은 gap이면서 내부 벽인 경우 — 원본 도면 자체가
  /// 벽 없이 열린 구조(open-plan)라는 뜻. 강제로 잇지 않는다.
  openPlan,

  /// 문 크기를 넘는 넓은 gap인데 외벽인 경우 — 건물 외곽은 항상 닫혀
  /// 있어야 하므로, 이건 실제로 pixel 검출이 놓친 구간일 가능성이 높다.
  /// 조용히 잇지 않고 root cause로 보고한다.
  notConnected,
}

class WallGap {
  const WallGap({required this.gapPx, required this.kind, required this.centerPx});
  final double gapPx;
  final GapKind kind;
  final ({double x, double y}) centerPx;
}

/// §10 VirtualBoundary — 실제 벽 evidence는 없지만(문/창 gap이거나 아주
/// 작은 끊김) topology 계산(FloorDomain 닫힘, PhysicalRoom 연결성)에서만
/// "연결됐다"고 취급하기 위한 가상 경계. CANONICAL CAD에는 실선으로
/// 그리지 않는다(§11/§12).
class VirtualBoundary {
  const VirtualBoundary({required this.start, required this.end, required this.reason});
  final Point2 start;
  final Point2 end;
  final GapKind reason;
}

/// 같은 축(orientation + crossPx) 위에 있는 여러 물리 pixel segment를
/// 하나의 "벽 체계"로 묶은 것 — §4 WALL CONSOLIDATION.
class WallSystem {
  const WallSystem({
    required this.orientation,
    required this.axisPx,
    required this.isExterior,
    required this.segments,
    required this.gaps,
  });

  final PixelWallOrientation orientation;

  /// 대표 cross-axis 위치(길이 가중 평균, px, 분석 해상도 기준).
  final double axisPx;
  final bool isExterior;

  /// along-axis 순서로 정렬된 물리 segment들(§10 PhysicalWallSegment 역할).
  final List<PixelWallCandidate> segments;

  /// segments[i]와 segments[i+1] 사이 gap (길이 = segments.length - 1).
  final List<WallGap> gaps;
}

const double _axisTolerancePx = 10.0;
const double _doorRangeMinPx = 4.0;
const double _doorRangeMaxPx = 65.0;

GapKind classifyGap(double gapPx, {required bool isExterior}) {
  if (gapPx <= _doorRangeMinPx) return GapKind.imageBreak;
  if (gapPx <= _doorRangeMaxPx) return GapKind.doorOpening;
  return isExterior ? GapKind.notConnected : GapKind.openPlan;
}

/// structural candidate만 대상으로 wall system을 만든다(reviewNeeded는
/// 이미 별도로 분류됨 — pixel_wall_classifier.dart).
List<WallSystem> buildWallSystems({
  required List<PixelWallCandidate> candidates,
  required int w,
  required int h,
}) {
  final structural = candidates.where((c) => c.category == PixelWallCategory.structural).toList();

  double crossPx(PixelWallCandidate c) =>
      c.orientation == PixelWallOrientation.horizontal ? c.start.y * h : c.start.x * w;
  double alongMinPx(PixelWallCandidate c) =>
      c.orientation == PixelWallOrientation.horizontal ? math.min(c.start.x, c.end.x) * w : math.min(c.start.y, c.end.y) * h;
  double alongMaxPx(PixelWallCandidate c) =>
      c.orientation == PixelWallOrientation.horizontal ? math.max(c.start.x, c.end.x) * w : math.max(c.start.y, c.end.y) * h;
  double lengthPx(PixelWallCandidate c) => alongMaxPx(c) - alongMinPx(c);

  final systems = <WallSystem>[];
  for (final orientation in PixelWallOrientation.values) {
    final group = structural.where((c) => c.orientation == orientation).toList();
    final used = List<bool>.filled(group.length, false);
    for (var i = 0; i < group.length; i++) {
      if (used[i]) continue;
      final cluster = <PixelWallCandidate>[group[i]];
      used[i] = true;
      final anchorCross = crossPx(group[i]);
      for (var j = i + 1; j < group.length; j++) {
        if (used[j]) continue;
        if ((crossPx(group[j]) - anchorCross).abs() <= _axisTolerancePx) {
          cluster.add(group[j]);
          used[j] = true;
        }
      }
      cluster.sort((a, b) => alongMinPx(a).compareTo(alongMinPx(b)));

      final totalLen = cluster.fold<double>(0, (sum, c) => sum + math.max(lengthPx(c), 1));
      final weightedAxis = cluster.fold<double>(0, (sum, c) => sum + crossPx(c) * math.max(lengthPx(c), 1)) / totalLen;
      final exteriorVotes = cluster.where((c) => c.isExterior).length;
      final isExterior = exteriorVotes * 2 >= cluster.length;

      final gaps = <WallGap>[];
      for (var k = 0; k < cluster.length - 1; k++) {
        final gapPx = alongMinPx(cluster[k + 1]) - alongMaxPx(cluster[k]);
        if (gapPx <= 0) continue; // 겹침 — 이미 상류에서 병합됐어야 함, 방어적으로 skip.
        final kind = classifyGap(gapPx, isExterior: isExterior);
        final centerAlong = (alongMaxPx(cluster[k]) + alongMinPx(cluster[k + 1])) / 2;
        final center = orientation == PixelWallOrientation.horizontal
            ? (x: centerAlong, y: weightedAxis)
            : (x: weightedAxis, y: centerAlong);
        gaps.add(WallGap(gapPx: gapPx, kind: kind, centerPx: center));
      }

      systems.add(WallSystem(orientation: orientation, axisPx: weightedAxis, isExterior: isExterior, segments: cluster, gaps: gaps));
    }
  }
  return systems;
}
