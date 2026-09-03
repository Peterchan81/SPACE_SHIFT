// SPACE SHIFT — Canonical Wall Graph First POC.
//
// 실제 PASS C(pass_b_repaired.json — 최종 graph 시도) 응답에 대해
// 전체 파이프라인이 안전하게 동작하는지 확인한다. 이 테스트는 결과가
// "좋다"고 주장하지 않는다 — 실제 API 호출 결과가 이번 라운드에는
// 심각하게 부족했음(13개 방에 corner 10개/wall 8개)을 정직하게
// 기록한다. 파이프라인/TopologyValidator가 이런 부족한 입력에도
// 크래시 없이 안전하게 reviewNeeded로 처리하는지가 이 테스트의
// 핵심이다.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/vision_cad_poc/e2e_v2/real_image2_source.dart';
import 'package:ason_space/vision_cad_poc/gpt_vision_v3/gpt_graph_schema.dart';
import 'package:ason_space/vision_cad_poc/gpt_vision_v3/gpt_wall_graph_processor.dart';

const _capturePath = 'lib/vision_cad_poc/gpt_vision_v3/captured/pass_b_repaired.json';

void main() {
  final realBytes = loadRealImage2Bytes();

  test('실제(부족한) GPT wall graph 응답도 크래시 없이 안전하게 처리된다', () {
    if (realBytes == null || !File(_capturePath).existsSync()) {
      // ignore: avoid_print
      print('SKIP: 실제 이미지 2 또는 캡처된 응답 파일 없음');
      return;
    }
    final json = jsonDecode(File(_capturePath).readAsStringSync()) as Map<String, dynamic>;
    final graph = GptWallGraphResponse.fromJson(json);

    const processor = GptWallGraphProcessor();
    final result = processor.process(graph: graph, imageWidthPx: 443, imageHeightPx: 300, imageBytes: realBytes);

    // 정직한 현재 상태: 13개 공간 중 극소수만 닫힘 — bbox로 대체하지
    // 않고 실패를 그대로 보고했는지가 핵심이다.
    expect(result.model.spaces, hasLength(13));
    for (final space in result.model.spaces) {
      if (!space.closed) {
        expect(space.polygon, isEmpty, reason: '${space.id}: 실패한 공간은 bbox로 대체되지 않아야 한다');
        expect(space.reviewNeeded, isTrue);
      }
    }
    // TopologyValidator가 빈 polygon이 섞여도 크래시하지 않아야 한다
    // (이번 세션에서 발견/수정한 실제 버그의 회귀 방지).
    expect(() => result.model, returnsNormally);
  });
}
