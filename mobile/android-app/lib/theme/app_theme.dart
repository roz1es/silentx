import 'package:flutter/material.dart';

// ─── Палитра BrenksChat: тёмный графит + умеренное золото-акцент ───────────

// Фон
const bg = Color(0xFF17191D);
const deepBg = Color(0xFF111215);
const chatBg = Color(0xFF1C1F24);
const chatBgAlt = Color(0xFF24272D);

// Панели и карточки
const panel = Color(0xFF22252A);
const panelSoft = Color(0xFF2D3037);
const panelStrong = Color(0xFF464950); // = «сильная» граница
const hoverBg = Color(0xFF303238);

// Текст
const text = Color(0xFFF6F4EF);
const muted = Color(0xFFB9B5AC);
const hint = Color(0xFF858A92);

// Границы (по умолчанию — мягкая белая, фокус — золотая)
const border = Color(0x1FFFFFFF); // white ~12%
const goldBorder = Color(0x4DD8B76C); // gold ~30% (focus/важное)

// Золото — только тонкий акцент
const accent = Color(0xFFD8B76C);
const softGold = Color(0xFFE0C783);
const goldDark = Color(0xFF5D4A28);

const danger = Color(0xFFFF7474);

// Светлая тема (вторична; золото-акцент сохраняется)
const lightBg = Color(0xFFF3F1EC);
const lightPanel = Color(0xFFFFFFFF);
const lightText = Color(0xFF1B1A17);
const lightMuted = Color(0xFF6B675F);
const lightAccent = Color(0xFFB5933F);

ThemeData buildBrenksTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: bg,
    colorScheme: const ColorScheme.dark(
      primary: accent,
      secondary: softGold,
      surface: panel,
      error: danger,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: text,
      displayColor: text,
      fontFamily: 'Roboto',
    ),
    // Иконки по умолчанию — нейтральные светлые (золото точечно в коде).
    iconTheme: const IconThemeData(color: text),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: text),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1A1C20),
      foregroundColor: text,
      iconTheme: IconThemeData(color: text),
      actionsIconTheme: IconThemeData(color: text),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: _inputDecorationTheme(
      fill: const Color(0x75121418), // rgba(18,20,24,0.46)
      hint: hint,
      label: muted,
      enabled: border,
      focused: accent,
    ),
    snackBarTheme: _snackBarTheme(
      background: panelSoft,
      textColor: text,
      action: accent,
    ),
  );
}

ThemeData buildBrenksLightTheme() {
  final base = ThemeData.light(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: lightBg,
    colorScheme: const ColorScheme.light(
      primary: lightAccent,
      secondary: Color(0xFF8A6E22),
      surface: lightPanel,
      error: Color(0xFFD84B4B),
    ),
    textTheme: base.textTheme.apply(
      bodyColor: lightText,
      displayColor: lightText,
      fontFamily: 'Roboto',
    ),
    iconTheme: const IconThemeData(color: lightText),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: lightText),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: lightPanel,
      foregroundColor: lightText,
      iconTheme: IconThemeData(color: lightText),
      actionsIconTheme: IconThemeData(color: lightText),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: _inputDecorationTheme(
      fill: const Color(0xFFFFFFFF),
      hint: const Color(0xFF8A857B),
      label: lightMuted,
      enabled: const Color(0xFFE0DCD2),
      focused: lightAccent,
    ),
    snackBarTheme: _snackBarTheme(
      background: const Color(0xFF26241F),
      textColor: Colors.white,
      action: softGold,
    ),
  );
}

SnackBarThemeData _snackBarTheme({
  required Color background,
  required Color textColor,
  required Color action,
}) {
  return SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    backgroundColor: background,
    contentTextStyle: TextStyle(color: textColor, fontWeight: FontWeight.w600),
    actionTextColor: action,
    elevation: 6,
    insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  );
}

InputDecorationTheme _inputDecorationTheme({
  required Color fill,
  required Color hint,
  required Color label,
  required Color enabled,
  required Color focused,
}) {
  return InputDecorationTheme(
    filled: true,
    fillColor: fill,
    hintStyle: TextStyle(color: hint),
    labelStyle: TextStyle(color: label),
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(color: enabled),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(color: focused, width: 1.4),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: danger),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: danger, width: 1.4),
    ),
  );
}
