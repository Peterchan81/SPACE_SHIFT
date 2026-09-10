// SS CAD TEST — C:\ASON\SS_CAD_TEST_REAL_FLOORPLAN.dxf 독립 검증.
// 프로덕션 pointToMm/E2eDxfExporter를 전혀 거치지 않는 별도 파서로 원본
// DXF 텍스트를 다시 읽어, 기준 실측 벽(4700mm)이 실제로 4700mm로
// 나오는지와 레이어/개체 수/골격을 확인한다.
// 실행: flutter test tool/verify_real_floorplan_dxf.dart (네트워크 없음)
// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

class _Line {
  _Line(this.layer, this.x1, this.y1, this.x2, this.y2);
  final String layer;
  final double x1, y1, x2, y2;
  double get lengthMm => math.sqrt(math.pow(x2 - x1, 2) + math.pow(y2 - y1, 2));
}

List<_Line> _parseLines(String dxf) {
  final lines = dxf.split('\n').map((l) => l.trim()).toList();
  final out = <_Line>[];
  for (var i = 0; i < lines.length - 1; i++) {
    if (lines[i] == '0' && lines[i + 1] == 'LINE') {
      String? layer;
      double? x1, y1, x2, y2;
      var j = i + 2;
      while (j + 1 < lines.length && lines[j] != '0') {
        final code = lines[j];
        final value = lines[j + 1];
        switch (code) {
          case '8': layer = value;
          case '10': x1 = double.parse(value);
          case '20': y1 = double.parse(value);
          case '11': x2 = double.parse(value);
          case '21': y2 = double.parse(value);
        }
        j += 2;
      }
      if (layer != null && x1 != null && y1 != null && x2 != null && y2 != null) {
        out.add(_Line(layer, x1, y1, x2, y2));
      }
      i = j - 1;
    }
  }
  return out;
}

void main() {
  test('독립 재파싱: 레이어/개수/골격/기준벽 4700mm 검증', () {
    const path = r'C:\ASON\SS_CAD_TEST_REAL_FLOORPLAN.dxf';
    final file = File(path);
    expect(file.existsSync(), isTrue, reason: '$path 가 존재해야 한다');
    final content = file.readAsStringSync();

    expect(content, contains('SECTION'));
    expect(content, contains('ENTITIES'));
    expect(content.trim(), endsWith('0\nEOF'));

    final parsed = _parseLines(content);
    final byLayer = <String, List<_Line>>{};
    for (final l in parsed) {
      byLayer.putIfAbsent(l.layer, () => []).add(l);
    }

    print('=== 독립 재파싱 결과 ===');
    print('총 LINE 개체 수: ${parsed.length}');
    for (final entry in byLayer.entries) {
      print('레이어 ${entry.key}: ${entry.value.length}개');
    }

    final exteriorCount = byLayer['SS-EXTERIOR-WALL']?.length ?? 0;
    final interiorCount = byLayer['SS-INTERIOR-WALL']?.length ?? 0;
    final spaceCount = byLayer['SS-SPACE']?.length ?? 0;
    final doorCount = byLayer['SS-DOOR']?.length ?? 0;
    final windowCount = byLayer['SS-WINDOW']?.length ?? 0;

    // GPT 3회 통합 결과(export_real_floorplan_dxf.dart에 그대로 얼린 값):
    // 외벽(exterior) = wall-1/2/3/4/7/8 = 6개, 내벽(interior) = wall-5/6/9 = 3개,
    // 방 12개(4점 폴리곤이므로 변 4개씩 = 48줄), 문 1개(vision-wall-9에 실제로
    // 존재), 창 0개.
    expect(exteriorCount, 6, reason: '외벽 6개(wall-1/2/3/4/7/8)여야 한다');
    expect(interiorCount, 3, reason: '내벽 3개(wall-5/6/9)여야 한다');
    expect(spaceCount, 48, reason: '방 12개 × 폴리곤 변 4개 = 48줄이어야 한다');
    expect(doorCount, 1, reason: '문 1개(vision-door-1, host wall-9 존재)여야 한다');
    expect(windowCount, 0, reason: '이번 GPT 결과에는 창이 하나도 확정되지 않았다(원본에는 실제 창이 있음 — 별도 보고)');
    expect(parsed.length, exteriorCount + interiorCount + spaceCount + doorCount + windowCount);

    // 기준 실측 벽(vision-wall-4 = 4700mm) 재검증 — 길이만으로 고유하게
    // 식별된다(다른 8개 벽 중 4700mm에 가까운 것이 없음, 아래 exterior
    // 목록에서 직접 확인).
    final exteriorLines = byLayer['SS-EXTERIOR-WALL']!;
    final matches = exteriorLines.where((l) => (l.lengthMm - 4700).abs() < 0.5).toList();
    print('\n=== 외벽 6개 길이(mm) ===');
    for (final l in exteriorLines) {
      print(l.lengthMm.toStringAsFixed(1));
    }
    expect(matches, hasLength(1), reason: '4700mm에 해당하는 벽이 정확히 1개(기준 실측 벽)여야 한다');
    print('\n기준 실측 벽 재측정 결과: ${matches.single.lengthMm.toStringAsFixed(4)} mm (기대값 4700mm)');
    expect(matches.single.lengthMm, closeTo(4700.0, 1e-6));
  }, timeout: const Timeout(Duration(seconds: 30)));
}
