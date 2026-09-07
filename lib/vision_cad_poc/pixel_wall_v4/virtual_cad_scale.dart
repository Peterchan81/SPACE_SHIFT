// SPACE SHIFT — WO082 EVIDENCE/PROVENANCE + VIRTUAL CAD FOUNDATION.
//
// §3B/§3C — 4단계 좌표 계층을 명시적으로 분리한다:
//
//   Image Coordinate (특정 원본 이미지의 px 격자)
//     -> Normalized Drawing Coordinate ([Point2], 이미지 해상도 독립적 [0,1])
//     -> Virtual CAD Coordinate ([VirtualCadPoint], 이 파일이 formalize)
//     -> Real-world Metric Coordinate (mm, [RealWorldScale]로만 변환 가능)
//
// pixel_wall_v4 파이프라인 전체(WallSystem/PlanarGraph 등 모든 `*Px`
// 필드)가 이미 암묵적으로 "이미지 분석 해상도 px" 공간에서 계산해 왔다 —
// 이 파일은 그 계층에 명시적인 타입과 이름을 붙일 뿐, 새로운 산술을
// 만들지 않는다. Virtual CAD Coordinate는 특정 소스 이미지 하나에
// 종속되지 않는 캐노니컬 도면 작업 공간이라는 개념이므로(향후 여러
// 이미지/수기 편집 요소가 섞여도 동일 공간을 공유해야 한다), Point2와
// 구분되는 별도 타입으로 둔다.
//
// 실제 치수를 아직 모르면 임의 mm 값을 만들지 않는다(§3B) — 반드시
// [ScaleConfidence.unknown] 상태를 명시적으로 유지한다.

import 'dart:math' as math;

import '../../models/floor_plan_geometry.dart';

/// Virtual CAD Coordinate 위의 점 — 특정 원본 이미지의 px 격자에 얽매이지
/// 않는 캐노니컬 도면 작업 공간의 좌표(현재는 이미지 분석 해상도 px와
/// 수치적으로 동일하지만, 개념적으로는 "이 도면 프로젝트 전체가 공유하는
/// 좌표계"이다 — 여러 소스/수기 편집 요소가 섞여도 이 공간 하나로
/// 모인다).
class VirtualCadPoint {
  const VirtualCadPoint(this.x, this.y);

  final double x;
  final double y;

  /// Normalized Drawing Coordinate([Point2], [0,1])에서 변환한다 —
  /// [w]/[h]는 이 좌표가 유래한 이미지의 분석 해상도(px)다.
  factory VirtualCadPoint.fromNormalized(Point2 p, {required int w, required int h}) =>
      VirtualCadPoint(p.x * w, p.y * h);

  /// 다시 Normalized Drawing Coordinate로 되돌린다(렌더링/저장 등 기존
  /// [0,1] 기반 소비자와의 호환을 위해).
  Point2 toNormalized({required int w, required int h}) => Point2(x / w, y / h);

  double distanceTo(VirtualCadPoint other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return math.sqrt(dx * dx + dy * dy);
  }
}

/// [RealWorldScale]이 얼마나 신뢰할 수 있는 값인지 — 절대 [unknown]을
/// 건너뛰고 임의 추정치를 확정값처럼 노출하지 않는다.
enum ScaleConfidence {
  /// 실제 축척을 전혀 모른다 — [RealWorldScale.mmPerVirtualUnit]은
  /// 항상 null이다.
  unknown,

  /// 도면 평균적인 문/벽 두께 등 간접 근거로 추정한 값(아직 사용자가
  /// 직접 확인하지 않음).
  estimated,

  /// 사용자가 도면 위 두 점을 고르고 실제 길이(mm)를 직접 입력해 계산한
  /// 값 — §3C User Anchor.
  userAnchored,

  /// 도면에 실제로 인쇄된 치수 텍스트 등, 별도 근거로 교차 검증까지
  /// 끝난 값.
  verified,
}

/// Virtual CAD Coordinate 거리 -> 실측 mm 변환 비율. [confidence]가
/// [ScaleConfidence.unknown]이면 [mmPerVirtualUnit]은 항상 null이다 —
/// 확정되지 않은 축척을 임의의 숫자로 채우지 않는다(§3B/§14).
class RealWorldScale {
  const RealWorldScale._({required this.confidence, this.mmPerVirtualUnit, this.anchorDescription});

  const RealWorldScale.unknown() : this._(confidence: ScaleConfidence.unknown);

  const RealWorldScale.estimated({required double mmPerVirtualUnit, String? anchorDescription})
    : this._(confidence: ScaleConfidence.estimated, mmPerVirtualUnit: mmPerVirtualUnit, anchorDescription: anchorDescription);

  const RealWorldScale.verified({required double mmPerVirtualUnit, String? anchorDescription})
    : this._(confidence: ScaleConfidence.verified, mmPerVirtualUnit: mmPerVirtualUnit, anchorDescription: anchorDescription);

  /// §3C — virtualDistance <= 0 또는 realWorldMm <= 0이면(사용자가 같은
  /// 점을 두 번 찍었거나 0을 입력한 경우 등) 계산하지 않고 unknown으로
  /// 안전하게 남긴다 — NaN/Infinity를 절대 확정 scale처럼 반환하지 않는다.
  factory RealWorldScale.fromUserAnchor({
    required double virtualDistance,
    required double realWorldMm,
    String? anchorDescription,
  }) {
    if (!virtualDistance.isFinite || !realWorldMm.isFinite || virtualDistance <= 0 || realWorldMm <= 0) {
      return const RealWorldScale.unknown();
    }
    return RealWorldScale._(
      confidence: ScaleConfidence.userAnchored,
      mmPerVirtualUnit: realWorldMm / virtualDistance,
      anchorDescription: anchorDescription,
    );
  }

  final ScaleConfidence confidence;

  /// 1 Virtual CAD 단위 = 몇 mm인지. [confidence] == unknown이면 항상 null.
  final double? mmPerVirtualUnit;

  /// 이 축척이 어떤 근거로 계산됐는지(예: "왼쪽 벽 전체 길이 = 4200mm").
  final String? anchorDescription;

  bool get isCalibrated => confidence != ScaleConfidence.unknown && mmPerVirtualUnit != null;

  /// Virtual CAD Coordinate 거리를 mm로 변환한다. calibrate되지 않았으면
  /// null(§3B — 아직 모르는 값을 임의로 채우지 않는다).
  double? toMm(double virtualDistance) => isCalibrated ? virtualDistance * mmPerVirtualUnit! : null;

  /// Virtual CAD 점 하나를 mm 단위 (x, y)로 변환한다 — 원점 기준 상대
  /// 좌표일 뿐 실세계 절대 위치를 뜻하지 않는다. calibrate되지 않았으면 null.
  ({double xMm, double yMm})? toMmPoint(VirtualCadPoint p) {
    if (!isCalibrated) return null;
    return (xMm: p.x * mmPerVirtualUnit!, yMm: p.y * mmPerVirtualUnit!);
  }
}

/// §3C USER ANCHOR SCALE CALIBRATION — 사용자가 도면 위 두 점(예: 벽
/// 끝점)을 고르고 그 실제 길이(mm)를 입력하면 전체 도면 축척을 계산한다.
/// `scale = realWorldMm / virtualDistance` 그대로다 — 이 함수는 그
/// 계산과 안전한 실패 처리(0/음수/NaN 거부)만 담당하고, 어떤 UI도
/// 강제하지 않는다(§3C "UI를 과도하게 만들지 않는다").
RealWorldScale calibrateScaleFromUserAnchor({
  required VirtualCadPoint a,
  required VirtualCadPoint b,
  required double realWorldMm,
  String? anchorDescription,
}) {
  return RealWorldScale.fromUserAnchor(
    virtualDistance: a.distanceTo(b),
    realWorldMm: realWorldMm,
    anchorDescription: anchorDescription,
  );
}
