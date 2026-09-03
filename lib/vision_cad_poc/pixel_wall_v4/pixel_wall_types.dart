// SPACE SHIFT — Vision-Guided Full Pixel Wall Extraction POC.
//
// GPT는 이제 CAD 좌표를 전혀 만들지 않는다("WHAT/RELATIONSHIP/WHERE TO
// LOOK"만 담당). 실제 벽 geometry는 이 파일이 정의하는
// [PixelWallCandidate]로, floor_plan_analysis_engine.dart의 기존
// 전체-이미지 검출(detectWallsAndOpenings)이 만든 [WallSegment]를
// 그대로 재사용해 multi-factor(길이+junction 지지+원본 confidence)
// 분류를 한 겹 더한 것이다 — 두께 하나만으로 텍스트/가구를 걸러내지
// 않는다는 이번 설계 원칙(§6)을 따른다.

import '../../models/floor_plan_geometry.dart';

enum PixelWallOrientation { horizontal, vertical }

/// [PixelWallCandidate]가 최종적으로 "구조 벽으로 확정"인지, 아니면
/// 근거는 있지만 GPT 의미 지도와 맞지 않거나 근거가 약해 검토가
/// 필요한지 — 절대 조용히 삭제하지 않는다(설계 원칙, §6/§14).
enum PixelWallCategory { structural, reviewNeeded }

enum PixelWallConfidenceTier { high, medium, low }

/// run-length 검출로 얻은 [WallSegment] 한 개에 continuity/junction
/// 근거를 더해 만든 최종 픽셀 벽 후보. [source]로 원본 WallSegment id를
/// 계속 추적할 수 있다(merge로 여러 개가 하나로 합쳐졌으면 첫 id).
class PixelWallCandidate {
  const PixelWallCandidate({
    required this.id,
    required this.start,
    required this.end,
    required this.thicknessNormalized,
    required this.orientation,
    required this.isExterior,
    required this.baseConfidence,
    required this.junctionSupport,
    required this.confidenceTier,
    required this.category,
    required this.sourceSegmentIds,
    this.mergedFromCount = 1,
  });

  final String id;
  final Point2 start;
  final Point2 end;
  final double thicknessNormalized;
  final PixelWallOrientation orientation;
  final bool isExterior;

  /// floor_plan_analysis_engine._confidenceFor()가 계산한 길이 기반 원본 값.
  final double baseConfidence;

  /// 이 벽의 두 끝점 중 적어도 하나가 다른 벽과 실제로 맞닿은(교차/T/L)
  /// 횟수(0~2). 0이면 "허공에 뜬" 조각 — 가구/텍스트 노이즈일 가능성이
  /// 높다는 신호로만 쓰고, 그 자체만으로 삭제하지는 않는다.
  final int junctionSupport;

  final PixelWallConfidenceTier confidenceTier;
  final PixelWallCategory category;
  final List<String> sourceSegmentIds;
  final int mergedFromCount;

  double get lengthNormalized {
    final dx = end.x - start.x;
    final dy = end.y - start.y;
    return (dx * dx + dy * dy) == 0 ? 0 : (dx.abs() + dy.abs());
  }
}

/// GPT의 회의적/rejected 후보를 진단용으로 남긴다 — 최종 canonical
/// 벽에는 포함되지 않지만 UI "PIXEL WALLS" 탭에서 왜 제외됐는지
/// 확인할 수 있게 한다.
class PixelWallRejection {
  const PixelWallRejection({
    required this.start,
    required this.end,
    required this.reasonLabel,
  });

  final Point2 start;
  final Point2 end;
  final String reasonLabel;
}
