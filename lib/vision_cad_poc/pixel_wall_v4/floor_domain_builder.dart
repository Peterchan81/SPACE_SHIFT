// SPACE SHIFT — PC1 CONTINUE: FLOOR DOMAIN FIRST.
//
// §6 핵심 목표 — FloorDomain은 semantic space에서 만들지 않고, 실제
// outer structural wall network(WallSystem)에서만 만든다. 문/작은 끊김
// gap은 VirtualBoundary로 이어 닫되(§6 "필요한 연결은 pixel evidence +
// same axis + exterior continuity + junction evidence로 복원"), 문
// 범위를 넘는 넓은 gap은 절대 조용히 잇지 않고 root cause로 보고한다
// (공간 수를 맞추려는 fabricated exterior line 생성 금지).

import 'dart:math' as math;

import '../../models/floor_plan_geometry.dart';
import 'pixel_wall_types.dart';
import 'wall_system.dart';

class FloorDomainResult {
  const FloorDomainResult({
    required this.loop,
    required this.failureReason,
    required this.virtualBoundaries,
    required this.unresolvedGaps,
  });

  /// 닫혔으면 외곽 loop, 아니면 null(§ "fake exterior line 생성 금지").
  final List<Point2>? loop;
  final String? failureReason;
  final List<VirtualBoundary> virtualBoundaries;

  /// 문 범위를 넘겨 조용히 잇지 않은 gap들 — root cause 보고용
  /// (위치 + gap 크기 + 왜 못 이었는지).
  final List<WallGap> unresolvedGaps;

  bool get isValid => loop != null;
}

/// 한 축(system) 안에서 notConnected/openPlan gap을 경계로 "실제로 하나로
/// 이어지는 구간(run)"만 잘라낸다 — doorOpening/imageBreak gap은
/// VirtualBoundary로 이어 하나의 run으로 취급한다.
class _WallRun {
  _WallRun({required this.orientation, required this.axisPx, required this.startAlongPx, required this.endAlongPx});
  final PixelWallOrientation orientation;
  final double axisPx;
  final double startAlongPx;
  final double endAlongPx;

  Point2 startPoint(int w, int h) => orientation == PixelWallOrientation.horizontal
      ? Point2(startAlongPx / w, axisPx / h)
      : Point2(axisPx / w, startAlongPx / h);
  Point2 endPoint(int w, int h) => orientation == PixelWallOrientation.horizontal
      ? Point2(endAlongPx / w, axisPx / h)
      : Point2(axisPx / w, endAlongPx / h);
}

double _distPx(Point2 a, Point2 b, int w, int h) {
  final dx = (a.x - b.x) * w;
  final dy = (a.y - b.y) * h;
  return math.sqrt(dx * dx + dy * dy);
}

FloorDomainResult buildFloorDomain({
  required List<WallSystem> wallSystems,
  required int w,
  required int h,
}) {
  final exteriorSystems = wallSystems.where((s) => s.isExterior).toList();
  if (exteriorSystems.isEmpty) {
    return const FloorDomainResult(
      loop: null,
      failureReason: '외벽으로 분류된 wall system이 없음',
      virtualBoundaries: [],
      unresolvedGaps: [],
    );
  }

  double alongOf(PixelWallCandidate c, PixelWallOrientation o, bool isMin) {
    final a = o == PixelWallOrientation.horizontal ? c.start.x * w : c.start.y * h;
    final b = o == PixelWallOrientation.horizontal ? c.end.x * w : c.end.y * h;
    return isMin ? math.min(a, b) : math.max(a, b);
  }

  final runs = <_WallRun>[];
  final virtualBoundaries = <VirtualBoundary>[];
  final unresolvedGaps = <WallGap>[];

  for (final system in exteriorSystems) {
    var runStartAlong = alongOf(system.segments.first, system.orientation, true);
    var runEndAlong = alongOf(system.segments.first, system.orientation, false);

    void flushRun() {
      runs.add(_WallRun(orientation: system.orientation, axisPx: system.axisPx, startAlongPx: runStartAlong, endAlongPx: runEndAlong));
    }

    for (var i = 0; i < system.gaps.length; i++) {
      final gap = system.gaps[i];
      final nextSeg = system.segments[i + 1];
      if (gap.kind == GapKind.imageBreak || gap.kind == GapKind.doorOpening) {
        final bridgeStart = system.orientation == PixelWallOrientation.horizontal
            ? Point2(alongOf(system.segments[i], system.orientation, false) / w, system.axisPx / h)
            : Point2(system.axisPx / w, alongOf(system.segments[i], system.orientation, false) / h);
        final bridgeEnd = system.orientation == PixelWallOrientation.horizontal
            ? Point2(alongOf(nextSeg, system.orientation, true) / w, system.axisPx / h)
            : Point2(system.axisPx / w, alongOf(nextSeg, system.orientation, true) / h);
        virtualBoundaries.add(VirtualBoundary(start: bridgeStart, end: bridgeEnd, reason: gap.kind));
        runEndAlong = alongOf(nextSeg, system.orientation, false);
      } else {
        // notConnected(외벽에서 문 범위를 넘는 gap) — 조용히 잇지 않고
        // 여기서 run을 끊는다. openPlan은 외벽에서는 이론상 나오지 않지만
        // 방어적으로 동일하게 처리.
        flushRun();
        unresolvedGaps.add(gap);
        runStartAlong = alongOf(nextSeg, system.orientation, true);
        runEndAlong = alongOf(nextSeg, system.orientation, false);
      }
    }
    flushRun();
  }

  if (runs.isEmpty) {
    return const FloorDomainResult(
      loop: null,
      failureReason: '외벽 run이 하나도 만들어지지 않음',
      virtualBoundaries: [],
      unresolvedGaps: [],
    );
  }

  const cornerTolerancePx = 16.0;
  final remaining = [...runs];
  final first = remaining.removeAt(0);
  final loopPoints = <Point2>[first.startPoint(w, h), first.endPoint(w, h)];
  var current = first.endPoint(w, h);

  while (remaining.isNotEmpty) {
    _WallRun? best;
    var useStart = true;
    var bestDist = double.infinity;
    for (final run in remaining) {
      final dStart = _distPx(current, run.startPoint(w, h), w, h);
      final dEnd = _distPx(current, run.endPoint(w, h), w, h);
      if (dStart < bestDist) {
        bestDist = dStart;
        best = run;
        useStart = true;
      }
      if (dEnd < bestDist) {
        bestDist = dEnd;
        best = run;
        useStart = false;
      }
    }
    if (best == null || bestDist > cornerTolerancePx) break;
    remaining.remove(best);
    final next = useStart ? best.endPoint(w, h) : best.startPoint(w, h);
    loopPoints.add(next);
    current = next;
  }

  if (remaining.isNotEmpty) {
    return FloorDomainResult(
      loop: null,
      failureReason: '외벽 run ${remaining.length}개가 인접 run과 코너에서 연결되지 않음(허용오차 ${cornerTolerancePx}px 초과)',
      virtualBoundaries: virtualBoundaries,
      unresolvedGaps: unresolvedGaps,
    );
  }
  final closureDist = _distPx(current, first.startPoint(w, h), w, h);
  if (closureDist > cornerTolerancePx) {
    return FloorDomainResult(
      loop: null,
      failureReason: '외벽 loop가 시작점으로 닫히지 않음(닫힘 거리 ${closureDist.toStringAsFixed(1)}px)',
      virtualBoundaries: virtualBoundaries,
      unresolvedGaps: unresolvedGaps,
    );
  }

  return FloorDomainResult(loop: loopPoints, failureReason: null, virtualBoundaries: virtualBoundaries, unresolvedGaps: unresolvedGaps);
}
