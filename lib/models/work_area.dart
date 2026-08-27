import 'package:flutter/material.dart';

/// 공간 작업실에서 사용자가 변경하고 싶은 부위를 나타내는 종류.
///
/// MASTER UI(SS_V1_UI_MASTER.png) 4번 화면의 "작업 부위 선택" 패널과
/// 1:1로 대응한다.
enum WorkArea { entire, ceiling, wall, floor, window, lighting, furniture, door, other }

/// [WorkArea]에 대한 표시용 정보(이름/아이콘/질문 문구)를 제공하는 확장.
extension WorkAreaX on WorkArea {
  /// 패널/칩 등에 표시할 한글 이름.
  String get label {
    switch (this) {
      case WorkArea.entire:
        return '전체';
      case WorkArea.ceiling:
        return '천장';
      case WorkArea.wall:
        return '벽';
      case WorkArea.floor:
        return '바닥';
      case WorkArea.window:
        return '창호';
      case WorkArea.lighting:
        return '조명';
      case WorkArea.furniture:
        return '가구';
      case WorkArea.door:
        return '문';
      case WorkArea.other:
        return '기타';
    }
  }

  /// 작업 부위 패널에 표시할 아이콘.
  IconData get icon {
    switch (this) {
      case WorkArea.entire:
        return Icons.crop_free_rounded;
      case WorkArea.ceiling:
        return Icons.horizontal_rule_rounded;
      case WorkArea.wall:
        return Icons.view_agenda_outlined;
      case WorkArea.floor:
        return Icons.layers_outlined;
      case WorkArea.window:
        return Icons.window_outlined;
      case WorkArea.lighting:
        return Icons.lightbulb_outline_rounded;
      case WorkArea.furniture:
        return Icons.chair_outlined;
      case WorkArea.door:
        return Icons.sensor_door_outlined;
      case WorkArea.other:
        return Icons.more_horiz_rounded;
    }
  }

  /// 선택한 부위에 맞춰 자연스럽게 바뀌는 작업 지시 질문 문구.
  /// 예: "선택한 벽 부분을 어떻게 바꾸고 싶으세요?"
  String get instructionQuestion => '선택한 $label 부분을 어떻게 바꾸고 싶으세요?';
}
