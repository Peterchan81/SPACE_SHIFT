// SettingsScreen(MASTER 공통 "설정" 화면)에 대한 위젯 테스트.
//
// 1. 현재 설치된 앱 버전 정보(PackageInfo)가 표시된다.
// 2. 앱 업데이트 섹션이 AppUpdateStore 상태에 따라 올바르게 반응한다 —
//    idle(확인 전) / 업데이트 확인 → updateAvailable / upToDate / error.
// 3. updateAvailable일 때 "업데이트" 버튼이 실제 다운로드를 트리거한다.
//
// 새 확인/다운로드 로직을 만들지 않고 기존 AppUpdateStore/AppUpdateService를
// 그대로 재사용하므로, app_update_store_test.dart와 같은 Fake 패턴으로
// 네트워크/플랫폼 채널 없이 상태 전이를 검증한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:ason_space/models/app_update_info.dart';
import 'package:ason_space/screens/settings_screen.dart';
import 'package:ason_space/services/app_update_service.dart';
import 'package:ason_space/services/app_update_store.dart';

class _FakeAppUpdateService implements AppUpdateService {
  _FakeAppUpdateService({this.checkResult, this.downloadedPath});

  AppUpdateCheck? checkResult;
  String? downloadedPath;
  int downloadApkCallCount = 0;
  int openForInstallCallCount = 0;

  @override
  Future<AppUpdateCheck> checkForUpdate() async =>
      checkResult ??
      const AppUpdateCheck(
        result: AppUpdateCheckResult.error,
        errorMessage: 'not configured',
        currentVersionName: '0.0.0',
        currentVersionCode: 0,
      );

  @override
  Future<String?> downloadApk(
    AppUpdateInfo info, {
    void Function(int received, int? total)? onProgress,
  }) async {
    downloadApkCallCount++;
    onProgress?.call(1024, 1024);
    return downloadedPath;
  }

  @override
  Future<bool> openForInstall(String filePath) async {
    openForInstallCallCount++;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'SPACE SHIFT',
      packageName: 'com.example.ason_space',
      version: '1.0.0',
      buildNumber: '2015',
      buildSignature: '',
    );
  });

  Future<void> pumpSettings(WidgetTester tester, AppUpdateStore store) async {
    await tester.pumpWidget(
      MaterialApp(home: SettingsScreen(updateStore: store)),
    );
    await tester.pump();
  }

  testWidgets('현재 설치된 앱 버전 정보(버전/빌드)가 표시된다', (tester) async {
    final store = AppUpdateStore.withService(_FakeAppUpdateService());
    await pumpSettings(tester, store);

    expect(find.text('SPACE SHIFT'), findsOneWidget);
    expect(find.text('1.0.0'), findsOneWidget);
    expect(find.text('2015'), findsOneWidget);
  });

  testWidgets('업데이트를 확인하지 않은 상태(idle)에서는 확인 버튼만 보인다', (tester) async {
    final store = AppUpdateStore.withService(_FakeAppUpdateService());
    await pumpSettings(tester, store);

    expect(find.text('아직 업데이트를 확인하지 않았습니다.'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '업데이트 확인'), findsOneWidget);
  });

  testWidgets('업데이트 확인 결과 최신 버전이면 "최신 버전을 사용 중입니다"를 보여준다', (tester) async {
    final fake = _FakeAppUpdateService(
      checkResult: const AppUpdateCheck(
        result: AppUpdateCheckResult.upToDate,
        currentVersionName: '1.0.0',
        currentVersionCode: 2016,
      ),
    );
    final store = AppUpdateStore.withService(fake);
    await pumpSettings(tester, store);

    await tester.tap(find.widgetWithText(OutlinedButton, '업데이트 확인'));
    await tester.pumpAndSettle();

    expect(find.text('최신 버전을 사용 중입니다.'), findsOneWidget);
  });

  testWidgets('업데이트 확인 결과 새 버전이 있으면 버전 정보와 업데이트 버튼을 보여준다', (tester) async {
    final fake = _FakeAppUpdateService(
      checkResult: const AppUpdateCheck(
        result: AppUpdateCheckResult.updateAvailable,
        info: AppUpdateInfo(
          versionName: '1.0.0',
          versionCode: 2017,
          apkUrl: 'https://example.supabase.co/space_shift.apk',
          releaseNotes: '',
        ),
        currentVersionName: '1.0.0',
        currentVersionCode: 2016,
      ),
    );
    final store = AppUpdateStore.withService(fake);
    await pumpSettings(tester, store);

    await tester.tap(find.widgetWithText(OutlinedButton, '업데이트 확인'));
    await tester.pumpAndSettle();

    expect(find.textContaining('새 업데이트가 있습니다'), findsOneWidget);
    expect(find.textContaining('2017'), findsWidgets);
    expect(find.widgetWithText(FilledButton, '업데이트'), findsOneWidget);
  });

  testWidgets('"업데이트" 버튼을 누르면 실제 다운로드/설치 호출로 이어진다', (tester) async {
    final fake = _FakeAppUpdateService(
      checkResult: const AppUpdateCheck(
        result: AppUpdateCheckResult.updateAvailable,
        info: AppUpdateInfo(
          versionName: '1.0.0',
          versionCode: 2017,
          apkUrl: 'https://example.supabase.co/space_shift.apk',
          releaseNotes: '',
        ),
        currentVersionName: '1.0.0',
        currentVersionCode: 2016,
      ),
      downloadedPath: '/tmp/space_shift.apk',
    );
    final store = AppUpdateStore.withService(fake);
    await pumpSettings(tester, store);

    await tester.tap(find.widgetWithText(OutlinedButton, '업데이트 확인'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '업데이트'));
    await tester.pumpAndSettle();

    expect(fake.downloadApkCallCount, 1);
    expect(fake.openForInstallCallCount, 1);
    expect(find.textContaining('설치 준비가 완료됐습니다'), findsOneWidget);
  });

  testWidgets('업데이트 확인이 실패하면 안전한 오류 메시지와 다시 시도 버튼을 보여준다', (tester) async {
    final fake = _FakeAppUpdateService(
      checkResult: const AppUpdateCheck(
        result: AppUpdateCheckResult.error,
        errorMessage: '업데이트 서버 응답이 없습니다 — 네트워크 연결을 확인해 주세요.',
        currentVersionName: '1.0.0',
        currentVersionCode: 2016,
      ),
    );
    final store = AppUpdateStore.withService(fake);
    await pumpSettings(tester, store);

    await tester.tap(find.widgetWithText(OutlinedButton, '업데이트 확인'));
    await tester.pumpAndSettle();

    expect(find.textContaining('네트워크 연결을 확인'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '다시 시도'), findsOneWidget);
  });
}
