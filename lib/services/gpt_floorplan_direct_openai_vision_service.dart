import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/vision_understanding.dart';
import 'gpt_floorplan_openai_contract.dart';
import 'vision_interpretation_service.dart';

/// SS CAD TEST — Windows 개발/검증 전용 우회 경로(`--dart-define=
/// GPT_FLOORPLAN_PROVIDER=direct`). [GptFloorplanEdgeFunctionVisionService]
/// (기존 production 경로, Supabase Edge Function을 거친다)와 달리, 이
/// 클래스는 Flutter 앱이 OpenAI Chat Completions를 직접 호출한다 — 실제
/// Supabase 배포/Secret 상태와 무관하게 "OpenAI 응답 자체"를 검증하고
/// 싶을 때만 쓴다.
///
/// [gpt_floorplan_openai_contract.dart]의 model/system prompt/JSON schema/
/// 응답 변환 로직을 그대로 재사용하므로, downstream(VisionGuidedSpatialModelBuilder
/// → buildCad → consolidation → CadFloorPlan)은 이 서비스가 supabase
/// 경로 대신 쓰여도 전혀 수정할 필요가 없다 — 둘 다 같은
/// [VisionUnderstanding] 계약을 돌려준다.
///
/// [apiKey]는 반드시 호출부가(즉 `createVisionInterpretationService`가
/// `--dart-define=OPENAI_API_KEY=...`로 받은 값을) 주입한다 — 이 클래스는
/// key를 저장/로그/예외 메시지 어디에도 노출하지 않는다.
class GptDirectOpenAiVisionService implements VisionInterpretationService {
  GptDirectOpenAiVisionService({required this.apiKey, http.Client? client}) : _client = client ?? http.Client();

  final String apiKey;
  final http.Client _client;

  @override
  Future<VisionUnderstanding> interpret(Uint8List imageBytes) async {
    final imageDataUri = toGptFloorplanImageDataUri(imageBytes);

    http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(kGptFloorplanOpenAiEndpoint),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(buildGptFloorplanOpenAiRequestBody(imageDataUri)),
          )
          .timeout(const Duration(seconds: 60));
    } on TimeoutException {
      debugPrint('[GPT direct] OpenAI 요청 timeout (60s)');
      throw Exception('GPT 평면도 분석 요청이 시간 초과되었습니다.');
    } catch (error) {
      // 네트워크 자체 실패(DNS/연결 거부 등) — key는 절대 로그에 남기지
      // 않는다(error.toString()에 요청 URL/헤더가 섞여 나올 수 있는
      // 클라이언트 예외 타입도 있어, 타입 이름만 남긴다).
      debugPrint('[GPT direct] 네트워크 오류: ${error.runtimeType}');
      throw Exception('GPT 평면도 분석 요청에 실패했습니다.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final isBilling = _isBillingExhausted(response);
      _debugPrintHttpFailure(response.statusCode, isBilling: isBilling);
      if (isBilling) throw const GptBillingExhaustedException();
      throw Exception('GPT 평면도 분석 요청에 실패했습니다.');
    }

    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      debugPrint('[GPT direct] OpenAI 응답이 JSON이 아님(malformed JSON)');
      throw Exception('GPT 평면도 분석 서버 응답을 확인할 수 없습니다.');
    }

    final choices = payload['choices'];
    final firstChoice = (choices is List && choices.isNotEmpty) ? choices.first : null;
    final message = firstChoice is Map ? firstChoice['message'] : null;
    final rawContent = message is Map ? message['content'] : null;
    if (rawContent is! String) {
      debugPrint('[GPT direct] OpenAI 응답에 message.content가 없음(schema mismatch)');
      throw Exception('GPT 평면도 분석 결과가 비어 있습니다.');
    }

    Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(rawContent) as Map<String, dynamic>;
    } catch (_) {
      debugPrint('[GPT direct] GPT content가 JSON이 아님(malformed JSON)');
      throw Exception('GPT 평면도 분석 결과 형식이 올바르지 않습니다.');
    }

    final Map<String, Object?> understanding;
    try {
      understanding = convertGptFloorplanIntermediateJson(parsed);
    } catch (error) {
      debugPrint('[GPT direct] 중간 스키마 변환 실패(schema mismatch): ${error.runtimeType}');
      throw Exception('GPT 평면도 분석 결과 형식을 확인할 수 없습니다.');
    }

    return VisionUnderstanding.fromJson(understanding.cast<String, dynamic>());
  }

  /// 5.항목 요구사항 — 401/403/429/5xx를 개발 로그에서 구분한다. API
  /// key/Authorization 헤더 값은 여기 어디에도 넣지 않는다 — status 숫자만
  /// 남긴다.
  void _debugPrintHttpFailure(int statusCode, {required bool isBilling}) {
    final category = switch (statusCode) {
      401 => '401 auth(키가 유효하지 않음)',
      403 => '403 access(권한 없음)',
      429 when isBilling => '429 billing(크레딧/쿼터 소진 — 재시도 안 함)',
      429 => '429 rate/quota(일시적 요청 제한)',
      >= 500 => '$statusCode 5xx(OpenAI 서버 오류)',
      _ => '$statusCode',
    };
    debugPrint('[GPT direct] OpenAI 요청 실패: $category');
  }

  /// API 호출 정책(비용 감사) WO §5 — OpenAI 표준 에러 포맷
  /// (`error.type`/`error.code`)에서 "요청 자체가 아니라 계정 잔액/쿼터
  /// 문제"임을 명시적으로 판별한다. 이 판별에 실패해도(응답이 JSON이
  /// 아니거나 예상과 다른 모양이어도) 예외를 던지지 않고 그냥 false로
  /// 돌아간다 — 진단이 실패했다고 원래 오류 처리 흐름을 막지 않는다.
  bool _isBillingExhausted(http.Response response) {
    if (response.statusCode != 429) return false;
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      final error = body is Map ? body['error'] : null;
      if (error is! Map) return false;
      final type = error['type'];
      final code = error['code'];
      return type == 'insufficient_quota' || code == 'credit_balance_exhausted';
    } catch (_) {
      return false;
    }
  }
}
