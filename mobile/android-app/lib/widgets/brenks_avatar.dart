import 'package:flutter/material.dart';

import '../format.dart';

/// Круглый аватар с поддержкой сетевых картинок, data-url и буквы-заглушки.
class BrenksAvatar extends StatelessWidget {
  const BrenksAvatar({
    super.key,
    required this.title,
    this.imageUrl,
    this.baseUrl,
    this.size = 48,
  });

  final String title;
  final String? imageUrl;
  final String? baseUrl;
  final double size;

  // Приглушённая палитра — не «кричит» и не бросается в глаза.
  static const _palette = [
    Color(0xFF5B7C99), // приглушённый синий
    Color(0xFF5E927A), // приглушённый зелёный
    Color(0xFFBE9266), // тёплый песочный
    Color(0xFFA9707F), // приглушённый розово-лиловый
    Color(0xFF836F9E), // приглушённый фиолетовый
    Color(0xFFA87A66), // терракота
    Color(0xFF5E97A0), // приглушённый бирюзовый
    Color(0xFF6D77A1), // приглушённый индиго
    Color(0xFF629285), // морская волна
    Color(0xFF7E9468), // оливковый
  ];

  Color _avatarColor() {
    if (title.trim().isEmpty) return _palette[0];
    final code = title.trim().codeUnitAt(0);
    return _palette[code % _palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final first = title.trim().isEmpty ? 'B' : title.trim()[0].toUpperCase();
    final url = _resolveUrl(imageUrl, baseUrl);
    final hasImage = url != null && url.isNotEmpty;
    final isLight = Theme.of(context).brightness == Brightness.light;
    // Под картинкой — нейтральный фон. Если аватар PNG с прозрачными краями,
    // цветная хеш-заливка раньше «вылезала» зелёным ободком из-под фото.
    final bgColor = hasImage
        ? (isLight ? const Color(0xFFE6EAF0) : const Color(0xFF2A2F38))
        : _avatarColor();
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bgColor,
        border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1),
      ),
      child: _image(url, first),
    );
  }

  Widget _image(String? url, String first) {
    if (url == null || url.isEmpty) {
      return Center(child: _initial(first));
    }
    // data:image/...;base64,... — Image.network не умеет, нужен Image.memory.
    if (url.startsWith('data:')) {
      final bytes = bytesFromDataUrl(url);
      if (bytes == null || bytes.isEmpty) {
        return Center(child: _initial(first));
      }
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        // Смещаем кадр к верху: у вертикальных фото cover иначе срезает макушку.
        alignment: const Alignment(0, -0.55),
        width: size,
        height: size,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => Center(child: _initial(first)),
      );
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      alignment: const Alignment(0, -0.55),
      width: size,
      height: size,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => Center(child: _initial(first)),
    );
  }

  Widget _initial(String first) {
    return Text(
      first,
      style: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w800,
        fontSize: size * 0.42,
      ),
    );
  }
}

String? _resolveUrl(String? value, String? baseUrl) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty || raw.startsWith('data:')) return raw;
  final uri = Uri.tryParse(raw);
  if (uri == null || uri.hasScheme || baseUrl == null || baseUrl.isEmpty) {
    return raw;
  }
  return Uri.parse(baseUrl).resolve(raw).toString();
}
