/// WO093 — "3D 아이소 Cutaway/Dollhouse 표현 수정"의 순수 geometry
/// 판정 로직. [Space3DViewGpuV2](space_3d_view_gpu_v2.dart)에서 분리해
/// three_js/위젯 없이 단위 테스트할 수 있게 한다 — 이 계산이 실제로
/// 정확히 맞는지가 이 WO의 핵심(회전/확대해도 방 내부가 계속 보여야
/// 한다)이라, 위젯에 묻어 두면 Windows/Tab 실기로만 확인할 수 있어
/// 회귀를 놓치기 쉽다.
///
/// 벽 하나는 중심선(XZ 평면, mm)과 높이([WallSegmentXZ.topY], 항상
/// 바닥 Y=0에서 시작한다고 가정)로 표현한다 — 벽 두께까지 반영한
/// 정확한 폴리곤 대신 중심선 하나로 충분히 안정적으로 판단된다(WO
/// 지침 "가장 단순하고 안정적인 방법").
///
/// 처음 구현은 카메라 높이를 무시하고 XZ 평면(위에서 본 평면도)만으로
/// "카메라→방 중심 선이 벽 중심선을 가로지르면 그 벽을 숨긴다"고
/// 판단했는데, 이는 실제로 틀렸다 — 카메라가 아주 멀고 높은 곳에
/// 있으면 평면도상으로는 어떤 벽 위를 "지나가는" 것처럼 보여도, 실제
/// 3D 시선은 그 벽의 낮은 높이보다 훨씬 위를 지나가므로 벽이 시야를
/// 막지 않는다(예: 아파트 반대편 구석에서 내려다볼 때 중간에 있는
/// 낮은 칸막이벽 때문에 먼 방이 안 보이면 안 된다). 그래서 이 버전은
/// 카메라 높이([cameraY])와 각 벽의 실제 높이([WallSegmentXZ.topY])를
/// 함께 반영한 진짜 3D 판정을 한다 — "카메라 → 방 바닥 중심"을 잇는
/// 3D 직선이 XZ 평면에서 벽 중심선과 만나는 지점에서, 그 직선의 Y값이
/// 벽 높이보다 낮을 때만(=벽이 실제로 그 지점의 시선을 가로챌 때만)
/// 그 벽을 숨긴다.
typedef WallSegmentXZ = ({
  String objectId,
  double sx,
  double sz,
  double ex,
  double ez,
  double topY,
});

/// 카메라 위치([cameraX], [cameraY], [cameraZ])에서 각 방 바닥 중심
/// (Y=0, [roomCentroidsXZ])으로의 3D 시선을 가로막는 벽의
/// [WallSegmentXZ.objectId] 집합을 돌려준다. 회전/확대로 카메라가 바뀔
/// 때마다 다시 호출해 "지금 실제로 가로막는 벽"만 정확히 가려낸다 —
/// 고정된 벽 몇 개를 미리 정해 숨기는 방식이 아니다.
Set<String> computeIsoCutawayHiddenWallIds({
  required double cameraX,
  required double cameraY,
  required double cameraZ,
  required List<WallSegmentXZ> wallSegments,
  required List<(double, double)> roomCentroidsXZ,
}) {
  final hidden = <String>{};
  for (final segment in wallSegments) {
    for (final room in roomCentroidsXZ) {
      if (_wallBlocksSightline(
        cameraX: cameraX,
        cameraY: cameraY,
        cameraZ: cameraZ,
        targetX: room.$1,
        targetZ: room.$2,
        wall: segment,
      )) {
        hidden.add(segment.objectId);
        break;
      }
    }
  }
  return hidden;
}

/// "카메라 → (targetX, Y=0, targetZ)" 3D 직선이 [wall]의 XZ 중심선을
/// 가로지르는 지점에서, 그 직선의 실제 Y값이 [wall]의 높이보다 낮으면
/// (=벽이 그 높이까지 서 있어서 실제로 시선을 가로막으면) true.
bool _wallBlocksSightline({
  required double cameraX,
  required double cameraY,
  required double cameraZ,
  required double targetX,
  required double targetZ,
  required WallSegmentXZ wall,
}) {
  // 카메라→타겟(r)과 벽 중심선(s), 두 2D 선분의 교차를 표준
  // 벡터(cross product) 공식으로 계산한다. t는 r 위의 위치(0=카메라,
  // 1=타겟), u는 벽 중심선 위의 위치(0=시작, 1=끝) — 둘 다 [0,1]
  // 안에 있어야 두 "선분"이 실제로 겹친다.
  final rx = targetX - cameraX;
  final rz = targetZ - cameraZ;
  final sx = wall.ex - wall.sx;
  final sz = wall.ez - wall.sz;

  final rxs = rx * sz - rz * sx;
  if (rxs.abs() < 1e-9) {
    // 평행(또는 거의 평행)한 경우 — 드문 경계 케이스라 안전하게
    // "막지 않음"으로 처리한다(과도하게 숨기는 것보다 과소하게
    // 숨기는 쪽이 "선택 기능이 깨진다"는 실패를 피하기에 더 안전하다).
    return false;
  }

  final qpx = wall.sx - cameraX;
  final qpz = wall.sz - cameraZ;
  final t = (qpx * sz - qpz * sx) / rxs;
  final u = (qpx * rz - qpz * rx) / rxs;
  if (t < 0 || t > 1 || u < 0 || u > 1) return false;

  // 교차 지점에서 실제 3D 시선의 높이 — 타겟 Y를 항상 바닥(0)으로
  // 두므로 카메라 높이에서 선형 보간만 하면 된다.
  final sightlineYAtCrossing = cameraY * (1 - t);
  return sightlineYAtCrossing < wall.topY;
}
