import 'package:flutter/foundation.dart';

import 'region_selection.dart';
import 'work_area.dart';

/// 공간 작업실에서 완성한 "부위 하나에 대한 작업 지시" 하나를 나타내는 불변 모델.
///
/// 사용자는 하나의 공간 사진 안에서 여러 부위(벽/천장/바닥 등)에 대해
/// 이 모델을 여러 개 만들 수 있다. [AiGenerationRequest.workInstructions]에
/// 담겨 AI 서비스로 전달된다.
@immutable
class WorkInstruction {
  const WorkInstruction({
    required this.id,
    required this.area,
    this.selection,
    required this.instructionText,
    this.referenceImages = const [],
  });

  /// 작업 목록에서 항목을 구분하기 위한 고유 ID.
  final String id;

  /// 이 작업 지시가 대상으로 하는 부위(벽/천장/바닥 등).
  final WorkArea area;

  /// 이미지 위에서 사용자가 지정한 부분 선택 영역.
  /// 특정 영역을 지정하지 않고 부위 전체(또는 기타 요청)에 대한 지시라면 null일 수 있다.
  final RegionSelection? selection;

  /// "선택한 벽 부분을 어떻게 바꾸고 싶으세요?" 같은 질문에 대한 사용자 답변.
  final String instructionText;

  /// 사용자가 첨부한 참고 이미지들.
  final List<Uint8List> referenceImages;

  WorkInstruction copyWith({
    String? id,
    WorkArea? area,
    RegionSelection? selection,
    bool clearSelection = false,
    String? instructionText,
    List<Uint8List>? referenceImages,
  }) {
    return WorkInstruction(
      id: id ?? this.id,
      area: area ?? this.area,
      selection: clearSelection ? null : (selection ?? this.selection),
      instructionText: instructionText ?? this.instructionText,
      referenceImages: referenceImages ?? this.referenceImages,
    );
  }

  @override
  String toString() =>
      'WorkInstruction(id: $id, area: ${area.label}, selection: $selection, '
      'instructionText: $instructionText, referenceImages: ${referenceImages.length})';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WorkInstruction &&
        other.id == id &&
        other.area == area &&
        other.selection == selection &&
        other.instructionText == instructionText &&
        listEquals(other.referenceImages, referenceImages);
  }

  @override
  int get hashCode => Object.hash(
    id,
    area,
    selection,
    instructionText,
    referenceImages.length,
  );
}
