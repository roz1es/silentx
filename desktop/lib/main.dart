import 'dart:async';

import 'package:flutter/material.dart';

import 'config.dart';
import 'models.dart';
import 'screens/login_screen.dart';
import 'screens/messenger_screen.dart';
import 'services/api_client.dart';
import 'services/auth_store.dart';
import 'services/auto_update_service.dart';
import 'theme/app_theme.dart';
import 'widgets/update_dialog.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BrenksChatDesktopApp());
}

class BrenksChatDesktopApp extends StatefulWidget {
  const BrenksChatDesktopApp({super.key});

  @override
  State<BrenksChatDesktopApp> createState() => _BrenksChatDesktopAppState();
}

class _BrenksChatDesktopAppState extends State<BrenksChatDesktopApp> {
  final _authStore = AuthStore();
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _updater = const AutoUpdateService();
  bool _bootstrapping = true;
  bool _updateChecked = false;
  String _serverUrl = defaultApiUrl;
  String? _token;
  User? _user;
  ApiClient? _api;
  ThemeMode _themeMode = ThemeMode.dark;
  double _uiScale = 0.9;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final savedTheme = await _authStore.loadTheme();
    final savedScale = await _authStore.loadUiScale();
    final token = await _authStore.loadToken();
    final serverUrl = normalizeServerUrl(defaultApiUrl);
    final themeMode = savedTheme == 'light' ? ThemeMode.light : ThemeMode.dark;
    final uiScale = _clampUiScale(savedScale ?? 0.9);
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      setState(() {
        _serverUrl = serverUrl;
        _themeMode = themeMode;
        _uiScale = uiScale;
        _bootstrapping = false;
      });
      _scheduleUpdateCheck();
      return;
    }

    final api = ApiClient(baseUrl: serverUrl, token: token);
    try {
      final user = await api.fetchMe();
      if (!mounted) return;
      setState(() {
        _serverUrl = serverUrl;
        _token = token;
        _user = user;
        _api = api;
        _themeMode = themeMode;
        _uiScale = uiScale;
        _bootstrapping = false;
      });
      _scheduleUpdateCheck();
    } on Object {
      await _authStore.clearToken();
      if (!mounted) return;
      setState(() {
        _serverUrl = serverUrl;
        _themeMode = themeMode;
        _uiScale = uiScale;
        _bootstrapping = false;
      });
      _scheduleUpdateCheck();
    }
  }

  void _scheduleUpdateCheck() {
    if (_updateChecked) return;
    _updateChecked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkForUpdates());
    });
  }

  Future<void> _checkForUpdates() async {
    final context = _navigatorKey.currentContext;
    if (context == null) return;
    final update = await _updater.checkForUpdate();
    if (!mounted || update == null) return;
    final dialogContext = _navigatorKey.currentContext;
    if (dialogContext == null || !dialogContext.mounted) return;
    await showBrenksUpdateDialog(
      context: dialogContext,
      updater: _updater,
      update: update,
    );
  }

  Future<void> _handleAuthenticated(LoginPayload payload) async {
    final api = ApiClient(baseUrl: payload.serverUrl, token: payload.token);
    await _authStore.saveServerUrl(payload.serverUrl);
    await _authStore.saveToken(payload.token);
    if (!mounted) return;
    setState(() {
      _serverUrl = payload.serverUrl;
      _token = payload.token;
      _user = payload.user;
      _api = api;
    });
  }

  Future<void> _logout() async {
    await _authStore.clearToken();
    if (!mounted) return;
    setState(() {
      _token = null;
      _user = null;
      _api = null;
    });
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    await _authStore.saveTheme(mode == ThemeMode.light ? 'light' : 'dark');
    if (!mounted) return;
    setState(() => _themeMode = mode);
  }

  Future<void> _setUiScale(double scale) async {
    final next = _clampUiScale(scale);
    await _authStore.saveUiScale(next);
    if (!mounted) return;
    setState(() => _uiScale = next);
  }

  double _clampUiScale(double scale) => scale.clamp(0.82, 1.0).toDouble();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'BrenksChat',
      debugShowCheckedModeBanner: false,
      theme: buildBrenksLightTheme(),
      darkTheme: buildBrenksTheme(),
      themeMode: _themeMode,
      themeAnimationDuration: const Duration(milliseconds: 220),
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear(_uiScale),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    if (_bootstrapping) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final user = _user;
    final api = _api;
    final token = _token;
    if (user == null || api == null || token == null) {
      return LoginScreen(
        initialServerUrl: _serverUrl,
        onAuthenticated: _handleAuthenticated,
      );
    }

    return MessengerScreen(
      user: user,
      api: api,
      serverUrl: _serverUrl,
      token: token,
      themeMode: _themeMode,
      onThemeModeChanged: _setThemeMode,
      uiScale: _uiScale,
      onUiScaleChanged: _setUiScale,
      onLogout: _logout,
    );
  }
}
