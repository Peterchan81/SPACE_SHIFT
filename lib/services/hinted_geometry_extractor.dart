import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/vision_understanding.dart';
import 'floor_plan_analysis_engine.dart' show RawRun, WallBand, mergeRunsToBands, otsuThreshold, scanRuns;

/// Vision Guided CAD POC — "Vision이 WHAT + WHERE-ABOUT를 주면, Geometry가
/// EXACT WHERE를 찾는다"(설계 4번)의 실제 구현.
///
/// 전체 이미지에서 무작정 벽을 찾지 않는다 — Vision hint 주변 좁은
/// 영역에서만 기존 저수준 함수([otsuThreshold]/[scanRuns]/
/// [mergeRunsToBands], `floor_plan_analysis_engine.dart`에서 이 목적을
/// 위해 public으로 바꾼 것들)를 재사용해 정밀 geometry를 찾는다.
/// [floor_plan_analysis_engine.dart]의 최종 semantic 판단(어떤 band가
/// "진짜 벽"인가) 로직은 여기서 다시 쓰지 않는다 — 이 클래스는 오직
/// "이 특정 위치에 벽/개구부가 있는가"만 판단한다.
class HintedGeometryExtractor {
  HintedGeometryExtractor(Uint8List imageBytes) : _image = img.decodeImage(imageBytes) {
    final image = _image;
    if (image == null) {
      _mask = null;
      width = 0;
      height = 0;
      return;
    }
    width = image.width;
    height = image.height;
    final luminance = List<int>.filled(width * height, 0);
    final histogram = List<int>.filled(256, 0);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final l = image.getPixel(x, y).luminance.round().clamp(0, 255);
        luminance[y * width + x] = l;
        histogram[l]++;
      }
    }
    final threshold = otsuThreshold(histogram, width * height);
    final mask = Uint8List(width * height);
    for (var i = 0; i < luminance.length; i++) {
      mask[i] = luminance[i] <= threshold ? 1 : 0;
    }
    _mask = mask;
  }

  final img.Image? _image;
  Uint8List? _mask;
  int width = 0;
  int height = 0;

  bool get isReady => _image != null && _mask != null && width > 0 && height > 0;

  /// hint 주변([marginRatio] × 이미지 대각선)만 스캔해 실제 벽 band를
  /// 찾는다. 찾지 못하면 [marginRatio]를 한 번 더 넓혀 재시도한다(설계
  /// CASE B — "탐색 범위 1회 확장").
  GeometryCandidate? refineBoundary(NormalizedPoint start, NormalizedPoint end) {
    if (!isReady) return null;
    final candidate = _searchBoundary(start, end, marginRatio: 0.02);
    if (candidate != null) return candidate;
    return _searchBoundary(start, end, marginRatio: 0.05);
  }

  GeometryCandidate? _searchBoundary(
    NormalizedPoint start,
    NormalizedPoint end, {
    required double marginRatio,
  }) {
    final diagonal = math.sqrt(width * width + height * height);
    final marginPx = (diagonal * marginRatio).round().clamp(2, width + height);

    final x1 = (start.x * width).round();
    final y1 = (start.y * height).round();
    final x2 = (end.x * width).round();
    final y2 = (end.y * height).round();
    final horizontal = (x2 - x1).abs() >= (y2 - y1).abs();

    final alongMinHint = horizontal ? math.min(x1, x2) : math.min(y1, y2);
    final alongMaxHint = horizontal ? math.max(x1, x2) : math.max(y1, y2);
    final crossHint = horizontal ? (y1 + y2) / 2 : (x1 + x2) / 2;

    final crossMinSearch = (crossHint - marginPx).round().clamp(0, horizontal ? height - 1 : width - 1);
    final crossMaxSearch = (crossHint + marginPx).round().clamp(0, horizontal ? height - 1 : width - 1);
    final alongMinSearch = (alongMinHint - marginPx).clamp(0, horizontal ? width : height);
    final alongMaxSearch = (alongMaxHint + marginPx).clamp(0, horizontal ? width : height);

    // 절대 최소 길이만 걸러낸다(잡음 픽셀 제거용). hint 전체 길이에
    // 비례한 값을 쓰면, 문/창 gap으로 원래 하나였던 벽이 두 개의 짧은
    // run으로 쪼개졌을 때 더 짧은 쪽이 통째로 걸러져 벽의 실제 범위가
    // gap 건너편 조각 하나로 잘못 축소되는 문제가 있었다.
    const minRunLen = 4;
    final alongLen = alongMaxSearch - alongMinSearch;
    if (alongLen <= 0) return null;

    final runs = <RawRun>[];
    for (var cross = crossMinSearch; cross <= crossMaxSearch; cross++) {
      // 한 줄(cross line)만 담은 1차원 sub-mask를 만들어 기존 [scanRuns]를
      // 그대로 재사용한다 — 새 스캔 루프를 다시 짜지 않는다.
      final line = Uint8List(alongLen);
      for (var i = 0; i < alongLen; i++) {
        final along = alongMinSearch + i;
        final x = horizontal ? along : cross;
        final y = horizontal ? cross : along;
        line[i] = _mask![y * width + x];
      }
      final lineRuns = horizontal
          ? scanRuns(line, alongLen, 1, horizontal: true, minRunLen: minRunLen)
          : scanRuns(line, 1, alongLen, horizontal: false, minRunLen: minRunLen);
      for (final r in lineRuns) {
        runs.add(RawRun(cross, alongMinSearch + r.start, alongMinSearch + r.end));
      }
    }
    if (runs.isEmpty) return null;

    final bands = mergeRunsToBands(runs, maxThicknessPx: crossMaxSearch - crossMinSearch + 1);
    if (bands.isEmpty) return null;

    // hint의 cross 위치에 가장 가까운 band를 고른다.
    WallBand? best;
    var bestDist = double.infinity;
    for (final band in bands) {
      final dist = (band.crossCenter - crossHint).abs();
      if (dist < bestDist) {
        best = band;
        bestDist = dist;
      }
    }
    if (best == null) return null;

    // 문/창 gap 때문에 같은 벽 한 줄이 cross 위치는 거의 같지만 along
    // 범위가 서로 다른 여러 band로 쪼개졌을 수 있다 — 그런 band들을
    // 묶어 전체 범위(gap 포함 양쪽 끝)를 "이 경계선의 실제 범위"로
    // 본다. gap 자체를 메우지는 않는다([refineOpening]이 그 안에서
    // gap을 다시 찾는다) — 여기서는 boundary 확인/범위만 정한다.
    final sameLine = bands.where((b) => (b.crossCenter - best!.crossCenter).abs() <= 2).toList();
    final groupAlongMin = sameLine.map((b) => b.alongMin).reduce(math.min);
    final groupAlongMax = sameLine.map((b) => b.alongMax).reduce(math.max);
    final groupCrossCenter = sameLine.map((b) => b.crossCenter).reduce((a, b) => a + b) / sameLine.length;
    final groupThickness = sameLine.map((b) => b.thicknessPx).reduce(math.max);

    final coveredLen = math.min(groupAlongMax, alongMaxHint) - math.max(groupAlongMin, alongMinHint);
    final hintLen = math.max(1, alongMaxHint - alongMinHint);
    final coverageRatio = (coveredLen / hintLen).clamp(0.0, 1.0);
    final confidence = coverageRatio >= 0.6 && bestDist <= marginPx * 0.6
        ? VisionConfidence.high
        : coverageRatio >= 0.25
        ? VisionConfidence.medium
        : VisionConfidence.low;

    final preciseStart = horizontal
        ? NormalizedPoint(groupAlongMin / width, groupCrossCenter / height)
        : NormalizedPoint(groupCrossCenter / width, groupAlongMin / height);
    final preciseEnd = horizontal
        ? NormalizedPoint(groupAlongMax / width, groupCrossCenter / height)
        : NormalizedPoint(groupCrossCenter / width, groupAlongMax / height);

    return GeometryCandidate(
      geometry: GeometryHint.segment(preciseStart, preciseEnd),
      confidence: confidence,
      thicknessNormalized: groupThickness / (horizontal ? height : width),
    );
  }

  /// [refineBoundary]로 이미 정밀화된 boundary 위에서, [openingHint] 위치
  /// 근처에 실제 벽 gap(문/창 후보)이 있는지 찾는다. 벽이 끊김 없이
  /// 이어지면(gap 없음) [OpeningGeometryResult.wallContinuous]가 true다
  /// — 이 경우와 "아예 아무것도 없음"은 다른 상황이므로 구분해서
  /// 돌려준다(설계 CASE D vs CASE E를 구분하는 근거).
  OpeningGeometryResult refineOpening({
    required NormalizedPoint boundaryStart,
    required NormalizedPoint boundaryEnd,
    required NormalizedPoint openingHint,
  }) {
    if (!isReady) {
      return const OpeningGeometryResult(found: false, wallContinuous: false);
    }
    final x1 = (boundaryStart.x * width).round();
    final y1 = (boundaryStart.y * height).round();
    final x2 = (boundaryEnd.x * width).round();
    final y2 = (boundaryEnd.y * height).round();
    final horizontal = (x2 - x1).abs() >= (y2 - y1).abs();
    final cross = horizontal ? ((y1 + y2) / 2).round() : ((x1 + x2) / 2).round();
    final alongMin = horizontal ? math.min(x1, x2) : math.min(y1, y2);
    final alongMax = horizontal ? math.max(x1, x2) : math.max(y1, y2);
    final hintAlong = horizontal ? (openingHint.x * width).round() : (openingHint.y * height).round();

    // boundary 중심선 ±두께 정도의 좁은 띠에서 "밝은(벽이 아닌) 픽셀"이
    // 연속되는 구간(gap)을 찾는다.
    const crossBand = 3;
    var gapStart = -1, gapEnd = -1;
    final innerStart = math.max(alongMin, hintAlong - (alongMax - alongMin));
    final innerEnd = math.min(alongMax, hintAlong + (alongMax - alongMin));
    for (var along = innerStart; along <= innerEnd; along++) {
      final isWall = _isWallAt(horizontal: horizontal, along: along, cross: cross, band: crossBand);
      if (!isWall) {
        if (gapStart == -1) gapStart = along;
        gapEnd = along;
      } else if (gapStart != -1 && (gapEnd - gapStart).abs() > 2) {
        break;
      } else {
        gapStart = -1;
        gapEnd = -1;
      }
    }

    if (gapStart == -1 || gapEnd - gapStart < 2) {
      return const OpeningGeometryResult(found: false, wallContinuous: true);
    }

    final centerAlong = (gapStart + gapEnd) / 2;
    final widthPx = (gapEnd - gapStart).toDouble();
    final center = horizontal
        ? NormalizedPoint(centerAlong / width, cross / height)
        : NormalizedPoint(cross / width, centerAlong / height);
    return OpeningGeometryResult(
      found: true,
      wallContinuous: false,
      center: center,
      widthNormalized: widthPx / math.sqrt(width * width + height * height),
    );
  }

  /// [hintBox] 안에 어떤 형태로든 실제 어두운 픽셀 구조가 있는지만
  /// 확인한다 — 가구/설비의 정확한 외곽선은 재구성하지 않는다(설계
  /// 문서 원칙: 오브젝트는 정밀 형태보다 "여기 무언가 있다/없다"만
  /// 확인해 hallucination(CASE E)만 걸러낸다).
  bool regionHasStructure(({double minX, double minY, double maxX, double maxY}) hintBox) {
    if (!isReady) return false;
    final x1 = (hintBox.minX * width).round().clamp(0, width - 1);
    final y1 = (hintBox.minY * height).round().clamp(0, height - 1);
    final x2 = (hintBox.maxX * width).round().clamp(0, width - 1);
    final y2 = (hintBox.maxY * height).round().clamp(0, height - 1);
    var darkCount = 0;
    var total = 0;
    for (var y = math.min(y1, y2); y <= math.max(y1, y2); y++) {
      for (var x = math.min(x1, x2); x <= math.max(x1, x2); x++) {
        total++;
        if (_mask![y * width + x] == 1) darkCount++;
      }
    }
    if (total == 0) return false;
    return darkCount / total > 0.02;
  }

  bool _isWallAt({required bool horizontal, required int along, required int cross, required int band}) {
    for (var offset = -band; offset <= band; offset++) {
      final x = horizontal ? along : cross + offset;
      final y = horizontal ? cross + offset : along;
      if (x < 0 || y < 0 || x >= width || y >= height) continue;
      if (_mask![y * width + x] == 1) return true;
    }
    return false;
  }
}

/// [HintedGeometryExtractor.refineBoundary]의 결과 — hint 근처에서 실제로
/// 발견된 정밀 geometry와, 그 발견에 대한 geometry측 confidence.
class GeometryCandidate {
  const GeometryCandidate({
    required this.geometry,
    required this.confidence,
    required this.thicknessNormalized,
  });

  final GeometryHint geometry;
  final VisionConfidence confidence;
  final double thicknessNormalized;
}

/// [HintedGeometryExtractor.refineOpening]의 결과. [found]가 false이면서
/// [wallContinuous]가 true인 경우(벽이 끊김 없이 이어짐)와, [found]가
/// false이면서 [wallContinuous]도 false인 경우(추출기 자체가 준비되지
/// 않음 등)는 의미가 다르다 — 전자는 CASE D(vision=door vs
/// geometry=continuous wall 충돌) 판단의 근거가 된다.
class OpeningGeometryResult {
  const OpeningGeometryResult({
    required this.found,
    required this.wallContinuous,
    this.center,
    this.widthNormalized,
  });

  final bool found;
  final bool wallContinuous;
  final NormalizedPoint? center;
  final double? widthNormalized;
}
