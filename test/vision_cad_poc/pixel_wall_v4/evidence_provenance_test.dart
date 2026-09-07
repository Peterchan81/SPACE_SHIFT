// SPACE SHIFT — WO082 EVIDENCE/PROVENANCE + VIRTUAL CAD FOUNDATION.
//
// SSWallEdge/SSOpening의 source가 "직접 관측(geometry)"과 "위상 추론
// (inferredTopology)"을 정확히 구분하는지, GPT 근거가 있을 때만 vision
// (semantic AI evidence)이 되는지를 합성 도면으로 검증한다 — 추론값을
// 관측값처럼 저장하지 않는다는 원칙(§3A)의 핵심 회귀 테스트.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:ason_space/models/ss_spatial_model.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_pipeline.dart';

Uint8List _rectSingleWall() {
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

  thickLine(30, 30, 270, 30);
  thickLine(30, 170, 270, 170);
  thickLine(30, 30, 30, 170);
  thickLine(270, 30, 270, 170);
  return Uint8List.fromList(img.encodePng(image));
}

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

  thickLine(30, 30, 120, 30);
  thickLine(140, 30, 270, 30);
  thickLine(30, 170, 270, 170);
  thickLine(30, 30, 30, 170);
  thickLine(270, 30, 270, 170);
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  test('gap 없이 완전히 닫힌 벽 — 모든 WallEdge가 직접 관측(geometry)으로 남는다', () {
    final result = runPixelWallPipeline(imageBytes: _rectSingleWall());
    expect(result.model.wallEdges, isNotEmpty);
    for (final edge in result.model.wallEdges) {
      expect(edge.physicalWallIds, hasLength(1), reason: '이 도면엔 문 gap이 없으므로 모든 WallEdge가 물리 segment 1개로만 구성돼야 한다');
      expect(edge.source, SSEntitySource.geometry, reason: '직접 관측된 벽은 geometry여야 한다(추론 아님)');
    }
  });

  test('문 gap으로 끊긴 벽 — 그 WallEdge만 inferredTopology로 표시된다(추론값을 관측값처럼 저장하지 않는다)', () {
    final result = runPixelWallPipeline(imageBytes: _rectWithDoorGap());
    final multiSegmentEdges = result.model.wallEdges.where((e) => e.physicalWallIds.length >= 2).toList();
    expect(multiSegmentEdges, isNotEmpty);
    for (final edge in multiSegmentEdges) {
      expect(edge.source, SSEntitySource.inferredTopology, reason: '문 gap을 건너 이어붙인 벽은 직접 관측이 아니라 위상 추론이다');
    }
    // 문 gap이 없는 나머지 3면은 여전히 직접 관측(geometry)이어야 한다.
    final singleSegmentEdges = result.model.wallEdges.where((e) => e.physicalWallIds.length == 1).toList();
    expect(singleSegmentEdges, isNotEmpty);
    for (final edge in singleSegmentEdges) {
      expect(edge.source, SSEntitySource.geometry);
    }

    // opening 자체도 GPT 의미 근거가 없으므로 vision이 아니라
    // inferredTopology여야 한다(pixel gap 크기만으로 추론한 값).
    for (final opening in result.model.openings) {
      expect(opening.source, SSEntitySource.inferredTopology);
    }
  });
}
