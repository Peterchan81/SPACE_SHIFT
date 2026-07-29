// AiGenerationResponse 모델에 대한 단위 테스트.
//
// 1. 생성자로 값이 올바르게 설정되는지 확인한다. (Response 생성 테스트)
// 2. copyWith가 지정한 필드만 바꾸는지 확인한다. (copyWith 테스트)
// 3. 같은 값을 가진 두 인스턴스가 ==/hashCode로 동등하게 취급되는지 확인한다.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/ai_generation_response.dart';

void main() {
  test('성공 응답 생성자로 전달한 값이 그대로 필드에 저장된다', () {
    const response = AiGenerationResponse(
      success: true,
      elapsedTime: Duration(seconds: 3),
    );

    expect(response.success, isTrue);
    expect(response.generatedImageBytes, isNull);
    expect(response.errorMessage, isNull);
    expect(response.elapsedTime, const Duration(seconds: 3));
  });

  test('실패 응답 생성자로 전달한 값이 그대로 필드에 저장된다', () {
    const response = AiGenerationResponse(
      success: false,
      errorMessage: '알 수 없는 오류',
      elapsedTime: Duration(seconds: 1),
    );

    expect(response.success, isFalse);
    expect(response.generatedImageBytes, isNull);
    expect(response.errorMessage, '알 수 없는 오류');
  });

  test('copyWith은 지정한 필드만 바꾸고 나머지는 유지한다', () {
    const original = AiGenerationResponse(
      success: true,
      elapsedTime: Duration(seconds: 3),
    );

    final updated = original.copyWith(
      success: false,
      errorMessage: '실패했습니다',
    );

    expect(updated.success, isFalse);
    expect(updated.errorMessage, '실패했습니다');
    expect(updated.elapsedTime, original.elapsedTime);
  });

  test('같은 값을 가진 두 응답은 ==와 hashCode가 동일하다', () {
    const a = AiGenerationResponse(success: true, elapsedTime: Duration(seconds: 3));
    const b = AiGenerationResponse(success: true, elapsedTime: Duration(seconds: 3));

    expect(a, equals(b));
    expect(a.hashCode, equals(b.hashCode));
  });

  test('generatedImageBytes 내용까지 비교해 동등성을 판단한다', () {
    final a = AiGenerationResponse(
      success: true,
      generatedImageBytes: Uint8List.fromList([1, 2, 3]),
      elapsedTime: const Duration(seconds: 3),
    );
    final b = AiGenerationResponse(
      success: true,
      generatedImageBytes: Uint8List.fromList([1, 2, 3]),
      elapsedTime: const Duration(seconds: 3),
    );
    final c = AiGenerationResponse(
      success: true,
      generatedImageBytes: Uint8List.fromList([9, 9, 9]),
      elapsedTime: const Duration(seconds: 3),
    );

    expect(a, equals(b));
    expect(a, isNot(equals(c)));
  });
}
