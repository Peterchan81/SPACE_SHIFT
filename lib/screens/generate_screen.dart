import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../config/app_environment.dart';
import '../models/ai_generation_request.dart';
import '../models/space_task.dart';
import '../services/ai_generation_provider.dart';
import '../services/ai_generation_service.dart';
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
    this.aiGenerationService,
    this.tasks,
  });

  /// StyleSelectScreen에서 사용자가 선택한 스타일 이름, 또는 공간
  /// 작업실에서 등록한 작업들을 합쳐 만든 요약 지시 문구.
  /// 결과 화면으로 그대로 전달한다.
  final String selectedStyle;

  /// PhotoSelectScreen(또는 공간 작업실)에서 선택한 사진 데이터.
  /// 결과 화면의 원본 카드에 표시하기 위해 그대로 전달한다.
  final Uint8List selectedImageBytes;

  /// 공간 작업실에서 등록한 영역별 작업 목록.
  /// null이면 스타일 선택 등 이전 방식의 요청이다.
  final List<SpaceTask>? tasks;

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
      tasks: widget.tasks ?? const [],
    );

    final response = await _aiGenerationService.generate(request);
    if (!mounted) return;

    if (response.success) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => ResultScreen(
            selectedStyle: widget.selectedStyle,
            selectedImageBytes: widget.selectedImageBytes,
            generatedImageBytes: response.generatedImageBytes,
            tasks: widget.tasks,
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
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
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
    );
  }
}
