import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart';

/// 2D CAD geometry(mm 실측/추정값) → 실제 3D 공간 geometry 변환 결과.
///
/// 좌표계: X=가로, Z=깊이(평면도의 세로 방향), Y=높이(위) — mm 단위.
/// 원점은 도면 좌상단이다. 렌더러(궤도 카메라)만 이 모델을 소비하며,
/// 2D CAD 모델([CadFloorPlan])과는 완전히 분리된 layer다(WO 13번 —
/// 향후 벽/바닥/천장 선택, 재질, 색상, 가구를 이 삼각형 목록 위에
/// 얹을 수 있도록 [SpaceTriangle.sourceId]/[SpaceTriangle.sourceKind]로
/// "어느 2D geometry에서 왔는지"를 항상 유지한다).
enum SpaceElementKind { wall, floor }

@immutable
class SpaceTriangle {
  const SpaceTriangle({
    required this.a,
    required this.b,
    required this.c,
    required this.color,
    required this.sourceKind,
    required this.sourceId,
    this.isExteriorWall = false,
  });

  final Vector3 a;
  final Vector3 b;
  final Vector3 c;
  final Color color;

  /// 이 삼각형이 어떤 2D CAD geometry([CadWall.id]/[CadRoom.id])에서
  /// 생성됐는지 — 아직 선택/피킹 기능은 없지만(WO 14번, 이번 범위 밖),
  /// 나중에 화면 ray를 이 삼각형들과 교차시켜 넣을 수 있도록 지금부터
  /// 값을 채워 둔다.
  final SpaceElementKind sourceKind;
  final String sourceId;

  /// 실기 FAIL 재수정 WO(20번) — "집을 위에서 비스듬히 잘라서 내부가
  /// 보이는" 아이소를 만들기 위해, 렌더러가 카메라 쪽을 향한 외벽만
  /// 선택적으로 숨긴다(cutaway). 바닥/내벽은 절대 숨기지 않는다 — 항상
  /// false.
  final bool isExteriorWall;

  Vector3 get normal {
    final ab = b - a;
    final ac = c - a;
    final n = ab.cross(ac);
    final len = n.length;
    return len == 0 ? Vector3(0, 1, 0) : n / len;
  }

  Vector3 get centroid => (a + b + c) / 3.0;
}

/// 도면 전체를 3D로 옮긴 결과 — 궤도 카메라가 화면에 맞추기 위한 bounding
/// box와, 실제로 무엇을 생성했는지/못 했는지에 대한 사용자용 경고를
/// 함께 담는다(가짜 3D 금지 원칙을 결과에도 그대로 유지 — 눈에 보이는
/// 것과 실제로 만든 것이 다르면 안 된다).
@immutable
class SpaceScene {
  const SpaceScene({
    required this.triangles,
    required this.minBounds,
    required this.maxBounds,
    required this.wallCount,
    required this.floorCount,
    required this.warnings,
  });

  final List<SpaceTriangle> triangles;
  final Vector3 minBounds;
  final Vector3 maxBounds;

  final int wallCount;
  final int floorCount;

  /// "문/창 opening은 이번 1차 구현에서 벽에 반영되지 않았습니다" 같은,
  /// 실제로 생성되지 않은 부분을 사용자에게 정직하게 알리는 문구.
  final List<String> warnings;

  Vector3 get center => (minBounds + maxBounds) / 2.0;

  double get boundingRadius => (maxBounds - minBounds).length / 2.0;

  bool get isEmpty => triangles.isEmpty;
}
