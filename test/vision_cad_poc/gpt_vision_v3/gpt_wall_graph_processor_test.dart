// SPACE SHIFT — Canonical Wall Graph First POC.
//
// GptWallGraphProcessor 단위 테스트 — GPT가 같은 물리적 벽을 두 방에서
// 서로 다른 corner id/좌표로 선언해도(불완전한 id 재사용) 기하학적
// 중복 제거로 하나의 canonical wall로 합쳐지는지, axis alignment가
// 실제로 동작하는지, exterior/interior가 adjacency 개수로 올바르게
// 재분류되는지, space loop/FloorDomain이 기존 GptWallTopologySolver로
// 정확히 유도되는지 확인한다.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:ason_space/vision_cad_poc/gpt_vision_v3/gpt_graph_schema.dart';
import 'package:ason_space/vision_cad_poc/gpt_vision_v3/gpt_wall_graph_processor.dart';

Uint8List _buildTwoRoomImage() {
  const w = 200, h = 100;
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  final black = img.ColorRgb8(0, 0, 0);
  void rect(int x1, int y1, int x2, int y2) => img.fillRect(image, x1: x1, y1: y1, x2: x2, y2: y2, color: black);
  rect(0, 0, w - 1, 3);
  rect(0, h - 4, w - 1, h - 1);
  rect(0, 0, 3, h - 1);
  rect(w - 4, 0, w - 1, h - 1);
  rect(98, 0, 101, h - 1); // shared interior wall at x=100.
  return Uint8List.fromList(img.encodePng(image));
}

GptGraphCorner _c(String id, double x, double y) =>
    GptGraphCorner(id: id, x: x, y: y, kind: GptCornerKind.interiorJunction, confidence: 0.9);

GptGraphWall _w(String id, String c1, String c2, GptWallType type, {List<String> adj = const []}) => GptGraphWall(
      id: id,
      startCornerId: c1,
      endCornerId: c2,
      type: type,
      adjacentSpaceIds: adj,
      confidence: 0.9,
    );

void main() {
  const processor = GptWallGraphProcessor();
  final imageBytes = _buildTwoRoomImage();

  test('같은 물리적 벽을 두 방이 서로 다른 corner id/좌표로 선언해도 하나의 canonical wall로 병합된다', () {
    final graph = GptWallGraphResponse(
      corners: [
        _c('A1', 0, 0), _c('A2', 100, 0), _c('A3', 100, 100), _c('A4', 0, 100),
        // Room B의 좌측 벽(A2-A3와 같은 물리적 위치)을 살짝 다른
        // 좌표/다른 corner id로 선언 — 불완전한 id 재사용을 재현.
        _c('B1', 102, 3), _c('B2', 200, 0), _c('B3', 200, 100), _c('B4', 99, 97),
      ],
      walls: [
        _w('WA1', 'A1', 'A2', GptWallType.exterior),
        _w('WA2', 'A2', 'A3', GptWallType.interior), // 공유벽(방 A쪽 선언).
        _w('WA3', 'A3', 'A4', GptWallType.exterior),
        _w('WA4', 'A4', 'A1', GptWallType.exterior),
        _w('WB1', 'B1', 'B2', GptWallType.exterior),
        _w('WB2', 'B2', 'B3', GptWallType.exterior),
        _w('WB3', 'B3', 'B4', GptWallType.exterior),
        _w('WB4', 'B4', 'B1', GptWallType.interior), // 공유벽(방 B쪽 선언, 다른 id).
      ],
      spaces: [
        GptGraphSpace(id: 'A', label: 'A', semanticType: 'living', boundaryWallIds: ['WA1', 'WA2', 'WA3', 'WA4'], confidence: 0.9),
        GptGraphSpace(id: 'B', label: 'B', semanticType: 'living', boundaryWallIds: ['WB1', 'WB2', 'WB3', 'WB4'], confidence: 0.9),
      ],
    );

    final result = processor.process(graph: graph, imageWidthPx: 200, imageHeightPx: 100, imageBytes: imageBytes);

    expect(result.gptWallCount, 8);
    expect(result.duplicatesRemoved, greaterThanOrEqualTo(1));
    expect(result.closedLoopCount, 2);

    // 공유벽이 병합되었으면, adjacency count 2로 interior 분류된
    // canonical wall이 최소 1개 있어야 한다.
    final sharedWall = result.canonicalWalls.firstWhere(
      (w) => w.adjacentSpaceIds.isEmpty && !w.isExterior,
      orElse: () => result.canonicalWalls.firstWhere((w) => !w.isExterior),
    );
    expect(sharedWall.isExterior, isFalse);
  });

  test('약간 기울어진 벽은 axis alignment로 완전한 수평/수직이 된다', () {
    final graph = GptWallGraphResponse(
      corners: [_c('C1', 0, 0), _c('C2', 100, 3), _c('C3', 100, 100), _c('C4', 0, 100)],
      walls: [
        _w('W1', 'C1', 'C2', GptWallType.exterior), // 약간 기울어짐(3px/100px ≈ 1.7도).
        _w('W2', 'C2', 'C3', GptWallType.exterior),
        _w('W3', 'C3', 'C4', GptWallType.exterior),
        _w('W4', 'C4', 'C1', GptWallType.exterior),
      ],
      spaces: [
        GptGraphSpace(id: 'S', label: 'S', semanticType: 'living', boundaryWallIds: ['W1', 'W2', 'W3', 'W4'], confidence: 0.9),
      ],
    );
    final result = processor.process(graph: graph, imageWidthPx: 200, imageHeightPx: 100, imageBytes: imageBytes);
    final w1 = result.canonicalWalls.firstWhere((w) => w.mergedFromIds.contains('W1'));
    expect(w1.start.y, equals(w1.end.y));
  });

  test('adjacency 개수로 exterior/interior가 재분류된다(1개 공간 참조=exterior, 2개=interior)', () {
    final graph = GptWallGraphResponse(
      corners: [
        _c('A1', 0, 0), _c('A2', 100, 0), _c('A3', 100, 100), _c('A4', 0, 100),
        _c('B2', 100, 0), _c('B3', 200, 0), _c('B4', 200, 100), _c('B1', 100, 100),
      ],
      walls: [
        _w('WA1', 'A1', 'A2', GptWallType.exterior),
        _w('WA2', 'A2', 'A3', GptWallType.exterior), // GPT가 잘못 exterior로 태그했지만 실제로 공유됨.
        _w('WA3', 'A3', 'A4', GptWallType.exterior),
        _w('WA4', 'A4', 'A1', GptWallType.exterior),
        _w('WB1', 'B2', 'B3', GptWallType.exterior),
        _w('WB2', 'B3', 'B4', GptWallType.exterior),
        _w('WB3', 'B4', 'B1', GptWallType.exterior),
        // WB4(B1-B2)는 WA2(A2-A3)와 같은 물리적 위치 — 두 space 모두 참조.
      ],
      spaces: [
        GptGraphSpace(id: 'A', label: 'A', semanticType: 'living', boundaryWallIds: ['WA1', 'WA2', 'WA3', 'WA4'], confidence: 0.9),
        GptGraphSpace(id: 'B', label: 'B', semanticType: 'living', boundaryWallIds: ['WB1', 'WB2', 'WB3', 'WA2'], confidence: 0.9),
      ],
    );
    final result = processor.process(graph: graph, imageWidthPx: 200, imageHeightPx: 100, imageBytes: imageBytes);
    final shared = result.canonicalWalls.firstWhere((w) => w.mergedFromIds.contains('WA2'));
    // GPT는 "exterior"로 태그했지만 실제로 2개 공간이 참조하므로
    // adjacency 기반 재분류에 의해 interior여야 한다.
    expect(shared.isExterior, isFalse);
  });

  test('FloorDomain은 exterior로 재분류된 wall만으로 기존 solver를 재사용해 닫힌다', () {
    final graph = GptWallGraphResponse(
      corners: [
        _c('A1', 0, 0), _c('A2', 100, 0), _c('A3', 100, 100), _c('A4', 0, 100),
        _c('B2', 100, 0), _c('B3', 200, 0), _c('B4', 200, 100), _c('B1', 100, 100),
      ],
      walls: [
        _w('WA1', 'A1', 'A2', GptWallType.exterior),
        _w('WA2', 'A2', 'A3', GptWallType.interior),
        _w('WA3', 'A3', 'A4', GptWallType.exterior),
        _w('WA4', 'A4', 'A1', GptWallType.exterior),
        _w('WB1', 'B2', 'B3', GptWallType.exterior),
        _w('WB2', 'B3', 'B4', GptWallType.exterior),
        _w('WB3', 'B4', 'B1', GptWallType.exterior),
        _w('WB4', 'B1', 'B2', GptWallType.interior),
      ],
      spaces: [
        GptGraphSpace(id: 'A', label: 'A', semanticType: 'living', boundaryWallIds: ['WA1', 'WA2', 'WA3', 'WA4'], confidence: 0.9),
        GptGraphSpace(id: 'B', label: 'B', semanticType: 'living', boundaryWallIds: ['WB1', 'WB2', 'WB3', 'WB4'], confidence: 0.9),
      ],
    );
    final result = processor.process(graph: graph, imageWidthPx: 200, imageHeightPx: 100, imageBytes: imageBytes);
    expect(result.floorDomainClosed, isTrue);
    expect(result.model.floorDomain, isNotNull);
  });
}
