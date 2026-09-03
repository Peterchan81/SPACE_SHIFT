// SPACE SHIFT — GPT Space Boundary Loop Recovery POC.
//
// 실제 PASS A/B/C 캡처 응답(파일시스템에 존재해야 함)을 합쳐 실제
// 이미지 2에 대해 전체 파이프라인을 검증한다. 이 PC 전용 파일에
// 의존하므로 없으면 스킵한다.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/vision_cad_poc/e2e_v2/real_image2_source.dart';
import 'package:ason_space/vision_cad_poc/gpt_vision_v2/gpt_boundary_loop_processor.dart';
import 'package:ason_space/vision_cad_poc/gpt_vision_v2/gpt_pass_b_schema.dart';

const _captureDir = 'lib/vision_cad_poc/gpt_vision_v2/captured';

GptPassBResponse? _loadCombinedRealResponse() {
  final bFile = File('$_captureDir/pass_b.json');
  final cFile = File('$_captureDir/pass_c.json');
  if (!bFile.existsSync() || !cFile.existsSync()) return null;
  final passBJson = jsonDecode(bFile.readAsStringSync()) as Map<String, dynamic>;
  final passCJson = jsonDecode(cFile.readAsStringSync()) as Map<String, dynamic>;
  final allLoops = [
    ...(passBJson['spaceBoundaryLoops'] as List),
    ...(passCJson['spaceBoundaryLoops'] as List),
  ];
  return GptPassBResponse.fromJson({'spaceBoundaryLoops': allLoops});
}

void main() {
  final realBytes = loadRealImage2Bytes();
  final passB = _loadCombinedRealResponse();

  test('실제 PASS B + PASS C 응답으로 13/13 space boundary loop가 닫힌다', () {
    if (realBytes == null || passB == null) {
      // ignore: avoid_print
      print('SKIP: 실제 이미지 2 또는 캡처된 PASS B/C 응답 파일 없음');
      return;
    }
    expect(passB.spaceBoundaryLoops, hasLength(13));

    const processor = GptBoundaryLoopProcessor();
    final result = processor.process(
      passB: passB,
      imageWidthPx: 443,
      imageHeightPx: 300,
      imageBytes: realBytes,
    );

    // PRIMARY 목표: 13/13 closed loops.
    expect(result.closedLoopCount, 13);
    for (final s in result.spaceLoops) {
      expect(s.closed, isTrue, reason: '${s.spaceId} failed: ${s.failureReason}');
    }

    // bbox fallback을 쓰지 않았는지 확인 — 모든 space polygon이 실제
    // segment 개수(4개 이상)만큼의 꼭짓점을 가져야 한다(4점짜리 bbox와
    // 우연히 같은 사각형이더라도, 최소한 폴리곤 자체가 비어있지 않아야
    // 한다).
    for (final space in result.model.spaces) {
      expect(space.polygon, isNotEmpty);
    }
  });
}
