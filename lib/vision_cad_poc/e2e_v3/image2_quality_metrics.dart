import 'dart:math' as math;
import 'dart:typed_data';

import '../../models/vision_understanding.dart';
import '../../services/hinted_geometry_extractor.dart';

/// SPACE SHIFT — Image 2 GPT Direct CAD Geometry Proposal Benchmark.
/// 품질 지표 계산 전용 — [VisionGuidedSpatialModelBuilder]가 실제로
/// 만드는 최종 CAD에는 관여하지 않는다(그 파일은 전혀 수정하지 않는다).
/// 같은 [HintedGeometryExtractor]를 한 번 더 호출해, 각 벽의 proposal
/// 위치와 실제 픽셀에서 찾은 위치 사이의 픽셀 거리(delta)를 진단
/// 목적으로만 기록한다 — 가짜 ground truth를 만들어 비교하지 않는다
/// (proposal 자체가 곧 "비교 대상"이다).
class WallQualityMetric {
  const WallQualityMetric({
    required this.boundaryId,
    required this.found,
    this.deltaPx,
    this.geometryConfidence,
  });

  final String boundaryId;
  final bool found;
  final double? deltaPx;
  final VisionConfidence? geometryConfidence;
}

class Image2QualityMetrics {
  const Image2QualityMetrics(this.wallMetrics);

  final List<WallQualityMetric> wallMetrics;

  List<double> get _deltas => [for (final m in wallMetrics) if (m.deltaPx != null) m.deltaPx!];

  double get meanDeltaPx => _deltas.isEmpty ? 0 : _deltas.reduce((a, b) => a + b) / _deltas.length;
  double get maxDeltaPx => _deltas.isEmpty ? 0 : _deltas.reduce(math.max);

  int get highCount => wallMetrics.where((m) => m.geometryConfidence == VisionConfidence.high).length;
  int get mediumCount => wallMetrics.where((m) => m.geometryConfidence == VisionConfidence.medium).length;
  int get lowCount => wallMetrics.where((m) => m.geometryConfidence == VisionConfidence.low).length;
  int get unmatchedCount => wallMetrics.where((m) => !m.found).length;
}

class Image2QualityMetricsComputer {
  const Image2QualityMetricsComputer();

  Image2QualityMetrics compute(VisionUnderstanding proposal, Uint8List imageBytes) {
    final extractor = HintedGeometryExtractor(imageBytes);
    final metrics = <WallQualityMetric>[];

    for (final boundary in proposal.boundaries) {
      final hint = boundary.geometryHint;
      if (hint == null || hint.kind != GeometryHintKind.segment) continue;

      final candidate = extractor.refineBoundary(hint.start, hint.end);
      if (candidate == null) {
        metrics.add(WallQualityMetric(boundaryId: boundary.id, found: false));
        continue;
      }

      final hintMidX = (hint.start.x + hint.end.x) / 2;
      final hintMidY = (hint.start.y + hint.end.y) / 2;
      final refPoints = candidate.geometry.allPoints;
      final refMidX = (refPoints.first.x + refPoints.last.x) / 2;
      final refMidY = (refPoints.first.y + refPoints.last.y) / 2;

      final dxPx = (hintMidX - refMidX) * extractor.width;
      final dyPx = (hintMidY - refMidY) * extractor.height;
      final deltaPx = math.sqrt(dxPx * dxPx + dyPx * dyPx);

      metrics.add(WallQualityMetric(
        boundaryId: boundary.id,
        found: true,
        deltaPx: deltaPx,
        geometryConfidence: candidate.confidence,
      ));
    }

    return Image2QualityMetrics(metrics);
  }
}
