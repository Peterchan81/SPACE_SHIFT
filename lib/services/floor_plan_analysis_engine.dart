import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/floor_plan_geometry.dart';

// 평면도 CV 분석의 실제 픽셀 처리 파이프라인.
//
// compute()로 백그라운드 isolate에서만 실행되는 순수 함수들이다(WO 22번
// — 메인 UI thread에서 대형 bitmap pixel loop를 직접 돌리지 않는다).
// Flutter 위젯/컨텍스트에 의존하지 않고 dart:typed_data와 package:image
// (순수 Dart)만 사용해, isolate 경계를 넘나드는 메시지로 안전하게 주고받을
// 수 있는 값만 다룬다.
//
// 실제 알고리즘(보고서 27번 항목과 동일):
//   1. 이미지 디코드 → 최대 900px로 다운샘플(원본 비율 유지)
//   2. 픽셀별 luminance로 grayscale 값 계산
//   3. Otsu 방법으로 이진화 임계값을 실제 히스토그램에서 계산(하드코딩 아님)
//   3.5. (PC2 2D CAD 재조사 WO) 이미지 전체에 공통으로 적용되는 지배적
//      회전각을 추정해 "레벨을 맞춘" 작업 캔버스를 만든다 — 실제 촬영/
//      스캔된 평면도는 건물 구조 전체가 이미지 축과 어긋난 경우가 흔하기
//      때문이다. 이미 축에 잘 맞는 도면은 이 단계가 항등 변환이다.
//   4. 이진화된 "어두운 픽셀"을 (회전 보정된) 행/열 방향으로 run-length
//      스캔해 직선 후보 추출
//   5. 인접한 run을 겹침 기준으로 병합해 벽 band(두께 포함)로 그룹화
//   6. 같은 direction·같은 중심선의 인접 band 사이 gap을 문/창 후보로 추출
//   7. (2단계 isolate 호출) 벽이 아닌(밝은) 영역을 flood fill로 연결
//      요소를 찾아 이미지 경계에 닿지 않는 요소를 방 후보(경계 사각형)로 추출
//
// 이번 구현은 Hough 변환이 아니라 "run-length 기반 축 정렬 직선 추출"에
// 지배적 회전각 보정(deskew) 한 겹을 더한 것이다 — 평면도가 대체로
// 서로 수직/수평으로 맞물린 벽으로 이루어진다는 전제(대부분의 실제
// 평면도가 이 전제를 만족한다)를 쓰되, 그 전체 구조가 이미지 축 자체와는
// 몇 도 어긋나 있어도 된다. 축 정렬이 아닌, 벽마다 각도가 다른 진짜
// 비정형 구조(한 벽만 45도로 꺾인 경우 등)는 이번 단계에서도 그 벽만은
// 검출하지 못한다(한계로 보고) — 다만 그 벽의 두 이웃 벽이 여전히
// 서로 수직/수평이면 방 전체가 통째로 사라지지는 않는다.

const int kMaxAnalysisDimension = 900;
const int kMinSourceDimension = 200;

/// stage 1(벽/문·창 후보) isolate 호출의 입력.
class WallStageInput {
  const WallStageInput(this.bytes);
  final Uint8List bytes;
}

/// stage 1 결과. [mask]는 stage 2(방 후보)로 그대로 전달된다.
class WallStageResult {
  const WallStageResult.failure(this.failureReason)
    : sourceWidthPx = 0,
      sourceHeightPx = 0,
      analysisWidthPx = 0,
      analysisHeightPx = 0,
      mask = null,
      walls = const [],
      openings = const [],
      rejectedWalls = const [],
      rawHorizontalRuns = 0,
      rawVerticalRuns = 0,
      elapsedMs = 0,
      rotationDegrees = 0;

  const WallStageResult.success({
    required this.sourceWidthPx,
    required this.sourceHeightPx,
    required this.analysisWidthPx,
    required this.analysisHeightPx,
    required this.mask,
    required this.walls,
    required this.openings,
    required this.rawHorizontalRuns,
    required this.rawVerticalRuns,
    required this.elapsedMs,
    this.rejectedWalls = const [],
    this.rotationDegrees = 0,
  }) : failureReason = null;

  final FloorPlanAnalysisFailureReason? failureReason;
  final int sourceWidthPx;
  final int sourceHeightPx;
  final int analysisWidthPx;
  final int analysisHeightPx;

  /// 분석 해상도 기준 1바이트/픽셀 이진 마스크(1=벽 후보, 0=배경).
  final Uint8List? mask;
  final List<WallSegment> walls;
  final List<OpeningCandidate> openings;

  /// PC2 2D CAD 재조사 WO — 벽 band로 병합됐지만 두께 필터에 걸려
  /// 최종 벽 후보에서 제외된 구간(진단 전용, [walls]/[mask]에는 전혀
  /// 영향을 주지 않는다). "분석 확인" 디버그 오버레이에서만 쓰인다.
  final List<RejectedWallCandidate> rejectedWalls;
  final int rawHorizontalRuns;
  final int rawVerticalRuns;
  final int elapsedMs;

  /// PC2 2D CAD 재조사 WO — 추정된 지배적 회전 보정각(도). 0이면 이미지가
  /// 축에 잘 맞아 회전 보정이 적용되지 않았다는 뜻(진단/정보 표시 전용,
  /// geometry 자체는 항상 이미 원본 이미지 좌표계로 보정되어 있다).
  final double rotationDegrees;

  bool get isSuccess => failureReason == null;
}

/// stage 2(방 후보) isolate 호출의 입력.
class RoomStageInput {
  const RoomStageInput({
    required this.mask,
    required this.width,
    required this.height,
  });

  final Uint8List mask;
  final int width;
  final int height;
}

class RoomStageResult {
  const RoomStageResult({required this.rooms, required this.elapsedMs});

  final List<RoomCandidate> rooms;
  final int elapsedMs;
}

/// isolate 진입점 — stage 1: 디코드/다운샘플/이진화 + 벽/문·창 후보.
WallStageResult detectWallsAndOpenings(WallStageInput input) {
  final stopwatch = Stopwatch()..start();

  // 손상되었거나 형식을 흉내만 낸 바이트는 decodeImage가 null을 반환하지
  // 않고 내부에서 예외를 던질 수도 있다 — 두 경우 모두 "이미지를 읽지
  // 못했습니다"로 동일하게 처리한다(WO 15번).
  img.Image? decoded;
  try {
    decoded = img.decodeImage(input.bytes);
  } catch (_) {
    decoded = null;
  }
  if (decoded == null) {
    return const WallStageResult.failure(
      FloorPlanAnalysisFailureReason.unreadableImage,
    );
  }

  final sourceWidth = decoded.width;
  final sourceHeight = decoded.height;
  if (sourceWidth < kMinSourceDimension || sourceHeight < kMinSourceDimension) {
    return const WallStageResult.failure(
      FloorPlanAnalysisFailureReason.tooSmall,
    );
  }

  final longestSide = math.max(sourceWidth, sourceHeight);
  final scale = longestSide > kMaxAnalysisDimension
      ? kMaxAnalysisDimension / longestSide
      : 1.0;
  final analysisWidth = math.max(1, (sourceWidth * scale).round());
  final analysisHeight = math.max(1, (sourceHeight * scale).round());

  final analysisImage = scale < 1.0
      ? img.copyResize(
          decoded,
          width: analysisWidth,
          height: analysisHeight,
          interpolation: img.Interpolation.average,
        )
      : decoded;

  final w = analysisImage.width;
  final h = analysisImage.height;
  final luminance = Uint8List(w * h);
  final histogram = List<int>.filled(256, 0);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final l = analysisImage.getPixel(x, y).luminance.round().clamp(0, 255);
      luminance[y * w + x] = l;
      histogram[l]++;
    }
  }

  final threshold = otsuThreshold(histogram, w * h);
  final mask = Uint8List(w * h);
  for (var i = 0; i < mask.length; i++) {
    // Otsu 임계값 t는 "값 <= t가 배경(어두운 픽셀) 클래스"로 누적
    // 계산되므로(otsuThreshold의 weightBackground 누적과 일치해야 함),
    // 여기서도 <=로 나눠야 한다. <로 나누면 순수 이진(0/255) 이미지처럼
    // 임계값이 0으로 나올 때 어두운 픽셀이 전부 빠지는 문제가 있었다.
    mask[i] = luminance[i] <= threshold ? 1 : 0;
  }

  // PC2 2D CAD 재조사 WO(핵심 후보로 지목된 axis-aligned 전용 한계) —
  // run-length 스캔은 완전한 수평/수직 벽만 검출한다. 실제 촬영/스캔된
  // 평면도는 건물 구조 전체가 이미지 축과 몇 도씩 어긋나 있는 경우가
  // 흔하고, 그 경우 벽 대부분을 그냥 놓쳤다(실기 재현: "실제 벽이
  // 대량 누락됨"). 이미지 전체에 공통으로 적용되는 지배적 회전각
  // 하나를 추정해, 그 각으로 "레벨을 맞춘" 확장 작업 캔버스에서 기존에
  // 이미 검증된 run-length/band 파이프라인을 그대로 재사용하고, 결과
  // 좌표만 원본 이미지 좌표계로 되돌린다 — 겹침 병합/두께 필터/
  // saddle-point 안전 경계 추적 같은 기존 로직을 다시 만들지 않는다.
  // 이미 축에 잘 맞는 도면(추정 회전각이 사실상 0)은 이 경로 전체가
  // 항등 변환이라 기존 동작과 완전히 같다(회귀 없음 — 모든 기존
  // synthetic 테스트가 이 경로를 검증한다).
  final rotationDeg = _estimateDominantRotationDegrees(mask, w, h);
  final rotationRad = rotationDeg * math.pi / 180;

  final Uint8List workingMask;
  final int workingW;
  final int workingH;
  if (rotationDeg == 0) {
    workingMask = mask;
    workingW = w;
    workingH = h;
  } else {
    final expanded = _expandedCanvasSize(w, h, rotationRad);
    workingW = expanded.w;
    workingH = expanded.h;
    workingMask = _resampleMask(
      source: mask,
      sourceW: w,
      sourceH: h,
      destW: workingW,
      destH: workingH,
      destToSource: (dx, dy) => _undoDeskewPoint(
        x: dx,
        y: dy,
        originalW: w,
        originalH: h,
        rotatedW: workingW,
        rotatedH: workingH,
        angleRad: rotationRad,
      ),
    );
  }

  final workingDiagonal = math.sqrt(
    workingW * workingW + workingH * workingH,
  );
  final originalDiagonal = math.sqrt(w * w + h * h);
  final minRunLen = workingDiagonal * 0.02 < 6
      ? 6
      : (workingDiagonal * 0.02).round();

  final rawHorizontal = scanRuns(
    workingMask,
    workingW,
    workingH,
    horizontal: true,
    minRunLen: minRunLen,
  );
  final rawVertical = scanRuns(
    workingMask,
    workingW,
    workingH,
    horizontal: false,
    minRunLen: minRunLen,
  );

  final maxThicknessPx = (math.max(workingW, workingH) * 0.06).round();
  final rejectedHorizontalBands = <WallBand>[];
  final rejectedVerticalBands = <WallBand>[];
  final horizontalBands = mergeRunsToBands(
    rawHorizontal,
    maxThicknessPx: maxThicknessPx,
    rejectedOut: rejectedHorizontalBands,
  );
  final verticalBands = mergeRunsToBands(
    rawVertical,
    maxThicknessPx: maxThicknessPx,
    rejectedOut: rejectedVerticalBands,
  );

  // 검출된 모든 벽 band를 감싸는 bounding box(작업 캔버스 기준) — 외벽
  // 후보 판정 기준.
  var minX = double.infinity;
  var maxX = double.negativeInfinity;
  var minY = double.infinity;
  var maxY = double.negativeInfinity;
  for (final b in horizontalBands) {
    minX = math.min(minX, b.alongMin.toDouble());
    maxX = math.max(maxX, b.alongMax.toDouble());
    minY = math.min(minY, b.crossCenter);
    maxY = math.max(maxY, b.crossCenter);
  }
  for (final b in verticalBands) {
    minY = math.min(minY, b.alongMin.toDouble());
    maxY = math.max(maxY, b.alongMax.toDouble());
    minX = math.min(minX, b.crossCenter);
    maxX = math.max(maxX, b.crossCenter);
  }
  final boundaryTolerance = math.max(workingW, workingH) * 0.03;

  // 작업(회전 보정) 캔버스 픽셀 좌표 → 원본 분석 이미지 정규화 좌표.
  // rotationDeg가 0이면 기존 코드와 완전히 동일한 나눗셈(항등 변환).
  Point2 toOriginalNormalized(double px, double py) {
    if (rotationDeg == 0) return Point2(px / w, py / h);
    final orig = _undoDeskewPoint(
      x: px,
      y: py,
      originalW: w,
      originalH: h,
      rotatedW: workingW,
      rotatedH: workingH,
      angleRad: rotationRad,
    );
    return Point2(orig.x / w, orig.y / h);
  }

  // 3D 근본 수정 WO(2번)이 확정한 규칙("두께는 벽과 같은 축의 정규화
  // 단위") — 회전 보정 후에도 원본 이미지 기준 수평/수직에 가까운
  // 벽(회전각이 작거나 0인 절대다수의 실제 사례)은 이전과 100% 동일한
  // h/w 나눗셈을 그대로 쓴다(회귀 없음, CadWall.boundaryPolygon과 3D
  // 벽 두께 계산이 그대로 의존하는 규칙이라 절대 안전해야 한다). 두
  // 축 어디에도 뚜렷이 속하지 않는 진짜 대각선 벽만 가로/세로 평균
  // 기준의 근사치를 쓴다 — boundaryPolygon에 진짜 대각선용 정확한
  // 두께 공식이 없어(3D 쪽 수정이 필요하며 이번 범위 밖) 의도적으로
  // 받아들이는 한계다. 위치/각도(topology)는 항상 정확하다.
  double thicknessNormalizedFor(Point2 start, Point2 end, double thicknessPx) {
    final dxPx = (end.x - start.x) * w;
    final dyPx = (end.y - start.y) * h;
    final absDx = dxPx.abs();
    final absDy = dyPx.abs();
    if (absDx >= absDy * 3) return thicknessPx / h;
    if (absDy >= absDx * 3) return thicknessPx / w;
    return thicknessPx / ((w + h) / 2);
  }

  var idCounter = 0;
  final walls = <WallSegment>[];
  final wallBandById = <String, WallBand>{};

  for (final band in horizontalBands) {
    final id = 'wall-${idCounter++}';
    final isExterior =
        band.crossCenter <= minY + boundaryTolerance ||
        band.crossCenter >= maxY - boundaryTolerance;
    final start = toOriginalNormalized(
      band.alongMin.toDouble(),
      band.crossCenter,
    );
    final end = toOriginalNormalized(
      band.alongMax.toDouble(),
      band.crossCenter,
    );
    walls.add(
      WallSegment(
        id: id,
        start: start,
        end: end,
        thicknessNormalized: thicknessNormalizedFor(
          start,
          end,
          band.thicknessPx.toDouble(),
        ),
        confidence: _confidenceFor(band, workingDiagonal),
        isExterior: isExterior,
      ),
    );
    wallBandById[id] = band;
  }
  for (final band in verticalBands) {
    final id = 'wall-${idCounter++}';
    final isExterior =
        band.crossCenter <= minX + boundaryTolerance ||
        band.crossCenter >= maxX - boundaryTolerance;
    final start = toOriginalNormalized(
      band.crossCenter,
      band.alongMin.toDouble(),
    );
    final end = toOriginalNormalized(
      band.crossCenter,
      band.alongMax.toDouble(),
    );
    walls.add(
      WallSegment(
        id: id,
        start: start,
        end: end,
        thicknessNormalized: thicknessNormalizedFor(
          start,
          end,
          band.thicknessPx.toDouble(),
        ),
        confidence: _confidenceFor(band, workingDiagonal),
        isExterior: isExterior,
      ),
    );
    wallBandById[id] = band;
  }

  final openings = _detectOpenings(
    horizontalBands: horizontalBands,
    verticalBands: verticalBands,
    wallIds: wallBandById,
    thresholdDiagonal: workingDiagonal,
    normalizationDiagonal: originalDiagonal,
    idStart: idCounter,
    toOriginalNormalized: toOriginalNormalized,
  );

  final rejectedWalls = <RejectedWallCandidate>[
    for (final band in rejectedHorizontalBands)
      RejectedWallCandidate(
        id: 'rejected-${idCounter++}',
        start: toOriginalNormalized(
          band.alongMin.toDouble(),
          band.crossCenter,
        ),
        end: toOriginalNormalized(band.alongMax.toDouble(), band.crossCenter),
        thicknessNormalized: thicknessNormalizedFor(
          toOriginalNormalized(band.alongMin.toDouble(), band.crossCenter),
          toOriginalNormalized(band.alongMax.toDouble(), band.crossCenter),
          band.thicknessPx.toDouble(),
        ),
        reason: RejectedWallReason.tooThick,
      ),
    for (final band in rejectedVerticalBands)
      RejectedWallCandidate(
        id: 'rejected-${idCounter++}',
        start: toOriginalNormalized(
          band.crossCenter,
          band.alongMin.toDouble(),
        ),
        end: toOriginalNormalized(band.crossCenter, band.alongMax.toDouble()),
        thicknessNormalized: thicknessNormalizedFor(
          toOriginalNormalized(band.crossCenter, band.alongMin.toDouble()),
          toOriginalNormalized(band.crossCenter, band.alongMax.toDouble()),
          band.thicknessPx.toDouble(),
        ),
        reason: RejectedWallReason.tooThick,
      ),
  ];

  // Windows 실기 FAIL 재조사(2D CAD reconstruction) — 방 검출(stage 2)에
  // 넘기는 mask는 raw Otsu 픽셀이 아니라 벽으로 실제 확정된 band만으로
  // 다시 채운다(가구/해칭/텍스트/워터마크가 방을 잘못 쪼개지 못하게).
  // 작업(회전 보정) 캔버스 기준으로 만든 뒤, stage 2(방 검출)는 회전을
  // 전혀 몰라도 되도록 항상 "원본 분석 해상도(w×h)" 크기로 되돌려
  // 넘긴다 — saddle-point 안전 경계 추적을 포함한 기존 검증된 방 검출
  // 코드를 그대로, 아무 변경 없이 재사용하기 위해서다.
  final wallOnlyMaskWorking = _buildWallOnlyMask(
    workingW,
    workingH,
    horizontalBands,
    verticalBands,
  );
  final wallOnlyMask = rotationDeg == 0
      ? wallOnlyMaskWorking
      : _resampleMask(
          source: wallOnlyMaskWorking,
          sourceW: workingW,
          sourceH: workingH,
          destW: w,
          destH: h,
          destToSource: (dx, dy) => _deskewPoint(
            x: dx,
            y: dy,
            originalW: w,
            originalH: h,
            rotatedW: workingW,
            rotatedH: workingH,
            angleRad: rotationRad,
          ),
        );

  stopwatch.stop();
  return WallStageResult.success(
    sourceWidthPx: sourceWidth,
    sourceHeightPx: sourceHeight,
    analysisWidthPx: w,
    analysisHeightPx: h,
    mask: wallOnlyMask,
    walls: walls,
    openings: openings,
    rejectedWalls: rejectedWalls,
    rawHorizontalRuns: rawHorizontal.length,
    rawVerticalRuns: rawVertical.length,
    elapsedMs: stopwatch.elapsedMilliseconds,
    rotationDegrees: rotationDeg,
  );
}

/// isolate 진입점 — stage 2: 벽이 아닌 영역의 연결 요소를 찾아 방 후보를
/// 추출한다(경계에 닿지 않는 요소만 "닫힌 공간"으로 취급).
RoomStageResult detectRooms(RoomStageInput input) {
  final stopwatch = Stopwatch()..start();
  final w = input.width;
  final h = input.height;
  final mask = input.mask;
  final visited = Uint8List(w * h);
  final rooms = <RoomCandidate>[];
  var idCounter = 0;
  final minAreaPx = (w * h * 0.005).round();

  for (var startY = 0; startY < h; startY++) {
    for (var startX = 0; startX < w; startX++) {
      final startIdx = startY * w + startX;
      if (mask[startIdx] == 1 || visited[startIdx] == 1) continue;

      var minX = startX, maxX = startX, minY = startY, maxY = startY;
      var area = 0;
      var touchesBorder = false;
      final stack = <int>[startIdx];
      visited[startIdx] = 1;
      // 2D 정확도 개선 WO(8번) — bounding box만이 아니라 실제 픽셀
      // 좌표도 모아 둔다. 분석이 끝난 뒤 이 좌표들로 실제 윤곽(contour)을
      // 추적해, 직사각형이 아닌 방(L자 등)도 실제 모양에 가깝게 만든다.
      final regionPixels = <int>[startIdx];

      while (stack.isNotEmpty) {
        final idx = stack.removeLast();
        final x = idx % w;
        final y = idx ~/ w;
        area++;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
        if (x == 0 || y == 0 || x == w - 1 || y == h - 1) touchesBorder = true;

        void tryPush(int nx, int ny) {
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) return;
          final nIdx = ny * w + nx;
          if (mask[nIdx] == 1 || visited[nIdx] == 1) return;
          visited[nIdx] = 1;
          stack.add(nIdx);
          regionPixels.add(nIdx);
        }

        tryPush(x - 1, y);
        tryPush(x + 1, y);
        tryPush(x, y - 1);
        tryPush(x, y + 1);
      }

      if (area < minAreaPx || touchesBorder) continue;

      final boundingBoxPolygon = [
        Point2(minX / w, minY / h),
        Point2(maxX / w, minY / h),
        Point2(maxX / w, maxY / h),
        Point2(minX / w, maxY / h),
      ];
      // 실제 윤곽 추적이 실패하면(구멍/예상 밖 topology 등, 방어적으로만
      // 발생) 기존 bounding box로 안전하게 폴백한다 — 절대 자기교차하는
      // 폴리곤을 만들지 않는다.
      final polygon =
          _traceRoomBoundary(
            pixels: regionPixels,
            minX: minX,
            minY: minY,
            maxX: maxX,
            maxY: maxY,
            width: w,
            height: h,
          ) ??
          boundingBoxPolygon;
      final boxArea = (maxX - minX + 1) * (maxY - minY + 1);
      final fillRatio = boxArea > 0 ? area / boxArea : 0.0;
      rooms.add(
        RoomCandidate(
          id: 'room-${idCounter++}',
          polygon: polygon,
          areaNormalized: area / (w * h),
          confidence: fillRatio.clamp(0.3, 0.95),
          closed: true,
        ),
      );
    }
  }

  stopwatch.stop();
  return RoomStageResult(
    rooms: rooms,
    elapsedMs: stopwatch.elapsedMilliseconds,
  );
}

/// 2D 정확도 개선 WO(8번) — flood-fill로 찾은 연결 요소(방)의 실제
/// 픽셀 경계를 rectilinear(축 정렬) 폴리곤으로 추적한다. 각 픽셀의 4면
/// 중 "영역 밖과 맞닿은 면"만 경계 edge로 모으고, 각 격자 정점에서
/// edge를 하나씩만 따라가며 닫힌 루프 하나를 만든다 — 구멍이 없는 단순
/// 연결 영역(이 CV 파이프라인이 실제로 만드는 형태)이면 항상 성공한다.
///
/// 안전 설계: 예상 밖 topology(각 정점의 edge가 1개가 아님, 루프가 안
/// 닫힘 등 — 이론상 이 파이프라인에서는 나오지 않아야 하지만 방어적으로
/// 확인한다)를 만나면 즉시 null을 반환해 호출부가 기존 bounding box로
/// 안전하게 폴백하게 한다. 잘못된(자기교차) 폴리곤을 만드느니 차라리
/// 덜 정확한 사각형을 쓴다.
List<Point2>? _traceRoomBoundary({
  required List<int> pixels,
  required int minX,
  required int minY,
  required int maxX,
  required int maxY,
  required int width,
  required int height,
}) {
  final localWidth = maxX - minX + 1;
  final localHeight = maxY - minY + 1;
  if (localWidth <= 0 || localHeight <= 0) return null;

  final region = <int>{};
  for (final idx in pixels) {
    final x = idx % width - minX;
    final y = idx ~/ width - minY;
    region.add(y * localWidth + x);
  }

  bool inRegion(int x, int y) {
    if (x < 0 || y < 0 || x >= localWidth || y >= localHeight) return false;
    return region.contains(y * localWidth + x);
  }

  // 격자 정점(픽셀 코너) 좌표계 — (localWidth+1) x (localHeight+1)개.
  int vKey(int x, int y) => y * (localWidth + 1) + x;
  final nextVertex = <int, int>{};

  // 실기 FAIL 재수정(3D 근본 수정) — 대각선으로만 맞닿은 두 영역 조각이
  // 같은 정점을 공유하는 "안장점(saddle point, marching-squares 고전적
  // ambiguous case)"에서는 이 정점이 실제로 서로 다른 2개의 바깥쪽
  // edge를 가진다. 예전 구현은 Map[key]=value로 그냥 덮어써서 그 중
  // 하나를 조용히 버렸다 — 그 결과 경계 추적이 방의 실제 모양과 무관한
  // 엉뚱한 정점으로 "점프"해, ear-clipping 단계에서 방과 무관하게 멀리
  // 뻗는 거대한 삼각형을 만드는 원인이 됐다(벽 geometry는 항상 고정
  // 사각형 extrusion이라 이 버그의 영향을 받지 않지만, 바닥/방 polygon은
  // 이 함수의 결과를 그대로 쓴다). 같은 정점에 두 번째 edge가 들어오면
  // "안전하게 실패"로 처리해 호출부가 bounding box로 폴백하게 한다 —
  // 잘못된 polygon을 만드느니 차라리 부정확한 사각형을 쓴다는 이 파일의
  // 기존 설계 원칙을 그대로 따른다.
  var hasAmbiguousVertex = false;

  void addEdge(int x1, int y1, int x2, int y2) {
    final key = vKey(x1, y1);
    if (nextVertex.containsKey(key)) {
      hasAmbiguousVertex = true;
      return;
    }
    nextVertex[key] = vKey(x2, y2);
  }

  for (var y = 0; y < localHeight; y++) {
    for (var x = 0; x < localWidth; x++) {
      if (!inRegion(x, y)) continue;
      if (!inRegion(x, y - 1)) addEdge(x, y, x + 1, y); // top, 왼→오.
      if (!inRegion(x + 1, y)) addEdge(x + 1, y, x + 1, y + 1); // right, 위→아래.
      if (!inRegion(x, y + 1)) {
        addEdge(x + 1, y + 1, x, y + 1); // bottom, 오→왼.
      }
      if (!inRegion(x - 1, y)) addEdge(x, y + 1, x, y); // left, 아래→위.
    }
  }
  if (nextVertex.isEmpty) return null;
  if (hasAmbiguousVertex) return null;

  final startKey = nextVertex.keys.first;
  final loopKeys = <int>[startKey];
  final seen = <int>{startKey};
  var current = startKey;
  final maxSteps = (localWidth + 1) * (localHeight + 1) * 4 + 8;
  while (loopKeys.length <= maxSteps) {
    final next = nextVertex[current];
    if (next == null) return null; // edge가 안 이어짐 — 예상 밖 topology.
    if (next == startKey) break; // 루프 완성.
    if (!seen.add(next)) return null; // 이미 지나간 정점 — 예상 밖 분기.
    loopKeys.add(next);
    current = next;
  }
  if (loopKeys.length < 3) return null;

  // 직선 위의 중간 정점(방향이 안 바뀌는 점)은 제거해 폴리곤을
  // 단순화한다 — 실제 모서리(꼭짓점)만 남긴다.
  final gridPoints = [
    for (final k in loopKeys)
      (x: k % (localWidth + 1), y: k ~/ (localWidth + 1)),
  ];
  final corners = <({int x, int y})>[];
  for (var i = 0; i < gridPoints.length; i++) {
    final prev = gridPoints[(i - 1 + gridPoints.length) % gridPoints.length];
    final cur = gridPoints[i];
    final next = gridPoints[(i + 1) % gridPoints.length];
    final dx1 = cur.x - prev.x, dy1 = cur.y - prev.y;
    final dx2 = next.x - cur.x, dy2 = next.y - cur.y;
    if (dx1 * dy2 - dy1 * dx2 != 0) corners.add(cur);
  }
  final finalPoints = corners.length >= 3 ? corners : gridPoints;
  if (finalPoints.length < 3) return null;

  return [
    for (final p in finalPoints)
      Point2((p.x + minX) / width, (p.y + minY) / height),
  ];
}

/// Otsu 방법 — 클래스 내 분산이 최소(클래스 간 분산이 최대)가 되는
/// 임계값을 히스토그램에서 실제로 계산한다(고정값 하드코딩이 아니다).
///
/// Vision Guided CAD POC WO — 이 함수와 [scanRuns]/[mergeRunsToBands]/
/// [RawRun]/[WallBand]는 원래 이 파일 전용 private 헬퍼였지만, 전체
/// 이미지 전역 분석이 아니라 "Vision이 지목한 좁은 영역 안에서만" 같은
/// 저수준 계산을 재사용해야 하는 [HintedGeometryExtractor]를 위해
/// public으로 바꿨다 — 동작은 전혀 바뀌지 않았고 가시성만 넓어졌다.
int otsuThreshold(List<int> histogram, int totalPixels) {
  if (totalPixels == 0) return 128;

  var sumAll = 0.0;
  for (var i = 0; i < 256; i++) {
    sumAll += i * histogram[i];
  }

  var sumBackground = 0.0;
  var weightBackground = 0;
  var maxVariance = -1.0;
  var threshold = 128;

  for (var t = 0; t < 256; t++) {
    weightBackground += histogram[t];
    if (weightBackground == 0) continue;
    final weightForeground = totalPixels - weightBackground;
    if (weightForeground == 0) break;

    sumBackground += t * histogram[t];
    final meanBackground = sumBackground / weightBackground;
    final meanForeground = (sumAll - sumBackground) / weightForeground;

    final betweenVariance =
        weightBackground *
        weightForeground *
        (meanBackground - meanForeground) *
        (meanBackground - meanForeground);

    if (betweenVariance > maxVariance) {
      maxVariance = betweenVariance;
      threshold = t;
    }
  }
  return threshold;
}

class RawRun {
  const RawRun(this.lineIndex, this.start, this.end);
  final int lineIndex;
  final int start;
  final int end;
}

/// 이진 마스크를 행(수평) 또는 열(수직) 방향으로 스캔해 연속된 "어두운
/// 픽셀" run을 찾는다 — run-length 기반 축 정렬 직선 후보 추출.
List<RawRun> scanRuns(
  Uint8List mask,
  int w,
  int h, {
  required bool horizontal,
  required int minRunLen,
}) {
  final runs = <RawRun>[];
  final outerLen = horizontal ? h : w;
  final innerLen = horizontal ? w : h;

  for (var line = 0; line < outerLen; line++) {
    var runStart = -1;
    for (var i = 0; i <= innerLen; i++) {
      final isDark =
          i < innerLen &&
          (horizontal ? mask[line * w + i] == 1 : mask[i * w + line] == 1);
      if (isDark) {
        runStart = runStart == -1 ? i : runStart;
      } else if (runStart != -1) {
        final len = i - runStart;
        if (len >= minRunLen) runs.add(RawRun(line, runStart, i - 1));
        runStart = -1;
      }
    }
  }
  return runs;
}

/// 벽 band — 서로 인접한 여러 줄(행 또는 열)의 run이 겹쳐 병합된 결과.
/// [crossCenter]는 두께 방향의 중심선, [thicknessPx]는 병합된 줄 수(두께).
class WallBand {
  WallBand({
    required this.crossMin,
    required this.crossMax,
    required this.alongMin,
    required this.alongMax,
  });

  int crossMin;
  int crossMax;
  int alongMin;
  int alongMax;

  double get crossCenter => (crossMin + crossMax) / 2;
  int get thicknessPx => crossMax - crossMin + 1;
}

/// 인접한 줄(±1) + along-axis 겹침을 기준으로 raw run을 벽 band로
/// 병합한다. 두께가 비정상적으로 큰(채워진 영역 같은) band는 벽이 아닌
/// 노이즈로 간주해 제외한다.
List<WallBand> mergeRunsToBands(
  List<RawRun> runs, {
  required int maxThicknessPx,
  List<WallBand>? rejectedOut,
}) {
  final sorted = [...runs]..sort((a, b) => a.lineIndex.compareTo(b.lineIndex));
  final active = <WallBand>[];
  final activeLastLine = <WallBand, int>{};
  final finished = <WallBand>[];

  for (final run in sorted) {
    active.removeWhere((b) {
      final last = activeLastLine[b]!;
      if (run.lineIndex - last > 1) {
        finished.add(b);
        return true;
      }
      return false;
    });

    WallBand? match;
    for (final b in active) {
      final overlapStart = math.max(b.alongMin, run.start);
      final overlapEnd = math.min(b.alongMax, run.end);
      final overlapLen = overlapEnd - overlapStart;
      // 겹침 비율은 두 run 중 "짧은 쪽" 대비가 아니라 "긴 쪽" 대비로
      // 계산한다 — 짧은 쪽 기준이면, 전혀 다른 벽(예: 수직 벽 두께만큼
      // 짧은 가로 run)이 우연히 넓은 벽 band 안에 완전히 포함되는 것만
      // 으로도 "같은 벽"으로 잘못 병합되어 버린다(WO 7번 후처리 —
      // collinear 아닌 선을 노이즈로 제거).
      final bandLen = b.alongMax - b.alongMin + 1;
      final runLen = run.end - run.start + 1;
      final maxLen = math.max(bandLen, runLen);
      if (overlapLen > 0 && overlapLen >= maxLen * 0.6) {
        match = b;
        break;
      }
    }

    if (match != null) {
      match.alongMin = math.min(match.alongMin, run.start);
      match.alongMax = math.max(match.alongMax, run.end);
      match.crossMax = run.lineIndex;
      activeLastLine[match] = run.lineIndex;
    } else {
      final band = WallBand(
        crossMin: run.lineIndex,
        crossMax: run.lineIndex,
        alongMin: run.start,
        alongMax: run.end,
      );
      active.add(band);
      activeLastLine[band] = run.lineIndex;
    }
  }
  finished.addAll(active);

  if (rejectedOut != null) {
    rejectedOut.addAll(finished.where((b) => b.thicknessPx > maxThicknessPx));
  }
  return finished.where((b) => b.thicknessPx <= maxThicknessPx).toList();
}

/// 확정된 벽 band만으로 새 이진 마스크를 채운다 — 각 band가 차지하는
/// 실제 픽셀 사각형(along축 범위 x cross축 두께 범위)만 1로 표시한다.
/// 벽 판정을 통과하지 못한 어두운 픽셀(가구/텍스트/워터마크/해칭)은
/// 이 mask에 전혀 반영되지 않아, 방 검출(flood-fill) 단계가 실제
/// 벽에서만 막히게 한다.
Uint8List _buildWallOnlyMask(
  int w,
  int h,
  List<WallBand> horizontalBands,
  List<WallBand> verticalBands,
) {
  final mask = Uint8List(w * h);
  void fillRect(int xMin, int xMax, int yMin, int yMax) {
    final clampedYMin = math.max(0, yMin);
    final clampedYMax = math.min(h - 1, yMax);
    final clampedXMin = math.max(0, xMin);
    final clampedXMax = math.min(w - 1, xMax);
    for (var y = clampedYMin; y <= clampedYMax; y++) {
      final rowStart = y * w;
      for (var x = clampedXMin; x <= clampedXMax; x++) {
        mask[rowStart + x] = 1;
      }
    }
  }

  for (final band in horizontalBands) {
    fillRect(band.alongMin, band.alongMax, band.crossMin, band.crossMax);
  }
  for (final band in verticalBands) {
    fillRect(band.crossMin, band.crossMax, band.alongMin, band.alongMax);
  }
  return mask;
}

double _confidenceFor(WallBand band, double diagonal) {
  final length = (band.alongMax - band.alongMin).toDouble();
  final lengthRatio = diagonal > 0 ? length / diagonal : 0.0;
  final scaled = (lengthRatio * 6).clamp(0.0, 1.0);
  return 0.3 + 0.6 * scaled;
}

/// 같은 방향·같은 중심선 위의 인접한 두 band 사이 gap을 문/창 후보로
/// 추출한다. 확신이 낮으므로 항상 [FloorPlanObjectStatus.needsReview]로
/// 둔다(WO 8번).
List<OpeningCandidate> _detectOpenings({
  required List<WallBand> horizontalBands,
  required List<WallBand> verticalBands,
  required Map<String, WallBand> wallIds,
  required double thresholdDiagonal,
  required double normalizationDiagonal,
  required int idStart,
  required Point2 Function(double px, double py) toOriginalNormalized,
}) {
  final openings = <OpeningCandidate>[];
  var idCounter = idStart;
  final minGapPx = math.max(4, (thresholdDiagonal * 0.015).round());
  final maxGapPx = (thresholdDiagonal * 0.18).round();
  final idealDoorPx = thresholdDiagonal * 0.08;

  void scanGroup(List<MapEntry<String, WallBand>> group, bool horizontal) {
    final sorted = [...group]
      ..sort((a, b) => a.value.alongMin.compareTo(b.value.alongMin));
    for (var i = 0; i < sorted.length - 1; i++) {
      final a = sorted[i];
      final b = sorted[i + 1];
      if ((a.value.crossCenter - b.value.crossCenter).abs() >
          math.max(a.value.thicknessPx, b.value.thicknessPx) * 1.5) {
        continue;
      }
      final gap = b.value.alongMin - a.value.alongMax;
      if (gap < minGapPx || gap > maxGapPx) continue;

      final centerAlong = (a.value.alongMax + b.value.alongMin) / 2;
      final crossCenter = (a.value.crossCenter + b.value.crossCenter) / 2;
      final type = gap > idealDoorPx * 0.6
          ? OpeningType.door
          : OpeningType.window;
      final confidence = (1.0 - ((gap - idealDoorPx).abs() / idealDoorPx))
          .clamp(0.2, 0.7);

      // 수평 band 그룹: along축=x(→width), cross축=y(→height).
      // 수직 band 그룹: along축=y(→height), cross축=x(→width).
      final center = horizontal
          ? toOriginalNormalized(centerAlong, crossCenter)
          : toOriginalNormalized(crossCenter, centerAlong);

      openings.add(
        OpeningCandidate(
          id: 'opening-${idCounter++}',
          type: type,
          center: center,
          // estimateScaleFromDoors 등 downstream 소비자가 항상
          // "원본 이미지 대각선" 기준으로 widthNormalized를 해석하므로,
          // 회전 보정 작업 캔버스에서 계산 중이어도 정규화 기준은 항상
          // 원본 대각선([normalizationDiagonal])으로 고정한다 —
          // 회전은 등거리 변환이라 gap(픽셀)은 어느 프레임에서 재도
          // 물리적으로 같다.
          widthNormalized: gap / normalizationDiagonal,
          confidence: confidence.toDouble(),
          wallId: a.key,
          status: FloorPlanObjectStatus.needsReview,
        ),
      );
    }
  }

  final horizontalEntries = wallIds.entries
      .where((e) => horizontalBands.contains(e.value))
      .toList();
  final verticalEntries = wallIds.entries
      .where((e) => verticalBands.contains(e.value))
      .toList();
  scanGroup(horizontalEntries, true);
  scanGroup(verticalEntries, false);

  return openings;
}

// ---------------------------------------------------------------------------
// PC2 2D CAD 재조사 WO — 회전(deskew) 보정.
//
// 아래 함수들은 이 파일의 모든 "회전각만큼 좌표/픽셀을 옮기는" 계산이
// 공유하는 유일한 원시 연산([_rotateAround])과 그 위에 쌓은 두 변환
// ([_deskewPoint]/[_undoDeskewPoint], 서로 정확한 역함수)만 쓴다 — 공식을
// 여러 곳에 따로 베껴 적어 부호를 틀리는 사고를 막기 위해서다. 실제
// 정확성은 이 파일과 짝을 이루는 테스트의 왕복(원본→회전→원본) 검증으로
// 확인한다.
// ---------------------------------------------------------------------------

/// (cx,cy) 중심으로 (x,y)를 angleRad만큼(표준 수학 규약, 반시계 방향)
/// 회전한 좌표.
({double x, double y}) _rotateAround(
  double x,
  double y,
  double cx,
  double cy,
  double angleRad,
) {
  final dx = x - cx;
  final dy = y - cy;
  final cosA = math.cos(angleRad);
  final sinA = math.sin(angleRad);
  return (x: cx + dx * cosA - dy * sinA, y: cy + dx * sinA + dy * cosA);
}

/// 원본 분석 캔버스(originalW×originalH)의 한 점을, [angleRad]만큼
/// "레벨을 맞춘"(deskew) 확장 작업 캔버스(rotatedW×rotatedH) 위의
/// 위치로 옮긴다.
({double x, double y}) _deskewPoint({
  required double x,
  required double y,
  required int originalW,
  required int originalH,
  required int rotatedW,
  required int rotatedH,
  required double angleRad,
}) {
  final rotated = _rotateAround(x, y, originalW / 2, originalH / 2, -angleRad);
  return (
    x: rotated.x + (rotatedW - originalW) / 2,
    y: rotated.y + (rotatedH - originalH) / 2,
  );
}

/// [_deskewPoint]의 정확한 역함수 — 작업(회전 보정) 캔버스의 한 점을
/// 원본 분석 캔버스 좌표로 되돌린다. 벽/방/문·창 결과 좌표는 항상 이
/// 함수를 거쳐 "원본 이미지 기준"으로 반환된다.
({double x, double y}) _undoDeskewPoint({
  required double x,
  required double y,
  required int originalW,
  required int originalH,
  required int rotatedW,
  required int rotatedH,
  required double angleRad,
}) {
  final shiftedX = x - (rotatedW - originalW) / 2;
  final shiftedY = y - (rotatedH - originalH) / 2;
  return _rotateAround(
    shiftedX,
    shiftedY,
    originalW / 2,
    originalH / 2,
    angleRad,
  );
}

/// [angleRad]만큼 회전해도 원본 내용이 잘리지 않는 최소 확장 캔버스
/// 크기(표준 "rotate and expand" bounding box 공식).
({int w, int h}) _expandedCanvasSize(int w, int h, double angleRad) {
  final cosA = math.cos(angleRad).abs();
  final sinA = math.sin(angleRad).abs();
  return (w: (w * cosA + h * sinA).ceil(), h: (w * sinA + h * cosA).ceil());
}

/// [destToSource]가 계산한 원본 좌표를 양선형(bilinear) 보간으로
/// 샘플링해 (destW×destH) 크기의 새 마스크를 만든다 — 회전 보정 작업
/// 캔버스를 만들거나(원본→회전) 되돌릴(회전→원본) 때 공통으로 쓰는
/// 리샘플링.
///
/// 처음에는 최근접 이웃(nearest-neighbor)으로 샘플링했다 — 그런데
/// wallOnlyMask는 "원본→회전(검출용)→원본(방 검출용)"으로 두 번
/// 리샘플링되는데, 최근접 이웃을 두 번 거치면 특정 각도에서 모서리
/// 부근에 계단식 앨리어싱이 누적되어(테스트로 실제 확인: -20도에서
/// 벽이 4개가 아니라 21개로 잘게 쪼개짐) 짧은 잡음 조각이 여럿
/// 생겼다. 이진 마스크에 양선형 보간(주변 4픽셀의 거리 가중 평균 후
/// 0.5 문턱으로 재이진화)을 적용하면 회전된 경계가 계단이 아니라
/// 매끄러운 직선에 훨씬 가깝게 유지되어, 이 잡음이 원천적으로
/// 줄어든다.
Uint8List _resampleMask({
  required Uint8List source,
  required int sourceW,
  required int sourceH,
  required int destW,
  required int destH,
  required ({double x, double y}) Function(double destX, double destY)
  destToSource,
}) {
  final dest = Uint8List(destW * destH);
  for (var y = 0; y < destH; y++) {
    for (var x = 0; x < destW; x++) {
      final src = destToSource(x.toDouble(), y.toDouble());
      dest[y * destW + x] = _bilinearSampleMask(
        source,
        sourceW,
        sourceH,
        src.x,
        src.y,
      );
    }
  }
  return dest;
}

int _bilinearSampleMask(Uint8List mask, int w, int h, double x, double y) {
  final x0 = x.floor();
  final y0 = y.floor();
  final fx = x - x0;
  final fy = y - y0;

  int at(int xi, int yi) {
    if (xi < 0 || yi < 0 || xi >= w || yi >= h) return 0;
    return mask[yi * w + xi];
  }

  final v00 = at(x0, y0);
  final v10 = at(x0 + 1, y0);
  final v01 = at(x0, y0 + 1);
  final v11 = at(x0 + 1, y0 + 1);

  final top = v00 * (1 - fx) + v10 * fx;
  final bottom = v01 * (1 - fx) + v11 * fx;
  final value = top * (1 - fy) + bottom * fy;
  return value >= 0.5 ? 1 : 0;
}

/// 회전각 탐색 전용 — 최대 변이 이 값이 되도록 최근접 이웃으로 축소한
/// mask 사본만 있으면 된다(품질이 아니라 방향 탐색 속도가 목적).
const int _kRotationProbeMaxDimension = 220;

({Uint8List mask, int w, int h}) _downsampleMaskForProbe(
  Uint8List mask,
  int w,
  int h,
) {
  final longest = math.max(w, h);
  if (longest <= _kRotationProbeMaxDimension) return (mask: mask, w: w, h: h);
  final scale = _kRotationProbeMaxDimension / longest;
  final pw = math.max(1, (w * scale).round());
  final ph = math.max(1, (h * scale).round());
  final probe = Uint8List(pw * ph);
  for (var y = 0; y < ph; y++) {
    final sy = math.min(h - 1, (y / scale).round());
    for (var x = 0; x < pw; x++) {
      final sx = math.min(w - 1, (x / scale).round());
      probe[y * pw + x] = mask[sy * w + sx];
    }
  }
  return (mask: probe, w: pw, h: ph);
}

/// 이미지 전체에 공통으로 적용되는 지배적 회전각(도, [-45,45])을
/// 추정한다 — 촬영/스캔 과정에서 건물 구조 전체가 이미지 축과 몇 도씩
/// 어긋난 실제 평면도를 다루기 위해서다. 원본 해상도로 여러 각도를 전부
/// 시도하면 느리므로, 훨씬 작은 다운샘플 사본에서만 "어느 각도로 회전해야
/// run-length 벽 band가 가장 길게/많이 잡히는가"를 탐색한다 — 최종 검출
/// 품질이 아니라 방향만 필요하기 때문이다.
double _estimateDominantRotationDegrees(Uint8List mask, int w, int h) {
  final probe = _downsampleMaskForProbe(mask, w, h);
  final zeroScore = _rotatedAlignmentScore(probe.mask, probe.w, probe.h, 0);

  var bestAngle = 0.0;
  var bestScore = zeroScore;

  void search(double from, double to, double step) {
    var angle = from;
    while (angle <= to + 1e-9) {
      if (angle != 0) {
        final score = _rotatedAlignmentScore(
          probe.mask,
          probe.w,
          probe.h,
          angle,
        );
        if (score > bestScore) {
          bestScore = score;
          bestAngle = angle;
        }
      }
      angle += step;
    }
  }

  search(-45, 45, 3);
  final coarseBest = bestAngle;
  search(coarseBest - 2.5, coarseBest + 2.5, 0.5);

  // 개선폭이 미미하면(잡음/과적합) 회전하지 않는다 — 이미 축이 맞는
  // 도면에서 불필요한 리샘플 손실을 만들지 않기 위해서다.
  if (bestScore < zeroScore * 1.08) return 0;
  return double.parse(bestAngle.toStringAsFixed(1));
}

/// 다운샘플된 mask를 [angleDeg]만큼 회전했을 때, 행/열 방향 "어두운
/// 픽셀 개수" 투영(projection profile)의 분산 — 문서/도면 deskew에
/// 널리 쓰이는 표준 기법이다. 축이 잘 맞을수록 벽이 있는 특정 행/열에
/// 어두운 픽셀이 몰려 분산이 커지고, 축이 어긋날수록 여러 행/열에
/// 퍼져 분산이 작아진다.
///
/// 처음에는 이 파일의 실제 벽 검출 파이프라인(run-length + band
/// 병합, minRunLen/maxThicknessPx 문턱값)을 그대로 재사용해 "검출된
/// band 총 길이"를 점수로 썼다 — 그런데 회전 리샘플링이 경계를
/// 미세하게 어긋나게(aliasing) 만들면 문턱값 근처에서 band가 잘게
/// 쪼개지거나 우연히 겹쳐 총 길이가 실제보다 훨씬 크게 잡히는 경우가
/// 있었다(테스트로 확인된 실제 버그 — 완전히 축 정렬된 사각형에서도
/// 엉뚱한 각도가 더 높은 점수를 받아 벽이 83개로 깨짐). 순수 픽셀
/// 개수 분산은 문턱값/병합 같은 민감한 휴리스틱이 없어 이런 리샘플링
/// 잡음에 훨씬 안정적이다.
///
/// 회전은 원본과 같은 크기 캔버스에서(모서리는 잘려도 무방 — 탐색
/// 전용이라 실제 검출에는 쓰이지 않는다) [_deskewPoint]/
/// [_undoDeskewPoint]와 동일한 회전 방향 규약으로 계산해, 여기서 고른
/// 각도를 그대로 그 두 함수에 넘겨도 항상 같은 의미(레벨을 맞추는
/// 방향)를 갖도록 한다.
double _rotatedAlignmentScore(
  Uint8List probeMask,
  int probeW,
  int probeH,
  double angleDeg,
) {
  final Uint8List rotated;
  if (angleDeg == 0) {
    rotated = probeMask;
  } else {
    final angleRad = angleDeg * math.pi / 180;
    rotated = _resampleMask(
      source: probeMask,
      sourceW: probeW,
      sourceH: probeH,
      destW: probeW,
      destH: probeH,
      destToSource: (dx, dy) =>
          _rotateAround(dx, dy, probeW / 2, probeH / 2, angleRad),
    );
  }

  final rowSums = List<int>.filled(probeH, 0);
  final colSums = List<int>.filled(probeW, 0);
  for (var y = 0; y < probeH; y++) {
    final rowBase = y * probeW;
    for (var x = 0; x < probeW; x++) {
      if (rotated[rowBase + x] == 1) {
        rowSums[y]++;
        colSums[x]++;
      }
    }
  }
  return _variance(rowSums) + _variance(colSums);
}

double _variance(List<int> values) {
  if (values.isEmpty) return 0;
  var sum = 0.0;
  for (final v in values) {
    sum += v;
  }
  final mean = sum / values.length;
  var squaredDiff = 0.0;
  for (final v in values) {
    final d = v - mean;
    squaredDiff += d * d;
  }
  return squaredDiff / values.length;
}
