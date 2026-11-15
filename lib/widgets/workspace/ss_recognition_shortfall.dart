/// SS-수정004 — 평면도는 정상으로 올라갔지만 인식 결과가 부족할 때(방 0개, 요소가 거의
/// 없음, 분석 서비스 경고가 있음) 업로드 실패처럼 보이지 않도록, 무엇이 부족한지·왜
/// 그런지·다음에 무엇을 할지를 한 상자로 보여준다.
///
/// - 가짜 인식 결과나 가짜 성공을 만들지 않는다: 실제 개수와 실제 경고만 보여준다.
/// - "왜 그런지" 한 줄은 분석 서비스가 실제로 AI 인식을 부르는지
///   ([FloorPlanAnalysisService.aiRecognitionConnected])로 정한다.
library;

import 'package:flutter/material.dart';

import '../../models/floor_plan_geometry.dart';
import '../../services/ss_recognition_summary.dart';
import '../../theme/ss_master_theme.dart';

/// 인식 결과가 부족하다는 판단과 그 안내 문구.
class SsRecognitionShortfall {
  const SsRecognitionShortfall({required this.headline, required this.reason, this.engineDetail, this.warnings = const []});

  /// 무엇이 부족한지(예: "방을 찾지 못했습니다 · 벽 3개만 인식").
  final String headline;

  /// 왜 그런지 한 줄.
  final String reason;

  /// 기본 인식 엔진이 실제로 찾은 후보 개수(있을 때만).
  final String? engineDetail;

  /// 분석 서비스·공간 해석이 남긴 실제 경고.
  final List<String> warnings;

  /// 이 개수 미만이면 "요소가 거의 없음"으로 본다.
  static const int fewElementsThreshold = 3;

  /// 방 하나를 닫으려면 벽이 최소 이만큼 필요하다 — 이보다 적으면 "벽 N개만 인식"으로 알린다.
  static const int minWallsForRoom = 4;

  /// CAD 변환 버튼이 비활성일 때 보여줄 이유.
  static const String cadDisabledReason = '벽이 인식되어야 CAD로 변환할 수 있습니다 — “직접 수정하기”에서 벽을 추가하세요.';

  /// CAD 변환은 벽이 1개 이상 있어야 한다(사용자가 직접 벽을 추가하면 다시 켜진다).
  static bool canConvertToCad(SsRecognitionSummary summary) => (summary.counts[SsRecognitionLayer.wall] ?? 0) > 0;

  /// "왜 그런지" 한 줄 — AI 인식 연결 여부(실제 서비스 값)에 따라 사실대로.
  static String reasonFor({required bool aiRecognitionConnected}) => aiRecognitionConnected
      ? 'AI 인식을 거쳤지만 이 도면에서 요소를 충분히 찾지 못했습니다.'
      : '현재는 기본 인식 엔진만 사용 중이라(AI 인식 미연결) 복잡한 도면을 읽지 못할 수 있습니다.';

  /// 인식 결과가 부족하면 안내를, 충분하면 null을 돌려준다.
  ///
  /// [summary]가 null이면 인식 자체가 구조를 찾지 못한 경우(요소 0개)다. [warnings]는
  /// 분석 서비스 경고로, 하나라도 있으면 부족으로 본다. [notes]는 함께 보여줄 참고
  /// 안내(공간 해석 경고 등)로, 그것만으로는 부족 판단을 하지 않는다.
  static SsRecognitionShortfall? evaluate({
    required SsRecognitionSummary? summary,
    required bool aiRecognitionConnected,
    FloorPlanAnalysisResult? engineResult,
    List<String> warnings = const [],
    List<String> notes = const [],
  }) {
    final serviceWarnings = <String>{for (final w in warnings) if (w.trim().isNotEmpty) w.trim()};
    final rooms = summary?.counts[SsRecognitionLayer.space] ?? 0;
    final walls = summary?.counts[SsRecognitionLayer.wall] ?? 0;
    final openings = (summary?.counts[SsRecognitionLayer.door] ?? 0) + (summary?.counts[SsRecognitionLayer.window] ?? 0);
    final total = summary?.totalCount ?? 0;

    final insufficient = summary == null || rooms == 0 || total < fewElementsThreshold || serviceWarnings.isNotEmpty;
    if (!insufficient) return null;

    final parts = <String>[];
    if (rooms == 0) parts.add('방을 찾지 못했습니다');
    if (walls == 0) {
      parts.add('벽을 찾지 못했습니다');
    } else if (walls < minWallsForRoom) {
      parts.add('벽 $walls개만 인식');
    }
    if (openings == 0) parts.add('문/창을 찾지 못했습니다');
    if (parts.isEmpty) parts.add('확인이 필요한 경고가 있습니다');

    final allWarnings = <String>{...serviceWarnings, for (final n in notes) if (n.trim().isNotEmpty) n.trim()}.toList();

    return SsRecognitionShortfall(
      headline: parts.join(' · '),
      reason: reasonFor(aiRecognitionConnected: aiRecognitionConnected),
      engineDetail: engineResult == null
          ? null
          : '기본 인식 엔진 결과: 벽 ${engineResult.walls.length} · 방 ${engineResult.rooms.length} · 문/창 ${engineResult.openings.length}',
      warnings: allWarnings,
    );
  }
}

/// 인식 결과 부족 안내 상자 — 무엇이 부족한지 + 왜 + 다음 행동 버튼(다시 인식 / 다른 파일 선택 / 직접 수정하기).
class SsRecognitionShortfallNotice extends StatelessWidget {
  const SsRecognitionShortfallNotice({
    super.key,
    required this.shortfall,
    required this.busy,
    this.onRetry,
    this.onPickOther,
    this.onDirectEdit,
  });

  final SsRecognitionShortfall shortfall;

  /// 분석이 실행 중이면 true — 버튼을 모두 막아 중복 실행을 막는다.
  final bool busy;
  final VoidCallback? onRetry;
  final VoidCallback? onPickOther;
  final VoidCallback? onDirectEdit;

  static const Color _accent = Color(0xFFFBBF24);

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('ssRecognitionShortfallNotice'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.12),
        border: Border.all(color: _accent),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, color: _accent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  shortfall.headline,
                  key: const Key('ssShortfallHeadline'),
                  style: const TextStyle(color: _accent, fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(shortfall.reason, key: const Key('ssShortfallReason'), style: const TextStyle(color: SsMasterTheme.textPrimary, fontSize: 12)),
          if (shortfall.engineDetail != null) ...[
            const SizedBox(height: 4),
            Text(
              shortfall.engineDetail!,
              key: const Key('ssShortfallEngineDetail'),
              style: const TextStyle(color: SsMasterTheme.textSecondary, fontSize: 12),
            ),
          ],
          for (var i = 0; i < shortfall.warnings.length; i++) ...[
            const SizedBox(height: 4),
            Text(
              '• ${shortfall.warnings[i]}',
              key: Key('ssShortfallWarning_$i'),
              style: const TextStyle(color: SsMasterTheme.textSecondary, fontSize: 12),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                key: const Key('ssShortfallRetry'),
                onPressed: busy ? null : onRetry,
                icon: const Icon(Icons.refresh, size: 16),
                label: Text(busy ? '인식 중…' : '다시 인식'),
              ),
              OutlinedButton.icon(
                key: const Key('ssShortfallPickOther'),
                onPressed: busy ? null : onPickOther,
                icon: const Icon(Icons.upload_file, size: 16),
                label: const Text('다른 파일 선택'),
              ),
              ElevatedButton.icon(
                key: const Key('ssShortfallDirectEdit'),
                onPressed: busy ? null : onDirectEdit,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('직접 수정하기'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
