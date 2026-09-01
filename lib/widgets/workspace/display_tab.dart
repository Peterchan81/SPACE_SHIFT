import 'package:flutter/material.dart';

import '../../theme/space_shift_colors.dart';

/// 우측 "작업 환경 → 디스플레이" Tab.
///
/// 캔버스에 무엇을 표시할지(그리드/치수/마커/조명 프리뷰)를 조절하는
/// 화면 표시 설정. 실제 3D 렌더 엔진 연동은 이번 범위 밖이므로, 값 자체는
/// 로컬 상태로 토글되는 UI까지만 제공한다(WO 12-2 — 조명 탭은 별도로
/// 두지 않고 이 안의 옵션으로 흡수).
class DisplayTab extends StatefulWidget {
  const DisplayTab({super.key});

  @override
  State<DisplayTab> createState() => _DisplayTabState();
}

enum _LightingPreset { day, evening, studio }

extension on _LightingPreset {
  String get label => switch (this) {
    _LightingPreset.day => '주간',
    _LightingPreset.evening => '저녁',
    _LightingPreset.studio => '스튜디오',
  };

  IconData get icon => switch (this) {
    _LightingPreset.day => Icons.wb_sunny_outlined,
    _LightingPreset.evening => Icons.nights_stay_outlined,
    _LightingPreset.studio => Icons.highlight_outlined,
  };
}

class _DisplayTabState extends State<DisplayTab> {
  bool _showGrid = true;
  bool _showDimensions = true;
  bool _showMarkers = true;
  bool _showHiddenGhost = false;
  double _renderQuality = 0.6;
  _LightingPreset _lighting = _LightingPreset.day;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Card(
          title: '캔버스 표시',
          child: Column(
            children: [
              _ToggleRow(
                label: '그리드',
                value: _showGrid,
                onChanged: (value) => setState(() => _showGrid = value),
              ),
              _ToggleRow(
                label: '치수 라벨',
                value: _showDimensions,
                onChanged: (value) => setState(() => _showDimensions = value),
              ),
              _ToggleRow(
                label: '작업 마커',
                value: _showMarkers,
                onChanged: (value) => setState(() => _showMarkers = value),
              ),
              _ToggleRow(
                label: '숨긴 항목 반투명 표시',
                value: _showHiddenGhost,
                onChanged: (value) => setState(() => _showHiddenGhost = value),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Card(
          title: '조명',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in _LightingPreset.values)
                ChoiceChip(
                  label: Text(
                    preset.label,
                    style: const TextStyle(fontSize: 12),
                  ),
                  avatar: Icon(preset.icon, size: 15),
                  selected: preset == _lighting,
                  onSelected: (_) => setState(() => _lighting = preset),
                  selectedColor: SpaceShiftColors.textPrimary,
                  labelStyle: TextStyle(
                    color: preset == _lighting
                        ? Colors.white
                        : SpaceShiftColors.textPrimary,
                  ),
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: SpaceShiftColors.border),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Card(
          title: '렌더링 품질',
          child: Row(
            children: [
              const Text(
                '낮음',
                style: TextStyle(
                  fontSize: 12,
                  color: SpaceShiftColors.textSecondary,
                ),
              ),
              Expanded(
                child: Slider(
                  value: _renderQuality,
                  onChanged: (value) => setState(() => _renderQuality = value),
                ),
              ),
              const Text(
                '높음',
                style: TextStyle(
                  fontSize: 12,
                  color: SpaceShiftColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});

  final String title;
  final Widget child;

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
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: SpaceShiftColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: SpaceShiftColors.textPrimary,
            ),
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}
