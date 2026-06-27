import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../format.dart';

/// Круглый аватар с поддержкой сетевых картинок, data-url и буквы-заглушки.
/// Байты data-url декодируются один раз и кешируются — иначе при каждом
/// rebuild (typing/chat_updated) аватар мерцал.
class BrenksAvatar extends StatefulWidget {
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
  State<BrenksAvatar> createState() => _BrenksAvatarState();
}

class _BrenksAvatarState extends State<BrenksAvatar> {
  // Приглушённая палитра — не «кричит» и не бросается в глаза.
  static const _palette = [
    Color(0xFF5B7C99),
    Color(0xFF5E927A),
    Color(0xFFBE9266),
    Color(0xFFA9707F),
    Color(0xFF836F9E),
    Color(0xFFA87A66),
    Color(0xFF5E97A0),
    Color(0xFF6D77A1),
    Color(0xFF629285),
    Color(0xFF7E9468),
  ];

  Uint8List? _bytes;
  String? _resolvedUrl;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(BrenksAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.baseUrl != widget.baseUrl) {
      _prepare();
    }
  }

  void _prepare() {
    final url = widget.imageUrl?.trim();
    if (url != null && url.startsWith('data:')) {
      _bytes = bytesFromDataUrl(url);
      _resolvedUrl = null;
    } else {
      _bytes = null;
      _resolvedUrl = _resolveUrl(url, widget.baseUrl);
    }
  }

  Color _avatarColor() {
    final t = widget.title.trim();
    if (t.isEmpty) return _palette[0];
    return _palette[t.codeUnitAt(0) % _palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final first =
        widget.title.trim().isEmpty ? 'B' : widget.title.trim()[0].toUpperCase();
    final hasImage = _bytes != null ||
        (_resolvedUrl != null && _resolvedUrl!.isNotEmpty);
    final isLight = Theme.of(context).brightness == Brightness.light;
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
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1),
      ),
      child: _image(first),
    );
  }

  Widget _image(String first) {
    final size = widget.size;
    final bytes = _bytes;
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        alignment: const Alignment(0, -0.55),
        width: size,
        height: size,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => Center(child: _initial(first)),
      );
    }
    final url = _resolvedUrl;
    if (url == null || url.isEmpty) {
      return Center(child: _initial(first));
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
        fontSize: widget.size * 0.42,
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
