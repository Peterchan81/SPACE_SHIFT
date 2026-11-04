/// SS014 — ISO에서 벽 하나를 선택해 정면도(Elevation)/측면도/평면도로 전환해 정밀하게 디자인하는
/// 화면([ElevationFaceEditorScreen])의 상태. 실제 구조/마감재/가구/조명/설비 편집과
/// Undo/Redo/History/저장은 전부 이미 검증된 [SsIsoEditorController](SS013)를 그대로 쓴다 — 이
/// 컨트롤러는 그 위에 "지금 어느 벽을 정면으로 보고 있는지"(focusedWallId)와 "정면도/측면도/평면도
/// 중 무엇을 보고 있는지"(view)만 더한다(§14 기존 기능 보존 — 새 3D/편집 엔진을 만들지 않는다).
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/cad_floor_plan.dart';
import '../models/floor_plan_geometry.dart';
import '../models/space_scene_v2.dart';
import '../services/space_scene_builder_v2.dart' show kAssumedDoorOpeningHeightMm, kAssumedWindowHeightMm, kAssumedWindowSillHeightMm;
import 'ss_iso_editor_controller.dart';

/// View Cube(또는 동등한 전환 버튼)가 고르는 작업 화면.
enum SsElevationView {
  front('정면도'),
  side('측면도'),
  plan('평면도');

  const SsElevationView(this.label);
  final String label;
}

/// 정면도 캔버스 위에 그릴 문/창 하나 — [focusedWall] 기준 along-축(0=시작, lengthMm=끝) mm와
/// 바닥 기준 높이(mm) 구간. [CadOpening]에는 폭만 있고 sill/head 높이가 없어([CadOpening]), 3D
/// 빌더([buildSpaceSceneV2]/space_scene_builder_v2.dart)와 똑같은 통상 가정값을 그대로 쓴다 —
/// 정면도와 3D가 서로 다른 수치를 보여주면 "변경 결과가 같은 모델에 정확히 반영"됐는지 확인할 수
/// 없기 때문이다.
@immutable
class SsElevationOpening {
  const SsElevationOpening({required this.openingId, required this.type, required this.startMm, required this.endMm, required this.bottomMm, required this.topMm});
  final String openingId;
  final OpeningType type;
  final double startMm;
  final double endMm;
  final double bottomMm;
  final double topMm;
}

/// 선택된 벽 하나의 정면도 전체 — 길이/높이/문창 목록.
@immutable
class SsWallElevationLayout {
  const SsWallElevationLayout({required this.wallId, required this.lengthMm, required this.heightMm, required this.openings});
  final String wallId;
  final double lengthMm;
  final double heightMm;
  final List<SsElevationOpening> openings;
}

class SsElevationEditorController extends ChangeNotifier {
  SsElevationEditorController({required this.iso, required String initialWallId}) : focusedWallId = initialWallId {
    iso.addListener(notifyListeners);
  }

  /// SS013의 실제 편집/Undo/Redo/저장 엔진 — 이 컨트롤러는 절대 독립된 상태를 두지 않는다(정면도에서
  /// 고친 결과가 "같은 3D 모델"이어야 한다는 완료조건을 데이터 레벨에서 보장한다).
  final SsIsoEditorController iso;

  /// 지금 정면/측면으로 보고 있는 벽의 id.
  String focusedWallId;

  SsElevationView view = SsElevationView.front;

  CadWall? get focusedWall {
    for (final w in iso.plan.walls) {
      if (w.id == focusedWallId) return w;
    }
    return null;
  }

  void setView(SsElevationView v) {
    if (view == v) return;
    view = v;
    notifyListeners();
  }

  /// 다른 벽을 정면(또는 측면)으로 바꾼다 — ISO에서 선택이 바뀐 것과 같은 뜻이라 3D 하이라이트도
  /// 같이 옮긴다(§완료조건 "선택 상태 유지").
  void focusWall(String wallId) {
    focusedWallId = wallId;
    iso.selectObjectIdentity(SpaceObjectIdentityV2(objectId: 'wall:$wallId', sourceKind: SpaceElementKindV2.wall, sourceId: wallId, wallId: wallId));
    notifyListeners();
  }

  /// "측면도" 전환에 쓸 만한 벽 — 지금 정면 벽과 거의 수직(±~20도 이내)인 다른 벽만 고른다. MASTER
  /// UI에는 정식 3D View Cube가 없어, "이 벽과 수직인 벽들"을 측면도 후보로 보여주는 쪽이 존재하지
  /// 않는 선택지를 지어내지 않는 가장 직관적인 대안이다.
  List<CadWall> get sideWallCandidates {
    final focused = focusedWall;
    final s = iso.scale;
    if (focused == null || s == null) return const [];
    final plan = iso.plan;
    final a = plan.pointToMm(focused.start, s);
    final b = plan.pointToMm(focused.end, s);
    final dx1 = b.xMm - a.xMm, dz1 = b.yMm - a.yMm;
    final len1 = math.sqrt(dx1 * dx1 + dz1 * dz1);
    if (len1 == 0) return const [];
    final out = <CadWall>[];
    for (final w in plan.walls) {
      if (w.id == focused.id) continue;
      final c = plan.pointToMm(w.start, s);
      final d = plan.pointToMm(w.end, s);
      final dx2 = d.xMm - c.xMm, dz2 = d.yMm - c.yMm;
      final len2 = math.sqrt(dx2 * dx2 + dz2 * dz2);
      if (len2 == 0) continue;
      final cosAngle = (dx1 * dx2 + dz1 * dz2) / (len1 * len2);
      if (cosAngle.abs() < 0.35) out.add(w);
    }
    return out;
  }

  /// 지금 정면 벽의 정면도 layout — 축척이 없으면(실측/자동 추정 전) 존재하지 않는 치수를 지어내지
  /// 않고 null.
  SsWallElevationLayout? get layout {
    final wall = focusedWall;
    final s = iso.scale;
    if (wall == null || s == null) return null;
    final plan = iso.plan;
    final lengthMm = plan.realMmBetween(wall.start, wall.end, s);
    if (lengthMm == null || lengthMm <= 0) return null;
    final heightMm = wall.heightMm ?? iso.ceilingHeightMm;
    final openings = <SsElevationOpening>[];
    for (final o in plan.openings.where((o) => o.wallId == wall.id)) {
      final widthMm = plan.realMmForNormalizedLength(o.widthNormalized, s);
      if (widthMm == null || widthMm <= 0) continue;
      final t = wall.projectPoint(o.center).t;
      final centerMm = (t * lengthMm).clamp(0.0, lengthMm);
      final isDoor = o.type == OpeningType.door;
      final bottomMm = isDoor ? 0.0 : kAssumedWindowSillHeightMm;
      final topMm = (isDoor ? kAssumedDoorOpeningHeightMm : kAssumedWindowSillHeightMm + kAssumedWindowHeightMm).clamp(0.0, heightMm);
      openings.add(
        SsElevationOpening(
          openingId: o.id,
          type: o.type,
          startMm: (centerMm - widthMm / 2).clamp(0.0, lengthMm),
          endMm: (centerMm + widthMm / 2).clamp(0.0, lengthMm),
          bottomMm: bottomMm,
          topMm: topMm,
        ),
      );
    }
    return SsWallElevationLayout(wallId: wall.id, lengthMm: lengthMm, heightMm: heightMm, openings: openings);
  }

  /// 정면도 캔버스에서 along-축 mm 좌표를 탭했을 때 가장 가까운 문/창을 고른다. 아무 것도 없으면
  /// 선택을 비운다([SsCadEditorController.selectAt]과 같은 생각).
  void selectOpeningAtAlongMm(double alongMm) {
    final l = layout;
    if (l == null) return;
    for (final o in l.openings) {
      if (alongMm >= o.startMm - 1 && alongMm <= o.endMm + 1) {
        iso.selectOpening(o.openingId);
        return;
      }
    }
    iso.clearSelection();
  }

  @override
  void dispose() {
    iso.removeListener(notifyListeners);
    super.dispose();
  }
}
