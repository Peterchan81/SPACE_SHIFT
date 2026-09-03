import 'dart:math' as math;
import 'dart:typed_data';

import '../../models/vision_understanding.dart' show NormalizedPoint, VisionConfidence;
import '../../services/hinted_geometry_extractor.dart';
import 'gpt_cad_schema.dart';

/// SPACE SHIFT — Real GPT Vision → Detailed CAD JSON → SS Refinement POC.
///
/// GPT가 corner 좌표를 pixel 단위로 이미 상당히 정확하게 준다는 전제
/// 하에(설계 18번), 각 wall segment 주변의 좁은 ROI에서만 실제 픽셀을
/// 다시 확인한다 — 전체 이미지를 다시 스캔하지 않는다. 기존
/// [HintedGeometryExtractor](이미 검증된 코드)를 그대로 재사용하고 여기서
/// 새 픽셀 처리 로직을 만들지 않는다.
class WallSegmentRefinement {
  const WallSegmentRefinement({
    required this.wallId,
    required this.segmentIndex,
    required this.visionStart,
    required this.visionEnd,
    required this.visionConfidence,
    this.refinedStart,
    this.refinedEnd,
    this.deltaPx,
    this.geometryConfidence,
  });

  final String wallId;
  final int segmentIndex;
  final NormalizedPoint visionStart;
  final NormalizedPoint visionEnd;
  final VisionConfidence visionConfidence;
  final NormalizedPoint? refinedStart;
  final NormalizedPoint? refinedEnd;
  final double? deltaPx;
  final VisionConfidence? geometryConfidence;

  bool get found => refinedStart != null;
}

class GptLocalRefinementResult {
  const GptLocalRefinementResult({required this.segments, required this.refinedCornerPositions});

  final List<WallSegmentRefinement> segments;

  /// corner id → 그 corner에 닿은 모든 wall segment 정밀화 결과의
  /// 평균(normalized). 정밀화에 실패한 corner는 원본 GPT 좌표만 남는다
  /// (별도로 [GptCadProposal.corners]에서 조회).
  final Map<String, ({double x, double y})> refinedCornerPositions;
}

class GptLocalRefinement {
  const GptLocalRefinement();

  GptLocalRefinementResult refine(GptCadProposal proposal, Uint8List imageBytes) {
    final extractor = HintedGeometryExtractor(imageBytes);
    final cornersById = {for (final c in proposal.corners) c.id: c};
    final segments = <WallSegmentRefinement>[];

    final cornerSumX = <String, double>{};
    final cornerSumY = <String, double>{};
    final cornerCount = <String, int>{};

    void accumulate(String cornerId, double x, double y) {
      cornerSumX[cornerId] = (cornerSumX[cornerId] ?? 0) + x;
      cornerSumY[cornerId] = (cornerSumY[cornerId] ?? 0) + y;
      cornerCount[cornerId] = (cornerCount[cornerId] ?? 0) + 1;
    }

    for (final wall in proposal.walls) {
      for (var i = 0; i < wall.cornerIds.length - 1; i++) {
        final c1 = cornersById[wall.cornerIds[i]]!;
        final c2 = cornersById[wall.cornerIds[i + 1]]!;
        final start = NormalizedPoint(c1.x / proposal.image.widthPx, c1.y / proposal.image.heightPx);
        final end = NormalizedPoint(c2.x / proposal.image.widthPx, c2.y / proposal.image.heightPx);
        final visionConfidence = _toVisionConfidence(wall.confidence);

        final candidate = extractor.refineBoundary(start, end);
        if (candidate == null) {
          segments.add(WallSegmentRefinement(
            wallId: wall.id,
            segmentIndex: i,
            visionStart: start,
            visionEnd: end,
            visionConfidence: visionConfidence,
          ));
          continue;
        }

        final refPoints = candidate.geometry.allPoints;
        final refinedStart = refPoints.first;
        final refinedEnd = refPoints.last;

        final dxPx = (start.x - refinedStart.x) * extractor.width;
        final dyPx = (start.y - refinedStart.y) * extractor.height;
        final deltaPx = _distance(dxPx, dyPx);

        segments.add(WallSegmentRefinement(
          wallId: wall.id,
          segmentIndex: i,
          visionStart: start,
          visionEnd: end,
          visionConfidence: visionConfidence,
          refinedStart: refinedStart,
          refinedEnd: refinedEnd,
          deltaPx: deltaPx,
          geometryConfidence: candidate.confidence,
        ));

        accumulate(c1.id, refinedStart.x, refinedStart.y);
        accumulate(c2.id, refinedEnd.x, refinedEnd.y);
      }
    }

    final refinedCorners = <String, ({double x, double y})>{
      for (final id in cornerCount.keys) id: (x: cornerSumX[id]! / cornerCount[id]!, y: cornerSumY[id]! / cornerCount[id]!),
    };

    return GptLocalRefinementResult(segments: segments, refinedCornerPositions: refinedCorners);
  }

  VisionConfidence _toVisionConfidence(double c) {
    if (c >= 0.8) return VisionConfidence.high;
    if (c >= 0.5) return VisionConfidence.medium;
    if (c > 0) return VisionConfidence.low;
    return VisionConfidence.unknown;
  }

  double _distance(double dx, double dy) => math.sqrt(dx * dx + dy * dy);
}
