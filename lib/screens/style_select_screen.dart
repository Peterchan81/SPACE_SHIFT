import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../widgets/primary_button.dart';
import '../widgets/style_card.dart';
import 'workspace_screen.dart';

/// 선택 가능한 인테리어 스타일 하나를 나타내는 데이터.
class _StyleOption {
  const _StyleOption({required this.title, required this.description});

  final String title;
  final String description;
}

/// 원하는 인테리어 스타일을 선택하는 화면.
///
/// 이번 단계에서는 실제 AI 생성은 하지 않고, 스타일 선택과
/// [GenerateScreen]으로의 화면 이동만 구현한다.
class StyleSelectScreen extends StatefulWidget {
  const StyleSelectScreen({super.key, required this.selectedImageBytes});

  /// PhotoSelectScreen에서 사용자가 선택한 사진 데이터.
  /// GenerateScreen을 거쳐 ResultScreen까지 그대로 전달한다.
  final Uint8List selectedImageBytes;

  @override
  State<StyleSelectScreen> createState() => _StyleSelectScreenState();
}

class _StyleSelectScreenState extends State<StyleSelectScreen> {
  /// Splash, 사진 선택 화면과 동일한 밝은 아이보리 계열 배경색
  static const Color _ivoryBackground = Color(0xFFFFF8E7);

  /// 선택 가능한 인테리어 스타일 목록
  static const List<_StyleOption> _styles = [
    _StyleOption(title: '모던', description: '깔끔하고 세련된 공간'),
    _StyleOption(title: '미니멀', description: '불필요한 요소를 줄인 심플한 공간'),
    _StyleOption(title: '북유럽', description: '밝고 따뜻한 감성의 인테리어'),
    _StyleOption(title: '호텔', description: '고급스럽고 편안한 분위기'),
    _StyleOption(title: '따뜻한 우드', description: '자연스러운 원목 느낌의 공간'),
  ];

  /// 현재 선택된 스타일의 인덱스. 아직 선택하지 않았다면 null.
  int? _selectedIndex;

  void _goToWorkspace() {
    // 스타일을 아직 선택하지 않았다면 화면을 이동시키지 않고 안내만 표시한다.
    final selectedIndex = _selectedIndex;
    if (selectedIndex == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('스타일을 먼저 선택해주세요.')));
      return;
    }

    final selectedStyleName = _styles[selectedIndex].title;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => WorkspaceScreen(
          selectedStyle: selectedStyleName,
          selectedImageBytes: widget.selectedImageBytes,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ivoryBackground,
      appBar: AppBar(
        title: const Text('인테리어 스타일'),
        backgroundColor: _ivoryBackground,
        foregroundColor: const Color(0xFF3E2723),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              children: [
                // 상단 안내 영역 (스크롤 되지 않는 고정 영역)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '원하는 스타일을 선택해주세요',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF3E2723),
                            ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'AI가 선택한 스타일에 맞게\n공간 이미지를 새롭게 생성합니다.',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: const Color(0xFF5D4037),
                              height: 1.4,
                            ),
                      ),
                    ],
                  ),
                ),
                // 스타일 카드 목록 (세로 스크롤)
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                    itemCount: _styles.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      final style = _styles[index];
                      return StyleCard(
                        title: style.title,
                        description: style.description,
                        selected: _selectedIndex == index,
                        onTap: () {
                          setState(() {
                            _selectedIndex = index;
                          });
                        },
                      );
                    },
                  ),
                ),
                // 하단 영역: AI로 공간 만들기 버튼
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: PrimaryButton(
                    label: 'AI로 공간 만들기',
                    onPressed: _goToWorkspace,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
