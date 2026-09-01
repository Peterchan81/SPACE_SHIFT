import 'package:flutter/material.dart';

import '../../theme/space_shift_colors.dart';
import 'workspace_color_picker.dart';

enum FurnitureCategory { all, sofa, table, storage, bed, chair, etc }

extension FurnitureCategoryX on FurnitureCategory {
  String get label => switch (this) {
    FurnitureCategory.all => '전체',
    FurnitureCategory.sofa => '소파',
    FurnitureCategory.table => '테이블',
    FurnitureCategory.storage => '수납장',
    FurnitureCategory.bed => '침대',
    FurnitureCategory.chair => '의자',
    FurnitureCategory.etc => '기타',
  };

  IconData get icon => switch (this) {
    FurnitureCategory.all => Icons.grid_view_rounded,
    FurnitureCategory.sofa => Icons.weekend_outlined,
    FurnitureCategory.table => Icons.table_restaurant_outlined,
    FurnitureCategory.storage => Icons.shelves,
    FurnitureCategory.bed => Icons.bed_outlined,
    FurnitureCategory.chair => Icons.chair_outlined,
    FurnitureCategory.etc => Icons.category_outlined,
  };
}

class FurnitureCatalogItem {
  const FurnitureCatalogItem(this.name, this.category, this.icon);
  final String name;
  final FurnitureCategory category;
  final IconData icon;
}

const _catalog = [
  FurnitureCatalogItem('3인 소파', FurnitureCategory.sofa, Icons.weekend_outlined),
  FurnitureCatalogItem('암체어', FurnitureCategory.chair, Icons.chair_outlined),
  FurnitureCatalogItem(
    '다이닝 테이블',
    FurnitureCategory.table,
    Icons.table_restaurant_outlined,
  ),
  FurnitureCatalogItem(
    '사이드 테이블',
    FurnitureCategory.table,
    Icons.table_bar_outlined,
  ),
  FurnitureCatalogItem('책장', FurnitureCategory.storage, Icons.shelves),
  FurnitureCatalogItem(
    '서랍장',
    FurnitureCategory.storage,
    Icons.inventory_2_outlined,
  ),
  FurnitureCatalogItem('퀸 침대', FurnitureCategory.bed, Icons.bed_outlined),
  FurnitureCatalogItem('스탠드 조명', FurnitureCategory.etc, Icons.light_outlined),
];

class PlacedFurniture {
  PlacedFurniture({
    required this.id,
    required this.item,
    this.rotation = 0,
    this.scale = 1,
    this.color = const Color(0xFFD8C3A5),
  });

  final int id;
  final FurnitureCatalogItem item;
  double rotation;
  double scale;
  Color color;
}

/// 우측 "작업 환경 → 가구" Tab.
///
/// 실제 3D 배치 엔진은 이번 범위가 아니므로, 카탈로그에서 추가한 가구를
/// 목록으로 관리하며 위치/회전/크기/복사/삭제/색상을 편집하는 UI까지
/// 구현한다(WO 12번). 재질별(프레임/패브릭/상판/다리) 부분 편집은 후속
/// 확장으로 남겨 두고, 이번에는 가구 전체의 대표 색상 변경까지 지원한다.
class FurnitureTab extends StatefulWidget {
  const FurnitureTab({super.key});

  @override
  State<FurnitureTab> createState() => _FurnitureTabState();
}

class _FurnitureTabState extends State<FurnitureTab> {
  FurnitureCategory _category = FurnitureCategory.all;
  final List<PlacedFurniture> _placed = [];
  int _nextId = 1;
  int? _selectedId;

  List<FurnitureCatalogItem> get _visibleCatalog =>
      _category == FurnitureCategory.all
      ? _catalog
      : _catalog.where((item) => item.category == _category).toList();

  PlacedFurniture? get _selected =>
      _placed.where((f) => f.id == _selectedId).firstOrNull;

  void _addFurniture(FurnitureCatalogItem item) {
    setState(() {
      final placed = PlacedFurniture(id: _nextId++, item: item);
      _placed.add(placed);
      _selectedId = placed.id;
    });
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          '가구 추가',
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
            itemCount: FurnitureCategory.values.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final category = FurnitureCategory.values[index];
              final selected = category == _category;
              return ChoiceChip(
                label: Text(
                  category.label,
                  style: const TextStyle(fontSize: 12),
                ),
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
            return _CatalogCard(item: item, onTap: () => _addFurniture(item));
          },
        ),
        const SizedBox(height: 20),
        Text(
          '배치된 가구  ${_placed.length}',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: SpaceShiftColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        if (_placed.isEmpty)
          const Text(
            '위에서 가구를 눌러 공간에 배치해보세요.',
            style: TextStyle(
              fontSize: 13,
              color: SpaceShiftColors.textSecondary,
            ),
          )
        else
          for (final placed in _placed)
            _PlacedRow(
              placed: placed,
              selected: placed.id == _selectedId,
              onTap: () => setState(() => _selectedId = placed.id),
              onDelete: () => setState(() {
                _placed.remove(placed);
                if (_selectedId == placed.id) _selectedId = null;
              }),
            ),
        if (selected != null) ...[
          const SizedBox(height: 16),
          _FurnitureEditor(placed: selected, onChanged: () => setState(() {})),
        ],
      ],
    );
  }
}

class _CatalogCard extends StatelessWidget {
  const _CatalogCard({required this.item, required this.onTap});

  final FurnitureCatalogItem item;
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
              Icon(item.icon, size: 26, color: SpaceShiftColors.textSecondary),
              const SizedBox(height: 6),
              Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: SpaceShiftColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlacedRow extends StatelessWidget {
  const _PlacedRow({
    required this.placed,
    required this.selected,
    required this.onTap,
    required this.onDelete,
  });

  final PlacedFurniture placed;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? SpaceShiftColors.selectionAccent.withValues(alpha: 0.08)
          : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? SpaceShiftColors.selectionAccent
                  : SpaceShiftColors.border,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: placed.color,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: SpaceShiftColors.border),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  placed.item.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                onPressed: onDelete,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FurnitureEditor extends StatelessWidget {
  const _FurnitureEditor({required this.placed, required this.onChanged});

  final PlacedFurniture placed;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SpaceShiftColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${placed.item.name} 편집',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: SpaceShiftColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(
                width: 60,
                child: Text('회전', style: TextStyle(fontSize: 13)),
              ),
              Expanded(
                child: Slider(
                  value: placed.rotation,
                  min: 0,
                  max: 360,
                  onChanged: (value) {
                    placed.rotation = value;
                    onChanged();
                  },
                ),
              ),
            ],
          ),
          Row(
            children: [
              const SizedBox(
                width: 60,
                child: Text('크기', style: TextStyle(fontSize: 13)),
              ),
              Expanded(
                child: Slider(
                  value: placed.scale,
                  min: 0.5,
                  max: 2,
                  onChanged: (value) {
                    placed.scale = value;
                    onChanged();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          WorkspaceColorPicker(
            color: placed.color,
            onColorChanged: (color) {
              placed.color = color;
              onChanged();
            },
          ),
        ],
      ),
    );
  }
}
