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
//   4. 이진화된 "어두운 픽셀"을 행/열 방향으로 run-length 스캔해 직선 후보 추출
//   5. 인접한 run을 겹침 기준으로 병합해 벽 band(두께 포함)로 그룹화
//   6. 같은 direction·같은 중심선의 인접 band 사이 gap을 문/창 후보로 추출
//   7. (2단계 isolate 호출) 벽이 아닌(밝은) 영역을 flood fill로 연결
//      요소를 찾아 이미지 경계에 닿지 않는 요소를 방 후보(경계 사각형)로 추출
//
// 이번 1차 구현은 Hough 변환이 아니라 "run-length 기반 축 정렬 직선 추출"이다
// — 평면도가 대체로 수평/수직 벽으로 이루어진다는 전제를 쓴다. 사선 벽은
// 이번 단계에서 검출하지 못한다(한계로 보고).

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
      rawHorizontalRuns = 0,
      rawVerticalRuns = 0,
      elapsedMs = 0;

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
  final int rawHorizontalRuns;
  final int rawVerticalRuns;
  final int elapsedMs;

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

  final threshold = _otsuThreshold(histogram, w * h);
  final mask = Uint8List(w * h);
  for (var i = 0; i < mask.length; i++) {
    // Otsu 임계값 t는 "값 <= t가 배경(어두운 픽셀) 클래스"로 누적
    // 계산되므로(_otsuThreshold의 weightBackground 누적과 일치해야 함),
    // 여기서도 <=로 나눠야 한다. <로 나누면 순수 이진(0/255) 이미지처럼
    // 임계값이 0으로 나올 때 어두운 픽셀이 전부 빠지는 문제가 있었다.
    mask[i] = luminance[i] <= threshold ? 1 : 0;
  }

  final diagonal = math.sqrt(w * w + h * h);
  final minRunLen = diagonal * 0.02 < 6 ? 6 : (diagonal * 0.02).round();

  final rawHorizontal = _scanRuns(
    mask,
    w,
    h,
    horizontal: true,
    minRunLen: minRunLen,
  );
  final rawVertical = _scanRuns(
    mask,
    w,
    h,
    horizontal: false,
    minRunLen: minRunLen,
  );

  final maxThicknessPx = (math.max(w, h) * 0.06).round();
  final horizontalBands = _mergeRunsToBands(
    rawHorizontal,
    maxThicknessPx: maxThicknessPx,
  );
  final verticalBands = _mergeRunsToBands(
    rawVertical,
    maxThicknessPx: maxThicknessPx,
  );

  // 검출된 모든 벽 band를 감싸는 bounding box — 외벽 후보 판정 기준.
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
  final boundaryTolerance = math.max(w, h) * 0.03;

  var idCounter = 0;
  final walls = <WallSegment>[];
  final wallBandById = <String, _WallBand>{};

  for (final band in horizontalBands) {
    final id = 'wall-${idCounter++}';
    final isExterior =
        band.crossCenter <= minY + boundaryTolerance ||
        band.crossCenter >= maxY - boundaryTolerance;
    walls.add(
      WallSegment(
        id: id,
        start: Point2(band.alongMin / w, band.crossCenter / h),
        end: Point2(band.alongMax / w, band.crossCenter / h),
        // 3D 근본 수정 WO(2번, 면적/치수 재추적) — CadWall.boundaryPolygon은
        // 이 값을 start/end와 "같은 축의 정규화 단위"로 취급해 그대로
        // y좌표에 더한다(수평 벽은 두께 offset이 y축에만 실린다). 그런데
        // 예전 코드는 diagonal 기준 비율을 넣고 있었다 — 정사각형이
        // 아닌 이미지에서는 diagonal ≠ height라 벽 두께가 실제보다
        // 얇거나 두껍게 재구성됐다(전형적으로 h/diagonal배, 대략
        // 0.6~0.8배 과소). 수평 벽의 두께는 세로(y) 방향 픽셀 폭이므로
        // h로 정규화해야 이후 mm 변환이 정확하다.
        thicknessNormalized: band.thicknessPx / h,
        confidence: _confidenceFor(band, diagonal),
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
    walls.add(
      WallSegment(
        id: id,
        start: Point2(band.crossCenter / w, band.alongMin / h),
        end: Point2(band.crossCenter / w, band.alongMax / h),
        // 위와 대칭 — 수직 벽의 두께 offset은 x축에 실리므로 가로(x)
        // 방향 픽셀 폭 기준인 w로 정규화한다.
        thicknessNormalized: band.thicknessPx / w,
        confidence: _confidenceFor(band, diagonal),
        isExterior: isExterior,
      ),
    );
    wallBandById[id] = band;
  }

  final openings = _detectOpenings(
    horizontalBands: horizontalBands,
    verticalBands: verticalBands,
    wallIds: wallBandById,
    diagonal: diagonal,
    width: w,
    height: h,
    idStart: idCounter,
  );

  // Windows 실기 FAIL 재조사(2D CAD reconstruction) — 방 검출(stage 2)에
  // 넘기는 mask를 이전에는 Otsu 이진화 직후의 "raw 어두운 픽셀" 그대로
  // 썼다. 가구 아이콘(옷장 내부 해칭, 위생기구 체크무늬), 치수/텍스트
  // 라벨, 워터마크처럼 "벽으로 확정되지 않은" 어두운 픽셀도 전부 이
  // raw mask에는 그대로 남아 있어, flood-fill 연결성을 끊어 실제로는
  // 하나인 방을 여러 개의 작은 "방"으로 잘못 쪼갰다(실기 재현: 14개
  // 공간 중 다수가 실제로는 존재하지 않는 노이즈 분할). 벽으로 실제
  // 확정된 band(길이/두께 필터를 통과한 것)만으로 다시 채운 mask를
  // 써야, 벽 판정에서 걸러진 노이즈가 방을 쪼개지 못한다.
  final wallOnlyMask = _buildWallOnlyMask(w, h, horizontalBands, verticalBands);

  stopwatch.stop();
  return WallStageResult.success(
    sourceWidthPx: sourceWidth,
    sourceHeightPx: sourceHeight,
    analysisWidthPx: w,
    analysisHeightPx: h,
    mask: wallOnlyMask,
    walls: walls,
    openings: openings,
    rawHorizontalRuns: rawHorizontal.length,
    rawVerticalRuns: rawVertical.length,
    elapsedMs: stopwatch.elapsedMilliseconds,
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
int _otsuThreshold(List<int> histogram, int totalPixels) {
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

class _RawRun {
  const _RawRun(this.lineIndex, this.start, this.end);
  final int lineIndex;
  final int start;
  final int end;
}

/// 이진 마스크를 행(수평) 또는 열(수직) 방향으로 스캔해 연속된 "어두운
/// 픽셀" run을 찾는다 — run-length 기반 축 정렬 직선 후보 추출.
List<_RawRun> _scanRuns(
  Uint8List mask,
  int w,
  int h, {
  required bool horizontal,
  required int minRunLen,
}) {
  final runs = <_RawRun>[];
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
        if (len >= minRunLen) runs.add(_RawRun(line, runStart, i - 1));
        runStart = -1;
      }
    }
  }
  return runs;
}

/// 벽 band — 서로 인접한 여러 줄(행 또는 열)의 run이 겹쳐 병합된 결과.
/// [crossCenter]는 두께 방향의 중심선, [thicknessPx]는 병합된 줄 수(두께).
class _WallBand {
  _WallBand({
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
List<_WallBand> _mergeRunsToBands(
  List<_RawRun> runs, {
  required int maxThicknessPx,
}) {
  final sorted = [...runs]..sort((a, b) => a.lineIndex.compareTo(b.lineIndex));
  final active = <_WallBand>[];
  final activeLastLine = <_WallBand, int>{};
  final finished = <_WallBand>[];

  for (final run in sorted) {
    active.removeWhere((b) {
      final last = activeLastLine[b]!;
      if (run.lineIndex - last > 1) {
        finished.add(b);
        return true;
      }
      return false;
    });

    _WallBand? match;
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
      final band = _WallBand(
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
  List<_WallBand> horizontalBands,
  List<_WallBand> verticalBands,
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

double _confidenceFor(_WallBand band, double diagonal) {
  final length = (band.alongMax - band.alongMin).toDouble();
  final lengthRatio = diagonal > 0 ? length / diagonal : 0.0;
  final scaled = (lengthRatio * 6).clamp(0.0, 1.0);
  return 0.3 + 0.6 * scaled;
}

/// 같은 방향·같은 중심선 위의 인접한 두 band 사이 gap을 문/창 후보로
/// 추출한다. 확신이 낮으므로 항상 [FloorPlanObjectStatus.needsReview]로
/// 둔다(WO 8번).
List<OpeningCandidate> _detectOpenings({
  required List<_WallBand> horizontalBands,
  required List<_WallBand> verticalBands,
  required Map<String, _WallBand> wallIds,
  required double diagonal,
  required int width,
  required int height,
  required int idStart,
}) {
  final openings = <OpeningCandidate>[];
  var idCounter = idStart;
  final minGapPx = math.max(4, (diagonal * 0.015).round());
  final maxGapPx = (diagonal * 0.18).round();
  final idealDoorPx = diagonal * 0.08;

  void scanGroup(List<MapEntry<String, _WallBand>> group, bool horizontal) {
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
          ? Point2(centerAlong / width, crossCenter / height)
          : Point2(crossCenter / width, centerAlong / height);

      openings.add(
        OpeningCandidate(
          id: 'opening-${idCounter++}',
          type: type,
          center: center,
          widthNormalized: gap / diagonal,
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
