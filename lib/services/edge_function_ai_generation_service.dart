import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config/app_environment.dart';
import '../models/ai_generation_request.dart';
import 'ai_generation_service.dart';

/// Supabase Edge Function만 호출하는 실제 AI 생성 서비스.
/// AI Provider Secret은 Flutter에 전달하거나 저장하지 않는다.
class EdgeFunctionAiGenerationService extends AiGenerationService {
  EdgeFunctionAiGenerationService({required this.endpoint, http.Client? client})
    : _client = client ?? http.Client(),
      super(provider: AiProviderType.fal);

  final Uri endpoint;
  final http.Client _client;

  @override
  Future<Uint8List?> requestGeneration(AiGenerationRequest request) async {
    final response = await _client
        .post(
          endpoint,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'style': request.selectedStyle,
            'image': _toDataUri(request.imageBytes),
          }),
        )
        .timeout(const Duration(minutes: 2));

    Map<String, dynamic> payload;
    try {
      payload =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('AI 서버 응답을 확인할 수 없습니다.');
    }

    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      throw Exception(payload['message'] ?? 'AI 이미지 생성에 실패했습니다.');
    }

    final imageUrl = payload['imageUrl'];
    if (imageUrl is! String || imageUrl.isEmpty) {
      throw Exception('생성된 이미지 주소가 없습니다.');
    }

    final imageResponse = await _client
        .get(Uri.parse(imageUrl))
        .timeout(const Duration(seconds: 30));
    if (imageResponse.statusCode < 200 || imageResponse.statusCode >= 300) {
      throw Exception('생성된 이미지를 불러오지 못했습니다.');
    }
    return imageResponse.bodyBytes;
  }

  String _toDataUri(Uint8List bytes) {
    final isPng =
        bytes.length >= 8 &&
        bytes[0] == 137 &&
        bytes[1] == 80 &&
        bytes[2] == 78 &&
        bytes[3] == 71;
    final mimeType = isPng ? 'image/png' : 'image/jpeg';
    return 'data:$mimeType;base64,${base64Encode(bytes)}';
  }
}
