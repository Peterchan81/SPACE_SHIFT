import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ason_space/services/app_update_service.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// SS017 — catch-all이 모든 실패를 "네트워크 오류"로 둔갑시키지 않는지 검증한다.
///
/// AppUpdateService.checkForUpdate는 실제 연결 문제(SocketException,
/// http.ClientException, TimeoutException — 기존 테스트가 이미 검증)만 네트워크
/// 오류로 안내해야 하고, 그 밖의 예상치 못한 예외(우리 코드의 버그를 흉내낸
/// StateError 등)는 절대 같은 네트워크 문구로 보고하지 않고 일반 오류로 안내해야
/// 한다.
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

  group('AppUpdateService.checkForUpdate — 오류 분류(SS017)', () {
    test('실제 연결 실패(SocketException)는 네트워크 오류 문구로 안내한다', () async {
      final client = MockClient((request) async {
        throw const SocketException('Failed host lookup');
      });
      final service = AppUpdateService(
        httpClient: client,
        supabaseUrlOverride: 'https://example-project.supabase.co',
      );

      final result = await service.checkForUpdate();

      expect(result.result, AppUpdateCheckResult.error);
      expect(result.errorMessage, isNotNull);
      expect(result.errorMessage, contains('네트워크'));
    });

    test('http.ClientException도 네트워크 오류 문구로 안내한다', () async {
      final client = MockClient((request) async {
        throw http.ClientException('connection closed');
      });
      final service = AppUpdateService(
        httpClient: client,
        supabaseUrlOverride: 'https://example-project.supabase.co',
      );

      final result = await service.checkForUpdate();

      expect(result.result, AppUpdateCheckResult.error);
      expect(result.errorMessage, contains('네트워크'));
    });

    test('네트워크와 무관한 예외(StateError)는 네트워크 오류로 둔갑시키지 않는다', () async {
      final client = MockClient((request) async {
        throw StateError('unexpected bug, not a network issue');
      });
      final service = AppUpdateService(
        httpClient: client,
        supabaseUrlOverride: 'https://example-project.supabase.co',
      );

      final result = await service.checkForUpdate();

      expect(result.result, AppUpdateCheckResult.error);
      expect(result.errorMessage, isNotNull);
      // 핵심 회귀 방지 — catch-all이 이 실패를 "네트워크 연결을 확인해주세요"로
      // 둔갑시키던 결함이 다시 생기지 않았는지 확인한다.
      expect(result.errorMessage, isNot(contains('네트워크')));
    });

    test('채널 JSON이 손상되어도(FormatException) 네트워크 오류로 둔갑시키지 않는다', () async {
      final client = MockClient(
        (request) async => http.Response('{not valid json', 200),
      );
      final service = AppUpdateService(
        httpClient: client,
        supabaseUrlOverride: 'https://example-project.supabase.co',
      );

      final result = await service.checkForUpdate();

      expect(result.result, AppUpdateCheckResult.error);
      expect(result.errorMessage, isNot(contains('네트워크')));
    });
  });
}
