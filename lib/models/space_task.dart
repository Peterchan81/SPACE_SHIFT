import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color, LinearGradient, Alignment;

/// 공간 작업실에서 사용자가 지정할 수 있는 작업 대상 카테고리.
///
/// 오른쪽 세로 Tool Panel에 이 순서 그대로 표시된다.
enum SpaceCategory {
  all,
  ceiling,
  wall,
  floor,
  window,
  lighting,
  furniture,
  door,
  etc,
}

/// [SpaceCategory]의 한글 표시 이름.
extension SpaceCategoryLabel on SpaceCategory {
  String get label {
    switch (this) {
      case SpaceCategory.all:
        return '전체';
      case SpaceCategory.ceiling:
        return '천장';
      case SpaceCategory.wall:
        return '벽';
      case SpaceCategory.floor:
        return '바닥';
      case SpaceCategory.window:
        return '창호';
      case SpaceCategory.lighting:
        return '조명';
      case SpaceCategory.furniture:
        return '가구';
      case SpaceCategory.door:
        return '문';
      case SpaceCategory.etc:
        return '기타';
    }
  }
}

/// 사진 위에서 선택한 영역을, 화면 크기나 사진 해상도와 무관하게 항상 같은
/// 위치를 가리키도록 0.0~1.0 범위로 정규화해 저장하는 좌표.
///
/// (left, top)이 좌상단 기준이며 width/height는 캔버스 전체 대비 비율이다.
@immutable
class NormalizedRect {
  const NormalizedRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;

  /// 0.0~1.0 정규화 좌표 공간 안의 한 점이 이 영역 내부에 있는지 확인한다.
  bool contains(double dx, double dy) {
    return dx >= left && dx <= right && dy >= top && dy <= bottom;
  }

  /// 전체 사진 대비 가로/세로 비율을 사람이 읽기 쉬운 문구로 요약한다.
  /// 예: "가로 34% · 세로 50%"
  String get sizeSummary =>
      '가로 ${(width * 100).round()}% · 세로 ${(height * 100).round()}%';

  NormalizedRect copyWith({
    double? left,
    double? top,
    double? width,
    double? height,
  }) {
    return NormalizedRect(
      left: left ?? this.left,
      top: top ?? this.top,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NormalizedRect &&
        other.left == left &&
        other.top == top &&
        other.width == width &&
        other.height == height;
  }

  @override
  int get hashCode => Object.hash(left, top, width, height);
}

/// 공간 작업실에서 사용자가 등록한 작업 하나.
///
/// 선택 대상(카테고리), 선택 영역(정규화 좌표), 변경 내용 텍스트, 참고
/// 이미지를 함께 담아 AI 생성 요청과 결과 화면의 "변경 내용" 목록에서
/// 그대로 사용한다.
@immutable
class SpaceTask {
  const SpaceTask({
    required this.id,
    required this.category,
    required this.rect,
    this.instruction = '',
    this.referenceImageBytes,
  });

  /// 작업을 구분하는 고유 id. 수정/삭제 시 이 값으로 대상을 찾는다.
  final String id;

  final SpaceCategory category;

  final NormalizedRect rect;

  /// 사용자가 입력한 변경 지시 텍스트.
  /// 예: "좌측 벽을 밝은 아이보리 컬러로 변경하고 TV 뒤쪽은 밝은 우드 패널로 만들어줘."
  final String instruction;

  /// 변경 결과의 참고가 될 이미지. 선택 사항이다.
  final Uint8List? referenceImageBytes;

  SpaceTask copyWith({
    SpaceCategory? category,
    NormalizedRect? rect,
    String? instruction,
    Uint8List? referenceImageBytes,
    bool clearReferenceImage = false,
  }) {
    return SpaceTask(
      id: id,
      category: category ?? this.category,
      rect: rect ?? this.rect,
      instruction: instruction ?? this.instruction,
      referenceImageBytes: clearReferenceImage
          ? null
          : (referenceImageBytes ?? this.referenceImageBytes),
    );
  }

  /// 결과 화면의 "변경 내용" 목록 등에서 사용하는 한 줄 요약.
  String get summary => '${category.label}: $instruction';
}

/// 작업 카드/영역 강조 표시에 순환해서 사용하는 Rainbow Accent 팔레트.
/// White 배경 위에서 핵심 CTA와 선택 상태를 구분하는 용도로만 사용한다.
const List<Color> spaceRainbowPalette = [
  Color(0xFFEF5350),
  Color(0xFFFFA726),
  Color(0xFFFFD54F),
  Color(0xFF66BB6A),
  Color(0xFF42A5F5),
  Color(0xFFAB47BC),
];

/// 핵심 CTA(공간의 변화 만들기)와 선택된 Tool Panel 항목에 사용하는
/// Rainbow Accent 그라디언트.
const LinearGradient spaceRainbowGradient = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: spaceRainbowPalette,
);
