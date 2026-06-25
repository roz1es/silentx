import 'dart:ui';

import 'package:flutter/material.dart';

/// Аккуратный всплывающий тост с иконкой (стиль берётся из SnackBarTheme).
void showAppToast(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(milliseconds: 1800),
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            error ? Icons.error_outline_rounded : Icons.check_circle_rounded,
            color: error ? const Color(0xFFFF7474) : const Color(0xFF5AD1A0),
            size: 20,
          ),
          const SizedBox(width: 10),
          Flexible(child: Text(message)),
        ],
      ),
    ),
  );
}

/// Палитра фона мессенджера — чистая, как в веб-версии (без ярких оттенков).
const _lightGradient = [
  Color(0xFFF2F5F9),
  Color(0xFFE8EDF4),
];
const _darkGradient = [
  Color(0xFF20242B),
  Color(0xFF14171D),
];

/// Фон-градиент в стиле экрана авторизации. Кладётся под весь экран.
class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isLight ? _lightGradient : _darkGradient,
        ),
      ),
      child: child,
    );
  }
}

/// Матовая стеклянная панель: размытие + полупрозрачный градиент + светлая рамка.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.borderRadius = 24,
    this.blur = 22,
    this.padding,
    this.margin,
    this.strength = 1,
    this.border = true,
    this.shadow = false,
  });

  final Widget child;
  final double borderRadius;
  final double blur;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  /// Множитель непрозрачности (1 = базовый, <1 — прозрачнее).
  final double strength;
  final bool border;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final radius = BorderRadius.circular(borderRadius);
    Widget panel = ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isLight
                  ? [
                      Colors.white.withValues(alpha: 0.78 * strength),
                      Colors.white.withValues(alpha: 0.52 * strength),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.12 * strength),
                      Colors.white.withValues(alpha: 0.05 * strength),
                    ],
            ),
            border: border
                ? Border.all(
                    color: Colors.white.withValues(alpha: isLight ? 0.7 : 0.16),
                    width: 1.2,
                  )
                : null,
          ),
          child: child,
        ),
      ),
    );

    if (shadow) {
      panel = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isLight ? 0.08 : 0.35),
              blurRadius: 30,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: panel,
      );
    }

    if (margin != null) {
      panel = Padding(padding: margin!, child: panel);
    }
    return panel;
  }
}

/// Матовая полоса для AppBar/нижних панелей (без скруглений, с волосяной рамкой).
class GlassBar extends StatelessWidget {
  const GlassBar({
    super.key,
    this.blur = 22,
    this.bottomBorder = false,
    this.topBorder = false,
    this.child,
  });

  final double blur;
  final bool bottomBorder;
  final bool topBorder;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final line = Colors.white.withValues(alpha: isLight ? 0.6 : 0.12);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: isLight ? 0.46 : 0.06),
            border: Border(
              bottom: bottomBorder ? BorderSide(color: line) : BorderSide.none,
              top: topBorder ? BorderSide(color: line) : BorderSide.none,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Лёгкая стеклянная «карточка» без размытия (дёшево для списков).
/// Полупрозрачная заливка поверх градиента — сохраняет ощущение слоистости.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius = 20,
    this.padding,
    this.selected = false,
  });

  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final baseAlpha = isLight ? 0.55 : 0.07;
    final selAlpha = isLight ? 0.85 : 0.16;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        color: Colors.white.withValues(alpha: selected ? selAlpha : baseAlpha),
        border: Border.all(
          color: Colors.white.withValues(alpha: isLight ? 0.6 : 0.12),
          width: 1,
        ),
      ),
      child: child,
    );
  }
}
