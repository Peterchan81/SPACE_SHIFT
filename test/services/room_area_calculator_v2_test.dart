// SpaceScene V2 — 면적 재정의(WO 5번) + room false-positive 필터(WO 6번) +
// 실측 1개 벽으로 전체 project scale을 확정하는 흐름(WO 4번, "측정한
// 벽 하나로 전체가 다시 계산된다")을 검증한다. 실제 UI(치수 보정 바텀시트)
// 없이, 화면이 실제로 하는 계산(`mmPerPixel = realMm / pixelLength`)을
// 그대로 재현해 그 결과로 만든 [FloorPlanScale]이 면적 전체를 올바르게
// 다시 계산하는지 확인한다.
import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/cad_floor_plan.dart';
import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/services/room_area_calculator_v2.dart';

CadFloorPlan _planWithSquareRoom({
  required int widthPx,
  required int heightPx,
  required List<Point2> polygon,
  double confidence = 0.9,
}) {
  return CadFloorPlan(
    sourceWidthPx: widthPx,
    sourceHeightPx: heightPx,
    walls: const [],
    openings: const [],
    rooms: [
      CadRoom(
        id: 'room-0',
        polygon: polygon,
        areaNormalized: 0.5,
        confidence: confidence,
      ),
    ],
    warnings: const [],
  );
}

void main() {
  group('computeRoomAreasV2 — 실제 CAD geometry 기반 재계산(WO 5번)', () {
    test('정사각형 room의 mm² 면적이 mmPerPixel 기준으로 정확히 계산된다', () {
      // 1000x1000px 이미지에 정확히 절반(0.5~1.0, 0.5~1.0)을 차지하는
      // 정사각형 방 — 실제 픽셀 크기는 500x500px.
      final plan = _planWithSquareRoom(
        widthPx: 1000,
        heightPx: 1000,
        polygon: const [
          Point2(0.5, 0.5),
          Point2(1.0, 0.5),
          Point2(1.0, 1.0),
          Point2(0.5, 1.0),
        ],
      );
      const scale = FloorPlanScale(
        mmPerPixel: 4.0, // 500px * 4mm/px = 2000mm = 2m 변.
        referenceStart: Point2(0, 0),
        referenceEnd: Point2(1, 0),
        referenceLengthMm: 4000,
        source: ScaleSource.measured,
      );

      final summary = computeRoomAreasV2(plan: plan, scale: scale);
      expect(summary.rooms, hasLength(1));
      final room = summary.rooms.single;
      expect(room.areaM2, closeTo(4.0, 1e-6)); // 2m x 2m = 4㎡.
      expect(room.includedInTotal, isTrue);
      expect(summary.totalAreaM2, closeTo(4.0, 1e-6));
      expect(
        summary.totalAreaPyeong,
        closeTo(4.0 / kSquareMetersPerPyeong, 1e-6),
      );
    });

    test('실측 1개 벽 입력으로 mmPerPixel이 바뀌면 전체 면적이 제곱으로 재계산된다(WO 4번)', () {
      final plan = _planWithSquareRoom(
        widthPx: 1000,
        heightPx: 1000,
        polygon: const [
          Point2(0.0, 0.0),
          Point2(1.0, 0.0),
          Point2(1.0, 1.0),
          Point2(0.0, 1.0),
        ],
      );

      // 1단계: 문 폭 추정 등으로 만든 초기(신뢰도 낮은) 축척.
      const initialScale = FloorPlanScale(
        mmPerPixel: 5.0,
        referenceStart: Point2(0, 0),
        referenceEnd: Point2(0, 0),
        referenceLengthMm: 900,
        source: ScaleSource.estimatedFromDoor,
      );
      final before = computeRoomAreasV2(plan: plan, scale: initialScale);

      // 2단계: 사용자가 화면 왼쪽 벽(정규화 길이 1.0 = 1000px)을 드래그로
      // 선택하고 실제 길이 6000mm를 입력했다고 가정 — 화면(
      // _onApplyCalibrationLength)이 실제로 하는 계산을 그대로 재현한다.
      final pixelLength = plan.pixelDistance(
        const Point2(0, 0),
        const Point2(0, 1),
      );
      const realMm = 6000.0;
      final measuredScale = FloorPlanScale(
        mmPerPixel: realMm / pixelLength,
        referenceStart: const Point2(0, 0),
        referenceEnd: const Point2(0, 1),
        referenceLengthMm: realMm,
        source: ScaleSource.measured,
      );
      final after = computeRoomAreasV2(plan: plan, scale: measuredScale);

      final ratio = measuredScale.mmPerPixel / initialScale.mmPerPixel;
      expect(
        after.totalAreaM2,
        closeTo(before.totalAreaM2 * ratio * ratio, 1e-6),
        reason: '면적은 길이 스케일의 제곱으로 재계산돼야 한다(선형이 아니라 면적).',
      );
      expect(after.rooms.single.scaleSource, ScaleSource.measured);
      expect(before.rooms.single.scaleSource, ScaleSource.estimatedFromDoor);
    });
  });

  group('computeRoomAreasV2 — room false-positive 필터(WO 6번)', () {
    const scale = FloorPlanScale(
      mmPerPixel: 5.0,
      referenceStart: Point2(0, 0),
      referenceEnd: Point2(1, 0),
      referenceLengthMm: 5000,
      source: ScaleSource.measured,
    );

    test('충분히 큰 정상 방은 삭제되지 않고 합계에 포함된다', () {
      // 1000x1000px * 5mm/px 기준 0.2 정규화 폭 = 200px*5mm = 1000mm(1m)
      // 변 — 작은 화장실 수준이지만 노이즈는 아니다.
      final plan = _planWithSquareRoom(
        widthPx: 1000,
        heightPx: 1000,
        polygon: const [
          Point2(0.0, 0.0),
          Point2(0.2, 0.0),
          Point2(0.2, 0.2),
          Point2(0.0, 0.2),
        ],
      );
      final summary = computeRoomAreasV2(plan: plan, scale: scale);
      final room = summary.rooms.single;
      expect(room.includedInTotal, isTrue);
      expect(room.exclusionReason, isNull);
    });

    test('벽 틈 수준의 아주 작은 polygon은 합계에서 제외되지만 목록에는 남는다', () {
      // 0.01 정규화 폭 = 10px*5mm = 50mm 변 — 실제 방일 수 없는 크기.
      final plan = _planWithSquareRoom(
        widthPx: 1000,
        heightPx: 1000,
        polygon: const [
          Point2(0.0, 0.0),
          Point2(0.01, 0.0),
          Point2(0.01, 0.01),
          Point2(0.0, 0.01),
        ],
      );
      final summary = computeRoomAreasV2(plan: plan, scale: scale);
      expect(summary.rooms, hasLength(1), reason: 'room을 목록에서 삭제하지 않는다.');
      final room = summary.rooms.single;
      expect(room.includedInTotal, isFalse);
      expect(room.exclusionReason, isNotNull);
      expect(summary.totalAreaM2, 0);
    });

    test('자기교차하는 polygon은 유효하지 않음으로 표시되고 합계에서 제외된다', () {
      // 나비넥타이(bowtie) 형태 — 변끼리 교차한다.
      final plan = _planWithSquareRoom(
        widthPx: 1000,
        heightPx: 1000,
        polygon: const [
          Point2(0.0, 0.0),
          Point2(1.0, 1.0),
          Point2(1.0, 0.0),
          Point2(0.0, 1.0),
        ],
      );
      final summary = computeRoomAreasV2(plan: plan, scale: scale);
      final room = summary.rooms.single;
      expect(room.includedInTotal, isFalse);
      expect(room.polygonMm, isEmpty);
      expect(room.exclusionReason, contains('유효하지 않음'));
    });

    test('거의 같은 자리에 겹치는 두 room 중 하나만 합계에 포함된다(중복 후보)', () {
      final plan = CadFloorPlan(
        sourceWidthPx: 1000,
        sourceHeightPx: 1000,
        walls: const [],
        openings: const [],
        rooms: const [
          CadRoom(
            id: 'a',
            polygon: [
              Point2(0.0, 0.0),
              Point2(0.5, 0.0),
              Point2(0.5, 0.5),
              Point2(0.0, 0.5),
            ],
            areaNormalized: 0.25,
            confidence: 0.9,
          ),
          CadRoom(
            id: 'b',
            polygon: [
              Point2(0.0, 0.0),
              Point2(0.49, 0.0),
              Point2(0.49, 0.49),
              Point2(0.0, 0.49),
            ],
            areaNormalized: 0.24,
            confidence: 0.4,
          ),
        ],
        warnings: [],
      );
      final summary = computeRoomAreasV2(plan: plan, scale: scale);
      final included = summary.rooms.where((r) => r.includedInTotal).toList();
      expect(included, hasLength(1), reason: '겹치는 두 room 중 하나만 합계에 남아야 한다.');
      expect(included.single.id, 'a', reason: '면적이 더 큰(신뢰도 반영) 쪽을 남긴다.');
    });
  });
}
