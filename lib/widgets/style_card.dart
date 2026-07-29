import 'package:flutter/material.dart';

/// 인테리어 스타일 하나를 보여주는 선택 카드.
///
/// 왼쪽에는 대표 이미지 자리(Placeholder), 오른쪽에는 스타일 이름과 설명을
/// 표시한다. 선택된 상태에서는 테두리 색이 바뀌고 우측 상단에 체크 아이콘이
/// 표시된다. 스타일 목록 화면에서 반복해서 재사용한다.
class StyleCard extends StatelessWidget {
  const StyleCard({
    super.key,
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  /// 스타일 이름 (예: 모던)
  final String title;

  /// 스타일 설명 (예: 깔끔하고 세련된 공간)
  final String description;

  /// 현재 선택된 카드인지 여부
  final bool selected;

  /// 카드를 눌렀을 때 실행할 동작
  final VoidCallback onTap;

  static const Color _accent = Color(0xFF8D6E63);
  static const Color _borderDefault = Color(0xFFD7CCC8);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? _accent : _borderDefault,
              width: selected ? 2.5 : 1.5,
            ),
          ),
          child: Stack(
            children: [
              Row(
                children: [
                  // 대표 이미지 자리 (Placeholder)
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.image_rounded,
                      size: 36,
                      color: Color(0xFFBCAAA4),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF3E2723),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          description,
                          style: const TextStyle(
                            fontSize: 15,
                            color: Color(0xFF5D4037),
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // 선택 상태일 때만 우측 상단에 체크 아이콘 표시
              if (selected)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: _accent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
