import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

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

  @override
  Widget build(BuildContext context) {
    final first = title.trim().isEmpty ? 'B' : title.trim()[0].toUpperCase();
    final url = _resolveUrl(imageUrl, baseUrl);
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accent.withValues(alpha: 0.9),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: url == null || url.isEmpty
          ? Center(
              child: Text(
                first,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: size * 0.42,
                ),
              ),
            )
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Center(
                child: Text(
                  first,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: size * 0.42,
                  ),
                ),
              ),
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
