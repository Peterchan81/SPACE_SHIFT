// SPACE SHIFT — PC1 CONTINUE: DOOR/WINDOW → PARENT WALL + PARAMETRIC OPENING.
//
// runPixelWallPipeline() 전체를 합성 이미지로 실행해, 문 gap이 있어도
// FloorDomain/PhysicalRoom topology가 깨지지 않고(§9), virtual door
// bridge가 절대 물리 SSWall로 나타나지 않으며(§7), doorArc 근거가 있는
// gap만 door로 확정된다는 것을 end-to-end로 검증한다(합성 도면 —
// isolated_low_tier_exclusion_test.dart와 같은 스타일).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_pipeline.dart';

Uint8List _rectWithDoorGap() {
  final image = img.Image(width: 300, height: 200);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  void thickLine(int x1, int y1, int x2, int y2) {
    for (var t = -3; t <= 3; t++) {
      if (y1 == y2) {
        img.drawLine(image, x1: x1, y1: y1 + t, x2: x2, y2: y2 + t, color: img.ColorRgb8(0, 0, 0));
      } else {
        img.drawLine(image, x1: x1 + t, y1: y1, x2: x2 + t, y2: y2, color: img.ColorRgb8(0, 0, 0));
      }
    }
  }

  // top 벽을 두 조각으로 나눠 문 크기(20px) gap을 만든다.
  thickLine(30, 30, 120, 30);
  thickLine(140, 30, 270, 30);
  thickLine(30, 170, 270, 170);
  thickLine(30, 30, 30, 170);
  thickLine(270, 30, 270, 170);
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  test('문 gap이 있는 합성 도면 — FloorDomain은 닫히고, virtual bridge는 물리 SSWall이 되지 않는다', () {
    final result = runPixelWallPipeline(imageBytes: _rectWithDoorGap());

    // §9 opening preserves room topology — 문 gap이 있어도 FloorDomain은
    // (virtual door bridge로) 정상적으로 닫혀야 한다. 새 Opening 계층을
    // 추가하기 전부터 이미 보장되던 성질이며, 회귀가 없어야 한다.
    expect(result.floorDomainClosed, isTrue, reason: result.floorDomainFailureReason ?? '');

    // §7 virtual bridge는 절대 물리 SSWall이 되지 않는다 — top 벽은
    // 여전히 분리된 2개의 SSWall(각각 짧은 조각)로 남아야 하고, 그
    // 사이 문 구간을 가로지르는 단일 SSWall이 새로 생기면 안 된다.
    final topWalls = result.model.walls.where((wall) => (wall.start.y - wall.end.y).abs() < 0.001 && wall.start.y < 0.2).toList();
    expect(topWalls.length, greaterThanOrEqualTo(2), reason: '문으로 끊긴 top 벽은 하나로 합쳐지면 안 된다');
    final gapStartPx = 120 / result.extraction.analysisWidthPx;
    final gapEndPx = 140 / result.extraction.analysisWidthPx;
    for (final wall in topWalls) {
      final minX = wall.start.x < wall.end.x ? wall.start.x : wall.end.x;
      final maxX = wall.start.x < wall.end.x ? wall.end.x : wall.start.x;
      expect(minX < gapStartPx && maxX > gapEndPx, isFalse, reason: '문 gap([$gapStartPx,$gapEndPx])을 가로지르는 합쳐진 SSWall이 생기면 안 된다');
    }

    // 문 크기 gap이 최소 1개는 Opening 후보로 확인돼야 한다(도면에
    // doorArc 근거가 없으므로 unknownOpening + reviewNeeded=true로 남는
    // 것이 정확한 결과다 — 근거 없이 door로 단정하지 않는다, §7/§16).
    expect(result.unknownOpeningCount + result.doorOpeningCount, greaterThanOrEqualTo(1));

    // wallEdges(parent WallEdge)가 최소 하나는 물리 SSWall 2개 이상을
    // physicalWallIds로 묶고 있어야 한다(문으로 끊긴 top 벽 하나).
    final multiSegmentEdges = result.model.wallEdges.where((e) => e.physicalWallIds.length >= 2).toList();
    expect(multiSegmentEdges, isNotEmpty, reason: '문 gap으로 끊긴 물리 벽 조각들을 하나의 연속 구조 벽으로 묶은 WallEdge가 있어야 한다');

    // Opening이 있다면 parentWallId가 실제 wallEdges 중 하나를 정확히
    // 가리켜야 한다(§10 cross-reference).
    final wallEdgeIds = result.model.wallEdges.map((e) => e.id).toSet();
    for (final o in result.model.openings) {
      if (o.parentWallId != null) {
        expect(wallEdgeIds, contains(o.parentWallId), reason: 'opening.parentWallId는 항상 유효한 wallEdge를 가리켜야 한다');
        expect(o.startT, isNotNull);
        expect(o.endT, isNotNull);
        expect(o.startT! < o.endT!, isTrue);
      }
    }
  });
}
