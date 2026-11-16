/// SS-수정003 4차 — 작업 화면 머리글(MASTER 05)의 ✎ 버튼으로 프로젝트 이름을 바꾼다.
///
/// - 이름 검사는 프로젝트 생성과 같은 규칙([SsProjectSummary.validateName] — 빈 이름 거부, 30자 이내).
/// - 저장은 저장소의 최신 프로젝트에서 이름 칸만 바꿔([SsProject.withName]) 다시 저장한다(다른 데이터·형식 그대로).
/// - 바꾼 뒤 [SsProjectRenames.revision]을 올려, 좌측 "진행 중인 프로젝트" 목록 등이 바로 다시 읽게 한다.
library;

import 'package:flutter/material.dart';

import 'package:ason_space/core/ss_project.dart';
import 'package:ason_space/core/ss_project_store.dart';
import 'package:ason_space/core/ss_project_summary.dart';
import 'package:ason_space/theme/ss_master_theme.dart';

/// 프로젝트 이름이 바뀌었음을 알리는 신호(목록 화면이 듣고 다시 읽는다).
abstract final class SsProjectRenames {
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void notifyRenamed() => revision.value++;
}

/// 저장소의 프로젝트 이름을 바꿔 저장한다. 이름이 규칙에 맞지 않으면 [ArgumentError],
/// 프로젝트가 없으면 null. 저장 실패는 저장소 예외를 그대로 던진다(호출부가 일반 실패로 알린다).
Future<SsProject?> renameSsProject(SsProjectStore store, String projectId, String rawName) async {
  final problem = SsProjectSummary.validateName(rawName);
  if (problem != null) throw ArgumentError.value(rawName, 'rawName', problem);
  final latest = await store.load(projectId);
  if (latest == null) return null;
  final renamed = latest.withName(rawName.trim());
  await store.save(renamed);
  SsProjectRenames.notifyRenamed();
  return renamed;
}

/// 이름 바꾸기 창 — 저장을 누르면 검사를 통과한 새 이름(앞뒤 공백 제거), 취소하면 null.
Future<String?> showSsProjectRenameDialog(BuildContext context, {required String initialName}) {
  return showDialog<String>(context: context, builder: (_) => SsProjectRenameDialog(initialName: initialName));
}

class SsProjectRenameDialog extends StatefulWidget {
  const SsProjectRenameDialog({super.key, required this.initialName});
  final String initialName;

  @override
  State<SsProjectRenameDialog> createState() => _SsProjectRenameDialogState();
}

class _SsProjectRenameDialogState extends State<SsProjectRenameDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialName);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final problem = SsProjectSummary.validateName(_controller.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('ssProjectRenameDialog'),
      backgroundColor: SsMasterTheme.panel,
      title: const Text('프로젝트 이름 바꾸기', style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 360,
        child: TextField(
          key: const Key('ssProjectRenameField'),
          controller: _controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            hintText: '프로젝트 이름',
            hintStyle: const TextStyle(color: SsMasterTheme.textMuted),
            helperText: '${SsProjectSummary.maxNameLength}자 이내',
            helperStyle: const TextStyle(color: SsMasterTheme.textMuted),
            errorText: _error,
          ),
        ),
      ),
      actions: [
        TextButton(key: const Key('ssProjectRenameCancel'), onPressed: () => Navigator.of(context).pop(), child: const Text('취소')),
        FilledButton(
          key: const Key('ssProjectRenameSave'),
          style: FilledButton.styleFrom(backgroundColor: SsMasterTheme.neonBlue),
          onPressed: _submit,
          child: const Text('저장'),
        ),
      ],
    );
  }
}
