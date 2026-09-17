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

      // 3c) §8 — 실제 LIVE 분석은 semantic 단계에서 문 2개(o1/o2)를
      // 감지했지만 최종 CadFloorPlan에는 0개만 남았다(위 doors=$doorCount
      // 출력 참고, pixel 근거 부족으로 탈락). 이 화면은 기존까지 "이미
      // 있는 문/창의 폭을 고치는" 기능만 있고 "새 문/창 추가" 기능이
      // 전혀 없어 사용자가 이 누락을 복구할 방법이 없었다(§8 "복구
      // 불가능하면 FINAL PASS 금지"). 오늘 추가한 최소 기능
      // (_onAddOpeningToSelectedWall/createOpeningOnWall)이 실제로
      // 이 real E2E의 CadFloorPlan 위에서 동작하는지 검증한다.
      final hostWall = cad.walls.firstWhere((w) => !w.reviewNeeded, orElse: () => cad.walls.first);
      final addedDoor = createOpeningOnWall(cad, hostWall, type: OpeningType.door, scale: null);
      mutate((p) => CadFloorPlan(
        sourceWidthPx: p.sourceWidthPx,
        sourceHeightPx: p.sourceHeightPx,
        walls: p.walls,
        openings: [...p.openings, addedDoor],
        rooms: p.rooms,
        warnings: p.warnings,
        objectCandidates: p.objectCandidates,
      ));
      final addDoorPass = cad.openings.any(
        (o) => o.id == addedDoor.id && o.type == OpeningType.door && o.source == CadElementSource.userCreated,
      );
      // ignore: avoid_print
      print(
        '[USER EDIT] §8 누락 문 복구(Add Door): ${addDoorPass ? "PASS" : "FAIL"} '
        '(AI가 실제로 감지한 semantic 문=2개, 최종 CadFloorPlan 생존=$doorCount개 -> '
        '사용자가 이 화면에서 직접 ${cad.openings.length}개로 보강 가능함을 확인)',
      );
      expect(addDoorPass, isTrue);

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
        '(doors $doorCount->$reimportedDoorCount+1추가분, windows $windowCount->$reimportedWindowCount, '
        'unknown $unknownCount->$reimportedUnknownCount) '
        'warnings=${importResult.warnings} unsupportedEntities=${importResult.unsupportedEntityCount} '
        'unsupportedLayers=${importResult.unsupportedLayerCount}',
      );
      expect(reimported.walls.length, cad.walls.length, reason: '벽 개수는 round-trip 후 보존되어야 한다');
      expect(reimported.openings.length, cad.openings.length, reason: '개구부 개수는 round-trip 후 보존되어야 한다');
      expect(reimportedDoorCount, doorCount + 1, reason: '방금 추가한 문 1개가 round-trip 후에도 문으로 보존되어야 한다');
      expect(reimportedUnknownCount, unknownCount, reason: 'unknown 개구부 개수가 보존되어야 한다');

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
