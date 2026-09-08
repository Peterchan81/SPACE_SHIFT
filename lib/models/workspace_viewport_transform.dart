import 'package:flutter/material.dart' show Offset;

/// WO089 §5 좌표 원칙 — 화면 pixel 좌표를 최종 데이터로 저장하지 않는다.
///
/// 이 클래스는 "이미 contain-fit된 화면 공간"(ContainFitTransform이
/// 만든, 평면도 이미지 실제 표시 영역 기준 좌표) 위에 사용자가 편 pan/
/// zoom만을 표현한다 — 문서 좌표([Point2], 정규화 0.0~1.0)는 절대
/// 건드리지 않는다. 합성 순서:
///
///   document(Point2) --ContainFitTransform--> fitted(Offset)
///                     --WorkspaceViewportTransform--> screen(Offset)
///
/// 역방향도 정확히 그 반대 순서로 되돌린다. zoom/pan은 오직 이 transform
/// 자체(scale/offset)만 바꾸고, 문서 좌표는 절대 다시 계산/저장하지
/// 않는다 — 그래서 확대·이동을 아무리 해도 기존 도형의 document 좌표는
/// 항상 그대로다(§5 필수 요구사항, 테스트로 고정).
class WorkspaceViewportTransform {
  const WorkspaceViewportTransform({this.scale = 1.0, this.offset = Offset.zero});

  static const WorkspaceViewportTransform identity = WorkspaceViewportTransform();

  static const double minScale = 0.5;
  static const double maxScale = 6.0;

  final double scale;
  final Offset offset;

  /// fitted 화면 좌표 -> 실제(확대/이동 반영) 화면 좌표.
  Offset apply(Offset fitted) => fitted * scale + offset;

  /// 실제 화면 좌표 -> fitted 화면 좌표(역변환).
  Offset invert(Offset screen) => (screen - offset) / scale;

  /// 화면 픽셀 [delta]만큼 이동(pan) — 문서 좌표에는 영향 없음.
  WorkspaceViewportTransform panBy(Offset delta) => WorkspaceViewportTransform(scale: scale, offset: offset + delta);

  /// [focalPoint](실제 화면 좌표)를 고정한 채 배율을 [factor]배 한다
  /// (핀치 줌의 표준 동작 — 두 손가락 중심이 확대 중에도 같은 화면
  /// 위치에 남는다). 최소/최대 배율로 clamp한다.
  WorkspaceViewportTransform zoomBy(double factor, {required Offset focalPoint}) {
    final newScale = (scale * factor).clamp(minScale, maxScale);
    if (newScale == scale) return this;
    final newOffset = focalPoint - (focalPoint - offset) * (newScale / scale);
    return WorkspaceViewportTransform(scale: newScale, offset: newOffset);
  }
}
