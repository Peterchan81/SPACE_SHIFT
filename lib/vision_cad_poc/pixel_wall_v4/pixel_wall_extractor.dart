// SPACE SHIFT — Vision-Guided Full Pixel Wall Extraction POC.
//
// [extractPixelWalls]는 이번 라운드의 핵심 재사용 결정이다: GPT가 만든
// wall/corner 그래프(v1~v3에서 반복 실패)를 다시 시도하는 대신, 이미
// 검증되어 있는 전체 이미지 detectWallsAndOpenings()의 출력을 후보
// pool로 삼아 multi-factor(junction 지지 + 길이 + 원본 confidence)
// 분류만 새로 얹는다. run-length 스캔은 축 정렬 벽만 만들 수 있으므로
// "가짜 대각선"은 애초에 생성 구조상 나올 수 없다.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../models/floor_plan_geometry.dart';
import '../../services/floor_plan_analysis_engine.dart';
import 'pixel_wall_types.dart';
import 'wall_system.dart';

class PixelWallExtractionResult {
  const PixelWallExtractionResult.failure(this.failureReason)
    : sourceWidthPx = 0,
      sourceHeightPx = 0,
      analysisWidthPx = 0,
      analysisHeightPx = 0,
      mask = null,
      candidates = const [],
      rejected = const [],
      openings = const [],
      rooms = const [],
      rotationDegrees = 0,
      rawWallSegmentCount = 0,
      weakRecoveredCount = 0;

  const PixelWallExtractionResult.success({
    required this.sourceWidthPx,
    required this.sourceHeightPx,
    required this.analysisWidthPx,
    required this.analysisHeightPx,
    required this.mask,
    required this.candidates,
    required this.rejected,
    required this.openings,
    required this.rooms,
    required this.rotationDegrees,
    required this.rawWallSegmentCount,
    this.weakRecoveredCount = 0,
  }) : failureReason = null;

  final FloorPlanAnalysisFailureReason? failureReason;
  final int sourceWidthPx;
  final int sourceHeightPx;
  final int analysisWidthPx;
  final int analysisHeightPx;
  final Uint8List? mask;
  final List<PixelWallCandidate> candidates;
  final List<PixelWallRejection> rejected;
  final List<OpeningCandidate> openings;
  final List<RoomCandidate> rooms;
  final double rotationDegrees;

  /// 분류 이전, detectWallsAndOpenings가 만든 원본 WallSegment 개수
  /// (weak-recovery 보강분 제외).
  final int rawWallSegmentCount;

  /// 1차 run-length(minRunLen 표준값) 스캔이 놓친, 얇거나/anti-alias로
  /// 끊긴 벽을 낮은 minRunLen + 1px 간격 보정(gap-close)으로 2차
  /// 복구한 개수 — §6에서 허용한 morphology 보조 기법.
  final int weakRecoveredCount;

  bool get isSuccess => failureReason == null;

  int get structuralCount =>
      candidates.where((c) => c.category == PixelWallCategory.structural).length;
  int get reviewNeededCount =>
      candidates.where((c) => c.category == PixelWallCategory.reviewNeeded).length;
  int get highCount =>
      candidates.where((c) => c.confidenceTier == PixelWallConfidenceTier.high).length;
  int get mediumCount =>
      candidates.where((c) => c.confidenceTier == PixelWallConfidenceTier.medium).length;
  int get lowCount =>
      candidates.where((c) => c.confidenceTier == PixelWallConfidenceTier.low).length;

  /// noise 재분류(pixel_wall_classifier.dart) 이후의 candidate 목록으로
  /// 교체한 사본을 만든다 — 다른 필드는 그대로 유지.
  PixelWallExtractionResult copyWithCandidates(List<PixelWallCandidate> newCandidates) {
    if (!isSuccess) return this;
    return PixelWallExtractionResult.success(
      sourceWidthPx: sourceWidthPx,
      sourceHeightPx: sourceHeightPx,
      analysisWidthPx: analysisWidthPx,
      analysisHeightPx: analysisHeightPx,
      mask: mask,
      candidates: newCandidates,
      rejected: rejected,
      openings: openings,
      rooms: rooms,
      rotationDegrees: rotationDegrees,
      rawWallSegmentCount: rawWallSegmentCount,
      weakRecoveredCount: weakRecoveredCount,
    );
  }
}

/// 병합 후보로 볼 두 콜리니어 band 사이 최대 gap(px) — 실제 문/창 gap
/// 범위(_detectOpenings의 minGapPx ≈ diagonal*0.015)보다 확실히 작게
/// 잡아, 진짜 출입구를 실수로 이어붙이지 않는다.
const double _mergeGapMultiplier = 1.6;

/// 두 끝점이 "같은 점"으로 볼 수 있는 허용 오차(px) — 실측된 실제 벽
/// 두께(6~7px)에 맞춘 값. 너무 크면 서로 다른 벽을 하나로 잘못 묶고,
/// 너무 작으면 진짜 T/L 접합도 junction으로 못 잡는다.
const double _junctionTolerancePx = 9.0;

/// 실측된 실제 벽 두께(6~18px)에 안전 마진을 더한 상한 — 이보다 두꺼운
/// "병합 벽"은 서로 다른 두 벽이 잘못 합쳐진 것으로 보고 병합을 거부한다.
const double _maxWallGroupThicknessPx = 20.0;

/// 1차 run-length(minRunLen ≈ diagonal*0.02)가 놓치는 얇거나(anti-alias로
/// 1~2px씩 끊긴) 실내 partition을 복구하는 2차 pass. 실측(§3 조사)에서
/// 실제 벽인데도 표본 y값 3개 중 1개만 어두운 얇은 벽이 확인됐다 —
/// 이런 벽은 1차 스캔의 minRunLen을 만족하지 못해 통째로 누락된다.
/// gap-close(작은 끊김 메우기)는 스캔 방향으로만 최대 2px까지만 메워
/// 실제 문/창 gap(수십 px)과 절대 혼동하지 않는다.
List<WallSegment> _recoverWeakCollinearWalls({
  required Uint8List imageBytes,
  required List<WallSegment> existing,
  required int w,
  required int h,
  required double rotationDegrees,
}) {
  // 회전 보정이 걸린 경우 좌표계가 stage1 내부 작업 캔버스와 달라질 수
  // 있어 안전하게 건너뛴다(실제 이미지 2는 회전 보정 0도로 확인됨 —
  // 이 POC 범위 밖의 이미지에는 이 보조 pass가 적용되지 않을 뿐, 1차
  // 결과에는 전혀 영향 없다).
  if (rotationDegrees != 0) return const [];

  img.Image? decoded;
  try {
    decoded = img.decodeImage(imageBytes);
  } catch (_) {
    return const [];
  }
  if (decoded == null || decoded.width != w || decoded.height != h) {
    return const [];
  }

  final luminance = Uint8List(w * h);
  final histogram = List<int>.filled(256, 0);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final l = decoded.getPixel(x, y).luminance.round().clamp(0, 255);
      luminance[y * w + x] = l;
      histogram[l]++;
    }
  }
  final threshold = otsuThreshold(histogram, w * h);
  final mask = Uint8List(w * h);
  for (var i = 0; i < mask.length; i++) {
    mask[i] = luminance[i] <= threshold ? 1 : 0;
  }

  const bridgeGapPx = 2;
  void closeGaps({required bool horizontal}) {
    final outer = horizontal ? h : w;
    final inner = horizontal ? w : h;
    for (var line = 0; line < outer; line++) {
      var lastDark = -10;
      for (var i = 0; i < inner; i++) {
        final idx = horizontal ? line * w + i : i * w + line;
        if (mask[idx] == 1) {
          if (i - lastDark > 1 && i - lastDark <= bridgeGapPx + 1) {
            for (var k = lastDark + 1; k < i; k++) {
              final fillIdx = horizontal ? line * w + k : k * w + line;
              mask[fillIdx] = 1;
            }
          }
          lastDark = i;
        }
      }
    }
  }

  closeGaps(horizontal: false);
  closeGaps(horizontal: true);

  const weakMinRunLen = 8;
  final rawHorizontal = scanRuns(mask, w, h, horizontal: true, minRunLen: weakMinRunLen);
  final rawVertical = scanRuns(mask, w, h, horizontal: false, minRunLen: weakMinRunLen);
  final maxThicknessPx = (math.max(w, h) * 0.06).round();
  final hBands = mergeRunsToBands(rawHorizontal, maxThicknessPx: maxThicknessPx);
  final vBands = mergeRunsToBands(rawVertical, maxThicknessPx: maxThicknessPx);

  bool overlapsExisting(WallBand band, bool horizontal) {
    for (final e in existing) {
      final dxPx = (e.end.x - e.start.x) * w;
      final dyPx = (e.end.y - e.start.y) * h;
      final eHorizontal = dxPx.abs() >= dyPx.abs();
      if (eHorizontal != horizontal) continue;
      final eCross = horizontal ? e.start.y * h : e.start.x * w;
      if ((band.crossCenter - eCross).abs() > math.max(band.thicknessPx, 4) * 1.2) continue;
      final eAlongMin = horizontal ? math.min(e.start.x, e.end.x) * w : math.min(e.start.y, e.end.y) * h;
      final eAlongMax = horizontal ? math.max(e.start.x, e.end.x) * w : math.max(e.start.y, e.end.y) * h;
      final overlap = math.min(band.alongMax.toDouble(), eAlongMax) - math.max(band.alongMin.toDouble(), eAlongMin);
      if (overlap > (band.alongMax - band.alongMin) * 0.5) return true;
    }
    return false;
  }

  final recovered = <WallSegment>[];
  var idCounter = 0;
  for (final band in hBands) {
    if (band.alongMax - band.alongMin < weakMinRunLen) continue;
    if (overlapsExisting(band, true)) continue;
    recovered.add(
      WallSegment(
        id: 'weak-h-${idCounter++}',
        start: Point2(band.alongMin / w, band.crossCenter / h),
        end: Point2(band.alongMax / w, band.crossCenter / h),
        thicknessNormalized: band.thicknessPx / h,
        confidence: 0.35,
      ),
    );
  }
  for (final band in vBands) {
    if (band.alongMax - band.alongMin < weakMinRunLen) continue;
    if (overlapsExisting(band, false)) continue;
    recovered.add(
      WallSegment(
        id: 'weak-v-${idCounter++}',
        start: Point2(band.crossCenter / w, band.alongMin / h),
        end: Point2(band.crossCenter / w, band.alongMax / h),
        thicknessNormalized: band.thicknessPx / w,
        confidence: 0.35,
      ),
    );
  }
  return recovered;
}

PixelWallExtractionResult extractPixelWalls(Uint8List imageBytes) {
  final stage1 = detectWallsAndOpenings(WallStageInput(imageBytes));
  if (!stage1.isSuccess) {
    return PixelWallExtractionResult.failure(stage1.failureReason!);
  }

  final w = stage1.analysisWidthPx;
  final h = stage1.analysisHeightPx;

  final weakRecovered = _recoverWeakCollinearWalls(
    imageBytes: imageBytes,
    existing: stage1.walls,
    w: w,
    h: h,
    rotationDegrees: stage1.rotationDegrees,
  );
  final allWalls = [...stage1.walls, ...weakRecovered];

  // WallSegment는 정규화 좌표라 orientation을 다시 픽셀 기준으로
  // 판단해야 한다(정규화 좌표만 보면 종횡비 때문에 오판할 수 있음).
  PixelWallOrientation orientationOf(WallSegment s) {
    final dxPx = (s.end.x - s.start.x) * w;
    final dyPx = (s.end.y - s.start.y) * h;
    return dxPx.abs() >= dyPx.abs()
        ? PixelWallOrientation.horizontal
        : PixelWallOrientation.vertical;
  }

  double lengthPxOf(WallSegment s) {
    final dxPx = (s.end.x - s.start.x) * w;
    final dyPx = (s.end.y - s.start.y) * h;
    return math.sqrt(dxPx * dxPx + dyPx * dyPx);
  }

  double crossCenterPxOf(WallSegment s, PixelWallOrientation o) =>
      o == PixelWallOrientation.horizontal ? s.start.y * h : s.start.x * w;

  double thicknessPxOf(WallSegment s, PixelWallOrientation o) =>
      s.thicknessNormalized * (o == PixelWallOrientation.horizontal ? h : w);

  // --- 1단계: 같은 축, 같은 중심선 위의 작은 gap을 잇는 segment 병합.
  // 진짜 문/창(넓은 gap)은 그대로 남겨 detectWallsAndOpenings가 이미
  // 만든 OpeningCandidate가 이어받는다 — 여기서는 "노이즈로 잘린" 짧은
  // gap만 잇는다.
  final horizontal = allWalls.where((s) => orientationOf(s) == PixelWallOrientation.horizontal).toList()
    ..sort((a, b) => a.start.x.compareTo(b.start.x));
  final vertical = allWalls.where((s) => orientationOf(s) == PixelWallOrientation.vertical).toList()
    ..sort((a, b) => a.start.y.compareTo(b.start.y));

  // 실측 실제 벽 두께(6~18px)를 넘는 그룹은 서로 다른 두 벽이 잘못
  // 합쳐진 것으로 본다 — 이전 구현은 병합할 때마다 crossCenter를
  // 이동평균으로 갱신해 "현재" 값끼리만 비교했기 때문에, A(y=45)+B(y=50)
  // →중간값 47.5 상태에서 C(y=54)까지 서서히 끌려 들어가는 creep 버그가
  // 있었다(실측: 두께 38.3px짜리 가짜 "벽" 발생 — 서로 다른 두 줄의 벽이
  // 하나로 뭉개짐). 고정된 anchor(그룹의 첫 segment) 기준 cross 범위로만
  // 비교하고, 그 범위가 [_maxWallGroupThicknessPx]를 넘으면 병합을 거부한다.
  List<WallSegment> mergeCollinear(List<WallSegment> segs, PixelWallOrientation o) {
    final used = List<bool>.filled(segs.length, false);
    final result = <WallSegment>[];
    for (var i = 0; i < segs.length; i++) {
      if (used[i]) continue;
      used[i] = true;
      var alongMin = o == PixelWallOrientation.horizontal ? segs[i].start.x * w : segs[i].start.y * h;
      var alongMax = o == PixelWallOrientation.horizontal ? segs[i].end.x * w : segs[i].end.y * h;
      var crossMin = crossCenterPxOf(segs[i], o);
      var crossMax = crossMin;
      var maxThicknessPx = thicknessPxOf(segs[i], o);
      var maxConfidence = segs[i].confidence;
      var anyExterior = segs[i].isExterior;

      var changed = true;
      while (changed) {
        changed = false;
        for (var j = 0; j < segs.length; j++) {
          if (used[j]) continue;
          final other = segs[j];
          final crossB = crossCenterPxOf(other, o);
          final newCrossMin = math.min(crossMin, crossB);
          final newCrossMax = math.max(crossMax, crossB);
          if (newCrossMax - newCrossMin > _maxWallGroupThicknessPx) continue;

          final bMin = o == PixelWallOrientation.horizontal ? other.start.x * w : other.start.y * h;
          final bMax = o == PixelWallOrientation.horizontal ? other.end.x * w : other.end.y * h;
          final thick = math.max(maxThicknessPx, thicknessPxOf(other, o));
          final gap = math.max(alongMin, bMin) - math.min(alongMax, bMax);
          final maxGap = math.max(4.0, thick * _mergeGapMultiplier);
          if (gap > maxGap) continue;

          alongMin = math.min(alongMin, bMin);
          alongMax = math.max(alongMax, bMax);
          crossMin = newCrossMin;
          crossMax = newCrossMax;
          maxThicknessPx = math.max(maxThicknessPx, thicknessPxOf(other, o));
          maxConfidence = math.max(maxConfidence, other.confidence);
          anyExterior = anyExterior || other.isExterior;
          used[j] = true;
          changed = true;
        }
      }

      final finalCross = (crossMin + crossMax) / 2;
      result.add(
        o == PixelWallOrientation.horizontal
            ? WallSegment(
                id: segs[i].id,
                start: Point2(alongMin / w, finalCross / h),
                end: Point2(alongMax / w, finalCross / h),
                thicknessNormalized: maxThicknessPx / h,
                confidence: maxConfidence,
                isExterior: anyExterior,
              )
            : WallSegment(
                id: segs[i].id,
                start: Point2(finalCross / w, alongMin / h),
                end: Point2(finalCross / w, alongMax / h),
                thicknessNormalized: maxThicknessPx / w,
                confidence: maxConfidence,
                isExterior: anyExterior,
              ),
      );
    }
    return result;
  }

  final mergedHorizontal = mergeCollinear(horizontal, PixelWallOrientation.horizontal);
  final mergedVertical = mergeCollinear(vertical, PixelWallOrientation.vertical);
  final merged = [...mergedHorizontal, ...mergedVertical];

  // --- 2단계: junction 지지 계산 — 이 벽의 두 끝점이 다른 벽의 band(along
  // 범위 + cross 위치) 안쪽에 닿는지 확인한다(T/L/십자 접합 포함, 단순
  // 끝점-끝점 근접보다 실제 벽 접합을 더 잘 반영한다).
  bool touchesBand(Point2 p, WallSegment band, PixelWallOrientation bandOrientation) {
    final px = p.x * w;
    final py = p.y * h;
    if (bandOrientation == PixelWallOrientation.horizontal) {
      final minX = math.min(band.start.x, band.end.x) * w - _junctionTolerancePx;
      final maxX = math.max(band.start.x, band.end.x) * w + _junctionTolerancePx;
      final cy = band.start.y * h;
      return px >= minX && px <= maxX && (py - cy).abs() <= _junctionTolerancePx;
    } else {
      final minY = math.min(band.start.y, band.end.y) * h - _junctionTolerancePx;
      final maxY = math.max(band.start.y, band.end.y) * h + _junctionTolerancePx;
      final cx = band.start.x * w;
      return py >= minY && py <= maxY && (px - cx).abs() <= _junctionTolerancePx;
    }
  }

  int junctionSupportFor(WallSegment self, PixelWallOrientation selfOrientation) {
    var touches = 0;
    var startTouched = false;
    var endTouched = false;
    for (final other in merged) {
      if (identical(other, self)) continue;
      final otherOrientation = orientationOf(other);
      if (!startTouched && touchesBand(self.start, other, otherOrientation)) {
        startTouched = true;
      }
      if (!endTouched && touchesBand(self.end, other, otherOrientation)) {
        endTouched = true;
      }
    }
    if (startTouched) touches++;
    if (endTouched) touches++;
    return touches;
  }

  final candidates = <PixelWallCandidate>[];
  var idCounter = 0;
  for (final seg in merged) {
    final orientation = orientationOf(seg);
    final lengthPx = lengthPxOf(seg);
    final junction = junctionSupportFor(seg, orientation);

    final combined = seg.confidence * 0.55 + (junction / 2) * 0.30 + (lengthPx >= 15 ? 0.15 : 0.0);
    final PixelWallConfidenceTier tier;
    if (combined >= 0.62) {
      tier = PixelWallConfidenceTier.high;
    } else if (combined >= 0.42) {
      tier = PixelWallConfidenceTier.medium;
    } else {
      tier = PixelWallConfidenceTier.low;
    }

    // 짧고(노이즈 run-length 분포상 short 버킷 상한 15px 이하) junction
    // 지지가 전혀 없는 조각은 "구조 벽 확정"이 아니라 검토 대상으로 —
    // 삭제하지 않고 남긴다(§6/§14 — 조용히 삭제 금지).
    final category = (lengthPx < 15 && junction == 0)
        ? PixelWallCategory.reviewNeeded
        : PixelWallCategory.structural;

    candidates.add(
      PixelWallCandidate(
        id: 'pxwall-${idCounter++}',
        start: seg.start,
        end: seg.end,
        thicknessNormalized: seg.thicknessNormalized,
        orientation: orientation,
        isExterior: seg.isExterior,
        baseConfidence: seg.confidence,
        junctionSupport: junction,
        confidenceTier: tier,
        category: category,
        sourceSegmentIds: [seg.id],
      ),
    );
  }

  final rejected = [
    for (final r in stage1.rejectedWalls)
      PixelWallRejection(start: r.start, end: r.end, reasonLabel: r.reason.name),
  ];

  // 방 분리(flood-fill)를 위한 mask는 stage1의 wall-only mask가 아니라
  // "최종 분류된 candidates(weak-recovery 포함) 전체를 다시 그린" 새
  // mask다 — stage1.mask는 weak-recovery로 새로 복구된 벽을 전혀 모르기
  // 때문이다. 그 위에 실제 문/창 gap 위치를 "임시로" 메운다 — 실제
  // 도면은 방마다 문으로 서로 연결되어 있어(설계상 당연함) gap을 그대로
  // 두면 인접한 방들이 전부 하나로 흘러 이어지다 결국 이미지 경계까지
  // 새어나가 detectRooms가 모든 방을 "경계에 닿음"으로 버린다(실측:
  // 벽 49개가 검출됐는데도 RoomCandidate가 0개였던 실제 원인). 문/창은
  // 여전히 [SSOpening]으로 따로 기록되고 지나갈 수 있는 연결로 남는다 —
  // 여기서 메우는 것은 오직 "닫힌 면(face)"을 세는 이 계산에서만 쓰는
  // 임시 사본이며, 최종 topology/opening 데이터에는 전혀 영향을 주지 않는다.
  final roomMask = Uint8List(w * h);
  void fillRoomMaskRect(int xMin, int xMax, int yMin, int yMax) {
    final cxMin = xMin.clamp(0, w - 1);
    final cxMax = xMax.clamp(0, w - 1);
    final cyMin = yMin.clamp(0, h - 1);
    final cyMax = yMax.clamp(0, h - 1);
    for (var y = cyMin; y <= cyMax; y++) {
      final rowBase = y * w;
      for (var x = cxMin; x <= cxMax; x++) {
        roomMask[rowBase + x] = 1;
      }
    }
  }

  for (final c in candidates) {
    if (c.category != PixelWallCategory.structural) continue;
    final thicknessPx = c.thicknessNormalized * (c.orientation == PixelWallOrientation.horizontal ? h : w);
    if (c.orientation == PixelWallOrientation.horizontal) {
      final xMin = (math.min(c.start.x, c.end.x) * w).round();
      final xMax = (math.max(c.start.x, c.end.x) * w).round();
      final centerY = c.start.y * h;
      fillRoomMaskRect(xMin, xMax, (centerY - thicknessPx / 2).round(), (centerY + thicknessPx / 2).round());
    } else {
      final yMin = (math.min(c.start.y, c.end.y) * h).round();
      final yMax = (math.max(c.start.y, c.end.y) * h).round();
      final centerX = c.start.x * w;
      fillRoomMaskRect((centerX - thicknessPx / 2).round(), (centerX + thicknessPx / 2).round(), yMin, yMax);
    }
  }

  // 실기 FAIL 재조사(PC1 CONTINUE — WALL CONSOLIDATION §4) — stage1의
  // OpeningCandidate(같은 orientation 그룹 내에서만 짝 짓는 원래 엔진의
  // 좁은 판정)만으로는 안 잡히는 gap이 실제로 많았다(실측: 하단 외벽이
  // 문 5칸으로 쪼개졌는데도 opening 후보는 1개뿐). wall system 기반 gap
  // 분류(door/imageBreak만 bridge, openPlan/notConnected은 그대로 둠)로
  // 대체 — 더 포괄적이면서도 진짜 넓은 gap은 여전히 잇지 않는다.
  final bridgeSystems = buildWallSystems(candidates: candidates, w: w, h: h);
  for (final system in bridgeSystems) {
    for (var i = 0; i < system.gaps.length; i++) {
      final gap = system.gaps[i];
      if (gap.kind != GapKind.doorOpening && gap.kind != GapKind.imageBreak) continue;
      final a = system.segments[i];
      final b = system.segments[i + 1];
      double candidateThicknessPx(PixelWallCandidate c) =>
          c.thicknessNormalized * (system.orientation == PixelWallOrientation.horizontal ? h : w);
      final thicknessPx = math.max(candidateThicknessPx(a), candidateThicknessPx(b));
      if (system.orientation == PixelWallOrientation.horizontal) {
        final xMin = math.min(a.start.x, a.end.x) * w;
        final xMax = math.max(b.start.x, b.end.x) * w;
        fillRoomMaskRect(xMin.round(), xMax.round(), (system.axisPx - thicknessPx / 2).round(), (system.axisPx + thicknessPx / 2).round());
      } else {
        final yMin = math.min(a.start.y, a.end.y) * h;
        final yMax = math.max(b.start.y, b.end.y) * h;
        fillRoomMaskRect((system.axisPx - thicknessPx / 2).round(), (system.axisPx + thicknessPx / 2).round(), yMin.round(), yMax.round());
      }
    }
  }

  // 실기 FAIL 재조사(PC1 CONTINUE §3 exterior wall classification 개선) —
  // 기존 엔진의 "전체 bounding box 가장자리에 가까우면 외벽"이라는 판정은
  // 직사각형 건물에서만 통한다. 이 도면은 실제로 계단형(step) 외곽을
  // 가져(우측 상단 발코니/현관 쪽이 안쪽으로 들어가 있음) 그 판정이 틀린
  // 사례가 실측으로 확인됐다. 대신 "이 벽의 양옆 중 한쪽이 실제로
  // 건물 바깥(이미지 경계에서부터 이어지는 빈 영역)과 맞닿아 있는가"를
  // border flood-fill로 직접 판정한다 — 벽 모양이 어떻든 항상 성립하는
  // 유일하게 안전한 기준이다.
  // 위 flood-fill은 실제 건물 외곽에 남은 (아직 못 찾은) 진짜 벽 구멍을
  // 통해 "바깥"이 건물 내부 깊숙이 새어 들어올 수 있다(실측: 거실 안쪽
  // 파티션 벽까지 "외벽"으로 잘못 재분류됨). 이 오탐을 막기 위해, 벽
  // 자신의 축 좌표가 이미지 가장자리 근처(margin 이내)일 때만
  // flood-fill 근거를 신뢰한다 — 계단형 외곽(발코니/욕실1 돌출 등)은
  // 항상 가장자리 부근에 있으므로 이 조건을 만족하고, 안쪽 깊숙한
  // 파티션은 새어 들어온 "바깥"과 우연히 닿아도 걸러진다. 기존
  // bounding-box 기준(직사각형 부분에서는 이미 정확했음)은 OR 조건으로
  // 계속 인정한다.
  const edgeMarginRatio = 0.30;
  final outsideMask = _computeOutsideMask(roomMask, w, h);
  final reclassified = <PixelWallCandidate>[
    for (final c in candidates)
      c.withExterior(
        c.isExterior ||
            (_touchesOutside(c, outsideMask, w, h) && _nearOwnAxisEdge(c, edgeMarginRatio)),
      ),
  ];

  final rooms = detectRooms(RoomStageInput(mask: roomMask, width: w, height: h)).rooms;

  return PixelWallExtractionResult.success(
    sourceWidthPx: stage1.sourceWidthPx,
    sourceHeightPx: stage1.sourceHeightPx,
    analysisWidthPx: w,
    analysisHeightPx: h,
    mask: roomMask,
    candidates: reclassified,
    rejected: rejected,
    openings: stage1.openings,
    rooms: rooms,
    rotationDegrees: stage1.rotationDegrees,
    rawWallSegmentCount: stage1.walls.length,
    weakRecoveredCount: weakRecovered.length,
  );
}

/// roomMask(1=벽/door-bridge, 0=빈 공간)에서 이미지 경계와 연결된 0-영역을
/// BFS로 찾는다 — 이 영역이 "건물 바깥"이다(내부 방은 벽으로 막혀 있어
/// 경계까지 이어지지 않는다).
Uint8List _computeOutsideMask(Uint8List roomMask, int w, int h) {
  final outside = Uint8List(w * h);
  final queue = <int>[];
  void tryEnqueue(int x, int y) {
    if (x < 0 || y < 0 || x >= w || y >= h) return;
    final idx = y * w + x;
    if (roomMask[idx] == 1 || outside[idx] == 1) return;
    outside[idx] = 1;
    queue.add(idx);
  }

  for (var x = 0; x < w; x++) {
    tryEnqueue(x, 0);
    tryEnqueue(x, h - 1);
  }
  for (var y = 0; y < h; y++) {
    tryEnqueue(0, y);
    tryEnqueue(w - 1, y);
  }

  var head = 0;
  while (head < queue.length) {
    final idx = queue[head++];
    final x = idx % w;
    final y = idx ~/ w;
    tryEnqueue(x - 1, y);
    tryEnqueue(x + 1, y);
    tryEnqueue(x, y - 1);
    tryEnqueue(x, y + 1);
  }
  return outside;
}

/// [c]의 중심선을 따라 몇 지점을 샘플링해, 벽 두께만큼 양옆으로
/// 벗어난 위치 중 하나라도 "건물 바깥"이면 외벽으로 본다.
bool _touchesOutside(PixelWallCandidate c, Uint8List outside, int w, int h) {
  const samples = 3;
  final thicknessPx = c.thicknessNormalized * (c.orientation == PixelWallOrientation.horizontal ? h : w);
  final offset = thicknessPx / 2 + 3;

  bool isOutside(double x, double y) {
    final xi = x.round();
    final yi = y.round();
    if (xi < 0 || yi < 0 || xi >= w || yi >= h) return true; // 이미지 밖도 바깥으로 간주.
    return outside[yi * w + xi] == 1;
  }

  for (var i = 0; i <= samples; i++) {
    final t = i / samples;
    final px = (c.start.x + (c.end.x - c.start.x) * t) * w;
    final py = (c.start.y + (c.end.y - c.start.y) * t) * h;
    if (c.orientation == PixelWallOrientation.horizontal) {
      if (isOutside(px, py - offset) || isOutside(px, py + offset)) return true;
    } else {
      if (isOutside(px - offset, py) || isOutside(px + offset, py)) return true;
    }
  }
  return false;
}

/// 벽 자신의 축 좌표(수평 벽=y, 수직 벽=x, 정규화 0~1)가 이미지
/// 가장자리로부터 [marginRatio] 이내인지 — 계단형 외곽 판정에만 쓰는
/// 보수적 안전장치(위 함수 문서 참고).
bool _nearOwnAxisEdge(PixelWallCandidate c, double marginRatio) {
  final axisNorm = c.orientation == PixelWallOrientation.horizontal ? c.start.y : c.start.x;
  return axisNorm <= marginRatio || axisNorm >= (1 - marginRatio);
}
