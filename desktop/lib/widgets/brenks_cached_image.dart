import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class BrenksCachedNetworkImage extends StatefulWidget {
  const BrenksCachedNetworkImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;

  @override
  State<BrenksCachedNetworkImage> createState() =>
      _BrenksCachedNetworkImageState();
}

class _BrenksCachedNetworkImageState extends State<BrenksCachedNetworkImage>
    with AutomaticKeepAliveClientMixin {
  static const _maxImageBytes = 18 * 1024 * 1024;
  static final Map<String, Uint8List> _memory = {};
  static final Map<String, Future<Uint8List?>> _inFlight = {};

  Future<Uint8List?>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load(widget.url);
  }

  @override
  void didUpdateWidget(covariant BrenksCachedNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _future = _load(widget.url);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cached = _memory[widget.url];
    if (cached != null) return _image(cached);

    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes != null) return _image(bytes);
        if (snapshot.connectionState == ConnectionState.waiting) {
          return widget.placeholder ?? const SizedBox.shrink();
        }
        return widget.errorWidget ??
            widget.placeholder ??
            const SizedBox.shrink();
      },
    );
  }

  @override
  bool get wantKeepAlive => true;

  Widget _image(Uint8List bytes) {
    return Image.memory(
      bytes,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) =>
          widget.errorWidget ?? widget.placeholder ?? const SizedBox.shrink(),
    );
  }

  static Future<Uint8List?> _load(String url) {
    final cached = _memory[url];
    if (cached != null) return Future.value(cached);
    return _inFlight.putIfAbsent(url, () async {
      try {
        final file = await _cacheFile(url);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          if (bytes.isNotEmpty) {
            _remember(url, bytes);
            return bytes;
          }
        }

        final response =
            await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          return null;
        }
        final bytes = response.bodyBytes;
        if (bytes.isEmpty || bytes.length > _maxImageBytes) return null;
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes, flush: false);
        _remember(url, bytes);
        return bytes;
      } on Object {
        return null;
      } finally {
        _inFlight.remove(url);
      }
    });
  }

  static void _remember(String url, Uint8List bytes) {
    if (_memory.length > 180) _memory.remove(_memory.keys.first);
    _memory[url] = bytes;
  }

  static Future<io.File> _cacheFile(String url) async {
    final dir = await getApplicationCacheDirectory();
    return io.File('${dir.path}/brenkschat-images/${_stableHash(url)}.img');
  }

  static String _stableHash(String value) {
    const offset = 0xcbf29ce484222325;
    const prime = 0x100000001b3;
    var hash = offset;
    for (final byte in utf8.encode(value)) {
      hash ^= byte;
      hash = (hash * prime) & 0xffffffffffffffff;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}
