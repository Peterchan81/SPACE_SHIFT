// SS CAD TEST — LiveSemanticProvider: 기존 GPT 구조 분석 결과
// (VisionUnderstanding)를 재사용해 pixel_wall_v4의 GptSemanticResponse로
// 변환하는 새 live 연결. 새 AI 호출을 추가하지 않는다 — 주입된
// VisionInterpretationService를 그대로 위임 호출한다.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/vision_understanding.dart';
import 'package:ason_space/services/vision_interpretation_service.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/live_semantic_provider.dart';
import 'package:ason_space/vision_cad_poc/pixel_wall_v4/semantic_provider.dart';

class _FakeVisionService implements VisionInterpretationService {
  _FakeVisionService(this._result);
  _FakeVisionService.throwing() : _result = null;
  final VisionUnderstanding? _result;
  int callCount = 0;

  @override
  Future<VisionUnderstanding> interpret(Uint8List imageBytes) async {
    callCount++;
    if (_result == null) throw Exception('fake failure');
    return _result;
  }
}

VisionUnderstanding _fakeUnderstanding() => const VisionUnderstanding(
  floorDomain: VisionFloorDomain(id: 'floor-domain', confidence: VisionConfidence.medium, geometryHint: null),
  spaces: [
    VisionSpace(
      id: 'space-1',
      confidence: VisionConfidence.high,
      geometryHint: GeometryHint.boundingBox(minX: 0.1, minY: 0.1, maxX: 0.4, maxY: 0.4),
      label: '침실',
      semanticType: VisionSpaceSemanticType.bedroom,
      adjacentSpaceIds: ['space-2'],
    ),
    VisionSpace(
      id: 'space-2',
      confidence: VisionConfidence.low,
      geometryHint: GeometryHint.boundingBox(minX: 0.5, minY: 0.1, maxX: 0.8, maxY: 0.4),
      label: null,
      semanticType: VisionSpaceSemanticType.bathroom,
    ),
  ],
  boundaries: [],
  openings: [
    VisionOpening(
      id: 'opening-1',
      confidence: VisionConfidence.medium,
      geometryHint: GeometryHint.point(NormalizedPoint(0.4, 0.25)),
      openingType: VisionOpeningType.door,
      attachedBoundaryId: 'b1',
      connectedSpaceIds: ['space-1', 'space-2'],
    ),
    VisionOpening(
      id: 'opening-2',
      confidence: VisionConfidence.low,
      geometryHint: GeometryHint.point(NormalizedPoint(0.6, 0.1)),
      openingType: VisionOpeningType.window,
      attachedBoundaryId: 'b2',
    ),
    // openPassage는 GptSemanticOpening 계약(door|window)에 없으므로
    // 변환 결과에서 제외되어야 한다.
    VisionOpening(
      id: 'opening-3',
      confidence: VisionConfidence.low,
      geometryHint: GeometryHint.point(NormalizedPoint(0.2, 0.5)),
      openingType: VisionOpeningType.openPassage,
      attachedBoundaryId: 'b3',
    ),
  ],
);

void main() {
  group('convertVisionUnderstandingToGptSemantic', () {
    test('space label/semanticType/approxRegion/neighborSpaceIds를 그대로 옮긴다', () {
      final result = convertVisionUnderstandingToGptSemantic(_fakeUnderstanding());

      expect(result.spaces, hasLength(2));
      final s1 = result.spaces.firstWhere((s) => s.id == 'space-1');
      expect(s1.label, '침실');
      expect(s1.semanticType, 'bedroom');
      expect(s1.approxRegion.x0, 0.1);
      expect(s1.approxRegion.x1, 0.4);
      expect(s1.neighborSpaceIds, ['space-2']);
    });

    test('label이 null이면(도면에 이름이 안 보이면) semanticType으로 대체한다(거짓 이름을 지어내지 않는다)', () {
      final result = convertVisionUnderstandingToGptSemantic(_fakeUnderstanding());
      final s2 = result.spaces.firstWhere((s) => s.id == 'space-2');
      expect(s2.label, 'bathroom');
    });

    test('door/window opening은 중심점 주변 작은 사각형 힌트로 변환되고, openPassage는 제외된다', () {
      final result = convertVisionUnderstandingToGptSemantic(_fakeUnderstanding());

      expect(result.openings, hasLength(2));
      expect(result.openings.map((o) => o.type), containsAll(['door', 'window']));
      final door = result.openings.firstWhere((o) => o.type == 'door');
      expect(door.approxRegion.x0, closeTo(0.38, 1e-9));
      expect(door.approxRegion.x1, closeTo(0.42, 1e-9));
      expect(door.adjacentSpaceId, 'space-1');
    });

    test('furnitureRegions/ambiguousRegions는 항상 비어 있다(현재 GPT 응답 계약에 없는 데이터를 지어내지 않는다)', () {
      final result = convertVisionUnderstandingToGptSemantic(_fakeUnderstanding());
      expect(result.furnitureRegions, isEmpty);
      expect(result.ambiguousRegions, isEmpty);
    });
  });

  group('LiveSemanticProvider', () {
    test('성공하면 SemanticProviderResult.success를 돌려주고, VisionInterpretationService를 정확히 1번만 호출한다', () async {
      final fakeService = _FakeVisionService(_fakeUnderstanding());
      final provider = LiveSemanticProvider(fakeService);

      final result = await provider.fetch(Uint8List(0));

      expect(result.status, SemanticProviderStatus.success);
      expect(result.hasResponse, isTrue);
      expect(result.response!.spaces, hasLength(2));
      expect(fakeService.callCount, 1, reason: '같은 이미지에 semantic 전용 추가 호출을 만들지 않는다');
    });

    test('VisionInterpretationService가 실패하면 예외를 던지지 않고 unavailable을 돌려준다(§16 죽으면 안 된다)', () async {
      final provider = LiveSemanticProvider(_FakeVisionService.throwing());

      final result = await provider.fetch(Uint8List(0));

      expect(result.status, SemanticProviderStatus.unavailable);
      expect(result.hasResponse, isFalse);
      expect(result.reason, isNotNull);
    });
  });
}
