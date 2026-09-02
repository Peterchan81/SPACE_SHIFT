import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// 정규화된 평면도 이미지 좌표(0.0~1.0).
///
/// source 이미지 픽셀 좌표도, 화면 표시(canvas contain-fit) 좌표도 아닌
/// 세 번째 좌표계다 — 원본 이미지의 가로세로 비율만 따르므로 분석 해상도나
/// 화면 크기가 달라져도 값이 그대로 재사용된다. 화면에 그릴 때만(overlay
/// 쪽에서) contain-fit 변환을 거쳐 실제 픽셀 좌표로 바꾼다(WO 6번).
@immutable
class Point2 {
  const Point2(this.x, this.y);

  final double x;
  final double y;

  double distanceTo(Point2 other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  Point2 copyWith({double? x, double? y}) => Point2(x ?? this.x, y ?? this.y);

  @override
  bool operator ==(Object other) =>
      other is Point2 && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() =>
      'Point2(${x.toStringAsFixed(4)}, ${y.toStringAsFixed(4)})';
}

/// 분석 결과 객체가 사용자에게 확정으로 보여도 되는지, 아직 보정이
/// 필요한지 — 자신 없는 후보를 확정처럼 보여주지 않기 위한 상태다
/// (WO 8번 "가짜로 확정 처리 금지").
enum FloorPlanObjectStatus { confirmed, needsReview }

/// 벽 후보 한 개. 이미지에서 실제로 검출된 직선 구간을 담는다 — 좌표는
/// 입력 이미지에 따라 달라지며 하드코딩된 값이 아니다.
@immutable
class WallSegment {
  const WallSegment({
    required this.id,
    required this.start,
    required this.end,
    required this.thicknessNormalized,
    required this.confidence,
    this.isExterior = false,
    this.status = FloorPlanObjectStatus.confirmed,
    this.heightMm,
  });

  final String id;
  final Point2 start;
  final Point2 end;

  /// 벽 두께를 이미지 대각선 길이에 대한 비율로 담는다(정규화 좌표계와
  /// 같은 단위 — mm 실측값이 아니다. WO 17번: 실제 치수는 scale 확인
  /// 전까지 절대 추정하지 않는다).
  final double thicknessNormalized;

  final double confidence;

  /// 평면도 외곽선을 이루는 벽인지(외벽 후보) 여부 — 작업 목록에서
  /// "외벽"/"내벽" 그룹을 나누는 데 쓰인다.
  final bool isExterior;

  final FloorPlanObjectStatus status;

  /// 벽 높이(mm). 이번 단계에서는 자동 추정하지 않아 항상 null이다 —
  /// 후속 "기본 벽 높이 입력" 흐름에서 채워질 자리만 미리 만들어 둔다
  /// (WO 18번).
  final double? heightMm;

  bool get isHorizontal => (start.y - end.y).abs() < (start.x - end.x).abs();

  double get lengthNormalized => start.distanceTo(end);

  WallSegment copyWith({
    Point2? start,
    Point2? end,
    FloorPlanObjectStatus? status,
    double? heightMm,
  }) {
    return WallSegment(
      id: id,
      start: start ?? this.start,
      end: end ?? this.end,
      thicknessNormalized: thicknessNormalized,
      confidence: confidence,
      isExterior: isExterior,
      status: status ?? this.status,
      heightMm: heightMm ?? this.heightMm,
    );
  }
}

/// 문/창 후보 종류. 이번 1차 구현에서는 gap 폭 기반 휴리스틱으로만
/// 구분하므로 확신이 낮은 경우 [unknown]으로 둔다.
enum OpeningType { door, window, unknown }

/// 문/창 후보 한 개 — 벽의 gap에서 추출한다. 확신이 낮을 수 있어 항상
/// [status]로 확정/보정필요를 구분한다(WO 8번).
@immutable
class OpeningCandidate {
  const OpeningCandidate({
    required this.id,
    required this.type,
    required this.center,
    required this.widthNormalized,
    required this.confidence,
    this.wallId,
    this.status = FloorPlanObjectStatus.needsReview,
  });

  final String id;
  final OpeningType type;
  final Point2 center;
  final double widthNormalized;
  final double confidence;
  final String? wallId;
  final FloorPlanObjectStatus status;

  OpeningCandidate copyWith({
    Point2? center,
    OpeningType? type,
    FloorPlanObjectStatus? status,
  }) {
    return OpeningCandidate(
      id: id,
      type: type ?? this.type,
      center: center ?? this.center,
      widthNormalized: widthNormalized,
      confidence: confidence,
      wallId: wallId,
      status: status ?? this.status,
    );
  }
}

/// [RejectedWallCandidate]가 벽 후보에서 걸러진 이유 — 지금은 두께 필터
/// (채워진 가구/해칭 블록 등)뿐이지만, 향후 다른 필터가 추가되면 값을
/// 늘린다.
enum RejectedWallReason { tooThick }

/// 벽 band로 병합됐지만 최종 벽 후보에서 제외된 구간 — PC2 2D CAD
/// 재조사(사용자 실기 FAIL 원인 진단) WO. 실제 제품 동작에는 전혀
/// 영향을 주지 않는다(최종 [WallSegment]/[CadWall] 목록에는 들어가지
/// 않는다) — 오직 "분석 확인"(개발자용) 디버그 오버레이에서만, 원본
/// 도면의 어떤 어두운 영역이 왜 벽으로 인정되지 않았는지 보여주기
/// 위한 진단 전용 데이터다.
@immutable
class RejectedWallCandidate {
  const RejectedWallCandidate({
    required this.id,
    required this.start,
    required this.end,
    required this.thicknessNormalized,
    required this.reason,
  });

  final String id;
  final Point2 start;
  final Point2 end;
  final double thicknessNormalized;
  final RejectedWallReason reason;
}

/// 닫힌 영역(방/공간) 후보.
///
/// 2D 정확도 개선 WO(8번) — [FloorPlanAnalysisEngine]이 flood-fill로 찾은
/// 실제 픽셀 경계를 추적해(rectilinear contour, L자 등 오목 형태 포함)
/// polygon으로 담는다. 추적이 실패하는 예상 밖 경우(구멍이 있는 영역 등,
/// 방어적으로만 발생)에만 기존 경계 사각형(4점)으로 폴백한다 — 어느
/// 쪽이든 polygon은 항상 실제로 검출된 형태를 그대로 반영하며, 임의로
/// 지어내지 않는다.
@immutable
class RoomCandidate {
  const RoomCandidate({
    required this.id,
    required this.polygon,
    required this.areaNormalized,
    required this.confidence,
    this.closed = true,
  });

  final String id;

  /// 실제 픽셀 경계를 따라간 polygon(보통 4점보다 많을 수 있다) — 추적에
  /// 실패했을 때만 경계 사각형(4점) 폴백. 시계 방향이 보장되지는 않는다
  /// (호출부는 [containsPoint]/삼각분할처럼 방향에 의존하지 않는 방식만
  /// 쓴다).
  final List<Point2> polygon;

  /// 전체 이미지 면적 대비 비율(0.0~1.0).
  final double areaNormalized;

  final double confidence;

  /// 이미지 경계에 닿지 않고 완전히 벽으로 둘러싸였는지. false면 화면에
  /// "공간이 완전히 닫히지 않았습니다" 경고가 함께 표시된다(WO 9번).
  final bool closed;

  bool containsPoint(Point2 p) {
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final a = polygon[i];
      final b = polygon[j];
      final intersects =
          ((a.y > p.y) != (b.y > p.y)) &&
          (p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x);
      if (intersects) inside = !inside;
    }
    return inside;
  }
}

/// 개발 검증용 최소 통계 — production UI에는 과도하게 노출하지 않고
/// [FloorPlanWorkspaceScreen]의 "정보" 탭 등 개발자가 확인할 자리에만
/// 붙인다(WO 26번).
@immutable
class FloorPlanAnalysisDebugStats {
  const FloorPlanAnalysisDebugStats({
    required this.sourceWidthPx,
    required this.sourceHeightPx,
    required this.analysisWidthPx,
    required this.analysisHeightPx,
    required this.rawHorizontalRuns,
    required this.rawVerticalRuns,
    required this.mergedWallCount,
    required this.roomCandidateCount,
    required this.openingCandidateCount,
    required this.durationMs,
    this.rejectedWallCount = 0,
    this.rotationDegrees = 0,
  });

  final int sourceWidthPx;
  final int sourceHeightPx;
  final int analysisWidthPx;
  final int analysisHeightPx;
  final int rawHorizontalRuns;
  final int rawVerticalRuns;
  final int mergedWallCount;
  final int roomCandidateCount;
  final int openingCandidateCount;
  final int durationMs;

  /// 두께 필터에 걸려 최종 벽 후보에서 제외된 band 수(진단 전용,
  /// [RejectedWallCandidate] 참고).
  final int rejectedWallCount;

  /// PC2 2D CAD 재조사 WO — 추정된 지배적 회전 보정각(도). 0이면 도면이
  /// 이미 이미지 축에 잘 맞아 회전 보정이 적용되지 않았다는 뜻이다.
  final double rotationDegrees;
}

/// 평면도 한 장을 분석한 결과 전체.
@immutable
class FloorPlanAnalysisResult {
  const FloorPlanAnalysisResult({
    required this.sourceWidthPx,
    required this.sourceHeightPx,
    required this.walls,
    required this.openings,
    required this.rooms,
    required this.warnings,
    required this.debugStats,
    this.rejectedWalls = const [],
  });

  /// 원본(다운샘플 전) 이미지 픽셀 크기 — 화면에 실제로 그려지는
  /// [Image.memory]의 자연 크기와 같아, contain-fit 변환의 기준이 된다.
  final int sourceWidthPx;
  final int sourceHeightPx;

  final List<WallSegment> walls;
  final List<OpeningCandidate> openings;
  final List<RoomCandidate> rooms;

  /// "공간이 완전히 닫히지 않았습니다" 같은, 결과는 있지만 사용자가
  /// 알아야 할 경고 메시지.
  final List<String> warnings;

  final FloorPlanAnalysisDebugStats debugStats;

  /// 벽 후보에서 걸러진 band — [RejectedWallCandidate] 참고. 진단
  /// 전용이며 기본값(빈 목록)이면 기존 호출부는 아무 변화가 없다.
  final List<RejectedWallCandidate> rejectedWalls;

  FloorPlanAnalysisResult copyWithWalls(List<WallSegment> walls) {
    return FloorPlanAnalysisResult(
      sourceWidthPx: sourceWidthPx,
      sourceHeightPx: sourceHeightPx,
      walls: walls,
      openings: openings,
      rooms: rooms,
      warnings: warnings,
      debugStats: debugStats,
      rejectedWalls: rejectedWalls,
    );
  }
}

/// "평면도 분석 시작" 진행 중 보여줄 실제 단계.
///
/// 각 값은 실제로 별도의 비동기 작업(격리된 isolate 호출 또는 실제 결과
/// 조립)에 대응한다 — 타이머로 흉내낸 가짜 단계가 아니다(WO 14번).
enum FloorPlanAnalysisStep {
  /// 이미지 디코드/다운샘플/이진화와 벽 검출을 함께 수행하는 동안.
  preparingAndWalls,

  /// 공간(방) 후보와 문/창 후보를 검출하는 동안.
  roomsAndOpenings,

  /// 결과를 화면이 쓰는 모델로 조립하는 짧은 마무리 단계.
  finalizing,
}

/// 분석이 성공적인 결과를 내지 못했을 때의 이유 — 사용자에게는 짧은
/// 안내만 보여주고 개발자용 stack trace는 노출하지 않는다(WO 15번).
enum FloorPlanAnalysisFailureReason {
  unsupportedFormat,
  unreadableImage,
  tooSmall,
  noWallsFound,
  internalError,
}

/// [FloorPlanAnalysisService.analyze]의 최종 결과 — 성공/실패를 하나의
/// 값으로 표현한다([AppUpdateCheck]과 같은 "결과 enum + nullable payload"
/// 관례를 그대로 따른다).
@immutable
class FloorPlanAnalysisOutcome {
  const FloorPlanAnalysisOutcome.success(this.result)
    : isSuccess = true,
      failureReason = null,
      message = null;

  const FloorPlanAnalysisOutcome.failure(this.failureReason, this.message)
    : isSuccess = false,
      result = null;

  final bool isSuccess;
  final FloorPlanAnalysisResult? result;
  final FloorPlanAnalysisFailureReason? failureReason;
  final String? message;
}
