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
  final _passwordController = TextEditingController();
  final _codeController = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _ticket;
  String? _emailMasked;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  String get _serverUrl => normalizeServerUrl(widget.initialServerUrl);

  Future<void> _submitLogin() async {
    final serverUrl = _serverUrl;
    final username = _loginController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = 'Введите логин и пароль.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = ApiClient(baseUrl: serverUrl);
      final result = await api.login(username: username, password: password);
      if (!mounted) return;
      if (result.emailCodeRequired) {
        setState(() {
          _ticket = result.ticket;
          _emailMasked = result.emailMasked;
          _loading = false;
        });
        return;
      }
      widget.onAuthenticated(
        LoginPayload(
          user: result.user!,
          token: result.token!,
          serverUrl: serverUrl,
        ),
      );
    } on Object catch (err) {
      if (!mounted) return;
      setState(() {
        _error = err.toString();
        _loading = false;
      });
    }
  }

  Future<void> _submitCode() async {
    final serverUrl = _serverUrl;
    final ticket = _ticket;
    final code = _codeController.text.trim();
    if (ticket == null || code.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = ApiClient(baseUrl: serverUrl);
      final result = await api.confirmLogin(ticket: ticket, code: code);
      if (!mounted) return;
      widget.onAuthenticated(
        LoginPayload(
          user: result.user!,
          token: result.token!,
          serverUrl: serverUrl,
        ),
      );
    } on Object catch (err) {
      if (!mounted) return;
      setState(() {
        _error = err.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF24262B).withValues(alpha: 0.98),
              const Color(0xFF181A1F),
              const Color(0xFF111215),
            ],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Container(
              margin: const EdgeInsets.all(28),
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(
                color: panel.withValues(alpha: 0.86),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.28),
                    blurRadius: 40,
                    offset: const Offset(0, 22),
                  ),
                  BoxShadow(
                    color: accent.withValues(alpha: 0.035),
                    blurRadius: 0,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFFFFF4D2),
                              Color(0xFFD5B462),
                              Color(0xFF35302A),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Color(0x80FFE6A8),
                          ),
                        ),
                        child: const Center(
                          child: Text(
                            'B',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 25,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'БренксЧат',
                            style: TextStyle(
                              fontSize: 27,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Вход в аккаунт',
                            style: TextStyle(color: muted),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: _ticket == null
                        ? _LoginFields(
                            loginController: _loginController,
                            passwordController: _passwordController,
                            loading: _loading,
                            onSubmit: _submitLogin,
                          )
                        : _CodeFields(
                            codeController: _codeController,
                            emailMasked: _emailMasked ?? '',
                            loading: _loading,
                            onSubmit: _submitCode,
                            onBack: () {
                              setState(() {
                                _ticket = null;
                                _emailMasked = null;
                                _codeController.clear();
                              });
                            },
                          ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: const TextStyle(color: danger),
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

class _LoginFields extends StatelessWidget {
  const _LoginFields({
    required this.loginController,
    required this.passwordController,
    required this.loading,
    required this.onSubmit,
  });

  final TextEditingController loginController;
  final TextEditingController passwordController;
  final bool loading;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('login'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: loginController,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Логин',
            hintText: 'Ваш логин',
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: passwordController,
          obscureText: true,
          onSubmitted: (_) => loading ? null : onSubmit(),
          decoration: const InputDecoration(
            labelText: 'Пароль',
            hintText: 'Пароль',
          ),
        ),
        const SizedBox(height: 22),
        _PrimaryButton(
          loading: loading,
          label: 'Войти',
          onPressed: loading ? null : onSubmit,
        ),
      ],
    );
  }
}

class _CodeFields extends StatelessWidget {
  const _CodeFields({
    required this.codeController,
    required this.emailMasked,
    required this.loading,
    required this.onSubmit,
    required this.onBack,
  });

  final TextEditingController codeController;
  final String emailMasked;
  final bool loading;
  final VoidCallback onSubmit;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('code'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Код отправлен на $emailMasked',
          style: const TextStyle(color: muted, fontSize: 15),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: codeController,
          autofocus: true,
          onSubmitted: (_) => loading ? null : onSubmit(),
          decoration: const InputDecoration(
            labelText: 'Код подтверждения',
            hintText: '6 цифр',
          ),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: loading ? null : onBack,
                child: const Text('Назад'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PrimaryButton(
                loading: loading,
                label: 'Подтвердить',
                onPressed: loading ? null : onSubmit,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.loading,
    required this.label,
    required this.onPressed,
  });

  final bool loading;
  final String label;
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
      ),
      child: loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
    );
  }
}
