/// SS001 §6 — 자동저장과 작업 복원.
///
/// - 저장은 "임시 파일에 쓰고 바꿔 넣기"로 한다(쓰는 도중 앱이 꺼져도 마지막 정상 파일이 남는다). 바꾸기 전 파일은 .bak로 남긴다.
/// - 읽을 때 본 파일이 깨졌으면 .bak(마지막 정상 저장본)으로 연다.
/// - [SsAutosaveController]는 변경을 모았다가 잠시 뒤 저장하고, 상태(저장 중/완료/실패)를 화면에 알린다. 실패하면 다시 시도할 수 있고,
///   그동안 메모리의 작업은 그대로다(AI·저장 실패로 작업을 잃지 않게 — §8).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'ss_project.dart';

/// 프로젝트 저장소 — 화면은 이 인터페이스만 쓴다(파일/메모리/나중에 Cloud).
abstract class SsProjectStore {
  Future<void> save(SsProject project);
  Future<SsProject?> load(String projectId);
  Future<List<String>> list();

  /// 마지막으로 연 프로젝트(앱을 다시 열면 이어서 — §6).
  Future<void> setLastOpened(String projectId);
  Future<String?> lastOpened();
}

/// 메모리 저장소(테스트·미리보기용).
class MemorySsProjectStore implements SsProjectStore {
  final Map<String, String> _files = {};
  String? _last;
  bool failNextSave = false;

  @override
  Future<void> save(SsProject project) async {
    if (failNextSave) {
      failNextSave = false;
      throw const FileSystemException('저장 실패(시험)');
    }
    _files[project.info.id] = jsonEncode(project.toJson());
  }

  @override
  Future<SsProject?> load(String projectId) async {
    final t = _files[projectId];
    return t == null ? null : SsProject.tryFromJson(jsonDecode(t));
  }

  @override
  Future<List<String>> list() async => _files.keys.toList();

  @override
  Future<void> setLastOpened(String projectId) async => _last = projectId;

  @override
  Future<String?> lastOpened() async => _last;
}

/// 파일 저장소 — 프로젝트마다 `<id>.json` + 직전 정상본 `<id>.json.bak`.
class FileSsProjectStore implements SsProjectStore {
  FileSsProjectStore(this.dir);

  /// 앱 문서 폴더 아래 `space_shift_projects`(path_provider로 정해서 넘긴다).
  final Directory dir;

  File _file(String id) => File('${dir.path}${Platform.pathSeparator}${_safe(id)}.json');
  static String _safe(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');

  @override
  Future<void> save(SsProject project) async {
    await dir.create(recursive: true);
    final f = _file(project.info.id);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(project.toJson()), flush: true);
    if (await f.exists()) {
      final bak = File('${f.path}.bak');
      if (await bak.exists()) await bak.delete();
      await f.rename(bak.path);
    }
    await tmp.rename(f.path);
  }

  @override
  Future<SsProject?> load(String projectId) async {
    final f = _file(projectId);
    for (final c in [f, File('${f.path}.bak')]) {
      try {
        if (!await c.exists()) continue;
        final p = SsProject.tryFromJson(jsonDecode(await c.readAsString()));
        if (p != null) return p;
      } catch (_) {
        // 깨진 파일 — 다음 후보(마지막 정상 저장본)로
      }
    }
    return null;
  }

  @override
  Future<List<String>> list() async {
    if (!await dir.exists()) return const [];
    return [
      for (final e in dir.listSync())
        if (e is File && e.path.endsWith('.json')) e.uri.pathSegments.last.replaceAll(RegExp(r'\.json$'), ''),
    ];
  }

  File get _lastFile => File('${dir.path}${Platform.pathSeparator}last_opened.txt');

  @override
  Future<void> setLastOpened(String projectId) async {
    await dir.create(recursive: true);
    await _lastFile.writeAsString(projectId, flush: true);
  }

  @override
  Future<String?> lastOpened() async {
    try {
      return await _lastFile.exists() ? (await _lastFile.readAsString()).trim() : null;
    } catch (_) {
      return null;
    }
  }
}

/// 열린 프로젝트 하나의 자동저장 — 바꿀 때마다 [update]를 부르면 [delay] 뒤 한 번 저장한다.
class SsAutosaveController extends ChangeNotifier {
  // ignore: prefer_initializing_formals — 이름 있는 인자(project)는 private 필드의 initializing formal로 쓸 수 없다.
  SsAutosaveController({required this.store, required SsProject project, this.delay = const Duration(milliseconds: 800)}) : _project = project;

  final SsProjectStore store;
  final Duration delay;
  SsProject _project;
  SsProject get project => _project;

  SsSaveState _state = SsSaveState.idle;
  SsSaveState get state => _state;
  Object? _lastError;
  Object? get lastError => _lastError;
  DateTime? _lastSavedAt;
  DateTime? get lastSavedAt => _lastSavedAt;
  Timer? _timer;
  bool _disposed = false;

  /// 이 프로젝트를 저장소에서 연다 — 마지막 정상 저장본에서 이어서(§6). 없으면 null.
  static Future<SsAutosaveController?> restore(SsProjectStore store, String projectId, {Duration delay = const Duration(milliseconds: 800)}) async {
    final p = await store.load(projectId);
    if (p == null) return null;
    await store.setLastOpened(projectId);
    return SsAutosaveController(store: store, project: p, delay: delay).._state = SsSaveState.saved;
  }

  /// 앱을 다시 열었을 때 마지막으로 작업한 프로젝트.
  static Future<SsAutosaveController?> restoreLast(SsProjectStore store, {Duration delay = const Duration(milliseconds: 800)}) async {
    final id = await store.lastOpened();
    return id == null ? null : restore(store, id, delay: delay);
  }

  void _set(SsSaveState s) {
    _state = s;
    if (!_disposed) notifyListeners();
  }

  /// 메모리의 작업을 바꾸고 자동저장을 예약한다(저장이 실패해도 메모리 작업은 그대로).
  void update(SsProject next) {
    _project = next;
    _set(SsSaveState.dirty);
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(saveNow()));
  }

  /// 지금 저장(화면을 떠날 때, "저장" 버튼, 다시 시도).
  Future<bool> saveNow() async {
    _timer?.cancel();
    _set(SsSaveState.saving);
    try {
      await store.save(_project);
      await store.setLastOpened(_project.info.id);
      _lastError = null;
      _lastSavedAt = DateTime.now();
      _set(SsSaveState.saved);
      return true;
    } catch (e) {
      _lastError = e;
      _set(SsSaveState.failed);
      return false;
    }
  }

  /// 저장 실패 뒤 "다시 시도".
  Future<bool> retry() => saveNow();

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
