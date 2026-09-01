import 'package:flutter/foundation.dart';

/// 사용자가 업로드한 평면도 파일의 형식. PDF는 이미지처럼 디코드하지 않고
/// 파일명/아이콘 기반 placeholder로만 다룬다(WO 12번 — crash 위험 회피).
enum FloorPlanFileKind { image, pdf }

/// "① 평면도 업로드"에서 사용자가 실제로 선택한 파일 한 개.
@immutable
class FloorPlanFile {
  const FloorPlanFile({
    required this.fileName,
    required this.extension,
    required this.kind,
    required this.sizeBytes,
    this.bytes,
  });

  final String fileName;

  /// 소문자, 점(.) 없는 확장자(예: "jpg", "png", "pdf").
  final String extension;
  final FloorPlanFileKind kind;
  final int sizeBytes;

  /// 이미지 미리보기에 쓰는 실제 바이트. PDF는 렌더링 엔진이 없어 이 값을
  /// 미리보기에 사용하지 않는다(파일명/아이콘만 표시).
  final Uint8List? bytes;
}

/// "평면도 분석 시작" 버튼을 누른 뒤의 진행 상태.
///
/// [analyzing] 동안 실제로 어느 단계인지는
/// `FloorPlanAnalysisStep`(floor_plan_geometry.dart)이 담당한다. 분석이
/// 실제 결과를 내면 [completed](FloorPlanAnalysisResult 보유), 벽 후보를
/// 찾지 못했거나 오류가 나면 [failed](실패 메시지 보유)로 정직하게
/// 구분한다 — 항상 "준비 중"만 반환하던 이전 placeholder는 제거했다.
enum FloorPlanAnalysisPhase { notStarted, analyzing, completed, failed }
