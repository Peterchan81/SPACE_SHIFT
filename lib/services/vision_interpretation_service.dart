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
