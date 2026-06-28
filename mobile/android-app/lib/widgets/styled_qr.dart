import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

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

  // Золотой градиент модулей.
  static const _gold = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFEAD392), Color(0xFFD8B76C), Color(0xFF9C7C3C)],
  );

  // Графит карточки и «дырки» под аватаром.
  static const _cardTop = Color(0xFF26282E);
  static const _cardBottom = Color(0xFF15171B);

  @override
  Widget build(BuildContext context) {
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
            border: Border.all(color: const Color(0x33D8B76C)),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Золото накладываем на сами модули (срез по непрозрачным).
              ShaderMask(
                shaderCallback: (rect) => _gold.createShader(rect),
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
          shaderCallback: (rect) => _gold.createShader(rect),
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
