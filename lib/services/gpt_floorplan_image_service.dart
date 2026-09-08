import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config/app_environment.dart';

/// V1 AI-IMAGE FLOW WO — 방향 수정: GPT는 좌표/topology가 아니라, 원본
/// 평면도 사진의 배치를 최대한 유지한 "깨끗한 CAD 스타일 2D 평면도
/// 이미지"를 새로 그려서 돌려준다. [VisionInterpretationService]
/// (구조화 좌표 계약, gpt_floorplan_vision_service.dart)와는 목적이
/// 완전히 다른 별도 서비스다 — 그 파일은 삭제하지 않고 R&D/대체
/// 경로로 남겨 둔다.
abstract class FloorPlanImageGenerationService {
  Future<Uint8List> generate(Uint8List originalImageBytes);
}

/// [FloorPlanImageGenerationService]의 실제 production 구현. OpenAI API
/// key는 이 클래스 어디에도 없다 — Supabase Edge Function
/// (`supabase/functions/gpt-floorplan-cad-image`)만 호출하고, 그 함수
/// 안에서만 secret을 읽는다. 요청/응답/에러 처리 패턴은 기존
/// [EdgeFunctionAiGenerationService]/[GptFloorplanEdgeFunctionVisionService]
/// 와 동일한 "Flutter → Edge Function → 외부 AI" 패턴을 그대로 재사용한다.
class GptFloorplanCadImageService implements FloorPlanImageGenerationService {
  GptFloorplanCadImageService({required this.endpoint, http.Client? client})
    : _client = client ?? http.Client();

  final Uri endpoint;
  final http.Client _client;

  @override
  Future<Uint8List> generate(Uint8List originalImageBytes) async {
    final response = await _client
        .post(
          endpoint,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'image': _toDataUri(originalImageBytes)}),
        )
        .timeout(const Duration(seconds: 120));

    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('AI 평면도 생성 서버 응답을 확인할 수 없습니다.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300 || payload['success'] != true) {
      throw Exception(payload['message'] ?? 'AI 평면도 생성에 실패했습니다.');
    }

    final image = payload['image'];
    if (image is! String || !image.startsWith('data:')) {
      throw Exception('AI 평면도 생성 결과 형식을 확인할 수 없습니다.');
    }
    final commaIndex = image.indexOf(',');
    if (commaIndex == -1) {
      throw Exception('AI 평면도 생성 결과 형식을 확인할 수 없습니다.');
    }
    return base64Decode(image.substring(commaIndex + 1));
  }

  String _toDataUri(Uint8List bytes) {
    final isPng = bytes.length >= 8 && bytes[0] == 137 && bytes[1] == 80 && bytes[2] == 78 && bytes[3] == 71;
    final mimeType = isPng ? 'image/png' : 'image/jpeg';
    return 'data:$mimeType;base64,${base64Encode(bytes)}';
  }
}

/// Edge Function URL이 아직 설정되지 않은 환경에서 쓰는 안전한 기본값 —
/// 실제 네트워크 호출을 전혀 시도하지 않고 즉시, 정직하게 실패한다.
/// 호출부는 이 실패를 받아 원본 사진을 그대로 보여주는 것으로 안전하게
/// 폴백한다.
class UnavailableFloorPlanImageGenerationService implements FloorPlanImageGenerationService {
  const UnavailableFloorPlanImageGenerationService();

  @override
  Future<Uint8List> generate(Uint8List originalImageBytes) async {
    throw Exception('AI 평면도 생성 기능이 아직 설정되지 않았습니다.');
  }
}

/// [AppEnvironment.gptFloorPlanImageEdgeFunctionUrl]이 설정되어 있으면
/// 실제 Edge Function 구현을, 없으면
/// [UnavailableFloorPlanImageGenerationService]를 돌려준다.
///
/// [urlOverride]는 dart-define 없이도 "URL이 실제로 설정된 경우" 분기를
/// 테스트할 수 있게 한다(createVisionInterpretationService와 동일한 이유).
FloorPlanImageGenerationService createFloorPlanImageGenerationService({String? urlOverride}) {
  final url = urlOverride ?? AppEnvironment.gptFloorPlanImageEdgeFunctionUrl;
  if (url.isEmpty) return const UnavailableFloorPlanImageGenerationService();
  return GptFloorplanCadImageService(endpoint: Uri.parse(url));
}
