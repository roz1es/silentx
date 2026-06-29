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

  // Градиент модулей строится из акцентного цвета: светлее → акцент → темнее
  // (металлический отлив). Меняется вместе с темой/акцентом.
  static LinearGradient _accentGradient() {
    final hsl = HSLColor.fromColor(accent);
    final light =
        hsl.withLightness((hsl.lightness + 0.12).clamp(0.0, 1.0)).toColor();
    final dark =
        hsl.withLightness((hsl.lightness - 0.18).clamp(0.0, 1.0)).toColor();
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [light, accent, dark],
    );
  }

  @override
  Widget build(BuildContext context) {
    final grad = _accentGradient();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_cardTop, _cardBottom],
            ),
            border: Border.all(color: accent.withValues(alpha: 0.2)),
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
                decoration: const BoxDecoration(
                  color: _cardBottom,
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
