import 'package:flutter/material.dart';

import '../models/site_meeting_request.dart';
import '../widgets/primary_button.dart';

class SiteMeetingRequestScreen extends StatefulWidget {
  const SiteMeetingRequestScreen({super.key, this.onSubmitted});

  final ValueChanged<SiteMeetingRequest>? onSubmitted;

  @override
  State<SiteMeetingRequestScreen> createState() =>
      _SiteMeetingRequestScreenState();
}

class _SiteMeetingRequestScreenState extends State<SiteMeetingRequestScreen> {
  static const Color _ivoryBackground = Color(0xFFFFF8E7);
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _contactController = TextEditingController();
  final _areaController = TextEditingController();
  final _dateTimeController = TextEditingController();
  final _notesController = TextEditingController();
  bool _privacyAgreed = false;
  bool _isSubmitted = false;

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    _areaController.dispose();
    _dateTimeController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD7CCC8), width: 1.5),
      ),
    );
  }

  String? _required(String? value) {
    return value == null || value.trim().isEmpty ? '필수 항목입니다.' : null;
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    widget.onSubmitted?.call(
      SiteMeetingRequest(
        name: _nameController.text.trim(),
        contact: _contactController.text.trim(),
        visitArea: _areaController.text.trim(),
        preferredDateTime: _dateTimeController.text.trim(),
        notes: _notesController.text.trim(),
        privacyAgreed: _privacyAgreed,
      ),
    );
    setState(() => _isSubmitted = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ivoryBackground,
      appBar: AppBar(
        title: const Text('현장미팅 문의'),
        backgroundColor: _ivoryBackground,
        foregroundColor: const Color(0xFF3E2723),
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
            '방문 상담에 필요한 정보만 알려주세요',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: const Color(0xFF3E2723),
            ),
          ),
          const SizedBox(height: 24),
          TextFormField(
            key: const ValueKey('meeting_name'),
            controller: _nameController,
            decoration: _decoration('이름'),
            validator: _required,
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const ValueKey('meeting_contact'),
            controller: _contactController,
            keyboardType: TextInputType.phone,
            decoration: _decoration('연락처', hint: '예: 010-1234-5678'),
            validator: _required,
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const ValueKey('meeting_area'),
            controller: _areaController,
            decoration: _decoration('희망 방문 지역', hint: '예: 서울시 강남구'),
            validator: _required,
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const ValueKey('meeting_datetime'),
            controller: _dateTimeController,
            decoration: _decoration('희망 날짜/시간', hint: '예: 8월 20일 오후 2시'),
            validator: _required,
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const ValueKey('meeting_notes'),
            controller: _notesController,
            maxLines: 4,
            maxLength: 300,
            decoration: _decoration('간단한 요청사항 (선택)'),
          ),
          FormField<bool>(
            initialValue: false,
            validator: (value) =>
                value == true ? null : '개인정보 수집 및 이용에 동의해주세요.',
            builder: (field) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text(
                    '개인정보 수집 및 이용에 동의합니다. (필수)',
                    style: TextStyle(fontSize: 15, color: Color(0xFF3E2723)),
                  ),
                  value: _privacyAgreed,
                  onChanged: (value) {
                    setState(() => _privacyAgreed = value ?? false);
                    field.didChange(_privacyAgreed);
                  },
                ),
                if (field.hasError)
                  Padding(
                    padding: const EdgeInsets.only(left: 12, bottom: 8),
                    child: Text(
                      field.errorText!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          PrimaryButton(label: '현장미팅 문의하기', onPressed: _submit),
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
          color: Color(0xFF8D6E63),
        ),
        const SizedBox(height: 24),
        Text(
          '현장미팅 문의가 접수되었습니다',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: const Color(0xFF3E2723),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          '입력하신 연락처로 방문 일정을 안내드릴게요.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Color(0xFF5D4037)),
        ),
        const SizedBox(height: 36),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('이전 화면으로 돌아가기'),
        ),
      ],
    );
  }
}
