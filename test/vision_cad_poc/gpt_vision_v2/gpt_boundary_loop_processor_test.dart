// SPACE SHIFT — GPT Space Boundary Loop Recovery POC.
//
// GptBoundaryLoopProcessor 단위 테스트 — 두 개의 방이 하나의 벽을
// 공유하고, 각자 약간 다른 좌표로 그 벽을 설명하는(실제 GPT가 그럴
// 법한) 상황을 재현해 shared wall merge / space loop derivation /
// FloorDomain 재구성이 실제로 동작하는지 확인한다. 실제 이미지 없이도
// 알고리즘 자체를 검증할 수 있도록, HintedGeometryExtractor가
// 대상으로 삼을 아주 단순한 합성 이미지를 함께 사용한다.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:ason_space/vision_cad_poc/gpt_vision_v2/gpt_boundary_loop_processor.dart';
import 'package:ason_space/vision_cad_poc/gpt_vision_v2/gpt_pass_b_schema.dart';

Uint8List _buildTwoRoomImage() {
  const w = 200, h = 100;
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  final black = img.ColorRgb8(0, 0, 0);
  void rect(int x1, int y1, int x2, int y2) => img.fillRect(image, x1: x1, y1: y1, x2: x2, y2: y2, color: black);
  // exterior perimeter.
  rect(0, 0, w - 1, 3);
  rect(0, h - 4, w - 1, h - 1);
  rect(0, 0, 3, h - 1);
  rect(w - 4, 0, w - 1, h - 1);
  // shared interior wall between the two rooms at x=100.
  rect(98, 0, 101, h - 1);
  return Uint8List.fromList(img.encodePng(image));
}

GptBoundarySegment _seg(String id, double x1, double y1, double x2, double y2, GptSegmentKind kind,
        {String? sharedWith, double confidence = 0.9}) =>
    GptBoundarySegment(
      id: id,
      start: GptPixelPoint(x1, y1),
      end: GptPixelPoint(x2, y2),
      kind: kind,
      sharedWithSpaceId: sharedWith,
      confidence: confidence,
    );

void main() {
  const processor = GptBoundaryLoopProcessor();
  final imageBytes = _buildTwoRoomImage();

  test('두 공간이 공유하는 벽을 서로 다른 좌표로 설명해도 하나의 canonical wall로 병합된다', () {
    // Room A: (0,0)-(100,0)-(100,100)-(0,100).
    final loopA = GptSpaceBoundaryLoop(
      spaceId: 'A',
      confidence: 0.9,
      closed: true,
      segments: [
        _seg('a1', 0, 0, 100, 0, GptSegmentKind.exterior),
        _seg('a2', 100, 0, 100, 100, GptSegmentKind.wall, sharedWith: 'B'),
        _seg('a3', 100, 100, 0, 100, GptSegmentKind.exterior),
        _seg('a4', 0, 100, 0, 0, GptSegmentKind.exterior),
      ],
    );
    // Room B: 같은 공유벽을 살짝 다른 좌표(101,2)-(99,98)로 설명.
    final loopB = GptSpaceBoundaryLoop(
      spaceId: 'B',
      confidence: 0.9,
      closed: true,
      segments: [
        _seg('b1', 101, 2, 200, 0, GptSegmentKind.exterior),
        _seg('b2', 200, 0, 200, 100, GptSegmentKind.exterior),
        _seg('b3', 200, 100, 99, 98, GptSegmentKind.exterior),
        _seg('b4', 99, 98, 101, 2, GptSegmentKind.wall, sharedWith: 'A'),
      ],
    );

    final result = processor.process(
      passB: GptPassBResponse(spaceBoundaryLoops: [loopA, loopB]),
      imageWidthPx: 200,
      imageHeightPx: 100,
      imageBytes: imageBytes,
    );

    expect(result.closedLoopCount, 2);
    final wallA = result.spaceLoops.firstWhere((s) => s.spaceId == 'A').canonicalWallIds;
    final wallB = result.spaceLoops.firstWhere((s) => s.spaceId == 'B').canonicalWallIds;
    // 공유벽이 병합되었다면 두 공간의 canonicalWallIds 교집합이 1개 있어야 한다.
    final shared = wallA.toSet().intersection(wallB.toSet());
    expect(shared, hasLength(1));

    final sharedWall = result.canonicalWalls.firstWhere((w) => w.id == shared.first);
    expect(sharedWall.spaceIds, {'A', 'B'});
  });

  test('exterior 표시된 canonical wall만으로 FloorDomain이 재구성된다', () {
    final loopA = GptSpaceBoundaryLoop(
      spaceId: 'A',
      confidence: 0.9,
      closed: true,
      segments: [
        _seg('a1', 0, 0, 100, 0, GptSegmentKind.exterior),
        _seg('a2', 100, 0, 100, 100, GptSegmentKind.wall, sharedWith: 'B'),
        _seg('a3', 100, 100, 0, 100, GptSegmentKind.exterior),
        _seg('a4', 0, 100, 0, 0, GptSegmentKind.exterior),
      ],
    );
    final loopB = GptSpaceBoundaryLoop(
      spaceId: 'B',
      confidence: 0.9,
      closed: true,
      segments: [
        _seg('b1', 100, 0, 200, 0, GptSegmentKind.exterior),
        _seg('b2', 200, 0, 200, 100, GptSegmentKind.exterior),
        _seg('b3', 200, 100, 100, 100, GptSegmentKind.exterior),
        _seg('b4', 100, 100, 100, 0, GptSegmentKind.wall, sharedWith: 'A'),
      ],
    );

    final result = processor.process(
      passB: GptPassBResponse(spaceBoundaryLoops: [loopA, loopB]),
      imageWidthPx: 200,
      imageHeightPx: 100,
      imageBytes: imageBytes,
    );

    expect(result.floorDomainClosed, isTrue);
    expect(result.model.floorDomain, isNotNull);
    expect(result.model.floorDomain!.length, greaterThanOrEqualTo(4));
  });

  test('순서가 닫히지 않는 segment 목록은 bbox로 대체되지 않고 reviewNeeded로 표시된다', () {
    final brokenLoop = GptSpaceBoundaryLoop(
      spaceId: 'C',
      confidence: 0.9,
      closed: true,
      segments: [
        _seg('c1', 0, 0, 50, 0, GptSegmentKind.exterior),
        _seg('c2', 50, 0, 50, 50, GptSegmentKind.exterior),
        // c3가 (50,50)에서 시작하지 않고 멀리 떨어진 곳에서 시작 — 안 닫힘.
        _seg('c3', 150, 150, 0, 150, GptSegmentKind.exterior),
      ],
    );

    final result = processor.process(
      passB: GptPassBResponse(spaceBoundaryLoops: [brokenLoop]),
      imageWidthPx: 200,
      imageHeightPx: 200,
      imageBytes: imageBytes,
    );

    final spaceC = result.model.spaces.single;
    expect(spaceC.closed, isFalse);
    expect(spaceC.reviewNeeded, isTrue);
    expect(spaceC.polygon, isEmpty);
  });

  test('공유벽이 실제 이미지 픽셀로 refine되어 delta/confidence가 기록된다', () {
    final loopA = GptSpaceBoundaryLoop(
      spaceId: 'A',
      confidence: 0.9,
      closed: true,
      segments: [
        _seg('a1', 0, 0, 100, 0, GptSegmentKind.exterior),
        _seg('a2', 105, 5, 105, 95, GptSegmentKind.wall), // 실제(100)보다 살짝 어긋난 hint.
        _seg('a3', 100, 100, 0, 100, GptSegmentKind.exterior),
        _seg('a4', 0, 100, 0, 0, GptSegmentKind.exterior),
      ],
    );
    final result = processor.process(
      passB: GptPassBResponse(spaceBoundaryLoops: [loopA]),
      imageWidthPx: 200,
      imageHeightPx: 100,
      imageBytes: imageBytes,
    );
    final wall = result.canonicalWalls.firstWhere((w) => (w.start.x - w.end.x).abs() < 1 && w.start.x > 50);
    expect(wall.refinedDeltaPx, isNotNull);
    expect(wall.geometryConfidence, isNotNull);
  });
}
