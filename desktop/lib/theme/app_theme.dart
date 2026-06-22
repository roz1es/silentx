import 'package:flutter/material.dart';

const bg = Color(0xFF20242B);
const panel = Color(0xFF272C35);
const panelSoft = Color(0xFF303744);
const panelStrong = Color(0xFF3A4352);
const text = Color(0xFFF4F7FB);
const muted = Color(0xFFABB5C4);
const border = Color(0xFF465061);
const accent = Color(0xFF5CC8F5);
const danger = Color(0xFFFF7474);

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
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF1D2027),
      hintStyle: const TextStyle(color: Color(0xFF7F8CA0)),
      labelStyle: const TextStyle(color: muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFF3A4250)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: accent, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: danger, width: 1.4),
      ),
    ),
  );
}

ThemeData buildBrenksLightTheme() {
  final base = ThemeData.light(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: const Color(0xFFF3F5F8),
    colorScheme: const ColorScheme.light(
      primary: Color(0xFF596575),
      secondary: Color(0xFF4AAE8A),
      surface: Color(0xFFFFFFFF),
      error: Color(0xFFD84B4B),
    ),
    textTheme: base.textTheme.apply(
      bodyColor: const Color(0xFF17202B),
      displayColor: const Color(0xFF17202B),
      fontFamily: 'Roboto',
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFFFFFFF),
      hintStyle: const TextStyle(color: Color(0xFF7C8797)),
      labelStyle: const TextStyle(color: Color(0xFF637083)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFFD4DAE3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFF596575), width: 1.4),
      ),
    ),
  );
}
