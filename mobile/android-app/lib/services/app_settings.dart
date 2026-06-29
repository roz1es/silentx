import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Глобальные визуальные настройки (размер шрифта сообщений, плотность списка).
/// Экраны слушают этот синглтон, чтобы изменения применялись сразу.
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  /// Масштаб шрифта сообщений: 0.9 (мелкий) / 1.0 (обычный) / 1.15 (крупный).
  double msgFontScale = 1.0;

  /// Компактный (плотный) список чатов.
  bool compactList = false;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    msgFontScale = p.getDouble('msg_font_scale') ?? 1.0;
    compactList = p.getBool('compact_list') ?? false;
  }

  Future<void> setMsgFontScale(double v) async {
    if (v == msgFontScale) return;
    msgFontScale = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setDouble('msg_font_scale', v);
  }

  Future<void> setCompactList(bool v) async {
    if (v == compactList) return;
    compactList = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool('compact_list', v);
  }
}
