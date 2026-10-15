/// SS001 §5 / §9 — 모든 화면이 함께 쓰는 프로젝트 공통 데이터.
///
/// Project = projectInfo · sourceType · sourceData · recognitionData · userCorrections · cadData · isoData · renderData
///           · history · currentStage · saveState
///
/// - 단계별 데이터는 각자의 칸([SsStageData])에만 쓴다. 한 단계가 다른 단계 칸을 덮어쓰지 않는다.
/// - 원본(sourceData)은 한 번 정해지면 바뀌지 않는다(바꾸려면 새 프로젝트 — §5 "원본 데이터는 항상 보존").
/// - 단계 데이터는 고칠 때마다 revision이 오르고, 그 데이터가 어느 앞 단계의 몇 번째 revision으로 만들어졌는지(basedOn)를
///   기억한다. 앞 단계가 더 새로우면 "업데이트 필요" 상태가 된다(§9). 실제 재생성은 각 Work Order에서.
/// - 실제 엔진 데이터(CAD 도면, 평면도 기하 등)는 각 화면의 기존 모델을 그대로 쓰고, 여기에는 JSON으로 담는다
///   (기존 엔진을 바꾸지 않는다 — §14).
library;

import 'ss_stage.dart';

/// 프로젝트 데이터 칸(단계별).
enum SsDataSlot {
  sourceData('원본'),
  recognitionData('AI 인식'),
  userCorrections('사용자 수정'),
  cadData('CAD'),
  isoData('3D ISO'),
  renderData('렌더링');

  const SsDataSlot(this.label);
  final String label;
}

/// 어느 칸이 어느 칸을 바탕으로 만들어지는가(앞 단계가 바뀌면 뒤 단계가 낡는다).
abstract final class SsDataDependencies {
  static const Map<SsDataSlot, List<SsDataSlot>> upstream = {
    SsDataSlot.recognitionData: [SsDataSlot.sourceData],
    SsDataSlot.userCorrections: [SsDataSlot.recognitionData],
    SsDataSlot.cadData: [SsDataSlot.userCorrections, SsDataSlot.recognitionData, SsDataSlot.sourceData],
    SsDataSlot.isoData: [SsDataSlot.cadData],
    SsDataSlot.renderData: [SsDataSlot.isoData, SsDataSlot.sourceData],
  };

  /// 사용자에게 보일 "업데이트 필요" 문구(§9 예시와 같은 말).
  static String staleMessage(SsDataSlot stale, SsDataSlot changed) => switch ((changed, stale)) {
    (SsDataSlot.userCorrections || SsDataSlot.recognitionData || SsDataSlot.sourceData, SsDataSlot.cadData) => '평면도가 변경되었습니다. CAD를 업데이트해야 합니다.',
    (SsDataSlot.cadData, SsDataSlot.isoData) => 'CAD가 변경되었습니다. 3D 모델을 업데이트해야 합니다.',
    (SsDataSlot.isoData, SsDataSlot.renderData) => '3D 모델이 변경되었습니다. 렌더링을 다시 해야 합니다.',
    (SsDataSlot.sourceData, SsDataSlot.renderData) => '원본 이미지가 변경되었습니다. 렌더링을 다시 해야 합니다.',
    _ => '${changed.label}이(가) 변경되었습니다. ${stale.label}을(를) 업데이트해야 합니다.',
  };
}

/// 한 단계 칸의 데이터와 그 내력.
class SsStageData {
  const SsStageData({required this.revision, required this.payload, required this.updatedAt, this.basedOn = const {}});

  /// 이 칸을 고친 횟수(처음 1).
  final int revision;

  /// 엔진별 데이터(JSON 가능 값). SS001은 형식을 정하지 않는다 — 각 Work Order가 자기 칸의 형식을 정한다.
  final Map<String, Object?> payload;
  final DateTime updatedAt;

  /// 만들 때 쓴 앞 칸들의 revision.
  final Map<SsDataSlot, int> basedOn;

  Map<String, Object?> toJson() => {
    'revision': revision,
    'payload': payload,
    'updatedAt': updatedAt.toIso8601String(),
    'basedOn': {for (final e in basedOn.entries) e.key.name: e.value},
  };

  static SsStageData? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final rev = j['revision'];
    final payload = j['payload'];
    final at = DateTime.tryParse('${j['updatedAt']}');
    if (rev is! int || payload is! Map || at == null) return null;
    final based = <SsDataSlot, int>{};
    final b = j['basedOn'];
    if (b is Map) {
      for (final e in b.entries) {
        final slot = SsDataSlot.values.where((s) => s.name == e.key).firstOrNull;
        if (slot != null && e.value is int) based[slot] = e.value as int;
      }
    }
    return SsStageData(revision: rev, payload: Map<String, Object?>.from(payload), updatedAt: at, basedOn: based);
  }
}

/// SS001 §6 — 공통 저장 상태.
enum SsSaveState {
  idle('저장할 변경 없음'),
  dirty('저장 대기'),
  saving('저장 중'),
  saved('저장 완료'),
  failed('저장 실패 — 다시 시도');

  const SsSaveState(this.label);
  final String label;
}

/// 작업 이력 한 줄(§7: 원본 → AI 결과 → 사용자 수정 1..n → 최종).
class SsHistoryEntry {
  const SsHistoryEntry({required this.at, required this.slot, required this.revision, required this.label});
  final DateTime at;
  final SsDataSlot slot;
  final int revision;
  final String label;

  Map<String, Object?> toJson() => {'at': at.toIso8601String(), 'slot': slot.name, 'revision': revision, 'label': label};

  static SsHistoryEntry? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final at = DateTime.tryParse('${j['at']}');
    final slot = SsDataSlot.values.where((s) => s.name == j['slot']).firstOrNull;
    final rev = j['revision'];
    if (at == null || slot == null || rev is! int) return null;
    return SsHistoryEntry(at: at, slot: slot, revision: rev, label: '${j['label'] ?? ''}');
  }
}

class SsProjectInfo {
  const SsProjectInfo({required this.id, required this.name, required this.createdAt});
  final String id;
  final String name;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'createdAt': createdAt.toIso8601String()};
}

/// 프로젝트 하나. 바꿀 때는 새 객체를 돌려준다(이전 상태가 그대로 남아 History/복원에 쓸 수 있다).
class SsProject {
  const SsProject({
    required this.info,
    required this.sourceType,
    required this.currentStage,
    this.data = const {},
    this.history = const [],
    this.updatedAt,
    this.schemaVersion = kSsProjectSchema,
  });

  /// 새 프로젝트 — 시작 방식에 맞는 첫 작업 단계에서 시작한다.
  factory SsProject.create({required String id, required String name, required SsSourceType sourceType, DateTime? now}) {
    final t = now ?? DateTime.now();
    return SsProject(info: SsProjectInfo(id: id, name: name, createdAt: t), sourceType: sourceType, currentStage: SsFlows.firstStage(sourceType), updatedAt: t);
  }

  final SsProjectInfo info;
  final SsSourceType sourceType;
  final SsStage currentStage;
  final Map<SsDataSlot, SsStageData> data;
  final List<SsHistoryEntry> history;
  final DateTime? updatedAt;
  final int schemaVersion;

  SsStageData? operator [](SsDataSlot slot) => data[slot];

  /// 원본은 한 번만 정한다 — 이미 있으면 [StateError](원본 보존, §5).
  SsProject withSource(Map<String, Object?> payload, {String label = '원본', DateTime? now}) {
    if (data.containsKey(SsDataSlot.sourceData)) throw StateError('원본 데이터는 바꿀 수 없습니다(새 프로젝트로 시작하세요)');
    return _write(SsDataSlot.sourceData, payload, label: label, now: now);
  }

  /// 원본이 아닌 단계 칸에 쓴다. 지금 앞 칸들의 revision을 함께 기록한다.
  SsProject withStageData(SsDataSlot slot, Map<String, Object?> payload, {required String label, DateTime? now}) {
    if (slot == SsDataSlot.sourceData) return withSource(payload, label: label, now: now);
    return _write(slot, payload, label: label, now: now);
  }

  SsProject _write(SsDataSlot slot, Map<String, Object?> payload, {required String label, DateTime? now}) {
    final t = now ?? DateTime.now();
    final rev = (data[slot]?.revision ?? 0) + 1;
    final based = <SsDataSlot, int>{
      for (final up in SsDataDependencies.upstream[slot] ?? const <SsDataSlot>[])
        if (data[up] != null) up: data[up]!.revision,
    };
    return copyWith(
      data: {...data, slot: SsStageData(revision: rev, payload: Map.unmodifiable(payload), updatedAt: t, basedOn: based)},
      history: [...history, SsHistoryEntry(at: t, slot: slot, revision: rev, label: label)],
      updatedAt: t,
    );
  }

  /// 작업 단계 이동 — 이 프로젝트 FLOW의 단계만(다른 FLOW 단계로 잘못 가지 않게).
  SsProject moveTo(SsStage stage, {DateTime? now}) {
    if (!SsFlows.belongs(sourceType, stage)) throw ArgumentError('${stage.title}은(는) ${sourceType.label} 흐름의 단계가 아닙니다');
    return copyWith(currentStage: stage, updatedAt: now ?? DateTime.now());
  }

  /// 앞 단계가 더 새로워져 다시 만들어야 하는 칸과 그 이유(§9).
  List<SsStaleNotice> staleNotices() {
    final out = <SsStaleNotice>[];
    for (final e in data.entries) {
      for (final up in SsDataDependencies.upstream[e.key] ?? const <SsDataSlot>[]) {
        final upData = data[up];
        if (upData == null) continue;
        final usedRev = e.value.basedOn[up];
        if (usedRev == null || usedRev < upData.revision) {
          out.add(SsStaleNotice(stale: e.key, changed: up, message: SsDataDependencies.staleMessage(e.key, up)));
          break;
        }
      }
    }
    return out;
  }

  SsProject copyWith({SsStage? currentStage, Map<SsDataSlot, SsStageData>? data, List<SsHistoryEntry>? history, DateTime? updatedAt}) => SsProject(
    info: info,
    sourceType: sourceType,
    currentStage: currentStage ?? this.currentStage,
    data: data ?? this.data,
    history: history ?? this.history,
    updatedAt: updatedAt ?? this.updatedAt,
    schemaVersion: schemaVersion,
  );

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'projectInfo': info.toJson(),
    'sourceType': sourceType.name,
    'currentStage': currentStage.name,
    'updatedAt': updatedAt?.toIso8601String(),
    for (final slot in SsDataSlot.values) slot.name: data[slot]?.toJson(),
    'history': [for (final h in history) h.toJson()],
  };

  /// 저장된 JSON에서 — 깨졌으면 null(호출부가 마지막 정상 저장본으로 돌아간다).
  static SsProject? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final infoJ = j['projectInfo'];
    if (infoJ is! Map) return null;
    final id = infoJ['id'], name = infoJ['name'];
    final created = DateTime.tryParse('${infoJ['createdAt']}');
    final type = SsSourceType.values.where((s) => s.name == j['sourceType']).firstOrNull;
    final stage = SsStage.fromName(j['currentStage'] as String?);
    if (id is! String || name is! String || created == null || type == null || stage == null) return null;
    final data = <SsDataSlot, SsStageData>{};
    for (final slot in SsDataSlot.values) {
      final d = SsStageData.tryFromJson(j[slot.name]);
      if (d != null) data[slot] = d;
    }
    final hist = j['history'];
    return SsProject(
      info: SsProjectInfo(id: id, name: name, createdAt: created),
      sourceType: type,
      currentStage: stage,
      data: data,
      history: hist is List ? [for (final h in hist) ?SsHistoryEntry.tryFromJson(h)] : const [],
      updatedAt: DateTime.tryParse('${j['updatedAt']}'),
      schemaVersion: j['schemaVersion'] is int ? j['schemaVersion'] as int : kSsProjectSchema,
    );
  }
}

/// 프로젝트 저장 형식의 버전 — 나중에 칸 형식이 바뀌면 올리고 읽을 때 변환한다.
const int kSsProjectSchema = 1;

class SsStaleNotice {
  const SsStaleNotice({required this.stale, required this.changed, required this.message});
  final SsDataSlot stale;
  final SsDataSlot changed;
  final String message;
}
