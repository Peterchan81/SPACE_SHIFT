import 'dart:math' as math;

import '../models/cad_floor_plan.dart';
import '../models/floor_plan_geometry.dart';

/// SS CAD TEST — CAD Editor WO §4 (DXF IMPORT).
///
/// [E2eDxfExporter](e2e_dxf_exporter.dart)가 만드는 DXF의 역방향 — 그
/// 파일이 쓰는 5개 layer(SS-EXTERIOR-WALL/SS-INTERIOR-WALL/SS-SPACE/
/// SS-DOOR/SS-WINDOW)의 LINE 엔티티만 이해한다. 이 앱이 만들지 않은
/// DXF(외부 CAD 파일)라도, 이 다섯 layer 이름의 LINE만 있으면 그대로
/// 읽는다 — 지원하지 않는 entity/layer 때문에 전체 import를 실패시키지
/// 않고 [DxfImportResult.unsupportedEntityCount]/[unsupportedLayerCount]
/// 로 보고한다(§4 "unsupported/reviewNeeded로 표시").
///
/// DXF 좌표는 이미 실측 mm(또는 UNSCALED 정규화 좌표)다 — 원본 사진이
/// 없으므로 [CadFloorPlan.sourceWidthPx]/[sourceHeightPx]는 이 DXF
/// 자체의 bounding box에서 새로 만든다(mmPerPixel=1.0 정확히 — 그래야
/// 재-export 시 mm 값이 소수 오차 없이 그대로 복원된다). 원점이 원본과
/// 다를 수 있지만(전체를 한 방향으로 평행이동한 것뿐) 상대 위치/길이/폭은
/// 정확히 보존된다.
class DxfImportResult {
  const DxfImportResult.success({
    required this.plan,
    required this.scale,
    this.warnings = const [],
    this.unsupportedEntityCount = 0,
    this.unsupportedLayerCount = 0,
  }) : success = true,
       failureMessage = null;

  const DxfImportResult.failure(this.failureMessage)
    : success = false,
      plan = null,
      scale = null,
      warnings = const [],
      unsupportedEntityCount = 0,
      unsupportedLayerCount = 0;

  final bool success;
  final CadFloorPlan? plan;
  final FloorPlanScale? scale;
  final String? failureMessage;

  /// 사용자에게 보여줄 수 있는, 실패는 아니지만 알아야 할 사항(예: "이
  /// 파일은 mm 단위가 아닙니다", "닫히지 않은 방 폴리곤 N개").
  final List<String> warnings;

  /// LINE이 아닌 entity(POLYLINE/CIRCLE/TEXT/ARC 등) 개수 — 조용히
  /// 무시하지 않고 개수로 보고한다.
  final int unsupportedEntityCount;

  /// 5개 지원 layer 외의 layer를 가진 LINE 개수.
  final int unsupportedLayerCount;
}

const _kWallExteriorLayer = 'SS-EXTERIOR-WALL';
const _kWallInteriorLayer = 'SS-INTERIOR-WALL';
const _kSpaceLayer = 'SS-SPACE';
const _kDoorLayer = 'SS-DOOR';
const _kWindowLayer = 'SS-WINDOW';
const _kSupportedLayers = {_kWallExteriorLayer, _kWallInteriorLayer, _kSpaceLayer, _kDoorLayer, _kWindowLayer};

class _RawLine {
  _RawLine(this.layer, this.x1, this.y1, this.x2, this.y2);
  final String layer;
  final double x1, y1, x2, y2;
}

/// [dxfContent]를 파싱해 [CadFloorPlan]을 복원한다. 실패하면(빈 파일,
/// LINE이 하나도 없음, 파싱 불가) [DxfImportResult.failure]를 돌려준다 —
/// 절대 예외를 던지지 않는다(호출부가 화면에서 안전하게 처리할 수
/// 있도록, 이 프로젝트의 기존 관례와 동일).
DxfImportResult importDxf(String dxfContent) {
  List<String> lines;
  try {
    lines = dxfContent.split('\n').map((l) => l.trim()).toList();
  } catch (_) {
    return const DxfImportResult.failure('DXF 파일 내용을 읽을 수 없습니다.');
  }

  final isUnscaled = dxfContent.contains('UNSCALED');

  final rawLines = <_RawLine>[];
  var unsupportedEntityCount = 0;
  var unsupportedLayerCount = 0;

  for (var i = 0; i < lines.length - 1; i++) {
    if (lines[i] != '0') continue;
    final entityType = lines[i + 1];

    // 이 엔티티의 그룹코드/값 쌍을 전부 소비해 다음 최상위 '0'까지
    // 건너뛴다 — LINE이 아닌 엔티티(TABLE/LAYER/ENDTAB 등)라도 그
    // 본문 값 중 하나가 우연히 "0"이면(예: LAYER의 flag 필드) 그 줄을
    // 새 엔티티 시작으로 잘못 해석해 파싱 전체가 어긋나는 문제를
    // 막는다 — 모든 엔티티에 동일하게 적용한다.
    var j = i + 2;
    String? layer;
    double? x1, y1, x2, y2;
    while (j + 1 < lines.length && lines[j] != '0') {
      final code = lines[j];
      final value = lines[j + 1];
      if (entityType == 'LINE') {
        switch (code) {
          case '8':
            layer = value;
          case '10':
            x1 = double.tryParse(value);
          case '20':
            y1 = double.tryParse(value);
          case '11':
            x2 = double.tryParse(value);
          case '21':
            y2 = double.tryParse(value);
        }
      }
      j += 2;
    }
    i = j - 1;

    if (entityType == 'ENDSEC' ||
        entityType == 'EOF' ||
        entityType == 'SECTION' ||
        entityType == 'ENDTAB' ||
        entityType == 'TABLE' ||
        entityType == 'LAYER' ||
        entityType.isEmpty) {
      continue;
    }
    if (entityType != 'LINE') {
      // 실제 도형 엔티티(POLYLINE/CIRCLE/ARC/TEXT 등)만 "지원 안 함"으로
      // 센다 — 조용히 삭제하지 않는다.
      unsupportedEntityCount++;
      continue;
    }

    if (layer == null || x1 == null || y1 == null || x2 == null || y2 == null) {
      unsupportedEntityCount++;
      continue;
    }
    if (!_kSupportedLayers.contains(layer)) {
      unsupportedLayerCount++;
      continue;
    }
    rawLines.add(_RawLine(layer, x1, y1, x2, y2));
  }

  if (rawLines.isEmpty) {
    return const DxfImportResult.failure('이 DXF 파일에서 인식할 수 있는 벽/방/문/창 선을 찾지 못했습니다.');
  }

  // DXF 관례(Y 위로 증가)를 이미지 좌표(Y 아래로 증가)로 되돌린다 —
  // E2eDxfExporter.toUnits()의 정확한 역함수.
  double imgY(double dxfY) => isUnscaled ? dxfY : -dxfY;
  double imgX(double dxfX) => dxfX;

  var minX = double.infinity, minY = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity;
  for (final l in rawLines) {
    for (final (x, y) in [(imgX(l.x1), imgY(l.y1)), (imgX(l.x2), imgY(l.y2))]) {
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
  }
  // 벽 하나가 정확히 수직/수평이면 그 축의 범위가 0인 것이 정상이다
  // (예: 벽 하나만 있는 도면, 전부 같은 x좌표의 세로 벽). 실패로 보지
  // 않고 여백 최소값(1.0)으로 대체한다 — 두 축이 "동시에" 0일 때만
  // (모든 점이 정말 한 점에 겹침) 좌표를 복원할 수 없는 것으로 본다.
  final rawRangeX = maxX - minX;
  final rawRangeY = maxY - minY;
  if (rawRangeX <= 0 && rawRangeY <= 0) {
    return const DxfImportResult.failure('DXF의 도형 좌표 범위가 올바르지 않습니다(모든 점이 한 곳에 겹쳐 있음).');
  }
  final rangeX = rawRangeX > 0 ? rawRangeX : 1.0;
  final rangeY = rawRangeY > 0 ? rawRangeY : 1.0;

  final sourceWidthPx = rangeX.ceil().clamp(1, 1 << 30);
  final sourceHeightPx = rangeY.ceil().clamp(1, 1 << 30);

  Point2 toNormalized(double dxfX, double dxfY) {
    final x = imgX(dxfX);
    final y = imgY(dxfY);
    return Point2((x - minX) / sourceWidthPx, (y - minY) / sourceHeightPx);
  }

  final wallLines = <_RawLine>[];
  final spaceLines = <_RawLine>[];
  final doorLines = <_RawLine>[];
  final windowLines = <_RawLine>[];
  for (final l in rawLines) {
    switch (l.layer) {
      case _kWallExteriorLayer:
      case _kWallInteriorLayer:
        wallLines.add(l);
      case _kSpaceLayer:
        spaceLines.add(l);
      case _kDoorLayer:
        doorLines.add(l);
      case _kWindowLayer:
        windowLines.add(l);
    }
  }

  final walls = <CadWall>[
    for (var k = 0; k < wallLines.length; k++)
      CadWall(
        id: 'imported-wall-$k',
        start: toNormalized(wallLines[k].x1, wallLines[k].y1),
        end: toNormalized(wallLines[k].x2, wallLines[k].y2),
        // DXF는 벽 두께를 실선 하나로만 표현해 원래 두께 정보가 없다 —
        // 지어내지 않고 이 앱의 기존 기본값(0.01)을 그대로 쓴다.
        thicknessNormalized: 0.01,
        wallType: wallLines[k].layer == _kWallExteriorLayer ? CadWallType.exterior : CadWallType.interior,
        confidence: 1.0,
        source: CadElementSource.userEdited,
      ),
  ];

  Point2 midpoint(_RawLine l) => toNormalized((l.x1 + l.x2) / 2, (l.y1 + l.y2) / 2);
  double lengthPxOf(_RawLine l, Point2 a, Point2 b) {
    final dx = (b.x - a.x) * sourceWidthPx;
    final dy = (b.y - a.y) * sourceHeightPx;
    return math.sqrt(dx * dx + dy * dy);
  }

  double pointToWallDistancePx(Point2 p, CadWall wall) {
    final pxPx = p.x * sourceWidthPx, pyPx = p.y * sourceHeightPx;
    final axPx = wall.start.x * sourceWidthPx, ayPx = wall.start.y * sourceHeightPx;
    final bxPx = wall.end.x * sourceWidthPx, byPx = wall.end.y * sourceHeightPx;
    final abx = bxPx - axPx, aby = byPx - ayPx;
    final abLenSq = abx * abx + aby * aby;
    if (abLenSq <= 0) return math.sqrt(math.pow(pxPx - axPx, 2) + math.pow(pyPx - ayPx, 2));
    final t = (((pxPx - axPx) * abx + (pyPx - ayPx) * aby) / abLenSq).clamp(0.0, 1.0);
    final projX = axPx + t * abx, projY = ayPx + t * aby;
    return math.sqrt(math.pow(pxPx - projX, 2) + math.pow(pyPx - projY, 2));
  }

  List<CadOpening> buildOpenings(List<_RawLine> lines, OpeningType type, int idOffset) {
    final result = <CadOpening>[];
    for (var k = 0; k < lines.length; k++) {
      final l = lines[k];
      final center = midpoint(l);
      final startN = toNormalized(l.x1, l.y1);
      final endN = toNormalized(l.x2, l.y2);
      final lengthPx = lengthPxOf(l, startN, endN);
      final diagonalPx = math.sqrt(sourceWidthPx * sourceWidthPx + sourceHeightPx * sourceHeightPx);

      String? nearestWallId;
      var bestDistPx = double.infinity;
      for (final wall in walls) {
        final d = pointToWallDistancePx(center, wall);
        if (d < bestDistPx) {
          bestDistPx = d;
          nearestWallId = wall.id;
        }
      }
      // 벽 두께 근처(수십 px)에 있을 때만 그 벽에 anchor한다 — 임의로
      // 먼 벽에 잇지 않는다(§2 원칙과 동일).
      final anchored = nearestWallId != null && bestDistPx <= 30.0;

      result.add(
        CadOpening(
          id: 'imported-${type.name}-${idOffset + k}',
          type: type,
          center: center,
          widthNormalized: diagonalPx > 0 ? lengthPx / diagonalPx : 0.02,
          confidence: 1.0,
          wallId: anchored ? nearestWallId : null,
          source: CadElementSource.userEdited,
          reviewNeeded: !anchored,
          reviewReasons: anchored ? const [] : const ['가까운 벽을 찾지 못해 자동으로 연결하지 않음 — 확인 필요'],
        ),
      );
    }
    return result;
  }

  final openings = [
    ...buildOpenings(doorLines, OpeningType.door, 0),
    ...buildOpenings(windowLines, OpeningType.window, doorLines.length),
  ];

  // 방(SS-SPACE) 폴리곤 재구성 — 같은 끝점을 공유하는 선분을 그리디하게
  // 이어 붙인다. E2eDxfExporter는 방 하나의 변을 항상 순서대로(닫힌
  // loop) 내보내므로, 서로 다른 방의 변끼리는 끝점을 공유하지 않는다는
  // 전제로 충분하다 — 새 topology 알고리즘을 만들지 않는다.
  final rooms = <CadRoom>[];
  final usedSpace = List<bool>.filled(spaceLines.length, false);
  var roomIndex = 0;
  for (var start = 0; start < spaceLines.length; start++) {
    if (usedSpace[start]) continue;
    final chain = <Point2>[toNormalized(spaceLines[start].x1, spaceLines[start].y1), toNormalized(spaceLines[start].x2, spaceLines[start].y2)];
    usedSpace[start] = true;
    var extended = true;
    while (extended) {
      extended = false;
      final tail = chain.last;
      for (var k = 0; k < spaceLines.length; k++) {
        if (usedSpace[k]) continue;
        final a = toNormalized(spaceLines[k].x1, spaceLines[k].y1);
        final b = toNormalized(spaceLines[k].x2, spaceLines[k].y2);
        const eps = 1e-6;
        if ((a.x - tail.x).abs() < eps && (a.y - tail.y).abs() < eps) {
          chain.add(b);
          usedSpace[k] = true;
          extended = true;
          break;
        } else if ((b.x - tail.x).abs() < eps && (b.y - tail.y).abs() < eps) {
          chain.add(a);
          usedSpace[k] = true;
          extended = true;
          break;
        }
      }
    }
    // 닫힌 loop면 마지막에 첫 점과 중복되는 점을 뺀다.
    final polygon = chain.length > 1 && (chain.first.x - chain.last.x).abs() < 1e-6 && (chain.first.y - chain.last.y).abs() < 1e-6
        ? chain.sublist(0, chain.length - 1)
        : chain;
    if (polygon.length < 3) continue;
    var area = 0.0;
    for (var k = 0; k < polygon.length; k++) {
      final p1 = polygon[k];
      final p2 = polygon[(k + 1) % polygon.length];
      area += p1.x * p2.y - p2.x * p1.y;
    }
    rooms.add(
      CadRoom(
        id: 'imported-room-${roomIndex++}',
        polygon: polygon,
        areaNormalized: area.abs() / 2,
        confidence: 1.0,
        source: CadElementSource.userEdited,
      ),
    );
  }

  final plan = CadFloorPlan(
    sourceWidthPx: sourceWidthPx,
    sourceHeightPx: sourceHeightPx,
    walls: walls,
    openings: openings,
    rooms: rooms,
    warnings: [
      if (isUnscaled) '이 DXF는 실제 mm 단위가 아닌 정규화 좌표(UNSCALED)로 내보내진 파일입니다 — 치수를 신뢰할 수 없습니다.',
      if (unsupportedEntityCount > 0) '지원하지 않는 entity $unsupportedEntityCount개를 건너뛰었습니다(LINE만 지원).',
      if (unsupportedLayerCount > 0) '지원하지 않는 layer의 선 $unsupportedLayerCount개를 건너뛰었습니다.',
      for (final o in openings)
        if (o.reviewNeeded) ...o.reviewReasons,
    ],
  );

  final scale = isUnscaled
      ? null
      : FloorPlanScale(
          mmPerPixel: 1.0,
          referenceStart: const Point2(0, 0),
          referenceEnd: Point2(1, 0),
          referenceLengthMm: sourceWidthPx.toDouble(),
          source: ScaleSource.drawingDimension,
        );

  return DxfImportResult.success(
    plan: plan,
    scale: scale,
    warnings: plan.warnings,
    unsupportedEntityCount: unsupportedEntityCount,
    unsupportedLayerCount: unsupportedLayerCount,
  );
}
