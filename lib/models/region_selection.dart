import 'package:flutter/foundation.dart';

/// 이미지 위에서 사용자가 지정한 부분 선택 영역을 나타내는 불변 모델.
///
/// 화면 픽셀 크기에 종속되지 않도록 [x], [y], [width], [height]를 모두
/// 0.0 ~ 1.0 사이의 정규화된(normalized) 좌표로 저장한다. 이렇게 하면
/// 화면 크기(웹/태블릿/폰)가 달라져도 동일한 상대 위치를 복원할 수 있다.
@immutable
class RegionSelection {
  const RegionSelection({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  /// 선택 영역 좌측 상단의 정규화된 X 좌표 (0.0 ~ 1.0).
  final double x;

  /// 선택 영역 좌측 상단의 정규화된 Y 좌표 (0.0 ~ 1.0).
  final double y;

  /// 선택 영역의 정규화된 너비 (0.0 ~ 1.0).
  final double width;

  /// 선택 영역의 정규화된 높이 (0.0 ~ 1.0).
  final double height;

  /// 사용자에게 보여주기 위한 간결한 백분율 표현 (예: 42).
  int get xPercent => (x * 100).round();
  int get yPercent => (y * 100).round();
  int get widthPercent => (width * 100).round();
  int get heightPercent => (height * 100).round();

  RegionSelection copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
  }) {
    return RegionSelection(
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  /// AI 요청 등 외부로 전달할 때 사용할 순수 데이터 형태.
  Map<String, double> toMap() => {
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };

  @override
  String toString() =>
      'RegionSelection(x: $x, y: $y, width: $width, height: $height)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RegionSelection &&
        other.x == x &&
        other.y == y &&
        other.width == width &&
        other.height == height;
  }

  @override
  int get hashCode => Object.hash(x, y, width, height);
}
