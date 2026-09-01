import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/app_update_store.dart';
import '../theme/space_shift_colors.dart';

/// MASTER 공통 "설정" 화면.
///
/// 신규 MASTER 작업 화면 좌측 하단 "⚙ 설정"에서 진입한다(시작 방식과
/// 무관한 공통 기능). 기존에 [AppUpdateBanner]로 화면 위쪽에만 조용히
/// 보여주던 무선 업데이트 기능을, 사용자가 직접 확인/실행할 수 있는
/// 전용 화면으로 옮겼다 — 새 확인/다운로드/설치 로직을 만들지 않고
/// 이미 Galaxy Tab에서 실기 검증된 [AppUpdateStore]/[AppUpdateService]를
/// 그대로 구독/호출만 한다.
class SettingsScreen extends StatefulWidget {
  SettingsScreen({super.key, AppUpdateStore? updateStore})
    : updateStore = updateStore ?? AppUpdateStore.instance;

  final AppUpdateStore updateStore;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  PackageInfo? _packageInfo;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _packageInfo = info);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpaceShiftColors.background,
      appBar: AppBar(
        title: const Text('설정'),
        backgroundColor: SpaceShiftColors.background,
        foregroundColor: SpaceShiftColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _SettingsSection(title: '앱 정보', child: _buildAppInfo()),
                const SizedBox(height: 20),
                _SettingsSection(
                  title: '앱 업데이트',
                  child: ListenableBuilder(
                    listenable: widget.updateStore,
                    builder: (context, _) => _AppUpdateSection(
                      store: widget.updateStore,
                      currentVersionName:
                          widget.updateStore.currentVersionName ??
                          _packageInfo?.version,
                      currentVersionCode:
                          widget.updateStore.currentVersionCode ??
                          int.tryParse(_packageInfo?.buildNumber ?? ''),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const _SettingsSection(
                  title: '기타',
                  child: Text(
                    '추가 설정 항목은 이후 이곳에 채워질 예정입니다.',
                    style: TextStyle(
                      fontSize: 13,
                      color: SpaceShiftColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppInfo() {
    final info = _packageInfo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _InfoRow(label: '앱 이름', value: 'SPACE SHIFT'),
        _InfoRow(label: '버전', value: info == null ? '확인 중...' : info.version),
        _InfoRow(
          label: '빌드 번호(versionCode)',
          value: info == null ? '확인 중...' : info.buildNumber,
        ),
        const _InfoRow(label: '설치 상태', value: '정상적으로 설치되어 실행 중입니다'),
      ],
    );
  }
}

class _AppUpdateSection extends StatelessWidget {
  const _AppUpdateSection({
    required this.store,
    required this.currentVersionName,
    required this.currentVersionCode,
  });

  final AppUpdateStore store;
  final String? currentVersionName;
  final int? currentVersionCode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InfoRow(
          label: '현재 버전',
          value: currentVersionName == null
              ? '확인 중...'
              : '$currentVersionName (빌드 ${currentVersionCode ?? '-'})',
        ),
        const SizedBox(height: 12),
        _buildStateBody(context),
      ],
    );
  }

  Widget _buildStateBody(BuildContext context) {
    switch (store.state) {
      case AppUpdateState.idle:
        return _StatusRow(
          icon: Icons.system_update_outlined,
          message: '아직 업데이트를 확인하지 않았습니다.',
          action: _CheckButton(store: store),
        );
      case AppUpdateState.checking:
        return const _StatusRow(
          icon: null,
          loading: true,
          message: '업데이트를 확인하는 중입니다...',
        );
      case AppUpdateState.upToDate:
        return _StatusRow(
          icon: Icons.check_circle_outline_rounded,
          message: '최신 버전을 사용 중입니다.',
          action: _CheckButton(store: store, label: '다시 확인'),
        );
      case AppUpdateState.updateAvailable:
        final info = store.latestInfo;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatusRow(
              icon: Icons.new_releases_outlined,
              message: info == null
                  ? '새 업데이트가 있습니다.'
                  : '새 업데이트가 있습니다 · ${info.versionName} (빌드 ${info.versionCode})',
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: store.downloadAndOpenInstaller,
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('업데이트'),
                style: FilledButton.styleFrom(
                  backgroundColor: SpaceShiftColors.textPrimary,
                  minimumSize: const Size.fromHeight(44),
                ),
              ),
            ),
          ],
        );
      case AppUpdateState.downloading:
        final total = store.totalBytes;
        final received = store.downloadedBytes;
        final progress = (total != null && total > 0) ? received / total : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              progress == null
                  ? '다운로드 중...'
                  : '다운로드 중... ${(progress * 100).toStringAsFixed(0)}%',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: SpaceShiftColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: progress, minHeight: 8),
            ),
          ],
        );
      case AppUpdateState.readyToInstall:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _StatusRow(
              icon: Icons.inventory_2_outlined,
              message: '설치 준비가 완료됐습니다 — 설치 화면을 확인해 주세요.',
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: store.reopenInstaller,
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('설치 화면 다시 열기'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  foregroundColor: SpaceShiftColors.textPrimary,
                  side: const BorderSide(color: SpaceShiftColors.border),
                ),
              ),
            ),
          ],
        );
      case AppUpdateState.error:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatusRow(
              icon: Icons.error_outline_rounded,
              message: store.errorMessage ?? '업데이트 확인 중 문제가 발생했습니다.',
              iconColor: Colors.redAccent,
            ),
            const SizedBox(height: 10),
            _CheckButton(store: store, label: '다시 시도'),
          ],
        );
    }
  }
}

class _CheckButton extends StatelessWidget {
  const _CheckButton({required this.store, this.label = '업데이트 확인'});

  final AppUpdateStore store;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: store.checkForUpdate,
        icon: const Icon(Icons.refresh_rounded, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(44),
          foregroundColor: SpaceShiftColors.textPrimary,
          side: const BorderSide(color: SpaceShiftColors.border),
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.message,
    this.action,
    this.loading = false,
    this.iconColor = SpaceShiftColors.textSecondary,
  });

  final IconData? icon;
  final String message;
  final Widget? action;
  final bool loading;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (loading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (icon != null)
              Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 13,
                  color: SpaceShiftColors.textPrimary,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
        if (action != null) ...[const SizedBox(height: 10), action!],
      ],
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SpaceShiftColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: SpaceShiftColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: SpaceShiftColors.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: SpaceShiftColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
