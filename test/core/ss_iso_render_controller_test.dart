// SS015 — SsIsoRenderController 단위 테스트: 단계가 순서대로 진행되고 완료되면 결과를 돌려주는지,
// 실패해도 재시도할 수 있고 재시도 한도를 넘으면 더 이상 재시도할 수 없는지, 입력 자체가 문제면
// 재시도 대상이 아닌지, 이미 처리 중일 때 start()를 다시 불러도 새 요청을 만들지 않는지(중복
// 렌더링 요청 방지) 확인한다.
import 'dart:async';

import 'package:ason_space/core/ss_ai_task.dart';
import 'package:ason_space/core/ss_iso_render_controller.dart';
import 'package:ason_space/core/ss_iso_render_step.dart';
import 'package:ason_space/models/iso_render_result.dart';
import 'package:ason_space/models/space_scene_v2.dart';
import 'package:ason_space/models/ss_iso_camera_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

const _camera = SsIsoCameraState(targetXMm: 0, targetYMm: 0, targetZMm: 0, distanceMm: 5000, azimuthRadians: 0.1, polarRadians: 0.2);
// SpaceSceneV2의 minBounds/maxBounds는 Vector3(vector_math_64) — Vector3는 const 생성자가 없으므로
// 이 값은 const로 만들 수 없다(기존 SpaceSceneV2 선언 그대로, lib/models/space_scene_v2.dart 참고).
final _emptyScene = SpaceSceneV2(
  wallMeshes: const [],
  floorMeshes: const [],
  openings: const [],
  minBounds: Vector3.zero(),
  maxBounds: Vector3.zero(),
  warnings: const [],
);

void main() {
  test('렌더링 단계가 순서대로 진행되고 완료되면 결과를 돌려준다', () async {
    final controller = SsIsoRenderController();
    final seenSteps = <SsIsoRenderStep>[];

    final status = await controller.start((onStep) async {
      for (final step in SsIsoRenderStep.values) {
        onStep(step);
        seenSteps.add(step);
      }
      return IsoRenderResult(scene: _emptyScene, camera: _camera);
    });

    expect(status, SsAiStatus.completed);
    expect(seenSteps, SsIsoRenderStep.values);
    expect(controller.completedSteps, SsIsoRenderStep.values);
    expect(controller.currentStep, isNull);
    expect(controller.progress, 1.0);
    expect(controller.task.lastGoodResult?.camera, _camera);
  });

  test('실패해도 다시 시도할 수 있고, 재시도가 성공하면 완료된다', () async {
    final controller = SsIsoRenderController();
    var attempt = 0;
    Future<IsoRenderResult> call(void Function(SsIsoRenderStep) onStep) async {
      attempt++;
      onStep(SsIsoRenderStep.imageQualityProcessing);
      if (attempt == 1) throw Exception('렌더링 실패(시험)');
      return IsoRenderResult(scene: _emptyScene, camera: _camera);
    }

    final first = await controller.start(call);
    expect(first, SsAiStatus.retryable);
    expect(controller.task.canRetry, isTrue);

    final second = await controller.retry();
    expect(second, SsAiStatus.completed);
    expect(controller.task.lastGoodResult?.camera, _camera);
  });

  test('재시도 횟수를 넘으면 실패로 끝나고 더 재시도할 수 없다', () async {
    final controller = SsIsoRenderController();
    var status = await controller.start((onStep) async {
      onStep(SsIsoRenderStep.imageQualityProcessing);
      throw Exception('항상 실패(시험)');
    });
    while (controller.task.canRetry) {
      status = await controller.retry();
    }
    expect(status, SsAiStatus.failed);
    expect(controller.task.canRetry, isFalse);
  });

  test('입력 자체가 문제면 재시도 대상이 아니다(일반 실패와 구분)', () async {
    final controller = SsIsoRenderController();
    final status = await controller.start((onStep) async {
      onStep(SsIsoRenderStep.imageQualityProcessing);
      throw const IsoRenderInputError('테스트: 렌더링할 디자인이 없습니다.');
    });
    expect(status, SsAiStatus.inputFixNeeded);
    expect(controller.task.canRetry, isFalse);
  });

  test('이미 처리 중이면 start()를 다시 불러도 새 요청을 만들지 않는다(중복 렌더링 요청 방지)', () async {
    final controller = SsIsoRenderController();
    var callCount = 0;
    final completer = Completer<IsoRenderResult>();

    Future<IsoRenderResult> call(void Function(SsIsoRenderStep) onStep) {
      callCount++;
      onStep(SsIsoRenderStep.imageQualityProcessing);
      return completer.future;
    }

    final firstFuture = controller.start(call);
    // 아직 첫 요청이 끝나지 않은 동안(processing) 다시 start()를 불러도 두 번째 렌더 호출이 생기지
    // 않아야 한다 — 실제 렌더 엔진/API를 쓸 때 중복 호출을 막기 위함.
    final secondStatus = await controller.start(call);
    expect(secondStatus, SsAiStatus.processing);
    expect(callCount, 1, reason: '처리 중에는 렌더 호출이 다시 일어나지 않아야 한다');

    completer.complete(IsoRenderResult(scene: _emptyScene, camera: _camera));
    final firstStatus = await firstFuture;
    expect(firstStatus, SsAiStatus.completed);
  });
}
