// SPACE SHIFT — WO088-7 WALL CENTERLINE POC.
//
// §16 — 이 파일은 drafting_v1(WO088-4~6)과 독립적으로 구현한다. 유일한
// 재사용은 [buildStructuralMask](drafting_v1/structural_layer.dart,
// 수정하지 않고 그대로 import)의 dark+low-chroma pixel evidence layer뿐
// 이다 — 이미 WO088-4/5에서 검증된 "색상 자체를 벽으로 판단하지 않는다"
// 원칙의 재사용이지, 이번 WO가 비교하려는 "기존 방식"(WO088-6의 mm/
// snap/평균-junction 방식)이 아니다. Boundary pairing/Centerline/
// Junction 로직은 전부 새로 작성했고 drafting_v1의 어떤 함수도 호출하지
// 않는다.
//
// 핵심 차이(§8): WO088-6은 endpoint를 5mm grid로 스냅한 뒤 근접
// 평균으로 junction 좌표를 만들었다(그 결과 축정렬 벽이 미세하게
// 기우는 버그가 실측으로 발견됨, WO088-6 보고서 참고). 이번 POC는
// grid snap을 전혀 쓰지 않고, centerline geometry(수평선의 y, 수직선의
// x)를 먼저 확정한 뒤, 그 "두 직선의 교점"을 junction 좌표로 직접
// 계산한다 — 평균이 아니라 기하학적 교점이 evidence다.

import 'dart:typed_data';

import 'dart:math' as math;

typedef Pt = ({double x, double y});

enum LineKind { solid, dashed }

/// §4 — run-length band 하나(축정렬, 방향/위치/along-span/coverage 포함).
/// coverage가 낮으면(구멍이 많으면) dashed로 분류된다 — 삭제하지 않고
/// [LineKind.dashed]로 보존한다.
class RawRunBand {
  const RawRunBand({
    required this.id,
    required this.horizontal,
    required this.crossPx,
    required this.alongMinPx,
    required this.alongMaxPx,
    required this.coverageRatio,
    required this.kind,
  });

  final String id;
  final bool horizontal;

  /// 수평이면 y, 수직이면 x(축에 수직인 고정 좌표).
  final double crossPx;
  final double alongMinPx;
  final double alongMaxPx;

  /// [alongMinPx,alongMaxPx] 구간 중 실제로 어두운 픽셀이 있는 위치의 비율.
  final double coverageRatio;
  final LineKind kind;

  double get lengthPx => alongMaxPx - alongMinPx;

  Pt get start => horizontal ? (x: alongMinPx, y: crossPx) : (x: crossPx, y: alongMinPx);
  Pt get end => horizontal ? (x: alongMaxPx, y: crossPx) : (x: crossPx, y: alongMaxPx);
}

/// §5 — 평행한 두 solid boundary를 하나의 벽으로 묶은 것. 짝을 못 찾은
/// 경우(§5 단일 경계 fallback)는 [boundaryBId]가 null이고 [singleBoundary]가
/// true다 — 이 경우 그 경계선 자체를 centerline으로 쓰되 reviewNeeded로
/// 표시한다(§9 "확신할 수 없으면 reviewNeeded").
class WallBoundaryPair {
  const WallBoundaryPair({
    required this.id,
    required this.horizontal,
    required this.boundaryAId,
    required this.boundaryACrossPx,
    this.boundaryBId,
    this.boundaryBCrossPx,
    required this.alongMinPx,
    required this.alongMaxPx,
    required this.singleBoundary,
  });

  final String id;
  final bool horizontal;
  final String boundaryAId;
  final double boundaryACrossPx;
  final String? boundaryBId;
  final double? boundaryBCrossPx;
  final double alongMinPx;
  final double alongMaxPx;
  final bool singleBoundary;

  double get centerCrossPx => singleBoundary ? boundaryACrossPx : (boundaryACrossPx + boundaryBCrossPx!) / 2;
  double? get spacingPx => singleBoundary ? null : (boundaryBCrossPx! - boundaryACrossPx).abs();
}

class Centerline {
  const Centerline({
    required this.id,
    required this.start,
    required this.end,
    required this.horizontal,
    required this.sourceBoundaryIds,
    required this.confidence,
    required this.reviewNeeded,
    required this.evidence,
    this.boundarySpacingPx,
    this.aToCenterPx,
    this.centerToBPx,
  });

  final String id;
  final Pt start;
  final Pt end;
  final bool horizontal;
  final List<String> sourceBoundaryIds;
  final double confidence;
  final bool reviewNeeded;
  final String evidence;

  // §12 정확도 측정용(px 기준, mm 아님).
  final double? boundarySpacingPx;
  final double? aToCenterPx;
  final double? centerToBPx;

  double get crossPx => horizontal ? start.y : start.x;
  double get alongMinPx => horizontal ? math.min(start.x, end.x) : math.min(start.y, end.y);
  double get alongMaxPx => horizontal ? math.max(start.x, end.x) : math.max(start.y, end.y);
}

// ---------------------------------------------------------------------
// §3/§4 — raw run-length scan + coverage 기반 solid/dashed 분류.
// ---------------------------------------------------------------------

const double _maxAntiAliasBridgePx = 3.0; // 일반적인 anti-alias 끊김 보정(고정, Image 4 전용 아님).

/// §4 dashed 패턴 인식용 — 실제 파선/점선의 개별 획 사이 gap은 anti-alias
/// 보정(3px)보다 훨씬 크다(수 px~십수 px). 이 gap을 못 넘기면 파선의
/// 각 짧은 획이 서로 합쳐지지 못해 [_minMeaningfulLengthPx] 미달로 전부
/// 조용히 버려진다(실측: WO088-7 최초 구현에서 파선 인식이 전혀 안 되던
/// 원인). solid 판정에는 여전히 3px만 쓴다 — 이 값은 "이 구간에 반복
/// 패턴이 있는지"를 보기 위한 별도의 느슨한 pass에서만 쓰인다.
const double _maxDashGapBridgePx = 20.0;
const double _solidCoverageThreshold = 0.85;
const double _dashedCoverageFloor = 0.2;

/// §4 최소 "의미 있는 벽 evidence" 길이 — Image 4 실측(길이 히스토그램)에서
/// 짧은 반복 눈금(10~30px 구간에 91개 집중)과 실제 벽(30px 이상, 훨씬
/// 성긴 분포)이 뚜렷이 갈라지는 지점을 근거로 도출했다. 고정 픽셀
/// 수치가 아니라 기존 structural_layer.dart의 minRunPx 관례(이미지
/// 대각선에 비례)와 같은 방식으로 만들어, 다른 해상도 이미지에도
/// 일반적으로 적용된다.
double defaultMinMeaningfulLengthPx(int w, int h) => math.max(10.0, math.sqrt(w * w + h * h) * 0.05);

List<RawRunBand> _scanAxis(Uint8List mask, int w, int h, {required bool horizontal, required double minMeaningfulLengthPx, required double bridgeGapPx}) {
  final outerLen = horizontal ? h : w;
  final innerLen = horizontal ? w : h;
  int at(int outer, int inner) => horizontal ? mask[outer * w + inner] : mask[inner * w + outer];

  // 1) 각 outer(행 또는 열)에서 anti-alias bridge를 적용한 "느슨한 run" 목록.
  final looseRuns = <(int outer, int start, int end)>[]; // end는 exclusive.
  for (var o = 0; o < outerLen; o++) {
    var runStart = -1;
    var gapStart = -1;
    for (var i = 0; i <= innerLen; i++) {
      final v = i < innerLen ? at(o, i) : 0;
      if (v == 1) {
        if (runStart == -1) runStart = i;
        gapStart = -1;
      } else {
        if (runStart != -1) {
          if (gapStart == -1) gapStart = i;
          if (i - gapStart > bridgeGapPx) {
            looseRuns.add((o, runStart, gapStart));
            runStart = -1;
            gapStart = -1;
          }
        }
      }
    }
    if (runStart != -1) looseRuns.add((o, runStart, innerLen));
  }

  // 2) outer(행/열) 인접 + inner 범위 overlap 기준으로 band 병합(구조는
  // structural_layer.dart의 밴드 병합과 유사하지만 완전히 별도 구현).
  final sorted = [...looseRuns]..sort((a, b) => a.$1.compareTo(b.$1));
  final active = <_BandAcc>[];
  final finished = <_BandAcc>[];
  var lastOuter = sorted.isEmpty ? 0 : sorted.first.$1;
  for (final r in sorted) {
    final (outer, start, end) = r;
    if (outer != lastOuter) {
      for (final b in [...active]) {
        if (outer - b.outerMax > 1) {
          finished.add(b);
          active.remove(b);
        }
      }
      lastOuter = outer;
    }
    _BandAcc? target;
    for (final b in active) {
      if (b.outerMax != outer - 1 && b.outerMax != outer) continue;
      // 두께 상한 — 이 값이 없으면 서로 다른 벽이 근접한 행/열에서
      // 우연히 overlap 조건을 만족할 때 계속 체인처럼 합쳐져 하나의
      // 거대한 저-coverage 덩어리가 되고, 그 결과 전체가 노이즈로
      // 오분류(폐기)된다 — WO088-7에서 Image 4로 실측 확인된 실패
      // 원인. structural_layer.dart(WO088-4)가 이미 쓰는 것과 동일한
      // 일반 상수를 그대로 재사용한다(Image 4 전용 튜닝이 아니다).
      if (b.outerMax - b.outerMin + 1 >= _maxWallThicknessPx) continue;
      final overlap = math.min(end, b.innerMax) - math.max(start, b.innerMin);
      final shorter = math.min(end - start, b.innerMax - b.innerMin);
      if (overlap > 0 && shorter > 0 && overlap >= shorter * 0.5) {
        target = b;
        break;
      }
    }
    if (target == null) {
      active.add(_BandAcc(outerMin: outer, outerMax: outer, innerMin: start, innerMax: end));
    } else {
      target.outerMax = math.max(target.outerMax, outer);
      target.innerMin = math.min(target.innerMin, start);
      target.innerMax = math.max(target.innerMax, end);
    }
  }
  finished.addAll(active);

  // 3) 각 band의 coverage(실제 어두운 픽셀이 있는 along-position 비율) 계산.
  final out = <RawRunBand>[];
  var counter = 0;
  for (final b in finished) {
    final alongLen = b.innerMax - b.innerMin;
    if (alongLen < 2) continue;
    var coveredCount = 0;
    for (var i = b.innerMin; i < b.innerMax; i++) {
      var covered = false;
      for (var o = b.outerMin; o <= b.outerMax; o++) {
        if (at(o, i) == 1) {
          covered = true;
          break;
        }
      }
      if (covered) coveredCount++;
    }
    final coverage = coveredCount / alongLen;
    final crossPx = (b.outerMin + b.outerMax) / 2.0;
    LineKind? kind;
    // §4/§5 — 짧은 반복 눈금(예: 도면 테두리의 격자/자 눈금 장식)이
    // coverage만으로는 진짜 벽과 구분되지 않는다(둘 다 자기 자신의
    // 짧은 구간 안에서는 거의 항상 연속적이다) — Image 4 실측에서
    // 확인됨. 벽은 "충분히 길다"는 일반 건축적 가정을 solid 판정에도
    // 적용한다(기존에는 dashed에만 적용하고 있었다 — 이 누락이 원인).
    if (alongLen < minMeaningfulLengthPx) {
      kind = null;
    } else if (coverage >= _solidCoverageThreshold) {
      kind = LineKind.solid;
    } else if (coverage >= _dashedCoverageFloor) {
      kind = LineKind.dashed;
    }
    if (kind == null) continue; // 너무 짧거나 너무 sparse — 의미 있는 evidence 아님(노이즈).
    out.add(
      RawRunBand(
        id: '${horizontal ? "h" : "v"}-${counter++}',
        horizontal: horizontal,
        crossPx: crossPx,
        alongMinPx: b.innerMin.toDouble(),
        alongMaxPx: b.innerMax.toDouble(),
        coverageRatio: coverage,
        kind: kind,
      ),
    );
  }
  return out;
}

class _BandAcc {
  _BandAcc({required this.outerMin, required this.outerMax, required this.innerMin, required this.innerMax});
  int outerMin, outerMax, innerMin, innerMax;
}

class LineEvidenceResult {
  const LineEvidenceResult({required this.solidBands, required this.dashedBands, required this.patternBands});
  final List<RawRunBand> solidBands;
  final List<RawRunBand> dashedBands;

  /// §3 — 타일/그리드 바닥 texture(예: 발코니 타일 그라우트 선) 등
  /// 반복적으로 촘촘히 나열된 평행선. 벽이 아니라고 확정하지만
  /// 삭제하지 않고 별도로 보존한다(다용도 evidence로 남길 수 있음).
  final List<RawRunBand> patternBands;
}

/// §3 — WO088-5(Image 3 바닥 texture)와 같은 계열의 문제를 Image 4(타일
/// 격자 패턴)에서도 확인함: 촘촘하고 규칙적으로 반복되는 평행선은
/// coverage/길이만으로는 진짜 벽과 구분되지 않는다. "국소적으로 같은
/// 방향의 다른 solid band가 비정상적으로 많이 몰려 있다"를 evidence로
/// 써서 분리한다 — WO088-5/6의 repeatedPatternCluster와 같은 원칙(그
/// 코드를 직접 재사용하지는 않는다, 타입이 다르고 §16 독립 구현 원칙).
List<RawRunBand> _splitPatternNoise(List<RawRunBand> bands, List<RawRunBand> outPattern, {int minClusterSize = 5, double clusterCrossRangePx = 30}) {
  final kept = <RawRunBand>[];
  final byOrientation = <bool, List<RawRunBand>>{true: [], false: []};
  for (final b in bands) {
    byOrientation[b.horizontal]!.add(b);
  }
  for (final horizontal in [true, false]) {
    final group = byOrientation[horizontal]!;
    for (final b in group) {
      final neighbors = group.where((o) {
        if (identical(o, b)) return false;
        if ((o.crossPx - b.crossPx).abs() > clusterCrossRangePx) return false;
        final overlap = math.min(o.alongMaxPx, b.alongMaxPx) - math.max(o.alongMinPx, b.alongMinPx);
        return overlap > 0;
      }).length;
      if (neighbors + 1 >= minClusterSize) {
        outPattern.add(b);
      } else {
        kept.add(b);
      }
    }
  }
  return kept;
}

/// §3/§4 진입점 — [mask](buildStructuralMask 결과)에서 수평/수직 solid·
/// dashed band를 모두 뽑고, 반복 패턴(타일/격자) 노이즈를 분리한다.
/// [minMeaningfulLengthPx]를 넘기지 않으면 [defaultMinMeaningfulLengthPx]
/// (이미지 대각선 비례)를 쓴다.
LineEvidenceResult extractLineEvidence(Uint8List mask, int w, int h, {double? minMeaningfulLengthPx}) {
  final minLen = minMeaningfulLengthPx ?? defaultMinMeaningfulLengthPx(w, h);
  // fine pass(3px bridge) — solid line 연속성 판정용, 기존 그대로.
  final fine = [
    ..._scanAxis(mask, w, h, horizontal: true, minMeaningfulLengthPx: minLen, bridgeGapPx: _maxAntiAliasBridgePx),
    ..._scanAxis(mask, w, h, horizontal: false, minMeaningfulLengthPx: minLen, bridgeGapPx: _maxAntiAliasBridgePx),
  ];
  // coarse pass(20px bridge) — 파선의 개별 획들을 하나의 평가 단위로
  // 묶어야만 "규칙적으로 끊긴 긴 선"인지 판단할 수 있다.
  final coarse = [
    ..._scanAxis(mask, w, h, horizontal: true, minMeaningfulLengthPx: minLen, bridgeGapPx: _maxDashGapBridgePx),
    ..._scanAxis(mask, w, h, horizontal: false, minMeaningfulLengthPx: minLen, bridgeGapPx: _maxDashGapBridgePx),
  ];
  final rawSolid = fine.where((b) => b.kind == LineKind.solid).toList();
  final patternBands = <RawRunBand>[];
  final solidBands = _splitPatternNoise(rawSolid, patternBands);
  return LineEvidenceResult(
    solidBands: solidBands,
    dashedBands: coarse.where((b) => b.kind == LineKind.dashed).toList(),
    patternBands: patternBands,
  );
}

// ---------------------------------------------------------------------
// §5/§6 — solid band를 평행 pair로 묶어 centerline을 만든다.
// ---------------------------------------------------------------------

const double _minWallThicknessPx = 2.0;
const double _maxWallThicknessPx = 30.0;
const double _minAlongOverlapFraction = 0.5;

/// [solidBands]에서 같은 방향(수평/수직)이고, cross 간격이 벽 두께로
/// 그럴듯한 범위([_minWallThicknessPx].._maxWallThicknessPx])이며, along
/// 범위가 충분히 겹치는(§ [_minAlongOverlapFraction]) 두 band를 짝지어
/// [WallBoundaryPair]로 만든다. 짝을 못 찾은 band는 §5 fallback으로
/// 단일 경계 그대로 pair(singleBoundary=true)가 된다.
List<WallBoundaryPair> pairWallBoundaries(List<RawRunBand> solidBands) {
  final pairs = <WallBoundaryPair>[];
  final used = List<bool>.filled(solidBands.length, false);
  var counter = 0;

  for (var i = 0; i < solidBands.length; i++) {
    if (used[i]) continue;
    final a = solidBands[i];
    RawRunBand? bestPartner;
    var bestPartnerIdx = -1;
    var bestScore = double.infinity;
    for (var j = i + 1; j < solidBands.length; j++) {
      if (used[j]) continue;
      final b = solidBands[j];
      if (b.horizontal != a.horizontal) continue;
      final spacing = (b.crossPx - a.crossPx).abs();
      if (spacing < _minWallThicknessPx || spacing > _maxWallThicknessPx) continue;
      final overlap = math.min(a.alongMaxPx, b.alongMaxPx) - math.max(a.alongMinPx, b.alongMinPx);
      final shorterLen = math.min(a.lengthPx, b.lengthPx);
      if (shorterLen <= 0 || overlap / shorterLen < _minAlongOverlapFraction) continue;
      // 가장 spacing이 작은(가장 그럴듯한 벽 두께) 후보를 우선한다.
      if (spacing < bestScore) {
        bestScore = spacing;
        bestPartner = b;
        bestPartnerIdx = j;
      }
    }
    if (bestPartner != null) {
      used[i] = true;
      used[bestPartnerIdx] = true;
      final along0 = math.max(a.alongMinPx, bestPartner.alongMinPx);
      final along1 = math.min(a.alongMaxPx, bestPartner.alongMaxPx);
      pairs.add(
        WallBoundaryPair(
          id: 'pair-${counter++}',
          horizontal: a.horizontal,
          boundaryAId: a.id,
          boundaryACrossPx: a.crossPx,
          boundaryBId: bestPartner.id,
          boundaryBCrossPx: bestPartner.crossPx,
          alongMinPx: along0,
          alongMaxPx: along1,
          singleBoundary: false,
        ),
      );
    } else {
      used[i] = true;
      pairs.add(
        WallBoundaryPair(
          id: 'pair-${counter++}',
          horizontal: a.horizontal,
          boundaryAId: a.id,
          boundaryACrossPx: a.crossPx,
          alongMinPx: a.alongMinPx,
          alongMaxPx: a.alongMaxPx,
          singleBoundary: true,
        ),
      );
    }
  }
  return pairs;
}

/// §6/§7 — [WallBoundaryPair]마다 centerline을 만든다. 두 경계 사이
/// 정중앙(cross 방향 평균)에서, along 방향은 원본 pixel run 그대로다
/// (0/90 방향 자체는 이미 축정렬 스캔에서 나온 것이라 회전/미세 기울임이
/// 생기지 않는다 — §7).
List<Centerline> buildCenterlines(List<WallBoundaryPair> pairs) {
  final lines = <Centerline>[];
  var counter = 0;
  for (final p in pairs) {
    final center = p.centerCrossPx;
    final start = p.horizontal ? (x: p.alongMinPx, y: center) : (x: center, y: p.alongMinPx);
    final end = p.horizontal ? (x: p.alongMaxPx, y: center) : (x: center, y: p.alongMaxPx);
    final sourceIds = [p.boundaryAId, if (p.boundaryBId != null) p.boundaryBId!];
    lines.add(
      Centerline(
        id: 'centerline-${counter++}',
        start: start,
        end: end,
        horizontal: p.horizontal,
        sourceBoundaryIds: sourceIds,
        confidence: p.singleBoundary ? 0.5 : 0.9,
        reviewNeeded: p.singleBoundary,
        evidence: p.singleBoundary
            ? 'single solid boundary — 짝이 되는 평행선을 찾지 못해 그 경계선 자체를 centerline으로 사용(review 필요)'
            : 'paired solid boundaries(spacing=${p.spacingPx!.toStringAsFixed(1)}px)',
        boundarySpacingPx: p.spacingPx,
        aToCenterPx: p.singleBoundary ? null : (center - p.boundaryACrossPx).abs(),
        centerToBPx: p.singleBoundary ? null : (center - p.boundaryBCrossPx!).abs(),
      ),
    );
  }
  return lines;
}
