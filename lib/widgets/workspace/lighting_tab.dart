import 'package:flutter/material.dart';

import '../../theme/space_shift_colors.dart';

enum _LightingCategory { all, ceiling, pendant, floor, indirect }

extension on _LightingCategory {
  String get label => switch (this) {
    _LightingCategory.all => '전체',
    _LightingCategory.ceiling => '천장등',
    _LightingCategory.pendant => '펜던트',
    _LightingCategory.floor => '스탠드',
    _LightingCategory.indirect => '간접조명',
  };

  IconData get icon => switch (this) {
    _LightingCategory.all => Icons.grid_view_rounded,
    _LightingCategory.ceiling => Icons.light_rounded,
    _LightingCategory.pendant => Icons.emoji_objects_outlined,
    _LightingCategory.floor => Icons.lightbulb_outline_rounded,
    _LightingCategory.indirect => Icons.wb_incandescent_outlined,
  };
}

class _LightingCatalogItem {
  const _LightingCatalogItem(this.name, this.category, this.icon);
  final String name;
  final _LightingCategory category;
  final IconData icon;
}

const _catalog = [
  _LightingCatalogItem('원형 천장등', _LightingCategory.ceiling, Icons.light_rounded),
  _LightingCatalogItem(
    '매입등 세트',
    _LightingCategory.ceiling,
    Icons.blur_circular_outlined,
  ),
  _LightingCatalogItem(
    '펜던트 조명',
    _LightingCategory.pendant,
    Icons.emoji_objects_outlined,
  ),
  _LightingCatalogItem(
    '체인 펜던트',
    _LightingCategory.pendant,
    Icons.emoji_objects_outlined,
  ),
  _LightingCatalogItem(
    '스탠드 조명',
    _LightingCategory.floor,
    Icons.lightbulb_outline_rounded,
  ),
  _LightingCatalogItem(
    '무드등',
    _LightingCategory.floor,
    Icons.nightlight_outlined,
  ),
  _LightingCatalogItem(
    '간접 조명 라인',
    _LightingCategory.indirect,
    Icons.wb_incandescent_outlined,
  ),
];

/// 우측 "작업 환경 → 조명" Tab.
///
/// PROFESSIONAL WORKSPACE UI RESTRUCTURE WO §6/§8 — 조명 "기구"
/// 카탈로그(천장등/펜던트/스탠드/간접조명)를 위한 자리다. [FurnitureTab]과
/// 달리, 아직 실제 조명 asset/library나 3D 배치 backend가 전혀 없으므로
/// (§8 — "실제 asset/library가 없으면 mock 기능을 과도하게 만들지
/// 않는다") 배치·편집까지 흉내 내지 않는다 — 카테고리/썸네일을 수용할 수
/// 있는 구조만 만들고, 항목을 누르면 정직하게 "준비 중"만 안내한다.
class LightingTab extends StatefulWidget {
  const LightingTab({super.key});

  @override
  State<LightingTab> createState() => _LightingTabState();
}

class _LightingTabState extends State<LightingTab> {
  _LightingCategory _category = _LightingCategory.all;

  List<_LightingCatalogItem> get _visibleCatalog => _category == _LightingCategory.all
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
          '조명 카탈로그',
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
            itemCount: _LightingCategory.values.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final category = _LightingCategory.values[index];
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
