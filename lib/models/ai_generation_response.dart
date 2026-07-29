import 'package:flutter/foundation.dart';

/// AI 인테리어 이미지 생성 결과를 담는 불변 모델.
///
/// [AiGenerationService]의 반환 타입으로, 실제 AI 서비스가 무엇이든
/// 화면(UI)은 이 구조만 알면 된다.
@immutable
class AiGenerationResponse {
  const AiGenerationResponse({
    required this.success,
    this.generatedImageBytes,
    this.errorMessage,
    required this.elapsedTime,
  });

  /// 생성 성공 여부.
  final bool success;

  /// AI가 생성한 이미지 데이터. 아직 생성되지 않았거나 실패한 경우 null.
  final Uint8List? generatedImageBytes;

  /// 실패했을 때의 오류 메시지. 성공한 경우 null.
  final String? errorMessage;

  /// 요청부터 응답까지 걸린 시간.
  final Duration elapsedTime;

  /// 지정한 필드만 바꾼 새 인스턴스를 반환한다.
  AiGenerationResponse copyWith({
    bool? success,
    Uint8List? generatedImageBytes,
    String? errorMessage,
    Duration? elapsedTime,
  }) {
    return AiGenerationResponse(
      success: success ?? this.success,
      generatedImageBytes: generatedImageBytes ?? this.generatedImageBytes,
      errorMessage: errorMessage ?? this.errorMessage,
      elapsedTime: elapsedTime ?? this.elapsedTime,
    );
  }

  @override
  String toString() {
    return 'AiGenerationResponse('
        'success: $success, '
        'generatedImageBytesLength: ${generatedImageBytes?.length}, '
        'errorMessage: $errorMessage, '
        'elapsedTime: $elapsedTime)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AiGenerationResponse &&
        other.success == success &&
        listEquals(other.generatedImageBytes, generatedImageBytes) &&
        other.errorMessage == errorMessage &&
        other.elapsedTime == elapsedTime;
  }

  @override
  int get hashCode => Object.hash(
        success,
        generatedImageBytes?.length,
        errorMessage,
        elapsedTime,
      );
}
