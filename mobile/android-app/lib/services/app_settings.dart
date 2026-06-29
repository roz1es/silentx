import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Глобальные визуальные настройки (размер шрифта сообщений, плотность списка,
/// акцентный цвет интерфейса). Экраны слушают этот синглтон, а корневой
/// MaterialApp обёрнут в ListenableBuilder — поэтому смена акцента применяется
/// сразу ко всему дереву.
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  /// Базовое золото — дефолтный акцент BrenksChat.
  static const Color goldAccent = Color(0xFFD8B76C);

  /// Масштаб шрифта сообщений: 0.9 (мелкий) / 1.0 (обычный) / 1.15 (крупный).
  double msgFontScale = 1.0;

  /// Компактный (плотный) список чатов.
  bool compactList = false;

  /// Акцентный цвет интерфейса (золото по умолчанию).
  Color accentColor = goldAccent;

  /// Идентификатор выбранного пресета акцента ('gold'/'ruby'/'graphite'/
  /// 'diamond') либо 'custom' для своего цвета.
  String accentId = 'gold';

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    msgFontScale = p.getDouble('msg_font_scale') ?? 1.0;
    compactList = p.getBool('compact_list') ?? false;
    accentId = p.getString('accent_id') ?? 'gold';
    final argb = p.getInt('accent_color');
    accentColor = argb != null ? Color(argb) : goldAccent;
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

  Future<void> setAccent({required String id, required Color color}) async {
    if (id == accentId && color.toARGB32() == accentColor.toARGB32()) return;
    accentId = id;
    accentColor = color;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('accent_id', id);
    await p.setInt('accent_color', color.toARGB32());
  }
}
