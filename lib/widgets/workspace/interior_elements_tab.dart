import 'package:flutter/material.dart';

import '../../theme/space_shift_colors.dart';

enum _InteriorCategory { all, tv, rug, frame, curtain, decor }

extension on _InteriorCategory {
  String get label => switch (this) {
    _InteriorCategory.all => '전체',
    _InteriorCategory.tv => 'TV',
    _InteriorCategory.rug => '카펫',
    _InteriorCategory.frame => '액자',
    _InteriorCategory.curtain => '커튼',
    _InteriorCategory.decor => '장식',
  };

  IconData get icon => switch (this) {
    _InteriorCategory.all => Icons.grid_view_rounded,
    _InteriorCategory.tv => Icons.tv_outlined,
    _InteriorCategory.rug => Icons.crop_square_outlined,
    _InteriorCategory.frame => Icons.photo_outlined,
    _InteriorCategory.curtain => Icons.curtains_closed_outlined,
    _InteriorCategory.decor => Icons.spa_outlined,
  };
}

class _InteriorCatalogItem {
  const _InteriorCatalogItem(this.name, this.category, this.icon);
  final String name;
  final _InteriorCategory category;
  final IconData icon;
}

const _catalog = [
  _InteriorCatalogItem('벽걸이 TV', _InteriorCategory.tv, Icons.tv_outlined),
  _InteriorCatalogItem('거실 러그', _InteriorCategory.rug, Icons.crop_square_outlined),
  _InteriorCatalogItem('액자 세트', _InteriorCategory.frame, Icons.photo_outlined),
  _InteriorCatalogItem(
    '리넨 커튼',
    _InteriorCategory.curtain,
    Icons.curtains_closed_outlined,
  ),
  _InteriorCatalogItem('화분', _InteriorCategory.decor, Icons.spa_outlined),
  _InteriorCatalogItem('장식 소품', _InteriorCategory.decor, Icons.category_outlined),
];

/// 우측 "작업 환경 → 인테리어 요소" Tab.
///
/// PROFESSIONAL WORKSPACE UI RESTRUCTURE WO §6/§8 — TV/카펫/액자/커튼/장식
/// 같은 소품 카탈로그를 위한 자리. [LightingTab]과 같은 이유로 실제
/// asset/library나 배치 backend가 없으므로(§8), 카테고리·썸네일 구조만
/// 만들고 항목을 누르면 "준비 중"만 정직하게 안내한다.
class InteriorElementsTab extends StatefulWidget {
  const InteriorElementsTab({super.key});

  @override
  State<InteriorElementsTab> createState() => _InteriorElementsTabState();
}

class _InteriorElementsTabState extends State<InteriorElementsTab> {
  _InteriorCategory _category = _InteriorCategory.all;

  List<_InteriorCatalogItem> get _visibleCatalog => _category == _InteriorCategory.all
      ? _catalog
      : _catalog.where((item) => item.category == _category).toList();

  void _showNotReady(String name) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('"$name"은(는) 준비 중입니다. 곧 지원할 예정입니다.')));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          '인테리어 요소 카탈로그',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: SpaceShiftColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _InteriorCategory.values.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final category = _InteriorCategory.values[index];
              final selected = category == _category;
              return ChoiceChip(
                label: Text(category.label, style: const TextStyle(fontSize: 12)),
                avatar: Icon(category.icon, size: 15),
                selected: selected,
                onSelected: (_) => setState(() => _category = category),
                selectedColor: SpaceShiftColors.textPrimary,
                labelStyle: TextStyle(
                  color: selected ? Colors.white : SpaceShiftColors.textPrimary,
                ),
                backgroundColor: Colors.white,
                side: const BorderSide(color: SpaceShiftColors.border),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.85,
          ),
          itemCount: _visibleCatalog.length,
          itemBuilder: (context, index) {
            final item = _visibleCatalog[index];
            return _CatalogCard(
              name: item.name,
              icon: item.icon,
              onTap: () => _showNotReady(item.name),
            );
          },
        ),
      ],
    );
  }
}

class _CatalogCard extends StatelessWidget {
  const _CatalogCard({required this.name, required this.icon, required this.onTap});

  final String name;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: SpaceShiftColors.border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 26, color: SpaceShiftColors.textSecondary),
              const SizedBox(height: 6),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: SpaceShiftColors.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
