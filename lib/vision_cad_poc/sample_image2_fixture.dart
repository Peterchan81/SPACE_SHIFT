import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Vision Guided CAD POC — "이미지 2"(그레이톤 아파트, 13개 명명 공간:
/// 드레스룸/주방·식당/발코니/부부거실/욕실2/펜트리/현관/욕실1/실외기실/
/// 안방/거실/침실2/침실1) 재현용 합성 평면도.
///
/// 정직한 고지: 실제 사용자가 채팅에 첨부한 원본 이미지 파일은 이
/// 저장소에 존재하지 않는다(채팅 첨부 이미지의 원본 바이트를 이
/// 세션의 파일시스템 도구로 추출할 방법이 없다). 그렇다고 최종 CAD
/// 좌표를 손으로 확정해 넣는 것(WO 절대 금지 1번)은 이 POC의 목적
/// 자체를 무너뜨린다 — 그래서 이전 turn에서 직접 육안으로 분석한
/// "이미지 2"의 실제 구조(외곽 형태 — 상단 발코니 돌출 + 좌하단
/// 실외기실 돌출, 13개 방 배치, 문 위치)를 최대한 충실히 재현한
/// 합성 픽셀 이미지를 만들고, 이 파이프라인의 모든 단계(Vision hint
/// 매칭 → geometry 정밀화 → topology 검증)가 이 이미지의 **실제
/// 픽셀**에 대해 진짜로 동작하게 한다 — 이 세션에서 지금까지 모든
/// CV 관련 테스트가 써 온 것과 동일한 방법론이다(실사용자 파일을
/// 무단으로 갖고 있지 않으면서도 하드코딩 없이 알고리즘을 검증).
///
/// 캔버스 900x650px, 벽 두께 8px.
const int kImage2Width = 900;
const int kImage2Height = 650;
const int kImage2WallThickness = 8;

class RoomBox {
  const RoomBox(this.label, this.left, this.top, this.right, this.bottom);
  final String label;
  final double left;
  final double top;
  final double right;
  final double bottom;
}

/// 13개 방의 실제 픽셀 bounding box — Mock Vision hint와 geometry
/// extractor 테스트가 "실제 이 이미지에서 이 방이 어디 있는가"를
/// 참조하는 단일 진실 소스다(하드코딩된 CAD 좌표가 아니라, 그림을
/// 그리는 데 쓰인 동일한 좌표를 재사용할 뿐이다).
const Map<String, RoomBox> image2Rooms = {
  'balcony': RoomBox('발코니', 380, 60, 620, 110),
  'masterBedroom': RoomBox('안방', 60, 110, 280, 320),
  'dressRoom': RoomBox('드레스룸', 280, 110, 380, 190),
  'masterLiving': RoomBox('부부거실', 280, 190, 380, 320),
  'kitchenDining': RoomBox('주방/식당', 380, 110, 620, 320),
  'pantry': RoomBox('펜트리', 620, 110, 700, 220),
  'bath1': RoomBox('욕실1', 620, 220, 700, 320),
  'entrance': RoomBox('현관', 700, 110, 840, 320),
  'living': RoomBox('거실', 60, 320, 380, 540),
  'bath2': RoomBox('욕실2', 380, 320, 460, 540),
  'bedroom2': RoomBox('침실2', 460, 320, 620, 540),
  'bedroom1': RoomBox('침실1', 620, 320, 840, 540),
  'mechanical': RoomBox('실외기실', 100, 540, 200, 590),
};

/// 건물 외곽(Envelope) — 발코니 돌출(위) + 실외기실 돌출(좌하단)을
/// 포함한 비정형 폐곡선. [image2Rooms]의 bounding box들과 일관되게
/// 맞물리도록 같은 좌표를 재사용한다.
const List<({double x, double y})> image2Envelope = [
  (x: 60, y: 110),
  (x: 380, y: 110),
  (x: 380, y: 60),
  (x: 620, y: 60),
  (x: 620, y: 110),
  (x: 840, y: 110),
  (x: 840, y: 540),
  (x: 200, y: 540),
  (x: 200, y: 590),
  (x: 100, y: 590),
  (x: 100, y: 540),
  (x: 60, y: 540),
];

/// 이미지 2의 픽셀 bytes(PNG)를 만든다. 외벽/내벽은 검은 실선, 문
/// 위치에는 벽에 실제 gap을 남겨(기존 저수준 엔진의 gap 기반 opening
/// 검출과 동일한 원리로 검증 가능하게) 둔다.
Uint8List buildImage2Png() {
  final image = img.Image(width: kImage2Width, height: kImage2Height);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  final black = img.ColorRgb8(0, 0, 0);
  const t = kImage2WallThickness / 2;

  void wall(double x1, double y1, double x2, double y2) {
    img.fillRect(
      image,
      x1: (x1 - t).round(),
      y1: (y1 - t).round(),
      x2: (x2 + t).round(),
      y2: (y2 + t).round(),
      color: black,
    );
  }

  /// [gapStart]~[gapEnd] 구간만 비워 문을 남긴다(수평 벽 전용).
  void wallWithHorizontalGap(double x1, double y, double x2, double gapStart, double gapEnd) {
    wall(x1, y, gapStart, y);
    wall(gapEnd, y, x2, y);
  }

  void wallWithVerticalGap(double x, double y1, double y2, double gapStart, double gapEnd) {
    wall(x, y1, x, gapStart);
    wall(x, gapEnd, x, y2);
  }

  // ---- 외곽(Envelope) ----
  wall(60, 110, 380, 110); // E1
  wall(380, 110, 380, 60); // E2
  wall(380, 60, 620, 60); // E3 발코니 바깥 상단
  wall(620, 60, 620, 110); // E4
  wall(620, 110, 840, 110); // E5
  wall(840, 110, 840, 540); // E6 우측 벽
  wall(840, 540, 200, 540); // E7 하단(우측)
  wall(200, 540, 200, 590); // E8 실외기실 우측
  wall(200, 590, 100, 590); // E9 실외기실 하단
  wall(100, 590, 100, 540); // E10 실외기실 좌측
  wall(100, 540, 60, 540); // E11 하단(좌측)
  wall(60, 540, 60, 110); // E12 좌측 벽

  // ---- 내벽 ----
  wall(380, 110, 620, 110); // 발코니 | 주방·식당
  wallWithVerticalGap(280, 110, 320, 150, 190); // 안방 | 드레스룸+부부거실(문)
  wall(280, 190, 380, 190); // 드레스룸 | 부부거실
  wall(620, 110, 620, 320); // 주방·식당 | 펜트리·욕실1
  wallWithVerticalGap(700, 110, 320, 150, 190); // 펜트리·욕실1 | 현관(문)
  wall(620, 220, 700, 220); // 펜트리 | 욕실1
  wallWithHorizontalGap(60, 320, 840, 150, 190); // 상/하 구역(안방→거실 문)
  wall(460, 320, 460, 540); // 욕실2 | 침실2
  wallWithVerticalGap(620, 320, 540, 400, 440); // 침실2 | 침실1(문)

  // 실외기실은 위쪽(거실 방향)이 원래 열려 있다 — 별도 문/벽 없음
  // (openPassage로 검증 대상).

  return Uint8List.fromList(img.encodePng(image));
}
