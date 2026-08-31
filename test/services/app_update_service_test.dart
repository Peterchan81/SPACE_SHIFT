import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ason_space/services/app_update_service.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// AppUpdateService.checkForUpdate가 실제 배포 채널 URL을 정확히 구성하고
/// 응답을 안전하게 파싱하는지 검증한다. 실제 네트워크 대신 [MockClient]를
/// 쓰고, `--dart-define=SUPABASE_URL=...`은 테스트 런타임에 바꿀 수 없으므로
/// [AppUpdateService.new]의 `supabaseUrlOverride`로 주입한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'SPACE SHIFT',
      packageName: 'com.example.ason_space',
      version: '1.0.0',
      buildNumber: '8',
      buildSignature: '',
    );
  });

  group('AppUpdateService.checkForUpdate — 채널 URL 구성/응답 파싱', () {
    test(
      'SPACE SHIFT 전용 버킷(space-shift-releases)의 version.json으로 요청한다',
      () async {
        Uri? requestedUri;
        final client = MockClient((request) async {
          requestedUri = request.url;
          return http.Response(
            jsonEncode({
              'app': 'space-shift',
              'versionName': '1.0.1',
              'versionCode': 9,
              'apkUrl':
                  'https://example-project.supabase.co/storage/v1/object/public/space-shift-releases/space_shift-1.0.1.apk',
              'releaseNotes': '',
            }),
            200,
          );
        });
        final service = AppUpdateService(
          httpClient: client,
          supabaseUrlOverride: 'https://example-project.supabase.co',
        );

        final result = await service.checkForUpdate();

        expect(
          requestedUri.toString(),
          'https://example-project.supabase.co/storage/v1/object/public/space-shift-releases/version.json',
        );
        expect(result.result, AppUpdateCheckResult.updateAvailable);
        expect(result.info?.versionCode, 9);
      },
    );

    test('원격 versionCode가 현재 buildNumber보다 크면 updateAvailable을 반환한다', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'app': 'space-shift',
            'versionName': '1.0.1',
            'versionCode': 9,
            'apkUrl': 'https://x/space_shift-1.0.1.apk',
            'releaseNotes': '',
          }),
          200,
        );
      });
      final service = AppUpdateService(
        httpClient: client,
        supabaseUrlOverride: 'https://example-project.supabase.co',
      );

      final result = await service.checkForUpdate();

      expect(result.result, AppUpdateCheckResult.updateAvailable);
      expect(result.currentVersionCode, 8);
    });

    test('원격 versionCode가 현재와 같거나 낮으면 upToDate를 반환한다(역행 배포 방지)', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'app': 'space-shift',
            'versionName': '1.0.0',
            'versionCode': 8,
            'apkUrl': 'https://x/space_shift-1.0.0.apk',
            'releaseNotes': '',
          }),
          200,
        );
      });
      final service = AppUpdateService(
        httpClient: client,
        supabaseUrlOverride: 'https://example-project.supabase.co',
      );

      final result = await service.checkForUpdate();

      expect(result.result, AppUpdateCheckResult.upToDate);
    });

    test('다른 앱(nompass)의 version.json을 잘못 받아도 절대 업데이트로 취급하지 않는다', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'app': 'nompass',
            'versionName': '9.9.9',
            'versionCode': 999,
            'apkUrl': 'https://x/nompass-9.9.9.apk',
            'releaseNotes': '',
          }),
          200,
        );
      });
      final service = AppUpdateService(
        httpClient: client,
        supabaseUrlOverride: 'https://example-project.supabase.co',
      );

      final result = await service.checkForUpdate();

      expect(result.result, AppUpdateCheckResult.error);
      expect(result.info, isNull);
    });

    test('SUPABASE_URL을 확인할 수 없으면 네트워크 요청 없이 error로 안전하게 실패한다', () async {
      final client = MockClient((request) async {
        fail('배포 채널 주소가 없으면 네트워크 요청 자체를 시도하면 안 된다');
      });
      final service = AppUpdateService(
        httpClient: client,
        supabaseUrlOverride: '',
      );

      final result = await service.checkForUpdate();

      expect(result.result, AppUpdateCheckResult.error);
      expect(result.errorMessage, isNotNull);
      expect(result.currentVersionName, '1.0.0');
    });

    test('업데이트 서버가 오류 상태 코드를 반환해도 error로 안전하게 실패한다', () async {
      final client = MockClient(
        (request) async => http.Response('not found', 404),
      );
      final service = AppUpdateService(
        httpClient: client,
        supabaseUrlOverride: 'https://example-project.supabase.co',
      );

      final result = await service.checkForUpdate();

      expect(result.result, AppUpdateCheckResult.error);
      expect(result.currentVersionCode, 8);
    });

    test('채널 JSON이 손상되면 error로 안전하게 실패한다', () async {
      final client = MockClient(
        (request) async => http.Response('{not valid json', 200),
      );
      final service = AppUpdateService(
        httpClient: client,
        supabaseUrlOverride: 'https://example-project.supabase.co',
      );

      final result = await service.checkForUpdate();

      expect(result.result, AppUpdateCheckResult.error);
    });
  });
}
