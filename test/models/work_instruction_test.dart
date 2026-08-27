// WorkInstruction 모델에 대한 단위 테스트.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/region_selection.dart';
import 'package:ason_space/models/work_area.dart';
import 'package:ason_space/models/work_instruction.dart';

void main() {
  const selection = RegionSelection(x: 0.1, y: 0.2, width: 0.3, height: 0.4);

  test('생성자로 전달한 값이 그대로 필드에 저장된다', () {
    final instruction = WorkInstruction(
      id: 'work_1',
      area: WorkArea.wall,
      selection: selection,
      instructionText: '좌측 벽을 아이보리 컬러로 변경해주세요.',
      referenceImages: [Uint8List.fromList([1, 2, 3])],
    );

    expect(instruction.id, 'work_1');
    expect(instruction.area, WorkArea.wall);
    expect(instruction.selection, selection);
    expect(instruction.instructionText, '좌측 벽을 아이보리 컬러로 변경해주세요.');
    expect(instruction.referenceImages, hasLength(1));
  });

  test('selection과 referenceImages는 생략할 수 있다', () {
    const instruction = WorkInstruction(
      id: 'work_1',
      area: WorkArea.other,
      instructionText: '기타 요청',
    );

    expect(instruction.selection, isNull);
    expect(instruction.referenceImages, isEmpty);
  });

  test('copyWith(clearSelection: true)는 선택 영역만 비운다', () {
    final instruction = WorkInstruction(
      id: 'work_1',
      area: WorkArea.wall,
      selection: selection,
      instructionText: '지시문',
    );

    final cleared = instruction.copyWith(clearSelection: true);

    expect(cleared.selection, isNull);
    expect(cleared.area, WorkArea.wall);
    expect(cleared.instructionText, '지시문');
  });

  test('WorkArea.instructionQuestion은 부위 이름을 포함한 자연스러운 질문을 만든다', () {
    expect(WorkArea.wall.instructionQuestion, contains('벽'));
    expect(WorkArea.ceiling.instructionQuestion, contains('천장'));
    expect(WorkArea.floor.instructionQuestion, contains('바닥'));
  });

  test('같은 값을 가진 두 작업 지시는 ==가 동일하다', () {
    const a = WorkInstruction(id: 'a', area: WorkArea.wall, instructionText: '텍스트');
    const b = WorkInstruction(id: 'a', area: WorkArea.wall, instructionText: '텍스트');

    expect(a, equals(b));
  });
}
