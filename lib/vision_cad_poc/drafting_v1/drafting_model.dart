// SPACE SHIFT — WO088-4 PHASE B: DRAFTING COORDINATE MODEL POC.
//
// structural_layer.dart(Flutter-free)의 [RawStructuralLine] 결과를
// "CAD 제도" 개념(Origin, X/Y axis, 0/90° 분류, 실제 사선 보존)으로
// 감싼다. 이 파일도 Flutter에 의존하지 않는다 — Point2(floor_plan_geometry.dart)
// 대신 이 모듈 전용 [Pt] 레코드를 그대로 재사용한다(§23 — 기존
// WallSystem/PlanarGraph/FloorDomain/CadFloorPlan/RealWorldScale을
// 전혀 참조하지 않는, 완전히 독립된 POC 경로).
//
// §17 — RealWorldScale(WO088-2)은 여기서 다시 만들지 않는다. 이 파일이
// 만드는 좌표는 "virtual"(px 단위, Origin 상대) 그대로이고, mm 변환은
// 이후 단계에서 coord_real_scale.dart류의 기존 변환기를 그대로 연결해야
// 한다(이번 WO 범위 아님).

import 'dart:math' as math;

import 'structural_layer.dart';

/// §12 — 개별 wall의 각도 분류. 이 POC의 axis-aligned run-length
/// extractor는 애초에 정확히 0°/90°만 검출하므로(구성상 각도 오차가
/// 없다) Image 3 결과에서는 사실상 전부 orthogonalConfirmed로 나온다 —
/// 이 분류 자체는 향후 sub-degree 각도를 실측하는 확장 extractor(예:
/// Hough류)를 위해 미리 마련해 둔 일반 구조다(정직하게 보고: 이번
/// 결과에서 이 정책이 실제로 시험되지는 않았다).
enum WallAngleClass { orthogonalConfirmed, orthogonalCandidate, diagonalConfirmed, reviewNeeded }

/// §12 — 벽 하나의 측정 각도(0~360, atan2 기반)와 길이(px)로부터 분류를
/// 정한다. 허용오차를 고정 상수(10°/20°/30°)로 박지 않고, "이 벽 길이에서
/// 1.5px 위치 오차가 만드는 각도 오차"로 유도한다(짧은 벽일수록 관대,
/// 긴 벽일수록 엄격 — 픽셀 양자화 노이즈에 대한 일반적인 근거).
WallAngleClass classifyWallAngle(double angleDeg, double lengthPx) {
  final normalized = angleDeg % 90;
  final distToAxis = math.min(normalized, 90 - normalized);
  final toleranceDeg = (math.atan(1.5 / math.max(lengthPx, 1)) * 180 / math.pi).clamp(0.3, 5.0);
  if (distToAxis <= toleranceDeg) return WallAngleClass.orthogonalConfirmed;
  if (distToAxis <= toleranceDeg * 3) return WallAngleClass.orthogonalCandidate;
  // 30°는 "직교로 볼 수 없다"는 확정적 컷오프로만 쓴다(POC 정책 — 이번
  // Image 3 evidence에서는 이 분기를 타는 벽이 실제로 없었다).
  if (distToAxis >= 30) return WallAngleClass.diagonalConfirmed;
  return WallAngleClass.reviewNeeded;
}

class DraftWall {
  const DraftWall({
    required this.id,
    required this.startVirtual,
    required this.endVirtual,
    required this.thicknessPx,
    required this.angleDeg,
    required this.classification,
    required this.method,
  });

  final String id;

  /// Origin 기준 virtual 좌표(px 단위, CAD 관례로 +Y가 위쪽).
  final Pt startVirtual;
  final Pt endVirtual;
  final double thicknessPx;
  final double angleDeg;
  final WallAngleClass classification;

  /// structural_layer.dart의 RawStructuralLine.method 그대로 보존
  /// (axisAligned | localDeskew:ANGLE) — provenance 유지.
  final String method;

  double get lengthPx {
    final dx = endVirtual.x - startVirtual.x;
    final dy = endVirtual.y - startVirtual.y;
    return math.sqrt(dx * dx + dy * dy);
  }
}

class DraftCorner {
  const DraftCorner({required this.id, required this.point, required this.wallIds});
  final String id;
  final Pt point;
  final List<String> wallIds;
}

class DraftingModel {
  const DraftingModel({required this.originPixel, required this.walls, required this.corners});

  /// Origin으로 선택된 corner의 원본(회전 없음) 분석 캔버스 px 좌표 —
  /// 이 값 자체가 "왜 이 점인지"를 추적할 수 있는 근거로 그대로 남는다
  /// (§10 — 코드에 pixel magic coordinate로 영구 hardcode하지 않는다;
  /// 이 값은 [findBottomLeftmostCorner] 같은 선택 함수의 "결과"이지,
  /// 소스에 박아 넣은 상수가 아니다).
  final Pt originPixel;
  final List<DraftWall> walls;
  final List<DraftCorner> corners;
}

double _dist(Pt a, Pt b) {
  final dx = a.x - b.x, dy = a.y - b.y;
  return math.sqrt(dx * dx + dy * dy);
}

/// §7/§20.A corner 근접 클러스터링 허용오차(px) — 실제 벽 두께
/// (production 관례상 6~18px) 규모에 맞춘 값. structural_layer.dart의
/// minRunPx/maxThicknessPx와 같은 성격의 "이미지 전체에 동일 적용되는"
/// 값이지 Image 3 전용 튜닝이 아니다.
const double kCornerClusterTolerancePx = 10.0;

List<({Pt point, List<String> wallIds})> _clusterCorners(List<RawStructuralLine> lines) {
  final endpoints = <(Pt point, String id)>[
    for (final l in lines) (l.start, l.id),
    for (final l in lines) (l.end, l.id),
  ];
  final used = List<bool>.filled(endpoints.length, false);
  final out = <({Pt point, List<String> wallIds})>[];
  for (var i = 0; i < endpoints.length; i++) {
    if (used[i]) continue;
    final (anchor, firstId) = endpoints[i];
    used[i] = true;
    final ids = <String>{firstId};
    var sx = anchor.x, sy = anchor.y, count = 1;
    for (var j = i + 1; j < endpoints.length; j++) {
      if (used[j]) continue;
      final (p, id) = endpoints[j];
      if (_dist(anchor, p) <= kCornerClusterTolerancePx) {
        used[j] = true;
        ids.add(id);
        sx += p.x;
        sy += p.y;
        count++;
      }
    }
    out.add((point: (x: sx / count, y: sy / count), wallIds: ids.toList()));
  }
  return out;
}

/// §10 Origin 자동 선택 기본 휴리스틱 — "가장 아래-왼쪽" corner를
/// 고른다(y가 클수록 아래, x가 작을수록 왼쪽 — score=y-x 최대화).
/// 이것은 Image 3 전용 규칙이 아니라 어떤 건물 외곽에도 적용 가능한
/// 일반 규칙이다. 향후 사용자가 직접 corner를 탭해 Origin을 고르는
/// 구조로 이 함수를 대체/우회할 수 있어야 한다(§10 "사용자가 Origin을
/// 선택할 수 있는 구조로 발전").
Pt findBottomLeftmostCorner(List<Pt> cornerPoints) {
  var best = cornerPoints.first;
  var bestScore = best.y - best.x;
  for (final p in cornerPoints.skip(1)) {
    final score = p.y - p.x;
    if (score > bestScore) {
      bestScore = score;
      best = p;
    }
  }
  return best;
}

/// [rawLines](structural_layer.dart 산출)로부터 Drafting Model을 만든다.
/// [originPixel]을 명시적으로 넘기면 그 점을 Origin으로 쓰고, 넘기지
/// 않으면 [findBottomLeftmostCorner] 기본 휴리스틱을 쓴다 — 항상 "왜
/// 이 점인지" 추적 가능한 방식으로 결정된다(하드코딩 아님).
DraftingModel buildDraftingModel(List<RawStructuralLine> rawLines, {Pt? originPixel}) {
  final clustered = _clusterCorners(rawLines);
  final origin = originPixel ?? findBottomLeftmostCorner([for (final c in clustered) c.point]);

  Pt toVirtual(Pt p) => (x: p.x - origin.x, y: -(p.y - origin.y));

  final walls = <DraftWall>[];
  for (final l in rawLines) {
    final sv = toVirtual(l.start);
    final ev = toVirtual(l.end);
    final dx = ev.x - sv.x, dy = ev.y - sv.y;
    final angleDeg = (math.atan2(dy, dx) * 180 / math.pi + 360) % 360;
    final lengthPx = math.sqrt(dx * dx + dy * dy);
    walls.add(
      DraftWall(
        id: l.id,
        startVirtual: sv,
        endVirtual: ev,
        thicknessPx: l.thicknessPx,
        angleDeg: angleDeg,
        classification: classifyWallAngle(angleDeg, lengthPx),
        method: l.method,
      ),
    );
  }

  final corners = <DraftCorner>[
    for (var i = 0; i < clustered.length; i++)
      DraftCorner(id: 'draft-corner-$i', point: toVirtual(clustered[i].point), wallIds: clustered[i].wallIds),
  ];

  return DraftingModel(originPixel: origin, walls: walls, corners: corners);
}
