import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// iOS-стиль переключателя «Ночной режим» (как на скриншоте Telegram).
/// Используется и в настройках, и на экране авторизации.
class NightModeSwitch extends StatelessWidget {
  const NightModeSwitch({
    super.key,
    required this.isLight,
    required this.onChanged,
  });

  final bool isLight;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return CupertinoSwitch(
      value: !isLight,
      activeTrackColor: accent,
      onChanged: (on) => onChanged(on ? ThemeMode.dark : ThemeMode.light),
    );
  }
}
