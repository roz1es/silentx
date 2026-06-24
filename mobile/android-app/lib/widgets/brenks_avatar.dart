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

  static const _palette = [
    Color(0xFF5CC8F5),
    Color(0xFF4CAF50),
    Color(0xFFFF9800),
    Color(0xFFE91E63),
    Color(0xFF9C27B0),
    Color(0xFFFF5722),
    Color(0xFF00BCD4),
    Color(0xFF3F51B5),
    Color(0xFF009688),
    Color(0xFF8BC34A),
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
    final color = _avatarColor();
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
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
        width: size,
        height: size,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => Center(child: _initial(first)),
      );
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
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
