// SPACE SHIFT — WO088-6 REAL MM GRID.
//
// §2 좌표 단위 추적(코드 근거):
//   structural_layer.dart RawStructuralLine.start/end
//     -> source pixel(원본 분석 캔버스, 회전 없음 px). Point2([0,1]
//        normalized)가 전혀 아니다 — drafting_v1은 애초에 Point2를 쓰지
//        않고 자체 Pt(px 단위) 레코드만 쓴다.
//   drafting_model.dart DraftWall.startVirtual/endVirtual
//     -> "virtual" = Origin(사용자가 고른 corner) 기준 상대 좌표, Y축만
//        CAD 관례로 뒤집은 것 — 단위는 여전히 원본 px 그대로다(정규화
//        아님, mm 아님, scale 미적용). Scale Anchor를 걸기 전까지는
//        이 값을 mm라고 표기하면 안 된다(§3).
// 이 파일이 비로소 "실제 mm"를 만드는 유일한 지점이다 — 그 전 어떤
// 레이어도 mm를 참칭하지 않는다.
//
// §4 — WO082(virtual_cad_scale.dart)의 RealWorldScale/VirtualCadPoint/
// calibrateScaleFromUserAnchor()를 그대로 재사용한다. 새 scale 계산식을
// 만들지 않는다. DraftWall.startVirtual/endVirtual은 이미 "px 단위 거리"
// 이므로(원본 이미지 px와 동일한 물리적 픽셀 크기, 원점/Y방향만 다른
// 강체변환) VirtualCadPoint(x, y) 원시 생성자에 그대로 넣을 수 있다 —
// 거리는 이동/반사에 불변이므로 별도 좌표 역변환이 필요 없다.

import 'dart:math' as math;

import '../pixel_wall_v4/virtual_cad_scale.dart';
import 'drafting_model.dart';
import 'structural_layer.dart' show Pt;

/// [a]/[b]는 DraftWall.startVirtual/endVirtual과 같은 "Origin 기준 virtual
/// px" 좌표(drafting_model.dart 참고)여야 한다. [realWorldMm]은 사용자가
/// 직접 입력한 값만 받는다 — "문은 보통 860/900/1000mm"라는 이유로
/// 자동 확정하지 않는다(§4, 호출자가 UI에서 후보를 보여주더라도 최종
/// 값은 항상 사용자 선택/입력이어야 한다).
RealWorldScale calibrateDraftScaleFromAnchor({
  required Pt a,
  required Pt b,
  required double realWorldMm,
  String? anchorDescription,
}) {
  return calibrateScaleFromUserAnchor(
    a: VirtualCadPoint(a.x, a.y),
    b: VirtualCadPoint(b.x, b.y),
    realWorldMm: realWorldMm,
    anchorDescription: anchorDescription,
  );
}

class RealMmPoint {
  const RealMmPoint(this.xMm, this.yMm);
  final double xMm;
  final double yMm;

  double distanceTo(RealMmPoint other) {
    final dx = xMm - other.xMm, dy = yMm - other.yMm;
    return math.sqrt(dx * dx + dy * dy);
  }

  @override
  String toString() => '(${xMm.toStringAsFixed(1)}mm, ${yMm.toStringAsFixed(1)}mm)';
}

/// §5 — raw(미보정) mm 좌표만 담는다. Snap은 이후 별도 레이어(mm_snap.dart)
/// 에서 이 값을 "보존한 채" 추가로 계산한다.
class RealMmWall {
  const RealMmWall({
    required this.id,
    required this.rawStart,
    required this.rawEnd,
    required this.classification,
    required this.method,
  });

  final String id;
  final RealMmPoint rawStart;
  final RealMmPoint rawEnd;
  final WallAngleClass classification;
  final String method;

  double get rawLengthMm => rawStart.distanceTo(rawEnd);
}

class RealMmDraft {
  const RealMmDraft({required this.scale, required this.walls});
  final RealWorldScale scale;
  final List<RealMmWall> walls;
}

/// [model]의 모든 wall을 mm로 변환한다. [scale]이 calibrate되지
/// 않았으면(§3) null을 반환한다 — 임의 mm를 만들지 않는다.
RealMmDraft? buildRealMmDraft(DraftingModel model, RealWorldScale scale) {
  if (!scale.isCalibrated) return null;
  final mmPerUnit = scale.mmPerVirtualUnit!;
  RealMmPoint toMm(Pt p) => RealMmPoint(p.x * mmPerUnit, p.y * mmPerUnit);
  return RealMmDraft(
    scale: scale,
    walls: [
      for (final w in model.walls)
        RealMmWall(id: w.id, rawStart: toMm(w.startVirtual), rawEnd: toMm(w.endVirtual), classification: w.classification, method: w.method),
    ],
  );
}
