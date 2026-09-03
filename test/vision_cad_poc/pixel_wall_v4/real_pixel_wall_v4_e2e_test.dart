// SPACE SHIFT — Vision-Guided Full Pixel Wall Extraction POC.
// 실제 이미지 2에 대해 pixel 전용(GPT 무관) 추출 결과를 있는 그대로
// 기록한다 — 숫자를 미리 예단하지 않고, 이 파일이 있는 PC에서 실행될
// 때마다 실제 수치를 출력해 사람이 확인할 수 있게 한다.

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/vision_cad_poc/e2e_v2/real_image2_source.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_extractor.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_types.dart';

void main() {
  test('실제 이미지 2 — pixel 전용 추출 결과를 정직하게 출력한다', () {
    final bytes = loadRealImage2Bytes();
    if (bytes == null) {
      // ignore: avoid_print
      print('SKIP: 실제 이미지 2 파일 없음 ($kRealImage2Path)');
      return;
    }

    final result = extractPixelWalls(bytes);
    expect(result.isSuccess, isTrue);

    final high = result.candidates.where((c) => c.confidenceTier == PixelWallConfidenceTier.high).length;
    final medium = result.candidates.where((c) => c.confidenceTier == PixelWallConfidenceTier.medium).length;
    final low = result.candidates.where((c) => c.confidenceTier == PixelWallConfidenceTier.low).length;
    final exterior = result.candidates.where((c) => c.isExterior).length;

    // ignore: avoid_print
    print('''
=== 실제 이미지 2 — PIXEL WALL EXTRACTION (GPT 무관) ===
원본 해상도: ${result.sourceWidthPx}x${result.sourceHeightPx}
분석 해상도: ${result.analysisWidthPx}x${result.analysisHeightPx}
회전 보정: ${result.rotationDegrees}도
원본 WallSegment 개수(분류 전): ${result.rawWallSegmentCount}
최종 pixel wall candidate: ${result.candidates.length} (구조=${result.structuralCount}, 검토필요=${result.reviewNeededCount})
  HIGH=$high MEDIUM=$medium LOW=$low
  외벽으로 분류: $exterior
Rejected(두께 초과, 진단용): ${result.rejected.length}
Opening 후보: ${result.openings.length}
RoomCandidate(flood-fill 닫힌 영역): ${result.rooms.length}
''');

    // 최소한의 안전성만 확인 — "얼마나 잘 맞았는지"는 사람이 Windows
    // 화면에서 시각적으로 판단한다(이 테스트가 PASS를 대신하지 않는다).
    expect(result.candidates, isNotEmpty);
  });
}
