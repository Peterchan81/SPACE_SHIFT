import 'package:flutter/material.dart';

import '../../theme/space_shift_colors.dart';

class _MaterialCatalogItem {
  const _MaterialCatalogItem(this.name, this.icon);
  final String name;
  final IconData icon;
}

const _catalog = [
  _MaterialCatalogItem('우드', Icons.forest_outlined),
  _MaterialCatalogItem('타일', Icons.grid_on_outlined),
  _MaterialCatalogItem('페인트', Icons.format_paint_outlined),
  _MaterialCatalogItem('벽지', Icons.wallpaper_outlined),
  _MaterialCatalogItem('석재', Icons.terrain_outlined),
  _MaterialCatalogItem('패브릭', Icons.checkroom_outlined),
  _MaterialCatalogItem('사용자 색상', Icons.palette_outlined),
];

/// 우측 "작업 환경 → 재질/색상" Tab.
///
/// PROFESSIONAL WORKSPACE UI RESTRUCTURE WO §7/§9 — 재질/색상은 "선택된
/// 벽/바닥/가구에 적용하는 property panel" 역할로 설계한다. 무엇이
/// 선택되어 있는지는 [selectionLabel](없으면 안내만)로 전달받는다. 실제
/// 재질 적용 backend(3D 표면에 텍스처를 입히는 기능)는 이번 WO 범위가
/// 아니므로(§12), 카테고리 구조만 갖추고 항목을 누르면 정직하게
/// "준비 중"만 안내한다 — 색을 실제로 바꾸는 척(가짜 미리보기 등)하지
/// 않는다.
class MaterialsTab extends StatelessWidget {
  const MaterialsTab({super.key, this.selectionLabel});

  final String? selectionLabel;

  void _showNotReady(BuildContext context, String name) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('"$name" 적용은 준비 중입니다. 곧 지원할 예정입니다.')));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: SpaceShiftColors.border),
          ),
          child: Text(
            selectionLabel != null
                ? '선택한 "$selectionLabel"에 적용할 재질/색상입니다.'
                : '벽·바닥·가구를 선택하면 그 대상에 적용할 재질/색상을 여기서 고를 수 '
                      '있습니다. 지금은 선택된 항목이 없습니다.',
            style: const TextStyle(
              fontSize: 12.5,
              color: SpaceShiftColors.textSecondary,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          '재질 종류',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: SpaceShiftColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.85,
          ),
          itemCount: _catalog.length,
          itemBuilder: (context, index) {
            final item = _catalog[index];
            return _MaterialCard(
              name: item.name,
              icon: item.icon,
              onTap: () => _showNotReady(context, item.name),
            );
          },
        ),
      ],
    );
  }
}

class _MaterialCard extends StatelessWidget {
  const _MaterialCard({required this.name, required this.icon, required this.onTap});

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
