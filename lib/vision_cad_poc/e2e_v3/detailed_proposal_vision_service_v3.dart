import 'dart:typed_data';

import '../../models/vision_understanding.dart';
import '../../services/vision_interpretation_service.dart';
import 'vision_cad_proposal_v3.dart';

/// [VisionInterpretationService] 어댑터 — v3 proposal을 기존
/// [VisionGuidedSpatialModelBuilder](5499365)에 그대로 꽂아 넣는다.
class DetailedProposalVisionServiceV3 implements VisionInterpretationService {
  const DetailedProposalVisionServiceV3();

  @override
  Future<VisionUnderstanding> interpret(Uint8List imageBytes) async {
    return buildImage2VisionProposalV3();
  }
}
