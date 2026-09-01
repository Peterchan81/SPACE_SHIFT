import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../models/app_update_view.dart';
import '../services/app_update_store.dart';
import '../services/image_picker_service.dart';
import '../theme/space_shift_colors.dart';
import '../widgets/app_update_banner.dart';
import '../widgets/gradient_cta_button.dart';
import '../widgets/photo_source_card.dart';
import 'workspace_screen.dart';

/// 선택된 사진이 카메라 촬영인지 갤러리 선택인지 구분하는 값.
enum _ImageSourceType { camera, gallery }

/// MASTER UI 2번 화면 — 공간 사진 등록.
///
/// 카메라 촬영 또는 갤러리에서 사진 한 장을 선택하면 같은 화면에서 바로
/// 미리보기로 보여주고(삭제/재선택 가능), "다음"을 누르면 곧바로 공간
/// 작업실([WorkspaceScreen], 4번 화면)로 이동한다. 이전에 있던 별도의
/// 사진 확인 화면(3번)은 이 화면과 기능이 중복되어 활성 흐름에서 제거했다.
class PhotoSelectScreen extends StatefulWidget {
  const PhotoSelectScreen({
    super.key,
    this.imagePickerService = const ImagePickerService(),
  });

  /// 카메라/갤러리 사진 선택 로직을 담당하는 서비스.
  /// 위젯 테스트에서는 가짜 이미지를 반환하는 구현으로 교체할 수 있다.
  final ImagePickerService imagePickerService;

  @override
  State<PhotoSelectScreen> createState() => _PhotoSelectScreenState();
}

class _PhotoSelectScreenState extends State<PhotoSelectScreen> {
  /// 사용자가 선택(촬영)한 사진의 바이트 데이터.
  /// 웹/모바일 모두에서 동일하게 Image.memory로 미리보기를 표시할 수 있다.
  Uint8List? _selectedImageBytes;

  /// 현재 선택된 사진의 출처(카메라/갤러리).
  _ImageSourceType? _imageSourceType;

  /// 카메라 또는 갤러리 선택창을 여는 동안 true.
  /// 두 버튼을 모두 비활성화해 중복 실행을 막는 데 사용한다.
  bool _isPickingImage = false;

  Future<void> _handleCameraTap() async {
    if (_isPickingImage) return;

    // Chrome 등 웹 환경에서는 카메라 캡처 동작이 브라우저/기기마다 달라
    // 신뢰할 수 없으므로, 실제 카메라를 실행하는 대신 갤러리 이용을 안내한다.
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('이 환경에서는 카메라를 사용할 수 없습니다.\n갤러리에서 사진을 선택해주세요.'),
        ),
      );
      return;
    }

    await _pickImage(
      source: _ImageSourceType.camera,
      pick: widget.imagePickerService.pickCameraImage,
      failureMessage: '카메라를 실행하지 못했습니다. 다시 시도해주세요.',
    );
  }

  Future<void> _handleGalleryTap() async {
    if (_isPickingImage) return;

    await _pickImage(
      source: _ImageSourceType.gallery,
      pick: widget.imagePickerService.pickGalleryImage,
      failureMessage: '사진을 불러오지 못했습니다. 다시 시도해주세요.',
    );
  }

  /// 카메라/갤러리 선택의 공통 처리(로딩 상태, 취소·오류 처리)를 담당한다.
  /// 선택을 취소하거나 실패해도 기존에 선택되어 있던 사진은 그대로 유지한다.
  Future<void> _pickImage({
    required _ImageSourceType source,
    required Future<Uint8List?> Function() pick,
    required String failureMessage,
  }) async {
    setState(() => _isPickingImage = true);
    try {
      final bytes = await pick();
      // 사용자가 선택/촬영을 취소한 경우 오류 없이 기존 화면을 유지한다.
      if (bytes == null) return;
      if (!mounted) return;
      setState(() {
        _selectedImageBytes = bytes;
        _imageSourceType = source;
      });
    } catch (error) {
      debugPrint('사진 선택 실패: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage)));
    } finally {
      if (mounted) {
        setState(() => _isPickingImage = false);
      }
    }
  }

  void _removePhoto() {
    setState(() {
      _selectedImageBytes = null;
      _imageSourceType = null;
    });
  }

  void _goToWorkspace() {
    final bytes = _selectedImageBytes;
    // 버튼이 비활성화되어 있어 정상적으로는 호출되지 않지만 안전하게 처리한다.
    if (bytes == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => WorkspaceScreen(selectedImageBytes: bytes),
      ),
    );
  }

  String _sourceLabel(_ImageSourceType source) {
    switch (source) {
      case _ImageSourceType.camera:
        return '카메라로 촬영한 사진';
      case _ImageSourceType.gallery:
        return '갤러리에서 선택한 사진';
    }
  }

  /// 인터넷 기반 무선 업데이트 배너. main.dart가 앱 시작 시 이미 실행해 둔
  /// AppUpdateStore.instance의 상태를 그대로 구독만 한다(새 확인 로직 없음).
  Widget _buildUpdateBanner(BuildContext context) {
    return AnimatedBuilder(
      animation: AppUpdateStore.instance,
      builder: (context, _) {
        final store = AppUpdateStore.instance;
        final view = AppUpdateViewState.of(
          state: store.state,
          versionName: store.latestInfo?.versionName,
        );
        if (!view.isVisible) return const SizedBox.shrink();
        return AppUpdateBanner(
          view: view,
          onInstall: store.downloadAndOpenInstaller,
        );
      },
    );
  }

  /// WorkspaceScreen/SignupScreen과 같은 관례 — 이 너비 이상이면 Galaxy Tab
  /// 가로 화면으로 보고 2단 레이아웃을 사용한다.
  static const double _wideMinWidth = 800;

  @override
  Widget build(BuildContext context) {
    final hasSelectedImage = _selectedImageBytes != null;
    final sourceType = _imageSourceType;

    return Scaffold(
      backgroundColor: SpaceShiftColors.background,
      appBar: AppBar(
        title: const Text('공간 사진 등록'),
        backgroundColor: SpaceShiftColors.background,
        foregroundColor: SpaceShiftColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= _wideMinWidth;
                  return isWide
                      ? _buildWideBody(
                          context,
                          hasSelectedImage: hasSelectedImage,
                          sourceType: sourceType,
                        )
                      : _buildNarrowBody(
                          context,
                          constraints: constraints,
                          hasSelectedImage: hasSelectedImage,
                          sourceType: sourceType,
                        );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 휴대폰 등 좁은 화면 — MASTER의 세로형 구성을 그대로 유지한다.
  Widget _buildNarrowBody(
    BuildContext context, {
    required BoxConstraints constraints,
    required bool hasSelectedImage,
    required _ImageSourceType? sourceType,
  }) {
    return SingleChildScrollView(
      child: ConstrainedBox(
        // 화면 높이만큼은 최소로 차지하도록 하여
        // 하단 CTA가 항상 하단에 위치하도록 한다.
        constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
        child: IntrinsicHeight(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildUpdateBanner(context),
                    _buildIntro(context),
                    const SizedBox(height: 24),
                    // 사진 미리보기 영역. 사진이 선택되어 있으면
                    // 우측 상단에 삭제 버튼을 함께 보여준다.
                    _PhotoPreviewBox(
                      imageBytes: _selectedImageBytes,
                      isLoading: _isPickingImage,
                      onRemove: hasSelectedImage ? _removePhoto : null,
                    ),
                    if (hasSelectedImage) ...[
                      const SizedBox(height: 12),
                      _buildSelectionStatus(sourceType),
                    ],
                    const SizedBox(height: 24),
                    _buildSourceButtons(),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildCta(hasSelectedImage),
            ],
          ),
        ),
      ),
    );
  }

  /// Galaxy Tab 가로 화면 — 왼쪽(안내 문구)/오른쪽(사진 미리보기+촬영·선택
  /// 버튼) 2단으로 배치해 세로 스크롤 없이 한 화면 안에 들어오게 한다.
  Widget _buildWideBody(
    BuildContext context, {
    required bool hasSelectedImage,
    required _ImageSourceType? sourceType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildUpdateBanner(context),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 4, child: _buildIntro(context)),
              const SizedBox(width: 32),
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _PhotoPreviewBox(
                        imageBytes: _selectedImageBytes,
                        isLoading: _isPickingImage,
                        onRemove: hasSelectedImage ? _removePhoto : null,
                        expand: true,
                      ),
                    ),
                    if (hasSelectedImage) ...[
                      const SizedBox(height: 10),
                      _buildSelectionStatus(sourceType),
                    ],
                    const SizedBox(height: 14),
                    _buildSourceButtons(compact: true),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildCta(hasSelectedImage),
      ],
    );
  }

  /// 상단 안내 영역(제목 + 설명). 좁은 화면 상단, 넓은 화면 왼쪽 열에서
  /// 공통으로 재사용한다.
  Widget _buildIntro(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '변화시킬 공간을 보여주세요',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: SpaceShiftColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          '사진을 촬영하거나 선택하면\n'
          'AI가 더 정확한 결과를 만들어드려요.',
          style: TextStyle(
            fontSize: 15,
            color: SpaceShiftColors.textSecondary,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  /// 사진 선택 완료 안내(체크 아이콘 + 상태 + 출처). 좁은/넓은 화면 모두
  /// 동일하게 재사용한다.
  Widget _buildSelectionStatus(_ImageSourceType? sourceType) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Row(
          children: [
            Icon(
              Icons.check_circle_rounded,
              size: 18,
              color: SpaceShiftColors.selectionAccent,
            ),
            SizedBox(width: 6),
            Text(
              '사진이 선택되었습니다.',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: SpaceShiftColors.textPrimary,
              ),
            ),
          ],
        ),
        if (sourceType != null) ...[
          const SizedBox(height: 4),
          Text(
            _sourceLabel(sourceType),
            style: const TextStyle(
              fontSize: 13,
              color: SpaceShiftColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }

  /// 사진 선택 버튼(카메라 / 갤러리). 선택창을 여는 동안에는 중복 실행을
  /// 막기 위해 두 버튼 모두 비활성화한다. [compact]가 true이면 Tablet
  /// Landscape의 좁은 세로 공간에 맞춰 카드 크기를 줄인다.
  Widget _buildSourceButtons({bool compact = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: PhotoSourceCard(
                icon: Icons.camera_alt_rounded,
                label: '카메라 촬영',
                onTap: _isPickingImage ? null : _handleCameraTap,
                compact: compact,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: PhotoSourceCard(
                icon: Icons.image_rounded,
                label: '사진 선택',
                onTap: _isPickingImage ? null : _handleGalleryTap,
                compact: compact,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          '사진 전체가 잘 보이는 사진일수록 좋아요.',
          style: TextStyle(fontSize: 13, color: SpaceShiftColors.textSecondary),
        ),
      ],
    );
  }

  /// 화면 하단 CTA — 공간 작업실(4번 화면)로 바로 이동한다.
  /// 사진을 선택해야만 다음 단계로 넘어갈 수 있다.
  Widget _buildCta(bool hasSelectedImage) {
    return GradientCtaButton(
      label: '다음',
      onPressed: hasSelectedImage ? _goToWorkspace : null,
    );
  }
}

/// 선택된 사진을 보여주는 미리보기 박스.
///
/// [imageBytes]가 없으면 빈 상태 Placeholder를 표시하고,
/// 있으면 실제 이미지를 BoxFit.cover로 채워 보여준다.
/// [isLoading]이 true이면 선택창이 열려 있는 동안 작은 로딩 표시를 겹쳐 보여준다.
/// [expand]가 true이면 4:3 비율 대신 부모(Expanded 등)가 제공하는 공간을
/// 그대로 채운다. Tablet Landscape처럼 세로 공간이 넉넉할 때 사용한다.
class _PhotoPreviewBox extends StatelessWidget {
  const _PhotoPreviewBox({
    this.imageBytes,
    this.isLoading = false,
    this.onRemove,
    this.expand = false,
  });

  /// 선택된 사진의 바이트 데이터. null이면 빈 상태를 표시한다.
  final Uint8List? imageBytes;

  /// 카메라/갤러리 선택창이 열려 있는 동안인지 여부.
  final bool isLoading;

  /// 선택된 사진을 지울 때 호출된다. null이면(사진이 없으면) 삭제 버튼을
  /// 표시하지 않는다.
  final VoidCallback? onRemove;

  /// true이면 4:3 비율 대신 부모가 제공하는 공간을 그대로 채운다.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final card = _buildCard();
    if (expand) {
      return SizedBox.expand(child: card);
    }
    return AspectRatio(aspectRatio: 4 / 3, child: card);
  }

  Widget _buildCard() {
    final bytes = imageBytes;

    return Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: SpaceShiftColors.border, width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            bytes == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.home_rounded,
                          size: 64,
                          color: SpaceShiftColors.border,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          '선택된 사진이 없습니다',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: SpaceShiftColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '밝고 공간 전체가 잘 보이는 사진이 좋아요.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: SpaceShiftColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  )
                : Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                  ),
            // 사진이 선택되어 있으면 우측 상단에 삭제(재선택) 버튼을 보여준다.
            if (onRemove != null)
              Positioned(
                top: 10,
                right: 10,
                child: GestureDetector(
                  onTap: onRemove,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Color(0x33000000), blurRadius: 6),
                      ],
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: SpaceShiftColors.textPrimary,
                    ),
                  ),
                ),
              ),
            // 선택창이 열려 있는 동안 작은 로딩 표시를 겹쳐 보여준다.
            if (isLoading)
              Container(
                color: const Color(0x99FFFFFF),
                child: const Center(
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: SpaceShiftColors.selectionAccent,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
  }
}



