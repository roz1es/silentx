import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../format.dart';
import '../models.dart';
import '../theme/app_theme.dart';

/// Отрисовка вложения сообщения: фото, голосовое, видеокружок или файл.
class MediaPreview extends StatelessWidget {
  const MediaPreview({
    super.key,
    required this.media,
    required this.serverUrl,
    required this.onPlayVoice,
  });

  final MessageMedia media;
  final String serverUrl;
  final ValueChanged<MessageMedia> onPlayVoice;

  @override
  Widget build(BuildContext context) {
    switch (media.kind) {
      case 'image':
        return ImagePreview(source: media.dataUrl, serverUrl: serverUrl);
      case 'voice':
        return VoicePreview(media: media, onPlay: () => onPlayVoice(media));
      case 'video_note':
        return _VideoNotePreview(media: media);
      default:
        return _FilePreview(media: media);
    }
  }
}

class _FilePreview extends StatelessWidget {
  const _FilePreview({required this.media});

  final MessageMedia media;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF242A33),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.insert_drive_file_rounded, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              media.fileName ?? 'Файл',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, color: text),
            ),
          ),
        ],
      ),
    );
  }
}

class VoicePreview extends StatelessWidget {
  const VoicePreview({super.key, required this.media, required this.onPlay});

  final MessageMedia media;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF242A33),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          IconButton.filled(
            tooltip: 'Воспроизвести',
            onPressed: onPlay,
            icon: const Icon(Icons.play_arrow_rounded),
            style: IconButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: const Color(0xFF08131A),
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Голосовое',
                  style: TextStyle(fontWeight: FontWeight.w800, color: text),
                ),
                SizedBox(height: 6),
                _VoiceWave(),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatDuration(media.durationMs ?? 0),
            style: const TextStyle(color: muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _VoiceWave extends StatelessWidget {
  const _VoiceWave();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        minHeight: 5,
        value: 0.44,
        backgroundColor: Colors.white.withValues(alpha: 0.08),
        valueColor: AlwaysStoppedAnimation<Color>(accent.withValues(alpha: 0.9)),
      ),
    );
  }
}

class _VideoNotePreview extends StatefulWidget {
  const _VideoNotePreview({required this.media});

  final MessageMedia media;

  @override
  State<_VideoNotePreview> createState() => _VideoNotePreviewState();
}

class _VideoNotePreviewState extends State<_VideoNotePreview> {
  VideoPlayerController? _ctrl;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    final bytes = bytesFromDataUrl(widget.media.dataUrl);
    if (bytes == null || bytes.isEmpty) return;
    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/vnote_${widget.media.dataUrl.hashCode.abs()}.mp4';
      await io.File(path).writeAsBytes(bytes);
      final ctrl = VideoPlayerController.file(io.File(path));
      await ctrl.initialize();
      ctrl.addListener(() {
        if (mounted) setState(() => _playing = ctrl.value.isPlaying);
      });
      if (mounted) setState(() => _ctrl = ctrl);
    } on Object {
      // Failed to init player — fallback to placeholder
    }
  }

  Future<void> _togglePlay() async {
    final ctrl = _ctrl;
    if (ctrl == null) return;
    if (ctrl.value.isPlaying) {
      await ctrl.pause();
    } else {
      if (ctrl.value.position >= ctrl.value.duration) {
        await ctrl.seekTo(Duration.zero);
      }
      await ctrl.play();
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final ctrl = _ctrl;
    final ready = ctrl != null && ctrl.value.isInitialized;

    return GestureDetector(
      onTap: _togglePlay,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 148,
            height: 148,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isLight ? const Color(0xFFD0EAFE) : panelStrong,
              border: Border.all(color: accent.withValues(alpha: 0.5), width: 3),
            ),
            child: ClipOval(
              child: !ready
                  ? Center(
                      child: CircularProgressIndicator(
                        color: accent,
                        strokeWidth: 2,
                      ),
                    )
                  : Stack(
                      alignment: Alignment.center,
                      children: [
                        FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: ctrl.value.size.width,
                            height: ctrl.value.size.height,
                            child: VideoPlayer(ctrl),
                          ),
                        ),
                        if (!_playing)
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.48),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Видеокружок',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: isLight ? const Color(0xFF17202B) : text,
              fontSize: 13,
            ),
          ),
          if ((widget.media.durationMs ?? 0) > 0)
            Text(
              formatDuration(widget.media.durationMs ?? 0),
              style: TextStyle(
                color: isLight ? const Color(0xFF637083) : muted,
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }
}

class ImagePreview extends StatelessWidget {
  const ImagePreview({super.key, required this.source, required this.serverUrl});

  final String source;
  final String serverUrl;

  @override
  Widget build(BuildContext context) {
    final bytes = bytesFromDataUrl(source);
    final url = bytes == null ? resolveMediaUrl(source, serverUrl) : null;
    if (bytes == null && (url == null || url.isEmpty)) {
      return const Text('Фото не удалось открыть',
          style: TextStyle(color: muted));
    }
    return GestureDetector(
      onTap: () => _openViewer(context, bytes, url),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320, maxWidth: 320),
          child: bytes != null
              ? Image.memory(bytes, fit: BoxFit.cover)
              : Image.network(
                  url!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Text(
                    'Фото не удалось загрузить',
                    style: TextStyle(color: muted),
                  ),
                ),
        ),
      ),
    );
  }

  void _openViewer(BuildContext context, Uint8List? bytes, String? url) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 0.6,
                maxScale: 5,
                child: Center(
                  child: bytes != null
                      ? Image.memory(bytes, fit: BoxFit.contain)
                      : Image.network(url!, fit: BoxFit.contain),
                ),
              ),
            ),
            Positioned(
              right: 16,
              top: 16,
              child: SafeArea(
                child: IconButton.filledTonal(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
