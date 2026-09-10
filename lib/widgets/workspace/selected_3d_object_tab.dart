import 'package:flutter/material.dart';

import '../../models/space_scene_v2.dart';
import '../../theme/space_shift_colors.dart';

/// WO092 §5/§7 — 실시간 3D(아이소/투시)에서 벽/바닥/천장을 탭해
/// 선택했을 때 보여주는 탭. [CadStructureTab]과 의도적으로 분리한다 —
/// 그쪽은 "도면 구조 보정"(geometry ID/신뢰도/출처 같은 분석 debug
/// 정보, 벽 끝점 드래그 안내)을 위한 화면이라, 사용자가 3D에서 벽을
/// 눌렀을 때 그 개발자 정보를 그대로 보여주면 §7의 "공간 번호/좌표/
/// debug CAD 정보는 사용자 화면에 표시하지 마라"를 정면으로 어긴다.
/// 이 탭은 오직 "지금 무엇을 선택했는지"와 "작업으로 추가" 버튼만
/// 보여주는 사용자용 화면이다.
class Selected3DObjectTab extends StatelessWidget {
  const Selected3DObjectTab({
    super.key,
    required this.kind,
    required this.onCreateWorkItem,
  });

  final SpaceElementKindV2 kind;
  final VoidCallback onCreateWorkItem;

  String get _label => switch (kind) {
    SpaceElementKindV2.ceiling => '천장',
    SpaceElementKindV2.wall => '벽',
    // WO099 §8/§9 — 가구가 새 선택 가능 종류로 추가됐다. 잘못 "바닥"으로
    // 표시되던 걸 바로잡는다(§9 "object type이 유지되어야 한다").
    SpaceElementKindV2.furniture => '가구',
    // WO102 §5/§9 — window frame/glass mesh가 이제 실제로 선택 가능한
    // object다(이전엔 [SpaceOpeningV2]가 렌더링되지 않아 이 kind가
    // 선택으로 온 적이 없었다 — 그래서 지금까지는 "바닥"으로 잘못
    // 떨어져도 드러나지 않았다).
    SpaceElementKindV2.opening => '창문',
    _ => '바닥',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
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
                '선택한 $_label',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: SpaceShiftColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '3D 화면에서 $_label을(를) 선택했습니다. 작업으로 추가하면 색상/재질/'
                '마감재를 바꿀 수 있고, 3D 화면에 바로 반영됩니다.',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: SpaceShiftColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onCreateWorkItem,
                  icon: const Icon(Icons.add_task_rounded, size: 18),
                  label: const Text('작업으로 추가'),
                  style: FilledButton.styleFrom(
                    backgroundColor: SpaceShiftColors.textPrimary,
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
