import '../models/vision_understanding.dart';
import 'hinted_geometry_extractor.dart';

/// Vision Guided CAD POC — Vision↔Geometry Matcher(설계 5번).
///
/// Vision(무엇/대략 어디)과 [HintedGeometryExtractor](정확히 어디)의
/// 결과를 대조해 다섯 가지 경우 중 하나로 분류한다. 어떤 경우에도
/// geometry를 억지로 vision hint에 맞추거나, vision 주장을 근거 없이
/// 확정하지 않는다 — 애매하면 항상 confidence를 낮추고 reviewNeeded를
/// 세운다.
enum MatchCase {
  /// CASE A — Vision과 Geometry 모두 확신 높음 → 확정.
  caseA,

  /// CASE B — Vision은 확신 높지만 Geometry가 약함(확장 재탐색 이후에도)
  /// → semantic은 유지하되 geometry confidence를 낮추고 review 표시.
  caseB,

  /// CASE C — Vision은 약하지만 Geometry가 강함 → geometry만 채택,
  /// semantic 분류는 미확정(UNKNOWN) 처리.
  caseC,

  /// CASE D — 충돌(예: Vision=문 vs Geometry=연속된 벽) → 자동 판단하지
  /// 않고 Topology Validator로 넘긴다.
  caseD,

  /// CASE E — Vision은 존재를 주장하지만 Geometry 근거가 전혀 없음 →
  /// 미확정/할루시네이션 가능성, 자동 CAD 생성에서 제외.
  caseE,
}

/// 매칭 한 건의 결과 — 최종 confidence/source/geometry와, 자동 CAD
/// 생성에 포함시킬지([included]) 여부, 사람 확인이 필요한지
/// ([reviewNeeded])를 함께 담는다.
class MatchResult {
  const MatchResult({
    required this.matchCase,
    required this.confidence,
    required this.source,
    required this.included,
    required this.typeConfirmed,
    this.reviewNeeded = false,
    this.reviewReasons = const [],
    this.finalGeometryHint,
  });

  final MatchCase matchCase;
  final VisionConfidence confidence;
  final VisionSource source;

  /// 이 entity를 자동 CAD 생성 파이프라인에 포함시킬지 — CASE E는 항상
  /// false(WO 절대 금지: hallucination을 CAD로 확정하지 않는다).
  final bool included;

  /// Vision이 매긴 semantic 분류(방 종류/boundary 종류/opening 종류 등)를
  /// 신뢰할 수 있는지 — CASE C는 항상 false(geometry는 존재만 확인해줄
  /// 뿐 종류를 확인해주지 않는다).
  final bool typeConfirmed;

  final bool reviewNeeded;
  final List<String> reviewReasons;

  /// geometry extractor가 찾아낸 정밀 geometry(있으면). CASE C/A에서는
  /// 항상 채워진다. CASE B는 재탐색으로 얻은 약한 geometry가, CASE
  /// D/E는 boundary 결과(있다면)만 참고용으로 담길 수 있다.
  final GeometryHint? finalGeometryHint;
}

bool _isHighish(VisionConfidence c) => c == VisionConfidence.high || c == VisionConfidence.medium;

class VisionGeometryMatcher {
  const VisionGeometryMatcher();

  /// [VisionBoundary]와 [HintedGeometryExtractor.refineBoundary] 결과를
  /// 대조한다. [geometryResult]가 null이면 hint 주변에서 벽 근거를 전혀
  /// 찾지 못했다는 뜻이다(재시도 포함, 이미 extractor 내부에서 처리됨).
  MatchResult matchBoundary({
    required VisionBoundary boundary,
    required GeometryCandidate? geometryResult,
  }) {
    final visionHigh = _isHighish(boundary.confidence);

    if (geometryResult == null) {
      return MatchResult(
        matchCase: MatchCase.caseE,
        confidence: VisionConfidence.unknown,
        source: VisionSource.vision,
        included: false,
        typeConfirmed: false,
        reviewNeeded: true,
        reviewReasons: const [
          'vision hinted a boundary but no wall evidence was found in the hinted '
              'region even after an expanded retry — possible hallucination',
        ],
      );
    }

    final geometryHigh = _isHighish(geometryResult.confidence);

    if (visionHigh && geometryHigh) {
      return MatchResult(
        matchCase: MatchCase.caseA,
        confidence: VisionConfidence.high,
        source: VisionSource.validated,
        included: true,
        typeConfirmed: true,
        finalGeometryHint: geometryResult.geometry,
      );
    }

    if (visionHigh && !geometryHigh) {
      return MatchResult(
        matchCase: MatchCase.caseB,
        confidence: VisionConfidence.low,
        source: VisionSource.vision,
        included: true,
        typeConfirmed: true,
        reviewNeeded: true,
        reviewReasons: const [
          'vision confidence high but geometry evidence weak after retry — '
              'kept vision semantic with low geometry confidence',
        ],
        finalGeometryHint: geometryResult.geometry,
      );
    }

    if (!visionHigh && geometryHigh) {
      return MatchResult(
        matchCase: MatchCase.caseC,
        confidence: VisionConfidence.high,
        source: VisionSource.geometry,
        included: true,
        typeConfirmed: false,
        reviewNeeded: true,
        reviewReasons: const [
          'geometry strongly confirms a boundary here but vision confidence was '
              'low — boundary type/classification is not vision-confirmed',
        ],
        finalGeometryHint: geometryResult.geometry,
      );
    }

    // 둘 다 약함 — 어느 쪽도 강하게 뒷받침하지 않는다.
    return MatchResult(
      matchCase: MatchCase.caseE,
      confidence: VisionConfidence.low,
      source: VisionSource.geometry,
      included: false,
      typeConfirmed: false,
      reviewNeeded: true,
      reviewReasons: const ['both vision and geometry confidence are low for this boundary'],
      finalGeometryHint: geometryResult.geometry,
    );
  }

  /// [VisionOpening]과 [HintedGeometryExtractor.refineOpening] 결과를
  /// 대조한다. 벽이 끊김 없이 이어지는 경우([wallContinuous])는 vision
  /// confidence와 무관하게 항상 CASE D(충돌)로 분류한다 — "문이 있다"는
  /// 주장과 "벽이 끊기지 않았다"는 관측은 구조적으로 양립할 수 없기
  /// 때문이다.
  MatchResult matchOpening({
    required VisionOpening opening,
    required OpeningGeometryResult geometryResult,
  }) {
    if (geometryResult.wallContinuous) {
      return const MatchResult(
        matchCase: MatchCase.caseD,
        confidence: VisionConfidence.unknown,
        source: VisionSource.vision,
        included: false,
        typeConfirmed: false,
        reviewNeeded: true,
        reviewReasons: [
          'vision claims an opening here but geometry shows the wall continues '
              'without a gap — conflict forwarded to topology validation, no '
              'automatic decision made',
        ],
      );
    }

    if (!geometryResult.found) {
      return const MatchResult(
        matchCase: MatchCase.caseE,
        confidence: VisionConfidence.unknown,
        source: VisionSource.vision,
        included: false,
        typeConfirmed: false,
        reviewNeeded: true,
        reviewReasons: [
          'vision hinted an opening but no gap or continuous wall could be '
              'determined at that location — possible hallucination',
        ],
      );
    }

    final visionHigh = _isHighish(opening.confidence);
    final refinedHint = geometryResult.center == null
        ? null
        : GeometryHint.point(geometryResult.center!);

    if (visionHigh) {
      return MatchResult(
        matchCase: MatchCase.caseA,
        confidence: VisionConfidence.high,
        source: VisionSource.validated,
        included: true,
        typeConfirmed: true,
        finalGeometryHint: refinedHint,
      );
    }

    return MatchResult(
      matchCase: MatchCase.caseC,
      confidence: VisionConfidence.high,
      source: VisionSource.geometry,
      included: true,
      typeConfirmed: false,
      reviewNeeded: true,
      reviewReasons: const [
        'geometry confirms a wall gap here but vision confidence was low — '
            'opening type (door/window/passage) is not vision-confirmed',
      ],
      finalGeometryHint: refinedHint,
    );
  }

  /// [VisionObject]는 정밀 외곽선을 재구성하지 않는다 — hint 영역에
  /// 어떤 형태로든 픽셀 구조가 있는지([hasStructure])만으로 존재 여부를
  /// 판단한다.
  MatchResult matchObject({required VisionObject object, required bool hasStructure}) {
    if (!hasStructure) {
      return const MatchResult(
        matchCase: MatchCase.caseE,
        confidence: VisionConfidence.unknown,
        source: VisionSource.vision,
        included: false,
        typeConfirmed: false,
        reviewNeeded: true,
        reviewReasons: [
          'vision claims an object here but no pixel structure was found in the '
              'hinted region — possible hallucination',
        ],
      );
    }

    final visionHigh = _isHighish(object.confidence);
    if (visionHigh) {
      return const MatchResult(
        matchCase: MatchCase.caseA,
        confidence: VisionConfidence.high,
        source: VisionSource.validated,
        included: true,
        typeConfirmed: true,
      );
    }

    return const MatchResult(
      matchCase: MatchCase.caseC,
      confidence: VisionConfidence.medium,
      source: VisionSource.geometry,
      included: true,
      typeConfirmed: false,
      reviewNeeded: true,
      reviewReasons: [
        'pixel structure confirms something exists here but vision confidence '
            'was low — object type is not vision-confirmed',
      ],
    );
  }
}
