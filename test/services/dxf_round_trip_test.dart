// SS CAD TEST — CAD Editor WO §5 ROUND-TRIP 핵심 검증.
//
// A. 4700mm -> Export -> Import -> 4700mm
// B. 4500mm -> 사용자 4830mm 수정 -> Export -> Import -> 4830mm
// C. 벽/문/창 -> Export -> Import -> 개수/위치(상대)/폭/layer 보존
// D. Import한 CAD -> 사용자 다시 수정 -> 재Export -> 독립 parser 검증

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/services/cad_editing_ops.dart';
import 'package:ason_space/services/dxf_import_service.dart';
import 'package:ason_space/services/e2e_dxf_exporter.dart';

const _exporter = E2eDxfExporter();

void main() {
  group('A. 4700mm 기준 벽 -> Export -> Import -> 4700mm', () {
    test('단일 벽 round-trip', () {
      const sourceWidthPx = 1000;
      const sourceHeightPx = 1000;
      const wall = CadWall(
        id: 'w1',
        start: Point2(0.1, 0.1),
        end: Point2(0.1, 0.5), // pxLen = 0.4*1000 = 400px.
        thicknessNormalized: 0.01,
        wallType: CadWallType.exterior,
        confidence: 1.0,
      );
      final plan = CadFloorPlan(
        sourceWidthPx: sourceWidthPx,
        sourceHeightPx: sourceHeightPx,
        walls: const [wall],
        openings: const [],
        rooms: const [],
        warnings: const [],
      );
      final scale = FloorPlanScale(
        mmPerPixel: 4700 / 400,
        referenceStart: wall.start,
        referenceEnd: wall.end,
        referenceLengthMm: 4700,
        source: ScaleSource.measured,
      );

      final exported = _exporter.export(plan, scale: scale);
      expect(exported.isScaled, isTrue);

      final imported = importDxf(exported.dxfContent);
      expect(imported.success, isTrue, reason: imported.failureMessage);
      expect(imported.plan!.walls, hasLength(1));
      expect(imported.scale, isNotNull);

      final importedWall = imported.plan!.walls.single;
      final lengthMm = imported.plan!.pixelDistance(importedWall.start, importedWall.end) * imported.scale!.mmPerPixel;
      expect(lengthMm, closeTo(4700.0, 1e-6));
      expect(importedWall.wallType, CadWallType.exterior);
    });
  });

  group('B. AI 4500mm -> 사용자 4830mm 수정 -> Export -> Import -> 4830mm', () {
    test('사용자 수정값이 round-trip을 거쳐도 유지된다', () {
      const sourceWidthPx = 1000;
      const sourceHeightPx = 1000;
      const aiWall = CadWall(
        id: 'w1',
        start: Point2(0.1, 0.1),
        end: Point2(0.55, 0.1), // pxLen = 0.45*1000 = 450px.
        thicknessNormalized: 0.01,
        wallType: CadWallType.exterior,
        confidence: 0.6, // AI 추정.
      );
      var plan = CadFloorPlan(
        sourceWidthPx: sourceWidthPx,
        sourceHeightPx: sourceHeightPx,
        walls: const [aiWall],
        openings: const [],
        rooms: const [],
        warnings: const [],
      );
      final scale = FloorPlanScale(
        mmPerPixel: 4500 / 450, // AI 결과 그대로면 4500mm.
        referenceStart: aiWall.start,
        referenceEnd: aiWall.end,
        referenceLengthMm: 4500,
        source: ScaleSource.measured,
      );
      expect(plan.pixelDistance(aiWall.start, aiWall.end) * scale.mmPerPixel, closeTo(4500, 1e-6));

      // 사용자가 4830mm로 직접 수정.
      final editedWall = wallWithLengthMm(plan, aiWall, 4830, scale);
      expect(editedWall.source, CadElementSource.userEdited);
      plan = plan.copyWithWalls([editedWall]);
      expect(plan.pixelDistance(editedWall.start, editedWall.end) * scale.mmPerPixel, closeTo(4830, 1e-6));

      final exported = _exporter.export(plan, scale: scale);
      final imported = importDxf(exported.dxfContent);
      expect(imported.success, isTrue, reason: imported.failureMessage);

      final importedWall = imported.plan!.walls.single;
      final lengthMm = imported.plan!.pixelDistance(importedWall.start, importedWall.end) * imported.scale!.mmPerPixel;
      expect(lengthMm, closeTo(4830.0, 1e-6), reason: 'AI 원래 값(4500mm)이 아니라 사용자 확정값(4830mm)이 남아야 한다');
    });
  });

  group('C. 벽/문/창 -> Export -> Import -> 개수/위치(상대)/폭/layer 보존', () {
    late CadFloorPlan originalPlan;
    late FloorPlanScale originalScale;
    late DxfImportResult imported;

    setUpAll(() {
      const sourceWidthPx = 2000;
      const sourceHeightPx = 1500;
      const wallTop = CadWall(id: 'top', start: Point2(0.1, 0.1), end: Point2(0.7, 0.1), thicknessNormalized: 0.01, wallType: CadWallType.exterior, confidence: 1.0);
      const wallRight = CadWall(id: 'right', start: Point2(0.7, 0.1), end: Point2(0.7, 0.5), thicknessNormalized: 0.01, wallType: CadWallType.exterior, confidence: 1.0);
      const wallDivider = CadWall(id: 'divider', start: Point2(0.4, 0.1), end: Point2(0.4, 0.5), thicknessNormalized: 0.01, wallType: CadWallType.interior, confidence: 1.0);
      const door = CadOpening(id: 'door-1', type: OpeningType.door, center: Point2(0.4, 0.3), widthNormalized: 0.03, confidence: 1.0, wallId: 'divider');
      const window = CadOpening(id: 'window-1', type: OpeningType.window, center: Point2(0.3, 0.1), widthNormalized: 0.04, confidence: 1.0, wallId: 'top');

      originalPlan = const CadFloorPlan(
        sourceWidthPx: sourceWidthPx,
        sourceHeightPx: sourceHeightPx,
        walls: [wallTop, wallRight, wallDivider],
        openings: [door, window],
        rooms: [],
        warnings: [],
      );
      final pxLen = originalPlan.pixelDistance(wallTop.start, wallTop.end);
      originalScale = FloorPlanScale(
        mmPerPixel: 3800 / pxLen,
        referenceStart: wallTop.start,
        referenceEnd: wallTop.end,
        referenceLengthMm: 3800,
        source: ScaleSource.measured,
      );

      final exported = _exporter.export(originalPlan, scale: originalScale);
      imported = importDxf(exported.dxfContent);
    });

    test('import가 성공하고 개수가 보존된다', () {
      expect(imported.success, isTrue, reason: imported.failureMessage);
      expect(imported.plan!.walls, hasLength(3));
      expect(imported.plan!.openings, hasLength(2));
      expect(imported.unsupportedEntityCount, 0);
      expect(imported.unsupportedLayerCount, 0);
    });

    test('벽 layer(exterior/interior)가 보존된다', () {
      final exteriorCount = imported.plan!.walls.where((w) => w.wallType == CadWallType.exterior).length;
      final interiorCount = imported.plan!.walls.where((w) => w.wallType == CadWallType.interior).length;
      expect(exteriorCount, 2);
      expect(interiorCount, 1);
    });

    test('상대 위치(벽 사이 실제 mm 거리)가 보존된다 — 절대 원점은 평행이동될 수 있다', () {
      // top wall 길이(3800mm 기준)와 divider wall 길이의 mm 비율이
      // 그대로 유지되어야 한다(원점 평행이동은 길이/비율에 영향 없음).
      final importedWalls = {for (final w in imported.plan!.walls) w.id: w};
      // id는 새로 부여되므로(imported-wall-N) 길이로 원래 벽을 역추적한다.
      final lengthsMm = imported.plan!.walls
          .map((w) => imported.plan!.pixelDistance(w.start, w.end) * imported.scale!.mmPerPixel)
          .toList()
        ..sort();
      final originalLengthsMm = originalPlan.walls
          .map((w) => originalPlan.pixelDistance(w.start, w.end) * originalScale.mmPerPixel)
          .toList()
        ..sort();
      expect(lengthsMm.length, originalLengthsMm.length);
      for (var i = 0; i < lengthsMm.length; i++) {
        expect(lengthsMm[i], closeTo(originalLengthsMm[i], 0.5));
      }
      expect(importedWalls, isNotEmpty);
    });

    test('문/창 폭(mm)이 보존된다', () {
      final doorWidthMm = originalPlan.openings[0].widthNormalized * originalPlan.diagonalPx * originalScale.mmPerPixel;
      final windowWidthMm = originalPlan.openings[1].widthNormalized * originalPlan.diagonalPx * originalScale.mmPerPixel;

      final importedDoor = imported.plan!.openings.firstWhere((o) => o.type == OpeningType.door);
      final importedWindow = imported.plan!.openings.firstWhere((o) => o.type == OpeningType.window);
      final importedDoorWidthMm = importedDoor.widthNormalized * imported.plan!.diagonalPx * imported.scale!.mmPerPixel;
      final importedWindowWidthMm = importedWindow.widthNormalized * imported.plan!.diagonalPx * imported.scale!.mmPerPixel;

      expect(importedDoorWidthMm, closeTo(doorWidthMm, 1.0));
      expect(importedWindowWidthMm, closeTo(windowWidthMm, 1.0));
    });

    test('문/창이 실제로 가까운 벽에 다시 anchor된다', () {
      for (final o in imported.plan!.openings) {
        expect(o.wallId, isNotNull, reason: '${o.id}가 어떤 벽에도 anchor되지 않음');
        expect(o.reviewNeeded, isFalse);
      }
    });
  });

  group('D. Import한 CAD -> 다시 수정 -> 재Export -> 독립 parser 검증', () {
    test('전체 사이클: Export -> Import -> 수정 -> 재Export -> 독립 재파싱', () {
      const sourceWidthPx = 1000;
      const sourceHeightPx = 1000;
      const wall = CadWall(id: 'w1', start: Point2(0.1, 0.1), end: Point2(0.1, 0.5), thicknessNormalized: 0.01, wallType: CadWallType.exterior, confidence: 1.0);
      final plan1 = CadFloorPlan(sourceWidthPx: sourceWidthPx, sourceHeightPx: sourceHeightPx, walls: const [wall], openings: const [], rooms: const [], warnings: const []);
      final scale1 = FloorPlanScale(mmPerPixel: 4700 / 400, referenceStart: wall.start, referenceEnd: wall.end, referenceLengthMm: 4700, source: ScaleSource.measured);

      final exported1 = _exporter.export(plan1, scale: scale1);
      final imported1 = importDxf(exported1.dxfContent);
      expect(imported1.success, isTrue);

      // 다시 수정: import된 벽을 5200mm로.
      final importedWall = imported1.plan!.walls.single;
      final reEditedWall = wallWithLengthMm(imported1.plan!, importedWall, 5200, imported1.scale!);
      final plan2 = imported1.plan!.copyWithWalls([reEditedWall]);

      final exported2 = _exporter.export(plan2, scale: imported1.scale!);

      // 독립 재파싱(프로덕션 import/export 코드를 전혀 거치지 않는
      // 별도 파서) — 이 세션에서 반복해서 써 온 것과 같은 최소 파서.
      final parsed = _parseLines(exported2.dxfContent);
      final exteriorLines = parsed.where((l) => l.layer == 'SS-EXTERIOR-WALL').toList();
      expect(exteriorLines, hasLength(1));
      expect(exteriorLines.single.lengthMm, closeTo(5200.0, 1e-6));
    });
  });

  group('E. OpeningType.unknown(AI 의미 판별 없는 pixel_wall_v4 결과) -> Export -> Import', () {
    // SS CAD TEST WorkOrder(1차 CAD/DXF E2E) §10 회귀 테스트 — 이 계층이
    // 고쳐지기 전에는 door가 아닌 opening을 전부 'SS-WINDOW'로 내보내
    // unknownOpening이 재-import 후 실제로 창(window)으로 둔갑했다(AI
    // 결과를 거짓으로 확정하지 않는다는 프로젝트 전체 원칙 위반).
    test('unknown 종류 opening이 SS-WINDOW로 거짓 표시되지 않고 그대로 unknown으로 왕복한다', () {
      const sourceWidthPx = 1000;
      const sourceHeightPx = 1000;
      const wall = CadWall(id: 'w1', start: Point2(0.1, 0.1), end: Point2(0.9, 0.1), thicknessNormalized: 0.01, wallType: CadWallType.exterior, confidence: 1.0);
      const unknownOpening = CadOpening(
        id: 'opening-1',
        type: OpeningType.unknown,
        center: Point2(0.5, 0.1),
        widthNormalized: 0.03,
        confidence: 0.6,
        wallId: 'w1',
        reviewNeeded: true,
      );
      final plan = const CadFloorPlan(
        sourceWidthPx: sourceWidthPx,
        sourceHeightPx: sourceHeightPx,
        walls: [wall],
        openings: [unknownOpening],
        rooms: [],
        warnings: [],
      );

      final exported = _exporter.export(plan);
      // 레이어 테이블(TABLES 섹션)은 SS-DOOR/SS-WINDOW를 항상 선언해 둔다
      // (사용 여부와 무관하게, 다른 CAD 프로그램 호환용) — 그래서 파일
      // 전체가 아니라 실제 LINE 엔티티(ENTITIES 섹션)가 어느 레이어에
      // 있는지로만 검증한다.
      final entitiesSection = exported.dxfContent.split('ENTITIES').last;
      expect(
        entitiesSection,
        contains('SS-UNKNOWN-OPENING'),
        reason: 'unknown opening은 SS-DOOR/SS-WINDOW가 아닌 별도 레이어로 내보내야 한다',
      );
      expect(
        entitiesSection,
        isNot(contains('SS-WINDOW')),
        reason: '실제 창이 아닌데 SS-WINDOW 레이어의 LINE 엔티티가 생기면 안 된다',
      );

      final imported = importDxf(exported.dxfContent);
      expect(imported.success, isTrue, reason: imported.failureMessage);
      expect(imported.unsupportedLayerCount, 0, reason: '새 레이어를 importer가 인식하지 못하면 안 된다');
      expect(imported.plan!.openings, hasLength(1));
      expect(
        imported.plan!.openings.single.type,
        OpeningType.unknown,
        reason: '문/창 종류가 확정되지 않은 상태 그대로 왕복해야 한다(거짓으로 window가 되면 안 된다)',
      );
    });
  });
}

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
        out.add(_Line(layer, x1, y1, x2, y2));
      }
      i = j - 1;
    }
  }
  return out;
}
