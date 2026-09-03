import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../services/floor_plan_analysis_engine.dart' show otsuThreshold;

/// SPACE SHIFT — Vision Hint → Exact Wall SNAP 기술검증.
///
/// 이 파일은 기존 `hinted_geometry_extractor.dart`(production
/// Vision-Guided 파이프라인이 쓰는 것)를 재사용/수정하지 않는다 — 이번
/// 지시("다른 벽 수정 금지, 전체 CAD 생성 개선 금지")를 지키기 위해
/// 완전히 독립된 1회성 기술검증 코드로 새로 작성한다. 유일하게
/// 재사용하는 것은 순수 함수 [otsuThreshold](임계값 계산 — 벽 판단
/// 로직이 아니라 흑백 임계값 하나를 고르는 범용 유틸리티)뿐이다.
///
/// 원칙:
/// - Vision hint의 좌표를 결과로 그대로 돌려주지 않는다 — 반드시 hint
///   주변 좁은 search window 안에서 실제 픽셀을 조사해 얻은 값만 쓴다.
/// - "검은 선 하나"가 아니라 "일정하게 이어지는 두 평행 edge(band)"를
///   찾는다 — band 폭/연속성이 기준에 못 미치면 실패로 본다.
/// - 벽의 시작/끝은 hint의 y 범위를 그대로 쓰지 않고, 그 범위를 벗어난
///   곳까지 마진을 두고 실제 junction(수직/수평 벽이 만나는 지점) 증거를
///   찾아 확정한다.
class SingleWallHint {
  const SingleWallHint({
    required this.xNormalized,
    required this.startYNormalized,
    required this.endYNormalized,
  });

  final double xNormalized;
  final double startYNormalized;
  final double endYNormalized;
}

class SingleWallSnapResult {
  const SingleWallSnapResult({
    required this.searchWindow,
    required this.leftEdgeX,
    required this.rightEdgeX,
    required this.centerX,
    required this.thicknessPx,
    required this.startY,
    required this.endY,
    required this.confidence,
    required this.confidenceReasons,
    required this.startJunctionConfirmed,
    required this.endJunctionConfirmed,
  });

  final ({double left, double top, double right, double bottom}) searchWindow;
  final double leftEdgeX;
  final double rightEdgeX;
  final double centerX;
  final double thicknessPx;
  final double startY;
  final double endY;
  final String confidence;
  final List<String> confidenceReasons;
  final bool startJunctionConfirmed;
  final bool endJunctionConfirmed;
}

class SingleWallSnapDetector {
  const SingleWallSnapDetector();

  SingleWallSnapResult? detect(Uint8List imageBytes, SingleWallHint hint) {
    final image = img.decodeImage(imageBytes);
    if (image == null) return null;
    final width = image.width;
    final height = image.height;

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
    bool isDark(int x, int y) {
      if (x < 0 || y < 0 || x >= width || y >= height) return false;
      return luminance[y * width + x] <= threshold;
    }

    // 1) 제한된 search window: 수평 ±5%, 수직은 hint 범위 + 15% 마진
    // (junction이 hint 범위 밖에 있을 수 있으므로).
    final hintX = hint.xNormalized * width;
    final hintYStart = hint.startYNormalized * height;
    final hintYEnd = hint.endYNormalized * height;
    final xMargin = width * 0.05;
    final yMargin = (hintYEnd - hintYStart).abs() * 0.15;

    final xMin = (hintX - xMargin).round().clamp(0, width - 1);
    final xMax = (hintX + xMargin).round().clamp(0, width - 1);
    final yMin = (math.min(hintYStart, hintYEnd) - yMargin).round().clamp(0, height - 1);
    final yMax = (math.max(hintYStart, hintYEnd) + yMargin).round().clamp(0, height - 1);

    // 2) 각 column마다 search window 안에서 가장 긴 연속 dark run을 찾는다
    // — "검은 선 하나"가 아니라 "세로로 길게 이어지는 band"만 벽 후보로
    // 본다.
    final runLength = List<int>.filled(xMax - xMin + 1, 0);
    final runStart = List<int>.filled(xMax - xMin + 1, 0);
    final runEnd = List<int>.filled(xMax - xMin + 1, 0);

    for (var x = xMin; x <= xMax; x++) {
      var bestLen = 0;
      var bestStart = yMin;
      var curStart = -1;
      for (var y = yMin; y <= yMax + 1; y++) {
        final dark = y <= yMax && isDark(x, y);
        if (dark) {
          curStart = curStart == -1 ? y : curStart;
        } else if (curStart != -1) {
          final len = y - curStart;
          if (len > bestLen) {
            bestLen = len;
            bestStart = curStart;
          }
          curStart = -1;
        }
      }
      final idx = x - xMin;
      runLength[idx] = bestLen;
      runStart[idx] = bestStart;
      runEnd[idx] = bestStart + bestLen - 1;
    }

    final maxRun = runLength.reduce(math.max);
    if (maxRun <= 0) return null;

    // "벽처럼 세로로 길게 이어지는" 조건 — search window 높이의
    // 절반 이상 이어져야 후보로 인정한다(가구/텍스트 같은 짧은
    // 조각은 자동 탈락).
    final windowHeight = yMax - yMin;
    if (maxRun < windowHeight * 0.5) {
      return null;
    }

    var peakIdx = runLength.indexOf(maxRun);

    // 3) peak에서 좌우로 확장하며 "비슷하게 긴 run을 가진" 인접
    // column만 같은 벽 band로 묶는다(평행한 두 edge 사이의 폭).
    bool qualifies(int idx) => runLength[idx] >= maxRun * 0.8;
    var leftIdx = peakIdx;
    while (leftIdx > 0 && qualifies(leftIdx - 1)) {
      leftIdx--;
    }
    var rightIdx = peakIdx;
    while (rightIdx < runLength.length - 1 && qualifies(rightIdx + 1)) {
      rightIdx++;
    }

    final leftEdgeX = (xMin + leftIdx).toDouble();
    final rightEdgeX = (xMin + rightIdx).toDouble();
    final centerX = (leftEdgeX + rightEdgeX) / 2;
    final thickness = rightEdgeX - leftEdgeX + 1;

    var startY = runStart[peakIdx].toDouble();
    var endY = runEnd[peakIdx].toDouble();

    // 4) 실제 junction 확인 — start/end 근처에서 벽 band 바깥
    // 좌우로도 어두운 픽셀(교차하는 가로 벽)이 이어지는지 검사한다.
    bool hasPerpendicularEvidence(int y) {
      const probe = 12;
      final leftHit = isDark((leftEdgeX - probe).round(), y) || isDark((leftEdgeX - probe / 2).round(), y);
      final rightHit = isDark((rightEdgeX + probe).round(), y) || isDark((rightEdgeX + probe / 2).round(), y);
      return leftHit && rightHit;
    }

    bool startConfirmed = false;
    for (var y = startY.round() - 8; y <= startY.round() + 8; y++) {
      if (hasPerpendicularEvidence(y.clamp(0, height - 1))) {
        startConfirmed = true;
        startY = y.toDouble();
        break;
      }
    }
    bool endConfirmed = false;
    for (var y = endY.round() + 8; y >= endY.round() - 8; y--) {
      if (hasPerpendicularEvidence(y.clamp(0, height - 1))) {
        endConfirmed = true;
        endY = y.toDouble();
        break;
      }
    }

    final reasons = <String>[];
    String confidence;
    if (startConfirmed && endConfirmed && thickness <= windowHeight * 0.3) {
      confidence = 'HIGH';
      reasons.add('both ends confirmed by perpendicular wall junction evidence');
    } else if (startConfirmed || endConfirmed) {
      confidence = 'MEDIUM';
      reasons.add('only one end confirmed by junction evidence');
      if (!startConfirmed) reasons.add('start point has no confirmed junction — may be an open end');
      if (!endConfirmed) reasons.add('end point has no confirmed junction — may be an open end');
    } else {
      confidence = 'LOW';
      reasons.add('no junction evidence found at either end within search margin');
    }

    return SingleWallSnapResult(
      searchWindow: (left: xMin.toDouble(), top: yMin.toDouble(), right: xMax.toDouble(), bottom: yMax.toDouble()),
      leftEdgeX: leftEdgeX,
      rightEdgeX: rightEdgeX,
      centerX: centerX,
      thicknessPx: thickness,
      startY: startY,
      endY: endY,
      confidence: confidence,
      confidenceReasons: reasons,
      startJunctionConfirmed: startConfirmed,
      endJunctionConfirmed: endConfirmed,
    );
  }
}
