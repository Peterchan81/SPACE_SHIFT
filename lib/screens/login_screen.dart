import 'package:flutter/material.dart';

import '../theme/space_shift_colors.dart';
import '../widgets/gradient_cta_button.dart';
import 'home_screen.dart';
import 'signup_screen.dart';

/// MASTER UI 1번 화면 — 로그인 / 자동로그인.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _autoLogin = true;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _enterApp() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => const HomeScreen(),
        settings: const RouteSettings(name: 'home'),
      ),
    );
  }

  void _goToSignup() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const SignupScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpaceShiftColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  const Center(child: _SpaceShiftLogoMark()),
                  const SizedBox(height: 20),
                  const Text(
                    'SPACE SHIFT',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: SpaceShiftColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '공간의 변화, 당신의 방식으로',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: SpaceShiftColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      hintText: '이메일',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      hintText: '비밀번호',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: _autoLogin,
                          activeColor: SpaceShiftColors.selectionAccent,
                          onChanged: (value) =>
                              setState(() => _autoLogin = value ?? false),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '자동 로그인',
                        style: TextStyle(
                          fontSize: 13,
                          color: SpaceShiftColors.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _enterApp,
                        child: const Text(
                          '비밀번호 찾기',
                          style: TextStyle(
                            fontSize: 13,
                            color: SpaceShiftColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  GradientCtaButton(label: '로그인', onPressed: _enterApp),
                  const SizedBox(height: 28),
                  Row(
                    children: const [
                      Expanded(child: Divider(color: SpaceShiftColors.border)),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          '간편 로그인',
                          style: TextStyle(
                            fontSize: 12,
                            color: SpaceShiftColors.textSecondary,
                          ),
                        ),
                      ),
                      Expanded(child: Divider(color: SpaceShiftColors.border)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _SocialLoginButton(
                        icon: Icons.g_mobiledata_rounded,
                        background: const Color(0xFFF2F2F2),
                        foreground: const Color(0xFF1F2933),
                        onTap: _enterApp,
                      ),
                      const SizedBox(width: 18),
                      _SocialLoginButton(
                        icon: Icons.chat_bubble_rounded,
                        background: const Color(0xFFFEE500),
                        foreground: const Color(0xFF3C1E1E),
                        onTap: _enterApp,
                      ),
                      const SizedBox(width: 18),
                      _SocialLoginButton(
                        icon: Icons.apple_rounded,
                        background: const Color(0xFF1F2933),
                        foreground: Colors.white,
                        onTap: _enterApp,
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        '계정이 없으신가요?',
                        style: TextStyle(
                          fontSize: 13,
                          color: SpaceShiftColors.textSecondary,
                        ),
                      ),
                      TextButton(
                        onPressed: _goToSignup,
                        child: const Text(
                          '회원가입',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: SpaceShiftColors.selectionAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SpaceShiftLogoMark extends StatelessWidget {
  const _SpaceShiftLogoMark();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 78,
      height: 80,
      child: Image.asset(
        'assets/icons/space_shift_symbol.png',
        fit: BoxFit.contain,
      ),
    );
  }
}

class _SocialLoginButton extends StatelessWidget {
  const _SocialLoginButton({
    required this.icon,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 52,
          height: 52,
          child: Icon(icon, color: foreground),
        ),
      ),
    );
  }
}