import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'brenks_avatar.dart';

/// Стилизованный QR-код в стиле Telegram: градиентные круглые модули на белой
/// карточке, аватар в центре и @юзернейм снизу.
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

  static const _gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4F8BF0), Color(0xFF8B6FE0), Color(0xFFE070C8)],
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Градиент накладываем на сами модули (срез по непрозрачным).
              ShaderMask(
                shaderCallback: (rect) => _gradient.createShader(rect),
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
                  color: Colors.white,
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
          shaderCallback: (rect) => _gradient.createShader(rect),
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
