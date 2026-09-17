import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/cad_floor_plan.dart';
import '../../models/floor_plan_geometry.dart';
import '../../theme/space_shift_colors.dart';

/// 우측 "작업 환경" 패널에서, 사용자 작업(WorkspaceTaskItem)이 아니라
/// CAD geometry(벽/공간/문·창)가 선택되었을 때 보여주는 탭.
///
/// 여기서 하는 일은 "도면 구조 보정"이다 — 사용자 인테리어 작업(벽지/
/// 타일 변경 등)과는 다른 개념이라 ①②③ 번호를 붙이지 않는다(WO 8번).
/// 벽 끝점 이동은 캔버스에서 직접 드래그하고, 이 탭은 삭제/실행취소/
/// "작업으로 추가" 같은 액션만 제공한다(WO 13번 — 별도 편집 툴바를
/// 중복 배치하지 않는다).
class CadStructureTab extends StatelessWidget {
  const CadStructureTab({
    super.key,
    required this.wall,
    required this.opening,
    required this.room,
    required this.scale,
    required this.sourceWidthPx,
    required this.sourceHeightPx,
    required this.canUndo,
    required this.onUndo,
    required this.onDelete,
    required this.onCreateWorkItem,
    this.onEditWallLengthMm,
    this.onEditOpeningWidthMm,
    this.onAddDoorToWall,
    this.onAddWindowToWall,
  });

  final CadWall? wall;
  final CadOpening? opening;
  final CadRoom? room;
  final FloorPlanScale? scale;

  final int sourceWidthPx;
  final int sourceHeightPx;

  final bool canUndo;
  final VoidCallback onUndo;
  final VoidCallback onDelete;
  final VoidCallback onCreateWorkItem;

  /// SS CAD TEST — CAD Editor WO. 선택된 벽의 실제 길이(mm)를 사용자가
  /// 직접 입력해 확정한다 — "치수 보정"(축척 자체를 바꾸는 것)과는
  /// 다르다: 이 값은 그 벽 하나의 geometry(끝점)만 바꾼다. scale이 아직
  /// 없으면(축척 미확정) mm를 계산할 근거가 없으므로 null로 두어 입력
  /// UI 자체를 숨긴다.
  final void Function(double newLengthMm)? onEditWallLengthMm;

  /// 선택된 문/창의 실제 폭(mm)을 사용자가 직접 입력해 확정한다.
  final void Function(double newWidthMm)? onEditOpeningWidthMm;

  /// CAD/DXF FIRST GOAL FINAL LIVE E2E WO §8 — 실제 실측도면 LIVE
  /// 검증에서 AI가 실제 문을 놓치는 경우(semantic 단계는 감지했으나
  /// pixel 근거 부족으로 최종 CadFloorPlan에서 탈락하는 경우 포함)가
  /// 확인됐고, 그때까지 이 화면에는 "이미 있는 문/창의 폭을 고치는"
  /// 기능만 있고 "선택한 벽에 새 문/창을 추가"하는 기능이 전혀 없었다
  /// — 즉 사용자가 놓친 문을 스스로 복구할 방법이 없었다. §8이 요구하는
  /// 최소 기능만 추가한다: 선택된 벽에 기본 폭 문/창 하나를 만드는
  /// 버튼(geometry는 [createOpeningOnWall], 새 판단 로직 없음). 벽이
  /// 선택되지 않았거나 호출부가 콜백을 안 주면(narrow 레이아웃 등)
  /// 버튼 자체를 숨긴다 — 새 대규모 CAD editor로 확대하지 않는다.
  final VoidCallback? onAddDoorToWall;
  final VoidCallback? onAddWindowToWall;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Card(title: '선택된 도면 요소', child: _buildBody()),
        const SizedBox(height: 16),
        _Card(
          title: '도면 보정',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (wall != null)
                const Text(
                  '캔버스에서 벽의 끝점(●)을 드래그하면 길이/위치를 조정할 수 있습니다.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: SpaceShiftColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: canUndo ? onUndo : null,
                      icon: const Icon(Icons.undo_rounded, size: 18),
                      label: const Text('실행 취소'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                        foregroundColor: SpaceShiftColors.textPrimary,
                        side: const BorderSide(color: SpaceShiftColors.border),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onDelete,
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        size: 18,
                        color: Colors.redAccent,
                      ),
                      label: const Text(
                        '삭제',
                        style: TextStyle(color: Colors.redAccent),
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                        side: const BorderSide(color: SpaceShiftColors.border),
                      ),
                    ),
                  ),
                ],
              ),
              if (wall != null &&
                  (onAddDoorToWall != null || onAddWindowToWall != null)) ...[
                const SizedBox(height: 10),
                const Text(
                  '이 벽에 AI가 놓친 문/창이 있으면 기본 폭으로 추가한 뒤, 위 캔버스에서 '
                  '위치를 옮기고 폭을 실제 치수로 고칠 수 있습니다.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: SpaceShiftColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (onAddDoorToWall != null)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onAddDoorToWall,
                          icon: const Icon(Icons.door_front_door_outlined, size: 18),
                          label: const Text('문 추가'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(44),
                            foregroundColor: SpaceShiftColors.textPrimary,
                            side: const BorderSide(color: SpaceShiftColors.border),
                          ),
                        ),
                      ),
                    if (onAddDoorToWall != null && onAddWindowToWall != null)
                      const SizedBox(width: 10),
                    if (onAddWindowToWall != null)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onAddWindowToWall,
                          icon: const Icon(Icons.window_outlined, size: 18),
                          label: const Text('창 추가'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(44),
                            foregroundColor: SpaceShiftColors.textPrimary,
                            side: const BorderSide(color: SpaceShiftColors.border),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Card(
          title: '사용자 작업으로 추가',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '이 도면 요소를 실제 인테리어 작업 대상으로 등록하면, 그때부터 '
                '작업 번호(①②③...)가 부여되고 작업 목록/우측 패널과 연동됩니다.',
                style: TextStyle(
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

  Widget _buildBody() {
    final wall = this.wall;
    if (wall != null) {
      final dxPx = (wall.end.x - wall.start.x) * sourceWidthPx;
      final dyPx = (wall.end.y - wall.start.y) * sourceHeightPx;
      final lengthPx = math.sqrt(dxPx * dxPx + dyPx * dyPx);
      final lengthMm = scale == null ? null : lengthPx * scale!.mmPerPixel;
      final diagonalPx = math.sqrt(
        sourceWidthPx * sourceWidthPx + sourceHeightPx * sourceHeightPx,
      );
      final thicknessMm = scale == null
          ? null
          : wall.thicknessNormalized * diagonalPx * scale!.mmPerPixel;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Row('geometry ID', wall.id),
          _Row('종류', wall.wallType == CadWallType.exterior ? '외벽' : '내벽'),
          _Row(
            '길이',
            lengthMm == null
                ? '미설정(축척 필요)'
                : '${lengthMm.toStringAsFixed(0)}mm',
          ),
          _Row(
            '두께',
            thicknessMm == null
                ? '미설정(축척 필요)'
                : '${thicknessMm.toStringAsFixed(0)}mm',
          ),
          _Row('신뢰도', '${(wall.confidence * 100).round()}%'),
          _Row('출처', _sourceLabel(wall.source)),
          if (wall.edited) _Row('상태', '사용자 보정됨'),
          if (onEditWallLengthMm != null)
            if (scale != null)
              _MmEditorRow(
                label: '실제 길이 직접 입력(mm)',
                initialValueMm: lengthMm,
                onApply: onEditWallLengthMm!,
              )
            else
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  '길이를 직접 입력하려면 먼저 "치수 보정"으로 축척을 확정해야 합니다.',
                  style: TextStyle(fontSize: 12, color: SpaceShiftColors.textSecondary),
                ),
              ),
        ],
      );
    }

    final opening = this.opening;
    if (opening != null) {
      final diagonalPx = math.sqrt(
        sourceWidthPx * sourceWidthPx + sourceHeightPx * sourceHeightPx,
      );
      final widthMm = scale == null ? null : opening.widthNormalized * diagonalPx * scale!.mmPerPixel;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Row('geometry ID', opening.id),
          _Row('종류', switch (opening.type) {
            OpeningType.door => '문 후보',
            OpeningType.window => '창 후보',
            OpeningType.unknown => '개구부 후보',
          }),
          _Row('폭', widthMm == null ? '미설정(축척 필요)' : '${widthMm.toStringAsFixed(0)}mm'),
          _Row('신뢰도', '${(opening.confidence * 100).round()}%'),
          const _Row('상태', '확인 필요'),
          if (onEditOpeningWidthMm != null && scale != null)
            _MmEditorRow(
              label: '실제 폭 직접 입력(mm)',
              initialValueMm: widthMm,
              onApply: onEditOpeningWidthMm!,
            ),
        ],
      );
    }

    final room = this.room;
    if (room != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Row('geometry ID', room.id),
          _Row('닫힘 여부', room.closed ? '닫힌 공간' : '미확정(보정 필요)'),
          _Row('신뢰도', '${(room.confidence * 100).round()}%'),
        ],
      );
    }

    return const Text(
      '선택된 도면 요소가 없습니다.',
      style: TextStyle(fontSize: 13, color: SpaceShiftColors.textSecondary),
    );
  }

  String _sourceLabel(CadElementSource source) => switch (source) {
    CadElementSource.analyzed => '자동 분석',
    CadElementSource.userEdited => '사용자 보정',
    CadElementSource.userCreated => '사용자 생성',
  };
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

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: SpaceShiftColors.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: SpaceShiftColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// SS CAD TEST — CAD Editor WO. mm 값 하나를 입력받아 [onApply]로 넘기는
/// 최소 입력줄 — 벽 길이/문·창 폭 편집에 공용으로 쓴다. 입력이 숫자가
/// 아니거나 0 이하면 조용히 무시한다(임의 값을 지어내 적용하지 않는다).
class _MmEditorRow extends StatefulWidget {
  const _MmEditorRow({
    required this.label,
    required this.initialValueMm,
    required this.onApply,
  });

  final String label;
  final double? initialValueMm;
  final void Function(double newValueMm) onApply;

  @override
  State<_MmEditorRow> createState() => _MmEditorRowState();
}

class _MmEditorRowState extends State<_MmEditorRow> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValueMm == null ? '' : widget.initialValueMm!.toStringAsFixed(0),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _apply() {
    final value = double.tryParse(_controller.text.trim());
    if (value == null || value <= 0) return;
    widget.onApply(value);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label,
            style: const TextStyle(fontSize: 12.5, color: SpaceShiftColors.textSecondary),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    isDense: true,
                    suffixText: 'mm',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  onSubmitted: (_) => _apply(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _apply,
                style: FilledButton.styleFrom(
                  backgroundColor: SpaceShiftColors.textPrimary,
                  minimumSize: const Size(64, 40),
                ),
                child: const Text('적용'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
