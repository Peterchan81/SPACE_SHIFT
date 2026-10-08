// SS CAD TEST — CAD/DXF FIRST GOAL FINAL LIVE E2E.
//
// 실제 사용자 실측도면(스케치) 1장으로 LIVE OpenAI 호출부터 DXF
// re-import까지 전체 흐름을 검증한다.
//
// 2026-09-17 비용 통제 지시(사용자 승인 메시지): 이 파일은 실제 네트워크를
// 직접 다시 호출하지 않는다. 같은 날 승인된 confirmatory LIVE 호출
// (visionService.interpret() 정확히 1회, HTTP 200, 실제 understanding
// JSON 수신 성공)에서 이미 확보한 응답을 `test/fixtures/
// real_floorplan_understanding_2026-09-17.json`에 저장해 두었고, 이
// 테스트는 그 fixture를 재생(replay)한다 — "같은 이미지를 OpenAI에
// 반복 전송해서 디버깅하지 않는다"는 명시적 지시를 따른다. 이 fixture
// replay 자체가 pixel_wall_v4/CadFloorPlan/DXF 단계를 실제 LIVE AI
// 응답으로 검증하는 것이므로 mock/synthetic 데이터가 아니다.
//
// 이 fixture가 없으면(예: 다른 환경) 안전하게 skip한다.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/scale_calibration.dart';
import 'package:ason_space/models/vision_understanding.dart';
import 'package:ason_space/services/cad_editing_ops.dart';
import 'package:ason_space/services/dxf_import_service.dart';
import 'package:ason_space/services/e2e_dxf_exporter.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/live_semantic_provider.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_pipeline.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/semantic_provider.dart';

const String kRealFloorplanPath = r'C:\Users\user\Desktop\스크린샷\실측1.PNG';
const String kSavedUnderstandingPath = 'test/fixtures/real_floorplan_understanding_2026-09-17.json';
const String kOverlayOutPath = r'C:\Users\user\Desktop\스크린샷\실측1_live_overlay.png';
const String kDxfOutPath = r'C:\Users\user\Desktop\스크린샷\실측1_live.dxf';

/// 2026-09-17 승인된 confirmatory LIVE 호출에서 이미 확보한 실제
/// [VisionUnderstanding]을 그대로 재생한다 — 네트워크를 다시 타지 않는다.
class _ReplaySemanticProvider implements SemanticProvider {
  const _ReplaySemanticProvider(this.understanding);
  final VisionUnderstanding understanding;

  @override
  Future<SemanticProviderResult> fetch(Uint8List imageBytes) async {
    return SemanticProviderResult.success(convertVisionUnderstandingToGptSemantic(understanding));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'CAD/DXF FIRST GOAL FINAL LIVE E2E — 실제 실측도면(LIVE AI 응답 재생) -> SS geometry -> '
    'CadFloorPlan -> 사용자 수정 -> calibration -> DXF export -> DXF re-import',
    () async {
      final imageFile = File(kRealFloorplanPath);
      final fixtureFile = File(kSavedUnderstandingPath);
      if (!imageFile.existsSync() || !fixtureFile.existsSync()) {
        // ignore: avoid_print
        print('SKIP: 실제 이미지 또는 저장된 LIVE 응답 fixture 없음');
        return;
      }

      final bytes = imageFile.readAsBytesSync();
      final understanding = VisionUnderstanding.fromJson(
        jsonDecode(fixtureFile.readAsStringSync()) as Map<String, dynamic>,
      );

      // ===== 1) LIVE 응답 재생 -> SS geometry -> CadFloorPlan =====
      final pipelineResult = await runPixelWallPipelineWithSemanticProvider(
        imageBytes: bytes,
        provider: _ReplaySemanticProvider(understanding),
      );
      // ignore: avoid_print
      print(
        '[pipeline] semanticStatus=${pipelineResult.semanticStatus} '
        'floorDomainClosed=${pipelineResult.floorDomainClosed} '
        'walls(model)=${pipelineResult.model.walls.length}',
      );
      var cad = buildCadFloorPlanFromSpatialModel(pipelineResult.model);

      final doorCount = cad.openings.where((o) => o.type == OpeningType.door).length;
      final windowCount = cad.openings.where((o) => o.type == OpeningType.window).length;
      final unknownCount = cad.openings.where((o) => o.type == OpeningType.unknown).length;
      // ignore: avoid_print
      print(
        '=== [REAL FLOORPLAN] 인식 결과 ===\n'
        'walls=${cad.walls.length} rooms=${cad.rooms.length} '
        'doors=$doorCount windows=$windowCount unknownOpenings=$unknownCount\n'
        'reviewNeeded walls=${cad.walls.where((w) => w.reviewNeeded).length} '
        'warnings=${cad.warnings}',
      );
      expect(cad.walls, isNotEmpty, reason: 'LIVE 분석 결과에 벽이 하나도 없으면 안 된다');

      for (final wall in cad.walls) {
        final lenPx = cad.pixelDistance(wall.start, wall.end);
        // ignore: avoid_print
        print(
          '  wall id=${wall.id} type=${wall.wallType} lenPx=${lenPx.toStringAsFixed(1)} '
          'reviewNeeded=${wall.reviewNeeded} '
          'start=(${wall.start.x.toStringAsFixed(3)},${wall.start.y.toStringAsFixed(3)}) '
          'end=(${wall.end.x.toStringAsFixed(3)},${wall.end.y.toStringAsFixed(3)})',
        );
      }
      for (final o in cad.openings) {
        // ignore: avoid_print
        print(
          '  opening id=${o.id} type=${o.type} wallId=${o.wallId} '
          'center=(${o.center.x.toStringAsFixed(3)},${o.center.y.toStringAsFixed(3)})',
        );
      }

      // ===== 2) 오버레이 렌더링(육안 비교용) =====
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final originalImage = frame.image;
      final w = originalImage.width.toDouble();
      final h = originalImage.height.toDouble();
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawImage(originalImage, ui.Offset.zero, ui.Paint());
      ui.Offset mapPoint(double nx, double ny) => ui.Offset(nx * w, ny * h);
      final wallPaint = ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = const ui.Color(0xFFFF0000);
      for (final wall in cad.walls) {
        canvas.drawLine(mapPoint(wall.start.x, wall.start.y), mapPoint(wall.end.x, wall.end.y), wallPaint);
      }
      final openingPaint = ui.Paint()..color = const ui.Color(0xFF9C27B0);
      for (final o in cad.openings) {
        canvas.drawCircle(mapPoint(o.center.x, o.center.y), 10, openingPaint);
      }
      final picture = recorder.endRecording();
      final outImage = await picture.toImage(originalImage.width, originalImage.height);
      final pngData = await outImage.toByteData(format: ui.ImageByteFormat.png);
      File(kOverlayOutPath).writeAsBytesSync(pngData!.buffer.asUint8List());
      // ignore: avoid_print
      print('WROTE OVERLAY: $kOverlayOutPath');

      // ===== 3) 사용자 CAD 수정 기능 검증(§7) =====
      final undoStack = <CadFloorPlan>[];
      void mutate(CadFloorPlan Function(CadFloorPlan) mutator) {
        undoStack.add(cad);
        cad = mutator(cad);
      }

      // 3a) Wall endpoint move — _onWallEndpointChanged와 동일한 로직 재현.
      final targetWall = cad.walls.first;
      final movedEnd = Point2((targetWall.end.x + 0.02).clamp(0.0, 1.0), targetWall.end.y);
      mutate(
        (p) => p.copyWithWalls([
          for (final w in p.walls)
            if (w.id == targetWall.id)
              w.copyWith(end: movedEnd, edited: true, source: CadElementSource.userEdited)
            else
              w,
        ]),
      );
      final movedWall = cad.walls.firstWhere((w) => w.id == targetWall.id);
      final endpointMovePass = movedWall.end == movedEnd && movedWall.source == CadElementSource.userEdited;
      // ignore: avoid_print
      print('[USER EDIT] wall endpoint move: ${endpointMovePass ? "PASS" : "FAIL"}');
      expect(endpointMovePass, isTrue);

      // 3b) Undo — 방금 한 endpoint move를 되돌린다.
      final beforeUndo = cad;
      cad = undoStack.removeLast();
      final undoPass = cad.walls.firstWhere((w) => w.id == targetWall.id).end == targetWall.end;
      // ignore: avoid_print
      print('[USER EDIT] undo: ${undoPass ? "PASS" : "FAIL"} (beforeUndo != null: ${beforeUndo.walls.isNotEmpty})');
      expect(undoPass, isTrue);

      // 3c) 실전 워크플로 최종 검증 WO §1 — 자동 복원된 문(o1, 이번
      // 인식 품질 개선으로 doors=0 -> 1이 됨)의 위치/폭이 실제로 말이
      // 되는지 확인한다. o1의 실제 좌표(0.632,0.104)는 LIVE 응답
      // fixture 자체의 값이다(육안 확인: 실측1.PNG 크롭 검증, §2 인식
      // 품질 개선 커밋 참고) — 자동 복원된 opening이 그 근처(하나의
      // 벽 두께+매칭 오차 이내)에 있어야 하고, 폭은 0보다 커야 한다.
      expect(doorCount, 1, reason: '이번 인식 품질 개선 이후 자동 복원되는 문은 1개(o1)여야 한다');
      final autoRecoveredDoor = cad.openings.firstWhere((o) => o.type == OpeningType.door);
      const o1TrueX = 0.632, o1TrueY = 0.104;
      final autoDoorDistNorm = ((autoRecoveredDoor.center.x - o1TrueX).abs() + (autoRecoveredDoor.center.y - o1TrueY).abs());
      final autoDoorSane = autoDoorDistNorm < 0.15 && autoRecoveredDoor.widthNormalized > 0;
      // ignore: avoid_print
      print(
        '[AUTO] 자동 복원된 문(o1) 위치=(${autoRecoveredDoor.center.x.toStringAsFixed(3)},'
        '${autoRecoveredDoor.center.y.toStringAsFixed(3)}) widthNormalized=${autoRecoveredDoor.widthNormalized.toStringAsFixed(4)} '
        'wallId=${autoRecoveredDoor.wallId} reviewNeeded=${autoRecoveredDoor.reviewNeeded} : '
        '${autoDoorSane ? "PASS(위치/폭 정상)" : "FAIL"}',
      );
      expect(autoDoorSane, isTrue);

      // 3d) 실전 워크플로 최종 검증 WO §2 — o2는 반경 150px 이내에 pixel
      // 증거가 전혀 없음을 직접 이미지 크롭으로 확인했다(육안 확인: 완전한
      // 빈 종이). "문 추가"만으로는 복구할 수 없다 — 호스트로 삼을 벽
      // 자체가 없기 때문이다(e2e_dxf_exporter.dart는 opening.wallId가
      // 실제 벽을 가리키지 않으면 그 문을 DXF에서 조용히 건너뛴다).
      // 그래서 이번에 추가한 "벽 추가"(_onAddWall/createDefaultWall)로
      // 새 벽을 만들고, 기존 끝점 드래그 기능(_onWallEndpointChanged와
      // 동일한 로직)으로 o2의 실제 위치 근처로 옮긴 뒤, 그 위에 "문
      // 추가"를 적용한다 — 실제 사용자가 화면에서 할 수 있는 것과
      // 정확히 같은 순서다.
      final newWall = createDefaultWall(cad, isExterior: false);
      mutate((p) => p.copyWithWalls([...p.walls, newWall]));
      const o2X = 0.854, o2Y = 0.192;
      final repositioned = newWall.copyWith(
        start: const Point2(o2X, o2Y - 0.05),
        end: const Point2(o2X, o2Y + 0.05),
        edited: true,
        source: CadElementSource.userEdited,
      );
      mutate(
        (p) => p.copyWithWalls([
          for (final w in p.walls) if (w.id == newWall.id) repositioned else w,
        ]),
      );
      final wallForO2 = cad.walls.firstWhere((w) => w.id == newWall.id);
      final addWallPass = wallForO2.source == CadElementSource.userEdited &&
          (wallForO2.start.x - o2X).abs() < 1e-9;
      // ignore: avoid_print
      print(
        '[USER EDIT] §2 누락 벽 추가(Add Wall) + 위치 이동: ${addWallPass ? "PASS" : "FAIL"} '
        '(새 벽을 o2 실제 위치 근처(${o2X.toStringAsFixed(3)},${o2Y.toStringAsFixed(3)})로 이동)',
      );
      expect(addWallPass, isTrue);

      final secondDoor = createOpeningOnWall(cad, wallForO2, type: OpeningType.door, scale: null);
      mutate((p) => CadFloorPlan(
        sourceWidthPx: p.sourceWidthPx,
        sourceHeightPx: p.sourceHeightPx,
        walls: p.walls,
        openings: [...p.openings, secondDoor],
        rooms: p.rooms,
        warnings: p.warnings,
        objectCandidates: p.objectCandidates,
      ));
      final doorCountAfterUserRecovery = cad.openings.where((o) => o.type == OpeningType.door).length;
      final o2RecoveryPass = doorCountAfterUserRecovery == 2;
      // ignore: avoid_print
      print(
        '[USER EDIT] §2 누락 문(o2) 복구(Add Door on new wall): ${o2RecoveryPass ? "PASS" : "FAIL"} '
        '(최종 문 개수=$doorCountAfterUserRecovery/2 — 실제 문 2개 모두 CAD에 존재)',
      );
      expect(o2RecoveryPass, isTrue);

      // ===== 4) 실제 치수 Calibration(§9) =====
      // 실제 실측도면에는 "3700"/"5200"/"4700"/"8300" 등 손글씨 mm
      // 치수가 적혀 있다(육안 확인, 스크린샷 참고). pixel_wall_v4의 pixel
      // 단위 벽 검출 결과(75개, 상당수 아주 짧은 구간)는 이 손글씨
      // 치수선과 자동으로 1:1 매칭되지 않는다 — 어느 pxwall-N이 정확히
      // "3700"에 대응하는지 픽셀 좌표만으로 확정할 근거가 없다(§9 "임의
      // 정확도를 지어내지 않는다"). 따라서 이 단계는 "이 벽이 정확히
      // 3700mm임을 증명"하지 않는다 — calibration 계산 로직(mmPerPixel
      // 산출/ScaleSource.measured 부여/신뢰도 판정) 자체가 실제 도면
      // 치수 값으로 올바르게 동작하는지를 검증하는 것이 목적이며, 이
      // 벽-치수 대응은 육안 근사임을 명시한다.
      final calibrationWall = cad.walls.firstWhere((w) => w.id == 'pxwall-25', orElse: () => cad.walls.first);
      final calibrationPixelLength = cad.pixelDistance(calibrationWall.start, calibrationWall.end);
      const calibrationRealMm = 3700.0; // 실측도면에 손글씨로 적힌 실제 치수(육안 근사 매칭, 위 설명 참고)
      final sample = ScaleReferenceSample(
        wallId: calibrationWall.id,
        pixelLength: calibrationPixelLength,
        measuredMm: calibrationRealMm,
      );
      final resolved = resolveScaleFromSamples([sample]);
      final scale = FloorPlanScale(
        mmPerPixel: resolved.mmPerPixel,
        referenceStart: calibrationWall.start,
        referenceEnd: calibrationWall.end,
        referenceLengthMm: calibrationRealMm,
        source: ScaleSource.measured,
      );
      final expectedMmPerPixel = calibrationRealMm / calibrationPixelLength;
      final calibrationPass =
          (scale.mmPerPixel - expectedMmPerPixel).abs() < 1e-9 && scale.source.isReliable;
      // ignore: avoid_print
      print(
        '[CALIBRATION] wall=${calibrationWall.id} pixelLength=${calibrationPixelLength.toStringAsFixed(1)} '
        'realMm=$calibrationRealMm -> mmPerPixel=${scale.mmPerPixel.toStringAsFixed(4)} '
        'reliable=${scale.source.isReliable} : ${calibrationPass ? "PASS" : "FAIL"}',
      );
      expect(calibrationPass, isTrue);

      // ===== 5) 개별 치수 수정 검증(§10) — 다른 벽 하나를 4200mm로 =====
      final dimensionEditWall = cad.walls.firstWhere(
        (w) => w.id != calibrationWall.id,
        orElse: () => cad.walls.first,
      );
      final beforeEditMm = cad.pixelDistance(dimensionEditWall.start, dimensionEditWall.end) * scale.mmPerPixel;
      final edited4200 = wallWithLengthMm(cad, dimensionEditWall, 4200.0, scale);
      mutate((p) => p.copyWithWalls([
        for (final w in p.walls) if (w.id == dimensionEditWall.id) edited4200 else w,
      ]));
      final afterEditWall = cad.walls.firstWhere((w) => w.id == dimensionEditWall.id);
      final afterEditMm = cad.pixelDistance(afterEditWall.start, afterEditWall.end) * scale.mmPerPixel;
      final dimensionEditPass =
          (afterEditMm - 4200.0).abs() < 0.5 && afterEditWall.source == CadElementSource.userEdited;
      // ignore: avoid_print
      print(
        '[USER EDIT] §10 개별 치수 수정: wall=${dimensionEditWall.id} '
        '${beforeEditMm.toStringAsFixed(0)}mm -> ${afterEditMm.toStringAsFixed(0)}mm '
        '(목표 4200mm): ${dimensionEditPass ? "PASS" : "FAIL"}',
      );
      expect(dimensionEditPass, isTrue);

      // ===== 5b) 두 문의 실제 폭(mm) 확정 — openingWithWidthMm(§1 사용자
      // 보정 난이도 검증: calibration 이후에는 문 폭도 실제 mm로 직접
      // 입력할 수 있어야 한다) =====
      const door1WidthMm = 900.0; // 표준 여닫이문
      const door2WidthMm = 800.0;
      final doorsBeforeWidthEdit = cad.openings.where((o) => o.type == OpeningType.door).toList();
      var widthEdited = cad;
      for (final entry in doorsBeforeWidthEdit.indexed) {
        final (i, door) = entry;
        final targetMm = i == 0 ? door1WidthMm : door2WidthMm;
        final edited = openingWithWidthMm(widthEdited, door, targetMm, scale);
        widthEdited = CadFloorPlan(
          sourceWidthPx: widthEdited.sourceWidthPx,
          sourceHeightPx: widthEdited.sourceHeightPx,
          walls: widthEdited.walls,
          openings: [for (final o in widthEdited.openings) if (o.id == door.id) edited else o],
          rooms: widthEdited.rooms,
          warnings: widthEdited.warnings,
          objectCandidates: widthEdited.objectCandidates,
        );
      }
      mutate((_) => widthEdited);
      final doorWidthsAfterEdit = cad.openings
          .where((o) => o.type == OpeningType.door)
          .map((o) => o.widthNormalized * cad.diagonalPx * scale.mmPerPixel)
          .toList();
      final doorWidthEditPass = doorWidthsAfterEdit.length == 2 &&
          (doorWidthsAfterEdit[0] - door1WidthMm).abs() < 1.0 &&
          (doorWidthsAfterEdit[1] - door2WidthMm).abs() < 1.0;
      // ignore: avoid_print
      print(
        '[USER EDIT] 두 문 실제 폭 확정: ${doorWidthsAfterEdit.map((w) => w.toStringAsFixed(0)).toList()}mm '
        '(목표 ${door1WidthMm.toStringAsFixed(0)}/${door2WidthMm.toStringAsFixed(0)}mm): '
        '${doorWidthEditPass ? "PASS" : "FAIL"}',
      );
      expect(doorWidthEditPass, isTrue);

      // ===== 6) DXF 실제 Export(§11) =====
      final exportResult = const E2eDxfExporter().export(cad, scale: scale);
      File(kDxfOutPath).writeAsStringSync(exportResult.dxfContent);
      final exportHasUnknownLayer = exportResult.dxfContent.contains('SS-UNKNOWN-OPENING');
      final exportHasDoorLayer = exportResult.dxfContent.contains('SS-DOOR');
      // ignore: avoid_print
      print(
        '[DXF EXPORT] isScaled=${exportResult.isScaled} notice="${exportResult.notice}" '
        'hasDoorLayer=$exportHasDoorLayer hasUnknownOpeningLayer=$exportHasUnknownLayer '
        'wrote=$kDxfOutPath',
      );
      expect(exportResult.isScaled, isTrue);
      // §11 — unknown 타입 개구부를 Window로 잘못 내보내지 않는지 재확인(기존 수정 유지).
      final unknownOpeningsBeforeExport = cad.openings.where((o) => o.type == OpeningType.unknown).toList();
      if (unknownOpeningsBeforeExport.isNotEmpty) {
        expect(exportHasUnknownLayer, isTrue, reason: 'unknown 개구부가 있으면 SS-UNKNOWN-OPENING layer로 나가야 한다');
      }

      // ===== 7) DXF Round-trip 검증(§12) =====
      final importResult = importDxf(exportResult.dxfContent);
      expect(importResult.success, isTrue, reason: importResult.failureMessage ?? 'DXF re-import 실패');
      final reimported = importResult.plan!;
      final reimportedDoorCount = reimported.openings.where((o) => o.type == OpeningType.door).length;
      final reimportedWindowCount = reimported.openings.where((o) => o.type == OpeningType.window).length;
      final reimportedUnknownCount = reimported.openings.where((o) => o.type == OpeningType.unknown).length;
      // ignore: avoid_print
      print(
        '[DXF ROUND-TRIP] walls: ${cad.walls.length} -> ${reimported.walls.length}, '
        'openings: ${cad.openings.length} -> ${reimported.openings.length} '
        '(doors ->$reimportedDoorCount(목표 2), windows ->$reimportedWindowCount, '
        'unknown $unknownCount->$reimportedUnknownCount) '
        'warnings=${importResult.warnings} unsupportedEntities=${importResult.unsupportedEntityCount} '
        'unsupportedLayers=${importResult.unsupportedLayerCount}',
      );
      expect(reimported.walls.length, cad.walls.length, reason: '벽 개수는 round-trip 후 보존되어야 한다');
      expect(reimported.openings.length, cad.openings.length, reason: '개구부 개수는 round-trip 후 보존되어야 한다');
      expect(reimportedDoorCount, 2, reason: '실제 문 2개(자동 복원 1개 + 사용자 보정 1개) 모두 round-trip 후에도 문으로 보존되어야 한다');
      expect(reimportedUnknownCount, unknownCount, reason: 'unknown 개구부 개수가 보존되어야 한다');

      // 두 문의 실제 폭(mm)이 round-trip 후에도 보존되는지 확인(§8 "사용자
      // 추가 문/수정 치수/scale이 모두 보존되는지 확인").
      final reimportedDoorWidthsMm = reimported.openings
          .where((o) => o.type == OpeningType.door)
          .map((o) => o.widthNormalized * reimported.diagonalPx) // mmPerPixel=1.0인 DXF 재-import 좌표계
          .toList()
        ..sort();
      final expectedWidths = [door1WidthMm, door2WidthMm]..sort();
      final doorWidthsPreserved = reimportedDoorWidthsMm.length == 2 &&
          (reimportedDoorWidthsMm[0] - expectedWidths[0]).abs() < 2.0 &&
          (reimportedDoorWidthsMm[1] - expectedWidths[1]).abs() < 2.0;
      // ignore: avoid_print
      print(
        '[DXF ROUND-TRIP] 문 폭 보존: ${reimportedDoorWidthsMm.map((w) => w.toStringAsFixed(0)).toList()}mm '
        '(목표 ${expectedWidths.map((w) => w.toStringAsFixed(0)).toList()}mm): '
        '${doorWidthsPreserved ? "PASS" : "FAIL"}',
      );
      expect(doorWidthsPreserved, isTrue);

      // 4200mm로 직접 수정한 벽 길이가 재-import 후에도 그대로인지 확인(§12).
      // DXF는 mm 좌표를 mmPerPixel=1.0으로 저장하므로(재-import 시 새
      // sourceWidthPx/HeightPx가 이 DXF 자체의 bounding box에서 새로
      // 만들어짐, dxf_import_service.dart 문서 참고) pixelDistance가 곧
      // mm 값이다 — id는 DXF에 저장되지 않으므로 길이로 대조한다.
      final has4200mmWall = reimported.walls.any((w) {
        final mm = reimported.pixelDistance(w.start, w.end); // mmPerPixel=1.0인 DXF 재-import 좌표계
        return (mm - 4200.0).abs() < 1.0;
      });
      // ignore: avoid_print
      print('[DXF ROUND-TRIP] 4200mm 사용자 수정 벽 보존: ${has4200mmWall ? "PASS" : "FAIL"}');
      expect(has4200mmWall, isTrue);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
