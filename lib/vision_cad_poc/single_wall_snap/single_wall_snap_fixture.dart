import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// SPACE SHIFT — Vision Hint → Exact Wall SNAP 기술검증 전용 fixture.
///
/// 정직한 고지: 실제 사용자가 준 "이미지 2" 원본 파일은 이 저장소의
/// 파일시스템에 없다(채팅 첨부 이미지를 파일로 추출할 도구가 없다).
/// 기존 `sample_image2_fixture.dart`(production Vision-Guided 파이프라인
/// 전체 테스트가 공유하는 fixture)도 이번 지시("다른 벽/방 polygon/
/// FloorDomain 수정 금지")를 지키기 위해 건드리지 않는다 — 대신 이번
/// 기술검증 하나만을 위한 완전히 독립된 새 합성 이미지를 만든다.
///
/// 이 fixture는 "거실(좌) | 세로 내부벽 | 침실2(우)" 상황을 재현하되:
/// - 실제 벽 중심은 Vision hint(x=0.61)와 의도적으로 다른 위치(x=0.575)에
///   둔다 — hint를 그대로 베끼면 검증 의미가 없다.
/// - 위/아래에 실제 벽과 교차하는 가로 벽(T-junction)을 둬서, 벽의
///   실제 시작/끝점을 hint의 y 범위 밖에서 찾아야 하게 만든다.
/// - 벽 바로 옆에 벽과 비슷한 굵기/명도의 가구 사각형과 텍스트 모양의
///   잡음을 둬서, "가구/문자에 끌려가지 않는지"를 실제로 시험한다.
const int kSnapImageWidth = 800;
const int kSnapImageHeight = 600;

/// 실제(ground-truth) 벽 위치 — 오직 이 fixture를 만들 때만 쓰고,
/// 검출 알고리즘에는 절대 넘기지 않는다(검출기는 이미지 픽셀만 본다).
const double kSnapRealWallCenterX = 460;
const double kSnapRealWallLeftEdgeX = 455;
const double kSnapRealWallRightEdgeX = 465;
const double kSnapRealWallThicknessPx = 10;
const double kSnapRealWallTopJunctionY = 200;
const double kSnapRealWallBottomJunctionY = 560;

/// 사용자가 제시한 Vision hint(정규화 좌표) — 실제 벽보다 x는 오른쪽으로
/// 치우치고, y는 위쪽 junction을 놓칠 만큼 짧게 잡혀 있다(의도적 오차).
const double kSnapVisionHintX = 0.61;
const double kSnapVisionHintStartYNorm = 0.39;
const double kSnapVisionHintEndYNorm = 0.94;

Uint8List buildSingleWallSnapImage() {
  final image = img.Image(width: kSnapImageWidth, height: kSnapImageHeight);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  final black = img.ColorRgb8(20, 20, 20);
  final gray = img.ColorRgb8(120, 120, 120);

  void rect(double x1, double y1, double x2, double y2, img.Color color) {
    img.fillRect(image, x1: x1.round(), y1: y1.round(), x2: x2.round(), y2: y2.round(), color: color);
  }

  // 상단 가로 벽 (T-junction 생성) — 거실/침실2 위쪽 경계.
  rect(40, kSnapRealWallTopJunctionY - 5, 760, kSnapRealWallTopJunctionY + 5, black);
  // 하단 외벽 (T-junction 생성).
  rect(40, kSnapRealWallBottomJunctionY - 5, 760, kSnapRealWallBottomJunctionY + 5, black);
  // 좌/우 외벽.
  rect(35, kSnapRealWallTopJunctionY, 45, kSnapRealWallBottomJunctionY, black);
  rect(755, kSnapRealWallTopJunctionY, 765, kSnapRealWallBottomJunctionY, black);

  // 실제 테스트 대상: 거실|침실2 사이 세로 내부벽.
  rect(
    kSnapRealWallLeftEdgeX,
    kSnapRealWallTopJunctionY,
    kSnapRealWallRightEdgeX,
    kSnapRealWallBottomJunctionY,
    black,
  );

  // 방해 요소 1: 벽 바로 왼쪽(거실 쪽)의 가구(옷장 등) — 벽과 비슷한
  // 명도지만 세로로 짧고 훨씬 두껍다(진짜 벽과는 다른 run 패턴).
  rect(410, 260, 452, 340, gray);

  // 방해 요소 2: 벽 바로 오른쪽(침실2 쪽) 텍스트 라벨을 흉내낸 작은
  // 어두운 점/획들 — 벽처럼 이어지지 않는 짧은 조각들.
  for (var i = 0; i < 5; i++) {
    rect(475 + i * 8.0, 420, 480 + i * 8.0, 434, gray);
  }

  // 방해 요소 3: 벽과 평행하지만 훨씬 짧은 별도 어두운 세로선(그림자나
  // 걸레받이 이음선 등을 흉내냄) — 진짜 벽보다 짧게.
  rect(468, 300, 472, 360, gray);

  return Uint8List.fromList(img.encodePng(image));
}
