import 'dart:typed_data';

import 'package:flutter/material.dart';

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

class _VideoNotePreview extends StatelessWidget {
  const _VideoNotePreview({required this.media});

  final MessageMedia media;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF242A33),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 118,
            height: 118,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: panelStrong,
              border: Border.all(color: accent.withValues(alpha: 0.32), width: 3),
            ),
            child: const Icon(Icons.play_arrow_rounded, color: accent, size: 50),
          ),
          const SizedBox(height: 10),
          const Text('Видеокружок',
              style: TextStyle(fontWeight: FontWeight.w900, color: text)),
          if ((media.durationMs ?? 0) > 0)
            Text(
              formatDuration(media.durationMs ?? 0),
              style: const TextStyle(color: muted, fontSize: 12),
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
