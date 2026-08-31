import 'package:flutter_test/flutter_test.dart';
import 'package:ason_space/models/app_update_view.dart';
import 'package:ason_space/services/app_update_store.dart';

void main() {
  group('AppUpdateViewState.of', () {
    test('updateAvailable이면 버전명을 포함한 문구와 함께 보인다', () {
      final view = AppUpdateViewState.of(
        state: AppUpdateState.updateAvailable,
        versionName: '1.0.1',
      );

      expect(view.isVisible, isTrue);
      expect(view.message, contains('1.0.1'));
    });

    test('downloading이면 다운로드 중 문구로 보인다', () {
      final view = AppUpdateViewState.of(state: AppUpdateState.downloading);

      expect(view.isVisible, isTrue);
      expect(view.message, contains('다운로드'));
    });

    test('readyToInstall이면 설치 안내 문구로 보인다', () {
      final view = AppUpdateViewState.of(state: AppUpdateState.readyToInstall);

      expect(view.isVisible, isTrue);
      expect(view.message, contains('설치'));
    });

    test('idle/checking/upToDate/error는 배경 확인 실패가 방해되지 않도록 항상 숨긴다', () {
      for (final state in [
        AppUpdateState.idle,
        AppUpdateState.checking,
        AppUpdateState.upToDate,
        AppUpdateState.error,
      ]) {
        final view = AppUpdateViewState.of(state: state);
        expect(view.isVisible, isFalse, reason: '$state는 숨겨져야 한다');
      }
    });
  });
}
