// SS CAD TEST — "실측 기반 Metric CAD → DXF" 검증.
//
// 목표: 사용자가 "치수 보정"에서 벽 하나를 실측해 3800mm라고 입력하면,
// 내보낸 DXF 파일의 그 벽 LINE 좌표를 다시 재서(측정해) 실제로 정확히
// 3800mm가 나오는가 — GPT나 exporter의 어떤 반올림/축 실수도 없이.
//
// e2e_dxf_exporter_test.dart는 "SCALED로 표시되는가/UNSCALED인가" 같은
// 메타데이터만 확인한다. 이 파일은 그보다 한 단계 더 나아가 DXF 텍스트
// 안의 그룹 코드(10/20/11/21)를 프로덕션 코드(pointToMm/toUnits)를 전혀
// 거치지 않는 별도의 초소형 파서로 직접 다시 읽어, 좌표를 그 자리에서
// 손으로 다시 계산한 기대값과 비교한다 — "내보내기 코드가 스스로와
// 일관적"이라는 순환 검증이 아니라 "파일 자체가 실측값과 맞는가"를
// 확인하기 위해서다(실제 CAD 프로그램으로 열어 자로 재는 것의 대역).
//
// 다중 실측 기준([resolveScaleFromSamples], SS CAD TEST WO)도 함께
// 검증한다 — 벽을 두 개 실측해도(서로 다른 벽) 첫 번째로 확정한 벽의
// mm 길이가 그대로 유지되는가.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/scale_calibration.dart';
import 'package:ason_space/services/e2e_dxf_exporter.dart';

/// DXF 텍스트에서 LINE 엔티티만 뽑아내는 독립 파서. 프로덕션의
/// [CadFloorPlan.pointToMm]/[E2eDxfExporter]의 toUnits는 전혀 쓰지
/// 않는다 — 순수 문자열/그룹코드 파싱만으로 좌표를 되짚는다.
class _ParsedLine {
  _ParsedLine(this.layer, this.x1, this.y1, this.x2, this.y2);
  final String layer;
  final double x1;
  final double y1;
  final double x2;
  final double y2;

  double get lengthMm {
    final dx = x2 - x1;
    final dy = y2 - y1;
    return math.sqrt(dx * dx + dy * dy);
  }
}

List<_ParsedLine> _parseLineEntities(String dxf) {
  final lines = dxf.split('\n').map((l) => l.trim()).toList();
  final result = <_ParsedLine>[];
  for (var i = 0; i < lines.length - 1; i++) {
    if (lines[i] == '0' && i + 1 < lines.length && lines[i + 1] == 'LINE') {
      String? layer;
      double? x1, y1, x2, y2;
      var j = i + 2;
      // 다음 엔티티 경계('0')를 만날 때까지 이 LINE 소속 그룹 코드만 읽는다.
      while (j + 1 < lines.length && lines[j] != '0') {
        final code = lines[j];
        final value = lines[j + 1];
        switch (code) {
          case '8':
            layer = value;
          case '10':
            x1 = double.parse(value);
          case '20':
            y1 = double.parse(value);
          case '11':
            x2 = double.parse(value);
          case '21':
            y2 = double.parse(value);
        }
        j += 2;
      }
      if (layer != null && x1 != null && y1 != null && x2 != null && y2 != null) {
        result.add(_ParsedLine(layer, x1, y1, x2, y2));
      }
      i = j - 1;
    }
  }
  return result;
}

void main() {
  const exporter = E2eDxfExporter();

  // 제어 가능한 최소 fixture — 실제 solver 결과에 의존하지 않고 좌표를
  // 직접 지정해, "정확히 몇 mm가 나와야 하는가"를 손으로 계산할 수 있게
  // 한다.
  const sourceWidthPx = 1000;
  const sourceHeightPx = 800;
  const trueMmPerPixel = 9.5; // 사용자가 재게 될 "실제" 축척(테스트 전용 진실값)

  const wallA = CadWall(
    id: 'wall-a',
    start: Point2(0.1, 0.1),
    end: Point2(0.5, 0.1),
    thicknessNormalized: 0.02,
    wallType: CadWallType.exterior,
    confidence: 1.0,
  ); // 픽셀 길이 = 0.4 * 1000 = 400px → 실제 3800mm(트루스: 400*9.5)

  const wallB = CadWall(
    id: 'wall-b',
    start: Point2(0.1, 0.1),
    end: Point2(0.1, 0.5),
    thicknessNormalized: 0.02,
    wallType: CadWallType.interior,
    confidence: 1.0,
  ); // 픽셀 길이 = 0.4 * 800 = 320px → 실제 3040mm(트루스: 320*9.5)

  final plan = CadFloorPlan(
    sourceWidthPx: sourceWidthPx,
    sourceHeightPx: sourceHeightPx,
    walls: const [wallA, wallB],
    openings: const [],
    rooms: const [],
    warnings: const [],
  );

  FloorPlanScale scaleFromSamples(List<ScaleReferenceSample> samples) {
    final resolved = resolveScaleFromSamples(samples);
    return FloorPlanScale(
      mmPerPixel: resolved.mmPerPixel,
      referenceStart: wallA.start,
      referenceEnd: wallA.end,
      referenceLengthMm: 3800,
      source: ScaleSource.measured,
    );
  }

  test('실측 3800mm로 확정한 벽이 DXF LINE 좌표를 재서도 정확히 3800mm다', () {
    final pixelLengthA = plan.pixelDistance(wallA.start, wallA.end);
    final sample = ScaleReferenceSample(
      wallId: wallA.id,
      pixelLength: pixelLengthA,
      measuredMm: 3800,
    );
    final scale = scaleFromSamples([sample]);

    final result = exporter.export(plan, scale: scale);
    expect(result.isScaled, isTrue);

    final parsed = _parseLineEntities(result.dxfContent);
    final exteriorLines = parsed.where((l) => l.layer == 'SS-EXTERIOR-WALL').toList();
    expect(exteriorLines, hasLength(1));

    // 독립적으로(프로덕션 pointToMm를 거치지 않고) 손으로 다시 계산한
    // 기대 좌표 — Y축은 DXF 관례상 뒤집힌다.
    final expectedX1 = wallA.start.x * sourceWidthPx * trueMmPerPixel;
    final expectedY1 = -(wallA.start.y * sourceHeightPx * trueMmPerPixel);
    final expectedX2 = wallA.end.x * sourceWidthPx * trueMmPerPixel;
    final expectedY2 = -(wallA.end.y * sourceHeightPx * trueMmPerPixel);

    final line = exteriorLines.single;
    expect(line.x1, closeTo(expectedX1, 1e-6));
    expect(line.y1, closeTo(expectedY1, 1e-6));
    expect(line.x2, closeTo(expectedX2, 1e-6));
    expect(line.y2, closeTo(expectedY2, 1e-6));

    // 진짜 검증 지점: 사용자가 "3800mm"라고 입력한 벽이, 파일 안의
    // 두 좌표로부터 다시 잰 길이도 정확히 3800mm인가.
    expect(line.lengthMm, closeTo(3800.0, 1e-6));
  });

  test(
    '벽을 하나 더 실측해도(다중 샘플) 이미 확정한 3800mm 벽의 DXF 길이는 그대로다',
    () {
      final pixelLengthA = plan.pixelDistance(wallA.start, wallA.end);
      final pixelLengthB = plan.pixelDistance(wallB.start, wallB.end);
      // 두 샘플 모두 같은 실제 축척(trueMmPerPixel)에서 나온 값이라
      // 서로 충돌하지 않는다 — median도 정확히 같은 mmPerPixel이 된다.
      final samples = [
        ScaleReferenceSample(
          wallId: wallA.id,
          pixelLength: pixelLengthA,
          measuredMm: pixelLengthA * trueMmPerPixel, // = 3800
        ),
        ScaleReferenceSample(
          wallId: wallB.id,
          pixelLength: pixelLengthB,
          measuredMm: pixelLengthB * trueMmPerPixel, // = 3040
        ),
      ];
      final resolved = resolveScaleFromSamples(samples);
      expect(resolved.hasConflict, isFalse);

      final scale = scaleFromSamples(samples);
      final result = exporter.export(plan, scale: scale);

      final parsed = _parseLineEntities(result.dxfContent);
      final exteriorLine = parsed.singleWhere((l) => l.layer == 'SS-EXTERIOR-WALL');
      final interiorLine = parsed.singleWhere((l) => l.layer == 'SS-INTERIOR-WALL');

      expect(exteriorLine.lengthMm, closeTo(3800.0, 1e-6));
      expect(interiorLine.lengthMm, closeTo(3040.0, 1e-6));
    },
  );
}
