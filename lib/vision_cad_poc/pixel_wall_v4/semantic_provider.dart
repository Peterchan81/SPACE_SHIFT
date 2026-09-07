// SPACE SHIFT — WO087 EXISTING SEMANTIC PRODUCTION WIRING.
//
// §5 조사 결과: GPT semantic 응답 스키마([GptSemanticResponse],
// gpt_semantic_schema.dart)와 그 응답을 실제 geometry evidence와
// 결합하는 fusion 로직(semantic_zone_mapper.dart의 mapSemanticZones,
// wall_opening.dart의 doorArc/windowDetail 대조)은 이미 존재하고 실제
// Image 2로 검증됐다. 빠져 있던 것은 딱 하나 — "이 GptSemanticResponse가
// 어디서 오는가"를 나타내는 추상화 자체가 없어서, pixel_wall_screen.dart
// (POC)가 파일 경로를 직접 하드코딩해 읽었고, production 화면
// (floor_plan_workspace_screen.dart)은 애초에 semantic을 전혀 넘기지
// 않았다(WO086에서 확인). 이 파일은 그 하나의 빠진 연결만 만든다 —
// fusion 로직 자체는 중복 구현하지 않는다.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'gpt_semantic_schema.dart';

/// §16 — semantic evidence가 실제로 얼마나 확보됐는지. FALLBACK_USED와
/// 혼동하지 않는다: FALLBACK_USED는 "geometry 엔진 자체가 실패해 다른
/// 엔진으로 대체했다"는 뜻이고, 이 상태는 "geometry 엔진은 정상 동작
/// 하되 semantic evidence가 없거나 일부만 있다"는 뜻이다.
enum SemanticProviderStatus {
  /// 유효한 [GptSemanticResponse]를 확보함.
  success,

  /// 시도는 했으나 일부만 확보(예: 응답 파싱은 됐지만 필드 일부 누락) —
  /// 이번 버전에서는 success/unavailable 두 상태만 실제로 반환되고,
  /// partial은 향후 실제 live provider가 부분 실패를 구분할 수 있게
  /// 미리 자리를 마련해 둔 것이다.
  partial,

  /// semantic evidence를 전혀 확보하지 못함(fixture 없음/live 미구현/
  /// API 호출 실패 등) — pixel_wall_pipeline은 이 경우 항상
  /// semantic=null로 안전하게 계속 동작해야 한다(§16 "죽으면 안 된다").
  unavailable,
}

class SemanticProviderResult {
  const SemanticProviderResult({required this.status, this.response, this.reason});

  const SemanticProviderResult.success(GptSemanticResponse response)
    : this(status: SemanticProviderStatus.success, response: response);

  const SemanticProviderResult.unavailable(String reason) : this(status: SemanticProviderStatus.unavailable, reason: reason);

  final SemanticProviderStatus status;
  final GptSemanticResponse? response;

  /// unavailable/partial일 때 왜인지(디버그/전문가용) — 원본 예외
  /// 메시지를 그대로 담지 않는다(이 프로젝트의 "원본 예외 비노출" 관례).
  final String? reason;

  bool get hasResponse => response != null;
}

/// §15 — 어디서 semantic evidence를 구하는지에 대한 추상화. 실제 구현체를
/// 바꿔 끼워도 pixel_wall_pipeline 호출부는 전혀 바뀌지 않는다(테스트는
/// [CapturedFixtureSemanticProvider], production은 지금은
/// [UnavailableSemanticProvider] — 실제 live 호출은 이번 WO 범위 밖).
abstract class SemanticProvider {
  Future<SemanticProviderResult> fetch(Uint8List imageBytes);
}

/// §6/§15 — 미리 캡처해 둔 GPT 응답 JSON 파일을 읽는다(pixel_wall_screen.dart
/// POC가 원래 인라인으로 하던 것과 정확히 같은 동작을 재사용 가능한
/// 클래스로 formalize했을 뿐, 새 파싱 로직을 만들지 않았다). 실제 API를
/// 다시 호출하지 않고 결정론적 회귀 테스트에 쓴다.
class CapturedFixtureSemanticProvider implements SemanticProvider {
  const CapturedFixtureSemanticProvider(this.path);
  final String path;

  @override
  Future<SemanticProviderResult> fetch(Uint8List imageBytes) async {
    final file = File(path);
    if (!file.existsSync()) {
      return SemanticProviderResult.unavailable('캡처된 semantic fixture 없음: $path');
    }
    try {
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return SemanticProviderResult.success(GptSemanticResponse.fromJson(json));
    } catch (_) {
      return const SemanticProviderResult.unavailable('캡처된 semantic fixture 파싱 실패');
    }
  }
}

/// §3/§13 — 실제 live GPT 호출은 이번 WO 범위 밖이다(보안 사고로 노출된
/// 키를 재사용하지 않는다는 원칙 + "새 대규모 기능을 한 WO에 몰아넣지
/// 않는다"는 원칙 둘 다 근거). production 경로가 semantic 없이도 절대
/// 죽지 않아야 한다는 요구(§16)를 만족하는 안전한 기본값 — 항상
/// unavailable을 정직하게 반환한다. 다음 WO에서 실제 [LiveSemanticProvider]
/// 구현으로 교체하면, 이 provider를 주입받는 모든 호출부는 코드 변경 없이
/// 그대로 동작한다.
class UnavailableSemanticProvider implements SemanticProvider {
  const UnavailableSemanticProvider();

  @override
  Future<SemanticProviderResult> fetch(Uint8List imageBytes) async {
    return const SemanticProviderResult.unavailable('live semantic provider가 아직 연결되지 않음(WO087 범위 밖)');
  }
}
