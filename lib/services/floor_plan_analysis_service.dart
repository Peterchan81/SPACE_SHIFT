import '../models/floor_plan_file.dart';

/// 평면도(벽/문/창문 인식 등) 분석을 담당할 백엔드의 service boundary.
///
/// 현재 저장소에는 실제 floor plan parsing/CV/AI 분석 백엔드가 없다 —
/// 조사 결과 확인된 사실이며, 없는 결과를 지어내지 않는다(WO 7-B).
/// 그래서 이 기본 구현은 짧게 기다렸다가 항상 "아직 준비되지 않음"을
/// 반환한다. 실제 분석 엔진이 준비되면 이 클래스 내부(또는 이 타입을
/// 구현하는 새 클래스)만 교체하면 되고, 화면 쪽 상태 흐름
/// ([FloorPlanAnalysisPhase])은 바뀌지 않는다.
class FloorPlanAnalysisService {
  const FloorPlanAnalysisService();

  Future<FloorPlanAnalysisPhase> analyze(FloorPlanFile file) async {
    await Future.delayed(const Duration(milliseconds: 900));
    return FloorPlanAnalysisPhase.unavailable;
  }
}
