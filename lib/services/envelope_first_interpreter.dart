import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/drawing_understanding.dart';
import '../models/floor_plan_geometry.dart';

/// PC2 Envelope-first 실험 — "선 → 벽 추정 → 빈 영역 → 방" 순서(space-first,
/// [ArchitecturalDrawingInterpreter])를 뒤집는다. 먼저 건물 외곽
/// (Envelope)을 이해하고, 그 안(FloorDomain)을 실제 벽 evidence로 나누어
/// SPACE를 만든다.
///
/// 핵심 사고방식(WO 지시): "이 도면에서 실제 건물의 바닥 영역은 어디까지
/// 인가?"를 먼저 답하고, 그 다음 "어떤 내부 경계가 이 바닥을 실제 독립
/// 건축공간으로 나누는가?"를 답한다. 기존 저해상도 CV 검출기(run-length
/// 벽 검출 + flood-fill 방 후보, [FloorPlanAnalysisResult])는 폐기하지
/// 않고 이 해석의 evidence로만 쓴다(WO 지시 8번) — 두 evidence(벽 band +
/// 방 flood-fill 후보)를 합쳐 "실제 바닥으로 보이는 영역 전체"를
/// 재구성한 뒤, 그 안에서만 벽 evidence로 다시 나눈다.
///
/// 이 파일은 자체 해상도의 작업용 격자(정규화 좌표 기준, 원본 이미지
/// 해상도와 무관)에서 순수 기하 연산만 한다 — 저수준 CV 단계(isolate에서
/// 실행되는 [floor_plan_analysis_engine.dart])는 전혀 건드리지 않는다.
class EnvelopeFirstInterpreter implements DrawingInterpreter {
  const EnvelopeFirstInterpreter();

  /// Envelope/FloorDomain 재구성용 작업 격자의 가로 칸 수 — 원본 분석
  /// 해상도(최대 900px)와 무관하게 고정한다. 이 정도면 실제 건물
  /// 외곽의 돌출/후퇴/비정형 구조를 충분히 보존하면서도(1칸 ≈ 전체
  /// 폭의 0.45%), 격자 연산 비용은 작게 유지된다.
  static const int gridCols = 220;

  /// 전체 격자 대비 이 비율보다 작은 연결 성분은 노이즈로 보고
  /// 무시한다(방/외곽 둘 다 공통 적용) — 실제 작은 화장실도 통과할 만큼
  /// 낮게 잡는다.
  static const double kMinComponentAreaRatio = 0.003;

  @override
  ArchitecturalInterpretation interpret(FloorPlanAnalysisResult input) {
    final w = math.max(1, input.sourceWidthPx);
    final h = math.max(1, input.sourceHeightPx);
    final gw = gridCols;
    final gh = math.max(1, (gw * h / w).round());

    // ---- 1단계: Envelope — 벽 evidence + 방 evidence를 합쳐 "실제 바닥
    // 으로 보이는 영역 전체"를 재구성한다. 어느 한쪽만으로는 부족하다
    // — 벽만 쓰면 방 내부(당연히 벽이 아닌 빈 공간)가 비어 있고, 방
    // 후보만 쓰면 (기존 space-first가 이미 보여줬듯) 가구/노이즈로
    // 조각난 채 남는다. 합집합이 "이 픽셀이 건물 바닥의 일부로 보이는가"
    // 라는 첫 질문에 가장 가까운 근사다.
    final union = _Grid(gw, gh);
    for (final wall in input.walls) {
      _fillPolygonNormalized(union, _wallFootprintPolygon(wall));
    }
    for (final room in input.rooms) {
      _fillPolygonNormalized(union, room.polygon);
    }
    // 안장점 제거는 여기(연결 성분을 나누기 전)에서 하지 않는다 — 대각선
    // 한 점에서만 맞닿은 두 "진짜로 서로 다른" 영역까지 하나로 용접해
    // 버릴 수 있다(예: 벽 evidence가 전혀 없는 두 방이 우연히 한 꼭짓점
    // 에서만 닿는 경우). 안장점 해소는 이미 확정된 성분 하나의 윤곽을
    // 그릴 때만([_outerLoop] 내부에서 그 성분 로컬 격자에만) 적용한다.
    final components = _connectedComponents(union, eightConnected: true);
    final minArea = (gw * gh * kMinComponentAreaRatio).round();
    components.removeWhere((c) => c.length < minArea);

    final warnings = <String>[...input.warnings];
    if (components.isEmpty) {
      warnings.add('건물 외곽을 인식하지 못했습니다 — 평면도 구조를 다시 확인해주세요.');
      return _emptyInterpretation(warnings, input.openings);
    }

    // 가장 큰 연결 성분을 건물 Envelope(=이번 단계의 FloorDomain — 아직
    // 발코니/샤프트 등 제외 영역 분류기가 없어 전체를 그대로 쓴다, WO
    // 지시 1번 "단, 이후 다음은 제외 영역으로 분류할 수 있게 한다")로
    // 삼는다.
    components.sort((a, b) => b.length.compareTo(a.length));
    final envelopePixels = components.first.toSet();

    // ---- 2단계: FloorDomain 내부를 실제 벽 evidence로만 다시 나눈다.
    // 가구/해칭처럼 벽으로 확정되지 않은 어두운 영역이 SPACE를 잘못
    // 쪼개지 않도록(WO 지시 2번 핵심 질문: "이 경계가 FloorDomain을
    // 실제 건축공간 두 개 이상으로 의미 있게 나누는가?"), 벽 evidence
    // 만으로 채운 별도 격자를 쓴다.
    final wallOnly = _Grid(gw, gh);
    for (final wall in input.walls) {
      _fillPolygonNormalized(wallOnly, _wallFootprintPolygon(wall));
    }

    final interior = _Grid(gw, gh);
    for (final idx in envelopePixels) {
      if (wallOnly.cells[idx] == 0) interior.cells[idx] = 1;
    }

    final spaceComponents = _connectedComponents(
      interior,
      eightConnected: false,
    )..removeWhere((c) => c.length < minArea);

    // ---- 3단계: 각 연결 성분(SPACE 후보)의 실제 윤곽(비정형/오목 포함)을
    // 추적한다.
    final rawSpaces = <_RawSpace>[];
    for (var i = 0; i < spaceComponents.length; i++) {
      final pixels = spaceComponents[i].toSet();
      final loop = _outerLoop(pixels, gw, gh);
      if (loop == null || loop.length < 3) continue;
      final polygon = [for (final p in loop) Point2(p.x / gw, p.y / gh)];
      rawSpaces.add(
        _RawSpace(
          id: 'space-${i + 1}',
          polygon: polygon,
          areaNormalized: pixels.length / (gw * gh),
        ),
      );
    }

    if (rawSpaces.isEmpty) {
      warnings.add('건물 외곽은 인식했지만 내부 공간을 나누지 못했습니다.');
      return _emptyInterpretation(warnings, input.openings);
    }

    // ---- 4단계: 가구/설비로 보이는 "SPACE 후보" 재분류 — 핵심 사례:
    // 실제 벽과 같은 두께의 얇은 외곽선으로 그려진 가구(옷장/침대 등)는
    // wall-only 격자에서도 진짜 벽처럼 flood-fill을 막아, 그 내부가
    // 자기만의 작은 rawSpace로 분리된다. [_outerLoop]가 구멍(hole)을
    // 무시하고 가장 바깥 loop만 쓰기 때문에, 그 가구를 둘러싼 "진짜
    // 큰 공간"의 폴리곤은 가구 부분의 구멍 없이 통째로(가구 영역까지
    // 포함해) 추적된다 — 즉 큰 공간의 폴리곤이 작은 가구-space의 폴리곤을
    // 기하학적으로 포함한다. 이 포함 관계 + 상대적 크기(WO 지시 2/5번)로
    // "이 경계가 실제 건축공간을 나누는가"를 재확인해, 아니라면 SPACE
    // 목록에서 빼고 [InterpretedObject]로 옮긴다 — 근처에 문/창이 있으면
    // (실제로 출입 가능한 작은 방일 수 있으므로) 예외로 유지한다.
    final objects = <InterpretedObject>[];
    final finalSpaces = <_RawSpace>[];
    for (final space in rawSpaces) {
      _RawSpace? container;
      for (final other in rawSpaces) {
        if (other.id == space.id) continue;
        if (other.areaNormalized <= space.areaNormalized) continue;
        if (!_contains(other.polygon, _centroid(space.polygon))) continue;
        if (container == null ||
            other.areaNormalized < container.areaNormalized) {
          container = other;
        }
      }
      final openingNearby = input.openings.any(
        (opening) => _nearPolygon(opening.center, space.polygon),
      );
      final objectLike =
          container != null &&
          space.areaNormalized < container.areaNormalized * 0.25 &&
          !openingNearby;
      if (objectLike) {
        objects.add(
          InterpretedObject(
            id: 'object-${space.id}',
            sourcePrimitiveId: 'envelope-floor-domain',
            semanticType: DrawingSemanticType.furniture,
            polygon: space.polygon,
            confidence: 0.8,
            reasons: const [
              'a larger reconstructed space geometrically contains this '
                  'region and it is much smaller — treated as an object '
                  'occupying that space, not an independent space',
            ],
            containingSpaceId: container.id,
          ),
        );
      } else {
        finalSpaces.add(space);
      }
    }

    if (finalSpaces.isEmpty) {
      warnings.add('건물 외곽은 인식했지만 내부 공간을 나누지 못했습니다.');
      return _emptyInterpretation(warnings, input.openings);
    }

    // ---- 4.5단계: 원본 방 flood-fill evidence 중, 위 재분류로도
    // 걸러지지 않았지만(두꺼운 채움 블록이라 애초에 벽으로도 인정되지
    // 않아 별도 rawSpace로 분리조차 되지 않은 경우) 이제 만들어진 SPACE
    // 하나에 완전히 담기면서 그 SPACE보다 훨씬 작은 것도 같은 원칙으로
    // 걸러낸다(WO 지시 2번 반대 방향 질문).
    for (final room in input.rooms) {
      final centroid = _centroid(room.polygon);
      _RawSpace? container;
      for (final space in finalSpaces) {
        if (_contains(space.polygon, centroid)) {
          container = space;
          break;
        }
      }
      if (container == null) continue;
      // container.areaNormalized*0.25 임계값 자체가 "room이 사실 이
      // container와 거의 같은 영역"인 경우(비율이 1에 가까움)를 이미
      // 걸러낸다 — 별도의 동일성 검사가 필요 없다.
      if (room.areaNormalized < container.areaNormalized * 0.25) {
        objects.add(
          InterpretedObject(
            id: 'object-${room.id}',
            sourcePrimitiveId: 'primitive-room-${room.id}',
            semanticType: DrawingSemanticType.furniture,
            polygon: room.polygon,
            confidence: 0.75,
            reasons: const [
              'contained by a reconstructed floor-domain space and much '
                  'smaller than it — treated as an object, not a boundary',
            ],
            containingSpaceId: container.id,
          ),
        );
      }
    }

    // ---- 5단계: 경계(boundary) 해석 — SPACE 폴리곤 변마다 벽/문/창/
    // 이웃 SPACE/미상 중 무엇인지 판정한다(WO 지시 4번).
    final validWallIds = <String>{};
    final spaceBoundaries = <String, List<InterpretedBoundarySegment>>{};
    for (final space in finalSpaces) {
      final segments = _boundarySegmentsFor(
        space,
        finalSpaces,
        input.walls,
        input.openings,
      );
      spaceBoundaries[space.id] = segments;
      for (final segment in segments) {
        if (segment.wallId != null) validWallIds.add(segment.wallId!);
      }
    }

    final validWalls = input.walls
        .where((w) => validWallIds.contains(w.id))
        .toList();
    final links = _links(validWalls);
    final junctions = _junctions(validWalls);
    final wallGraph = ArchitecturalWallGraph(
      walls: [
        for (final wall in validWalls)
          ArchitecturalWall(
            id: wall.id,
            sourcePrimitiveId: 'primitive-wall-${wall.id}',
            segment: wall,
            confidence: wall.confidence,
            reasons: const ['matched to a reconstructed space boundary'],
            junctionIds: [
              for (final junction in junctions)
                if (junction.wallIds.contains(wall.id)) junction.id,
            ],
          ),
      ],
      junctions: junctions,
      connectedComponents: _components(validWalls, links),
    );

    // ---- 6단계: opening(문/창) — 유효한 벽에 붙은 것만 SPACE 연결
    // 관계를 확정한다(WO 지시 4번 "문은 가능한 경우 두 SPACE의 연결
    // 관계를 가진다").
    final openings = <InterpretedOpening>[];
    for (final opening in input.openings) {
      final attached =
          opening.wallId != null && validWallIds.contains(opening.wallId);
      final kind = switch (opening.type) {
        OpeningType.door => DrawingSemanticType.doorSymbol,
        OpeningType.window => DrawingSemanticType.windowSymbol,
        OpeningType.unknown => DrawingSemanticType.unknown,
      };
      final connects = <String>[];
      if (attached) {
        for (final entry in spaceBoundaries.entries) {
          if (entry.value.any((segment) => segment.openingId == opening.id)) {
            connects.add(entry.key);
          }
        }
      }
      openings.add(
        InterpretedOpening(
          id: opening.id,
          sourcePrimitiveId: 'primitive-opening-${opening.id}',
          // 벽에 붙었는지는 confidence/parentWallId에만 반영한다 — 원본
          // evidence의 문/창 구분(kind) 자체는 별개의 정보라 벽 매칭
          // 실패로 지워버리지 않는다(estimateScaleFromDoors 같은 다른
          // 계층이 "문인가"를 그대로 물어볼 수 있어야 한다).
          kind: kind,
          center: opening.center,
          widthNormalized: opening.widthNormalized,
          parentWallId: attached ? opening.wallId : null,
          confidence: attached ? opening.confidence : 0.2,
          reasons: [
            attached
                ? 'opening is attached to a validated wall'
                : 'opening is not attached to a validated wall',
          ],
          connectsSpaceIds: connects,
        ),
      );
    }

    // ---- 7단계: 인접 SPACE 관계 + 최종 InterpretedSpace 조립.
    final spaces = <InterpretedSpace>[];
    for (final space in finalSpaces) {
      final segments = spaceBoundaries[space.id]!;
      final adjacent = <String>{
        for (final segment in segments)
          if (segment.oppositeSpaceId != null) segment.oppositeSpaceId!,
      };
      final boundaryWallIds = [
        for (final segment in segments)
          if (segment.wallId != null) segment.wallId!,
      ];
      final boundaryOpeningIds = [
        for (final segment in segments)
          if (segment.openingId != null) segment.openingId!,
      ];
      final containedObjectIds = [
        for (final object in objects)
          if (object.containingSpaceId == space.id) object.id,
      ];
      final wallSegmentCount = segments
          .where((s) => s.type == BoundarySegmentType.wall)
          .length;
      final boundaryConfidence = segments.isEmpty
          ? 0.3
          : wallSegmentCount / segments.length * 0.7 + 0.3;
      spaces.add(
        InterpretedSpace(
          id: space.id,
          sourcePrimitiveId: 'envelope-floor-domain',
          polygon: space.polygon,
          areaNormalized: space.areaNormalized,
          boundaryWallIds: boundaryWallIds,
          boundaryOpeningIds: boundaryOpeningIds,
          adjacentSpaceIds: adjacent.toList(),
          boundaryConfidence: boundaryConfidence,
          topologyValid: true,
          reasons: const [
            'reconstructed from envelope-first floor-domain subdivision',
          ],
          boundarySegments: segments,
          containedObjectIds: containedObjectIds,
        ),
      );
    }

    if (objects.isNotEmpty) {
      warnings.add('가구/설비 후보를 공간에서 제외했습니다.');
    }

    return ArchitecturalInterpretation(
      primitives: const [],
      semanticPrimitives: const [],
      wallGraph: wallGraph,
      openings: openings,
      spaces: spaces,
      objects: objects,
      dimensions: const [],
      annotations: const [],
      traces: const [],
      diagnostics: [
        DrawingDiagnosticOutput(
          stage: DrawingDiagnosticStage.finalModel,
          entityIds: [for (final space in spaces) space.id],
          summary:
              'envelope-first: ${spaces.length} space(s), ${wallGraph.walls.length} wall(s), '
              '${openings.length} opening(s), ${objects.length} object(s) excluded',
        ),
      ],
      warnings: warnings,
    );
  }

  /// 건물 외곽/공간 재구성이 실패해도(벽·방 evidence가 아예 없거나
  /// 너무 적음) 문/창 evidence 자체는 조용히 버리지 않는다 — 다른
  /// 계층(예: [estimateScaleFromDoors] 자동 축척 추정)이 여전히 이
  /// evidence를 쓸 수 있어야 한다. 어떤 벽에도 연결되지 못했다는
  /// 뜻이므로 confidence는 낮춰 미확정임을 정직하게 남긴다.
  ArchitecturalInterpretation _emptyInterpretation(
    List<String> warnings, [
    List<OpeningCandidate> openings = const [],
  ]) {
    return ArchitecturalInterpretation(
      primitives: const [],
      semanticPrimitives: const [],
      wallGraph: const ArchitecturalWallGraph(
        walls: [],
        junctions: [],
        connectedComponents: [],
      ),
      openings: [
        for (final opening in openings)
          InterpretedOpening(
            id: opening.id,
            sourcePrimitiveId: 'primitive-opening-${opening.id}',
            // 벽/공간 재구성이 실패했다는 사실과 원본 evidence의 문/창
            // 구분은 별개다 — 후자는 그대로 보존한다(위 본문 경로와
            // 동일한 원칙).
            kind: switch (opening.type) {
              OpeningType.door => DrawingSemanticType.doorSymbol,
              OpeningType.window => DrawingSemanticType.windowSymbol,
              OpeningType.unknown => DrawingSemanticType.unknown,
            },
            center: opening.center,
            widthNormalized: opening.widthNormalized,
            parentWallId: null,
            confidence: 0.2,
            reasons: const [
              'no reconstructed space/wall to attach this opening to',
            ],
          ),
      ],
      spaces: const [],
      objects: const [],
      dimensions: const [],
      annotations: const [],
      traces: const [],
      diagnostics: const [],
      warnings: warnings,
    );
  }

  /// [space]의 폴리곤 변(edge)마다 벽/문/창/이웃 SPACE/미상을 판정한다 —
  /// [ArchitecturalDrawingInterpreter._boundarySegmentsFor]와 원리는 같지만
  /// (표준적인 "가장 가까운 벽 evidence 찾기 → 없으면 이웃 SPACE 찾기 →
  /// 그마저 없으면 미상") 이 파일은 space-first 파일을 import하지 않고
  /// 독립적으로 구현한다.
  List<InterpretedBoundarySegment> _boundarySegmentsFor(
    _RawSpace space,
    List<_RawSpace> allSpaces,
    List<WallSegment> allWalls,
    List<OpeningCandidate> allOpenings,
  ) {
    final polygon = space.polygon;
    final segments = <InterpretedBoundarySegment>[];
    for (var i = 0; i < polygon.length; i++) {
      final a = polygon[i];
      final b = polygon[(i + 1) % polygon.length];
      final mid = Point2((a.x + b.x) / 2, (a.y + b.y) / 2);
      final id = 'boundary-${space.id}-$i';

      WallSegment? matchedWall;
      var bestDist = double.infinity;
      for (final wall in allWalls) {
        final d = _segmentDistance(mid, wall.start, wall.end);
        final tolerance = math.max(wall.thicknessNormalized * 2, 0.02);
        if (d <= tolerance && d < bestDist) {
          matchedWall = wall;
          bestDist = d;
        }
      }

      // 이 edge 바깥쪽(방 밖 방향)으로 [offset]만큼 나간 지점이 다른
      // SPACE 안에 있으면 그 SPACE가 반대편이다 — 벽이 있든 없든 같은
      // 방식으로 찾는다(벽이 있으면 그 두께를 건너뛸 만큼 [offset]을
      // 넉넉히 준다. 그렇지 않으면 샘플 지점이 여전히 벽 내부에 남아
      // 어느 SPACE에도 속하지 못해 인접 관계를 놓친다).
      String? findOppositeSpace(double offset) {
        final dx = b.x - a.x, dy = b.y - a.y;
        final len = math.sqrt(dx * dx + dy * dy);
        if (len == 0) return null;
        final nx = -dy / len * offset, ny = dx / len * offset;
        final p1 = Point2(mid.x + nx, mid.y + ny);
        final p2 = Point2(mid.x - nx, mid.y - ny);
        final outward = _contains(space.polygon, p1) ? p2 : p1;
        for (final other in allSpaces) {
          if (other.id == space.id) continue;
          if (_contains(other.polygon, outward)) return other.id;
        }
        return null;
      }

      if (matchedWall != null) {
        OpeningCandidate? matchedOpening;
        for (final opening in allOpenings) {
          if (_segmentDistance(opening.center, a, b) <= 0.03) {
            matchedOpening = opening;
            break;
          }
        }
        // 이 벽을 사이에 두고 실제로 맞닿은 다른 SPACE가 있는지 —
        // 벽 두께의 1.5배 정도면 반대쪽 방 안까지 확실히 넘어간다.
        final oppositeAcrossWall = findOppositeSpace(
          math.max(matchedWall.thicknessNormalized * 1.5, 0.025),
        );
        if (matchedOpening != null) {
          final type = switch (matchedOpening.type) {
            OpeningType.door => BoundarySegmentType.door,
            OpeningType.window => BoundarySegmentType.window,
            OpeningType.unknown => BoundarySegmentType.openPassage,
          };
          segments.add(
            InterpretedBoundarySegment(
              id: id,
              start: a,
              end: b,
              type: type,
              confidence: matchedOpening.confidence,
              reasons: const [
                'opening evidence found along this boundary edge',
              ],
              wallId: matchedWall.id,
              openingId: matchedOpening.id,
              oppositeSpaceId: oppositeAcrossWall,
              isExterior: matchedWall.isExterior && oppositeAcrossWall == null,
            ),
          );
          continue;
        }
        segments.add(
          InterpretedBoundarySegment(
            id: id,
            start: a,
            end: b,
            type: BoundarySegmentType.wall,
            confidence: matchedWall.confidence,
            reasons: const ['wall evidence found along this boundary edge'],
            wallId: matchedWall.id,
            oppositeSpaceId: oppositeAcrossWall,
            isExterior: matchedWall.isExterior && oppositeAcrossWall == null,
          ),
        );
        continue;
      }

      final oppositeId = findOppositeSpace(0.015);

      if (oppositeId != null) {
        segments.add(
          InterpretedBoundarySegment(
            id: id,
            start: a,
            end: b,
            type: BoundarySegmentType.virtual,
            confidence: 0.4,
            reasons: const [
              'no wall evidence, but this edge borders another reconstructed '
                  'space — kept as an open boundary rather than dropped',
            ],
            oppositeSpaceId: oppositeId,
          ),
        );
      } else {
        segments.add(
          InterpretedBoundarySegment(
            id: id,
            start: a,
            end: b,
            type: BoundarySegmentType.unknown,
            confidence: 0.25,
            reasons: const [
              'no wall evidence and no neighboring space found for this edge '
                  '— likely the building envelope itself',
            ],
            isExterior: true,
          ),
        );
      }
    }
    return segments;
  }

  Map<String, Set<String>> _links(List<WallSegment> walls) {
    final links = {for (final wall in walls) wall.id: <String>{}};
    for (var i = 0; i < walls.length; i++) {
      for (var j = i + 1; j < walls.length; j++) {
        if (_touch(walls[i], walls[j])) {
          links[walls[i].id]!.add(walls[j].id);
          links[walls[j].id]!.add(walls[i].id);
        }
      }
    }
    return links;
  }

  bool _touch(WallSegment a, WallSegment b) {
    for (final p in [a.start, a.end]) {
      if (_segmentDistance(p, b.start, b.end) <= 0.018) return true;
    }
    for (final p in [b.start, b.end]) {
      if (_segmentDistance(p, a.start, a.end) <= 0.018) return true;
    }
    return false;
  }

  List<List<String>> _components(
    List<WallSegment> walls,
    Map<String, Set<String>> links,
  ) {
    final unseen = walls.map((wall) => wall.id).toSet();
    final result = <List<String>>[];
    while (unseen.isNotEmpty) {
      final queue = [unseen.first];
      unseen.remove(queue.first);
      final component = <String>[];
      while (queue.isNotEmpty) {
        final id = queue.removeLast();
        component.add(id);
        for (final next in links[id] ?? const <String>{}) {
          if (unseen.remove(next)) queue.add(next);
        }
      }
      result.add(component);
    }
    return result;
  }

  List<WallGraphJunction> _junctions(List<WallSegment> walls) {
    final result = <WallGraphJunction>[];
    final used = <String>{};
    for (final wall in walls) {
      for (final point in [wall.start, wall.end]) {
        final ids = walls
            .where(
              (other) =>
                  _segmentDistance(point, other.start, other.end) <= 0.018,
            )
            .map((other) => other.id)
            .toSet();
        if (ids.length < 2) continue;
        final sorted = ids.toList()..sort();
        final key =
            sorted.join('|') +
            point.x.toStringAsFixed(2) +
            point.y.toStringAsFixed(2);
        if (!used.add(key)) continue;
        result.add(
          WallGraphJunction(
            id: 'junction-${result.length + 1}',
            position: point,
            type: ids.length == 2
                ? WallJunctionType.l
                : ids.length == 3
                ? WallJunctionType.t
                : WallJunctionType.x,
            wallIds: sorted,
          ),
        );
      }
    }
    return result;
  }
}

@immutable
class _RawSpace {
  const _RawSpace({
    required this.id,
    required this.polygon,
    required this.areaNormalized,
  });

  final String id;
  final List<Point2> polygon;
  final double areaNormalized;
}

class _Grid {
  _Grid(this.w, this.h) : cells = Uint8List(w * h);
  final int w;
  final int h;
  final Uint8List cells;
}

/// [polygon](정규화 좌표, 볼록/오목 모두 가능)을 [grid]에 채운다 —
/// 표준 스캔라인 다각형 채우기. 벽 footprint(얇은 사각형)와 방 evidence
/// polygon 둘 다 이 함수 하나로 처리한다.
void _fillPolygonNormalized(_Grid grid, List<Point2> polygon) {
  if (polygon.length < 3) return;
  var minY = double.infinity, maxY = -double.infinity;
  for (final p in polygon) {
    minY = math.min(minY, p.y);
    maxY = math.max(maxY, p.y);
  }
  final startRow = math.max(0, (minY * grid.h).floor());
  final endRow = math.min(grid.h - 1, (maxY * grid.h).ceil());

  for (var gy = startRow; gy <= endRow; gy++) {
    final y = (gy + 0.5) / grid.h;
    final xs = <double>[];
    for (var i = 0; i < polygon.length; i++) {
      final a = polygon[i];
      final b = polygon[(i + 1) % polygon.length];
      if ((a.y <= y && b.y > y) || (b.y <= y && a.y > y)) {
        final t = (y - a.y) / (b.y - a.y);
        xs.add(a.x + t * (b.x - a.x));
      }
    }
    if (xs.isEmpty) continue;
    xs.sort();
    for (var i = 0; i + 1 < xs.length; i += 2) {
      final spanStart = xs[i] * grid.w;
      final spanEnd = xs[i + 1] * grid.w;
      final startCol = math.max(0, spanStart.floor());
      final endCol = math.min(grid.w - 1, spanEnd.ceil());
      // 픽셀 "중심"이 span 안에 있을 때만 칠한다(반열림 구간
      // [spanStart, spanEnd)) — floor/ceil로 넉넉히 잡은 뒤 중심으로
      // 다시 거르는 이유: 두 폴리곤이 정확히 같은 좌표(예: 두 방이 벽
      // 없이 정확히 x=0.5에서 맞닿음)에서 경계를 공유하면, 양쪽 다
      // "그 경계 칸은 내 것"이라고 겹쳐 칠해 서로 다른 두 영역을
      // 1픽셀 두께로 용접해버리는 문제가 있었다 — 중심 기준 반열림
      // 판정은 그 경계 칸을 정확히 한쪽에만 배정한다.
      for (var gx = startCol; gx <= endCol; gx++) {
        final center = gx + 0.5;
        if (center >= spanStart && center < spanEnd) {
          grid.cells[gy * grid.w + gx] = 1;
        }
      }
    }
  }
}

/// [WallSegment]의 두께 있는 footprint(중심선 기준 양쪽으로 두께의
/// 절반만큼 수직 offset한 4점 폐곡선) — [CadWall.boundaryPolygon]과
/// 동일한 공식이지만, 이 파일은 model 계층(순환 import 위험, model이
/// 이 service를 이미 참조함)을 피하기 위해 evidence 타입([WallSegment])
/// 기준으로 독립적으로 계산한다.
List<Point2> _wallFootprintPolygon(WallSegment wall) {
  final dx = wall.end.x - wall.start.x;
  final dy = wall.end.y - wall.start.y;
  final len = math.sqrt(dx * dx + dy * dy);
  if (len == 0) {
    return [wall.start, wall.start, wall.start, wall.start];
  }
  final half = wall.thicknessNormalized / 2;
  final nx = -dy / len * half;
  final ny = dx / len * half;
  return [
    Point2(wall.start.x + nx, wall.start.y + ny),
    Point2(wall.end.x + nx, wall.end.y + ny),
    Point2(wall.end.x - nx, wall.end.y - ny),
    Point2(wall.start.x - nx, wall.start.y - ny),
  ];
}

/// 2x2 블록에서 대각선 두 칸만 채워진("안장점", marching-squares 고전적
/// ambiguous case) 구성을 찾아 그 중 하나를 채워 없앤다 — 이후 어떤
/// 윤곽 추적도 이 모호함 때문에 실패하지 않도록 미리 해소한다(WO —
/// 이번에는 "안전하게 실패해 bounding box로 폴백"하지 않는다: Envelope
/// 자체가 목적이므로 사각형 근사로 도망칠 수 없다).
void _removeSaddlePoints(_Grid grid) {
  for (var y = 0; y < grid.h - 1; y++) {
    for (var x = 0; x < grid.w - 1; x++) {
      final a = grid.cells[y * grid.w + x];
      final b = grid.cells[y * grid.w + x + 1];
      final c = grid.cells[(y + 1) * grid.w + x];
      final d = grid.cells[(y + 1) * grid.w + x + 1];
      if (a == 1 && d == 1 && b == 0 && c == 0) {
        grid.cells[y * grid.w + x + 1] = 1;
      } else if (b == 1 && c == 1 && a == 0 && d == 0) {
        grid.cells[y * grid.w + x] = 1;
      }
    }
  }
}

/// [grid]의 foreground(1) 픽셀을 연결 성분으로 묶는다. [eightConnected]가
/// true면 대각선 인접도 같은 성분으로 본다(Envelope 재구성 — 벽 footprint와
/// 방 polygon이 픽셀 경계에서 대각선으로만 살짝 어긋나 이어지는 경우가
/// 흔해, 8-연결이 실제로 하나인 건물을 여러 조각으로 잘못 나누는 것을
/// 막는다). 내부 SPACE 분할은 4-연결을 쓴다(기존 방 검출 관례와 동일 —
/// 대각선으로만 맞닿은 두 영역까지 "연결됐다"고 보면 실제로는 벽 하나
/// 사이에 두고 떨어진 두 방이 하나로 합쳐질 위험이 있다).
List<List<int>> _connectedComponents(
  _Grid grid, {
  required bool eightConnected,
}) {
  final visited = Uint8List(grid.w * grid.h);
  final result = <List<int>>[];
  for (var start = 0; start < grid.cells.length; start++) {
    if (grid.cells[start] != 1 || visited[start] == 1) continue;
    final component = <int>[];
    final stack = <int>[start];
    visited[start] = 1;
    while (stack.isNotEmpty) {
      final idx = stack.removeLast();
      component.add(idx);
      final x = idx % grid.w;
      final y = idx ~/ grid.w;
      final neighbors = eightConnected
          ? const [
              [-1, 0],
              [1, 0],
              [0, -1],
              [0, 1],
              [-1, -1],
              [1, -1],
              [-1, 1],
              [1, 1],
            ]
          : const [
              [-1, 0],
              [1, 0],
              [0, -1],
              [0, 1],
            ];
      for (final n in neighbors) {
        final nx = x + n[0], ny = y + n[1];
        if (nx < 0 || ny < 0 || nx >= grid.w || ny >= grid.h) continue;
        final nIdx = ny * grid.w + nx;
        if (grid.cells[nIdx] != 1 || visited[nIdx] == 1) continue;
        visited[nIdx] = 1;
        stack.add(nIdx);
      }
    }
    result.add(component);
  }
  return result;
}

/// [pixels](같은 연결 성분)의 실제 외곽(가장 바깥쪽 loop 하나)을 추적한다.
/// [_removeSaddlePoints]를 이미 거친 격자에서만 호출되므로 안장점 모호성은
/// 없지만, 성분 내부에 구멍(도넛 모양)이 있으면 edge 집합에 loop가 여러
/// 개 생길 수 있다 — 그 중 부호 있는 면적의 절댓값이 가장 큰 loop가
/// 항상 바깥 윤곽이므로 그것을 고른다.
List<({int x, int y})>? _outerLoop(Set<int> pixels, int w, int h) {
  var minX = w, maxX = -1, minY = h, maxY = -1;
  for (final idx in pixels) {
    final x = idx % w, y = idx ~/ w;
    if (x < minX) minX = x;
    if (x > maxX) maxX = x;
    if (y < minY) minY = y;
    if (y > maxY) maxY = y;
  }
  if (maxX < minX || maxY < minY) return null;
  final localW = maxX - minX + 1;
  final localH = maxY - minY + 1;

  // 성분 판정([_connectedComponents])은 이미 끝났다 — 여기서부터는 오직
  // 이 [pixels] 하나만의 윤곽을 어떻게 그릴지의 문제이므로, 안장점 제거를
  // 이 성분 전용 로컬 격자에만 적용해도 다른 성분과의 연결 여부에는 전혀
  // 영향을 주지 않는다(전역 격자에서 미리 제거하면 대각선 한 점에서만
  // 닿은 서로 다른 두 성분을 하나로 용접해버리는 문제가 있었다).
  final local = _Grid(localW, localH);
  for (final idx in pixels) {
    final x = idx % w - minX, y = idx ~/ w - minY;
    local.cells[y * localW + x] = 1;
  }
  _removeSaddlePoints(local);

  bool inRegion(int x, int y) {
    if (x < 0 || y < 0 || x >= localW || y >= localH) return false;
    return local.cells[y * localW + x] == 1;
  }

  int vKey(int x, int y) => y * (localW + 1) + x;
  final nextVertex = <int, int>{};
  void addEdge(int x1, int y1, int x2, int y2) {
    nextVertex[vKey(x1, y1)] = vKey(x2, y2);
  }

  for (var y = 0; y < localH; y++) {
    for (var x = 0; x < localW; x++) {
      if (!inRegion(x, y)) continue;
      if (!inRegion(x, y - 1)) addEdge(x, y, x + 1, y);
      if (!inRegion(x + 1, y)) addEdge(x + 1, y, x + 1, y + 1);
      if (!inRegion(x, y + 1)) addEdge(x + 1, y + 1, x, y + 1);
      if (!inRegion(x - 1, y)) addEdge(x, y + 1, x, y);
    }
  }
  if (nextVertex.isEmpty) return null;

  final remaining = Map<int, int>.from(nextVertex);
  final loops = <List<({int x, int y})>>[];
  while (remaining.isNotEmpty) {
    final startKey = remaining.keys.first;
    final loopKeys = <int>[startKey];
    var current = startKey;
    remaining.remove(startKey);
    final maxSteps = (localW + 1) * (localH + 1) * 4 + 8;
    while (loopKeys.length <= maxSteps) {
      final next = nextVertex[current];
      if (next == null || next == startKey) break;
      loopKeys.add(next);
      remaining.remove(current);
      current = next;
    }
    remaining.remove(current);
    if (loopKeys.length >= 3) {
      loops.add([
        for (final k in loopKeys) (x: k % (localW + 1), y: k ~/ (localW + 1)),
      ]);
    }
  }
  if (loops.isEmpty) return null;

  double area(List<({int x, int y})> loop) {
    var sum = 0.0;
    for (var i = 0; i < loop.length; i++) {
      final a = loop[i];
      final b = loop[(i + 1) % loop.length];
      sum += a.x.toDouble() * b.y - b.x.toDouble() * a.y;
    }
    return sum.abs() / 2;
  }

  loops.sort((a, b) => area(b).compareTo(area(a)));
  final outer = loops.first;

  // 직선 위 중간 정점(방향이 안 바뀌는 점) 제거 — 실제 모서리만 남긴다.
  final corners = <({int x, int y})>[];
  for (var i = 0; i < outer.length; i++) {
    final prev = outer[(i - 1 + outer.length) % outer.length];
    final cur = outer[i];
    final next = outer[(i + 1) % outer.length];
    final dx1 = cur.x - prev.x, dy1 = cur.y - prev.y;
    final dx2 = next.x - cur.x, dy2 = next.y - cur.y;
    if (dx1 * dy2 - dy1 * dx2 != 0) corners.add(cur);
  }
  final finalPoints = corners.length >= 3 ? corners : outer;
  return [for (final p in finalPoints) (x: p.x + minX, y: p.y + minY)];
}

double _segmentDistance(Point2 p, Point2 a, Point2 b) {
  final dx = b.x - a.x, dy = b.y - a.y;
  if (dx == 0 && dy == 0) return p.distanceTo(a);
  final t = (((p.x - a.x) * dx + (p.y - a.y) * dy) / (dx * dx + dy * dy)).clamp(
    0.0,
    1.0,
  );
  return p.distanceTo(Point2(a.x + t * dx, a.y + t * dy));
}

bool _nearPolygon(Point2 point, List<Point2> polygon) {
  for (var i = 0; i < polygon.length; i++) {
    if (_segmentDistance(
          point,
          polygon[i],
          polygon[(i + 1) % polygon.length],
        ) <=
        0.025) {
      return true;
    }
  }
  return false;
}

bool _contains(List<Point2> polygon, Point2 point) {
  var inside = false;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final a = polygon[i], b = polygon[j];
    if (((a.y > point.y) != (b.y > point.y)) &&
        point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x) {
      inside = !inside;
    }
  }
  return inside;
}

Point2 _centroid(List<Point2> polygon) {
  var sx = 0.0, sy = 0.0;
  for (final p in polygon) {
    sx += p.x;
    sy += p.y;
  }
  return Point2(sx / polygon.length, sy / polygon.length);
}
