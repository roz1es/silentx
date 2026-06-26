import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

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
              const Color(0xFFE0C783).withValues(alpha: 0.82),
              const Color(0xFF4A4030).withValues(alpha: 0.84),
              const Color(0xFF24272D).withValues(alpha: 0.9),
            ],
          ),
          border: Border.all(
            color: const Color(0xFFFFE6A8).withValues(alpha: 0.22),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.26),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: const Color(0xFFFFE6A8).withValues(alpha: 0.1),
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
