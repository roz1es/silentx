import 'package:flutter/material.dart';

const bg = Color(0xFF23272F);
const panel = Color(0xFF2D323C);
const panelSoft = Color(0xFF39404C);
const panelStrong = Color(0xFF48505E);
const text = Color(0xFFF1F5F9);
const muted = Color(0xFFB2BBC8);
const border = Color(0xFF4B525E);
const accent = Color(0xFF7DD3FC);
const hover = Color(0xFF39404C);
const bubbleIn = Color(0xFF48505E);
const bubbleOut = Color(0xFF435260);
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
      fillColor: const Color(0x8018181B),
      hintStyle: const TextStyle(color: Color(0xFF71717A)),
      labelStyle: const TextStyle(color: muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide:
            BorderSide(color: accent.withValues(alpha: 0.18), width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: danger, width: 1.4),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: muted,
        shape: const CircleBorder(),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: const Color(0xF227272A),
      elevation: 18,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: Colors.white.withValues(alpha: 0.08),
      thickness: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xF227272A),
      contentTextStyle: const TextStyle(color: text),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
