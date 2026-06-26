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
    this.timeLabel,
    this.read = false,
    this.own = false,
  });

  final MessageMedia media;
  final String serverUrl;
  final ValueChanged<MessageMedia> onPlayVoice;
  // Для видеокружка — наложить время/галочки прямо на круг.
  final String? timeLabel;
  final bool read;
  final bool own;

  @override
  Widget build(BuildContext context) {
    switch (media.kind) {
      case 'image':
        return ImagePreview(source: media.dataUrl, serverUrl: serverUrl);
      case 'voice':
        return VoicePreview(media: media, onPlay: () => onPlayVoice(media));
      case 'video_note':
        return _VideoNotePreview(
          media: media,
          timeLabel: timeLabel,
          read: read,
          own: own,
        );
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
    final bytes = bytesFromDataUrl(media.dataUrl);
    final size = _formatSize(bytes?.length ?? 0);
    final dur = formatDuration(media.durationMs ?? 0);
    final meta = size.isEmpty ? dur : '$dur, $size';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onPlay,
          child: Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: accent,
            ),
            child: const Icon(Icons.play_arrow_rounded,
                color: Color(0xFF08131A), size: 26),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const _VoiceWave(),
            const SizedBox(height: 6),
            Text(meta, style: const TextStyle(color: muted, fontSize: 11.5)),
          ],
        ),
      ],
    );
  }
}

String _formatSize(int bytes) {
  if (bytes <= 0) return '';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  return '${(kb / 1024).toStringAsFixed(1)} MB';
}

class _VoiceWave extends StatelessWidget {
  const _VoiceWave();

  // Статичная «волна» из палочек разной высоты.
  static const _bars = <double>[
    5, 9, 14, 8, 12, 18, 13, 7, 11, 17, 10, 6, //
    13, 8, 15, 10, 7, 12, 18, 9, 11, 7, 14, 9,
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (final h in _bars)
            Container(
              width: 2.5,
              height: h,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }
}

class _VideoNotePreview extends StatefulWidget {
  const _VideoNotePreview({
    required this.media,
    this.timeLabel,
    this.read = false,
    this.own = false,
  });

  final MessageMedia media;
  final String? timeLabel;
  final bool read;
  final bool own;

  @override
  State<_VideoNotePreview> createState() => _VideoNotePreviewState();
}

class _VideoNotePreviewState extends State<_VideoNotePreview> {
  VideoPlayerController? _ctrl;
  bool _playing = false;
  bool _muted = true;

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
      final path =
          '${dir.path}/vnote_${widget.media.dataUrl.hashCode.abs()}.mp4';
      await io.File(path).writeAsBytes(bytes);
      final ctrl = VideoPlayerController.file(io.File(path));
      await ctrl.initialize();
      await ctrl.setVolume(0); // по умолчанию без звука (как в Telegram)
      await ctrl.setLooping(true);
      ctrl.addListener(() {
        if (mounted) setState(() => _playing = ctrl.value.isPlaying);
      });
      if (mounted) setState(() => _ctrl = ctrl);
    } on Object {
      // Не удалось инициализировать — останется иконка-плейсхолдер.
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

  void _toggleMute() {
    final ctrl = _ctrl;
    setState(() => _muted = !_muted);
    ctrl?.setVolume(_muted ? 0 : 1);
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
    const size = 192.0;
    final dur = widget.media.durationMs ?? 0;

    return GestureDetector(
      onTap: _togglePlay,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          children: [
            // Круг: видео либо иконка-плейсхолдер видеокружка.
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isLight ? const Color(0xFFD0EAFE) : panelStrong,
                border:
                    Border.all(color: accent.withValues(alpha: 0.5), width: 3),
              ),
              child: ClipOval(
                child: ready
                    ? FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: ctrl.value.size.width,
                          height: ctrl.value.size.height,
                          child: VideoPlayer(ctrl),
                        ),
                      )
                    : Center(
                        child: Icon(
                          Icons.videocam_rounded,
                          size: 46,
                          color: isLight
                              ? const Color(0xFF4E5B6B)
                              : Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
              ),
            ),
            // Кнопка play по центру, когда не воспроизводится.
            if (ready && !_playing)
              const Positioned.fill(
                child: Center(
                  child: _CircleIcon(icon: Icons.play_arrow_rounded, size: 52),
                ),
              ),
            // Значок звука сверху по центру (тап — вкл/выкл).
            Positioned(
              top: 8,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: _toggleMute,
                  child: _CircleIcon(
                    icon: _muted
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded,
                    size: 30,
                    iconSize: 16,
                  ),
                ),
              ),
            ),
            // Длительность — пилюля снизу слева.
            if (dur > 0)
              Positioned(
                left: 10,
                bottom: 10,
                child: _OverlayPill(
                  child: Text(
                    formatDuration(dur),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            // Время + галочки — снизу справа.
            if (widget.timeLabel != null)
              Positioned(
                right: 10,
                bottom: 10,
                child: _OverlayPill(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(widget.timeLabel!,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12)),
                      if (widget.own) ...[
                        const SizedBox(width: 3),
                        Icon(
                          widget.read
                              ? Icons.done_all_rounded
                              : Icons.done_rounded,
                          size: 14,
                          color: widget.read ? softGold : Colors.white,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Тёмный круглый бейдж с иконкой (play / звук) поверх видеокружка.
class _CircleIcon extends StatelessWidget {
  const _CircleIcon({required this.icon, required this.size, this.iconSize});

  final IconData icon;
  final double size;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: Colors.white, size: iconSize ?? size * 0.6),
    );
  }
}

/// Полупрозрачная пилюля (длительность / время) поверх видеокружка.
class _OverlayPill extends StatelessWidget {
  const _OverlayPill({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
      ),
      child: child,
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
