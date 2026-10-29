/// SS004 — MASTER UI 4(프로젝트 생성). 프로젝트명 + 3가지 시작 방식(sourceType) 중 정확히 하나를 골라
/// 프로젝트를 만들고 저장한 뒤, 그 FLOW의 첫 작업 단계로 바로 이동한다.
/// 홈의 시작 카드가 Route 인자로 sourceType을 넘기면 그 방식이 미리 선택된다.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:ason_space/core/ss_project.dart';
import 'package:ason_space/core/ss_project_store.dart';
import 'package:ason_space/core/ss_project_summary.dart';
import 'package:ason_space/core/ss_router.dart';
import 'package:ason_space/core/ss_stage.dart';
import 'package:ason_space/screens/ss_source_type_visual.dart';
import 'package:ason_space/services/ss_project_store_provider.dart';
import 'package:ason_space/theme/ss_master_theme.dart';

class ProjectCreationScreen extends StatefulWidget {
  const ProjectCreationScreen({super.key, this.projectStore, this.initialSourceType});

  /// 테스트에서 주입. 없으면 앱 공용 [SsProjectStoreProvider] 저장소.
  final SsProjectStore? projectStore;

  /// 미리 선택할 시작 방식(없으면 Route 인자에서 읽는다).
  final SsSourceType? initialSourceType;

  @override
  State<ProjectCreationScreen> createState() => _ProjectCreationScreenState();
}

class _ProjectCreationScreenState extends State<ProjectCreationScreen> {
  final TextEditingController _name = TextEditingController();
  SsSourceType? _type;
  bool _argsRead = false;
  bool _saving = false;
  String? _nameError;
  String? _typeError;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _type = widget.initialSourceType;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_argsRead) return;
    _argsRead = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (_type == null && args is SsSourceType) _type = args;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _back() {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      unawaited(nav.pushReplacementNamed(SsStage.projectManagement.routeName));
    }
  }

  Future<void> _create() async {
    if (_saving) return;
    final nameErr = SsProjectSummary.validateName(_name.text);
    final type = _type;
    setState(() {
      _nameError = nameErr;
      _typeError = type == null ? '시작할 작업 방식을 하나 고르세요.' : null;
      _saveError = null;
    });
    if (nameErr != null || type == null) return;
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    try {
      final store = widget.projectStore ?? await SsProjectStoreProvider.instance.store();
      final now = DateTime.now();
      final project = SsProject.create(id: SsProjectSummary.newProjectId(now), name: _name.text.trim(), sourceType: type, now: now);
      await store.save(project);
      try {
        await store.setLastOpened(project.info.id);
      } catch (e, st) {
        debugPrint('setLastOpened 실패 (${e.runtimeType}): $e\n$st');
      }
      if (!mounted) return;
      unawaited(navigator.pushReplacementNamed(project.currentStage.routeName, arguments: project.info.id));
    } catch (e, st) {
      debugPrint('ProjectCreationScreen._create 실패 (${e.runtimeType}): $e\n$st');
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = e is FileSystemException
            ? '프로젝트 파일을 저장하지 못했습니다. 저장 공간을 확인한 뒤 다시 시도해주세요.'
            : '프로젝트를 만들지 못했습니다. 다시 시도해주세요.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const Key('ssCreateScroll'),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            key: const Key('ssCreateBack'),
            onPressed: _back,
            icon: const Icon(Icons.arrow_back, color: SsMasterTheme.textSecondary, size: 18),
            label: const Text('프로젝트', style: TextStyle(color: SsMasterTheme.textSecondary)),
          ),
          const SizedBox(height: 8),
          const SsStageHeader(stage: SsStage.projectCreation),
          const SizedBox(height: 20),
          _buildNamePanel(),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final cards = [
                for (var i = 0; i < SsSourceType.values.length; i++)
                  _SourceTypeCard(
                    type: SsSourceType.values[i],
                    number: (i + 1).toString().padLeft(2, '0'),
                    selected: _type == SsSourceType.values[i],
                    onTap: () => setState(() {
                      _type = SsSourceType.values[i];
                      _typeError = null;
                    }),
                  ),
              ];
              if (constraints.maxWidth < 760) {
                return Column(children: [for (final c in cards) Padding(padding: const EdgeInsets.only(bottom: 14), child: c)]);
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [for (final c in cards) Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 7), child: c))],
              );
            },
          ),
          if (_typeError != null) ...[
            const SizedBox(height: 10),
            Text(_typeError!, key: const Key('ssCreateTypeError'), style: const TextStyle(color: Colors.redAccent)),
          ],
          if (_saveError != null) ...[
            const SizedBox(height: 10),
            Text(_saveError!, key: const Key('ssCreateSaveError'), style: const TextStyle(color: Colors.redAccent)),
          ],
          const SizedBox(height: 24),
          Center(
            child: SizedBox(
              width: 520,
              height: 56,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: const Key('ssCreateSubmit'),
                  borderRadius: BorderRadius.circular(14),
                  onTap: _saving ? null : () => unawaited(_create()),
                  child: Ink(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: const LinearGradient(colors: [SsMasterTheme.neonBlue, SsMasterTheme.neonPurple, SsMasterTheme.neonPink]),
                    ),
                    child: Center(
                      child: Text(
                        _saving ? '프로젝트를 만드는 중…' : '프로젝트 생성하기  →',
                        style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNamePanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      decoration: BoxDecoration(color: SsMasterTheme.panel, borderRadius: BorderRadius.circular(16), border: Border.all(color: SsMasterTheme.panelBorder)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: SsMasterTheme.neonBlue.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.folder_open_outlined, color: Colors.white),
          ),
          const SizedBox(width: 14),
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('프로젝트명', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: TextField(
              key: const Key('ssCreateName'),
              controller: _name,
              maxLength: SsProjectSummary.maxNameLength,
              style: const TextStyle(color: Colors.white),
              onChanged: (_) {
                if (_nameError != null) setState(() => _nameError = null);
              },
              onSubmitted: (_) => unawaited(_create()),
              decoration: InputDecoration(
                isDense: true,
                hintText: '프로젝트 이름을 입력하세요. (예: 우리집 리모델링)',
                hintStyle: const TextStyle(color: SsMasterTheme.textMuted),
                counterStyle: const TextStyle(color: SsMasterTheme.textSecondary),
                errorText: _nameError,
                filled: true,
                fillColor: SsMasterTheme.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: SsMasterTheme.panelBorder)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: SsMasterTheme.panelBorder)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceTypeCard extends StatelessWidget {
  const _SourceTypeCard({required this.type, required this.number, required this.selected, required this.onTap});
  final SsSourceType type;
  final String number;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = SsSourceTypeVisual.color(type);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('ssCreateType_${type.name}'),
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.14) : SsMasterTheme.panel,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: selected ? color : SsMasterTheme.panelBorder, width: selected ? 2.5 : 1),
            boxShadow: selected ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 18)] : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(number, style: TextStyle(color: color, fontSize: 30, fontWeight: FontWeight.w800)),
                  const SizedBox(width: 12),
                  Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    child: Icon(SsSourceTypeVisual.icon(type), color: Colors.white, size: 26),
                  ),
                  const Spacer(),
                  if (selected) Icon(Icons.check_circle, key: Key('ssCreateTypeSelected_${type.name}'), color: color, size: 26),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(type.label, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        Text(SsSourceTypeVisual.description(type), style: const TextStyle(color: SsMasterTheme.textSecondary, fontSize: 13)),
                      ],
                    ),
                  ),
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: Icon(Icons.arrow_forward, color: color),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                height: 140,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [color.withValues(alpha: 0.3), SsMasterTheme.background],
                  ),
                ),
                child: Center(child: Icon(SsSourceTypeVisual.previewIcon(type), size: 64, color: Colors.white70)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.image_outlined, color: color),
                  const SizedBox(width: 10),
                  Expanded(child: Text(SsSourceTypeVisual.footer(type), style: const TextStyle(color: SsMasterTheme.textSecondary, fontSize: 12))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
