// AiGenerationService에 대한 단위 테스트.
//
// 1. Mock 이미지 asset(assets/images/mock_ai_result.png) 로드에 성공하는지
//    확인한다. (Asset 로드 성공 테스트)
// 2. generate()가 3초 대기 후 성공 응답을 반환하며, generatedImageBytes가
//    null이 아닌지 확인한다. (AiGenerationService 성공 응답 테스트)
// 3. requestGeneration()에서 예외가 발생해도 앱이 죽지 않고 success=false인
//    응답으로 안전하게 변환되는지 확인한다. (예외 처리 테스트)

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/ai_generation_request.dart';
import 'package:ason_space/services/ai_generation_service.dart';

/// PNG 파일의 매직 넘버(시그니처). 반환된 바이트가 실제 PNG 데이터인지
/// 확인하는 데 사용한다.
const List<int> _pngSignature = [137, 80, 78, 71, 13, 10, 26, 10];

/// requestGeneration()에서 항상 예외를 던지는 가짜 서비스.
/// generate()의 예외 안전 처리를 검증하기 위해 사용한다.
class _ThrowingAiGenerationService extends AiGenerationService {
  const _ThrowingAiGenerationService();

  @override
  Future<Uint8List?> requestGeneration(AiGenerationRequest request) async {
    throw Exception('가짜 AI 생성 오류');
  }
}

void main() {
  // rootBundle을 통한 asset 로드는 ServicesBinding(플랫폼 바인딩)이
  // 초기화되어 있어야 동작하므로, testWidgets가 아닌 일반 test에서도
  // 명시적으로 바인딩을 초기화해 둔다.
  TestWidgetsFlutterBinding.ensureInitialized();

  AiGenerationRequest buildRequest() {
    return AiGenerationRequest(
      imageBytes: Uint8List.fromList([1, 2, 3, 4]),
      selectedStyle: '모던',
      createdAt: DateTime.now(),
      appVersion: '1.0.0',
    );
  }

  test('mock_ai_result.png asset을 정상적으로 읽을 수 있다', () async {
    final byteData = await rootBundle.load('assets/images/mock_ai_result.png');
    final bytes = byteData.buffer.asUint8List();

    expect(bytes, isNotEmpty);
    expect(bytes.sublist(0, 8), equals(_pngSignature));
  });

  test(
    'generate는 3초 대기 후 Mock 이미지가 담긴 성공 응답을 반환한다',
    () async {
      const service = AiGenerationService();

      final response = await service.generate(buildRequest());

      expect(response.success, isTrue);
      expect(response.errorMessage, isNull);
      expect(response.elapsedTime, const Duration(seconds: 3));

      // generatedImageBytes가 null이 아니며, 실제 PNG 데이터여야 한다.
      final generatedImageBytes = response.generatedImageBytes;
      expect(generatedImageBytes, isNotNull);
      expect(generatedImageBytes, isNotEmpty);
      expect(
        generatedImageBytes!.sublist(0, 8),
        equals(_pngSignature),
      );
    },
    // 실제 3초 대기를 그대로 검증하므로 기본 타임아웃보다 넉넉하게 잡는다.
    timeout: const Timeout(Duration(seconds: 10)),
  );

  test('내부 요청에서 예외가 발생하면 success=false와 errorMessage를 담아 반환한다', () async {
    const service = _ThrowingAiGenerationService();

    final response = await service.generate(buildRequest());

    expect(response.success, isFalse);
    expect(response.generatedImageBytes, isNull);
    expect(response.errorMessage, isNotNull);
    expect(response.errorMessage, contains('가짜 AI 생성 오류'));
  });
}
