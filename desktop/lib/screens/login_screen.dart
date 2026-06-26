import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../config.dart';
import '../models.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';

class LoginPayload {
  const LoginPayload({
    required this.user,
    required this.token,
    required this.serverUrl,
  });

  final User user;
  final String token;
  final String serverUrl;
}

enum _AuthMode { login, register, reset }

enum _CodePurpose { login, register, reset }

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.initialServerUrl,
    required this.onAuthenticated,
  });

  final String initialServerUrl;
  final ValueChanged<LoginPayload> onAuthenticated;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _loginController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _codeController = TextEditingController();

  _AuthMode _mode = _AuthMode.login;
  _CodePurpose? _codePurpose;
  bool _loading = false;
  String? _error;
  String? _notice;
  String? _ticket;
  String? _emailMasked;

  @override
  void dispose() {
    _loginController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  String get _serverUrl => normalizeServerUrl(widget.initialServerUrl);

  void _switchMode(_AuthMode mode) {
    if (_loading || _mode == mode) return;
    setState(() {
      _mode = mode;
      _error = null;
      _notice = null;
      _ticket = null;
      _emailMasked = null;
      _codePurpose = null;
      _codeController.clear();
      if (mode == _AuthMode.reset) {
        _passwordController.clear();
      }
    });
  }

  Future<void> _submitLogin() async {
    final username = _loginController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = 'Введите логин и пароль.');
      return;
    }

    await _runAuth(() async {
      final api = ApiClient(baseUrl: _serverUrl);
      final result = await api.login(username: username, password: password);
      if (result.emailCodeRequired) {
        _showCodeStep(
          purpose: _CodePurpose.login,
          ticket: result.ticket,
          emailMasked: result.emailMasked,
        );
        return;
      }
      _completeAuth(result);
    });
  }

  Future<void> _submitRegister() async {
    final username = _loginController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Заполните логин, почту и пароль.');
      return;
    }
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _error = 'Введите корректную почту.');
      return;
    }
    if (password.length < 8) {
      setState(() => _error = 'Пароль должен быть не короче 8 символов.');
      return;
    }

    await _runAuth(() async {
      final api = ApiClient(baseUrl: _serverUrl);
      final result = await api.register(
        username: username,
        email: email,
        password: password,
      );
      if (result.emailCodeRequired) {
        _showCodeStep(
          purpose: _CodePurpose.register,
          ticket: result.ticket,
          emailMasked: result.emailMasked,
        );
        return;
      }
      _completeAuth(result);
    });
  }

  Future<void> _submitResetRequest() async {
    final login = _loginController.text.trim();
    if (login.isEmpty) {
      setState(() => _error = 'Введите логин или почту аккаунта.');
      return;
    }

    await _runAuth(() async {
      final api = ApiClient(baseUrl: _serverUrl);
      final result = await api.requestPasswordReset(login: login);
      if (result.ticket == null || result.ticket!.isEmpty) {
        setState(() {
          _loading = false;
          _notice = result.message ??
              'Если почта привязана к аккаунту, мы отправили код.';
        });
        return;
      }
      _showCodeStep(
        purpose: _CodePurpose.reset,
        ticket: result.ticket,
        emailMasked: result.emailMasked,
      );
    });
  }

  Future<void> _submitCode() async {
    final ticket = _ticket;
    final purpose = _codePurpose;
    final code = _codeController.text.trim();
    if (ticket == null || purpose == null || code.isEmpty) return;

    await _runAuth(() async {
      final api = ApiClient(baseUrl: _serverUrl);
      if (purpose == _CodePurpose.reset) {
        final password = _passwordController.text;
        if (password.length < 8) {
          throw ApiException('Пароль должен быть не короче 8 символов.');
        }
        await api.confirmPasswordReset(
          ticket: ticket,
          code: code,
          password: password,
        );
        if (!mounted) return;
        setState(() {
          _mode = _AuthMode.login;
          _ticket = null;
          _emailMasked = null;
          _codePurpose = null;
          _codeController.clear();
          _passwordController.clear();
          _loading = false;
          _notice = 'Пароль обновлён. Теперь можно войти.';
        });
        return;
      }
      final result = purpose == _CodePurpose.register
          ? await api.confirmRegister(ticket: ticket, code: code)
          : await api.confirmLogin(ticket: ticket, code: code);
      _completeAuth(result);
    });
  }

  Future<void> _runAuth(Future<void> Function() action) async {
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
    } on Object catch (err) {
      if (!mounted) return;
      setState(() {
        _error = err.toString();
        _loading = false;
      });
    }
  }

  void _showCodeStep({
    required _CodePurpose purpose,
    required String? ticket,
    required String? emailMasked,
  }) {
    if (!mounted) return;
    setState(() {
      _ticket = ticket;
      _emailMasked = emailMasked;
      _codePurpose = purpose;
      _codeController.clear();
      if (purpose == _CodePurpose.reset) _passwordController.clear();
      _loading = false;
    });
  }

  void _completeAuth(AuthResult result) {
    if (!mounted) return;
    widget.onAuthenticated(
      LoginPayload(
        user: result.user!,
        token: result.token!,
        serverUrl: _serverUrl,
      ),
    );
  }

  void _backFromCode() {
    setState(() {
      _ticket = null;
      _emailMasked = null;
      _codePurpose = null;
      _codeController.clear();
      _error = null;
      _notice = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isCodeStep = _ticket != null;
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: _LoginBackground()),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(34),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xD21F2228),
                        borderRadius: BorderRadius.circular(34),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.095),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.32),
                            blurRadius: 46,
                            offset: const Offset(0, 24),
                          ),
                          BoxShadow(
                            color: accent.withValues(alpha: 0.08),
                            blurRadius: 34,
                            offset: const Offset(0, -8),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(26),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _LoginHeader(
                              subtitle: isCodeStep
                                  ? 'Подтверждение почты'
                                  : _mode == _AuthMode.login
                                      ? 'Вход в аккаунт'
                                      : _mode == _AuthMode.register
                                          ? 'Создание аккаунта'
                                          : 'Восстановление доступа',
                            ),
                            const SizedBox(height: 24),
                            if (!isCodeStep)
                              _AuthModeSwitcher(
                                mode: _mode,
                                onChanged: _switchMode,
                              ),
                            if (!isCodeStep) const SizedBox(height: 22),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              child: isCodeStep
                                  ? _CodeFields(
                                      key: const ValueKey('code'),
                                      codeController: _codeController,
                                      passwordController: _passwordController,
                                      emailMasked: _emailMasked ?? '',
                                      loading: _loading,
                                      purpose: _codePurpose,
                                      onSubmit: _submitCode,
                                      onBack: _backFromCode,
                                    )
                                  : _mode == _AuthMode.login
                                      ? _LoginFields(
                                          key: const ValueKey('login'),
                                          loginController: _loginController,
                                          passwordController:
                                              _passwordController,
                                          loading: _loading,
                                          onSubmit: _submitLogin,
                                          onForgotPassword: () =>
                                              _switchMode(_AuthMode.reset),
                                        )
                                      : _mode == _AuthMode.register
                                          ? _RegisterFields(
                                              key: const ValueKey('register'),
                                              loginController: _loginController,
                                              emailController: _emailController,
                                              passwordController:
                                                  _passwordController,
                                              loading: _loading,
                                              onSubmit: _submitRegister,
                                            )
                                          : _ResetRequestFields(
                                              key: const ValueKey('reset'),
                                              loginController: _loginController,
                                              loading: _loading,
                                              onSubmit: _submitResetRequest,
                                              onBack: () =>
                                                  _switchMode(_AuthMode.login),
                                            ),
                            ),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              child: _notice == null
                                  ? const SizedBox.shrink()
                                  : Padding(
                                      key: ValueKey(_notice),
                                      padding: const EdgeInsets.only(top: 16),
                                      child: _InfoBanner(message: _notice!),
                                    ),
                            ),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              child: _error == null
                                  ? const SizedBox.shrink()
                                  : Padding(
                                      key: ValueKey(_error),
                                      padding: const EdgeInsets.only(top: 16),
                                      child: _ErrorBanner(text: _error!),
                                    ),
                            ),
                          ],
                        ),
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
}

class _LoginBackground extends StatelessWidget {
  const _LoginBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF24262B),
            Color(0xFF17191D),
            Color(0xFF0F1013),
          ],
        ),
      ),
      child: CustomPaint(
        painter: _LoginPatternPainter(),
        child: Stack(
          children: [
            Positioned(
              left: -120,
              top: -90,
              child: _GlowCircle(
                size: 300,
                color: accent.withValues(alpha: 0.13),
              ),
            ),
            Positioned(
              right: -110,
              bottom: -120,
              child: _GlowCircle(
                size: 340,
                color: const Color(0xFFFFE6A8).withValues(alpha: 0.08),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlowCircle extends StatelessWidget {
  const _GlowCircle({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color,
              blurRadius: 120,
              spreadRadius: 40,
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginHeader extends StatelessWidget {
  const _LoginHeader({required this.subtitle});

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFFF4D2),
                Color(0xFFD8B76C),
                Color(0xFF3C3427),
              ],
            ),
            borderRadius: BorderRadius.circular(21),
            border: Border.all(color: const Color(0x80FFE6A8)),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.2),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Center(
            child: Text(
              'B',
              style: TextStyle(
                color: Color(0xFF111215),
                fontWeight: FontWeight.w900,
                fontSize: 26,
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'БренксЧат',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(color: muted, fontSize: 14.5),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AuthModeSwitcher extends StatelessWidget {
  const _AuthModeSwitcher({
    required this.mode,
    required this.onChanged,
  });

  final _AuthMode mode;
  final ValueChanged<_AuthMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: const Color(0x8A141619),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.075)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModeButton(
              selected: mode == _AuthMode.login,
              icon: Icons.login_rounded,
              label: 'Вход',
              onTap: () => onChanged(_AuthMode.login),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _ModeButton(
              selected: mode == _AuthMode.register,
              icon: Icons.person_add_alt_1_rounded,
              label: 'Регистрация',
              onTap: () => onChanged(_AuthMode.register),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: selected
            ? accent.withValues(alpha: 0.14)
            : Colors.white.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(
          color: selected
              ? accent.withValues(alpha: 0.26)
              : Colors.white.withValues(alpha: 0.045),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(19),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: selected ? accent : muted),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: selected ? text : muted,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoginFields extends StatelessWidget {
  const _LoginFields({
    super.key,
    required this.loginController,
    required this.passwordController,
    required this.loading,
    required this.onSubmit,
    required this.onForgotPassword,
  });

  final TextEditingController loginController;
  final TextEditingController passwordController;
  final bool loading;
  final VoidCallback onSubmit;
  final VoidCallback onForgotPassword;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GlassTextField(
          controller: loginController,
          label: 'Логин',
          hint: '@username',
          icon: Icons.alternate_email_rounded,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 14),
        _GlassTextField(
          controller: passwordController,
          label: 'Пароль',
          hint: 'Ваш пароль',
          icon: Icons.lock_outline_rounded,
          obscureText: true,
          onSubmitted: (_) => loading ? null : onSubmit(),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: loading ? null : onForgotPassword,
            icon: const Icon(Icons.help_outline_rounded, size: 18),
            label: const Text('Забыл пароль'),
            style: TextButton.styleFrom(
              foregroundColor: accent,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _PrimaryButton(
          loading: loading,
          label: 'Войти',
          icon: Icons.arrow_forward_rounded,
          onPressed: loading ? null : onSubmit,
        ),
      ],
    );
  }
}

class _ResetRequestFields extends StatelessWidget {
  const _ResetRequestFields({
    super.key,
    required this.loginController,
    required this.loading,
    required this.onSubmit,
    required this.onBack,
  });

  final TextEditingController loginController;
  final bool loading;
  final VoidCallback onSubmit;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: accent.withValues(alpha: 0.14)),
          ),
          child: const Row(
            children: [
              Icon(Icons.lock_reset_rounded, color: accent, size: 28),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Введите @username или почту. Если аккаунт найден, мы отправим код восстановления.',
                  style: TextStyle(color: muted, height: 1.25),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _GlassTextField(
          controller: loginController,
          label: 'Аккаунт',
          hint: '@username или mail@example.com',
          icon: Icons.alternate_email_rounded,
          onSubmitted: (_) => loading ? null : onSubmit(),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(
              child: _SecondaryButton(
                label: 'Назад',
                onPressed: loading ? null : onBack,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PrimaryButton(
                loading: loading,
                label: 'Получить код',
                icon: Icons.mail_outline_rounded,
                onPressed: loading ? null : onSubmit,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RegisterFields extends StatelessWidget {
  const _RegisterFields({
    super.key,
    required this.loginController,
    required this.emailController,
    required this.passwordController,
    required this.loading,
    required this.onSubmit,
  });

  final TextEditingController loginController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool loading;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GlassTextField(
          controller: loginController,
          label: 'Юзернейм',
          hint: '@username',
          icon: Icons.alternate_email_rounded,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 14),
        _GlassTextField(
          controller: emailController,
          label: 'Почта',
          hint: 'mail@example.com',
          icon: Icons.mail_outline_rounded,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 14),
        _GlassTextField(
          controller: passwordController,
          label: 'Пароль',
          hint: 'Минимум 8 символов',
          icon: Icons.lock_outline_rounded,
          obscureText: true,
          onSubmitted: (_) => loading ? null : onSubmit(),
        ),
        const SizedBox(height: 22),
        _PrimaryButton(
          loading: loading,
          label: 'Создать аккаунт',
          icon: Icons.person_add_alt_1_rounded,
          onPressed: loading ? null : onSubmit,
        ),
      ],
    );
  }
}

class _CodeFields extends StatelessWidget {
  const _CodeFields({
    super.key,
    required this.codeController,
    required this.passwordController,
    required this.emailMasked,
    required this.loading,
    required this.purpose,
    required this.onSubmit,
    required this.onBack,
  });

  final TextEditingController codeController;
  final TextEditingController passwordController;
  final String emailMasked;
  final bool loading;
  final _CodePurpose? purpose;
  final VoidCallback onSubmit;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final title = purpose == _CodePurpose.register
        ? 'Подтвердите регистрацию'
        : purpose == _CodePurpose.reset
            ? 'Сброс пароля'
            : 'Подтвердите вход';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.075),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: accent.withValues(alpha: 0.16)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.13),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mark_email_read_rounded, color: accent),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Код отправлен на $emailMasked',
                      style: const TextStyle(color: muted, fontSize: 13.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _GlassTextField(
          controller: codeController,
          label: 'Код подтверждения',
          hint: '6 цифр',
          icon: Icons.password_rounded,
          autofocus: true,
          keyboardType: TextInputType.number,
          onSubmitted: (_) => loading ? null : onSubmit(),
        ),
        if (purpose == _CodePurpose.reset) ...[
          const SizedBox(height: 14),
          _GlassTextField(
            controller: passwordController,
            label: 'Новый пароль',
            hint: 'Минимум 8 символов',
            icon: Icons.lock_outline_rounded,
            obscureText: true,
            onSubmitted: (_) => loading ? null : onSubmit(),
          ),
        ],
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(
              child: _SecondaryButton(
                label: 'Назад',
                onPressed: loading ? null : onBack,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PrimaryButton(
                loading: loading,
                label: 'Подтвердить',
                icon: Icons.check_rounded,
                onPressed: loading ? null : onSubmit,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _GlassTextField extends StatelessWidget {
  const _GlassTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.autofocus = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final bool autofocus;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      autofocus: autofocus,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: danger.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: danger, size: 19),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: danger, fontSize: 13.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline_rounded,
              color: accent, size: 19),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: text, fontSize: 13.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        foregroundColor: text,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.loading,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final bool loading;
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        backgroundColor: accent,
        foregroundColor: const Color(0xFF08131A),
        disabledBackgroundColor: accent.withValues(alpha: 0.38),
        disabledForegroundColor:
            const Color(0xFF08131A).withValues(alpha: 0.65),
      ),
      child: loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(width: 8),
                Icon(icon, size: 19),
              ],
            ),
    );
  }
}

class _LoginPatternPainter extends CustomPainter {
  const _LoginPatternPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = accent.withValues(alpha: 0.028)
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round;

    const gap = 52.0;
    const arm = 5.0;
    for (double y = 26; y < size.height; y += gap) {
      for (double x = 26; x < size.width; x += gap) {
        canvas.drawLine(Offset(x - arm, y), Offset(x + arm, y), paint);
        canvas.drawLine(Offset(x, y - arm), Offset(x, y + arm), paint);
      }
    }

    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.026)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 160) {
      canvas.drawLine(Offset(x, 0), Offset(x + 180, size.height), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
