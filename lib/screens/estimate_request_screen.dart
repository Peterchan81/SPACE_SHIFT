import 'package:flutter/material.dart';

import '../models/estimate_request.dart';
import '../services/estimate_service.dart';
import '../theme/space_shift_colors.dart';
import '../widgets/gradient_cta_button.dart';
import '../widgets/primary_button.dart';

class EstimateRequestScreen extends StatefulWidget {
  EstimateRequestScreen({
    super.key,
    this.onSubmitted,
    this.onSiteMeetingRequested,
    EstimateService? service,
  }) : service = service ?? createEstimateService();

  final ValueChanged<EstimateRequest>? onSubmitted;

  /// 현장미팅 문의 화면이 구현되면 이 콜백에 이동 동작을 연결한다.
  final VoidCallback? onSiteMeetingRequested;

  /// 실제 접수를 담당하며 테스트에서는 가짜 구현으로 교체할 수 있다.
  final EstimateService service;

  @override
  State<EstimateRequestScreen> createState() => _EstimateRequestScreenState();
}

class _EstimateRequestScreenState extends State<EstimateRequestScreen> {
  static const List<String> _spaceTypes = [
    '거실',
    '침실',
    '주방',
    '욕실',
    '전체 공간',
    '기타',
  ];
  static const List<String> _areas = [
    '10평 미만',
    '10~20평',
    '20~30평',
    '30~40평',
    '40평 이상',
  ];
  static const List<String> _scopes = ['부분 시공', '전체 시공', '가구·스타일링', '아직 모르겠어요'];
  static const List<String> _colorTones = [
    '화이트',
    '베이지',
    '그레이',
    '우드',
    '블랙',
    '기타',
  ];

  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();
  final _customColorToneController = TextEditingController();
  String? _spaceType;
  String? _area;
  String? _scope;
  String? _colorTone;
  bool _isSubmitted = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _notesController.dispose();
    _customColorToneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final request = EstimateRequest(
      spaceType: _spaceType!,
      approximateArea: _area!,
      constructionScope: _scope!,
      desiredColorTone: _colorTone!,
      customColorTone: _colorTone == '기타'
          ? _customColorToneController.text.trim()
          : '',
      notes: _notesController.text.trim(),
    );

    setState(() => _isSubmitting = true);
    try {
      await widget.service.submit(request);
      widget.onSubmitted?.call(request);
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _isSubmitted = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('요청 접수에 실패했습니다. 다시 시도해주세요.')),
      );
    }
  }

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: SpaceShiftColors.border, width: 1.5),
      ),
    );
  }

  DropdownButtonFormField<String> _dropdown({
    required String label,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      decoration: _decoration(label),
      items: items
          .map((item) => DropdownMenuItem(value: item, child: Text(item)))
          .toList(),
      onChanged: onChanged,
      validator: (value) => value == null ? '항목을 선택해주세요.' : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpaceShiftColors.background,
      appBar: AppBar(
        title: const Text('무료 예상견적'),
        backgroundColor: SpaceShiftColors.background,
        foregroundColor: SpaceShiftColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: _isSubmitted
                  ? _buildComplete(context)
                  : _buildForm(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '간단한 정보만 알려주세요',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: SpaceShiftColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '정확한 금액은 상담 후 안내드리며, 지금은 예상견적 요청만 접수합니다.',
            style: TextStyle(
              fontSize: 16,
              color: SpaceShiftColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 28),
          _dropdown(
            label: '공간 종류',
            items: _spaceTypes,
            onChanged: (value) => _spaceType = value,
          ),
          const SizedBox(height: 16),
          _dropdown(
            label: '대략적인 면적',
            items: _areas,
            onChanged: (value) => _area = value,
          ),
          const SizedBox(height: 16),
          _dropdown(
            label: '원하는 시공 범위',
            items: _scopes,
            onChanged: (value) => _scope = value,
          ),
          const SizedBox(height: 16),
          FormField<String>(
            validator: (_) => _colorTone == null ? '색상/톤을 선택해주세요.' : null,
            builder: (field) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '원하는 색상/톤',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: SpaceShiftColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _colorTones.map((colorTone) {
                    return ChoiceChip(
                      label: SizedBox(
                        width: 82,
                        height: 44,
                        child: Center(child: Text(colorTone)),
                      ),
                      selected: _colorTone == colorTone,
                      onSelected: (_) {
                        setState(() {
                          _colorTone = colorTone;
                          if (colorTone != '기타') {
                            _customColorToneController.clear();
                          }
                        });
                        field.didChange(colorTone);
                      },
                      selectedColor: SpaceShiftColors.selectionAccent
                          .withValues(alpha: 0.15),
                      backgroundColor: Colors.white,
                      side: const BorderSide(
                        color: SpaceShiftColors.selectionAccent,
                      ),
                      labelStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: SpaceShiftColors.textPrimary,
                      ),
                    );
                  }).toList(),
                ),
                if (field.hasError) ...[
                  const SizedBox(height: 8),
                  Text(
                    field.errorText!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_colorTone == '기타') ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _customColorToneController,
              decoration: _decoration('원하는 색상/톤 직접 입력'),
              maxLength: 50,
              validator: (value) {
                if (_colorTone == '기타' &&
                    (value == null || value.trim().isEmpty)) {
                  return '원하는 색상/톤을 입력해주세요.';
                }
                return null;
              },
            ),
          ],
          const SizedBox(height: 16),
          TextFormField(
            controller: _notesController,
            maxLines: 4,
            maxLength: 300,
            decoration: _decoration(
              '간단한 요청사항 (선택)',
            ).copyWith(hintText: '예: 수납공간을 늘리고 싶어요.', alignLabelWithHint: true),
          ),
          const SizedBox(height: 12),
          GradientCtaButton(
            label: _isSubmitting ? '접수 중...' : '예상견적 요청하기',
            onPressed: _isSubmitting ? null : _submit,
          ),
        ],
      ),
    );
  }

  Widget _buildComplete(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 48),
        const Icon(
          Icons.check_circle_rounded,
          size: 80,
          color: SpaceShiftColors.selectionAccent,
        ),
        const SizedBox(height: 24),
        Text(
          '예상견적 요청이 접수되었습니다',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: SpaceShiftColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          '입력하신 내용을 확인한 뒤 상담을 통해 자세히 안내드릴게요.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            color: SpaceShiftColors.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 36),
        if (widget.onSiteMeetingRequested != null)
          PrimaryButton(
            label: '현장미팅 문의하기',
            onPressed: widget.onSiteMeetingRequested,
          ),
        if (widget.onSiteMeetingRequested != null) const SizedBox(height: 12),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('결과 화면으로 돌아가기'),
        ),
      ],
    );
  }
}
