import 'package:flutter/foundation.dart';

import '../models/floor_plan_file.dart';
import '../models/floor_plan_geometry.dart';
import 'floor_plan_analysis_engine.dart' as engine;

/// 평면도(벽/문/창/공간 후보) 분석 service boundary.
///
/// 실제 픽셀 처리(grayscale/Otsu 이진화/run-length 벽 검출/flood fill
/// 방 검출)는 [floor_plan_analysis_engine.dart]에 있고, 여기서는 그 두
/// 단계를 [compute]로 백그라운드 isolate에 위임한 뒤(WO 22번) 결과를
/// 화면이 쓰는 [FloorPlanAnalysisOutcome]으로 조립하는 역할만 한다.
///
/// PDF는 아직 렌더링/디코드 엔진이 없어 분석을 지원하지 않는다 — 정직하게
/// [FloorPlanAnalysisFailureReason.unsupportedFormat]으로 실패 처리한다
/// (WO 16번, 가짜 분석 완료를 만들지 않는다).
class FloorPlanAnalysisService {
  const FloorPlanAnalysisService();

  Future<FloorPlanAnalysisOutcome> analyze(
    FloorPlanFile file, {
    void Function(FloorPlanAnalysisStep step)? onStep,
  }) async {
    if (file.kind != FloorPlanFileKind.image || file.bytes == null) {
      return const FloorPlanAnalysisOutcome.failure(
        FloorPlanAnalysisFailureReason.unsupportedFormat,
        'PDF 분석은 다음 단계에서 지원할 예정입니다. 지금은 JPG/PNG만 분석할 수 있습니다.',
      );
    }

    onStep?.call(FloorPlanAnalysisStep.preparingAndWalls);

    engine.WallStageResult wallStage;
    try {
      wallStage = await compute(
        engine.detectWallsAndOpenings,
        engine.WallStageInput(file.bytes!),
      );
    } catch (_) {
      return const FloorPlanAnalysisOutcome.failure(
        FloorPlanAnalysisFailureReason.internalError,
        '평면도 분석 중 문제가 발생했습니다. 잠시 후 다시 시도해주세요.',
      );
    }

    if (!wallStage.isSuccess) {
      return FloorPlanAnalysisOutcome.failure(
        wallStage.failureReason!,
        _messageFor(wallStage.failureReason!),
      );
    }

    if (wallStage.walls.isEmpty) {
      return const FloorPlanAnalysisOutcome.failure(
        FloorPlanAnalysisFailureReason.noWallsFound,
        '평면도 구조를 충분히 인식하지 못했습니다.\n직접 보정할 수 있도록 원본을 유지했습니다.',
      );
    }

    onStep?.call(FloorPlanAnalysisStep.roomsAndOpenings);

    engine.RoomStageResult roomStage;
    try {
      roomStage = await compute(
        engine.detectRooms,
        engine.RoomStageInput(
          mask: wallStage.mask!,
          width: wallStage.analysisWidthPx,
          height: wallStage.analysisHeightPx,
        ),
      );
    } catch (_) {
      return const FloorPlanAnalysisOutcome.failure(
        FloorPlanAnalysisFailureReason.internalError,
        '평면도 분석 중 문제가 발생했습니다. 잠시 후 다시 시도해주세요.',
      );
    }

    onStep?.call(FloorPlanAnalysisStep.finalizing);

    final warnings = <String>[];
    if (roomStage.rooms.isEmpty) {
      warnings.add('공간이 완전히 닫히지 않았습니다. 벽을 직접 보정해주세요.');
    }

    final result = FloorPlanAnalysisResult(
      sourceWidthPx: wallStage.sourceWidthPx,
      sourceHeightPx: wallStage.sourceHeightPx,
      walls: wallStage.walls,
      openings: wallStage.openings,
      rooms: roomStage.rooms,
      warnings: warnings,
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
        durationMs: wallStage.elapsedMs + roomStage.elapsedMs,
      ),
    );

    return FloorPlanAnalysisOutcome.success(result);
  }

  String _messageFor(FloorPlanAnalysisFailureReason reason) {
    switch (reason) {
      case FloorPlanAnalysisFailureReason.unreadableImage:
        return '이미지를 읽지 못했습니다. 다른 파일로 다시 시도해주세요.';
      case FloorPlanAnalysisFailureReason.tooSmall:
        return '이미지가 너무 작아 분석할 수 없습니다. 더 큰 해상도의 평면도를 사용해주세요.';
      case FloorPlanAnalysisFailureReason.noWallsFound:
        return '평면도 구조를 충분히 인식하지 못했습니다.\n직접 보정할 수 있도록 원본을 유지했습니다.';
      case FloorPlanAnalysisFailureReason.unsupportedFormat:
        return 'PDF 분석은 다음 단계에서 지원할 예정입니다. 지금은 JPG/PNG만 분석할 수 있습니다.';
      case FloorPlanAnalysisFailureReason.internalError:
        return '평면도 분석 중 문제가 발생했습니다. 잠시 후 다시 시도해주세요.';
    }
  }
}
