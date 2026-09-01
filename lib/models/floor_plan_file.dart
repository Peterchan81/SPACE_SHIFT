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
/// 실제 벽/문/창문 인식 백엔드가 아직 없으므로, [analyzing] 다음에는
/// 항상 [unavailable]로 끝난다 — 분석이 끝난 것처럼 거짓 결과를 만들지
/// 않는다(WO 7-B).
enum FloorPlanAnalysisPhase { notStarted, analyzing, unavailable }
