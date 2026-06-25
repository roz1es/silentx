import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Одно действие в iOS-меню (иконка + подпись + обработчик).
class IosMenuAction {
  const IosMenuAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
    this.dividerBefore = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  /// Тонкая линия-разделитель над пунктом (для отделения деструктивных действий).
  final bool dividerBefore;
}

/// Всплывающее iOS-меню: размытый фон + «приподнятый» превью + карточка действий.
/// Превью и пункты строит вызывающая сторона — виджет универсальный.
Future<void> showIosContextMenu({
  required BuildContext context,
  required Offset pos,
  required Widget preview,
  required List<IosMenuAction> actions,
  double menuWidth = 280,
}) {
  final isLight = Theme.of(context).brightness == Brightness.light;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'menu',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (ctx, _, __) => _IosContextMenuView(
      pos: pos,
      isLight: isLight,
      preview: preview,
      actions: actions,
      menuWidth: menuWidth,
    ),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(opacity: curved, child: child);
    },
  );
}

class _IosContextMenuView extends StatelessWidget {
  const _IosContextMenuView({
    required this.pos,
    required this.isLight,
    required this.preview,
    required this.actions,
    required this.menuWidth,
  });

  final Offset pos;
  final bool isLight;
  final Widget preview;
  final List<IosMenuAction> actions;
  final double menuWidth;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final scrim = isLight
        ? Colors.black.withValues(alpha: 0.18)
        : Colors.black.withValues(alpha: 0.34);
    // Привязываем «остров» к точке нажатия, оставляя запас у краёв.
    final alignY = ((pos.dy / size.height) * 2 - 1).clamp(-0.7, 0.7);

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Размытие + лёгкое затемнение списка чатов.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(color: scrim),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).pop(),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 16),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                          minHeight: constraints.maxHeight - 32),
                      child: Align(
                        alignment: Alignment(0, alignY),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Превью «всплывает» над размытием.
                            GestureDetector(onTap: () {}, child: preview),
                            const SizedBox(height: 12),
                            GestureDetector(
                              onTap: () {},
                              child: _menuCard(context),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuCard(BuildContext context) {
    final cardBg = isLight ? Colors.white : panel;
    final actionColor = isLight ? lightText : text;
    return Container(
      width: menuWidth,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 26,
              offset: const Offset(0, 10)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final a in actions) ...[
            if (a.dividerBefore) Container(height: 1, color: border),
            _item(context, a, a.danger ? danger : actionColor),
          ],
        ],
      ),
    );
  }

  Widget _item(BuildContext context, IosMenuAction a, Color color) {
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        a.onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(a.icon, color: color, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                a.label,
                style: TextStyle(
                    color: color,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
