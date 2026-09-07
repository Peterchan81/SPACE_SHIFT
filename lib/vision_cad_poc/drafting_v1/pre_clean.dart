// SPACE SHIFT — WO088-5 CLEAN STRUCTURAL LAYER (PRE-CLEAN).
//
// §3/§4 — Grayscale 직후, line/wall extraction 전에 "벽처럼 생기지 않은"
// 연결 요소(connected component)를 구조적 특성으로 걸러낸다. WO088-4의
// dark+low-chroma mask(structural_layer.dart)는 그대로 재사용한다
// (§21 — 이미 검증된 pixel-level 판정을 다시 만들지 않는다). 이 파일은
// 그 mask 위에 "이 연결된 어두운 픽셀 덩어리가 벽처럼 길고 얇은가,
// 아니면 아이콘/기호/텍스트/바닥 얼룩처럼 뭉툭한가"를 구분하는 한 겹을
// 추가할 뿐이다.
//
// §4 절대 안전 규칙: 넓은 영역 = noise로 단순 판정하지 않는다. 두꺼운
// 구조벽도 넓을 수 있다 — 그래서 "면적"이 아니라 "elongation(길이/두께
// 비율)"으로 판단한다. 두껍고 긴 진짜 벽은 elongation이 여전히 크다
// (예: 300px 길이 x 15px 두께 = elongation 20). 반대로 아이콘/기호/
// 텍스트/바닥 얼룩은 bounding box가 정사각형에 가깝다(elongation 작음).
//
// §5 hatch 정책: hatch 연결 요소를 mask에서 완전히 지우지 않는다 —
// [PreCleanResult.suppressedMask]로 별도 보존해, 향후 "벽 영역 보조
// evidence"로 재사용할 수 있는 구조를 유지한다(§5 "hatch != wall line,
// but hatch may support wall-region evidence").

import 'dart:typed_data';

import 'dart:math' as math;

class PreCleanResult {
  const PreCleanResult({required this.w, required this.h, required this.cleanMask, required this.suppressedMask, required this.componentCount, required this.suppressedComponentCount});
  final int w, h;

  /// Layer 3 — wall-like(elongated) 연결 요소만 남긴 mask.
  final Uint8List cleanMask;

  /// 제외된 연결 요소(아이콘/기호/텍스트/바닥 얼룩/hatch) — 원본 evidence는
  /// 버리지 않고 여기 보존한다(§2/§6 — 삭제가 아니라 분리).
  final Uint8List suppressedMask;

  final int componentCount;
  final int suppressedComponentCount;
}

class _Component {
  _Component(int x, int y) : minX = x, maxX = x, minY = y, maxY = y, area = 0;
  int minX, maxX, minY, maxY, area;
  final List<int> pixelIndices = [];
}

/// [mask](WO088-4 structural_layer.dart의 dark+low-chroma mask)를 4-연결
/// 요소로 라벨링하고, 각 요소의 elongation(=bbox 긴 변/짧은 변)과
/// area로 "wall-like"인지 판정한다.
///
/// [elongationThreshold]: 이 값 이상이면 크기와 무관하게 무조건 유지한다
/// (§4 — 두꺼운 벽도 elongation만 크면 살아남아야 한다). 기본 4.0은
/// "벽은 두께보다 최소 4배 이상 길다"는 일반적인 건축 evidence이지
/// Image 3 전용 값이 아니다.
PreCleanResult preClean(
  Uint8List mask,
  int w,
  int h, {
  double elongationThreshold = 4.0,
}) {
  final labels = Int32List(w * h)..fillRange(0, w * h, -1);
  final components = <_Component>[];

  for (var start = 0; start < w * h; start++) {
    if (mask[start] != 1 || labels[start] != -1) continue;
    final comp = _Component(start % w, start ~/ w);
    final stack = <int>[start];
    labels[start] = components.length;
    while (stack.isNotEmpty) {
      final idx = stack.removeLast();
      final x = idx % w, y = idx ~/ w;
      comp.minX = math.min(comp.minX, x);
      comp.maxX = math.max(comp.maxX, x);
      comp.minY = math.min(comp.minY, y);
      comp.maxY = math.max(comp.maxY, y);
      comp.area++;
      comp.pixelIndices.add(idx);
      for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        final nx = x + dx, ny = y + dy;
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
        final nIdx = ny * w + nx;
        if (mask[nIdx] == 1 && labels[nIdx] == -1) {
          labels[nIdx] = components.length;
          stack.add(nIdx);
        }
      }
    }
    components.add(comp);
  }

  final cleanMask = Uint8List(w * h);
  final suppressedMask = Uint8List(w * h);
  var suppressedCount = 0;

  for (final comp in components) {
    final bboxW = comp.maxX - comp.minX + 1;
    final bboxH = comp.maxY - comp.minY + 1;
    final elongation = math.max(bboxW, bboxH) / math.max(1, math.min(bboxW, bboxH));
    // §4 — 판정 기준은 elongation 하나뿐이다. area는 절대 기준에 넣지
    // 않는다: "크다"는 이유로 제외하면 두꺼운 진짜 벽(면적은 크지만
    // elongation도 큼)까지 함께 제외될 위험이 있고, "작다"는 이유로
    // 제외하면 짧은 진짜 벽 stub까지 잃을 위험이 있다. elongation은
    // 두 경우 모두를 크기와 무관하게 올바르게 구분한다.
    final wallLike = elongation >= elongationThreshold;
    for (final idx in comp.pixelIndices) {
      if (wallLike) {
        cleanMask[idx] = 1;
      } else {
        suppressedMask[idx] = 1;
      }
    }
    if (!wallLike) suppressedCount++;
  }

  return PreCleanResult(w: w, h: h, cleanMask: cleanMask, suppressedMask: suppressedMask, componentCount: components.length, suppressedComponentCount: suppressedCount);
}
