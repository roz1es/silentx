import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class BrenksAvatar extends StatelessWidget {
  const BrenksAvatar({
    super.key,
    required this.title,
    this.imageUrl,
    this.size = 48,
  });

  final String title;
  final String? imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final first = title.trim().isEmpty ? 'B' : title.trim()[0].toUpperCase();
    final url = imageUrl;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accent.withValues(alpha: 0.9),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
