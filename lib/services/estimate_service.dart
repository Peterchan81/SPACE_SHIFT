import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_environment.dart';
import '../models/estimate_request.dart';

/// 무료 예상견적 요청을 접수하는 서비스.
///
/// 화면(UI)은 이 클래스만 알면 되고, 실제로 어떻게 접수되는지는 몰라도
/// 된다. Edge Function URL이 설정되지 않은 로컬 개발/테스트 환경에서는
/// 안전하게 즉시 성공 처리하는 Mock으로 동작한다.
class EstimateService {
  const EstimateService();

  /// 요청을 접수한다. 접수에 실패하면 예외를 던진다.
  Future<void> submit(EstimateRequest request) async {
    debugPrint('예상견적 요청(Mock) - 공간: ${request.spaceType}, 면적: ${request.approximateArea}');
  }
}

/// Supabase Edge Function(submit-estimate)만 호출하는 실제 접수 서비스.
class EdgeFunctionEstimateService extends EstimateService {
  EdgeFunctionEstimateService({required this.endpoint, http.Client? client})
    : _client = client ?? http.Client();

  final Uri endpoint;
  final http.Client _client;

  @override
  Future<void> submit(EstimateRequest request) async {
    final response = await _client
        .post(
          endpoint,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'spaceType': request.spaceType,
            'approximateArea': request.approximateArea,
            'constructionScope': request.constructionScope,
            'desiredColorTone': request.desiredColorTone,
            'customColorTone': request.customColorTone,
            'notes': request.notes,
          }),
        )
        .timeout(const Duration(seconds: 30));

    Map<String, dynamic> payload;
    try {
      payload =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('서버 응답을 확인할 수 없습니다.');
    }

    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] != true) {
      throw Exception(payload['message'] ?? '예상견적 요청 접수에 실패했습니다.');
    }
  }
}

/// [AppEnvironment] 설정에 맞는 [EstimateService]를 생성한다.
///
/// [edgeFunctionUrlOverride]를 지정하면 [AppEnvironment.estimateEdgeFunctionUrl]
/// 대신 이 값을 사용한다. 테스트에서 여러 상황을 손쉽게 검증하기 위한
/// 용도다.
EstimateService createEstimateService({String? edgeFunctionUrlOverride}) {
  final edgeFunctionUrl =
      edgeFunctionUrlOverride ?? AppEnvironment.estimateEdgeFunctionUrl;

  if (edgeFunctionUrl.trim().isNotEmpty) {
    return EdgeFunctionEstimateService(endpoint: Uri.parse(edgeFunctionUrl));
  }

  debugPrint('Estimate Edge Function URL이 없어 Mock으로 동작합니다.');
  return const EstimateService();
}
