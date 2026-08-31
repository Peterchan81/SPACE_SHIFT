import 'package:flutter/foundation.dart';

import 'space_task.dart';

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
    this.tasks = const [],
  });

  /// 사용자가 선택(촬영)한 원본 사진 데이터.
  /// 수정 재요청 흐름에서는 이전 AI 생성 결과 이미지가 전달될 수 있다.
  final Uint8List imageBytes;

  /// AI Provider에 전달하는 요약 지시 문구.
  /// 공간 작업실 흐름에서는 [tasks]의 내용을 합쳐 생성한다.
  final String selectedStyle;

  /// 요청이 생성된 시각.
  final DateTime createdAt;

  /// 요청을 보낸 앱의 버전. 추후 서버/AI 응답 호환성 추적 등에 활용할 수 있다.
  final String appVersion;

  /// 공간 작업실에서 등록한 영역별 작업 목록(카테고리/좌표/지시 텍스트/참고
  /// 이미지). 스타일 선택 등 이전 방식의 요청에서는 비어 있을 수 있다.
  final List<SpaceTask> tasks;

  /// 지정한 필드만 바꾼 새 인스턴스를 반환한다.
  AiGenerationRequest copyWith({
    Uint8List? imageBytes,
    String? selectedStyle,
    DateTime? createdAt,
    String? appVersion,
    List<SpaceTask>? tasks,
  }) {
    return AiGenerationRequest(
      imageBytes: imageBytes ?? this.imageBytes,
      selectedStyle: selectedStyle ?? this.selectedStyle,
      createdAt: createdAt ?? this.createdAt,
      appVersion: appVersion ?? this.appVersion,
      tasks: tasks ?? this.tasks,
    );
  }

  @override
  String toString() {
    return 'AiGenerationRequest('
        'imageBytesLength: ${imageBytes.length}, '
        'selectedStyle: $selectedStyle, '
        'createdAt: $createdAt, '
        'appVersion: $appVersion)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AiGenerationRequest &&
        listEquals(other.imageBytes, imageBytes) &&
        other.selectedStyle == selectedStyle &&
        other.createdAt == createdAt &&
        other.appVersion == appVersion;
  }

  @override
  int get hashCode => Object.hash(
        // Uint8List 전체를 매번 해시하면 큰 이미지에서 비용이 크므로
        // 길이만 사용한다. ==는 내용까지 정확히 비교하므로 계약은 유지된다.
        imageBytes.length,
        selectedStyle,
        createdAt,
        appVersion,
      );
}
