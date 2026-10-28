/// SS003 — MASTER UI 2(홈 화면). "3초 법칙": 화면에 들어오면 곧바로 3가지 시작 카드와
/// 최근/진행 중 프로젝트를 보여줘, 사용자가 무엇을 할 수 있는지 바로 알 수 있게 한다.
///
/// - 3가지 시작 카드(평면도 업로드·직접 그리기·이미지 변환) → 그 sourceType을 들고
///   프로젝트 생성 단계([SsStage.projectCreation], SS004)로 이동한다 — 그 화면이 아직
///   없어도(공통 "준비 중" 화면) 인자를 전달하는 연결 구조는 그대로 유지한다.
/// - 최근/진행 중 프로젝트는 [SsProjectStore]에서 읽는다(기본은 앱 공용
///   [SsProjectStoreProvider], 테스트는 [projectStore]로 주입). 프로젝트를 고르면 그
///   프로젝트에 저장된 현재 단계([SsProject.currentStage])로 그대로 이어서 연다(§6
///   자동저장/복원과 같은 생각 — "마지막 저장 단계 재개").
/// - AI 분석 미리보기는 실제 프로젝트에 AI 결과 데이터(ISO/렌더링)가 있으면 그
///   프로젝트로 연결하고, 없으면 자리만 유지한다(실제 썸네일 자산은 아직 없음).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/ss_project.dart';
import '../core/ss_project_store.dart';
import '../core/ss_router.dart';
import '../core/ss_stage.dart';
import '../services/ss_project_store_provider.dart';
import '../theme/ss_master_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.projectStore});

  /// 테스트에서 [MemorySsProjectStore] 등을 주입할 수 있게 한다. 지정하지 않으면
  /// 앱 전체가 공유하는 [SsProjectStoreProvider]의 저장소(기기 문서 폴더)를 쓴다.
  final SsProjectStore? projectStore;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _HomeLoad { loading, loaded, empty, error }

class _HomeScreenState extends State<HomeScreen> {
  _HomeLoad _state = _HomeLoad.loading;
  List<SsProject> _projects = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    // 처음 호출(initState)에서는 이미 _state가 loading이므로 build 중에 setState를
    // 부르지 않는다. "다시 시도"처럼 이미 빌드가 끝난 뒤 부르는 경우에만 로딩으로
    // 되돌린다.
    if (_state != _HomeLoad.loading) {
      setState(() => _state = _HomeLoad.loading);
    }
    try {
      final store = widget.projectStore ?? await SsProjectStoreProvider.instance.store();
      final ids = await store.list();
      final loaded = <SsProject>[];
      for (final id in ids) {
        final p = await store.load(id);
        if (p != null) loaded.add(p);
      }
      loaded.sort((a, b) => (b.updatedAt ?? b.info.createdAt).compareTo(a.updatedAt ?? a.info.createdAt));
      if (!mounted) return;
      setState(() {
        _projects = loaded;
        _state = loaded.isEmpty ? _HomeLoad.empty : _HomeLoad.loaded;
      });
    } catch (e, st) {
      // 로컬 파일 저장소 오류(권한/디스크 등)일 수도, 다른 예외일 수도 있다 — 원인을
      // "네트워크 오류"처럼 단정해 보여주지 않는다. 화면에는 일반 오류만 보여주고,
      // 실제 원인(타입 포함)은 개발자가 볼 수 있게 남긴다.
      debugPrint('HomeScreen._load 실패 (${e.runtimeType}): $e\n$st');
      if (!mounted) return;
      setState(() => _state = _HomeLoad.error);
    }
  }

  void _startFlow(SsSourceType sourceType) {
    Navigator.of(context).pushNamed(SsStage.projectCreation.routeName, arguments: sourceType);
  }

  void _resumeProject(SsProject project) {
    Navigator.of(context).pushNamed(project.currentStage.routeName, arguments: project.info.id);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const Key('ssHomeScroll'),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SsStageHeader(stage: SsStage.home),
          const SizedBox(height: 20),
          const _HeroBanner(),
          const SizedBox(height: 20),
          _StartCardsRow(onSelect: _startFlow),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final recent = _RecentProjectsSection(state: _state, projects: _projects, onRetry: () => unawaited(_load()), onOpen: _resumeProject);
              final ai = _AiPreviewSection(projects: _projects, onOpen: _resumeProject);
              if (constraints.maxWidth < 760) {
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [recent, const SizedBox(height: 20), ai]);
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Expanded(flex: 3, child: recent), const SizedBox(width: 20), Expanded(flex: 2, child: ai)],
              );
            },
          ),
          const SizedBox(height: 24),
          const _TipCardsRow(),
        ],
      ),
    );
  }
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('ssHomeHero'),
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0E2140), Color(0xFF1B2F55), Color(0xFF2A1E4D)],
        ),
        border: Border.all(color: SsMasterTheme.panelBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ShaderMask(
                shaderCallback: (bounds) => SsMasterTheme.rainbow.createShader(bounds),
                child: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 8),
              const Text(
                'SPACE SHIFT AI',
                style: TextStyle(color: SsMasterTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            '공간의 변화를 만드는\n새로운 가능성, SPACE SHIFT',
            style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800, height: 1.3),
          ),
          const SizedBox(height: 10),
          const Text('AI와 함께, 당신의 공간을 새롭게 디자인하세요.', style: TextStyle(color: SsMasterTheme.textSecondary, fontSize: 14)),
        ],
      ),
    );
  }
}

class _StartCardsRow extends StatelessWidget {
  const _StartCardsRow({required this.onSelect});
  final ValueChanged<SsSourceType> onSelect;

  static const _cards = [
    (type: SsSourceType.floorPlanUpload, icon: Icons.cloud_upload_outlined, title: '평면도 업로드', desc: '도면 이미지를 업로드하여\n공간을 분석하고 시작합니다.'),
    (type: SsSourceType.directDraw, icon: Icons.edit_outlined, title: '직접 그리기', desc: '간단한 도구로 직접 평면도를\n그리고 공간을 구성해보세요.'),
    (type: SsSourceType.imageTransform, icon: Icons.image_outlined, title: '이미지 변환', desc: '공간 사진을 업로드하여\n새로운 디자인을 만들어보세요.'),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cards = [
          for (final c in _cards) _StartCard(type: c.type, icon: c.icon, title: c.title, description: c.desc, onTap: () => onSelect(c.type)),
        ];
        if (constraints.maxWidth < 700) {
          return Column(children: [for (final c in cards) Padding(padding: const EdgeInsets.only(bottom: 12), child: c)]);
        }
        return Row(children: [for (final c in cards) Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: c))]);
      },
    );
  }
}

class _StartCard extends StatelessWidget {
  const _StartCard({required this.type, required this.icon, required this.title, required this.description, required this.onTap});
  final SsSourceType type;
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('ssHomeStartCard_${type.name}'),
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: SsMasterTheme.panel, borderRadius: BorderRadius.circular(16), border: Border.all(color: SsMasterTheme.panelBorder)),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: Icon(icon, color: SsMasterTheme.neonPurple),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(description, style: const TextStyle(color: SsMasterTheme.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward, color: SsMasterTheme.neonBlue, size: 18),
          ],
        ),
      ),
    );
  }
}

class _RecentProjectsSection extends StatelessWidget {
  const _RecentProjectsSection({required this.state, required this.projects, required this.onRetry, required this.onOpen});
  final _HomeLoad state;
  final List<SsProject> projects;
  final VoidCallback onRetry;
  final ValueChanged<SsProject> onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: SsMasterTheme.panel, borderRadius: BorderRadius.circular(16), border: Border.all(color: SsMasterTheme.panelBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('최근 프로젝트', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
              const Spacer(),
              TextButton(
                key: const Key('ssHomeProjectsSeeAll'),
                onPressed: () => Navigator.of(context).pushNamed(SsStage.projectManagement.routeName),
                child: const Text('전체보기 →', style: TextStyle(color: SsMasterTheme.neonBlue, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildBody(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (state) {
      case _HomeLoad.loading:
        // value를 고정해 두어(결정적 인디케이터) 끝없이 반복되는 애니메이션 컨트롤러가 생기지
        // 않게 한다 — 그렇지 않으면(불확정 스피너) 위젯 테스트의 pumpAndSettle()이 "더 이상
        // 예약된 프레임이 없는" 상태에 영원히 도달하지 못해 타임아웃한다.
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator(key: Key('ssHomeLoading'), color: SsMasterTheme.neonBlue, value: 0.3)),
        );
      case _HomeLoad.error:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              const Text(
                '프로젝트 정보를 불러오지 못했습니다. 다시 시도해주세요.',
                key: Key('ssHomeProjectsError'),
                textAlign: TextAlign.center,
                style: TextStyle(color: SsMasterTheme.textSecondary),
              ),
              const SizedBox(height: 10),
              OutlinedButton(key: const Key('ssHomeRetryButton'), onPressed: onRetry, child: const Text('다시 시도')),
            ],
          ),
        );
      case _HomeLoad.empty:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Text(
            '아직 프로젝트가 없습니다. 위 카드 중 하나를 선택해 첫 프로젝트를 시작해보세요.',
            key: Key('ssHomeEmptyProjects'),
            style: TextStyle(color: SsMasterTheme.textSecondary),
          ),
        );
      case _HomeLoad.loaded:
        return SizedBox(
          key: const Key('ssHomeRecentProjectsList'),
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: projects.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) => _ProjectCard(project: projects[i], onTap: () => onOpen(projects[i])),
          ),
        );
    }
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project, required this.onTap});
  final SsProject project;
  final VoidCallback onTap;

  bool get _isDone => SsFlows.next(project.sourceType, project.currentStage) == null;

  static String _formatDate(DateTime dt) => '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final updated = project.updatedAt ?? project.info.createdAt;
    return InkWell(
      key: Key('ssHomeProjectCard_${project.info.id}'),
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: SsMasterTheme.background, borderRadius: BorderRadius.circular(14), border: Border.all(color: SsMasterTheme.panelBorder)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (_isDone ? SsMasterTheme.neonCyan : SsMasterTheme.neonOrange).withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _isDone ? '완료' : '진행중',
                key: Key('ssHomeProjectStatus_${project.info.id}'),
                style: TextStyle(color: _isDone ? SsMasterTheme.neonCyan : SsMasterTheme.neonOrange, fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              project.info.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(project.sourceType.label, style: const TextStyle(color: SsMasterTheme.textMuted, fontSize: 11)),
            const Spacer(),
            Text(_formatDate(updated), style: const TextStyle(color: SsMasterTheme.textMuted, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _AiPreviewSection extends StatelessWidget {
  const _AiPreviewSection({required this.projects, required this.onOpen});
  final List<SsProject> projects;
  final ValueChanged<SsProject> onOpen;

  SsProject? get _withResult {
    for (final p in projects) {
      if (p[SsDataSlot.renderData] != null || p[SsDataSlot.isoData] != null) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final target = _withResult;
    return Container(
      key: const Key('ssHomeAiPreview'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: SsMasterTheme.panel, borderRadius: BorderRadius.circular(16), border: Border.all(color: SsMasterTheme.panelBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('AI 분석 미리보기', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
              const Spacer(),
              if (target != null)
                TextButton(
                  key: const Key('ssHomeAiPreviewOpen'),
                  onPressed: () => onOpen(target),
                  child: const Text('결과보기 →', style: TextStyle(color: SsMasterTheme.neonBlue, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 110,
            child: Center(
              child: Text(
                target == null
                    ? 'AI 분석 결과가 아직 없습니다.\n프로젝트를 진행하면 여기에 결과 미리보기가 연결됩니다.'
                    : '${target.info.name}의 AI 분석 결과를 확인할 수 있습니다.',
                key: const Key('ssHomeAiPreviewText'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: SsMasterTheme.textSecondary, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TipCardsRow extends StatelessWidget {
  const _TipCardsRow();

  static const _tips = [
    (icon: Icons.menu_book_outlined, title: '처음 사용하시나요?', desc: '간단한 가이드로 빠르게 시작해보세요.', cta: '가이드 보기 →'),
    (icon: Icons.lightbulb_outline, title: '오늘의 추천', desc: 'AI가 제안하는 인테리어 스타일을 확인해보세요.', cta: '추천 보기 →'),
    (icon: Icons.chat_bubble_outline, title: '공간 디자인 팁', desc: '더 좋은 결과를 위한 팁을 확인하세요.', cta: '팁 보기 →'),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cards = [for (final t in _tips) _TipCard(icon: t.icon, title: t.title, description: t.desc, cta: t.cta)];
        if (constraints.maxWidth < 760) {
          return Column(children: [for (final c in cards) Padding(padding: const EdgeInsets.only(bottom: 12), child: c)]);
        }
        return Row(children: [for (final c in cards) Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: c))]);
      },
    );
  }
}

class _TipCard extends StatelessWidget {
  const _TipCard({required this.icon, required this.title, required this.description, required this.cta});
  final IconData icon;
  final String title;
  final String description;
  final String cta;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: SsMasterTheme.panel, borderRadius: BorderRadius.circular(14), border: Border.all(color: SsMasterTheme.panelBorder)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: SsMasterTheme.neonCyan),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(description, style: const TextStyle(color: SsMasterTheme.textSecondary, fontSize: 12)),
                const SizedBox(height: 8),
                // 아직 실제로 연결된 기능(가이드/추천/팁 화면)이 없으므로 눌러도 동작하지
                // 않게 비활성으로만 둔다(가짜 동작을 만들지 않는다 — 도움말/알림
                // 아이콘과 같은 원칙, lib/core/ss_router.dart의 SsTopBar 참고).
                TextButton(onPressed: null, child: Text(cta)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
