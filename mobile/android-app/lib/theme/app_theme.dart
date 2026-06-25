import 'package:flutter/material.dart';

// Палитра BrenksChat (совпадает с веб-версией и desktop-клиентом).
const bg = Color(0xFF20242B);
const panel = Color(0xFF272C35);
const panelSoft = Color(0xFF303744);
const panelStrong = Color(0xFF3A4352);
const text = Color(0xFFF4F7FB);
const muted = Color(0xFFABB5C4);
const border = Color(0xFF465061);
const accent = Color(0xFF5CC8F5);
const danger = Color(0xFFFF7474);

// Цвета светлой темы.
const lightBg = Color(0xFFF3F5F8);
const lightPanel = Color(0xFFFFFFFF);
const lightText = Color(0xFF17202B);
const lightMuted = Color(0xFF637083);
const lightAccent = Color(0xFF596575);

ThemeData buildBrenksTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: bg,
    colorScheme: const ColorScheme.dark(
      primary: accent,
      secondary: Color(0xFF8ED9B8),
      surface: panel,
      error: danger,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: text,
      displayColor: text,
      fontFamily: 'Roboto',
    ),
    iconTheme: const IconThemeData(color: accent),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: accent),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF202329),
      foregroundColor: text,
      iconTheme: IconThemeData(color: accent),
      actionsIconTheme: IconThemeData(color: accent),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: _inputDecorationTheme(
      fill: const Color(0xFF1D2027),
      hint: const Color(0xFF7F8CA0),
      label: muted,
      enabled: const Color(0xFF3A4250),
      focused: accent,
    ),
    snackBarTheme: _snackBarTheme(
      background: const Color(0xFF3A4352),
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
      secondary: Color(0xFF4AAE8A),
      surface: lightPanel,
      error: Color(0xFFD84B4B),
    ),
    textTheme: base.textTheme.apply(
      bodyColor: lightText,
      displayColor: lightText,
      fontFamily: 'Roboto',
    ),
    iconTheme: const IconThemeData(color: accent),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: accent),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: lightPanel,
      foregroundColor: lightText,
      iconTheme: IconThemeData(color: accent),
      actionsIconTheme: IconThemeData(color: accent),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: _inputDecorationTheme(
      fill: const Color(0xFFFFFFFF),
      hint: const Color(0xFF7C8797),
      label: const Color(0xFF637083),
      enabled: const Color(0xFFD4DAE3),
      focused: lightAccent,
    ),
    snackBarTheme: _snackBarTheme(
      background: const Color(0xFF222A35),
      textColor: Colors.white,
      action: const Color(0xFF7FD4FF),
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
