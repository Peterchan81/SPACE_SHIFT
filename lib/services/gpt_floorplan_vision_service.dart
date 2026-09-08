import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config/app_environment.dart';
import '../models/vision_understanding.dart';
import 'vision_interpretation_service.dart';

/// GPT FLOORPLAN → STRUCTURED 2D → REAL 3D ISO FLOW WO §5 —
/// [VisionInterpretationService]의 실제 production 구현. OpenAI API key는
/// 이 클래스 어디에도 없다 — Supabase Edge Function(`supabase/functions/
/// gpt-floorplan-understand`)만 호출하고, 그 함수 안에서만 secret을
/// 읽는다. 요청/응답/에러 처리 패턴은 기존
/// [EdgeFunctionAiGenerationService](edge_function_ai_generation_service.dart)
/// 를 그대로 재사용한다 — 이 프로젝트에 이미 검증된 "Flutter → Edge
/// Function → 외부 AI" 패턴을 새로 발명하지 않는다.
///
/// 응답 JSON은 [VisionUnderstanding.toJson]/[VisionUnderstanding.fromJson]
/// 계약을 그대로 따른다 — 이 계약은 WO088 Vision Guided CAD POC에서 이미
/// 만들어져 있던 것을 그대로 재사용한다(§3/§4, 새 스키마를 새로 만들지
/// 않는다).
class GptFloorplanEdgeFunctionVisionService implements VisionInterpretationService {
  GptFloorplanEdgeFunctionVisionService({required this.endpoint, http.Client? client})
    : _client = client ?? http.Client();

  final Uri endpoint;
  final http.Client _client;

  @override
  Future<VisionUnderstanding> interpret(Uint8List imageBytes) async {
    final response = await _client
        .post(
          endpoint,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'image': _toDataUri(imageBytes)}),
        )
        .timeout(const Duration(seconds: 60));

    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('GPT 평면도 분석 서버 응답을 확인할 수 없습니다.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300 || payload['success'] != true) {
      throw Exception(payload['message'] ?? 'GPT 평면도 분석에 실패했습니다.');
    }

    final understanding = payload['understanding'];
    if (understanding is! Map<String, dynamic>) {
      throw Exception('GPT 평면도 분석 결과 형식을 확인할 수 없습니다.');
    }
    return VisionUnderstanding.fromJson(understanding);
  }

  String _toDataUri(Uint8List bytes) {
    final isPng = bytes.length >= 8 && bytes[0] == 137 && bytes[1] == 80 && bytes[2] == 78 && bytes[3] == 71;
    final mimeType = isPng ? 'image/png' : 'image/jpeg';
    return 'data:$mimeType;base64,${base64Encode(bytes)}';
  }
}

/// §5/§18 — Edge Function URL이 아직 설정되지 않은(=OpenAI secret도 아직
/// 배포되지 않은) 환경에서 쓰는 안전한 기본값. 실제 네트워크 호출을 전혀
/// 시도하지 않고 즉시, 정직하게 실패한다 — [UnavailableSemanticProvider]
/// (pixel_wall_v4/semantic_provider.dart)와 정확히 같은 원칙: "아직 연결
///되지 않았다"를 조용히 숨기거나 가짜로 성공한 것처럼 굴지 않는다. 호출부
/// (VisionGuidedSpatialModelBuilder)는 이 실패를 받아 기존 geometry 전용
/// 분석으로 안전하게 폴백한다.
class UnavailableVisionInterpretationService implements VisionInterpretationService {
  const UnavailableVisionInterpretationService();

  @override
  Future<VisionUnderstanding> interpret(Uint8List imageBytes) async {
    throw Exception('GPT 평면도 분석 기능이 아직 설정되지 않았습니다.');
  }
}

/// [AppEnvironment.gptFloorPlanEdgeFunctionUrl]이 설정되어 있으면 실제
/// Edge Function 구현을, 없으면 [UnavailableVisionInterpretationService]를
/// 돌려준다 — [createAiGenerationService](ai_generation_provider.dart)와
/// 동일한 "URL이 없으면 안전하게 폴백" 팩토리 패턴.
///
/// WO090 — [urlOverride]는 [ai_generation_provider.dart]의
/// `edgeFunctionUrlOverride`와 동일한 이유로 존재한다: dart-define 없이도
/// "URL이 실제로 설정된 경우" 분기를 테스트할 수 있게 한다. 지정하지
/// 않으면(실사용 경로) [AppEnvironment.gptFloorPlanEdgeFunctionUrl]을 쓴다.
VisionInterpretationService createVisionInterpretationService({String? urlOverride}) {
  final url = urlOverride ?? AppEnvironment.gptFloorPlanEdgeFunctionUrl;
  if (url.isEmpty) return const UnavailableVisionInterpretationService();
  return GptFloorplanEdgeFunctionVisionService(endpoint: Uri.parse(url));
}
