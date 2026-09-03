import 'gpt_cad_schema.dart';

/// SPACE SHIFT — Real GPT Vision → Detailed CAD JSON → SS Refinement POC.
///
/// GPT가 돌려준 JSON을 "형태만 맞으면" 그대로 신뢰하지 않는다(사용자
/// 지시 17번). [GptCadProposal.fromJson]이 이미 기본 모양(필드 존재/
/// 타입)을 확인했다는 전제 하에, 여기서는 cross-reference와 의미
/// 제약을 검증한다. 실패하면 명확한 [GptCadValidationException]을
/// 던진다 — 절대 임의 fallback geometry를 만들어 조용히 통과시키지
/// 않는다.
class GptCadValidationException implements Exception {
  GptCadValidationException(this.errors);
  final List<String> errors;

  @override
  String toString() => 'GptCadValidationException:\n${errors.map((e) => '  - $e').join('\n')}';
}

const kSupportedSchemaVersion = 'ss-cad-vision-v1';

class GptCadJsonValidator {
  const GptCadJsonValidator();

  /// 검증에 통과하면 그대로 [proposal]을 돌려준다(변형하지 않는다).
  /// 실패하면 [GptCadValidationException]을 던진다.
  GptCadProposal validate(GptCadProposal proposal) {
    final errors = <String>[];

    if (proposal.schemaVersion != kSupportedSchemaVersion) {
      errors.add('unsupported schemaVersion "${proposal.schemaVersion}" (expected "$kSupportedSchemaVersion")');
    }

    // 1) ID 고유성 (corners/walls/spaces/doors/windows/openings/objects
    // 전체를 한 namespace로 본다 — 서로 다른 종류가 같은 id를 쓰면
    // 참조가 모호해진다).
    final allIds = <String, String>{}; // id -> entity kind (첫 등장)
    void trackId(String id, String kind) {
      final existing = allIds[id];
      if (existing != null) {
        errors.add('duplicate id "$id" used by both $existing and $kind');
      } else {
        allIds[id] = kind;
      }
    }

    for (final c in proposal.corners) {
      trackId(c.id, 'corner');
    }
    for (final w in proposal.walls) {
      trackId(w.id, 'wall');
    }
    for (final s in proposal.spaces) {
      trackId(s.id, 'space');
    }
    for (final d in proposal.doors) {
      trackId(d.id, 'door');
    }
    for (final win in proposal.windows) {
      trackId(win.id, 'window');
    }
    for (final o in proposal.openings) {
      trackId(o.id, 'opening');
    }
    for (final obj in proposal.objects) {
      trackId(obj.id, 'object');
    }

    final cornerIds = proposal.corners.map((c) => c.id).toSet();
    final wallIds = proposal.walls.map((w) => w.id).toSet();
    final spaceIds = proposal.spaces.map((s) => s.id).toSet();

    // 2) 좌표 범위 — 이미지 경계를 심하게 벗어나면 실수/환각 가능성.
    // 약간의 오버슈트(경계선상 corner)는 허용한다.
    final marginX = proposal.image.widthPx * 0.05;
    final marginY = proposal.image.heightPx * 0.05;
    for (final c in proposal.corners) {
      if (c.x < -marginX || c.x > proposal.image.widthPx + marginX || c.y < -marginY || c.y > proposal.image.heightPx + marginY) {
        errors.add('corner "${c.id}" coordinate (${c.x}, ${c.y}) is far outside image bounds '
            '(${proposal.image.widthPx}x${proposal.image.heightPx})');
      }
    }

    // 3) Wall → corner 참조.
    for (final w in proposal.walls) {
      if (w.cornerIds.length < 2) {
        errors.add('wall "${w.id}" must reference at least 2 corners, got ${w.cornerIds.length}');
      }
      for (final cid in w.cornerIds) {
        if (!cornerIds.contains(cid)) {
          errors.add('wall "${w.id}" references unknown corner id "$cid"');
        }
      }
    }

    // 4) Space → wall 참조.
    for (final s in proposal.spaces) {
      for (final wid in s.boundaryWallIds) {
        if (!wallIds.contains(wid)) {
          errors.add('space "${s.id}" references unknown wall id "$wid"');
        }
      }
    }

    // 5) Door/Window/Opening → hostWall 참조 + connectsSpaceIds 참조.
    for (final d in proposal.doors) {
      if (!wallIds.contains(d.hostWallId)) {
        errors.add('door "${d.id}" references unknown hostWallId "${d.hostWallId}"');
      }
      if (d.startT >= d.endT) {
        errors.add('door "${d.id}" has invalid interval startT(${d.startT}) >= endT(${d.endT})');
      }
      for (final sid in d.connectsSpaceIds) {
        if (!spaceIds.contains(sid)) {
          errors.add('door "${d.id}" references unknown space id "$sid"');
        }
      }
    }
    for (final w in proposal.windows) {
      if (!wallIds.contains(w.hostWallId)) {
        errors.add('window "${w.id}" references unknown hostWallId "${w.hostWallId}"');
      }
      if (w.startT >= w.endT) {
        errors.add('window "${w.id}" has invalid interval startT(${w.startT}) >= endT(${w.endT})');
      }
    }
    for (final o in proposal.openings) {
      if (!wallIds.contains(o.hostWallId)) {
        errors.add('opening "${o.id}" references unknown hostWallId "${o.hostWallId}"');
      }
      for (final sid in o.connectsSpaceIds) {
        if (!spaceIds.contains(sid)) {
          errors.add('opening "${o.id}" references unknown space id "$sid"');
        }
      }
    }

    // 6) Object → containingSpaceId 참조(있으면).
    for (final obj in proposal.objects) {
      final sid = obj.containingSpaceId;
      if (sid != null && !spaceIds.contains(sid)) {
        errors.add('object "${obj.id}" references unknown containingSpaceId "$sid"');
      }
    }

    // 7) FloorDomain 폐합 — 최소 3개의 서로 다른 corner, 전부 실존.
    final domainIds = proposal.floorDomain.orderedCornerIds;
    if (domainIds.toSet().length < 3) {
      errors.add('floorDomain.orderedCornerIds must reference at least 3 distinct corners, got ${domainIds.toSet().length}');
    }
    for (final cid in domainIds) {
      if (!cornerIds.contains(cid)) {
        errors.add('floorDomain references unknown corner id "$cid"');
      }
    }

    // 8) Relationship → entity 참조(모든 종류의 id를 통틀어 확인).
    for (final r in proposal.relationships) {
      if (!allIds.containsKey(r.entityA)) {
        errors.add('relationship references unknown entityA "${r.entityA}"');
      }
      if (!allIds.containsKey(r.entityB)) {
        errors.add('relationship references unknown entityB "${r.entityB}"');
      }
    }

    if (errors.isNotEmpty) {
      throw GptCadValidationException(errors);
    }
    return proposal;
  }
}
