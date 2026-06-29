import 'package:flutter/material.dart';

const _darkBg = Color(0xFF17191D);
const _darkPanel = Color(0xFF22252A);
const _darkPanelSoft = Color(0xFF2D3037);
const _darkText = Color(0xFFF6F4EF);
const _darkMuted = Color(0xFFB9B5AC);
const _darkBorder = Color(0xFF464950);
const _darkHover = Color(0xFF303238);
const _darkBubbleIn = Color(0xFF34373E);

const _lightBg = Color(0xFFF4F6FA);
const _lightPanel = Color(0xFFFFFFFF);
const _lightPanelSoft = Color(0xFFE9EEF5);
const _lightText = Color(0xFF17202B);
const _lightMuted = Color(0xFF637083);
const _lightBorder = Color(0xFFD5DCE8);
const _lightHover = Color(0xFFE4E9F1);
const _lightBubbleIn = Color(0xFFFFFFFF);
const danger = Color(0xFFFF7474);

enum BrenksAccentPreset {
  gold(
    id: 'gold',
    label: 'Золото',
    accent: Color(0xFFD8B76C),
    secondary: Color(0xFFE8D6A8),
    panelStrong: Color(0xFF3B3831),
    bubbleOut: Color(0xFF34312A),
  ),
  ruby(
    id: 'ruby',
    label: 'Рубин',
    accent: Color(0xFFE2687C),
    secondary: Color(0xFFF0A2AF),
    panelStrong: Color(0xFF3B3037),
    bubbleOut: Color(0xFF382D33),
  ),
  graphite(
    id: 'graphite',
    label: 'Графит',
    accent: Color(0xFFB8C0CC),
    secondary: Color(0xFFE1E6ED),
    panelStrong: Color(0xFF34383F),
    bubbleOut: Color(0xFF30343A),
  ),
  diamond(
    id: 'diamond',
    label: 'Алмаз',
    accent: Color(0xFF8BE9FD),
    secondary: Color(0xFFD7FAFF),
    panelStrong: Color(0xFF2C3940),
    bubbleOut: Color(0xFF27343A),
  ),
  custom(
    id: 'custom',
    label: 'Свой',
    accent: Color(0xFF9D8CFF),
    secondary: Color(0xFFE1DCFF),
    panelStrong: Color(0xFF33303E),
    bubbleOut: Color(0xFF302D3B),
  );

  const BrenksAccentPreset({
    required this.id,
    required this.label,
    required this.accent,
    required this.secondary,
    required this.panelStrong,
    required this.bubbleOut,
  });

  final String id;
  final String label;
  final Color accent;
  final Color secondary;
  final Color panelStrong;
  final Color bubbleOut;
}

BrenksAccentPreset accentPresetFromId(String? id) {
  final value = id?.trim();
  if (value != null && value.startsWith('custom:')) {
    final parsed = colorFromHex(value.substring('custom:'.length));
    if (parsed != null) _customAccentColor = parsed;
    return BrenksAccentPreset.custom;
  }
  for (final preset in BrenksAccentPreset.values) {
    if (preset.id == value) return preset;
  }
  return BrenksAccentPreset.gold;
}

BrenksAccentPreset activeAccentPreset = BrenksAccentPreset.gold;
BrenksAccentPreset activeThemeAccentPreset = BrenksAccentPreset.gold;
Color? _customAccentColor;
bool _lightPaletteActive = false;
Color bg = _darkBg;
Color panel = _darkPanel;
Color panelSoft = _darkPanelSoft;
Color text = _darkText;
Color muted = _darkMuted;
Color border = _darkBorder;
Color hover = _darkHover;
Color bubbleIn = _darkBubbleIn;
Color accent = BrenksAccentPreset.gold.accent;
Color accentSecondary = BrenksAccentPreset.gold.secondary;
Color panelStrong = BrenksAccentPreset.gold.panelStrong;
Color bubbleOut = BrenksAccentPreset.gold.bubbleOut;

void setBrenksAccentPreset(BrenksAccentPreset preset) {
  activeAccentPreset = preset;
  activeThemeAccentPreset = preset;
  _applyBrenksPalette();
}

void setBrenksCustomAccent(Color color) {
  _customAccentColor = color;
  setBrenksAccentPreset(BrenksAccentPreset.custom);
}

String accentStorageId(BrenksAccentPreset preset) {
  if (preset != BrenksAccentPreset.custom) return preset.id;
  return 'custom:${colorToHex(_effectiveAccent(preset))}';
}

String colorToHex(Color color) {
  final value = color.toARGB32().toRadixString(16).padLeft(8, '0');
  return '#${value.substring(2).toUpperCase()}';
}

Color? colorFromHex(String raw) {
  final normalized = raw.trim().replaceFirst('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(normalized)) return null;
  return Color(int.parse('FF$normalized', radix: 16));
}

void setBrenksThemeMode(ThemeMode mode) {
  _lightPaletteActive = mode == ThemeMode.light;
  _applyBrenksPalette();
}

void _applyBrenksPalette() {
  final preset = activeAccentPreset;
  final presetAccent = _effectiveAccent(preset);
  final presetSecondary = _effectiveSecondary(preset);
  bg = _lightPaletteActive ? _lightBg : _darkBg;
  panel = _lightPaletteActive ? _lightPanel : _darkPanel;
  panelSoft = _lightPaletteActive ? _lightPanelSoft : _darkPanelSoft;
  text = _lightPaletteActive ? _lightText : _darkText;
  muted = _lightPaletteActive ? _lightMuted : _darkMuted;
  border = _lightPaletteActive ? _lightBorder : _darkBorder;
  hover = _lightPaletteActive ? _lightHover : _darkHover;
  bubbleIn = _lightPaletteActive ? _lightBubbleIn : _darkBubbleIn;
  accent = presetAccent;
  accentSecondary = presetSecondary;
  panelStrong = _lightPaletteActive
      ? Color.alphaBlend(presetAccent.withValues(alpha: 0.12), _lightPanelSoft)
      : _effectivePanelStrong(preset);
  bubbleOut = _lightPaletteActive
      ? Color.alphaBlend(presetAccent.withValues(alpha: 0.14), _lightPanel)
      : _effectiveBubbleOut(preset);
}

Color _effectiveAccent(BrenksAccentPreset preset) {
  return preset == BrenksAccentPreset.custom
      ? _customAccentColor ?? preset.accent
      : preset.accent;
}

Color _effectiveSecondary(BrenksAccentPreset preset) {
  if (preset != BrenksAccentPreset.custom) return preset.secondary;
  return _withLightness(_effectiveAccent(preset), 0.82);
}

Color _effectivePanelStrong(BrenksAccentPreset preset) {
  if (preset != BrenksAccentPreset.custom) return preset.panelStrong;
  return Color.alphaBlend(
    _effectiveAccent(preset).withValues(alpha: 0.16),
    _darkPanel,
  );
}

Color _effectiveBubbleOut(BrenksAccentPreset preset) {
  if (preset != BrenksAccentPreset.custom) return preset.bubbleOut;
  return Color.alphaBlend(
    _effectiveAccent(preset).withValues(alpha: 0.13),
    const Color(0xFF2B2D33),
  );
}

Color _withLightness(Color color, double lightness) {
  return HSLColor.fromColor(color)
      .withLightness(lightness.clamp(0.0, 1.0))
      .toColor();
}

ThemeData buildBrenksTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: bg,
    colorScheme: ColorScheme.dark(
      primary: accent,
      secondary: accentSecondary,
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
      labelStyle: TextStyle(color: muted),
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
        borderSide: BorderSide(color: danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: BorderSide(color: danger, width: 1.4),
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
      contentTextStyle: TextStyle(color: text),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
  );
}

ThemeData buildBrenksLightTheme() {
  final base = ThemeData.light(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: bg,
    colorScheme: ColorScheme.light(
      primary: accent,
      secondary: accentSecondary,
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
      fillColor: panel,
      hintStyle: const TextStyle(color: Color(0xFF7C8797)),
      labelStyle: TextStyle(color: muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: accent, width: 1.4),
      ),
    ),
  );
}
