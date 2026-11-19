/// SS003 — MASTER UI 2(홈 화면). "3초 법칙": 화면에 들어오면 곧바로 3가지 시작 카드와
/// 최근/진행 중 프로젝트를 보여줘, 사용자가 무엇을 할 수 있는지 바로 알 수 있게 한다.
///
/// SS 수정 01 — MASTER 02 원본과 같은 구성:
/// - 콘텐츠 판(둥근 테두리 + 가장자리 네온 빛) 위쪽·오른쪽 끝까지 꽉 찬 배너(home_hero.png + 왼쪽 남색 그라데이션).
/// - 시작 카드 3개: 위 사진 + 아래 반투명 밝은 판, 경계에 걸친 큰 흰 원 아이콘, 오른쪽 흰 원 화살표.
/// - 최근 프로젝트(왼쪽 약 59%) 4칸 고정 — 번호는 작업 화면 머리말과 같은 순서([SsRecentProjects]).
///   썸네일은 그 프로젝트에 저장된 실제 이미지만(없으면 시작 방식 아이콘 자리 그림), 남는 칸은 점선 빈 칸.
/// - AI 분석 미리보기(오른쪽 약 41%) — 실제 결과가 없으면 예시 그림에 "예시" 표시(사용자 결과처럼 보이지 않게).
/// - 하단 안내 카드 3개(가이드·추천·팁) — 색이 채워진 알약 버튼. 추천은 AI 미연결이라 "예시" 표시.
/// - 넓고 충분히 높은 창에서는 스크롤 없이 한 화면, 그 밖에는 같은 구성으로 스크롤.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/ss_project.dart';
import '../core/ss_project_store.dart';
import '../core/ss_project_summary.dart';
import '../core/ss_recent_projects.dart';
import '../core/ss_stage.dart';
import '../services/ss_project_store_provider.dart';
import '../theme/ss_master_theme.dart';
import '../widgets/ss_keep_words_text.dart';
import '../widgets/ss_project_rename_dialog.dart';
import 'project_management_screen.dart' show SsDashedRRectPainter;
import 'ss_guide_screen.dart';
import 'ss_recommendation_screen.dart';
import 'ss_tips_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.projectStore});

  /// 테스트에서 [MemorySsProjectStore] 등을 주입할 수 있게 한다. 지정하지 않으면
  /// 앱 전체가 공유하는 [SsProjectStoreProvider]의 저장소(기기 문서 폴더)를 쓴다.
  final SsProjectStore? projectStore;

  /// MASTER 02 사진 자산(사용자 승인 — 새로 그리거나 바꾸지 않는다).
  static const String heroImageAsset = 'assets/images/home_hero.png';
  static const String uploadCardImageAsset = 'assets/images/home_card_upload.png';
  static const String drawCardImageAsset = 'assets/images/home_card_draw.png';
  static const String imageCardImageAsset = 'assets/images/home_card_image.png';

  /// AI 분석 미리보기 예시 그림(MASTER 02에서 잘라낸 것) — 실제 결과가 없을 때만, "예시" 표시와 함께.
  static const String aiPlanExampleAsset = 'assets/images/home2_ai_plan_example.png';
  static const String ai3dExampleAsset = 'assets/images/home2_ai_3d_example.png';

  /// 스크롤 없이 한 화면에 나누는 최소 콘텐츠 판 폭.
  static const double fitMinWidth = 1000;

  /// 이 콘텐츠 판 크기에서 스크롤 없이 한 화면으로 보이는지(배너+카드+최근/AI+안내).
  static bool fitsOnOneScreen(double panelWidth, double panelHeight) => _HomePlan.resolve(panelWidth, panelHeight).fit;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _HomeLoad { loading, loaded, empty, error }

enum _ProjectAction { open, rename, manage }

/// 저장된 base64 이미지를 읽는다. 형식이 깨졌으면(FormatException) null — 원인은 개발자 로그에.
Uint8List? _decodeImage(Object? b64, String what) {
  if (b64 is! String || b64.isEmpty) return null;
  try {
    return base64Decode(b64);
  } on FormatException catch (e) {
    debugPrint('HomeScreen $what 이미지 해석 실패 (${e.runtimeType}): $e');
    return null;
  }
}

/// 프로젝트에 실제로 저장된 이미지(가짜 그림을 만들지 않는다).
class _ProjectImages {
  const _ProjectImages({this.source, this.render, this.path});
  final Uint8List? source;
  final Uint8List? render;
  final String? path;

  Uint8List? get thumbnailBytes => render ?? source;

  static _ProjectImages of(SsProject p) => _ProjectImages(
    source: _decodeImage(p[SsDataSlot.sourceData]?.payload['imageBase64'], '원본'),
    render: _decodeImage(p[SsDataSlot.renderData]?.payload['imageBase64'], '렌더링'),
    path: SsProjectSummary.thumbnailCandidate(p),
  );
}

SsProject? _aiTarget(List<SsProject> projects) {
  for (final p in projects) {
    if (p[SsDataSlot.renderData] != null || p[SsDataSlot.isoData] != null) return p;
  }
  return null;
}

/// 영역 높이 계획 — 넓고 충분히 높으면 원본 비율로 한 화면에 나누고(fit), 아니면 고정 높이로 스크롤.
class _HomePlan {
  const _HomePlan({required this.fit, required this.bannerH, required this.cardsH, required this.recentH, required this.tipsH, required this.pad});
  final bool fit;
  final double bannerH;
  final double cardsH;
  final double recentH;
  final double tipsH;
  final double pad;

  static const double gapAfterBanner = 12;
  static const double gapAfterCards = 14;
  static const double gapAfterRecent = 12;
  static const double bottomPad = 14;
  static const double _gaps = gapAfterBanner + gapAfterCards + gapAfterRecent + bottomPad;

  /// 안내 카드 줄(제목·설명·알약 버튼)이 들어갈 최소 높이.
  static const double minTipsH = 92;

  static _HomePlan resolve(double w, double h) {
    final pad = w >= HomeScreen.fitMinWidth ? 20.0 : 14.0;
    if (w >= HomeScreen.fitMinWidth && h.isFinite) {
      final banner = (h * 0.28).floorToDouble();
      final rest = h - banner - _gaps;
      // 안내 카드 줄은 제목·설명·알약 버튼이 들어갈 높이를 먼저 확보하고(원본 비율 12/59, 최소 minTipsH),
      // 나머지를 원본 비율(시작 카드 22 : 최근/AI 25)로 나눈다 — 1672×941과 같은 비율인 1280×720도 한 화면.
      final tips = (rest * 12 / 59).clamp(minTipsH, 116.0).floorToDouble();
      final cards = ((rest - tips) * 22 / 47).floorToDouble();
      final recent = (rest - tips - cards - 1).floorToDouble();
      if (cards >= 140 && recent >= 160) {
        return _HomePlan(fit: true, bannerH: banner, cardsH: cards, recentH: recent, tipsH: tips, pad: pad);
      }
    }
    return _HomePlan(fit: false, bannerH: w < 560 ? 210 : 240, cardsH: 190, recentH: 220, tipsH: 100, pad: pad);
  }
}

class _HomeScreenState extends State<HomeScreen> {
  _HomeLoad _state = _HomeLoad.loading;
  List<SsProject> _projects = const [];
  Map<String, _ProjectImages> _images = const {};
  SsProjectStore? _store;
  bool _renaming = false;

  static const EdgeInsets _panelMargin = EdgeInsets.fromLTRB(0, 0, 12, 12);

  @override
  void initState() {
    super.initState();
    SsProjectRenames.revision.addListener(_onRenamed);
    unawaited(_load());
  }

  @override
  void dispose() {
    SsProjectRenames.revision.removeListener(_onRenamed);
    super.dispose();
  }

  void _onRenamed() {
    if (mounted) unawaited(_load(silent: true));
  }

  Future<void> _load({bool silent = false}) async {
    // 처음 호출(initState)에서는 이미 _state가 loading이므로 build 중에 setState를
    // 부르지 않는다. "다시 시도"처럼 이미 빌드가 끝난 뒤 부르는 경우에만 로딩으로 되돌린다.
    if (!silent && _state != _HomeLoad.loading) {
      setState(() => _state = _HomeLoad.loading);
    }
    try {
      final store = widget.projectStore ?? await SsProjectStoreProvider.instance.store();
      // 작업 화면 머리말(SsStageHeader)과 같은 순서 — 프로젝트 번호가 같게 보인다.
      final loaded = await SsRecentProjects.load(store);
      final images = <String, _ProjectImages>{};
      for (final p in loaded.take(_RecentProjectsSection.slots)) {
        images[p.info.id] = _ProjectImages.of(p);
      }
      final target = _aiTarget(loaded);
      if (target != null) images.putIfAbsent(target.info.id, () => _ProjectImages.of(target));
      if (!mounted) return;
      setState(() {
        _store = store;
        _projects = loaded;
        _images = images;
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

  void _openPage(Widget page) {
    Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => page));
  }

  Future<void> _rename(SsProject project) async {
    final store = _store;
    if (store == null || _renaming) return;
    final name = await showSsProjectRenameDialog(context, initialName: project.info.name);
    if (name == null || !mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    _renaming = true;
    try {
      final renamed = await renameSsProject(store, project.info.id, name);
      if (!mounted) return;
      if (renamed == null) {
        messenger?.showSnackBar(const SnackBar(content: Text('이름을 바꿀 프로젝트를 찾지 못했습니다.', key: Key('ssProjectRenameError'))));
      }
      // 이름을 바꾸면 SsProjectRenames 신호로 목록을 다시 읽는다(_onRenamed).
    } catch (e, st) {
      // 저장 실패의 원인을 단정하지 않는다 — 화면엔 일반 실패만, 실제 원인(타입 포함)은 개발자에게.
      debugPrint('홈 프로젝트 이름 바꾸기 실패 (${e.runtimeType}): $e / $st');
      messenger?.showSnackBar(const SnackBar(content: Text('프로젝트 이름을 저장하지 못했습니다. 다시 시도해주세요.', key: Key('ssProjectRenameError'))));
    } finally {
      _renaming = false;
    }
  }

  void _onMenu(_ProjectAction action, SsProject project) {
    switch (action) {
      case _ProjectAction.open:
        _resumeProject(project);
      case _ProjectAction.rename:
        unawaited(_rename(project));
      case _ProjectAction.manage:
        Navigator.of(context).pushNamed(SsStage.projectManagement.routeName);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final innerW = constraints.maxWidth - _panelMargin.horizontal;
        final innerH = constraints.maxHeight.isFinite ? constraints.maxHeight - _panelMargin.vertical : double.infinity;
        final plan = _HomePlan.resolve(innerW, innerH);
        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: plan.bannerH, child: const _HeroBanner()),
            Padding(
              padding: EdgeInsets.fromLTRB(plan.pad, _HomePlan.gapAfterBanner, plan.pad, _HomePlan.bottomPad),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _StartCardsRow(rowHeight: plan.cardsH, onSelect: _startFlow),
                  const SizedBox(height: _HomePlan.gapAfterCards),
                  _sections(plan),
                  const SizedBox(height: _HomePlan.gapAfterRecent),
                  _TipCardsRow(
                    rowHeight: plan.tipsH,
                    onGuide: () => _openPage(const SsGuideScreen()),
                    onRecommend: () => _openPage(const SsRecommendationScreen()),
                    onTips: () => _openPage(const SsTipsScreen()),
                  ),
                ],
              ),
            ),
          ],
        );
        final body = plan.fit
            ? KeyedSubtree(key: const Key('ssHomeFit'), child: content)
            : SingleChildScrollView(key: const Key('ssHomeScroll'), child: content);
        return Padding(
          padding: _panelMargin,
          child: DecoratedBox(
            key: const Key('ssHomePanel'),
            decoration: BoxDecoration(
              color: SsMasterTheme.homePanel,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: SsMasterTheme.homePanelBorder),
              boxShadow: SsMasterTheme.homePanelGlow,
            ),
            child: ClipRRect(borderRadius: BorderRadius.circular(21), child: body),
          ),
        );
      },
    );
  }

  Widget _sections(_HomePlan plan) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final recent = _RecentProjectsSection(
          state: _state,
          projects: _projects,
          images: _images,
          onRetry: () => unawaited(_load()),
          onOpen: _resumeProject,
          onMenu: _onMenu,
        );
        final ai = _AiPreviewSection(projects: _projects, images: _images, onOpen: _resumeProject);
        if (constraints.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [SizedBox(height: 220, child: recent), const SizedBox(height: 12), SizedBox(height: 220, child: ai)],
          );
        }
        return SizedBox(
          height: plan.recentH,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [Expanded(flex: 59, child: recent), const SizedBox(width: 14), Expanded(flex: 41, child: ai)],
          ),
        );
      },
    );
  }
}

/// MASTER 02 사진 한 장(BoxFit.cover). 자산을 읽지 못하면 실제 오류(타입 포함)를 개발자 로그로
/// 남기고 빈 바탕만 보인다(가짜 그림을 그리지 않는다).
Widget _homePhoto(String asset, {required Key key, Alignment alignment = Alignment.center}) {
  return Image.asset(
    asset,
    key: key,
    fit: BoxFit.cover,
    alignment: alignment,
    errorBuilder: (context, error, stackTrace) {
      debugPrint('HomeScreen 사진을 불러오지 못했습니다 ($asset, ${error.runtimeType}): $error');
      return const ColoredBox(color: Color(0xFF14284A));
    },
  );
}

BoxDecoration _sectionDecoration() => BoxDecoration(
  color: const Color(0xFF0E2140).withValues(alpha: 0.85),
  borderRadius: BorderRadius.circular(16),
  border: Border.all(color: SsMasterTheme.panelBorder),
);

const TextStyle _sectionTitleStyle = TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800);

ButtonStyle _linkStyle() => TextButton.styleFrom(
  padding: const EdgeInsets.symmetric(horizontal: 4),
  minimumSize: const Size(0, 28),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  visualDensity: VisualDensity.compact,
);

/// "예시" 표시 — 예시 콘텐츠를 사용자 결과와 구분한다.
class _ExampleBadge extends StatelessWidget {
  const _ExampleBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: SsMasterTheme.neonOrange, borderRadius: BorderRadius.circular(6)),
      child: const Text('예시', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
    );
  }
}

/// MASTER UI 2 배너 — 배경 사진(home_hero.png) + 왼쪽 어두운 남색 그라데이션 위에 작은 SS 심볼 + SPACE SHIFT,
/// 두 줄 제목, 그라데이션 큰 "SPACE SHIFT", 설명. 판 위쪽·오른쪽 끝까지 꽉 찬다(판의 둥근 모서리만).
class _HeroBanner extends StatelessWidget {
  const _HeroBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('ssHomeHero'),
      width: double.infinity,
      color: const Color(0xFF0E2140),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight.isFinite ? constraints.maxHeight : 240.0;
          final compact = w < 560;
          final s = (h / 240).clamp(0.75, 1.2);
          final titleSize = (compact ? 22.0 : 30.0) * s;
          final brandSize = (compact ? 34.0 : 52.0) * s;
          final descSize = math.max(12.0, 15.0 * s);
          final padL = compact ? 18.0 : math.max(24.0, w * 0.035);
          final textMaxWidth = compact ? math.max(200.0, w - padL - 18) : math.max(320.0, w * 0.5);
          final titleStyle = TextStyle(color: Colors.white, fontSize: titleSize, fontWeight: FontWeight.w800, height: 1.25);
          final shade = compact
              ? const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Color(0xF20A1830), Color(0xD90A1830), Color(0x990A1830)],
                  stops: [0.0, 0.6, 1.0],
                )
              : const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Color(0xF20A1830), Color(0xCC0A1830), Color(0x000A1830)],
                  stops: [0.0, 0.38, 0.7],
                );
          return Stack(
            children: [
              Positioned.fill(
                child: _homePhoto(HomeScreen.heroImageAsset, key: const Key('ssHomeHeroImage'), alignment: Alignment.centerRight),
              ),
              Positioned.fill(
                child: DecoratedBox(key: const Key('ssHomeHeroShade'), decoration: BoxDecoration(gradient: shade)),
              ),
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(padL, h * 0.09, 18, h * 0.08),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: textMaxWidth),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Image.asset(
                                  'assets/icons/space_shift_symbol.png',
                                  key: const Key('ssHomeHeroSymbol'),
                                  height: 16 * s,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    debugPrint('HomeScreen 배너 심볼을 불러오지 못했습니다 (${error.runtimeType}): $error');
                                    return SizedBox(width: 16 * s, height: 16 * s);
                                  },
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  'SPACE SHIFT',
                                  key: Key('ssHomeHeroBadge'),
                                  style: TextStyle(color: SsMasterTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w400, letterSpacing: 1.5),
                                ),
                              ],
                            ),
                            SizedBox(height: 12 * s),
                            Text('공간의 변화를 만드는', key: const Key('ssHomeHeroTitle1'), style: titleStyle),
                            Text('새로운 가능성,', key: const Key('ssHomeHeroTitle2'), style: titleStyle),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: ShaderMask(
                                shaderCallback: (bounds) => SsMasterTheme.heroBrand.createShader(bounds),
                                child: Text(
                                  'SPACE SHIFT',
                                  key: const Key('ssHomeHeroBrand'),
                                  style: TextStyle(color: Colors.white, fontSize: brandSize, fontWeight: FontWeight.w900, letterSpacing: 1.5, height: 1.15),
                                ),
                              ),
                            ),
                            SizedBox(height: 6 * s),
                            SsKeepWordsText(
                              'AI와 함께, 당신의 공간을 새롭게 디자인하세요.',
                              key: const Key('ssHomeHeroDescription'),
                              style: TextStyle(color: const Color(0xFFDCE3EF), fontSize: descSize),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StartCardsRow extends StatelessWidget {
  const _StartCardsRow({required this.rowHeight, required this.onSelect});
  final double rowHeight;
  final ValueChanged<SsSourceType> onSelect;

  /// 이 폭보다 좁으면 카드를 세로로 쌓는다. 넓으면 MASTER 02처럼 한 줄.
  static const double rowMinWidth = 900;
  static const double stackedHeight = 160;

  static const _cards = [
    (
      type: SsSourceType.floorPlanUpload,
      icon: Icons.cloud_upload_outlined,
      iconColor: Color(0xFF2F6BFF),
      title: '평면도 업로드',
      desc: '도면 이미지를 업로드하여 공간을 분석하고 시작합니다.',
      image: HomeScreen.uploadCardImageAsset,
      bottom: Color(0xE6EEF4FF),
    ),
    (
      type: SsSourceType.directDraw,
      icon: Icons.edit_outlined,
      iconColor: Color(0xFF8B3FE0),
      title: '직접 그리기',
      desc: '간단한 도구로 직접 평면도를 그리고 공간을 구성해보세요.',
      image: HomeScreen.drawCardImageAsset,
      bottom: Color(0xE6F3EEFF),
    ),
    (
      type: SsSourceType.imageTransform,
      icon: Icons.image_outlined,
      iconColor: Color(0xFF0E9F7E),
      title: '이미지 변환',
      desc: '공간 사진을 업로드하여 새로운 디자인을 만들어보세요.',
      image: HomeScreen.imageCardImageAsset,
      bottom: Color(0xE6E3F8F1),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cards = [
          for (final c in _cards)
            _StartCard(
              type: c.type,
              icon: c.icon,
              iconColor: c.iconColor,
              title: c.title,
              description: c.desc,
              imageAsset: c.image,
              bottomColor: c.bottom,
              onTap: () => onSelect(c.type),
            ),
        ];
        if (constraints.maxWidth < rowMinWidth) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < cards.length; i++)
                Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : 12), child: SizedBox(height: stackedHeight, child: cards[i])),
            ],
          );
        }
        return SizedBox(
          height: rowHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(width: 14),
                Expanded(child: cards[i]),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// MASTER 02 시작 카드 — 위쪽 사진, 아래쪽 반투명 밝은 판(제목·설명·흰 원 화살표), 경계에 걸친 큰 흰 원 아이콘.
class _StartCard extends StatelessWidget {
  const _StartCard({
    required this.type,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.imageAsset,
    required this.bottomColor,
    required this.onTap,
  });
  final SsSourceType type;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  final String imageAsset;
  final Color bottomColor;
  final VoidCallback onTap;

  static const Color _titleColor = Color(0xFF0E1B33);
  static const Color _descColor = Color(0xFF4A5A73);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
        boxShadow: [BoxShadow(color: SsMasterTheme.neonBlue.withValues(alpha: 0.35), blurRadius: 14)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Material(
          color: const Color(0xFFDDE6F5),
          child: InkWell(
            key: Key('ssHomeStartCard_${type.name}'),
            onTap: onTap,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final h = constraints.maxHeight;
                final w = constraints.maxWidth;
                final bottomH = (h * 0.48).clamp(84.0, 110.0);
                final photoH = math.max(0.0, h - bottomH);
                final d = (w * 0.17).clamp(52.0, 80.0);
                final circleTop = math.max(0.0, photoH - d * 0.4);
                return Stack(
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: photoH + bottomH * 0.5,
                      child: _homePhoto(imageAsset, key: Key('ssHomeStartCardImage_${type.name}')),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: bottomH,
                      child: ColoredBox(
                        key: Key('ssHomeStartCardPanel_${type.name}'),
                        color: bottomColor,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(16 + d + 12, 10, 12, 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      key: Key('ssHomeStartCardTitle_${type.name}'),
                                      maxLines: 1,
                                      softWrap: false,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: _titleColor, fontSize: 16, fontWeight: FontWeight.w800),
                                    ),
                                    const SizedBox(height: 4),
                                    SsKeepWordsText(
                                      description,
                                      key: Key('ssHomeStartCardDesc_${type.name}'),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: _descColor, fontSize: 12, height: 1.35),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                key: Key('ssHomeStartCardArrow_${type.name}'),
                                width: 36,
                                height: 36,
                                alignment: Alignment.center,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [BoxShadow(color: Color(0x22000000), blurRadius: 6, offset: Offset(0, 2))],
                                ),
                                child: const Icon(Icons.arrow_forward, color: Color(0xFF2F6BFF), size: 20),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 16,
                      top: circleTop,
                      child: Container(
                        key: Key('ssHomeStartCardIcon_${type.name}'),
                        width: d,
                        height: d,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 2))],
                        ),
                        child: Icon(icon, color: iconColor, size: d * 0.46),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentProjectsSection extends StatelessWidget {
  const _RecentProjectsSection({
    required this.state,
    required this.projects,
    required this.images,
    required this.onRetry,
    required this.onOpen,
    required this.onMenu,
  });
  final _HomeLoad state;
  final List<SsProject> projects;
  final Map<String, _ProjectImages> images;
  final VoidCallback onRetry;
  final ValueChanged<SsProject> onOpen;
  final void Function(_ProjectAction action, SsProject project) onMenu;

  /// 원본처럼 항상 4칸.
  static const int slots = 4;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('ssHomeRecentProjects'),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: _sectionDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 28,
            child: Row(
              children: [
                const Text('최근 프로젝트', style: _sectionTitleStyle),
                const Spacer(),
                TextButton(
                  key: const Key('ssHomeProjectsSeeAll'),
                  style: _linkStyle(),
                  onPressed: () => Navigator.of(context).pushNamed(SsStage.projectManagement.routeName),
                  child: const Text('전체보기 →', style: TextStyle(color: SsMasterTheme.neonBlue, fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _slotsRow({Key? key, required List<SsProject> shown}) {
    return Row(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < slots; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: i < shown.length
                ? _ProjectCard(
                    project: shown[i],
                    number: i + 1,
                    images: images[shown[i].info.id],
                    onTap: () => onOpen(shown[i]),
                    onMenu: (a) => onMenu(a, shown[i]),
                  )
                : _EmptySlot(key: Key('ssHomeRecentEmptySlot_$i')),
          ),
        ],
      ],
    );
  }

  Widget _buildBody() {
    switch (state) {
      case _HomeLoad.loading:
        // value를 고정해 두어(결정적 인디케이터) 끝없이 반복되는 애니메이션이 생기지 않게 한다
        // — 그렇지 않으면 위젯 테스트의 pumpAndSettle()이 끝나지 않는다.
        return const Center(child: CircularProgressIndicator(key: Key('ssHomeLoading'), color: SsMasterTheme.neonBlue, value: 0.3));
      case _HomeLoad.error:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '프로젝트 정보를 불러오지 못했습니다. 다시 시도해주세요.',
                key: Key('ssHomeProjectsError'),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: SsMasterTheme.textSecondary),
              ),
              const SizedBox(height: 8),
              OutlinedButton(key: const Key('ssHomeRetryButton'), onPressed: onRetry, child: const Text('다시 시도')),
            ],
          ),
        );
      case _HomeLoad.empty:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '아직 프로젝트가 없습니다. 위 카드에서 첫 프로젝트를 시작해보세요.',
              key: Key('ssHomeEmptyProjects'),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: SsMasterTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 6),
            Expanded(child: _slotsRow(shown: const [])),
          ],
        );
      case _HomeLoad.loaded:
        return _slotsRow(key: const Key('ssHomeRecentProjectsList'), shown: projects.take(slots).toList());
    }
  }
}

/// 프로젝트가 없는 칸 — 같은 크기의 점선 빈 칸(영역 비율 유지).
class _EmptySlot extends StatelessWidget {
  const _EmptySlot({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const SsDashedRRectPainter(color: Color(0xFF34507A), radius: 12, strokeWidth: 1.2),
      child: const SizedBox.expand(child: Center(child: Icon(Icons.add, color: Color(0xFF34507A), size: 22))),
    );
  }
}

IconData _sourceIcon(SsSourceType t) => switch (t) {
  SsSourceType.floorPlanUpload => Icons.cloud_upload_outlined,
  SsSourceType.directDraw => Icons.edit_outlined,
  SsSourceType.imageTransform => Icons.image_outlined,
};

/// 실제 이미지가 없을 때의 남색 자리 그림(시작 방식 아이콘) — 원본의 예시 방 사진을 쓰지 않는다.
class _ThumbPlaceholder extends StatelessWidget {
  const _ThumbPlaceholder({super.key, required this.sourceType});
  final SsSourceType sourceType;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF17305A), Color(0xFF0B1A33)]),
      ),
      child: Center(child: Icon(_sourceIcon(sourceType), color: SsMasterTheme.neonBlue.withValues(alpha: 0.85), size: 28)),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project, required this.number, required this.images, required this.onTap, required this.onMenu});
  final SsProject project;
  final int number;
  final _ProjectImages? images;
  final VoidCallback onTap;
  final ValueChanged<_ProjectAction> onMenu;

  bool get _isDone => SsFlows.next(project.sourceType, project.currentStage) == null;

  static String formatDate(DateTime dt) => '${dt.year}. ${dt.month.toString().padLeft(2, '0')}. ${dt.day.toString().padLeft(2, '0')}';

  Widget _thumb() {
    final id = project.info.id;
    final placeholder = _ThumbPlaceholder(key: Key('ssHomeProjectThumbPlaceholder_$id'), sourceType: project.sourceType);
    final bytes = images?.thumbnailBytes;
    if (bytes != null) {
      return Image.memory(
        bytes,
        key: Key('ssHomeProjectThumbImage_$id'),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          debugPrint('HomeScreen 프로젝트 썸네일 표시 실패 ($id, ${error.runtimeType}): $error');
          return placeholder;
        },
      );
    }
    final path = images?.path;
    if (path != null) {
      return Image.file(
        File(path),
        key: Key('ssHomeProjectThumbImage_$id'),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          debugPrint('HomeScreen 프로젝트 썸네일 파일 표시 실패 ($id, ${error.runtimeType}): $error');
          return placeholder;
        },
      );
    }
    return placeholder;
  }

  @override
  Widget build(BuildContext context) {
    final id = project.info.id;
    final updated = project.updatedAt ?? project.info.createdAt;
    final statusColor = _isDone ? SsMasterTheme.neonCyan : SsMasterTheme.neonOrange;
    return Material(
      color: const Color(0xFF0D1F3C),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: SsMasterTheme.panelBorder)),
      child: InkWell(
        key: Key('ssHomeProjectCard_$id'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _thumb(),
                      Positioned(
                        left: 5,
                        top: 5,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: const Color(0xCC0A1830), borderRadius: BorderRadius.circular(10)),
                          child: Text(
                            _isDone ? '완료' : '진행중',
                            key: Key('ssHomeProjectStatus_$id'),
                            style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 38,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                number.toString().padLeft(2, '0'),
                                key: Key('ssHomeProjectNumber_$id'),
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  project.info.name,
                                  key: Key('ssHomeProjectName_$id'),
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            formatDate(updated),
                            key: Key('ssHomeProjectDate_$id'),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: SsMasterTheme.textMuted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<_ProjectAction>(
                      key: Key('ssHomeProjectMenu_$id'),
                      tooltip: '프로젝트 메뉴',
                      color: SsMasterTheme.panel,
                      onSelected: onMenu,
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          key: Key('ssHomeProjectMenuOpen'),
                          value: _ProjectAction.open,
                          child: Text('열기', style: TextStyle(color: Colors.white)),
                        ),
                        PopupMenuItem(
                          key: Key('ssHomeProjectMenuRename'),
                          value: _ProjectAction.rename,
                          child: Text('이름 바꾸기', style: TextStyle(color: Colors.white)),
                        ),
                        PopupMenuItem(
                          key: Key('ssHomeProjectMenuManage'),
                          value: _ProjectAction.manage,
                          child: Text('프로젝트 관리에서 보기', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                      child: const SizedBox(width: 22, height: 30, child: Icon(Icons.more_vert, color: SsMasterTheme.textSecondary, size: 18)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AiPreviewSection extends StatelessWidget {
  const _AiPreviewSection({required this.projects, required this.images, required this.onOpen});
  final List<SsProject> projects;
  final Map<String, _ProjectImages> images;
  final ValueChanged<SsProject> onOpen;

  Widget _placeholder(Key key, IconData icon, String label) {
    return ColoredBox(
      key: key,
      color: const Color(0xFF14284A),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: SsMasterTheme.neonBlue, size: 28),
            const SizedBox(height: 4),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: SsMasterTheme.textSecondary, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _memory(Uint8List bytes, Key key, Widget fallback) => Image.memory(
    bytes,
    key: key,
    fit: BoxFit.cover,
    errorBuilder: (context, error, stackTrace) {
      debugPrint('HomeScreen AI 미리보기 이미지 표시 실패 (${error.runtimeType}): $error');
      return fallback;
    },
  );

  @override
  Widget build(BuildContext context) {
    final target = _aiTarget(projects);
    final example = target == null;
    Widget left;
    Widget right;
    if (target == null) {
      left = _homePhoto(HomeScreen.aiPlanExampleAsset, key: const Key('ssHomeAiExamplePlan'));
      right = _homePhoto(HomeScreen.ai3dExampleAsset, key: const Key('ssHomeAiExample3d'));
    } else {
      final img = images[target.info.id];
      final srcFallback = _placeholder(const Key('ssHomeAiResultSourcePlaceholder'), Icons.grid_on, '원본');
      final resFallback = _placeholder(const Key('ssHomeAiResultPlaceholder'), Icons.view_in_ar_outlined, 'AI 결과');
      left = img?.source != null ? _memory(img!.source!, const Key('ssHomeAiResultSource'), srcFallback) : srcFallback;
      right = img?.render != null ? _memory(img!.render!, const Key('ssHomeAiResultImage'), resFallback) : resFallback;
    }
    return Container(
      key: const Key('ssHomeAiPreview'),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: _sectionDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 28,
            child: Row(
              children: [
                const Flexible(child: Text('AI 분석 미리보기', maxLines: 1, overflow: TextOverflow.ellipsis, style: _sectionTitleStyle)),
                const Spacer(),
                if (target != null)
                  TextButton(
                    key: const Key('ssHomeAiPreviewOpen'),
                    style: _linkStyle(),
                    onPressed: () => onOpen(target),
                    child: const Text('결과보기 →', style: TextStyle(color: SsMasterTheme.neonBlue, fontSize: 13, fontWeight: FontWeight.w700)),
                  )
                else
                  TextButton(
                    key: const Key('ssHomeAiPreviewNoResult'),
                    style: _linkStyle(),
                    onPressed: () => ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      const SnackBar(
                        content: Text(
                          '아직 AI 분석 결과가 없습니다. 지금 보이는 그림은 예시입니다.',
                          key: Key('ssHomeAiNoResultMessage'),
                        ),
                      ),
                    ),
                    child: const Text('결과보기 →', style: TextStyle(color: SsMasterTheme.textMuted, fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                key: Key(example ? 'ssHomeAiExample' : 'ssHomeAiResult'),
                fit: StackFit.expand,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [Expanded(child: left), Expanded(child: right)],
                  ),
                  Center(
                    child: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A3550),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
                      ),
                      child: const Icon(Icons.arrow_forward, color: Colors.white, size: 22),
                    ),
                  ),
                  if (example) const Positioned(left: 8, top: 8, child: _ExampleBadge(key: Key('ssHomeAiExampleBadge'))),
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 6,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0xB30A1830), borderRadius: BorderRadius.circular(6)),
                        child: Text(
                          example ? '예시 그림 · 아직 내 프로젝트의 AI 분석 결과가 없습니다' : '${target.info.name}의 AI 분석 결과',
                          key: const Key('ssHomeAiPreviewText'),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 11),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// MASTER UI 2 맨 아래 안내 카드 3개 — 가이드(파랑 책·파랑 판), 추천(노랑 전구·보라 알약), 팁(청록 말풍선·청록 알약).
class _TipCardsRow extends StatelessWidget {
  const _TipCardsRow({required this.rowHeight, required this.onGuide, required this.onRecommend, required this.onTips});
  final double rowHeight;
  final VoidCallback onGuide;
  final VoidCallback onRecommend;
  final VoidCallback onTips;

  static const double stackedHeight = 100;

  @override
  Widget build(BuildContext context) {
    final tips = [
      (
        id: 'guide',
        icon: Icons.menu_book_outlined,
        iconColor: const Color(0xFF4F9BFF),
        iconBg: const Color(0xFF173A70),
        card: const Color(0xFF0F2A55),
        border: const Color(0xFF2F5FA8),
        pill: const Color(0xFF2563EB),
        title: '처음 사용하시나요?',
        desc: '간단한 가이드로 빠르게 시작해보세요.',
        cta: '가이드 보기',
        example: false,
        onTap: onGuide,
      ),
      (
        id: 'recommend',
        icon: Icons.lightbulb_outline,
        iconColor: const Color(0xFFFACC15),
        iconBg: const Color(0xFF3D3320),
        card: const Color(0xFF1C1B4A),
        border: const Color(0xFF5B3FB0),
        pill: const Color(0xFF6D28D9),
        title: '오늘의 추천',
        desc: 'AI가 제안하는 인테리어 스타일을 확인해보세요.',
        cta: '추천 보기',
        example: true,
        onTap: onRecommend,
      ),
      (
        id: 'tips',
        icon: Icons.sms_outlined,
        iconColor: const Color(0xFF2DD4BF),
        iconBg: const Color(0xFF134E4A),
        card: const Color(0xFF0D2E3A),
        border: const Color(0xFF1F6F73),
        pill: const Color(0xFF0F766E),
        title: '공간 디자인 팁',
        desc: '더 좋은 결과를 위한 팁을 확인하세요.',
        cta: '팁 보기',
        example: false,
        onTap: onTips,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final cards = [
          for (final t in tips)
            _TipCard(
              id: t.id,
              icon: t.icon,
              iconColor: t.iconColor,
              iconBg: t.iconBg,
              cardColor: t.card,
              borderColor: t.border,
              pillColor: t.pill,
              title: t.title,
              description: t.desc,
              cta: t.cta,
              example: t.example,
              onTap: t.onTap,
            ),
        ];
        if (constraints.maxWidth < 760) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < cards.length; i++)
                Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : 10), child: SizedBox(height: stackedHeight, child: cards[i])),
            ],
          );
        }
        return SizedBox(
          height: rowHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(width: 14),
                Expanded(child: cards[i]),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _TipCard extends StatelessWidget {
  const _TipCard({
    required this.id,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.cardColor,
    required this.borderColor,
    required this.pillColor,
    required this.title,
    required this.description,
    required this.cta,
    required this.example,
    required this.onTap,
  });
  final String id;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final Color cardColor;
  final Color borderColor;
  final Color pillColor;
  final String title;
  final String description;
  final String cta;
  final bool example;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('ssHomeTipCard_$id'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          Container(
            key: Key('ssHomeTipIcon_$id'),
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // 낮은 줄(예: 1280×720)에서도 제목·설명·알약 버튼이 서로 겹치거나 잘리지 않게, 들어가지 않으면 통째로 살짝 줄인다.
                return FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: constraints.maxWidth,
                    child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (example) ...[const SizedBox(width: 6), const _ExampleBadge(key: Key('ssHomeRecommendExampleBadge'))],
                  ],
                ),
                const SizedBox(height: 2),
                SsKeepWordsText(
                  description,
                  key: Key('ssHomeTipDesc_$id'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: SsMasterTheme.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 6),
                TextButton(
                  key: Key('ssHomeTip_$id'),
                  style: TextButton.styleFrom(
                    backgroundColor: pillColor,
                    foregroundColor: Colors.white,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: onTap,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(cta, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward, size: 15),
                    ],
                  ),
                ),
              ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
