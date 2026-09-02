// 실제 픽셀 파이프라인(Otsu/run-length/flood-fill) → SSSpatialModelBuilder
// 전체 연결 테스트.
//
// PC2 재작업 WO — "굵은 선=벽, 얇은 선=가구 같은 규칙을 핵심 판단
// 기준으로 쓰지 않는다"의 핵심 근거. 가구를 두꺼운 채움 블록이 아니라
// 실제 벽과 "같은 두께의 얇은 외곽선"으로 그리면, 순수 두께 필터만
// 쓰는 엔진은 그 외곽선을 진짜 벽으로 오인해 내부를 별도의 작은 "방"
// 으로 flood-fill한다 — 이 케이스가 바로 SSSpatialModelBuilder의
// 포함 관계 판단이 잡아내야 하는 대상이다.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:ason_space/models/floor_plan_geometry.dart';
import 'package:ason_space/models/ss_spatial_model.dart';
import 'package:ason_space/services/floor_plan_analysis_engine.dart';
import 'package:ason_space/services/ss_spatial_model_builder.dart';

Uint8List _encodePng(img.Image image) =>
    Uint8List.fromList(img.encodePng(image));

/// 400x300 방(10px 외벽) 안, 벽에 닿지 않는 위치에 "가구"를 그린다 —
/// 채워진 두꺼운 블록이 아니라 실제 벽과 같은 두께(2px)의 얇은 사각형
/// 외곽선(속은 흰 배경 그대로)이라, 두께만으로는 벽과 구분되지 않는다.
Uint8List _buildRoomWithThinOutlinedFurniture() {
  final image = img.Image(width: 400, height: 300);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  final black = img.ColorRgb8(0, 0, 0);

  img.fillRect(image, x1: 10, y1: 10, x2: 390, y2: 20, color: black);
  img.fillRect(image, x1: 10, y1: 280, x2: 390, y2: 290, color: black);
  img.fillRect(image, x1: 10, y1: 10, x2: 20, y2: 290, color: black);
  img.fillRect(image, x1: 380, y1: 10, x2: 390, y2: 290, color: black);

  // 가구(예: 침대) 윤곽선 — 실제 벽(10px)보다 얇은 2px 테두리만, 속은
  // 채우지 않는다.
  img.drawRect(image, x1: 150, y1: 100, x2: 250, y2: 200, color: black);
  img.drawRect(image, x1: 151, y1: 101, x2: 249, y2: 199, color: black);

  return _encodePng(image);
}

void main() {
  test('실제 벽과 같은 두께의 얇은 외곽선으로 그려진 가구는, 엔진 단계에서는 '
      '"벽"으로 오인되어 작은 방을 만들지만, SSSpatialModelBuilder가 '
      '포함 관계로 가구/설비 후보로 재분류해 최종 공간 목록에서는 '
      '제외한다', () {
    final wallStage = detectWallsAndOpenings(
      WallStageInput(_buildRoomWithThinOutlinedFurniture()),
    );
    expect(wallStage.isSuccess, isTrue);

    final roomStage = detectRooms(
      RoomStageInput(
        mask: wallStage.mask!,
        width: wallStage.analysisWidthPx,
        height: wallStage.analysisHeightPx,
      ),
    );
    // 엔진(evidence) 단계만 보면 가구 내부가 별도의 작은 "방 후보"로
    // 잡혀 2개가 나온다 — 이게 바로 이번 재작업이 해결하려는 문제다.
    expect(roomStage.rooms.length, greaterThanOrEqualTo(2));

    final result = FloorPlanAnalysisResult(
      sourceWidthPx: wallStage.sourceWidthPx,
      sourceHeightPx: wallStage.sourceHeightPx,
      walls: wallStage.walls,
      openings: wallStage.openings,
      rooms: roomStage.rooms,
      warnings: const [],
      debugStats: FloorPlanAnalysisDebugStats(
        sourceWidthPx: wallStage.sourceWidthPx,
        sourceHeightPx: wallStage.sourceHeightPx,
        analysisWidthPx: wallStage.analysisWidthPx,
        analysisHeightPx: wallStage.analysisHeightPx,
        rawHorizontalRuns: wallStage.rawHorizontalRuns,
        rawVerticalRuns: wallStage.rawVerticalRuns,
        mergedWallCount: wallStage.walls.length,
        roomCandidateCount: roomStage.rooms.length,
        openingCandidateCount: wallStage.openings.length,
        durationMs: 1,
      ),
    );

    final model = const SSSpatialModelBuilder().build(result);

    // 해석 단계를 거치면 실제 방은 1개만 남아야 한다 — 가구 내부는
    // SSSpace가 아니라 SSObjectCandidate로 분류된다.
    expect(model.spaces, hasLength(1));
    expect(model.objects, isNotEmpty);
    expect(
      model.objects.every((o) => o.kind == SSObjectKind.furnitureOrEquipment),
      isTrue,
    );
  });
}
