import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Модальная палитра выбора «своего» акцентного цвета.
///
/// Без HEX-поля — только визуальный выбор: цветовое поле (насыщенность ×
/// яркость), слайдер оттенка и быстрые цветные кружки. Возвращает выбранный
/// [Color] через Navigator.pop, либо null при отмене.
Future<Color?> showAccentColorPicker(BuildContext context, Color initial) {
  return showDialog<Color>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => _AccentPickerDialog(initial: initial),
  );
}

/// Быстрые цвета — гармоничная палитра в духе BrenksChat.
const _quickColors = <Color>[
  Color(0xFFD8B76C), // золото
  Color(0xFFE0A15E), // янтарь
  Color(0xFFCB5F6E), // рубин
  Color(0xFFB98CD6), // аметист
  Color(0xFF7EC6DD), // алмаз
  Color(0xFF6E8BD6), // сапфир
  Color(0xFF6FC79B), // изумруд
  Color(0xFF9BA7B3), // графит
];

class _AccentPickerDialog extends StatefulWidget {
  const _AccentPickerDialog({required this.initial});

  final Color initial;

  @override
  State<_AccentPickerDialog> createState() => _AccentPickerDialogState();
}

class _AccentPickerDialogState extends State<_AccentPickerDialog> {
  late HSVColor _hsv;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial);
    // У почти-серых цветов оттенок не определён — даём осмысленный старт.
    if (_hsv.saturation < 0.02) {
      _hsv = _hsv.withSaturation(0.6).withValue(0.85);
    }
  }

  Color get _color => _hsv.toColor();

  void _setHue(double hue) => setState(() => _hsv = _hsv.withHue(hue));

  void _setSV(double sat, double val) =>
      setState(() => _hsv = _hsv.withSaturation(sat).withValue(val));

  void _pickQuick(Color c) => setState(() => _hsv = HSVColor.fromColor(c));

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final panelColor = isLight
        ? Colors.white.withValues(alpha: 0.92)
        : const Color(0xFF1E2126).withValues(alpha: 0.94);
    final txt = isLight ? lightText : text;
    final sub = isLight ? lightMuted : muted;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
          child: Container(
            decoration: BoxDecoration(
              color: panelColor,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: Colors.white.withValues(alpha: isLight ? 0.6 : 0.14),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isLight ? 0.12 : 0.4),
                  blurRadius: 34,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Свой цвет',
                        style: TextStyle(
                          color: txt,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    _swatch(_color),
                  ],
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, c) => _SVField(
                    width: c.maxWidth,
                    height: 168,
                    hsv: _hsv,
                    onChanged: _setSV,
                  ),
                ),
                const SizedBox(height: 16),
                _HueSlider(hue: _hsv.hue, onChanged: _setHue),
                const SizedBox(height: 18),
                Text(
                  'Быстрый выбор',
                  style: TextStyle(
                    color: sub,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final c in _quickColors)
                      _QuickDot(
                        color: c,
                        selected: _sameColor(c, _color),
                        onTap: () => _pickQuick(c),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color:
                                  Colors.white.withValues(alpha: isLight ? 0.5 : 0.16),
                            ),
                          ),
                          foregroundColor: sub,
                        ),
                        child: const Text('Отмена',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(_color),
                        style: FilledButton.styleFrom(
                          backgroundColor: _color,
                          foregroundColor: const Color(0xFF08131A),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text('Применить',
                            style: TextStyle(fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _swatch(Color c) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: c,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 2),
        boxShadow: [
          BoxShadow(
            color: c.withValues(alpha: 0.5),
            blurRadius: 12,
          ),
        ],
      ),
    );
  }
}

bool _sameColor(Color a, Color b) => a.toARGB32() == b.toARGB32();

/// Цветовое поле: по X — насыщенность, по Y — яркость (при текущем оттенке).
class _SVField extends StatelessWidget {
  const _SVField({
    required this.width,
    required this.height,
    required this.hsv,
    required this.onChanged,
  });

  final double width;
  final double height;
  final HSVColor hsv;
  final void Function(double sat, double val) onChanged;

  void _handle(Offset local) {
    final sat = (local.dx / width).clamp(0.0, 1.0).toDouble();
    final val = (1 - local.dy / height).clamp(0.0, 1.0).toDouble();
    onChanged(sat, val);
  }

  @override
  Widget build(BuildContext context) {
    final hueColor = HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor();
    final markerLeft = (hsv.saturation * width).clamp(0.0, width);
    final markerTop = ((1 - hsv.value) * height).clamp(0.0, height);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanDown: (d) => _handle(d.localPosition),
      onPanUpdate: (d) => _handle(d.localPosition),
      child: SizedBox(
        width: width,
        height: height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              // Слой 1: белый → чистый оттенок (насыщенность слева направо).
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.white, hueColor],
                    ),
                  ),
                ),
              ),
              // Слой 2: прозрачный → чёрный (яркость сверху вниз).
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: markerLeft - 11,
                top: markerTop - 11,
                child: _Marker(color: hsv.toColor()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Горизонтальный слайдер оттенка (радуга).
class _HueSlider extends StatelessWidget {
  const _HueSlider({required this.hue, required this.onChanged});

  final double hue;
  final ValueChanged<double> onChanged;

  static const _spectrum = [
    Color(0xFFFF0000),
    Color(0xFFFFFF00),
    Color(0xFF00FF00),
    Color(0xFF00FFFF),
    Color(0xFF0000FF),
    Color(0xFFFF00FF),
    Color(0xFFFF0000),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        void handle(Offset local) {
          final h = (local.dx / w * 360).clamp(0.0, 359.999).toDouble();
          onChanged(h);
        }

        final markerLeft = (hue / 360 * w).clamp(0.0, w);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (d) => handle(d.localPosition),
          onPanUpdate: (d) => handle(d.localPosition),
          child: SizedBox(
            height: 26,
            width: w,
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(13),
                      gradient: const LinearGradient(colors: _spectrum),
                    ),
                  ),
                ),
                Positioned(
                  left: markerLeft - 13,
                  top: 0,
                  child: _Marker(
                    color: HSVColor.fromAHSV(1, hue, 1, 1).toColor(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Перетаскиваемый маркер — белое кольцо с цветной серединой.
class _Marker extends StatelessWidget {
  const _Marker({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 6,
          ),
        ],
      ),
    );
  }
}

/// Быстрый цветной кружок.
class _QuickDot extends StatelessWidget {
  const _QuickDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? Colors.white
                : Colors.white.withValues(alpha: 0.18),
            width: selected ? 3 : 1,
          ),
          boxShadow: selected
              ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 10)]
              : null,
        ),
        child: selected
            ? const Icon(Icons.check_rounded,
                size: 18, color: Color(0xFF08131A))
            : null,
      ),
    );
  }
}
