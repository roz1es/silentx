import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../models.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';

/// Полезная нагрузка успешной авторизации.
class LoginResult {
  const LoginResult({required this.user, required this.token});

  final User user;
  final String token;
}

enum _AuthMode { login, register, reset }

class _PendingCode {
  const _PendingCode({
    required this.kind,
    required this.ticket,
    required this.emailMasked,
  });

  final _AuthMode kind;
  final String ticket;
  final String emailMasked;
}

/// Экран входа / регистрации / сброса пароля в стиле веб-версии BrenksChat.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.onAuthenticated,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  final ValueChanged<LoginResult> onAuthenticated;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _resetLoginController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _codeController = TextEditingController();

  late final ApiClient _api =
      ApiClient(baseUrl: normalizeServerUrl(defaultApiUrl));

  _AuthMode _mode = _AuthMode.login;
  _PendingCode? _pending;
  bool _rememberMe = true;
  bool _loading = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _resetLoginController.dispose();
    _newPasswordController.dispose();
    _codeController.dispose();
    _api.dispose();
    super.dispose();
  }

  void _switchMode(_AuthMode next) {
    setState(() {
      _mode = next;
      _pending = null;
      _codeController.clear();
      _error = null;
      _notice = null;
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });
    try {
      final pending = _pending;
      if (pending != null) {
        await _submitPending(pending);
      } else {
        await _submitPrimary();
      }
    } on Object catch (err) {
      if (!mounted) return;
      setState(() => _error = err.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitPending(_PendingCode pending) async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Введите код из письма.');
      return;
    }

    if (pending.kind == _AuthMode.login) {
      final result = await _api.confirmLogin(
        ticket: pending.ticket,
        code: code,
        rememberMe: _rememberMe,
      );
      _finishSuccess(result);
      return;
    }

    if (pending.kind == _AuthMode.register) {
      final result =
          await _api.confirmRegister(ticket: pending.ticket, code: code);
      _finishSuccess(result);
      return;
    }

    // Сброс пароля.
    final newPassword = _newPasswordController.text;
    if (newPassword.length < 8) {
      setState(() => _error = 'Пароль должен содержать минимум 8 символов.');
      return;
    }
    await _api.confirmPasswordReset(
      ticket: pending.ticket,
      code: code,
      password: newPassword,
    );
    if (!mounted) return;
    setState(() {
      _pending = null;
      _mode = _AuthMode.login;
      _passwordController.clear();
      _newPasswordController.clear();
      _codeController.clear();
      _notice = 'Пароль обновлён. Теперь можно войти.';
    });
  }

  Future<void> _submitPrimary() async {
    if (_mode == _AuthMode.login) {
      final username = _usernameController.text.trim();
      final password = _passwordController.text;
      if (username.isEmpty || password.isEmpty) {
        setState(() => _error = 'Введите логин и пароль.');
        return;
      }
      final result = await _api.login(
        username: username,
        password: password,
        rememberMe: _rememberMe,
      );
      if (result.codeRequired) {
        _enterPending(_AuthMode.login, result.ticket!, result.emailMasked!);
      } else {
        _finishSuccess(result);
      }
      return;
    }

    if (_mode == _AuthMode.register) {
      final username = _usernameController.text.trim();
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      if (username.length < 2) {
        setState(() => _error = 'Логин должен быть не короче 2 символов.');
        return;
      }
      if (!email.contains('@')) {
        setState(() => _error = 'Укажите корректную почту.');
        return;
      }
      if (password.length < 8) {
        setState(() => _error = 'Пароль должен содержать минимум 8 символов.');
        return;
      }
      final result = await _api.register(
        username: username,
        email: email,
        password: password,
      );
      _enterPending(_AuthMode.register, result.ticket!, result.emailMasked!);
      return;
    }

    // Запрос сброса пароля.
    final login = _resetLoginController.text.trim();
    if (login.isEmpty) {
      setState(() => _error = 'Укажите логин или почту.');
      return;
    }
    final result = await _api.requestPasswordReset(login);
    if (!mounted) return;
    if (result.codeSent) {
      _enterPending(_AuthMode.reset, result.ticket!, result.emailMasked ?? '');
    } else {
      setState(() =>
          _notice = result.message ?? 'Если почта привязана, код отправлен.');
    }
  }

  void _enterPending(_AuthMode kind, String ticket, String emailMasked) {
    setState(() {
      _pending = _PendingCode(
        kind: kind,
        ticket: ticket,
        emailMasked: emailMasked,
      );
      _codeController.clear();
      _notice = 'Код отправлен на $emailMasked';
    });
  }

  void _finishSuccess(AuthResult result) {
    widget.onAuthenticated(
      LoginResult(user: result.user!, token: result.token!),
    );
  }

  String get _title {
    if (_pending != null) return 'Введите код';
    return switch (_mode) {
      _AuthMode.login => 'С возвращением',
      _AuthMode.register => 'Создаём профиль',
      _AuthMode.reset => 'Сброс пароля',
    };
  }

  String get _subtitle {
    final pending = _pending;
    if (pending != null) return 'Мы отправили письмо на ${pending.emailMasked}';
    return switch (_mode) {
      _AuthMode.login => 'Продолжайте переписку в БренксЧат',
      _AuthMode.register => 'Почта нужна для входа и сброса пароля',
      _AuthMode.reset => 'Укажите логин или почту аккаунта',
    };
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isLight
                ? const [Color(0xFFEAF2F8), Color(0xFFDDE6F0)]
                : const [Color(0xFF252A33), Color(0xFF191C22)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: _card(isLight),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(bool isLight) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: (isLight ? Colors.white : panel).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: (isLight ? Colors.black : Colors.white).withValues(alpha: 0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isLight ? 0.12 : 0.32),
            blurRadius: 42,
            offset: const Offset(0, 24),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(isLight),
          const SizedBox(height: 22),
          Text(
            _title,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(_subtitle, style: const TextStyle(color: muted)),
          const SizedBox(height: 20),
          if (_pending == null && _mode != _AuthMode.reset) ...[
            _modeSwitch(isLight),
            const SizedBox(height: 18),
          ],
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: _pending != null
                ? _codeFields()
                : _mode == _AuthMode.reset
                    ? _resetFields()
                    : _credentialFields(isLight),
          ),
          if (_notice != null) ...[
            const SizedBox(height: 14),
            _banner(_notice!, isError: false),
          ],
          if (_error != null) ...[
            const SizedBox(height: 14),
            _banner(_error!, isError: true),
          ],
          const SizedBox(height: 20),
          _PrimaryButton(
            loading: _loading,
            label: _buttonLabel,
            onPressed: _loading ? null : _submit,
          ),
          const SizedBox(height: 12),
          _footerLinks(),
        ],
      ),
    );
  }

  String get _buttonLabel {
    if (_pending != null) return 'Подтвердить';
    return switch (_mode) {
      _AuthMode.login => 'Войти',
      _AuthMode.register => 'Создать аккаунт',
      _AuthMode.reset => 'Отправить код',
    };
  }

  Widget _header(bool isLight) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: const Text(
            'B',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 24,
              color: Color(0xFF08131A),
            ),
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'БренксЧат',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              Text('Авторизация', style: TextStyle(color: muted, fontSize: 13)),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Сменить тему',
          onPressed: () => widget.onThemeModeChanged(
            isLight ? ThemeMode.dark : ThemeMode.light,
          ),
          icon: Icon(isLight ? Icons.dark_mode_rounded : Icons.light_mode_rounded),
        ),
      ],
    );
  }

  Widget _modeSwitch(bool isLight) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: (isLight ? Colors.black : Colors.white).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _modeTab('Вход', _AuthMode.login, isLight),
          _modeTab('Регистрация', _AuthMode.register, isLight),
        ],
      ),
    );
  }

  Widget _modeTab(String label, _AuthMode mode, bool isLight) {
    final selected = _mode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => _switchMode(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected
                ? (isLight ? Colors.white : panelStrong)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: selected ? null : muted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _credentialFields(bool isLight) {
    return Column(
      key: const ValueKey('credentials'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _usernameController,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.username],
          decoration: const InputDecoration(
            labelText: 'Имя пользователя',
            hintText: 'Ваш логин',
            prefixIcon: Icon(Icons.alternate_email_rounded),
          ),
        ),
        if (_mode == _AuthMode.register) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(
              labelText: 'Почта',
              hintText: 'mail@example.com',
              prefixIcon: Icon(Icons.mail_outline_rounded),
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _passwordController,
          obscureText: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _loading ? null : _submit(),
          decoration: const InputDecoration(
            labelText: 'Пароль',
            hintText: 'Пароль',
            prefixIcon: Icon(Icons.lock_outline_rounded),
          ),
        ),
        if (_mode == _AuthMode.login) ...[
          const SizedBox(height: 12),
          _rememberMeTile(isLight),
        ],
      ],
    );
  }

  Widget _rememberMeTile(bool isLight) {
    return Material(
      color: (isLight ? Colors.black : Colors.white).withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(16),
      child: SwitchListTile(
        value: _rememberMe,
        onChanged: (value) => setState(() => _rememberMe = value),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Запомнить меня',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        subtitle: const Text(
          'Не выходить на этом устройстве 30 дней',
          style: TextStyle(color: muted, fontSize: 12),
        ),
        activeColor: accent,
      ),
    );
  }

  Widget _resetFields() {
    return Column(
      key: const ValueKey('reset'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _resetLoginController,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _loading ? null : _submit(),
          decoration: const InputDecoration(
            labelText: 'Логин или почта',
            hintText: 'login или mail@example.com',
            prefixIcon: Icon(Icons.person_search_rounded),
          ),
        ),
      ],
    );
  }

  Widget _codeFields() {
    final isReset = _pending?.kind == _AuthMode.reset;
    return Column(
      key: const ValueKey('code'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _codeController,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          autofillHints: const [AutofillHints.oneTimeCode],
          textInputAction: isReset ? TextInputAction.next : TextInputAction.done,
          onSubmitted: (_) => _loading ? null : _submit(),
          decoration: const InputDecoration(
            labelText: 'Код из письма',
            hintText: '123456',
            prefixIcon: Icon(Icons.password_rounded),
          ),
        ),
        if (isReset) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _newPasswordController,
            obscureText: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _loading ? null : _submit(),
            decoration: const InputDecoration(
              labelText: 'Новый пароль',
              hintText: 'Минимум 8 символов',
              prefixIcon: Icon(Icons.lock_reset_rounded),
            ),
          ),
        ],
      ],
    );
  }

  Widget _footerLinks() {
    if (_pending != null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () => setState(() {
            _pending = null;
            _error = null;
            _notice = null;
          }),
          child: const Text('Назад'),
        ),
      );
    }
    if (_mode == _AuthMode.reset) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () => _switchMode(_AuthMode.login),
          child: const Text('Вернуться ко входу'),
        ),
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        TextButton(
          onPressed: () => _switchMode(_AuthMode.reset),
          child: const Text('Забыли пароль?'),
        ),
        if (_mode == _AuthMode.login)
          const Text(
            'Код придёт на почту',
            style: TextStyle(color: muted, fontSize: 12),
          ),
      ],
    );
  }

  Widget _banner(String text, {required bool isError}) {
    final color = isError ? danger : const Color(0xFF4AAE8A);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 14)),
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
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: accent,
        foregroundColor: const Color(0xFF08131A),
      ),
      child: loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }
}
