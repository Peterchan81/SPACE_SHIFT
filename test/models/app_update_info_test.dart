import 'package:flutter_test/flutter_test.dart';
import 'package:ason_space/models/app_update_info.dart';

void main() {
  group('AppUpdateInfo.fromJson', () {
    test('app 필드가 space-shift인 정상 JSON은 그대로 파싱된다', () {
      final info = AppUpdateInfo.fromJson({
        'app': 'space-shift',
        'versionName': '1.0.0',
        'versionCode': 9,
        'apkUrl':
            'https://example.supabase.co/storage/v1/object/public/space-shift-releases/space_shift-1.0.0.apk',
        'releaseNotes': '안정성 개선',
      });

      expect(info, isNotNull);
      expect(info!.versionName, '1.0.0');
      expect(info.versionCode, 9);
      expect(info.releaseNotes, '안정성 개선');
    });

    test('releaseNotes를 생략하면 빈 문자열로 채워진다', () {
      final info = AppUpdateInfo.fromJson({
        'app': 'space-shift',
        'versionName': '1.0.0',
        'versionCode': 9,
        'apkUrl': 'https://x/space_shift.apk',
      });

      expect(info, isNotNull);
      expect(info!.releaseNotes, '');
    });

    test('app 필드가 다른 앱(예: nompass)이면 절대 파싱하지 않는다 — 잘못된 배포물 오인 방지', () {
      final info = AppUpdateInfo.fromJson({
        'app': 'nompass',
        'versionName': '1.0.0',
        'versionCode': 9,
        'apkUrl': 'https://x/nompass-1.0.0.apk',
      });

      expect(info, isNull);
    });

    test('app 필드가 아예 없으면 파싱하지 않는다', () {
      final info = AppUpdateInfo.fromJson({
        'versionName': '1.0.0',
        'versionCode': 9,
        'apkUrl': 'https://x/space_shift.apk',
      });

      expect(info, isNull);
    });

    test('형식이 손상되었거나 필수 필드가 어긋나면 예외 대신 null을 반환한다', () {
      expect(AppUpdateInfo.fromJson(null), isNull);
      expect(AppUpdateInfo.fromJson('not a map'), isNull);
      expect(AppUpdateInfo.fromJson(<String, dynamic>{}), isNull);
      expect(
        AppUpdateInfo.fromJson({
          'app': 'space-shift',
          'versionName': '1.0.0',
          'versionCode': 'not-an-int',
          'apkUrl': 'https://x',
        }),
        isNull,
      );
      expect(
        AppUpdateInfo.fromJson({
          'app': 'space-shift',
          'versionName': '',
          'versionCode': 1,
          'apkUrl': 'https://x',
        }),
        isNull,
      );
      expect(
        AppUpdateInfo.fromJson({
          'app': 'space-shift',
          'versionName': '1.0.0',
          'versionCode': 1,
          'apkUrl': '',
        }),
        isNull,
      );
    });
  });
}
