import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../config/app_environment.dart';
import '../models/ai_generation_request.dart';
import '../models/work_instruction.dart';
import '../services/ai_generation_provider.dart';
import '../services/ai_generation_service.dart';
import '../services/usage_policy_service.dart';
import '../widgets/primary_button.dart';
import 'result_screen.dart';

/// AI가 새로운 공간 이미지를 생성하는 동안 보여주는 대기 화면.
///
/// 실제 생성 작업은 [AiGenerationService]에 위임한다. 이 화면은
/// AiGenerationService.generate()가 어떤 방식으로 구현되어 있는지(현재는
/// 더미, 추후 실제 AI API) 전혀 알지 못하며, 응답의 success 여부에 따라
/// 결과 화면으로 이동하거나 오류 안내만 표시한다.
class GenerateScreen extends StatefulWidget {
  const GenerateScreen({
    super.key,
    required this.selectedStyle,
    required this.selectedImageBytes,
    this.workInstructions = const [],
    this.additionalNotes = '',
    this.aiGenerationService,
  });

  /// StyleSelectScreen에서 사용자가 선택한 스타일 이름.
  /// 결과 화면으로 그대로 전달한다.
  final String selectedStyle;

  /// PhotoSelectScreen에서 사용자가 선택한 사진 데이터.
  /// 결과 화면의 원본 카드에 표시하기 위해 그대로 전달한다.
  final Uint8List selectedImageBytes;

  /// WorkspaceScreen(공간 작업실)에서 완성한 부위별 부분 선택 + 작업 지시 목록.
  final List<WorkInstruction> workInstructions;

  /// WorkspaceScreen에서 입력한, 특정 부위에 묶이지 않는 추가 작업 지시.
  final String additionalNotes;

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
  /// Splash, 사진/스타일 선택 화면과 동일한 밝은 아이보리 계열 배경색
  static const Color _ivoryBackground = Color(0xFFFFF8E7);

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

  int _progressIndex = 0;
  Timer? _progressTimer;
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

  Future<void> _startGeneration() async {
    _progressTimer?.cancel();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _progressIndex = 0;
    });
    _startProgressMessages();

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
      return;
    }

    _progressTimer?.cancel();
    setState(() {
      _isLoading = false;
      _errorMessage = response.errorMessage ?? 'AI 생성 중 오류가 발생했습니다.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ivoryBackground,
      appBar: AppBar(
        title: const Text('AI 생성'),
        backgroundColor: _ivoryBackground,
        foregroundColor: const Color(0xFF3E2723),
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
                const SizedBox(
                  width: 72,
                  height: 72,
                  child: CircularProgressIndicator(
                    strokeWidth: 5,
                    color: Color(0xFF8D6E63),
                  ),
                ),
                const SizedBox(height: 28),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    _progressMessages[_progressIndex],
                    key: ValueKey<int>(_progressIndex),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF3E2723),
                    ),
                  ),
                ),
                const SizedBox(height: 36),
                const _SpaceShiftIntroSection(),
              ] else ...[
                const Icon(
                  Icons.error_outline_rounded,
                  size: 72,
                  color: Color(0xFF8D6E63),
                ),
                const SizedBox(height: 20),
                Text(
                  '이미지를 생성하지 못했습니다',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF3E2723),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _errorMessage ?? '잠시 후 다시 시도해주세요.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF5D4037)),
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
        border: Border.all(color: const Color(0xFFEFE6DA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SPACE SHIFT 소개',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color(0xFF3E2723),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'SPACE SHIFT는 당신의 공간을 사진 한 장으로 분석해서, '
            '원하는 변화 방향을 AI 이미지로 만들어드리는 서비스입니다.',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF5D4037),
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
                  Icon(feature.$1, size: 22, color: const Color(0xFF8D6E63)),
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
                            color: Color(0xFF3E2723),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          feature.$3,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF5D4037),
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
