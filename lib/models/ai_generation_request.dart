import 'package:flutter/foundation.dart';

import 'work_instruction.dart';

/// AI 인테리어 이미지 생성을 요청할 때 필요한 데이터를 담는 불변 모델.
///
/// 이 구조는 실제로 어떤 AI 서비스(OpenAI, Gemini, Fal.ai 등)를 사용하든
/// 바뀌지 않는다. UI(화면)와 [AiGenerationService] 구현 사이의 계약 역할을
/// 하며, AI 서비스가 교체되어도 이 모델은 그대로 유지된다.
@immutable
class AiGenerationRequest {
  const AiGenerationRequest({
    required this.imageBytes,
    required this.selectedStyle,
    required this.createdAt,
    required this.appVersion,
    this.workInstructions = const [],
    this.additionalNotes = '',
  });

  /// 사용자가 선택(촬영)한 원본 사진 데이터.
  final Uint8List imageBytes;

  /// 사용자가 선택한 인테리어 스타일 이름 (예: 모던, 미니멀).
  final String selectedStyle;

  /// 요청이 생성된 시각.
  final DateTime createdAt;

  /// 요청을 보낸 앱의 버전. 추후 서버/AI 응답 호환성 추적 등에 활용할 수 있다.
  final String appVersion;

  /// 공간 작업실(4번 화면)에서 사용자가 지정한, 부위별 부분 선택 + 작업 지시 목록.
  /// 비어 있을 수 있다(예: 스타일만 선택하고 넘어온 이전 흐름과의 호환).
  final List<WorkInstruction> workInstructions;

  /// 특정 부위에 묶이지 않는 추가 작업 지시(예: "전등은 간접조명, 바닥은 밝은 원목으로").
  final String additionalNotes;

  /// 지정한 필드만 바꾼 새 인스턴스를 반환한다.
  AiGenerationRequest copyWith({
    Uint8List? imageBytes,
    String? selectedStyle,
    DateTime? createdAt,
    String? appVersion,
    List<WorkInstruction>? workInstructions,
    String? additionalNotes,
  }) {
    return AiGenerationRequest(
      imageBytes: imageBytes ?? this.imageBytes,
      selectedStyle: selectedStyle ?? this.selectedStyle,
      createdAt: createdAt ?? this.createdAt,
      appVersion: appVersion ?? this.appVersion,
      workInstructions: workInstructions ?? this.workInstructions,
      additionalNotes: additionalNotes ?? this.additionalNotes,
    );
  }

  @override
  String toString() {
    return 'AiGenerationRequest('
        'imageBytesLength: ${imageBytes.length}, '
        'selectedStyle: $selectedStyle, '
        'createdAt: $createdAt, '
        'appVersion: $appVersion, '
        'workInstructions: ${workInstructions.length}, '
        'additionalNotes: $additionalNotes)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AiGenerationRequest &&
        listEquals(other.imageBytes, imageBytes) &&
        other.selectedStyle == selectedStyle &&
        other.createdAt == createdAt &&
        other.appVersion == appVersion &&
        listEquals(other.workInstructions, workInstructions) &&
        other.additionalNotes == additionalNotes;
  }

  @override
  int get hashCode => Object.hash(
        // Uint8List 전체를 매번 해시하면 큰 이미지에서 비용이 크므로
        // 길이만 사용한다. ==는 내용까지 정확히 비교하므로 계약은 유지된다.
        imageBytes.length,
        selectedStyle,
        createdAt,
        appVersion,
        workInstructions.length,
        additionalNotes,
      );
}
