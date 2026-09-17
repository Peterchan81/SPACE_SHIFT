// SS CAD TEST — pixel_wall_v4 §15 SemanticProvider의 실제 live 구현.
//
// [UnavailableSemanticProvider]의 문서 주석이 예고한 "다음 WO에서 실제
// LiveSemanticProvider 구현으로 교체" — 바로 그것이다. 새 GPT 호출을
// 만들지 않고, 이미 production에서 검증된 [VisionInterpretationService]
// (`gpt_floorplan_vision_service.dart`, "GPT 구조 분석" 버튼이 쓰는 것과
// 정확히 같은 서비스 — Supabase 경유든 Windows 개발용 direct 경로든)를
// 그대로 재사용한다. 같은 이미지에 대해 별도의 semantic 전용 API 호출을
// 새로 추가하지 않는다.
//
// [VisionUnderstanding](VisionGuidedSpatialModelBuilder 계약)과
// [GptSemanticResponse](pixel_wall_v4 계약)는 서로 다른 스키마이므로,
// [convertVisionUnderstandingToGptSemantic]이 결정론적으로 변환한다 —
// 좌표/판단 로직은 추가하지 않고 순수 스키마 매핑만 한다.
import 'package:flutter/foundation.dart';

import '../../models/vision_understanding.dart';
import '../../services/vision_interpretation_service.dart';
import 'gpt_semantic_schema.dart';
import 'semantic_provider.dart';

class LiveSemanticProvider implements SemanticProvider {
  const LiveSemanticProvider(this.visionService);

  final VisionInterpretationService visionService;

  @override
  Future<SemanticProviderResult> fetch(Uint8List imageBytes) async {
    try {
      final understanding = await visionService.interpret(imageBytes);
      return SemanticProviderResult.success(convertVisionUnderstandingToGptSemantic(understanding));
    } catch (error) {
      // CAD/DXF FIRST GOAL FINAL LIVE E2E WO — 이 catch가 error.runtimeType만
      // 남기던 이전 버전은 실제 라이브 테스트에서 3회 연속 semantic 호출이
      // 전부 unavailable로 조용히 폴백됐는데도 진짜 이유(스키마 불일치인지,
      // OpenAI 응답 자체 문제인지)를 전혀 알 수 없게 만들었다. 사용자에게
      // 보여주는 값(SemanticProviderResult.unavailable의 reason)은 여전히
      // 안전한 요약 문구로 유지하되(§16 "죽으면 안 된다" 원칙, 원본 예외를
      // 화면에 노출하지 않는다는 기존 관례), 개발 로그에는 실제 예외
      // 메시지를 남겨 다음 실패를 재현 없이 진단할 수 있게 한다. 이
      // 메시지에는 API key가 담기지 않는다 — VisionInterpretationService
      // 구현체들은 key를 예외 메시지에 넣지 않는다(단위 테스트로 확인됨).
      debugPrint('[LiveSemanticProvider] GPT 구조 분석(semantic) 호출 실패: $error');
      // §16 "죽으면 안 된다" — 원본 예외를 그대로 노출하지 않는다(이
      // 프로젝트의 기존 관례). 호출부(runPixelWallPipelineWithSemanticProvider)
      // 는 이 unavailable을 받아 geometry-only로 안전하게 계속 진행한다.
      return SemanticProviderResult.unavailable('GPT 구조 분석 호출 실패(${error.runtimeType}) — geometry-only로 계속 진행');
    }
  }
}

/// [VisionUnderstanding](구조화 좌표 계약)을 [GptSemanticResponse](pixel_wall_v4
/// 의미 계약)로 옮긴다 — 새 판단을 추가하지 않고 필드만 옮긴다.
///
/// [VisionOpening.geometryHint]는 점(문/창 중심) 하나뿐이라, [GptSemanticOpening.approxRegion]
/// (사각형)이 요구하는 "대략 이 근처를 보라"는 힌트로 쓰기 위해 중심점
/// 주변에 작은 정사각형을 합성한다 — 이 값은 최종 CAD 좌표로 쓰이지
/// 않고(§ pixel_wall_v4 원칙 3: "AI 좌표를 최종 CAD 좌표로 그대로 사용하지
/// 않는다"), `wall_opening.dart`의 doorArc/windowDetail 대조에서 실제
/// pixel gap과 겹치는지 확인하는 근사 ROI로만 쓰인다.
const double _kOpeningHintHalfSize = 0.02;

GptSemanticResponse convertVisionUnderstandingToGptSemantic(VisionUnderstanding understanding) {
  return GptSemanticResponse(
    spaces: [
      for (final space in understanding.spaces)
        if (space.geometryHint?.boundingBox case final box?)
          GptSemanticSpace(
            id: space.id,
            // GptSemanticSpace.label은 빈 문자열을 허용하지 않는다 — 도면에
            // 실제로 쓰인 이름이 없으면(null) semanticType으로 대체한다
            // (거짓 이름을 지어내지 않는다는 원칙은 CadRoom.name에서 계속
            // 지켜진다 — 이 label은 pixel_wall_v4 내부 매칭용일 뿐이다).
            label: space.label ?? space.semanticType.name,
            semanticType: space.semanticType.name,
            approxRegion: GptApproxRegion(x0: box.minX, y0: box.minY, x1: box.maxX, y1: box.maxY),
            neighborSpaceIds: space.adjacentSpaceIds,
          ),
    ],
    openings: [
      for (final opening in understanding.openings)
        if (opening.geometryHint?.point case final center?)
          if (opening.openingType != VisionOpeningType.openPassage)
            GptSemanticOpening(
              type: opening.openingType.name,
              approxRegion: GptApproxRegion(
                x0: center.x - _kOpeningHintHalfSize,
                y0: center.y - _kOpeningHintHalfSize,
                x1: center.x + _kOpeningHintHalfSize,
                y1: center.y + _kOpeningHintHalfSize,
              ),
              adjacentSpaceId: opening.connectedSpaceIds.isEmpty ? null : opening.connectedSpaceIds.first,
            ),
    ],
    // 현재 실제 gpt-floorplan-understand Edge Function 응답 계약
    // (index.ts RESPONSE_JSON_SCHEMA)은 objects/furniture를 전혀 요청하지
    // 않아 VisionUnderstanding.objects는 항상 비어 있다 — 있지도 않은
    // 데이터를 지어내지 않고 정직하게 비워 둔다.
    furnitureRegions: const [],
    ambiguousRegions: const [],
  );
}
