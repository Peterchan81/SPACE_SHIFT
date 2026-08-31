import 'package:flutter/foundation.dart';

import '../models/app_update_info.dart';
import 'app_update_service.dart';

enum AppUpdateState {
  idle,
  checking,
  upToDate,
  updateAvailable,
  downloading,
  readyToInstall,
  error,
}

/// [AppUpdateService](실제 HTTPS 확인/다운로드/설치 화면 호출)를 화면이
/// 구독할 수 있는 상태로 감싼다. 가짜 진행률 타이머를 만들지 않고, 실제
/// 다운로드 스트림의 바이트 수만 [downloadedBytes]/[totalBytes]에 반영한다.
class AppUpdateStore extends ChangeNotifier {
  AppUpdateStore._({AppUpdateService? service})
    : _service = service ?? AppUpdateService();

  static final AppUpdateStore instance = AppUpdateStore._();

  /// 테스트 전용 — 실제 네트워크 대신 Fake [AppUpdateService]를 쓰는 새
  /// 인스턴스를 만든다(싱글턴을 바꾸지 않는다).
  @visibleForTesting
  factory AppUpdateStore.withService(AppUpdateService service) =>
      AppUpdateStore._(service: service);

  final AppUpdateService _service;

  AppUpdateState _state = AppUpdateState.idle;
  AppUpdateInfo? _latestInfo;
  String? _currentVersionName;
  int? _currentVersionCode;
  String? _errorMessage;
  String? _downloadedFilePath;
  int _downloadedBytes = 0;
  int? _totalBytes;

  AppUpdateState get state => _state;
  AppUpdateInfo? get latestInfo => _latestInfo;
  String? get currentVersionName => _currentVersionName;
  int? get currentVersionCode => _currentVersionCode;
  String? get errorMessage => _errorMessage;
  int get downloadedBytes => _downloadedBytes;
  int? get totalBytes => _totalBytes;

  Future<void> checkForUpdate() async {
    _state = AppUpdateState.checking;
    _errorMessage = null;
    notifyListeners();

    final result = await _service.checkForUpdate();
    _currentVersionName = result.currentVersionName;
    _currentVersionCode = result.currentVersionCode;
    _latestInfo = result.info;

    switch (result.result) {
      case AppUpdateCheckResult.upToDate:
        _state = AppUpdateState.upToDate;
      case AppUpdateCheckResult.updateAvailable:
        _state = AppUpdateState.updateAvailable;
      case AppUpdateCheckResult.error:
        _state = AppUpdateState.error;
        _errorMessage = result.errorMessage;
    }
    notifyListeners();
  }

  Future<void> downloadAndOpenInstaller() async {
    final info = _latestInfo;
    if (info == null || _state != AppUpdateState.updateAvailable) return;

    _state = AppUpdateState.downloading;
    _downloadedBytes = 0;
    _totalBytes = null;
    _errorMessage = null;
    notifyListeners();

    final filePath = await _service.downloadApk(
      info,
      onProgress: (received, total) {
        _downloadedBytes = received;
        _totalBytes = total;
        notifyListeners();
      },
    );

    if (filePath == null) {
      _state = AppUpdateState.error;
      _errorMessage = 'APK 다운로드에 실패했습니다 — 네트워크 연결을 확인한 뒤 다시 시도해 주세요.';
      notifyListeners();
      return;
    }

    _downloadedFilePath = filePath;
    _state = AppUpdateState.readyToInstall;
    notifyListeners();

    // 다운로드가 끝나면 곧바로 OS 기본 설치 화면을 연다. 여기서 앱이 하는
    // 일은 그 화면을 "여는" 것뿐이다 — 실제 설치 버튼은 항상 Android
    // 사용자 본인이 그 화면에서 직접 누른다(자동 설치 없음, 보안 정책
    // 우회 없음). 기존 앱 위에 업데이트 설치되므로 데이터도 유지된다.
    await _service.openForInstall(filePath);
  }

  /// 사용자가 설치 화면을 놓쳤거나 취소했을 때 다시 열기 위한 진입점 —
  /// 다운로드를 다시 하지 않는다.
  Future<void> reopenInstaller() async {
    final filePath = _downloadedFilePath;
    if (filePath == null) return;
    await _service.openForInstall(filePath);
  }
}
