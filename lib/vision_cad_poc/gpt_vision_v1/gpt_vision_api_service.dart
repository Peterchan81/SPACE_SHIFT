import 'dart:typed_data';

/// SPACE SHIFT — Real GPT Vision → Detailed CAD JSON → SS Refinement POC.
///
/// 실제 GPT/OpenAI Vision API를 호출하는 경계. 이 POC 시점에는 이
/// 프로젝트 어디에도 OpenAI API 키가 설정되어 있지 않다(로컬 `.env`
/// 없음, 배포된 Supabase Edge Function은 Fal.ai 전용, 무관한 기능).
/// 따라서 실제 호출은 [GptVisionAuthRequiredException]을 던진다 — 이
/// 예외를 삼키고 가짜 성공으로 위장하지 않는다.
///
/// API 키가 준비되면 [OpenAiGptVisionApiService]의 `_apiKey` 대신 실제
/// 값을 안전한 경로(환경변수 `--dart-define` 또는 서버측 프록시)로
/// 주입하고, 이 클래스의 HTTP 호출부만 완성하면 된다 — 다른 파일
/// (schema/validator/refinement/solver/화면)은 이미 이 인터페이스만
/// 보고 동작하므로 수정할 필요가 없다.
abstract class GptVisionApiService {
  /// 이미지 바이트를 보내 "ss-cad-vision-v1" 스키마의 raw JSON 문자열을
  /// 받는다. 파싱/검증은 호출부([GptCadJsonValidator])의 책임이다 —
  /// 이 서비스는 raw 응답만 돌려준다.
  Future<String> requestCadJson(Uint8List imageBytes);
}

class GptVisionAuthRequiredException implements Exception {
  const GptVisionAuthRequiredException(this.message);
  final String message;

  @override
  String toString() => 'GptVisionAuthRequiredException: $message';
}

/// 실제 OpenAI Vision API 호출 구현체 — 이번 세션에는 API 키가 없어
/// 실행 시 항상 [GptVisionAuthRequiredException]을 던진다. 이 클래스
/// 자체는 삭제하지 않는다 — 키가 준비되면 [requestCadJson] 본문만
/// 채우면 되는 자리로 남겨 둔다.
class OpenAiGptVisionApiService implements GptVisionApiService {
  const OpenAiGptVisionApiService({this.apiKey});

  /// `--dart-define=OPENAI_API_KEY=...` 등 안전한 경로로만 주입한다 —
  /// 이 값을 코드에 하드코딩하거나 공개 바이너리에 포함하지 않는다.
  final String? apiKey;

  static const String promptInstructions = '''
당신은 건축 평면도 이미지를 CAD 재구성을 위해 분석하는 비전 모델입니다.

목적: room label만 찾는 것이 아니라 실제 CAD 재구성이 목적입니다.

반드시:
- 이미지 전체를 먼저 이해한 뒤 구조를 분석하세요.
- 실제 구조적(structural) 벽만 사용하고, 가구/텍스트/설비/문 스윙선/창문 세부선은 제외하세요.
- 모든 주요 exterior projection/indentation을 보존하세요.
- 13개 공간 의미를 모두 유지하세요(픽셀 근거가 약해도 삭제하지 말고 semantic HIGH + geometry LOW로 표시하세요).
- 불확실성은 반드시 confidence로 표현하고, 가짜 정밀도를 만들지 마세요.
- 실제 이미지 픽셀 좌표(top-left origin)를 사용하세요.
- 응답은 JSON만 반환하세요. JSON 외 텍스트를 포함하지 마세요.

스키마: schemaVersion "ss-cad-vision-v1", 필드: image, floorDomain, corners, walls,
spaces, doors, windows, openings, objects, relationships, dimensionHints, reviewReasons.
''';

  @override
  Future<String> requestCadJson(Uint8List imageBytes) async {
    if (apiKey == null || apiKey!.isEmpty) {
      throw const GptVisionAuthRequiredException(
        'OpenAI API key not configured. This project has no .env or safe backend route for '
        'GPT Vision analysis (only a Fal.ai key is deployed, for an unrelated feature). '
        'Provide a key via a safe channel (e.g. --dart-define=OPENAI_API_KEY=...) to enable a real call.',
      );
    }
    // 실제 HTTP 호출은 API 키가 주어졌을 때만 완성한다 — 이번 세션에는
    // 키가 없어 여기까지 도달하지 않는다(도달하면 즉시 명확한 예외로
    // 막아, 미완성 호출이 조용히 잘못된 값을 돌려주지 않게 한다).
    throw UnimplementedError(
      'OpenAiGptVisionApiService.requestCadJson HTTP call is not implemented yet — '
      'wire it once a real API key and safe invocation path are available.',
    );
  }
}
