import 'dart:typed_data';

import '../models/vision_understanding.dart';

/// Vision Guided CAD POC — Vision provider 추상 인터페이스(설계 3번).
///
/// 실제 구현은 이미지 한 장을 받아 [VisionUnderstanding]을 돌려준다.
/// 이 POC는 [MockVisionInterpretationService]만 구현하지만, 나중에
/// Claude Vision/OpenAI Vision/미래의 SS 자체 Vision 모델로 교체할 때
/// 이 인터페이스 밖(추출기/매처/검증기/orchestrator)은 전혀 바뀌지 않는
/// 것이 목표다 — provider는 언제나 "무엇이 있는가/대략 어디 있는가"만
/// 답하고, 정밀 좌표 확정은 이 인터페이스 바깥의 책임이다.
abstract class VisionInterpretationService {
  Future<VisionUnderstanding> interpret(Uint8List imageBytes);
}

/// SS CAD TEST — API 호출 정책(비용 감사) WO §5. OpenAI가 "요청 자체는
/// 정상이지만 계정에 남은 크레딧/쿼터가 없다"고 명시적으로 응답했을
/// 때만(`insufficient_quota`/`credit_balance_exhausted` 등) 던진다.
/// 이 예외를 받은 호출부(예: [runAdaptiveVisionConsolidation])는 같은
/// 요청을 자동으로 다시 보내지 않는다 — 결제 문제가 해결되지 않는 한
/// 몇 번을 다시 불러도 100% 같은 이유로 실패하므로, 추가 유료 요청을
/// 낭비하지 않고 즉시 멈춘 뒤 사용자에게 "API 크레딧/결제 확인 필요"를
/// 명확히 보여준다. 짧은 시간 뒤 저절로 회복되는 일시적 rate limit과는
/// 다른 범주이므로 절대 같은 예외로 섞지 않는다.
class GptBillingExhaustedException implements Exception {
  const GptBillingExhaustedException([
    this.message = 'OpenAI API 크레딧이 소진되었습니다. 결제(billing) 확인이 필요합니다.',
  ]);

  final String message;

  @override
  String toString() => message;
}
