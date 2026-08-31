/// 공개 배포 채널(Supabase Storage 공개 버킷 `space-shift-releases`)의
/// `version.json`을 그대로 담는 값 객체.
///
/// 인증이 필요 없는 순수 HTTPS GET 결과이며, 어떤 Secret과도 무관하다.
class AppUpdateInfo {
  final String versionName;
  final int versionCode;
  final String apkUrl;
  final String releaseNotes;

  const AppUpdateInfo({
    required this.versionName,
    required this.versionCode,
    required this.apkUrl,
    required this.releaseNotes,
  });

  /// `version.json`이 반드시 담아야 하는 앱 식별자.
  ///
  /// SPACE SHIFT와 다른 앱(NOMPASS 등)이 같은 Supabase 프로젝트를 함께
  /// 쓰게 되는 실수가 있어도, 버킷/경로 분리에 더해 이 필드로 한 번 더
  /// 걸러낸다 — `app` 값이 다르면 [fromJson]이 null을 반환해 절대
  /// updateAvailable로 이어지지 않는다.
  static const String expectedApp = 'space-shift';

  /// 형식이 맞지 않거나 다른 앱의 채널이면 예외 대신 null을 반환한다 —
  /// 배포 채널의 JSON이 손상되었다고 앱이 죽어서는 안 된다.
  static AppUpdateInfo? fromJson(Object? json) {
    if (json is! Map) return null;
    final app = json['app'];
    if (app is! String || app != expectedApp) return null;

    final versionName = json['versionName'];
    final versionCode = json['versionCode'];
    final apkUrl = json['apkUrl'];
    if (versionName is! String || versionName.isEmpty) return null;
    if (versionCode is! int) return null;
    if (apkUrl is! String || apkUrl.isEmpty) return null;

    return AppUpdateInfo(
      versionName: versionName,
      versionCode: versionCode,
      apkUrl: apkUrl,
      releaseNotes: json['releaseNotes'] as String? ?? '',
    );
  }
}
