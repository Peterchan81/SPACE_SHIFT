import 'package:flutter/material.dart';

import '../widgets/primary_button.dart';
import 'photo_select_screen.dart';

/// 앱 실행 시 가장 먼저 보여지는 스플래시 화면.
///
/// 앱을 소개하는 아이콘과 제목, 설명 문구를 보여주고
/// '시작하기' 버튼을 통해 사진 선택 화면으로 이동시킨다.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  /// 밝은 아이보리 계열 배경색
  static const Color _ivoryBackground = Color(0xFFFFF8E7);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ivoryBackground,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    // 화면 높이만큼은 최소로 차지하도록 하여
                    // 버튼이 항상 하단에 위치하도록 한다.
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 32,
                        ),
                        child: Column(
                          children: [
                            // 화면 중앙 영역: 아이콘 + 제목 + 설명
                            Expanded(
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.home_rounded,
                                      size: 120,
                                      color: Color(0xFF8D6E63),
                                    ),
                                    const SizedBox(height: 24),
                                    Text(
                                      'SPACE SHIFT',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: const Color(0xFF3E2723),
                                          ),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      '사진 한 장으로,\n우리 집의 새로운 모습을 확인하세요.',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                            color: const Color(0xFF5D4037),
                                            height: 1.4,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // 화면 하단 영역: 시작하기 버튼
                            PrimaryButton(
                              label: '시작하기',
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const PhotoSelectScreen(),
                                    // 결과 화면에서 popUntil로 돌아올 때 사용하는 이름
                                    // (result_screen.dart 참고)
                                    settings: const RouteSettings(
                                      name: 'photo_select',
                                    ),
                                  ),
                                );
                              },
                            ),
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
