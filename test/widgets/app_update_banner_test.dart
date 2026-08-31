import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ason_space/models/app_update_view.dart';
import 'package:ason_space/services/app_update_store.dart';
import 'package:ason_space/widgets/app_update_banner.dart';

void main() {
  testWidgets('숨김 상태(isVisible=false)면 아무것도 렌더링하지 않는다', (tester) async {
    final view = AppUpdateViewState.of(state: AppUpdateState.upToDate);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppUpdateBanner(view: view, onInstall: () {}),
        ),
      ),
    );

    expect(find.byType(AppUpdateBanner), findsOneWidget);
    expect(find.text('업데이트'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('updateAvailable이면 문구와 업데이트 버튼이 보이고 탭하면 콜백이 호출된다', (
    tester,
  ) async {
    var installTapped = false;
    final view = AppUpdateViewState.of(
      state: AppUpdateState.updateAvailable,
      versionName: '1.0.1',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppUpdateBanner(
            view: view,
            onInstall: () => installTapped = true,
          ),
        ),
      ),
    );

    expect(find.textContaining('1.0.1'), findsOneWidget);
    expect(find.text('업데이트'), findsOneWidget);

    await tester.tap(find.text('업데이트'));
    await tester.pump();

    expect(installTapped, isTrue);
  });

  testWidgets('downloading이면 업데이트 버튼 대신 진행 표시가 보인다', (tester) async {
    final view = AppUpdateViewState.of(state: AppUpdateState.downloading);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppUpdateBanner(view: view, onInstall: () {}),
        ),
      ),
    );

    expect(find.text('업데이트'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
