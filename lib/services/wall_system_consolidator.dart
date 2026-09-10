import '../models/cad_floor_plan.dart';
import '../models/floor_plan_geometry.dart';
import '../vision_cad_poc/pixel_wall_v4/pixel_wall_types.dart';
import '../vision_cad_poc/pixel_wall_v4/wall_system.dart';

/// SS CAD TEST — Wall Consolidation & Topology Closure WO.
///
/// [buildWallSystems](wall_system.dart, 이미 존재/검증된 코드)는 같은 축
/// 위의 raw pixel segment들을 이미 "같은 물리 벽"으로 묶어 두었다 — 이
/// 파일은 그 결과를 다시 만들지 않고, 그 안의 [WallSystem.segments]를
/// 하나의 연속된 벽 구간으로 병합해 topology 재구성 입력을 훨씬 적은
/// 수의(과분절되지 않은) 벽으로 줄인다.
///
/// 중요한 예외: 문/작은 끊김(door/imageBreak) gap만 이어 붙인다.
/// open-plan/notConnected gap(원본 도면 자체가 벽 없이 열려 있거나,
/// pixel 검출이 실제로 놓친 넓은 구간)까지 이어 버리면 "원본에 없는
/// 벽을 만드는" 것이므로, 그 지점에서는 반드시 별도 벽으로 남긴다
/// (gap 자체는 지어내지 않고 그대로 끊어 둔다 — WO 절대 금지 원칙).
List<CadWall> consolidateWallSystems(List<WallSystem> systems, {required int w, required int h}) {
  final result = <CadWall>[];

  Point2 systemPoint(PixelWallOrientation orientation, double axisPx, double alongPx) {
    return orientation == PixelWallOrientation.horizontal ? Point2(alongPx / w, axisPx / h) : Point2(axisPx / w, alongPx / h);
  }

  double alongMinPx(PixelWallCandidate c, PixelWallOrientation o) {
    if (o == PixelWallOrientation.horizontal) {
      return (c.start.x < c.end.x ? c.start.x : c.end.x) * w;
    }
    return (c.start.y < c.end.y ? c.start.y : c.end.y) * h;
  }

  double alongMaxPx(PixelWallCandidate c, PixelWallOrientation o) {
    if (o == PixelWallOrientation.horizontal) {
      return (c.start.x > c.end.x ? c.start.x : c.end.x) * w;
    }
    return (c.start.y > c.end.y ? c.start.y : c.end.y) * h;
  }

  for (final system in systems) {
    final segments = system.segments;
    if (segments.isEmpty) continue;

    var runStart = 0;
    for (var i = 0; i <= segments.length; i++) {
      final isEnd = i == segments.length;
      // segments[i-1]과 segments[i] 사이 gap이 door/imageBreak가 아니면
      // (open-plan/notConnected) 여기서 run을 끊는다 — 그 구간은 지어내지
      // 않고 별도 벽으로 남긴다.
      final shouldCutBeforeI = !isEnd && i > 0 && i - 1 < system.gaps.length
          ? (system.gaps[i - 1].kind != GapKind.doorOpening && system.gaps[i - 1].kind != GapKind.imageBreak)
          : false;
      if (isEnd || shouldCutBeforeI) {
        final run = segments.sublist(runStart, i);
        if (run.isNotEmpty) {
          final runMin = run.map((c) => alongMinPx(c, system.orientation)).reduce((a, b) => a < b ? a : b);
          final runMax = run.map((c) => alongMaxPx(c, system.orientation)).reduce((a, b) => a > b ? a : b);
          final maxThickness = run.fold<double>(0, (m, c) => c.thicknessNormalized > m ? c.thicknessNormalized : m);
          final avgConfidence = run.fold<double>(0, (s, c) => s + c.baseConfidence) / run.length;
          result.add(
            CadWall(
              id: '${system.id}-run${result.length}',
              start: systemPoint(system.orientation, system.axisPx, runMin),
              end: systemPoint(system.orientation, system.axisPx, runMax),
              thicknessNormalized: maxThickness,
              wallType: system.isExterior ? CadWallType.exterior : CadWallType.interior,
              confidence: avgConfidence,
            ),
          );
        }
        runStart = i;
      }
    }
  }
  return result;
}
