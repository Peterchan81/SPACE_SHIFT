import '../models/cad_floor_plan.dart';
import '../models/floor_plan_geometry.dart';

/// SPACE SHIFT — Image 2 AI → Real CAD End-to-End POC. DXF POC(설계 7번).
///
/// [CadFloorPlan](Canonical CAD Model을 화면과 공유하는 바로 그 geometry)
/// 에서 직접 최소 DXF를 만든다 — 화면을 이미지로 찍어 벡터화하지 않는다.
///
/// [scale]이 없으면(축척 미확정) 좌표를 정규화(0..1) 단위 그대로 쓰고,
/// 파일 맨 위 주석과 [DxfExportResult.isScaled]에 "UNSCALED/NORMALIZED
/// POC"임을 명시한다 — mm 단위 실측 CAD인 것처럼 오인될 수 있는 파일을
/// 정식 결과물로 만들지 않는다는 원칙을 지킨다.
class DxfExportResult {
  const DxfExportResult({required this.dxfContent, required this.isScaled, required this.notice});

  final String dxfContent;
  final bool isScaled;
  final String notice;
}

class E2eDxfExporter {
  const E2eDxfExporter();

  DxfExportResult export(CadFloorPlan plan, {FloorPlanScale? scale}) {
    final isScaled = scale != null && scale.source == ScaleSource.measured;
    final notice = isScaled
        ? 'SCALED (measured): ${scale.referenceLengthMm.toStringAsFixed(0)}mm 실측 기준, mmPerPixel=${scale.mmPerPixel.toStringAsFixed(4)}'
        : 'UNSCALED / NORMALIZED POC — 실제 mm 단위가 아님. 테스트 전용 파일입니다.';

    (double, double) toUnits(Point2 p) {
      if (!isScaled) return (p.x, p.y);
      final mmX = p.x * plan.sourceWidthPx * scale.mmPerPixel;
      final mmY = p.y * plan.sourceHeightPx * scale.mmPerPixel;
      // DXF/CAD 관례상 Y축은 위로 갈수록 증가 — 이미지 좌표(Y 아래로
      // 증가)를 뒤집는다.
      return (mmX, -mmY);
    }

    final buffer = StringBuffer();
    buffer.writeln('999');
    buffer.writeln('SPACE SHIFT E2E POC DXF — $notice');
    buffer.writeln('0');
    buffer.writeln('SECTION');
    buffer.writeln('2');
    buffer.writeln('HEADER');
    buffer.writeln('9');
    buffer.writeln('\$ACADVER');
    buffer.writeln('1');
    buffer.writeln('AC1009');
    buffer.writeln('0');
    buffer.writeln('ENDSEC');

    buffer.writeln('0');
    buffer.writeln('SECTION');
    buffer.writeln('2');
    buffer.writeln('TABLES');
    buffer.writeln('0');
    buffer.writeln('TABLE');
    buffer.writeln('2');
    buffer.writeln('LAYER');
    for (final (name, color) in [
      ('SS-EXTERIOR-WALL', 1),
      ('SS-INTERIOR-WALL', 5),
      ('SS-SPACE', 3),
    ]) {
      buffer.writeln('0');
      buffer.writeln('LAYER');
      buffer.writeln('2');
      buffer.writeln(name);
      buffer.writeln('70');
      buffer.writeln('0');
      buffer.writeln('62');
      buffer.writeln('$color');
      buffer.writeln('6');
      buffer.writeln('CONTINUOUS');
    }
    buffer.writeln('0');
    buffer.writeln('ENDTAB');
    buffer.writeln('0');
    buffer.writeln('ENDSEC');

    buffer.writeln('0');
    buffer.writeln('SECTION');
    buffer.writeln('2');
    buffer.writeln('ENTITIES');

    void line(String layer, Point2 a, Point2 b) {
      final (x1, y1) = toUnits(a);
      final (x2, y2) = toUnits(b);
      buffer.writeln('0');
      buffer.writeln('LINE');
      buffer.writeln('8');
      buffer.writeln(layer);
      buffer.writeln('10');
      buffer.writeln(x1.toStringAsFixed(4));
      buffer.writeln('20');
      buffer.writeln(y1.toStringAsFixed(4));
      buffer.writeln('11');
      buffer.writeln(x2.toStringAsFixed(4));
      buffer.writeln('21');
      buffer.writeln(y2.toStringAsFixed(4));
    }

    for (final wall in plan.walls) {
      final layer = wall.wallType == CadWallType.exterior ? 'SS-EXTERIOR-WALL' : 'SS-INTERIOR-WALL';
      line(layer, wall.start, wall.end);
    }
    for (final room in plan.rooms) {
      for (var i = 0; i < room.polygon.length; i++) {
        final a = room.polygon[i];
        final b = room.polygon[(i + 1) % room.polygon.length];
        line('SS-SPACE', a, b);
      }
    }

    buffer.writeln('0');
    buffer.writeln('ENDSEC');
    buffer.writeln('0');
    buffer.writeln('EOF');

    return DxfExportResult(dxfContent: buffer.toString(), isScaled: isScaled, notice: notice);
  }
}
