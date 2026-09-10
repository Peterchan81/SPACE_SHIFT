/// WO095-B — "3D 아이소 Architectural Dollhouse 표현"의 순수 geometry
/// 로직. [Space3DViewGpuV2](space_3d_view_gpu_v2.dart)에서 분리해
/// three_js/위젯 없이 단위 테스트할 수 있게 한다.
///
/// 이전 버전들(WO093~WO095-A)은 모두 "벽 하나하나에 대해 무엇을 할지"를
/// 판정했다 — 카메라 시선을 가로막는 벽을 통째로 숨기거나(WO093/094),
/// 카메라 반대편(뒤쪽) 벽만 골라 전체 높이로 남기고 나머지를 낮추는
/// 방식(WO095-A)이었다. 실측(평면도.PNG, 벽 86개)으로 재현하면 두
/// 방식 모두 "벽 개별 판정"이 실제 벽 분포(조밀한 방 클러스터 등)에
/// 따라 들쭉날쭉해져 문제를 재현했다 — WO095-A 재현 결과, "뒤쪽"으로
/// 뽑힌 9개 벽이 전부 건물 외곽이 아니라 한 구석에 조밀하게 몰린 작은
/// 방 클러스터의 내부 칸막이벽이었다(사용자 판정: "왼쪽 위에 큰
/// full-height 벽 덩어리").
///
/// WO095-B — 벽 단위 판정을 완전히 버리고, 실제 건축 Dollhouse/section
/// view 도구처럼 "건물 전체에 적용되는 단일 절단면(clip plane)"으로
/// 교체한다. 벽 mesh는 항상 원래 전체 높이 그대로 두고, GPU
/// clipping(three_js의 `Material.clipping` + `renderer.clippingPlanes`,
/// 표준 three.js 기능)으로 카메라 쪽 근처만 기하학적으로 잘라낸다 —
/// 벽이 몇 개든 어떻게 분포하든 항상 매끈한 단면 하나로 결과가
/// 일관된다. 이 파일은 그 절단면의 위치(순수 스칼라 계산)만 계산하고,
/// 실제 [three.Plane] 생성·[Material.clipping] 적용은 위젯에서 한다.
library;

/// [cutFraction]을 계산한다 — 카메라가 [referenceDistance](기본 아이소
/// 진입 거리)만큼 멀리 있으면 [baseFraction](기본 30% 절단)을 그대로
/// 쓰고, 확대해서 카메라가 가까워질수록(작은 방을 들여다보려 할 때)
/// [minFraction]까지 선형으로 줄어든다 — 절단 비율이 줄면 카메라 쪽으로
/// 더 가까운 지점까지만 잘리므로, 확대할수록 "지금 보고 있는 근처"의
/// 벽도 점점 더 열린다("작은 방을 확대하면 내부까지 보여야 한다" 요구
/// 대응). [orbitDistance]가 [referenceDistance]보다 멀어지는(축소하는)
/// 경우는 1.0으로 clamp해 [baseFraction]을 넘지 않는다 — 전체 조망보다
/// 더 많이 잘라낼 필요는 없다.
double computeIsoSectionCutFraction({
  required double orbitDistance,
  required double referenceDistance,
  double baseFraction = 0.3,
  double minFraction = 0.08,
}) {
  if (referenceDistance <= 0) return baseFraction;
  final ratio = (orbitDistance / referenceDistance).clamp(0.0, 1.0);
  return minFraction + (baseFraction - minFraction) * ratio;
}

/// 카메라([cameraX]/[cameraZ])에서 시선 방향([dirX]/[dirZ], 정규화된
/// XZ 벡터)을 기준으로 [boundingCornersXZ](보통 scene 전체 bounding
/// box의 4개 XZ 모서리)를 그 방향에 투영해 깊이 범위를 구하고, 그중
/// [cutFraction] 지점을 절단 위치로 돌려준다. 벽 하나하나가 아니라
/// "건물 전체의 bounding box"를 기준으로 삼으므로, 벽이 조밀하게 몰린
/// 구석이 있어도 절단 위치가 왜곡되지 않는다(WO095-A의 핵심 결함
/// 수정 — § 위 문서).
///
/// [minDepth]/[maxDepth]도 함께 돌려줘서 호출부가 diagnostic/테스트에서
/// 그대로 확인할 수 있게 한다.
({double cutDepth, double minDepth, double maxDepth}) computeIsoSectionCut({
  required double cameraX,
  required double cameraZ,
  required double dirX,
  required double dirZ,
  required List<(double, double)> boundingCornersXZ,
  required double cutFraction,
}) {
  var minDepth = double.infinity;
  var maxDepth = -double.infinity;
  for (final corner in boundingCornersXZ) {
    final depth = (corner.$1 - cameraX) * dirX + (corner.$2 - cameraZ) * dirZ;
    if (depth < minDepth) minDepth = depth;
    if (depth > maxDepth) maxDepth = depth;
  }
  if (!minDepth.isFinite || !maxDepth.isFinite) {
    return (cutDepth: 0, minDepth: 0, maxDepth: 0);
  }
  final cutDepth = minDepth + (maxDepth - minDepth) * cutFraction;
  return (cutDepth: cutDepth, minDepth: minDepth, maxDepth: maxDepth);
}
