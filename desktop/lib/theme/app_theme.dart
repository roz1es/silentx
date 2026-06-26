import 'package:flutter/material.dart';

const bg = Color(0xFF17191D);
const panel = Color(0xFF22252A);
const panelSoft = Color(0xFF2D3037);
const panelStrong = Color(0xFF3B3831);
const text = Color(0xFFF6F4EF);
const muted = Color(0xFFB9B5AC);
const border = Color(0xFF464950);
const accent = Color(0xFFD8B76C);
const hover = Color(0xFF303238);
const bubbleIn = Color(0xFF34373E);
const bubbleOut = Color(0xFF34312A);
const danger = Color(0xFFFF7474);

ThemeData buildBrenksTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: bg,
    colorScheme: const ColorScheme.dark(
      primary: accent,
      secondary: Color(0xFFE8D6A8),
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
      fillColor: const Color(0x66141619),
      hintStyle: const TextStyle(color: Color(0xFF858A92)),
      labelStyle: const TextStyle(color: muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.075)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide:
            BorderSide(color: accent.withValues(alpha: 0.34), width: 1.2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: const BorderSide(color: danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
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
      color: const Color(0xF0222428),
      elevation: 18,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.095)),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: Colors.white.withValues(alpha: 0.08),
      thickness: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xF0222428),
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
