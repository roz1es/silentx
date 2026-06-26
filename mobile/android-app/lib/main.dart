import 'dart:async';

import 'package:flutter/material.dart';

import 'config.dart';
import 'models.dart';
import 'screens/chat_list_screen.dart';
import 'screens/login_screen.dart';
import 'services/api_client.dart';
import 'services/auth_store.dart';
import 'services/messenger_controller.dart';
import 'theme/app_theme.dart';
import 'widgets/call_overlay.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BrenksChatApp());
}

class BrenksChatApp extends StatefulWidget {
  const BrenksChatApp({super.key});

  @override
  State<BrenksChatApp> createState() => _BrenksChatAppState();
}

class _BrenksChatAppState extends State<BrenksChatApp> {
  final _authStore = AuthStore();
  final _serverUrl = normalizeServerUrl(defaultApiUrl);

  bool _bootstrapping = true;
  ThemeMode _themeMode = ThemeMode.dark;
  MessengerController? _controller;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final savedTheme = await _authStore.loadTheme();
    final themeMode = savedTheme == 'light' ? ThemeMode.light : ThemeMode.dark;
    final token = await _authStore.loadToken();

    if (token == null || token.isEmpty) {
      if (!mounted) return;
      setState(() {
        _themeMode = themeMode;
        _bootstrapping = false;
      });
      return;
    }

    final api = ApiClient(baseUrl: _serverUrl, token: token);
    try {
      final user = await api.fetchMe();
      if (!mounted) return;
      setState(() {
        _themeMode = themeMode;
        _controller = _buildController(api: api, user: user, token: token)
          ..start();
        _bootstrapping = false;
      });
    } on Object {
      api.dispose();
      await _authStore.clearToken();
      if (!mounted) return;
      setState(() {
        _themeMode = themeMode;
        _bootstrapping = false;
      });
    }
  }

  MessengerController _buildController({
    required ApiClient api,
    required User user,
    required String token,
  }) {
    return MessengerController(
      api: api,
      currentUser: user,
      serverUrl: _serverUrl,
      token: token,
    );
  }

  Future<void> _handleAuthenticated(LoginResult result) async {
    await _authStore.saveServerUrl(_serverUrl);
    await _authStore.saveToken(result.token);
    final api = ApiClient(baseUrl: _serverUrl, token: result.token);
    if (!mounted) return;
    setState(() {
      _controller =
          _buildController(api: api, user: result.user, token: result.token)
            ..start();
    });
  }

  Future<void> _logout() async {
    final controller = _controller;
    if (controller != null) {
      // Лучшее усилие: сообщаем серверу и закрываем сокет.
      unawaited(controller.api.logout().catchError((_) {}));
      controller.dispose();
    }
    await _authStore.clearToken();
    if (!mounted) return;
    setState(() => _controller = null);
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    await _authStore.saveTheme(mode == ThemeMode.light ? 'light' : 'dark');
    if (!mounted) return;
    setState(() => _themeMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'БренксЧат',
      debugShowCheckedModeBanner: false,
      theme: buildBrenksLightTheme(),
      darkTheme: buildBrenksTheme(),
      themeMode: _themeMode,
      themeAnimationDuration: const Duration(milliseconds: 220),
      builder: (context, child) {
        final controller = _controller;
        return Stack(
          children: [
            child ?? const SizedBox.shrink(),
            if (controller != null) CallOverlay(controller: controller),
          ],
        );
      },
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    if (_bootstrapping) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final controller = _controller;
    if (controller == null) {
      return LoginScreen(
        onAuthenticated: _handleAuthenticated,
        themeMode: _themeMode,
        onThemeModeChanged: _setThemeMode,
      );
    }
    return ChatListScreen(
      // Пересоздаём дерево при смене пользователя/контроллера.
      key: ValueKey(controller),
      controller: controller,
      themeMode: _themeMode,
      onThemeModeChanged: _setThemeMode,
      onLogout: _logout,
    );
  }
}
