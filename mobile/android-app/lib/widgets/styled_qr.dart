import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../theme/app_theme.dart';
import 'brenks_avatar.dart';

/// Стилизованный QR-код в фирменной палитре BrenksChat: золотые круглые модули
/// на графитовой карточке, аватар в центре и @юзернейм снизу.
class StyledQr extends StatelessWidget {
  const StyledQr({
    super.key,
    required this.data,
    required this.username,
    this.avatarUrl,
    this.serverUrl = '',
    this.size = 216,
  });

  final String data;
  final String username;
  final String? avatarUrl;
  final String serverUrl;
  final double size;

  // Графит карточки и «дырки» под аватаром.
  static const _cardTop = Color(0xFF26282E);
  static const _cardBottom = Color(0xFF15171B);

  // Базовый цвет модулей: на тёмной карточке — сам акцент; на светлой —
  // темнее и насыщеннее, чтобы QR оставался контрастным и сканировался.
  static Color _moduleBase(bool isLight) {
    if (!isLight) return accent;
    final hsl = HSLColor.fromColor(accent);
    return hsl
        .withLightness((hsl.lightness - 0.26).clamp(0.0, 1.0))
        .withSaturation((hsl.saturation + 0.08).clamp(0.0, 1.0))
        .toColor();
  }

  // Градиент модулей из базового цвета: светлее → база → темнее
  // (металлический отлив). Меняется вместе с темой/акцентом.
  static LinearGradient _gradientFrom(Color base) {
    final hsl = HSLColor.fromColor(base);
    final light =
        hsl.withLightness((hsl.lightness + 0.12).clamp(0.0, 1.0)).toColor();
    final dark =
        hsl.withLightness((hsl.lightness - 0.18).clamp(0.0, 1.0)).toColor();
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [light, base, dark],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final grad = _gradientFrom(_moduleBase(isLight));
    final holeColor = isLight ? const Color(0xFFEEF1F5) : _cardBottom;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isLight
                  ? const [Color(0xFFFFFFFF), Color(0xFFEEF1F5)]
                  : const [_cardTop, _cardBottom],
            ),
            border: Border.all(
                color: accent.withValues(alpha: isLight ? 0.32 : 0.2)),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Золото накладываем на сами модули (срез по непрозрачным).
              ShaderMask(
                shaderCallback: (rect) => grad.createShader(rect),
                blendMode: BlendMode.srcIn,
                child: QrImageView(
                  data: data,
                  version: QrVersions.auto,
                  size: size,
                  backgroundColor: Colors.transparent,
                  // Высокая коррекция ошибок — чтобы аватар по центру не мешал.
                  errorCorrectionLevel: QrErrorCorrectLevel.H,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.circle,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.circle,
                    color: Colors.black,
                  ),
                ),
              ),
              // Аватар поверх центра (вне ShaderMask — сохраняет свои цвета).
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: holeColor,
                  shape: BoxShape.circle,
                ),
                child: BrenksAvatar(
                  title: username,
                  imageUrl: avatarUrl,
                  baseUrl: serverUrl,
                  size: size * 0.2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ShaderMask(
          shaderCallback: (rect) => grad.createShader(rect),
          blendMode: BlendMode.srcIn,
          child: Text(
            '@$username',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}
