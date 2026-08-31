import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/image_picker_service.dart';
import '../theme/space_shift_colors.dart';
import '../widgets/gradient_cta_button.dart';
import 'photo_select_screen.dart';

/// MASTER UI 1번 화면(회원가입 상태) — 이름/이메일/비밀번호와 약관 동의로
/// 신규 계정을 만드는 화면.
///
/// 휴대폰 MASTER의 디자인 언어(테두리 반경/선 두께/타이포그래피/그라디언트/
/// 색상/아이콘)와 기능은 그대로 유지하되, Galaxy Tab 가로 화면에서는 좁은
/// 폼 하나를 화면 가운데 길게 늘어뜨리지 않고 왼쪽(제목+프로필 사진)/
/// 오른쪽(입력 폼) 2열로 재배치해 세로 스크롤 없이 한 화면에 들어오게
/// 한다(WorkspaceScreen의 isWide 관례와 동일한 800px 기준).
///
/// 실제 인증 백엔드가 없으므로 입력값 검증(필수 항목, 비밀번호 일치, 약관
/// 동의)만 수행하고, 통과하면 곧바로 앱 사용 흐름(사진 선택 화면)으로
/// 진입시킨다.
class SignupScreen extends StatefulWidget {
  const SignupScreen({
    super.key,
    this.imagePickerService = const ImagePickerService(),
  });

  final ImagePickerService imagePickerService;

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmController = TextEditingController();
  bool _agreed = false;
  bool _obscurePassword = true;
  bool _obscurePasswordConfirm = true;
  Uint8List? _profileImageBytes;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    super.dispose();
  }

  Future<void> _pickProfileImage() async {
    try {
      final bytes = await widget.imagePickerService.pickGalleryImage();
      if (bytes == null || !mounted) return;
      setState(() => _profileImageBytes = bytes);
    } catch (_) {
      // 프로필 사진은 선택 항목이므로 실패해도 조용히 무시한다.
    }
  }

  String? _requiredValidator(String? value) {
    return (value == null || value.trim().isEmpty) ? '필수 항목입니다.' : null;
  }

  void _submit() {
    final formOk = _formKey.currentState?.validate() ?? false;
    if (!formOk) return;
    if (_passwordController.text != _passwordConfirmController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('비밀번호가 일치하지 않습니다.')),
      );
      return;
    }
    if (!_agreed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이용약관 및 개인정보처리방침에 동의해주세요.')),
      );
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => const PhotoSelectScreen(),
        settings: const RouteSettings(name: 'photo_select'),
      ),
    );
  }

  /// 이용약관/개인정보처리방침 원문을 Tablet에 적합한 바텀시트로 보여준다.
  ///
  /// 저장소 전체를 조사했지만 SPACE SHIFT 자체의 실제 약관/개인정보처리방침
  /// 원문(법률 문서)은 어디에도 없다 — 임의로 법률 문서를 만들어 넣지
  /// 않고, 원문이 등록되면 그대로 표시할 수 있는 UI 구조와 진입 지점만
  /// 먼저 연결해 둔다.
  void _showPolicyDocument(String title) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SpaceShiftColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => _PolicyDocumentSheet(title: title),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpaceShiftColors.background,
      appBar: AppBar(
        backgroundColor: SpaceShiftColors.background,
        foregroundColor: SpaceShiftColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text('회원가입'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Form(
                key: _formKey,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 800;
                    return isWide
                        ? _buildWideBody(context)
                        : _buildNarrowBody(context);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 휴대폰 등 좁은 화면 — MASTER의 세로형 구성을 그대로 유지한다.
  Widget _buildNarrowBody(BuildContext context) {
    return SingleChildScrollView(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildProfilePicker(),
            const SizedBox(height: 24),
            ..._buildFormFields(),
          ],
        ),
      ),
    );
  }

  /// Galaxy Tab 가로 화면 — 왼쪽(제목+프로필 사진)/오른쪽(입력 폼) 2열로
  /// 재배치해 세로 스크롤 없이 한 화면에 들어오게 한다. 입력창 폭은
  /// 휴대폰과 동일하게 유지한다(오른쪽 열도 460으로 제한).
  Widget _buildWideBody(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 300,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '회원가입',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: SpaceShiftColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'SPACE SHIFT 계정을 만들고\n공간의 변화를 시작해보세요.',
                  style: TextStyle(
                    fontSize: 14,
                    color: SpaceShiftColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 32),
                _buildProfilePicker(),
              ],
            ),
          ),
        ),
        const SizedBox(width: 40),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _buildFormFields(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfilePicker() {
    return Column(
      children: [
        GestureDetector(
          onTap: _pickProfileImage,
          child: Container(
            width: 88,
            height: 88,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: const Color(0xFFF7F8FA),
              shape: BoxShape.circle,
              border: Border.all(color: SpaceShiftColors.border),
            ),
            child: _profileImageBytes == null
                ? const Icon(
                    Icons.camera_alt_rounded,
                    size: 30,
                    color: SpaceShiftColors.textSecondary,
                  )
                : Image.memory(
                    _profileImageBytes!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                  ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '프로필 사진 (선택)',
          style: TextStyle(fontSize: 12, color: SpaceShiftColors.textSecondary),
        ),
      ],
    );
  }

  /// 이름/이메일/비밀번호/비밀번호 확인/약관 동의/가입 버튼/로그인 링크.
  /// 좁은 화면의 세로 스크롤 안, 넓은 화면의 오른쪽 열 양쪽에서 그대로
  /// 재사용한다.
  List<Widget> _buildFormFields() {
    return [
      TextFormField(
        controller: _nameController,
        decoration: const InputDecoration(hintText: '이름'),
        validator: _requiredValidator,
      ),
      const SizedBox(height: 14),
      TextFormField(
        controller: _emailController,
        keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(hintText: '이메일'),
        validator: _requiredValidator,
      ),
      const SizedBox(height: 14),
      TextFormField(
        controller: _passwordController,
        obscureText: _obscurePassword,
        decoration: InputDecoration(
          hintText: '비밀번호',
          suffixIcon: IconButton(
            onPressed: () =>
                setState(() => _obscurePassword = !_obscurePassword),
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
          ),
        ),
        validator: _requiredValidator,
      ),
      const SizedBox(height: 14),
      TextFormField(
        controller: _passwordConfirmController,
        obscureText: _obscurePasswordConfirm,
        decoration: InputDecoration(
          hintText: '비밀번호 확인',
          suffixIcon: IconButton(
            onPressed: () => setState(
              () => _obscurePasswordConfirm = !_obscurePasswordConfirm,
            ),
            icon: Icon(
              _obscurePasswordConfirm
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
          ),
        ),
        validator: _requiredValidator,
      ),
      const SizedBox(height: 14),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: _agreed,
              activeColor: SpaceShiftColors.selectionAccent,
              onChanged: (value) => setState(() => _agreed = value ?? false),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () => _showPolicyDocument('이용약관'),
                    child: const Text(
                      '이용약관',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: SpaceShiftColors.selectionAccent,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  const Text(
                    ' 및 ',
                    style: TextStyle(
                      fontSize: 13,
                      color: SpaceShiftColors.textSecondary,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _showPolicyDocument('개인정보처리방침'),
                    child: const Text(
                      '개인정보처리방침',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: SpaceShiftColors.selectionAccent,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  const Text(
                    '에 동의합니다.',
                    style: TextStyle(
                      fontSize: 13,
                      color: SpaceShiftColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 20),
      GradientCtaButton(label: '회원가입', onPressed: _submit),
      const SizedBox(height: 20),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            '이미 계정이 있으신가요?',
            style: TextStyle(fontSize: 13, color: SpaceShiftColors.textSecondary),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              '로그인',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: SpaceShiftColors.selectionAccent,
              ),
            ),
          ),
        ],
      ),
    ];
  }
}

/// 이용약관/개인정보처리방침 내용을 보여주는 바텀시트.
///
/// SPACE SHIFT 저장소에는 아직 실제 법률 문서 원문이 없다 — 임의로 약관
/// 내용을 만들어 채우지 않고, 원문이 준비되는 즉시 이 화면에 그대로
/// 표시할 수 있도록 구조(제목 + 스크롤 가능한 본문 + 닫기)만 먼저
/// 연결해 둔다.
class _PolicyDocumentSheet extends StatelessWidget {
  const _PolicyDocumentSheet({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.7,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: SpaceShiftColors.border,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: SpaceShiftColors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: SpaceShiftColors.border),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Text(
                  '$title 원문이 아직 등록되지 않았습니다.\n'
                  '서비스 운영 정책이 확정되는 대로 이 화면에 실제 $title 전문이 표시됩니다.',
                  style: const TextStyle(
                    fontSize: 14,
                    color: SpaceShiftColors.textSecondary,
                    height: 1.6,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
