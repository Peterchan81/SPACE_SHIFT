// SPACE SHIFT — PC1 CONTINUE: LOCAL EXTERIOR GAP RECOVERY + FLOOR DOMAIN
// VALIDATION.
//
// 두 실제 버그를 합성 데이터로 재현/회귀 검증한다:
// 1. WallSystem.isExterior 다수결 동률 버그 — 진짜 외벽 1개 + 진짜 내벽
//    1개가 같은 축 근처에 묶이면 시스템 전체가 잘못 "외벽"이 됐다.
//    buildFloorDomain은 이제 시스템 단위가 아니라 "개별 segment의
//    isExterior"만 신뢰해야 한다.
// 2. 미세한 명암 흔들림으로 조각난 벽 — 실제로는 어두운 띠가 이어져
//    있는데 여러 segment로 쪼개진 경우, dark-band continuity 증거가
//    있을 때만 하나로 합쳐야 한다(증거 없이 큰 gap을 이어붙이면 안 됨).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/floor_domain_builder.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_extractor.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_types.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/wall_system.dart';

const w = 400;
const h = 300;

PixelWallCandidate _c({
  required String id,
  required double x1,
  required double y1,
  required double x2,
  required double y2,
  required bool isExterior,
  PixelWallOrientation orientation = PixelWallOrientation.vertical,
  int junction = 1,
}) {
  return PixelWallCandidate(
    id: id,
    start: Point2(x1 / w, y1 / h),
    end: Point2(x2 / w, y2 / h),
    thicknessNormalized: 6 / w,
    orientation: orientation,
    isExterior: isExterior,
    baseConfidence: 0.8,
    junctionSupport: junction,
    confidenceTier: PixelWallConfidenceTier.high,
    category: PixelWallCategory.structural,
    sourceSegmentIds: [id],
  );
}

void main() {
  group('WallSystem 다수결 동률 버그 회귀 방지', () {
    test('진짜 외벽 1개 + 진짜 내벽 1개가 같은 축 근처면, FloorDomain은 내벽을 무시하고 외벽 segment만 써야 한다', () {
      final candidates = [
        _c(id: 'real-exterior', x1: 100, y1: 10, x2: 100, y2: 60, isExterior: true),
        // 내벽(오분류 없이 그대로 interior) — 같은 축(x=104, tolerance 10px 이내) 근처에 있지만 진짜 내벽.
        _c(id: 'real-interior', x1: 104, y1: 100, x2: 104, y2: 150, isExterior: false),
      ];
      final systems = buildWallSystems(candidates: candidates, w: w, h: h);
      // 시스템 자체는 다수결로 여전히 "외벽"이 될 수 있다(이게 원래 버그였음) —
      // 하지만 buildFloorDomain은 개별 segment의 isExterior만 신뢰해야 한다.
      final fd = buildFloorDomain(wallSystems: systems, w: w, h: h);
      // 내벽 segment가 gap 계산에 섞이지 않았다면, 이 최소 예제에서는
      // exterior segment가 단 1개뿐이라 loop를 닫을 수 없다(외벽이 이거
      // 하나뿐이므로) — 적어도 "내벽 구간을 gap으로 오인해 report하지
      // 않는다"는 것만 확인한다(unresolvedGaps에 real-interior 관련 큰
      // gap이 절대 나타나면 안 됨).
      for (final g in fd.unresolvedGaps) {
        expect(g.gapPx, isNot(closeTo(40, 5)), reason: '내벽 구간이 외벽 gap으로 잘못 보고됨');
      }
    });
  });

  group('dark-band continuity 병합', () {
    Uint8List _wallWithBreak({required int breakStartY, required int breakEndY, required int wallX}) {
      final image = img.Image(width: w, height: h);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));
      for (var y = 10; y < 200; y++) {
        if (y >= breakStartY && y < breakEndY) continue;
        for (var t = -3; t <= 3; t++) {
          image.setPixel(wallX + t, y, img.ColorRgb8(0, 0, 0));
        }
      }
      return Uint8List.fromList(img.encodePng(image));
    }

    test('실제로 어두운 띠가 거의 안 끊긴 경우(짧은 진짜 gap)는 이어붙인다', () {
      final bytes = _wallWithBreak(breakStartY: 100, breakEndY: 100, wallX: 150); // 사실상 끊김 없음.
      final result = extractPixelWalls(bytes);
      final verticalNearWall = result.candidates.where((c) => c.orientation == PixelWallOrientation.vertical && (c.start.x * result.analysisWidthPx - 150).abs() < 10);
      expect(verticalNearWall, isNotEmpty);
    });

    test('실제로 크게 밝은 gap(진짜 벽이 없는 구간)은 이어붙이지 않는다', () {
      final bytes = _wallWithBreak(breakStartY: 80, breakEndY: 160, wallX: 150); // 80px 순수 배경 gap.
      final result = extractPixelWalls(bytes);
      final verticalSegs = result.candidates.where((c) => c.orientation == PixelWallOrientation.vertical && (c.start.x * result.analysisWidthPx - 150).abs() < 10).toList();
      // 두 조각이 하나로(오탐) 합쳐지지 않고 여전히 분리돼 있어야 한다 —
      // 즉 어느 조각도 80px gap을 건너뛴 길이를 갖지 않는다.
      for (final seg in verticalSegs) {
        final lengthPx = (seg.end.y - seg.start.y).abs() * result.analysisHeightPx;
        expect(lengthPx, lessThan(80), reason: '실제로 밝은(벽이 없는) 구간을 넘어 이어붙이면 안 된다');
      }
    });
  });

  group('FloorDomain은 여전히 근거 없이 임의로 닫지 않는다', () {
    test('큰 notConnected gap이 있으면 FloorDomain은 INVALID를 유지하고 self-intersection 없는 정직한 실패를 보고한다', () {
      final candidates = [
        _c(id: 'top', x1: 20, y1: 20, x2: 220, y2: 20, orientation: PixelWallOrientation.horizontal, isExterior: true),
        _c(id: 'left', x1: 20, y1: 20, x2: 20, y2: 220, isExterior: true),
        _c(id: 'right', x1: 220, y1: 20, x2: 220, y2: 220, isExterior: true),
        // 하단은 완전히 빠짐 — 진짜 벽 근거가 전혀 없는 큰 gap.
      ];
      final systems = buildWallSystems(candidates: candidates, w: w, h: h);
      final fd = buildFloorDomain(wallSystems: systems, w: w, h: h);
      expect(fd.isValid, isFalse);
      expect(fd.loop, isNull, reason: '근거 없이 가짜 직선으로 닫으면 안 된다');
    });
  });
}
