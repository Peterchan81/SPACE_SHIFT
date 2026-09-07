// SPACE SHIFT — WO088-5 §9 LINE → WALL 판정 강화.
//
// "검은 픽셀 = 벽"이 아니라, 여러 구조 evidence가 함께 있어야 confirmed
// wall로 본다(§9). 0/90 정렬만으로는 확정하지 않는다 — 계단 발판/사다리
// 모양 hatch도 축정렬 짧은 선을 반복적으로 만들 수 있기 때문이다.
//
// 이 파일은 structural_layer.dart가 만든 [RawStructuralLine] 목록만
// 입력으로 받는 순수 후처리다(Flutter-free, 새 pixel 분석 없음).

import 'dart:math' as math;

import 'structural_layer.dart';

enum WallConfirmReason { substantialLength, junctionConnected }

enum WallSuppressReason { isolatedShort, repeatedPatternCluster }

class WallCandidateVerdict {
  const WallCandidateVerdict({required this.line, required this.confirmed, this.confirmReason, this.suppressReason});
  final RawStructuralLine line;
  final bool confirmed;
  final WallConfirmReason? confirmReason;
  final WallSuppressReason? suppressReason;
}

double _length(RawStructuralLine l) {
  final dx = l.end.x - l.start.x, dy = l.end.y - l.start.y;
  return math.sqrt(dx * dx + dy * dy);
}

bool _isHorizontal(RawStructuralLine l) => (l.end.x - l.start.x).abs() >= (l.end.y - l.start.y).abs();

double _endpointDist(Pt a, Pt b) {
  final dx = a.x - b.x, dy = a.y - b.y;
  return math.sqrt(dx * dx + dy * dy);
}

/// §9 우선순위 evidence로 wall 여부를 확정한다.
///
/// 1) substantialLength — 이미지 대각선의 [substantialLengthFraction](기본
///    6%, 사람 눈에 "방을 가로지르는 벽"으로 보이는 최소 비율의 보수적
///    근사) 이상이면 그 자체로 확정한다(이미 명백히 구조적인 벽).
/// 2) junctionConnected — 길이가 부족해도, 양 끝점 중 하나가 다른(자기
///    자신이 아닌) line의 끝점 또는 몸통 근처(§ cornerTolerancePx)에
///    닿아 있으면 L/T/X 접합으로 보아 확정한다.
/// 3) repeatedPatternCluster — 같은 방향(수평/수직)이고 서로 인접한 짧은
///    line이 국소 영역에 [repeatedPatternMinCount]개 이상 몰려 있으면
///    (계단 발판/사다리형 hatch의 전형적 패턴) 그룹 전체를 억제한다 —
///    개별 삭제가 아니라 reviewNeeded로 분리한다(§3 "삭제 아님").
/// 4) 위 어디에도 해당하지 않으면 isolatedShort로 억제한다.
List<WallCandidateVerdict> confirmWalls(
  List<RawStructuralLine> lines, {
  required int imageW,
  required int imageH,
  double substantialLengthFraction = 0.06,
  double cornerTolerancePx = 10,
  int repeatedPatternMinCount = 4,
  double repeatedPatternClusterPx = 60,
}) {
  final diagonal = math.sqrt(imageW * imageW + imageH * imageH);
  final substantialLengthPx = diagonal * substantialLengthFraction;

  final verdicts = <WallCandidateVerdict>[];
  final pendingShort = <RawStructuralLine>[];

  for (final l in lines) {
    if (_length(l) >= substantialLengthPx) {
      verdicts.add(WallCandidateVerdict(line: l, confirmed: true, confirmReason: WallConfirmReason.substantialLength));
      continue;
    }
    // junction 연결 여부 — 다른 모든 line(자기 자신 제외)의 끝점과 비교.
    var connected = false;
    for (final other in lines) {
      if (identical(other, l)) continue;
      if (_endpointDist(l.start, other.start) <= cornerTolerancePx ||
          _endpointDist(l.start, other.end) <= cornerTolerancePx ||
          _endpointDist(l.end, other.start) <= cornerTolerancePx ||
          _endpointDist(l.end, other.end) <= cornerTolerancePx) {
        connected = true;
        break;
      }
    }
    if (connected) {
      verdicts.add(WallCandidateVerdict(line: l, confirmed: true, confirmReason: WallConfirmReason.junctionConnected));
    } else {
      pendingShort.add(l);
    }
  }

  // repeated-pattern 클러스터 탐지 — pendingShort 중 같은 방향이고 서로
  // repeatedPatternClusterPx 이내에 몰린 그룹을 찾는다(단순 그리디 클러스터링).
  final assigned = List<bool>.filled(pendingShort.length, false);
  for (var i = 0; i < pendingShort.length; i++) {
    if (assigned[i]) continue;
    final group = <int>[i];
    final horizI = _isHorizontal(pendingShort[i]);
    final midI = ((pendingShort[i].start.x + pendingShort[i].end.x) / 2, (pendingShort[i].start.y + pendingShort[i].end.y) / 2);
    for (var j = i + 1; j < pendingShort.length; j++) {
      if (assigned[j]) continue;
      if (_isHorizontal(pendingShort[j]) != horizI) continue;
      final midJ = ((pendingShort[j].start.x + pendingShort[j].end.x) / 2, (pendingShort[j].start.y + pendingShort[j].end.y) / 2);
      final d = math.sqrt(math.pow(midI.$1 - midJ.$1, 2) + math.pow(midI.$2 - midJ.$2, 2));
      if (d <= repeatedPatternClusterPx) group.add(j);
    }
    if (group.length >= repeatedPatternMinCount) {
      for (final idx in group) {
        assigned[idx] = true;
        verdicts.add(WallCandidateVerdict(line: pendingShort[idx], confirmed: false, suppressReason: WallSuppressReason.repeatedPatternCluster));
      }
    }
  }
  for (var i = 0; i < pendingShort.length; i++) {
    if (assigned[i]) continue;
    verdicts.add(WallCandidateVerdict(line: pendingShort[i], confirmed: false, suppressReason: WallSuppressReason.isolatedShort));
  }

  return verdicts;
}
