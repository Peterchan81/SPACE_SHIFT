import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../config/app_environment.dart';
import '../models/ai_generation_request.dart';
import '../models/work_instruction.dart';
import '../services/ai_generation_provider.dart';
import '../services/ai_generation_service.dart';
import '../services/usage_policy_service.dart';
import '../theme/space_shift_colors.dart';
import '../widgets/gradient_progress_ring.dart';
import '../widgets/primary_button.dart';
import 'result_screen.dart';
import 'revise_result_screen.dart';

/// MASTER UI 5번(최초 생성) / 7번(수정 요청 처리 중) 화면 — AI가 새로운 공간
/// 이미지를 생성하는 동안 보여주는 대기 화면.
///
/// 실제 생성 작업은 [AiGenerationService]에 위임한다. 이 화면은
/// AiGenerationService.generate()가 어떤 방식으로 구현되어 있는지(현재는
/// 더미, 추후 실제 AI API) 전혀 알지 못하며, 응답의 success 여부에 따라
/// 결과 화면으로 이동하거나 오류 안내만 표시한다. [isRevision]이 true이면
/// "수정 요청 처리 중"(7번 화면) 문구를 보여주고 성공 시 [ReviseResultScreen]
/// (8번 화면)으로 이동한다.
class GenerateScreen extends StatefulWidget {
  const GenerateScreen({
    super.key,
    required this.selectedStyle,
    required this.selectedImageBytes,
    this.workInstructions = const [],
    this.additionalNotes = '',
    this.isRevision = false,
    this.aiGenerationService,
  });

  /// 선택된 스타일 이름(있는 경우). 결과 화면으로 그대로 전달한다.
  final String selectedStyle;

  /// PhotoSelectScreen에서 사용자가 선택한 사진 데이터.
  /// 결과 화면의 원본 카드에 표시하기 위해 그대로 전달한다.
  final Uint8List selectedImageBytes;

  /// WorkspaceScreen(공간 작업실)에서 완성한 부위별 부분 선택 + 작업 지시 목록.
  final List<WorkInstruction> workInstructions;

  /// WorkspaceScreen에서 입력한, 특정 부위에 묶이지 않는 추가 작업 지시.
  final String additionalNotes;

  /// 결과 확인 화면의 "수정 재요청"에서 시작된 재생성이면 true.
  final bool isRevision;

  /// AI 생성 요청을 담당하는 서비스.
  ///
  /// null이면 [createAiGenerationService]로 현재 환경(AppEnvironment)에
  /// 맞는 서비스를 만들어 사용한다. 위젯 테스트에서는 가짜 응답을 반환하는
  /// 구현을 직접 주입할 수 있다.
  final AiGenerationService? aiGenerationService;

  @override
  State<GenerateScreen> createState() => _GenerateScreenState();
}

class _GenerateScreenState extends State<GenerateScreen> {
  /// 실제로 사용할 AI 생성 서비스.
  /// 주입된 값이 없으면 현재 환경(AppEnvironment)에 맞는 서비스를 만든다.
  late final AiGenerationService _aiGenerationService =
      widget.aiGenerationService ?? createAiGenerationService();

  /// 생성이 진행되는 동안 1초 간격으로 순차 표시할 안내 문구.
  /// (0~1초, 1~2초, 2~3초에 각각 대응)
  static const List<String> _progressMessages = [
    '사진을 분석하고 있습니다...',
    '인테리어 스타일을 적용하고 있습니다...',
    '새로운 공간을 생성하고 있습니다...',
  ];

  /// MASTER UI 5/7번 화면의 "예상 완료 시간" 표시에 사용하는 값.
  /// 실제 서버 진행률이 없으므로 화면 안내용으로만 사용하는 값이며, 실제
  /// 응답은 이 시간과 무관하게 [AiGenerationService.generate] 완료 시점에
  /// 도착한다.
  late final int _estimateSeconds = widget.isRevision ? 12 : 15;

  int _progressIndex = 0;
  Timer? _progressTimer;
  Timer? _percentTimer;
  double _percentProgress = 0;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _startGeneration();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _percentTimer?.cancel();
    super.dispose();
  }

  /// 실제 생성 요청과는 별개로, 대기 화면의 안내 문구만 1초마다 다음
  /// 단계로 바꿔준다. 마지막 문구에 도달하면 더 이상 바꾸지 않는다.
  void _startProgressMessages() {
    _progressTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_progressIndex >= _progressMessages.length - 1) {
        timer.cancel();
        return;
      }
      setState(() {
        _progressIndex++;
      });
    });
  }

  /// 실제 서버 진행률이 없으므로, 예상 소요 시간(estimateSeconds)에 맞춰
  /// 시각적인 진행률(0 ~ 95%)만 부드럽게 채워준다. 응답이 도착하면 즉시
  /// 화면을 전환하므로 100%까지 도달하지 않아도 자연스럽다.
  void _startPercentProgress() {
    const tick = Duration(milliseconds: 200);
    final totalTicks = (_estimateSeconds * 1000) / tick.inMilliseconds;
    var ticks = 0;
    _percentTimer = Timer.periodic(tick, (timer) {
      if (!mounted) return;
      ticks++;
      setState(() {
        _percentProgress = (ticks / totalTicks).clamp(0.0, 0.95);
      });
    });
  }

  int get _remainingSeconds =>
      (_estimateSeconds - (_percentProgress * _estimateSeconds)).ceil().clamp(
        0,
        _estimateSeconds,
      );

  Future<void> _startGeneration() async {
    _progressTimer?.cancel();
    _percentTimer?.cancel();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _progressIndex = 0;
      _percentProgress = 0;
    });
    _startProgressMessages();
    _startPercentProgress();

    final request = AiGenerationRequest(
      imageBytes: widget.selectedImageBytes,
      selectedStyle: widget.selectedStyle,
      createdAt: DateTime.now(),
      appVersion: AppEnvironment.appVersion,
      workInstructions: widget.workInstructions,
      additionalNotes: widget.additionalNotes,
    );

    // 무료 이용 횟수는 실제로 AI 생성을 시도하는 이 시점에 1회로 집계한다.
    UsagePolicyService.instance.recordGeneration();

    final response = await _aiGenerationService.generate(request);
    if (!mounted) return;

    if (response.success) {
      _progressTimer?.cancel();
      _percentTimer?.cancel();
      if (widget.isRevision) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => ReviseResultScreen(
              selectedImageBytes: widget.selectedImageBytes,
              generatedImageBytes: response.generatedImageBytes,
              workInstructions: widget.workInstructions,
            ),
          ),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => ResultScreen(
              selectedStyle: widget.selectedStyle,
              selectedImageBytes: widget.selectedImageBytes,
              generatedImageBytes: response.generatedImageBytes,
              workInstructions: widget.workInstructions,
              additionalNotes: widget.additionalNotes,
            ),
          ),
        );
      }
      return;
    }

    _progressTimer?.cancel();
    _percentTimer?.cancel();
    setState(() {
      _isLoading = false;
      _errorMessage = response.errorMessage ?? 'AI 생성 중 오류가 발생했습니다.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpaceShiftColors.background,
      appBar: AppBar(
        title: Text(widget.isRevision ? '수정 요청 처리 중' : 'AI 생성'),
        backgroundColor: SpaceShiftColors.background,
        foregroundColor: SpaceShiftColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isLoading) ...[
                    Text(
                      widget.isRevision
                          ? '수정 내용을 반영하고 있어요'
                          : 'AI가 공간을 변화시키는 중입니다',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: SpaceShiftColors.textPrimary,
                          ),
                    ),
                    if (widget.isRevision) ...[
                      const SizedBox(height: 8),
                      const Text(
                        '더 만족스러운 결과를 만들어드릴게요.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: SpaceShiftColors.textSecondary),
                      ),
                    ],
                    const SizedBox(height: 28),
                    GradientProgressRing(progress: _percentProgress),
                    const SizedBox(height: 16),
                    Text(
                      '예상 완료 시간 $_remainingSeconds초',
                      style: const TextStyle(
                        fontSize: 14,
                        color: SpaceShiftColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        _progressMessages[_progressIndex],
                        key: ValueKey<int>(_progressIndex),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: SpaceShiftColors.textPrimary,
                            ),
                      ),
                    ),
                    const SizedBox(height: 36),
                    _SpaceShiftIntroSection(),
                  ] else ...[
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 72,
                      color: SpaceShiftColors.textSecondary,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '이미지를 생성하지 못했습니다',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: SpaceShiftColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _errorMessage ?? '잠시 후 다시 시도해주세요.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: SpaceShiftColors.textSecondary),
                    ),
                    const SizedBox(height: 24),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: PrimaryButton(
                        label: '다시 시도하기',
                        onPressed: _startGeneration,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 생성 대기 시간을 단순 progress로만 끝내지 않기 위한 SPACE SHIFT 소개 영역.
///
/// MASTER UI 5번 화면(생성 중 + 서비스 소개) 기준으로, 서비스 한 줄 소개와
/// 핵심 기능 3가지를 간단한 카드 형태로 보여준다.
class _SpaceShiftIntroSection extends StatelessWidget {
  const _SpaceShiftIntroSection();

  static const List<(IconData, String, String)> _features = [
    (
      Icons.center_focus_strong_rounded,
      '정확한 공간 분석',
      'AI가 공간 구조와 스타일을 정확하게 파악해요.',
    ),
    (
      Icons.tune_rounded,
      '원하는 대로 변경',
      '부위별 부분 선택과 텍스트 지시로 자유롭게 바꿀 수 있어요.',
    ),
    (
      Icons.visibility_rounded,
      '실시간 미리보기',
      '변경 결과를 바로 확인하고 다시 수정 요청할 수 있어요.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SpaceShiftColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SPACE SHIFT 소개',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: SpaceShiftColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'SPACE SHIFT는 당신의 공간을 사진 한 장으로 분석해서, '
            '원하는 변화 방향을 AI 이미지로 만들어드리는 서비스입니다.',
            style: TextStyle(
              fontSize: 13,
              color: SpaceShiftColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          for (final feature in _features)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    feature.$1,
                    size: 22,
                    color: SpaceShiftColors.selectionAccent,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          feature.$2,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: SpaceShiftColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          feature.$3,
                          style: const TextStyle(
                            fontSize: 12,
                            color: SpaceShiftColors.textSecondary,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
