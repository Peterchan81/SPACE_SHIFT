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
  double alongOf(PixelWallCandidate c, PixelWallOrientation o, bool isMin) {
    final a = o == PixelWallOrientation.horizontal ? c.start.x * w : c.start.y * h;
    final b = o == PixelWallOrientation.horizontal ? c.end.x * w : c.end.y * h;
    return isMin ? math.min(a, b) : math.max(a, b);
  }

  // 실기 FAIL 재조사(PC1 CONTINUE §10 진단: "B. exterior classification
  // 오류") — WallSystem.isExterior는 클러스터 내 다수결이라, 진짜 외벽
  // 1개 + 진짜 내벽 1개가 같은 축 근처에 우연히 묶이면 동률(1:1)로
  // 시스템 전체가 잘못 "외벽"이 돼 버렸다(실측: 두 gap 모두 이 패턴).
  // 시스템 단위가 아니라 "그 시스템에 속한 개별 segment 중 실제로
  // isExterior=true인 것"만 걸러 사용한다 — 다수결로 다른 segment의
  // 개별 판정을 덮어쓰지 않는다.
  final exteriorSegmentsBySystem = <(PixelWallOrientation orientation, double axisPx, List<PixelWallCandidate> segs)>[];
  for (final system in wallSystems) {
    final segs = system.segments.where((s) => s.isExterior).toList()
      ..sort((a, b) => alongOf(a, system.orientation, true).compareTo(alongOf(b, system.orientation, true)));
    if (segs.isNotEmpty) {
      exteriorSegmentsBySystem.add((system.orientation, system.axisPx, segs));
    }
  }
  if (exteriorSegmentsBySystem.isEmpty) {
    return const FloorDomainResult(
      loop: null,
      failureReason: '외벽으로 분류된 wall system이 없음',
      virtualBoundaries: [],
      unresolvedGaps: [],
    );
  }

  final runs = <_WallRun>[];
  final virtualBoundaries = <VirtualBoundary>[];
  final unresolvedGaps = <WallGap>[];

  for (final entry in exteriorSegmentsBySystem) {
    final (orientation, axisPx, segs) = entry;
    var runStartAlong = alongOf(segs.first, orientation, true);
    var runEndAlong = alongOf(segs.first, orientation, false);

    void flushRun() {
      runs.add(_WallRun(orientation: orientation, axisPx: axisPx, startAlongPx: runStartAlong, endAlongPx: runEndAlong));
    }

    for (var i = 0; i < segs.length - 1; i++) {
      final cur = segs[i];
      final next = segs[i + 1];
      final gapPx = alongOf(next, orientation, true) - alongOf(cur, orientation, false);
      if (gapPx <= 0) {
        // 겹침(이미 병합됐어야 함) — 방어적으로 이어붙인다.
        runEndAlong = alongOf(next, orientation, false);
        continue;
      }
      final kind = classifyGap(gapPx, isExterior: true);
      if (kind == GapKind.imageBreak || kind == GapKind.doorOpening) {
        final bridgeStart = orientation == PixelWallOrientation.horizontal
            ? Point2(alongOf(cur, orientation, false) / w, axisPx / h)
            : Point2(axisPx / w, alongOf(cur, orientation, false) / h);
        final bridgeEnd = orientation == PixelWallOrientation.horizontal
            ? Point2(alongOf(next, orientation, true) / w, axisPx / h)
            : Point2(axisPx / w, alongOf(next, orientation, true) / h);
        virtualBoundaries.add(VirtualBoundary(start: bridgeStart, end: bridgeEnd, reason: kind));
        runEndAlong = alongOf(next, orientation, false);
      } else {
        flushRun();
        final centerAlong = (alongOf(cur, orientation, false) + alongOf(next, orientation, true)) / 2;
        final center = orientation == PixelWallOrientation.horizontal ? (x: centerAlong, y: axisPx) : (x: axisPx, y: centerAlong);
        unresolvedGaps.add(WallGap(gapPx: gapPx, kind: kind, centerPx: center));
        runStartAlong = alongOf(next, orientation, true);
        runEndAlong = alongOf(next, orientation, false);
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
