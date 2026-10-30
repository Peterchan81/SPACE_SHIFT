// SS007 — SsImageRenderController 단위 테스트: 단계가 순서대로 진행되고 완료되면 결과를 돌려주는지,
// 실패해도 재시도할 수 있고 재시도 한도를 넘으면 더 이상 재시도할 수 없는지 확인한다.
import 'dart:typed_data';

import 'package:ason_space/core/ss_ai_task.dart';
import 'package:ason_space/core/ss_image_render_controller.dart';
import 'package:ason_space/core/ss_render_step.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('렌더링 단계가 순서대로 진행되고 완료되면 결과를 돌려준다', () async {
    final controller = SsImageRenderController();
    final seenSteps = <SsRenderStep>[];

    final status = await controller.start((onStep) async {
      for (final step in SsRenderStep.values) {
        onStep(step);
        seenSteps.add(step);
      }
      return Uint8List.fromList([1, 2, 3]);
    });

    expect(status, SsAiStatus.completed);
    expect(seenSteps, SsRenderStep.values);
    expect(controller.completedSteps, SsRenderStep.values);
    expect(controller.currentStep, isNull);
    expect(controller.progress, 1.0);
    expect(controller.task.lastGoodResult, [1, 2, 3]);
  });

  test('실패해도 다시 시도할 수 있고, 재시도가 성공하면 완료된다', () async {
    final controller = SsImageRenderController();
    var attempt = 0;
    Future<Uint8List> call(void Function(SsRenderStep) onStep) async {
      attempt++;
      onStep(SsRenderStep.analyzingImage);
      if (attempt == 1) throw Exception('렌더링 실패(시험)');
      return Uint8List.fromList([9]);
    }

    final first = await controller.start(call);
    expect(first, SsAiStatus.retryable);
    expect(controller.task.canRetry, isTrue);

    final second = await controller.retry();
    expect(second, SsAiStatus.completed);
    expect(controller.task.lastGoodResult, [9]);
  });

  test('재시도 횟수를 넘으면 실패로 끝나고 더 재시도할 수 없다', () async {
    final controller = SsImageRenderController();
    var status = await controller.start((onStep) async {
      onStep(SsRenderStep.analyzingImage);
      throw Exception('항상 실패(시험)');
    });
    while (controller.task.canRetry) {
      status = await controller.retry();
    }
    expect(status, SsAiStatus.failed);
    expect(controller.task.canRetry, isFalse);
  });
}
