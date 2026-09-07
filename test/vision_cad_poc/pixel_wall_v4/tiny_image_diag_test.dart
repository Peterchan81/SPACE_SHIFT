// WO084/085 — production 화면([FloorPlanWorkspaceScreen._startAnalysis])이
// 이제 [runPixelWallPipeline]을 isolate 없이 메인 스레드에서 직접 호출한다
// (compute()의 실제 Isolate.spawn이 위젯 테스트의 fake-async 존과 맞물려
// 절대 끝나지 않는 대기를 만드는 문제가 있었다). 그 전제 — 아주 작거나
// 퇴화된 이미지에서도 빠르게(블로킹 없이) 빈 결과로 안전하게 끝나야 한다 —
// 를 회귀로 고정한다.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:ason_space/vision_cad_poc/pixel_wall_v4/pixel_wall_pipeline.dart';

final _fakeImageBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
  '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

void main() {
  test(
    '1x1 퇴화 이미지 — runPixelWallPipeline이 즉시(블로킹 없이) 빈 geometry로 끝난다',
    () {
      final sw = Stopwatch()..start();
      final result = runPixelWallPipeline(imageBytes: _fakeImageBytes);
      sw.stop();

      expect(sw.elapsedMilliseconds, lessThan(2000));
      expect(result.model.walls, isEmpty);
      expect(result.model.spaces, isEmpty);
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );
}
