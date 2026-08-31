import 'package:flutter_test/flutter_test.dart';
import 'package:ason_space/models/app_update_info.dart';
import 'package:ason_space/services/app_update_service.dart';
import 'package:ason_space/services/app_update_store.dart';

/// 실제 네트워크/플랫폼 채널(http, PackageInfo, open_filex) 대신 미리 정한
/// 결과를 내보내는 Fake로 [AppUpdateStore]의 상태 전이만 검증한다.
class _FakeAppUpdateService implements AppUpdateService {
  _FakeAppUpdateService({this.checkResult, this.downloadedPath});

  AppUpdateCheck? checkResult;
  String? downloadedPath;
  int openForInstallCallCount = 0;
  String? lastOpenedPath;

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
    onProgress?.call(512, 1024);
    onProgress?.call(1024, 1024);
    return downloadedPath;
  }

  @override
  Future<bool> openForInstall(String filePath) async {
    openForInstallCallCount++;
    lastOpenedPath = filePath;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppUpdateStore.checkForUpdate', () {
    test('새 버전이 있으면 updateAvailable 상태와 정보를 반영한다', () async {
      final fake = _FakeAppUpdateService(
        checkResult: const AppUpdateCheck(
          result: AppUpdateCheckResult.updateAvailable,
          info: AppUpdateInfo(
            versionName: '1.0.1',
            versionCode: 9,
            apkUrl:
                'https://example.supabase.co/storage/v1/object/public/space-shift-releases/space_shift-1.0.1.apk',
            releaseNotes: '버그 수정',
          ),
          currentVersionName: '1.0.0',
          currentVersionCode: 8,
        ),
      );
      final store = AppUpdateStore.withService(fake);

      await store.checkForUpdate();

      expect(store.state, AppUpdateState.updateAvailable);
      expect(store.latestInfo?.versionName, '1.0.1');
      expect(store.currentVersionCode, 8);
    });

    test('같은 버전이거나 더 낮으면 upToDate 상태가 된다', () async {
      final fake = _FakeAppUpdateService(
        checkResult: const AppUpdateCheck(
          result: AppUpdateCheckResult.upToDate,
          currentVersionName: '1.0.0',
          currentVersionCode: 8,
        ),
      );
      final store = AppUpdateStore.withService(fake);

      await store.checkForUpdate();

      expect(store.state, AppUpdateState.upToDate);
    });

    test('네트워크 오류 등으로 확인에 실패하면 error 상태와 안전한 메시지를 남긴다', () async {
      final fake = _FakeAppUpdateService(
        checkResult: const AppUpdateCheck(
          result: AppUpdateCheckResult.error,
          errorMessage: '업데이트 서버 응답이 없습니다 — 네트워크 연결을 확인해 주세요.',
          currentVersionName: '1.0.0',
          currentVersionCode: 8,
        ),
      );
      final store = AppUpdateStore.withService(fake);

      await store.checkForUpdate();

      expect(store.state, AppUpdateState.error);
      expect(store.errorMessage, contains('네트워크'));
    });
  });

  group('AppUpdateStore.downloadAndOpenInstaller', () {
    test('다운로드가 성공하면 진행률이 반영되고 readyToInstall로 전환되며 설치 화면을 연다', () async {
      final fake = _FakeAppUpdateService(
        checkResult: const AppUpdateCheck(
          result: AppUpdateCheckResult.updateAvailable,
          info: AppUpdateInfo(
            versionName: '1.0.1',
            versionCode: 9,
            apkUrl: 'https://example.supabase.co/space_shift-1.0.1.apk',
            releaseNotes: '',
          ),
          currentVersionName: '1.0.0',
          currentVersionCode: 8,
        ),
        downloadedPath: '/tmp/space_shift-1.0.1.apk',
      );
      final store = AppUpdateStore.withService(fake);
      await store.checkForUpdate();

      await store.downloadAndOpenInstaller();

      expect(store.state, AppUpdateState.readyToInstall);
      expect(store.downloadedBytes, 1024);
      expect(store.totalBytes, 1024);
      expect(fake.openForInstallCallCount, 1);
      expect(fake.lastOpenedPath, '/tmp/space_shift-1.0.1.apk');
    });

    test('다운로드에 실패하면(네트워크 오류) error 상태로 남고 설치 화면을 열려고 시도하지 않는다', () async {
      final fake = _FakeAppUpdateService(
        checkResult: const AppUpdateCheck(
          result: AppUpdateCheckResult.updateAvailable,
          info: AppUpdateInfo(
            versionName: '1.0.1',
            versionCode: 9,
            apkUrl: 'https://example.supabase.co/space_shift-1.0.1.apk',
            releaseNotes: '',
          ),
          currentVersionName: '1.0.0',
          currentVersionCode: 8,
        ),
        downloadedPath: null,
      );
      final store = AppUpdateStore.withService(fake);
      await store.checkForUpdate();

      await store.downloadAndOpenInstaller();

      expect(store.state, AppUpdateState.error);
      expect(store.errorMessage, isNotNull);
      expect(fake.openForInstallCallCount, 0);
    });

    test('upToDate 상태에서는 다운로드를 시도하지 않는다(다운로드할 새 버전이 없다)', () async {
      final fake = _FakeAppUpdateService(
        checkResult: const AppUpdateCheck(
          result: AppUpdateCheckResult.upToDate,
          currentVersionName: '1.0.0',
          currentVersionCode: 8,
        ),
      );
      final store = AppUpdateStore.withService(fake);
      await store.checkForUpdate();

      await store.downloadAndOpenInstaller();

      expect(store.state, AppUpdateState.upToDate);
      expect(fake.openForInstallCallCount, 0);
    });
  });

  group('AppUpdateStore.reopenInstaller', () {
    test('다운로드된 파일이 있으면 다시 다운로드하지 않고 설치 화면만 다시 연다', () async {
      final fake = _FakeAppUpdateService(
        checkResult: const AppUpdateCheck(
          result: AppUpdateCheckResult.updateAvailable,
          info: AppUpdateInfo(
            versionName: '1.0.1',
            versionCode: 9,
            apkUrl: 'https://example.supabase.co/space_shift-1.0.1.apk',
            releaseNotes: '',
          ),
          currentVersionName: '1.0.0',
          currentVersionCode: 8,
        ),
        downloadedPath: '/tmp/space_shift-1.0.1.apk',
      );
      final store = AppUpdateStore.withService(fake);
      await store.checkForUpdate();
      await store.downloadAndOpenInstaller();

      await store.reopenInstaller();

      expect(fake.openForInstallCallCount, 2);
    });

    test('다운로드된 파일이 없으면 아무 동작도 하지 않는다', () async {
      final fake = _FakeAppUpdateService();
      final store = AppUpdateStore.withService(fake);

      await store.reopenInstaller();

      expect(fake.openForInstallCallCount, 0);
    });
  });
}
