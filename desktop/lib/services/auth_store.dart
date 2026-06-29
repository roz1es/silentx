import 'package:shared_preferences/shared_preferences.dart';

class AuthStore {
  static const _tokenKey = 'brenkschat.token';
  static const _serverKey = 'brenkschat.server';
  static const _themeKey = 'brenkschat.theme';
  static const _accentKey = 'brenkschat.accent';
  static const _uiScaleKey = 'brenkschat.uiScale';

  Future<String?> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  Future<String?> loadServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_serverKey);
  }

  Future<void> saveServerUrl(String serverUrl) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serverKey, serverUrl);
  }

  Future<String?> loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_themeKey);
  }

  Future<void> saveTheme(String theme) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, theme);
  }

  Future<String?> loadAccent() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_accentKey);
  }

  Future<void> saveAccent(String accent) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accentKey, accent);
  }

  Future<double?> loadUiScale() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_uiScaleKey);
  }

  Future<void> saveUiScale(double scale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_uiScaleKey, scale);
  }
}
