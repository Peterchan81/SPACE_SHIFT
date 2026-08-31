import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../config/app_environment.dart';
import '../models/app_update_info.dart';

enum AppUpdateCheckResult { upToDate, updateAvailable, error }

/// [AppUpdateService.checkForUpdate] 결과 — 실패해도 화면에 "현재 버전"은
/// 보여줄 수 있도록 현재 설치된 버전 정보를 항상 함께 담는다.
class AppUpdateCheck {
  final AppUpdateCheckResult result;
  final AppUpdateInfo? info;
  final String? errorMessage;
  final String currentVersionName;
  final int currentVersionCode;

  const AppUpdateCheck({
    required this.result,
    this.info,
    this.errorMessage,
    required this.currentVersionName,
    required this.currentVersionCode,
  });
}

/// Galaxy Tab 인터넷 기반 무선 업데이트.
///
/// USB/ADB 없이 "PC1 빌드 → Supabase Storage 공개 버킷 업로드 → 앱이 새
/// 버전 감지 → APK 다운로드 → Android 설치 화면"으로 이어지는 흐름을
/// 담당한다. NOMPASS(V1)가 이미 실기로 검증한 것과 같은 구조 — 인증이
/// 필요 없는 **공개** Storage 버킷만 바라보므로, 이 서비스도 여기서 만든
/// APK도 어떤 토큰/Secret도 필요로 하지 않는다.
///
/// NOMPASS와 완전히 분리하기 위해:
///   1. 버킷 이름을 다르게 쓴다(`space-shift-releases`, NOMPASS는
///      `app-releases`) — 같은 Supabase 프로젝트를 쓰게 되는 실수가
///      있어도 서로 다른 경로라 절대 겹치지 않는다.
///   2. `version.json`에 `app: "space-shift"` 필드를 요구한다
///      ([AppUpdateInfo.fromJson]) — 다른 앱의 채널을 잘못 읽어도 즉시
///      무시된다.
///
/// 설치는 항상 2단계다 — (1) 이 서비스가 HTTPS로 APK를 앱 임시 폴더에
/// 내려받고, (2) [openForInstall]로 OS 기본 패키지 설치 화면을 연다.
/// 실제 설치 버튼을 누르는 것은 항상 Android 사용자 본인이다 — 이 서비스
/// 어디에도 자동 설치 코드는 없다(Android 보안 정책을 우회하지 않는다).
class AppUpdateService {
  /// [supabaseUrlOverride]를 지정하면 [AppEnvironment.supabaseUrl] 대신 이
  /// 값을 사용한다. `--dart-define` 값은 컴파일 타임에 고정되어 테스트에서
  /// 런타임에 바꿀 수 없으므로(`createAiGenerationService`의
  /// `edgeFunctionUrlOverride`와 같은 관례), 여러 배포 채널 상황을
  /// 테스트하기 위한 용도로 둔 값이다.
  AppUpdateService({http.Client? httpClient, String? supabaseUrlOverride})
    : _httpClient = httpClient ?? http.Client(),
      _supabaseUrl = supabaseUrlOverride ?? AppEnvironment.supabaseUrl;

  final http.Client _httpClient;
  final String _supabaseUrl;

  static const String _bucket = 'space-shift-releases';
  static const String _channelPath =
      'storage/v1/object/public/$_bucket/version.json';

  /// 배포 채널 주소를 또 다른 하드코딩된 값으로 따로 관리하지 않고,
  /// Supabase 프로젝트 URL에서 그대로 파생시킨다. 이 URL 자체는 공개
  /// 정보다(민감정보 아님).
  String? get _versionInfoUrl {
    final base = _supabaseUrl;
    if (base.isEmpty) return null;
    final normalized = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    return '$normalized/$_channelPath';
  }

  Future<AppUpdateCheck> checkForUpdate() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersionName = packageInfo.version;
    final currentVersionCode = int.tryParse(packageInfo.buildNumber) ?? 0;

    final url = _versionInfoUrl;
    if (url == null) {
      return AppUpdateCheck(
        result: AppUpdateCheckResult.error,
        errorMessage: '업데이트 채널 주소를 확인할 수 없습니다(빌드 시 SUPABASE_URL 설정 필요).',
        currentVersionName: currentVersionName,
        currentVersionCode: currentVersionCode,
      );
    }

    try {
      final response = await _httpClient
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        return AppUpdateCheck(
          result: AppUpdateCheckResult.error,
          errorMessage: '업데이트 정보를 가져오지 못했습니다(오류 코드 ${response.statusCode}).',
          currentVersionName: currentVersionName,
          currentVersionCode: currentVersionCode,
        );
      }

      final info = AppUpdateInfo.fromJson(jsonDecode(response.body));
      if (info == null) {
        return AppUpdateCheck(
          result: AppUpdateCheckResult.error,
          errorMessage: '업데이트 정보 형식이 올바르지 않습니다.',
          currentVersionName: currentVersionName,
          currentVersionCode: currentVersionCode,
        );
      }

      return AppUpdateCheck(
        result: info.versionCode > currentVersionCode
            ? AppUpdateCheckResult.updateAvailable
            : AppUpdateCheckResult.upToDate,
        info: info,
        currentVersionName: currentVersionName,
        currentVersionCode: currentVersionCode,
      );
    } on TimeoutException {
      return AppUpdateCheck(
        result: AppUpdateCheckResult.error,
        errorMessage: '업데이트 서버 응답이 없습니다 — 네트워크 연결을 확인해 주세요.',
        currentVersionName: currentVersionName,
        currentVersionCode: currentVersionCode,
      );
    } catch (_) {
      return AppUpdateCheck(
        result: AppUpdateCheckResult.error,
        errorMessage: '업데이트 확인 중 오류가 발생했습니다 — 네트워크 연결을 확인해 주세요.',
        currentVersionName: currentVersionName,
        currentVersionCode: currentVersionCode,
      );
    }
  }

  /// [info.apkUrl]을 앱 임시 폴더로 내려받는다. 실패하면(네트워크 오류,
  /// 오류 상태 코드) null을 반환한다 — 예외를 밖으로 던지지 않는다.
  Future<String?> downloadApk(
    AppUpdateInfo info, {
    void Function(int received, int? total)? onProgress,
  }) async {
    try {
      final request = http.Request('GET', Uri.parse(info.apkUrl));
      final response = await _httpClient
          .send(request)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return null;

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/space_shift-${info.versionName}.apk');
      final sink = file.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.stream) {
          received += chunk.length;
          sink.add(chunk);
          onProgress?.call(received, response.contentLength);
        }
      } finally {
        await sink.close();
      }
      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// 내려받은 APK를 OS 기본 설치 화면으로 연다. 이 호출은 화면을 여는
  /// 것뿐이다 — 그다음 "설치" 버튼을 누르는 것은 항상 Android 사용자
  /// 본인이며, 이 앱은 그 결과를 기다리거나 강제하지 않는다. 기존 앱과
  /// 같은 applicationId/서명으로 설치되므로 사용자 데이터는 유지된다.
  Future<bool> openForInstall(String filePath) async {
    final result = await OpenFilex.open(filePath);
    return result.type == ResultType.done;
  }
}
