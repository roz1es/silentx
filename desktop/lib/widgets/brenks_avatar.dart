import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'brenks_cached_image.dart';

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

  static final Map<String, Uint8List> _dataUrlMemory = {};

  @override
  Widget build(BuildContext context) {
    final first = title.trim().isEmpty ? 'B' : title.trim()[0].toUpperCase();
    final url = _resolveUrl(imageUrl, baseUrl);
    final bytes = _bytesFromDataUrl(url);
    return RepaintBoundary(
      child: Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accentSecondary.withValues(alpha: 0.86),
              accent.withValues(alpha: 0.42),
              panelStrong.withValues(alpha: 0.95),
            ],
          ),
          border: Border.all(
            color: accentSecondary.withValues(alpha: 0.24),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.26),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: accentSecondary.withValues(alpha: 0.12),
              blurRadius: 0,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: bytes != null
            ? Image.memory(
                bytes,
                key: ValueKey(url),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => _AvatarFallback(
                  first: first,
                  size: size,
                ),
              )
            : url == null || url.isEmpty
                ? _AvatarFallback(first: first, size: size)
                : BrenksCachedNetworkImage(
                    key: ValueKey(url),
                    url: url,
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                    placeholder: _AvatarFallback(first: first, size: size),
                    errorWidget: _AvatarFallback(first: first, size: size),
                  ),
      ),
    );
  }

  static Uint8List? _bytesFromDataUrl(String? value) {
    final raw = value?.trim();
    if (raw == null || !raw.startsWith('data:')) return null;
    final cached = _dataUrlMemory[raw];
    if (cached != null) return cached;
    final marker = 'base64,';
    final index = raw.indexOf(marker);
    if (index == -1) return null;
    try {
      final bytes = base64Decode(raw.substring(index + marker.length));
      if (_dataUrlMemory.length > 120) {
        _dataUrlMemory.remove(_dataUrlMemory.keys.first);
      }
      _dataUrlMemory[raw] = bytes;
      return bytes;
    } on Object {
      return null;
    }
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({
    required this.first,
    required this.size,
  });

  final String first;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        first,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.42,
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
