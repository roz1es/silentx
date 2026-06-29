import 'package:flutter/material.dart';

import '../services/app_settings.dart';

// ─── Палитра BrenksChat: тёмный графит + настраиваемый акцент ───────────────

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

// Граница по умолчанию — мягкая белая (фокус — акцентная, см. goldBorder).
const border = Color(0x1FFFFFFF); // white ~12%

const danger = Color(0xFFFF7474);

// Светлая тема (вторична; акцент сохраняется)
const lightBg = Color(0xFFF3F1EC);
const lightPanel = Color(0xFFFFFFFF);
const lightText = Color(0xFF1B1A17);
const lightMuted = Color(0xFF6B675F);

// ─── Акцент (настраиваемый). Имена сохранены ради совместимости со всем
// кодом, который импортирует `accent`/`softGold`/`goldDark`/`goldBorder`/
// `lightAccent` — теперь это геттеры из AppSettings, а не const. Все спутники
// выводятся из базового акцента, поэтому работают и с пресетами, и со «своим
// цветом». ─────────────────────────────────────────────────────────────────

/// Базовый акцентный цвет (по умолчанию золото).
Color get accent => AppSettings.instance.accentColor;

/// Светлее акцента — для вторичных бликов/градиентов.
Color get softGold => _shiftLightness(accent, 0.08);

/// Тёмная, приглушённая версия акцента — для тёмных подложек/иконок.
Color get goldDark => _shiftLightness(_desaturate(accent, 0.18), -0.38);

/// Акцент ~30% — для фокус-рамок и важных контуров.
Color get goldBorder => accent.withValues(alpha: 0.30);

/// Версия акцента для светлой темы — темнее и чуть насыщеннее, чтобы читалась
/// на белом фоне.
Color get lightAccent {
  final hsl = HSLColor.fromColor(accent);
  return hsl
      .withLightness((hsl.lightness - 0.16).clamp(0.0, 1.0))
      .withSaturation((hsl.saturation + 0.06).clamp(0.0, 1.0))
      .toColor();
}

/// Пресеты акцента для экрана настроек (id, подпись, цвет).
class AccentPreset {
  const AccentPreset(this.id, this.label, this.color);
  final String id;
  final String label;
  final Color color;
}

const kAccentPresets = <AccentPreset>[
  AccentPreset('gold', 'Золото', Color(0xFFD8B76C)),
  AccentPreset('ruby', 'Рубин', Color(0xFFCB5F6E)),
  AccentPreset('graphite', 'Графит', Color(0xFF9BA7B3)),
  AccentPreset('diamond', 'Алмаз', Color(0xFF7EC6DD)),
];

Color _shiftLightness(Color c, double delta) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withLightness((hsl.lightness + delta).clamp(0.0, 1.0)).toColor();
}

Color _desaturate(Color c, double amount) {
  final hsl = HSLColor.fromColor(c);
  return hsl
      .withSaturation((hsl.saturation - amount).clamp(0.0, 1.0))
      .toColor();
}

ThemeData buildBrenksTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: bg,
    colorScheme: ColorScheme.dark(
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
    colorScheme: ColorScheme.light(
      primary: lightAccent,
      secondary: const Color(0xFF8A6E22),
      surface: lightPanel,
      error: const Color(0xFFD84B4B),
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
