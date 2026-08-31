import '../services/app_update_store.dart';

/// [AppUpdateState]를 화면에 그대로 노출해도 되는 순수 값으로 옮겨 담는다
/// — "보일지/무슨 문구인지"만 판단하는 순수 함수라 위젯을 펌핑하지 않고도
/// 단위 테스트할 수 있다. 아직 확인 전(idle/checking)이거나 이미 최신
/// (upToDate), 배경 확인 실패(error)일 때는 항상 숨긴다 — 앱 시작 시
/// 배경에서 자동으로 실행되는 확인이라 실패해도 사용자를 방해하지
/// 않는다는 원칙을 이 한 곳에서 강제한다.
class AppUpdateViewState {
  final AppUpdateState state;
  final String message;
  final bool isVisible;

  const AppUpdateViewState._({
    required this.state,
    required this.message,
    required this.isVisible,
  });

  factory AppUpdateViewState.of({
    required AppUpdateState state,
    String? versionName,
  }) {
    switch (state) {
      case AppUpdateState.updateAvailable:
        return AppUpdateViewState._(
          state: state,
          isVisible: true,
          message: versionName == null || versionName.isEmpty
              ? '새 버전이 있습니다'
              : '새 버전 $versionName이(가) 있습니다',
        );
      case AppUpdateState.downloading:
        return AppUpdateViewState._(
          state: state,
          isVisible: true,
          message: '업데이트를 다운로드하고 있습니다...',
        );
      case AppUpdateState.readyToInstall:
        return AppUpdateViewState._(
          state: state,
          isVisible: true,
          message: '설치 준비가 완료됐습니다 — 설치 화면을 확인해 주세요',
        );
      case AppUpdateState.idle:
      case AppUpdateState.checking:
      case AppUpdateState.upToDate:
      case AppUpdateState.error:
        return AppUpdateViewState._(
          state: state,
          isVisible: false,
          message: '',
        );
    }
  }
}
