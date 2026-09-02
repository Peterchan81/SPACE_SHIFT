import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart';

/// SpaceScene V2 — 기존 [SpaceScene]/[SpaceTriangle](space_scene.dart)을
/// 대체하지 않고 병렬로 존재하는 새 3D geometry 모델이다(NOMPASS V2 WO —
/// "기존 3D 구현에 patch를 계속 추가하지 않는다. 기존 코드는 삭제하지
/// 않되, 새 pipeline을 병렬로 만들고 Windows 실기 PASS 후 교체한다").
///
/// V1과의 핵심 차이:
/// - 바닥은 여전히 room polygon 삼각분할로 만들지만, 벽은 절대 room
///   polygon에서 파생되지 않는다 — 각 [CadWall]로부터 직접 안정적인
///   직육면체(rectangular prism)를 만든다(WO 8/9번).
/// - 모든 좌표가 이미 mm 단위 world 좌표다 — normalized/image 좌표는
///   빌더 내부에서만 쓰이고 이 모델에는 절대 남지 않는다(WO 21번, 2D↔3D
///   좌표계를 명확한 단위로 통일: 2D x→3D X, 2D y→3D Z, 높이→3D Y).
///
/// MASTER(SPACE SHIFT 3D 아이소 작업실) 확장 대비 — 이번 범위에서는 UI를
/// 만들지 않지만, 각 3D 객체가 나중에 "클릭 → 선택 → 우측 패널에서 재질/
/// 색상/크기 편집 → 3D 즉시 갱신"이 가능해야 하므로, 지금부터 모든 mesh가
/// 자신의 CAD 원본(wallId/floorId/roomId/openingId)과 향후 편집에 쓰일
/// 자리(materialId/color/visible/locked/transform/dimensions)를 갖는다.
/// 이번 범위는 이 필드들을 채우기만 하고 UI/피킹/편집 로직은 만들지
/// 않는다(과도한 조기 구현 금지 — 그러나 나중에 폐기해야 하는 구조도
/// 만들지 않는다).
enum SpaceElementKindV2 {
  wall,
  floor,
  ceiling,
  opening,
  furniture,
  light,
  other,
}

/// 3D 객체 하나의 위치/방향/크기 — 이번 범위에서는 항상 identity(원점,
/// 무회전, 배율 1)다. geometry는 이미 world mm 좌표로 baked돼 있어 이
/// transform을 실제로 적용하지 않는다 — MASTER 단계(가구 이동/회전/크기
/// 조절)에서 mesh를 다시 굽지 않고 transform만 바꿔 갱신할 수 있도록
/// 자리만 미리 만들어 둔다. [Vector3]는 const 생성자가 없어 기본값은
/// 팩토리에서 만든다.
@immutable
class SpaceTransformV2 {
  SpaceTransformV2({
    Vector3? positionMm,
    this.rotationRadians = 0,
    this.scale = 1,
  }) : positionMm = positionMm ?? Vector3.zero();

  final Vector3 positionMm;
  final double rotationRadians;
  final double scale;

  static final SpaceTransformV2 identity = SpaceTransformV2();
}

/// 3D 객체의 실측 치수 — 화면(우측 패널)이 "높이/너비/두께"를 그대로
/// 보여줄 수 있도록 mesh 생성 시점에 계산해 둔다(MASTER 우측 패널 "사이즈"
/// 섹션과 동일한 필드).
@immutable
class SpaceDimensionsV2 {
  const SpaceDimensionsV2({this.heightMm, this.widthMm, this.thicknessMm});

  final double? heightMm;
  final double? widthMm;
  final double? thicknessMm;
}

/// 모든 V2 3D 객체(벽/바닥/opening 등)가 공유하는 identity/편집 자리.
/// [SpaceObjectV2]를 직접 만들지 않고 [SpaceWallMeshV2] 등 구체 타입을
/// 통해서만 쓴다 — Dart에는 mixin 필드 상속이 번거로워 값 객체 하나를
/// 각 mesh가 들고 있는 형태(합성)로 둔다.
@immutable
class SpaceObjectIdentityV2 {
  SpaceObjectIdentityV2({
    required this.objectId,
    required this.sourceKind,
    required this.sourceId,
    this.roomId,
    this.wallId,
    this.floorId,
    this.openingId,
    SpaceTransformV2? transform,
    this.dimensions,
    this.materialId,
    this.color,
    this.visible = true,
    this.locked = false,
  }) : transform = transform ?? SpaceTransformV2.identity;

  /// 3D scene 안에서 유일한 id — 이번 범위에서는 sourceId와 같지만,
  /// 향후 같은 CAD 원본에서 여러 3D 객체(예: 가구 여러 개)가 나올 수
  /// 있어 별도 개념으로 분리해 둔다.
  final String objectId;
  final SpaceElementKindV2 sourceKind;

  /// 이 객체를 만든 CAD geometry id([CadWall.id]/[CadRoom.id]/
  /// [CadOpening.id]) — MASTER의 "3D 객체 ↔ 작업 번호 ↔ 작업 목록 ↔ 우측
  /// 선택 항목" 양방향 동기화가 전부 이 id 하나로 이뤄진다.
  final String sourceId;

  final String? roomId;
  final String? wallId;
  final String? floorId;
  final String? openingId;

  final SpaceTransformV2 transform;
  final SpaceDimensionsV2? dimensions;

  /// 향후 마감재 편집(MASTER 우측 패널 "마감재 선택") — 이번 범위는 항상
  /// null(적용 UI 없음).
  final String? materialId;

  /// 향후 색상 편집 — 이번 범위는 mesh 생성 시 쓴 기본 색을 그대로
  /// 담아 둔다(나중에 사용자가 바꾸면 이 필드만 갱신하면 되도록).
  final Color? color;

  final bool visible;
  final bool locked;
}

@immutable
class SpaceTriangleV2 {
  const SpaceTriangleV2({
    required this.a,
    required this.b,
    required this.c,
    required this.color,
  });

  final Vector3 a;
  final Vector3 b;
  final Vector3 c;
  final Color color;

  Vector3 get normal {
    final n = (b - a).cross(c - a);
    final len = n.length;
    return len == 0 ? Vector3(0, 1, 0) : n / len;
  }

  Vector3 get centroid => (a + b + c) / 3.0;
}

/// [CadWall] 하나로부터 만든 안정적인 직육면체(rectangular prism, WO
/// 9번) — room polygon과 무관하게 start/end/thickness/height만으로
/// 결정된다. 면 5종(top/outer/inner/startCap/endCap) × 2 triangle = 10
/// triangle 고정 구성이다(vertex가 유한하지 않거나 길이가 0인 벽은
/// 빌더가 아예 만들지 않는다).
@immutable
class SpaceWallMeshV2 {
  const SpaceWallMeshV2({
    required this.identity,
    required this.triangles,
    required this.startMm,
    required this.endMm,
    required this.isExterior,
  });

  final SpaceObjectIdentityV2 identity;
  final List<SpaceTriangleV2> triangles;

  /// 벽 중심선의 시작/끝(mm, world 좌표 — Y=0 평면 위) — 향후 junction
  /// 편집/피킹에 재사용한다.
  final Vector3 startMm;
  final Vector3 endMm;
  final bool isExterior;

  String get wallId => identity.wallId!;
}

/// [CadRoom] 하나로부터 만든 바닥 — 벽 mesh와 완전히 분리된 파이프라인
/// (WO 11번, "Floor는 wall과 완전히 분리")로 만들어진다. polygon
/// triangulation이 실패하면 이 mesh 자체가 생성되지 않는다(triangles가
/// 비어 있지 않음이 항상 보장됨 — 실패 시 빌더가 아예 만들지 않는다).
@immutable
class SpaceFloorMeshV2 {
  const SpaceFloorMeshV2({
    required this.identity,
    required this.triangles,
    required this.polygonMm,
  });

  final SpaceObjectIdentityV2 identity;
  final List<SpaceTriangleV2> triangles;

  /// 바닥 polygon(mm, world 좌표, Y=0) — cleanup(중복점 제거/collinear
  /// 정리) 이후의 최종 형태.
  final List<Vector3> polygonMm;

  String get roomId => identity.roomId!;
}

/// [CadOpening] identity만 담는 자리 — 이번 범위(WO 19번)는 벽 geometry에
/// 실제로 반영하지 않는다(구멍을 뚫지 않음). MASTER 단계에서 문/창을
/// 실제로 벽에서 잘라낼 때 이 타입을 채워 넣을 자리만 지금 만들어 둔다.
@immutable
class SpaceOpeningV2 {
  const SpaceOpeningV2({
    required this.identity,
    required this.centerMm,
    required this.widthMm,
  });

  final SpaceObjectIdentityV2 identity;
  final Vector3 centerMm;
  final double widthMm;
}

/// 도면 전체를 V2 방식으로 옮긴 결과.
@immutable
class SpaceSceneV2 {
  const SpaceSceneV2({
    required this.wallMeshes,
    required this.floorMeshes,
    required this.openings,
    required this.minBounds,
    required this.maxBounds,
    required this.warnings,
  });

  final List<SpaceWallMeshV2> wallMeshes;
  final List<SpaceFloorMeshV2> floorMeshes;
  final List<SpaceOpeningV2> openings;

  final Vector3 minBounds;
  final Vector3 maxBounds;

  /// "문/창을 아직 벽에 반영하지 않았습니다" 같은, 실제로 생성되지 않은
  /// 부분을 정직하게 알리는 문구 + 제외된 비정상 geometry 보고.
  final List<String> warnings;

  int get wallCount => wallMeshes.length;
  int get floorCount => floorMeshes.length;

  /// 렌더러가 순회할 평면화된 삼각형 목록 — 매 프레임 새로 만들지 않도록
  /// 호출부(렌더러)가 캐시해서 쓰는 것을 권장한다.
  List<SpaceTriangleV2> get triangles => [
    for (final wall in wallMeshes) ...wall.triangles,
    for (final floor in floorMeshes) ...floor.triangles,
  ];

  Vector3 get center => (minBounds + maxBounds) / 2.0;

  double get boundingRadius => (maxBounds - minBounds).length / 2.0;

  bool get isEmpty => wallMeshes.isEmpty && floorMeshes.isEmpty;
}
