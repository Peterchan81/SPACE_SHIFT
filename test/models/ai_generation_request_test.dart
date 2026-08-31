// AiGenerationRequest 모델에 대한 단위 테스트.
//
// 1. 생성자로 값이 올바르게 설정되는지 확인한다. (Request 생성 테스트)
// 2. copyWith가 지정한 필드만 바꾸는지 확인한다.
// 3. 같은 값을 가진 두 인스턴스가 ==/hashCode로 동등하게 취급되는지,
//    toString에 주요 정보가 포함되는지 확인한다.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/models/ai_generation_request.dart';
import 'package:ason_space/models/space_task.dart';

void main() {
  final imageBytes = Uint8List.fromList([1, 2, 3, 4]);
  final createdAt = DateTime(2026, 1, 1, 12, 0);

  AiGenerationRequest buildRequest({
    Uint8List? imageBytes,
    String selectedStyle = '모던',
    DateTime? createdAt,
    String appVersion = '1.0.0',
  }) {
    return AiGenerationRequest(
      imageBytes: imageBytes ?? Uint8List.fromList([1, 2, 3, 4]),
      selectedStyle: selectedStyle,
      createdAt: createdAt ?? DateTime(2026, 1, 1, 12, 0),
      appVersion: appVersion,
    );
  }

  test('생성자로 전달한 값이 그대로 필드에 저장된다', () {
    final request = AiGenerationRequest(
      imageBytes: imageBytes,
      selectedStyle: '모던',
      createdAt: createdAt,
      appVersion: '1.0.0',
    );

    expect(request.imageBytes, imageBytes);
    expect(request.selectedStyle, '모던');
    expect(request.createdAt, createdAt);
    expect(request.appVersion, '1.0.0');
  });

  test('copyWith은 지정한 필드만 바꾸고 나머지는 유지한다', () {
    final original = buildRequest();

    final updated = original.copyWith(selectedStyle: '북유럽');

    expect(updated.selectedStyle, '북유럽');
    expect(updated.imageBytes, original.imageBytes);
    expect(updated.createdAt, original.createdAt);
    expect(updated.appVersion, original.appVersion);
  });

  test('같은 값을 가진 두 요청은 ==와 hashCode가 동일하다', () {
    final a = buildRequest();
    final b = buildRequest();

    expect(a, equals(b));
    expect(a.hashCode, equals(b.hashCode));
  });

  test('다른 스타일을 가진 요청은 동등하지 않다', () {
    final a = buildRequest(selectedStyle: '모던');
    final b = buildRequest(selectedStyle: '북유럽');

    expect(a, isNot(equals(b)));
  });

  test('toString에 스타일과 앱 버전 정보가 포함된다', () {
    final request = buildRequest();

    expect(request.toString(), contains('모던'));
    expect(request.toString(), contains('1.0.0'));
  });

  test('tasks를 지정하지 않으면 빈 목록이 기본값이다', () {
    final request = buildRequest();

    expect(request.tasks, isEmpty);
  });

  test('공간 작업실에서 등록한 작업 목록을 tasks로 전달할 수 있다', () {
    const tasks = [
      SpaceTask(
        id: 'task_1',
        category: SpaceCategory.wall,
        rect: NormalizedRect(left: 0.1, top: 0.1, width: 0.3, height: 0.4),
        instruction: '벽을 아이보리로 변경해줘',
      ),
    ];

    final request = AiGenerationRequest(
      imageBytes: imageBytes,
      selectedStyle: '벽: 벽을 아이보리로 변경해줘',
      createdAt: createdAt,
      appVersion: '1.0.0',
      tasks: tasks,
    );

    expect(request.tasks, tasks);
    expect(request.copyWith().tasks, tasks);
  });
}
