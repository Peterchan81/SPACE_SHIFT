/// SS012 — ISO Orbit(3D 아이소 작업실, SS013)에 필요한 카메라 좌표/각도 기반을 미리 만들어 둔다.
/// 실제 Orbit 조작 UI(드래그 회전/휠 줌/pan)는 이번 범위가 아니다(SS013, [Space3DViewGpuV2]가 이미
/// 구면좌표 target/distance/azimuth/polar로 카메라를 돌리는 방식을 쓰고 있다 — 이 모델은 그 값들과
/// 같은 모양으로 맞춰, 변환 직후 "Orbit을 시작할 합리적인 기본 시점"과 "재생성해도 사용자가 이미
/// 돌려본 시점을 잃지 않도록 보존할 자리"만 만든다. 새 3D 카메라 엔진을 만들지 않는다).
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math_64.dart';

import 'space_scene_v2.dart';

@immutable
class SsIsoCameraState {
  const SsIsoCameraState({
    required this.targetXMm,
    required this.targetYMm,
    required this.targetZMm,
    required this.distanceMm,
    required this.azimuthRadians,
    required this.polarRadians,
  });

  final double targetXMm;
  final double targetYMm;
  final double targetZMm;
  final double distanceMm;
  final double azimuthRadians;
  final double polarRadians;

  Vector3 get target => Vector3(targetXMm, targetYMm, targetZMm);

  /// [scene]의 중심/크기로부터 합리적인 기본 Orbit 시점을 만든다 — 45도 아이소 각도(azimuth=45°,
  /// polar=45°)에서 전체 모델이 한 화면에 들어오도록 거리(boundingRadius 기반)를 잡는다. scene이
  /// 비어 있으면(아직 geometry가 없음) 존재하지 않는 치수를 지어내지 않고 원점 기준 고정값을
  /// 돌려준다.
  factory SsIsoCameraState.defaultForScene(SpaceSceneV2 scene) {
    if (scene.isEmpty) {
      return const SsIsoCameraState(
        targetXMm: 0,
        targetYMm: 0,
        targetZMm: 0,
        distanceMm: 5000,
        azimuthRadians: math.pi / 4,
        polarRadians: math.pi / 4,
      );
    }
    final center = scene.center;
    final radius = scene.boundingRadius;
    final distance = radius > 0 ? radius * 2.4 : 5000.0;
    return SsIsoCameraState(
      targetXMm: center.x,
      targetYMm: center.y,
      targetZMm: center.z,
      distanceMm: distance,
      azimuthRadians: math.pi / 4,
      polarRadians: math.pi / 4,
    );
  }

  Map<String, Object?> toJson() => {
    'targetXMm': targetXMm,
    'targetYMm': targetYMm,
    'targetZMm': targetZMm,
    'distanceMm': distanceMm,
    'azimuthRadians': azimuthRadians,
    'polarRadians': polarRadians,
  };

  /// 저장된 JSON에서 — 깨졌거나 알아볼 수 없는 값이면 null(지어내지 않는다. 호출부가 기본값을 다시
  /// 계산해야 한다).
  static SsIsoCameraState? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final tx = j['targetXMm'];
    final ty = j['targetYMm'];
    final tz = j['targetZMm'];
    final d = j['distanceMm'];
    final az = j['azimuthRadians'];
    final pol = j['polarRadians'];
    if (tx is! num || ty is! num || tz is! num || d is! num || az is! num || pol is! num) return null;
    return SsIsoCameraState(
      targetXMm: tx.toDouble(),
      targetYMm: ty.toDouble(),
      targetZMm: tz.toDouble(),
      distanceMm: d.toDouble(),
      azimuthRadians: az.toDouble(),
      polarRadians: pol.toDouble(),
    );
  }
}
