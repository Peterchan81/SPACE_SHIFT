/// SS008 — MASTER UI 5(평면도 업로드·AI 공간 인식) 우측 "공간 인식 결과"
/// 패널이 쓰는 집계: [SSSpatialModel]을 "인식 대상"별 레이어 개수와,
/// 신뢰도가 낮거나 확인이 필요한 요소 목록으로 바꾼다.
///
/// 지금 평면도 분석 파이프라인(FloorPlanAnalysisService의 run-length 벽
/// 검출 + [EnvelopeFirstInterpreter])은 가구/설비 종류나 계단/엘리베이터/
/// 기둥을 구분하지 못한다 — 이 파일은 그 한계를 숨기지 않는다. 검출되지
/// 않은 레이어는 그대로 0개로 보여준다(가짜 개수를 만들어 내지 않는다).
library;

import 'package:flutter/material.dart' show Color;

import '../models/ss_spatial_model.dart';

/// MASTER UI 5 "인식된 요소"/"레이어 표시" 목록의 한 줄 — SS008 "인식 대상"
/// 목록(공간·벽체·문·창·기둥·계단·엘리베이터·주요 가구·욕실/주방 설비·기타
/// 구조요소)과 1:1로 대응한다.
enum SsRecognitionLayer { space, wall, door, window, column, stair, elevator, furniture, fixture, otherStructural }

class SsRecognitionLayerInfo {
  const SsRecognitionLayerInfo({required this.layer, required this.label, required this.color});
  final SsRecognitionLayer layer;
  final String label;
  final Color color;
}

abstract final class SsRecognitionLayers {
  static const Map<SsRecognitionLayer, SsRecognitionLayerInfo> all = {
    SsRecognitionLayer.space: SsRecognitionLayerInfo(layer: SsRecognitionLayer.space, label: '공간(방/거실/주방 등)', color: Color(0xFFE3C9A0)),
    SsRecognitionLayer.wall: SsRecognitionLayerInfo(layer: SsRecognitionLayer.wall, label: '벽체', color: Color(0xFF4B5565)),
    SsRecognitionLayer.door: SsRecognitionLayerInfo(layer: SsRecognitionLayer.door, label: '문', color: Color(0xFFFB923C)),
    SsRecognitionLayer.window: SsRecognitionLayerInfo(layer: SsRecognitionLayer.window, label: '창문', color: Color(0xFF22D3EE)),
    SsRecognitionLayer.column: SsRecognitionLayerInfo(layer: SsRecognitionLayer.column, label: '기둥', color: Color(0xFFEC4899)),
    SsRecognitionLayer.stair: SsRecognitionLayerInfo(layer: SsRecognitionLayer.stair, label: '계단', color: Color(0xFFA855F7)),
    SsRecognitionLayer.elevator: SsRecognitionLayerInfo(layer: SsRecognitionLayer.elevator, label: '엘리베이터', color: Color(0xFF3B82F6)),
    SsRecognitionLayer.furniture: SsRecognitionLayerInfo(layer: SsRecognitionLayer.furniture, label: '가구(주요 가구)', color: Color(0xFF34D399)),
    SsRecognitionLayer.fixture: SsRecognitionLayerInfo(layer: SsRecognitionLayer.fixture, label: '욕실/주방 설비', color: Color(0xFFBFD7FF)),
    SsRecognitionLayer.otherStructural: SsRecognitionLayerInfo(layer: SsRecognitionLayer.otherStructural, label: '기타 구조요소', color: Color(0xFF9CA3AF)),
  };

  /// SS008 "인식 대상" 중 항상 보여주는 레이어 — 0개여도 "이 평면도에는 없다"는
  /// 정직한 정보다(mock의 "계단 0개"와 같은 원칙). 엘리베이터/기타 구조요소는
  /// "해당 시"만 보여준다(지시문 원문).
  static const Set<SsRecognitionLayer> alwaysShown = {
    SsRecognitionLayer.space,
    SsRecognitionLayer.wall,
    SsRecognitionLayer.door,
    SsRecognitionLayer.window,
    SsRecognitionLayer.column,
    SsRecognitionLayer.stair,
    SsRecognitionLayer.furniture,
    SsRecognitionLayer.fixture,
  };
}

/// 신뢰도가 낮거나(임계값 미만) 명시적으로 reviewNeeded인 요소 한 개.
class SsRecognitionReviewItem {
  const SsRecognitionReviewItem({required this.id, required this.layer, required this.label, required this.reason});
  final String id;
  final SsRecognitionLayer layer;
  final String label;
  final String reason;
}

class SsRecognitionSummary {
  const SsRecognitionSummary({required this.counts, required this.reviewItems});

  final Map<SsRecognitionLayer, int> counts;
  final List<SsRecognitionReviewItem> reviewItems;

  int get totalCount => counts.values.fold(0, (a, b) => a + b);

  /// 이 미만이면(그리고 명시적 reviewNeeded가 아니어도) "확인이 필요한 요소"로 본다.
  static const double lowConfidenceThreshold = 0.6;

  static bool _isFixtureKind(SSObjectKind kind) =>
      kind == SSObjectKind.sink || kind == SSObjectKind.toilet || kind == SSObjectKind.bathtub || kind == SSObjectKind.equipment;

  static SsRecognitionLayer _structuralLayer(SSStructuralKind kind) => switch (kind) {
    SSStructuralKind.column => SsRecognitionLayer.column,
    SSStructuralKind.stair => SsRecognitionLayer.stair,
    SSStructuralKind.elevator => SsRecognitionLayer.elevator,
    SSStructuralKind.shaft || SSStructuralKind.voidSpace => SsRecognitionLayer.otherStructural,
  };

  static String _reasonOf(bool reviewNeeded, List<String> reasons, String fallback) =>
      reviewNeeded && reasons.isNotEmpty ? reasons.join(', ') : fallback;

  factory SsRecognitionSummary.fromModel(SSSpatialModel model) {
    final counts = {for (final l in SsRecognitionLayer.values) l: 0};
    final review = <SsRecognitionReviewItem>[];

    for (final space in model.spaces) {
      counts[SsRecognitionLayer.space] = counts[SsRecognitionLayer.space]! + 1;
      final lowConfidence = space.spaceConfidence == SSSpaceConfidence.low || space.spaceConfidence == SSSpaceConfidence.unknown;
      if (space.reviewNeeded || lowConfidence) {
        review.add(
          SsRecognitionReviewItem(
            id: space.id,
            layer: SsRecognitionLayer.space,
            label: '공간 ${space.label ?? space.id}',
            reason: _reasonOf(space.reviewNeeded, space.reviewReasons, '공간으로 인식한 확신이 낮습니다'),
          ),
        );
      }
    }

    for (final wall in model.walls) {
      counts[SsRecognitionLayer.wall] = counts[SsRecognitionLayer.wall]! + 1;
      if (wall.reviewNeeded || wall.confidence < lowConfidenceThreshold) {
        review.add(
          SsRecognitionReviewItem(
            id: wall.id,
            layer: SsRecognitionLayer.wall,
            label: '벽체 ${wall.id}',
            reason: _reasonOf(wall.reviewNeeded, wall.reviewReasons, '신뢰도 ${(wall.confidence * 100).round()}%'),
          ),
        );
      }
    }

    for (final opening in model.openings) {
      final layer = opening.kind == SSOpeningKind.window ? SsRecognitionLayer.window : SsRecognitionLayer.door;
      counts[layer] = counts[layer]! + 1;
      final uncertainKind = opening.kind == SSOpeningKind.unknown;
      if (opening.reviewNeeded || opening.confidence < lowConfidenceThreshold || uncertainKind) {
        review.add(
          SsRecognitionReviewItem(
            id: opening.id,
            layer: layer,
            label: '${layer == SsRecognitionLayer.window ? '창문' : '문'} ${opening.id}',
            reason: _reasonOf(opening.reviewNeeded, opening.reviewReasons, '신뢰도 ${(opening.confidence * 100).round()}%'),
          ),
        );
      }
    }

    for (final obj in model.objects) {
      final isFixture = _isFixtureKind(obj.kind);
      final layer = isFixture ? SsRecognitionLayer.fixture : SsRecognitionLayer.furniture;
      counts[layer] = counts[layer]! + 1;
      if (obj.reviewNeeded || obj.kind == SSObjectKind.unknown) {
        review.add(
          SsRecognitionReviewItem(
            id: obj.id,
            layer: layer,
            label: '${isFixture ? '욕실/주방 설비' : '가구'} ${obj.id}',
            reason: _reasonOf(obj.reviewNeeded, obj.reviewReasons, '종류를 확실하게 인식하지 못했습니다'),
          ),
        );
      }
    }

    for (final s in model.structuralElements) {
      final layer = _structuralLayer(s.kind);
      counts[layer] = counts[layer]! + 1;
      if (s.reviewNeeded || s.confidence < lowConfidenceThreshold) {
        review.add(
          SsRecognitionReviewItem(
            id: s.id,
            layer: layer,
            label: '${SsRecognitionLayers.all[layer]!.label} ${s.id}',
            reason: _reasonOf(s.reviewNeeded, s.reviewReasons, '신뢰도 ${(s.confidence * 100).round()}%'),
          ),
        );
      }
    }

    return SsRecognitionSummary(counts: counts, reviewItems: review);
  }
}
