import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/space_shift_colors.dart';
import '../widgets/gradient_cta_button.dart';
import 'workspace_screen.dart';

/// MASTER UI 3번 화면 — 사진 미리보기 및 시작.
///
/// PhotoSelectScreen(2번)에서 고른 사진을 다시 확인하고, 필요하면 삭제한 뒤
/// "공간 변화 시작하기"로 곧바로 공간 작업실(4번)에 진입하는 화면이다.
/// 스타일 선택 단계는 MASTER 최종 흐름에 없으므로 2 -> 3 -> 4로 바로 연결한다.
class PhotoPreviewScreen extends StatelessWidget {
  const PhotoPreviewScreen({super.key, required this.selectedImageBytes});

  /// PhotoSelectScreen에서 선택한 사진 데이터.
  final Uint8List selectedImageBytes;

  void _removePhoto(BuildContext context) {
    // 현재는 사진 한 장만 다루므로, 삭제하면 사진을 다시 고를 수 있도록
    // 사진 선택 화면으로 되돌아간다.
    Navigator.of(context).pop();
  }

  void _startWorkspace(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            WorkspaceScreen(selectedImageBytes: selectedImageBytes),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpaceShiftColors.background,
      appBar: AppBar(
        backgroundColor: SpaceShiftColors.background,
        foregroundColor: SpaceShiftColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: IntrinsicHeight(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 8,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '사진을 확인하고\n공간 변화를 시작해보세요',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: SpaceShiftColors.textPrimary,
                                    height: 1.3,
                                  ),
                            ),
                            const SizedBox(height: 24),
                            Expanded(
                              child: Center(
                                child: Stack(
                                  children: [
                                    AspectRatio(
                                      aspectRatio: 4 / 3,
                                      child: Container(
                                        clipBehavior: Clip.antiAlias,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(
                                            color: SpaceShiftColors.border,
                                          ),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: Color(0x14000000),
                                              blurRadius: 8,
                                              offset: Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: Image.memory(
                                          selectedImageBytes,
                                          fit: BoxFit.cover,
                                          width: double.infinity,
                                          height: double.infinity,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 10,
                                      right: 10,
                                      child: GestureDetector(
                                        onTap: () => _removePhoto(context),
                                        child: Container(
                                          width: 32,
                                          height: 32,
                                          decoration: const BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Color(0x33000000),
                                                blurRadius: 6,
                                              ),
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
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Center(
                              child: Text(
                                '1 / 1',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: SpaceShiftColors.textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            GradientCtaButton(
                              label: '공간 변화 시작하기',
                              onPressed: () => _startWorkspace(context),
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
