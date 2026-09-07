// SPACE SHIFT — WO088-4 STRUCTURAL LINE PREPROCESSING (PHASE A) +
// DRAFTING COORDINATE POC (PHASE B).
//
// §2 핵심 원칙: 컬러 원본은 버리지 않는다(REFERENCE LAYER로 별도 보존).
// 이 파일은 그와 별도로 STRUCTURAL ANALYSIS LAYER만 만든다.
//
// WO088-3 root cause 재확인: 기존 luminance-only Otsu mask는 나무결
// 바닥 텍스처(따뜻한 갈색, chroma 100~120대)까지 "어두운 픽셀"로
// 포함시켜(luminance만으로는 벽 잉크 선과 구분 안 됨) global rotation
// estimator를 오도했다. 반면 실측(WO088-4 색상 샘플): 실제 벽 라인은
// rgb≈(2,2,1) 수준의 거의 완전한 무채색(chroma≈0~5)이고, 바닥 텍스처는
// chroma 100+ 수준의 뚜렷한 유채색이다 — "어둡다"만이 아니라 "무채색
// 으로 어둡다(dark AND low-chroma)"가 실제 벽 evidence를 훨씬 정확히
// 분리한다. 이 임계값은 Image 3 전용 상수가 아니라 luminance 채널과
// 동일하게 Otsu 방법으로 chroma 히스토그램에서 직접 계산한다(§6 반복
// 튜닝 금지 — 고정 매직넘버 대신 통계적으로 유도).
//
// 이 파일은 Flutter에 의존하지 않는다(package:image + dart:core만) —
// 진단 스크립트(dart run)와 Flutter POC 화면이 동일 코드를 공유한다.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

typedef Pt = ({double x, double y});

/// Otsu 방법 — floor_plan_analysis_engine.dart의 otsuThreshold()와 동일한
/// 표준 공식의 독립 재구현(이 모듈을 Flutter-free로 유지하기 위해 import
/// 대신 재구현 — production 코드를 호출/수정하지 않는다).
int otsuThreshold(List<int> histogram, int totalPixels) {
  if (totalPixels == 0) return 128;
  var sumAll = 0.0;
  for (var i = 0; i < histogram.length; i++) {
    sumAll += i * histogram[i];
  }
  var sumBackground = 0.0;
  var weightBackground = 0;
  var maxVariance = -1.0;
  var threshold = histogram.length ~/ 2;
  for (var t = 0; t < histogram.length; t++) {
    weightBackground += histogram[t];
    if (weightBackground == 0) continue;
    final weightForeground = totalPixels - weightBackground;
    if (weightForeground == 0) break;
    sumBackground += t * histogram[t];
    final meanBackground = sumBackground / weightBackground;
    final meanForeground = (sumAll - sumBackground) / weightForeground;
    final betweenVariance = weightBackground * weightForeground * (meanBackground - meanForeground) * (meanBackground - meanForeground);
    if (betweenVariance > maxVariance) {
      maxVariance = betweenVariance;
      threshold = t;
    }
  }
  return threshold;
}

class StructuralMaskResult {
  const StructuralMaskResult({
    required this.w,
    required this.h,
    required this.lumThreshold,
    required this.chromaThreshold,
    required this.grayscale,
    required this.chroma,
    required this.baselineMask,
    required this.structuralMask,
  });

  final int w;
  final int h;
  final int lumThreshold;
  final int chromaThreshold;

  /// 참고/시각화용 grayscale(luminance) 버퍼.
  final Uint8List grayscale;

  /// 참고/시각화용 chroma(max(r,g,b)-min(r,g,b)) 버퍼.
  final Uint8List chroma;

  /// A(baseline) — luminance만으로 어두운 픽셀(기존 production과 동일한
  /// 기준). 비교 대상으로만 쓰고 Phase B 입력으로는 쓰지 않는다.
  final Uint8List baselineMask;

  /// B(structural) — dark AND low-chroma(무채색으로 어두움)만 남긴 mask.
  final Uint8List structuralMask;
}

({int r, int g, int b}) _rgbOf(img.Pixel p) => (r: p.r.round(), g: p.g.round(), b: p.b.round());

/// [imageBytes]에서 A(baseline)/B(structural) 두 mask를 함께 만든다 —
/// production과 동일한 리사이즈 정책(최대 900px, 원본 비율 유지)을 써서
/// 두 결과가 서로 비교 가능하게 한다.
StructuralMaskResult buildStructuralMask(Uint8List imageBytes, {int maxAnalysisDim = 900}) {
  final decoded = img.decodeImage(imageBytes)!;
  final longest = math.max(decoded.width, decoded.height);
  final scale = longest > maxAnalysisDim ? maxAnalysisDim / longest : 1.0;
  final aw = math.max(1, (decoded.width * scale).round());
  final ah = math.max(1, (decoded.height * scale).round());
  final analysisImage = scale < 1.0 ? img.copyResize(decoded, width: aw, height: ah, interpolation: img.Interpolation.average) : decoded;
  final w = analysisImage.width, h = analysisImage.height;

  final lum = Uint8List(w * h);
  final chroma = Uint8List(w * h);
  final lumHist = List<int>.filled(256, 0);
  final chromaHist = List<int>.filled(256, 0);

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = analysisImage.getPixel(x, y);
      final rgb = _rgbOf(p);
      final l = p.luminance.round().clamp(0, 255);
      final maxc = math.max(rgb.r, math.max(rgb.g, rgb.b));
      final minc = math.min(rgb.r, math.min(rgb.g, rgb.b));
      final c = (maxc - minc).clamp(0, 255);
      lum[y * w + x] = l;
      chroma[y * w + x] = c;
      lumHist[l]++;
      chromaHist[c]++;
    }
  }

  final lumThreshold = otsuThreshold(lumHist, w * h);
  final chromaThreshold = otsuThreshold(chromaHist, w * h);

  final baselineMask = Uint8List(w * h);
  final structuralMask = Uint8List(w * h);
  for (var i = 0; i < w * h; i++) {
    final dark = lum[i] <= lumThreshold;
    baselineMask[i] = dark ? 1 : 0;
    structuralMask[i] = (dark && chroma[i] <= chromaThreshold) ? 1 : 0;
  }

  return StructuralMaskResult(
    w: w,
    h: h,
    lumThreshold: lumThreshold,
    chromaThreshold: chromaThreshold,
    grayscale: lum,
    chroma: chroma,
    baselineMask: baselineMask,
    structuralMask: structuralMask,
  );
}

/// §10/§20.E 진단용 — [mask] 위 지정 sub-region(cropped)의 지배적 각도를
/// 독립적으로 추정한다(WO088-3의 projection-variance 방법을 재사용하되,
/// 이번에는 이미지 전체가 아니라 "이 sub-region 하나만"에 국소적으로
/// 적용한다 — 전역 단일 회전각 가정이 실패였다는 WO088-3 root cause에
/// 대한 직접적 대응). 회전 없이도 이미 축이 맞으면(zeroScore가 이미
/// 최고) 0을 반환한다.
double estimateLocalDominantAngle(
  Uint8List mask,
  int w,
  int h, {
  required int x0,
  required int y0,
  required int x1,
  required int y1,
  double searchFrom = -45,
  double searchTo = 45,
  double coarseStep = 1,
}) {
  final cw = x1 - x0, ch = y1 - y0;
  if (cw <= 0 || ch <= 0) return 0;
  final crop = Uint8List(cw * ch);
  for (var y = 0; y < ch; y++) {
    for (var x = 0; x < cw; x++) {
      crop[y * cw + x] = mask[(y + y0) * w + (x + x0)];
    }
  }

  double scoreAt(double angleDeg) {
    final rotated = angleDeg == 0 ? crop : _resampleRotated(crop, cw, ch, angleDeg * math.pi / 180);
    final rowSums = List<int>.filled(ch, 0);
    final colSums = List<int>.filled(cw, 0);
    for (var y = 0; y < ch; y++) {
      for (var x = 0; x < cw; x++) {
        if (rotated[y * cw + x] == 1) {
          rowSums[y]++;
          colSums[x]++;
        }
      }
    }
    return _variance(rowSums) + _variance(colSums);
  }

  final zeroScore = scoreAt(0);
  var bestAngle = 0.0, bestScore = zeroScore;
  var angle = searchFrom;
  while (angle <= searchTo + 1e-9) {
    if (angle != 0) {
      final s = scoreAt(angle);
      if (s > bestScore) {
        bestScore = s;
        bestAngle = angle;
      }
    }
    angle += coarseStep;
  }
  if (bestScore < zeroScore * 1.08) return 0;
  return bestAngle;
}

double _variance(List<int> values) {
  if (values.isEmpty) return 0;
  var sum = 0.0;
  for (final v in values) {
    sum += v;
  }
  final mean = sum / values.length;
  var sq = 0.0;
  for (final v in values) {
    sq += (v - mean) * (v - mean);
  }
  return sq / values.length;
}

Pt _rotateAround(double x, double y, double cx, double cy, double angleRad) {
  final dx = x - cx, dy = y - cy;
  final cosA = math.cos(angleRad), sinA = math.sin(angleRad);
  return (x: cx + dx * cosA - dy * sinA, y: cy + dx * sinA + dy * cosA);
}

int _bilinear(Uint8List mask, int w, int h, double x, double y) {
  final x0 = x.floor(), y0 = y.floor();
  final fx = x - x0, fy = y - y0;
  int at(int xi, int yi) => (xi < 0 || yi < 0 || xi >= w || yi >= h) ? 0 : mask[yi * w + xi];
  final v00 = at(x0, y0), v10 = at(x0 + 1, y0), v01 = at(x0, y0 + 1), v11 = at(x0 + 1, y0 + 1);
  final top = v00 * (1 - fx) + v10 * fx;
  final bottom = v01 * (1 - fx) + v11 * fx;
  return (top * (1 - fy) + bottom * fy) >= 0.5 ? 1 : 0;
}

Uint8List _resampleRotated(Uint8List source, int w, int h, double angleRad) {
  final dest = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final src = _rotateAround(x.toDouble(), y.toDouble(), w / 2, h / 2, angleRad);
      dest[y * w + x] = _bilinear(source, w, h, src.x, src.y);
    }
  }
  return dest;
}

enum LineOrientation { horizontal, vertical }

/// §12 — 아직 orthogonal/diagonal 분류를 매기지 않은 원시 구조선 candidate.
/// 좌표는 항상 "원본 분석 캔버스(회전 없음)" 기준 px다 — 지역적으로
/// deskew된 sub-region에서 나온 candidate도 이 좌표계로 되돌려 반환한다.
class RawStructuralLine {
  const RawStructuralLine({
    required this.id,
    required this.start,
    required this.end,
    required this.thicknessPx,
    required this.method,
  });

  final String id;
  final Pt start;
  final Pt end;
  final double thicknessPx;

  /// `axisAligned` 또는 `localDeskew:ANGLE` 형태의 문자열.
  final String method;
}

/// 회전 없이(원본 방향 그대로) 수평/수직 run-length + 인접 band 병합으로
/// 구조선을 뽑는다 — production의 정교한 gap 분류/신뢰도 로직을 재사용하지
/// 않는 독립적인 단순 버전(POC 목적에 충분하다).
List<RawStructuralLine> extractAxisAlignedLines(
  Uint8List mask,
  int w,
  int h, {
  required double minRunPx,
  required double maxThicknessPx,
  String idPrefix = 'axis',
}) {
  final lines = <RawStructuralLine>[];
  var counter = 0;

  // 수평 — 행 단위 run 수집 후 인접 행 병합.
  final hRuns = <(int y, int xStart, int xEnd)>[];
  for (var y = 0; y < h; y++) {
    var runStart = -1;
    for (var x = 0; x <= w; x++) {
      final v = x < w ? mask[y * w + x] : 0;
      if (v == 1) {
        runStart = runStart == -1 ? x : runStart;
      } else if (runStart != -1) {
        if (x - runStart >= minRunPx) hRuns.add((y, runStart, x - 1));
        runStart = -1;
      }
    }
  }
  lines.addAll(_mergeRunsToBands(hRuns, horizontal: true, maxThicknessPx: maxThicknessPx, idPrefix: '$idPrefix-h', counterStart: counter));
  counter += lines.length;

  // 수직 — 열 단위 run 수집 후 인접 열 병합.
  final vRuns = <(int x, int yStart, int yEnd)>[];
  for (var x = 0; x < w; x++) {
    var runStart = -1;
    for (var y = 0; y <= h; y++) {
      final v = y < h ? mask[y * w + x] : 0;
      if (v == 1) {
        runStart = runStart == -1 ? y : runStart;
      } else if (runStart != -1) {
        if (y - runStart >= minRunPx) vRuns.add((x, runStart, y - 1));
        runStart = -1;
      }
    }
  }
  lines.addAll(_mergeRunsToBands(vRuns, horizontal: false, maxThicknessPx: maxThicknessPx, idPrefix: '$idPrefix-v', counterStart: counter));

  return lines;
}

/// (along, crossStart, crossEnd) 형태 run 목록을, "인접한 cross 위치이면서
/// along 범위가 충분히 겹치는" 것끼리 병합해 하나의 band(벽)로 만든다.
List<RawStructuralLine> _mergeRunsToBands(
  List<(int cross, int alongStart, int alongEnd)> runs,
  {required bool horizontal, required double maxThicknessPx, required String idPrefix, required int counterStart}
) {
  if (runs.isEmpty) return const [];
  final sorted = [...runs]..sort((a, b) => a.$1.compareTo(b.$1));

  final active = <_Band>[];
  final finished = <_Band>[];
  var lastCross = sorted.first.$1;

  for (final r in sorted) {
    final (cross, aStart, aEnd) = r;
    if (cross != lastCross) {
      // cross 위치가 바뀔 때, 이번 cross 값에 이어지지 못한 band는 종료.
      for (final b in [...active]) {
        if (cross - b.crossMax > 1) {
          finished.add(b);
          active.remove(b);
        }
      }
      lastCross = cross;
    }
    _Band? target;
    for (final b in active) {
      if (b.crossMax == cross - 1 || b.crossMax == cross) {
        final overlap = math.min(aEnd, b.alongMax) - math.max(aStart, b.alongMin);
        final shorter = math.min(aEnd - aStart, b.alongMax - b.alongMin);
        if (overlap >= 0 && shorter >= 0 && overlap >= shorter * 0.5) {
          target = b;
          break;
        }
      }
    }
    if (target == null) {
      active.add(_Band(crossMin: cross, crossMax: cross, alongMin: aStart, alongMax: aEnd));
    } else {
      target.crossMax = math.max(target.crossMax, cross);
      target.alongMin = math.min(target.alongMin, aStart);
      target.alongMax = math.max(target.alongMax, aEnd);
    }
  }
  finished.addAll(active);

  final out = <RawStructuralLine>[];
  var counter = counterStart;
  for (final b in finished) {
    final thickness = (b.crossMax - b.crossMin + 1).toDouble();
    if (thickness > maxThicknessPx) continue;
    final crossCenter = (b.crossMin + b.crossMax) / 2;
    final id = '$idPrefix-${counter++}';
    if (horizontal) {
      out.add(RawStructuralLine(
        id: id,
        start: (x: b.alongMin.toDouble(), y: crossCenter),
        end: (x: b.alongMax.toDouble(), y: crossCenter),
        thicknessPx: thickness,
        method: 'axisAligned',
      ));
    } else {
      out.add(RawStructuralLine(
        id: id,
        start: (x: crossCenter, y: b.alongMin.toDouble()),
        end: (x: crossCenter, y: b.alongMax.toDouble()),
        thicknessPx: thickness,
        method: 'axisAligned',
      ));
    }
  }
  return out;
}

class _Band {
  _Band({required this.crossMin, required this.crossMax, required this.alongMin, required this.alongMax});
  int crossMin, crossMax, alongMin, alongMax;
}

/// §14 HYBRID — sub-region([x0,y0,x1,y1])을 로컬 각도로 deskew한 뒤
/// 축정렬 스캔을 적용하고, 결과 좌표를 원본(회전 없음) 캔버스 좌표로
/// 되돌려 반환한다. 전역 회전을 이미지 전체에 적용하지 않는다(§13) —
/// 이 sub-region 안에서만 국소적으로 적용한다.
List<RawStructuralLine> extractLocalDeskewedLines(
  Uint8List mask,
  int w,
  int h, {
  required int x0,
  required int y0,
  required int x1,
  required int y1,
  required double minRunPx,
  required double maxThicknessPx,
  String idPrefix = 'wing',
}) {
  final angle = estimateLocalDominantAngle(mask, w, h, x0: x0, y0: y0, x1: x1, y1: y1);
  final cw = x1 - x0, ch = y1 - y0;
  final crop = Uint8List(cw * ch);
  for (var y = 0; y < ch; y++) {
    for (var x = 0; x < cw; x++) {
      crop[y * cw + x] = mask[(y + y0) * w + (x + x0)];
    }
  }
  if (angle == 0) {
    // 이미 축이 맞음 — 그냥 axis-aligned 스캔만 하되 좌표를 offset.
    final local = extractAxisAlignedLines(crop, cw, ch, minRunPx: minRunPx, maxThicknessPx: maxThicknessPx, idPrefix: idPrefix);
    return [
      for (final l in local)
        RawStructuralLine(
          id: l.id,
          start: (x: l.start.x + x0, y: l.start.y + y0),
          end: (x: l.end.x + x0, y: l.end.y + y0),
          thicknessPx: l.thicknessPx,
          method: 'axisAligned',
        ),
    ];
  }

  final angleRad = angle * math.pi / 180;
  final rotatedCrop = _resampleRotated(crop, cw, ch, angleRad);
  final local = extractAxisAlignedLines(rotatedCrop, cw, ch, minRunPx: minRunPx, maxThicknessPx: maxThicknessPx, idPrefix: idPrefix);

  Pt undo(Pt p) {
    // 로컬 crop 중심 기준으로 회전한 것을 되돌린 뒤, crop offset을 더해
    // 원본(회전 없음) 좌표로 되돌린다.
    final back = _rotateAround(p.x, p.y, cw / 2, ch / 2, -angleRad);
    return (x: back.x + x0, y: back.y + y0);
  }

  return [
    for (final l in local)
      RawStructuralLine(id: l.id, start: undo(l.start), end: undo(l.end), thicknessPx: l.thicknessPx, method: 'localDeskew:${angle.toStringAsFixed(1)}'),
  ];
}
