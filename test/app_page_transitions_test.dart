// SS-BUG-001 회귀 테스트 — Windows에서 3D 화면(외부 텍스처)이 있는 페이지를
// 덮거나 닫을 때 기본 Zoom 페이지 전환이 그 화면을 스냅샷하면서
// flutter_windows.dll 안에서 access violation이 나 앱이 꺼지던 문제를 막기
// 위해, AsonSpaceApp의 테마가 Windows/Android에 대해
// allowSnapshotting: false인 ZoomPageTransitionsBuilder를 쓰는지 확인한다.
//
// GPU 3D 뷰(Space3DViewGpuV2)는 실제 네이티브 ANGLE 텍스처가 있어야 crash가
// 재현되므로 위젯 테스트에는 띄우지 않는다 — 여기서는 테마 설정값만 검사한다.
import 'package:ason_space/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'AsonSpaceApp disables page-transition snapshotting on windows/android/linux/macOS',
    (tester) async {
      await tester.pumpWidget(const AsonSpaceApp());
      // bootstrap()이 끝나지 않은 초기 로딩 프레임이라도 MaterialApp의 theme은
      // 이미 구성되어 있으므로 추가로 pump할 필요가 없다.

      final materialApp = tester.widget<MaterialApp>(
        find.byType(MaterialApp),
      );
      final pageTransitionsTheme = materialApp.theme?.pageTransitionsTheme;
      expect(pageTransitionsTheme, isNotNull);

      final builders = pageTransitionsTheme!.builders;

      final windowsBuilder = builders[TargetPlatform.windows];
      expect(windowsBuilder, isA<ZoomPageTransitionsBuilder>());
      expect(
        (windowsBuilder as ZoomPageTransitionsBuilder).allowSnapshotting,
        isFalse,
      );

      final androidBuilder = builders[TargetPlatform.android];
      expect(androidBuilder, isA<ZoomPageTransitionsBuilder>());
      expect(
        (androidBuilder as ZoomPageTransitionsBuilder).allowSnapshotting,
        isFalse,
      );
    },
  );
}
