// WorkspaceTaskItem/관련 enum·헬퍼에 대한 단위 테스트.
//
// 1. copyWith이 지정한 필드만 바꾸고 나머지(id/number/markerPosition 등)는
//    그대로 유지하는지 확인한다.
// 2. workspaceMarkerColorFor가 번호에 따라 무지개색을 순환시키는지 확인한다.
// 3. 카테고리별 마감재 옵션 목록이 서로 다른지 확인한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/workspace_task_item.dart';

void main() {
  test('copyWith은 지정한 필드만 바꾸고 나머지는 유지한다', () {
    const task = WorkspaceTaskItem(
      id: 1,
      number: 1,
      name: '거실 벽',
      category: WorkspaceTaskCategory.wall,
      finishLabel: '벽지',
      color: Color(0xFFFFFFFF),
      markerPosition: Offset(0.2, 0.3),
      heightMm: 2700,
      widthMm: 3000,
      thicknessMm: 120,
    );

    final updated = task.copyWith(name: '거실 벽 (TV 벽체)', visible: false);

    expect(updated.name, '거실 벽 (TV 벽체)');
    expect(updated.visible, isFalse);
    expect(updated.id, task.id);
    expect(updated.number, task.number);
    expect(updated.markerPosition, task.markerPosition);
    expect(updated.finishLabel, task.finishLabel);
    expect(updated.color, task.color);
    expect(updated.locked, task.locked);
  });

  test('workspaceMarkerColorFor는 번호에 따라 무지개색을 순환시킨다', () {
    expect(workspaceMarkerColorFor(1), workspaceMarkerColors[0]);
    expect(workspaceMarkerColorFor(6), workspaceMarkerColors[5]);
    expect(workspaceMarkerColorFor(7), workspaceMarkerColors[0]);
    expect(workspaceMarkerColorFor(12), workspaceMarkerColors[5]);
  });

  test('카테고리별 마감재 옵션은 서로 다르며 사용자 선택을 포함한다', () {
    expect(
      WorkspaceTaskCategory.wall.finishOptions,
      isNot(equals(WorkspaceTaskCategory.floor.finishOptions)),
    );
    for (final category in WorkspaceTaskCategory.values) {
      expect(category.finishOptions, contains('사용자 선택'));
    }
  });
}
