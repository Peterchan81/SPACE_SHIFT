import 'dart:typed_data';

import '../../models/vision_understanding.dart';
import '../../services/vision_interpretation_service.dart';
import 'vision_cad_proposal_v2.dart';

/// SPACE SHIFT — Image 2 GPT Detailed CAD Geometry POC.
///
/// [VisionInterpretationService]의 얇은 어댑터 — 이번 POC의 상세 proposal
/// ([buildImage2VisionProposalV2])을 기존 [VisionGuidedSpatialModelBuilder]
/// (commit 5499365에서 이미 만들고 테스트한, hint 주변 실제 픽셀 정밀화 +
/// CASE A~E 매칭 + TopologyValidator를 전부 갖춘 orchestrator)에 그대로
/// 꽂아 넣기 위한 것이다 — 새 orchestrator를 다시 만들지 않는다.
class DetailedProposalVisionService implements VisionInterpretationService {
  const DetailedProposalVisionService();

  @override
  Future<VisionUnderstanding> interpret(Uint8List imageBytes) async {
    return buildImage2VisionProposalV2();
  }
}
