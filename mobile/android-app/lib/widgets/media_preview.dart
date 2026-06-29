import 'dart:async';
import 'dart:io' as io;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../format.dart';
import '../models.dart';
import '../services/audio_message_service.dart';
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
        return ImagePreview(
          source: media.dataUrl,
          serverUrl: serverUrl,
          timeLabel: timeLabel,
          read: read,
          own: own,
        );
      case 'voice':
        return VoicePreview(media: media);
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
      width: 210,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF242A33),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.insert_drive_file_rounded,
                color: accent, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              media.fileName ?? 'Файл',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: text, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class VoicePreview extends StatefulWidget {
  const VoicePreview({super.key, required this.media});

  final MessageMedia media;

  @override
  State<VoicePreview> createState() => _VoicePreviewState();
}

class _VoicePreviewState extends State<VoicePreview> {
  final AudioPlayer _player = AudioPlayer();
  final List<StreamSubscription<dynamic>> _subs = [];
  PlayerState _state = PlayerState.stopped;
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  String? _path;
  bool _preparing = false;
  // Реальная огибающая снимается при записи и хранится в fileName. Если её
  // нет (старые сообщения) — fallback на форму из байтов.
  late final List<double> _wave = _resolveWave();

  List<double> _resolveWave() {
    final env = decodeVoiceWaveform(widget.media.fileName);
    if (env != null && env.isNotEmpty) {
      return [for (final v in env) 3.0 + v.clamp(0.0, 1.0) * 17.0];
    }
    return waveformFromBytes(bytesFromDataUrl(widget.media.dataUrl));
  }

  bool get _playing => _state == PlayerState.playing;

  @override
  void initState() {
    super.initState();
    _subs.add(_player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _state = s);
    }));
    _subs.add(_player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _pos = p);
    }));
    _subs.add(_player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _dur = d);
    }));
    _subs.add(_player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _state = PlayerState.completed;
          _pos = Duration.zero;
        });
      }
    }));
  }

  Future<void> _toggle() async {
    try {
      if (_state == PlayerState.playing) {
        await _player.pause();
        return;
      }
      if (_state == PlayerState.paused) {
        await _player.resume();
        return;
      }
      if (_preparing) return;
      _preparing = true;
      if (_path == null) {
        final bytes = bytesFromDataUrl(widget.media.dataUrl);
        if (bytes == null || bytes.isEmpty) {
          _preparing = false;
          return;
        }
        final dir = await getTemporaryDirectory();
        final p =
            '${dir.path}/voice-${widget.media.dataUrl.hashCode.abs()}.m4a';
        final f = io.File(p);
        if (!await f.exists()) await f.writeAsBytes(bytes);
        _path = p;
      }
      await _player.stop();
      await _player.play(DeviceFileSource(_path!));
      _preparing = false;
    } on Object {
      _preparing = false;
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bytes = bytesFromDataUrl(widget.media.dataUrl);
    final size = _formatSize(bytes?.length ?? 0);
    final totalMs = _dur.inMilliseconds > 0
        ? _dur.inMilliseconds
        : (widget.media.durationMs ?? 0);
    final progress =
        totalMs == 0 ? 0.0 : (_pos.inMilliseconds / totalMs).clamp(0.0, 1.0);
    final shownMs = (_playing || _state == PlayerState.paused)
        ? _pos.inMilliseconds
        : totalMs;
    final time = formatDuration(shownMs);
    final meta = size.isEmpty ? time : '$time, $size';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _toggle,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent,
            ),
            child: Icon(
              _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: const Color(0xFF08131A),
              size: 24,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _VoiceWave(bars: _wave, progress: progress),
            const SizedBox(height: 5),
            Text(meta, style: const TextStyle(color: muted, fontSize: 11)),
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

/// Строит форму волны (высоты столбиков) из байтов аудиозаписи: разбивает их
/// на [count] корзин и берёт среднее отклонение от середины — получается
/// уникальный для каждой записи профиль громкости.
List<double> waveformFromBytes(Uint8List? bytes, {int count = 28}) {
  const minH = 3.0;
  const maxH = 20.0;
  if (bytes == null || bytes.length < count * 2) {
    return List<double>.filled(count, (minH + maxH) / 3);
  }
  final step = bytes.length / count;
  final raw = List<double>.filled(count, 0);
  for (var i = 0; i < count; i++) {
    final start = (i * step).floor();
    final end = math.min(((i + 1) * step).floor(), bytes.length);
    var sum = 0;
    for (var j = start; j < end; j++) {
      sum += (bytes[j] - 128).abs();
    }
    raw[i] = end > start ? sum / (end - start) : 0;
  }
  var lo = raw[0];
  var hi = raw[0];
  for (final v in raw) {
    lo = math.min(lo, v);
    hi = math.max(hi, v);
  }
  final range = (hi - lo) < 1e-6 ? 1.0 : (hi - lo);
  return [
    for (final v in raw) minH + ((v - lo) / range) * (maxH - minH),
  ];
}

class _VoiceWave extends StatelessWidget {
  const _VoiceWave({required this.bars, this.progress = 0});

  final List<double> bars;

  /// 0..1 — доля проигранного (закрашивается ярким золотом).
  final double progress;

  @override
  Widget build(BuildContext context) {
    final active = (bars.length * progress).round();
    return SizedBox(
      height: 20,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < bars.length; i++)
            Container(
              width: 2.5,
              height: bars[i].clamp(3.0, 20.0),
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: i < active ? accent : accent.withValues(alpha: 0.3),
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

  void _openViewer(BuildContext context) {
    showGeneralDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      barrierDismissible: true,
      barrierLabel: 'note',
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, __, ___) => _VideoNoteViewer(
        media: widget.media,
        timeLabel: widget.timeLabel,
      ),
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          // Кружок «вырастает» из маленького в крупный круг (как в Telegram).
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.3, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
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
      onTap: () => _openViewer(context),
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

class ImagePreview extends StatefulWidget {
  const ImagePreview({
    super.key,
    required this.source,
    required this.serverUrl,
    this.timeLabel,
    this.read = false,
    this.own = false,
  });

  final String source;
  final String serverUrl;
  // Для «голого» фото без пузыря — наложить время/галочки прямо на снимок.
  final String? timeLabel;
  final bool read;
  final bool own;

  @override
  State<ImagePreview> createState() => _ImagePreviewState();
}

class _ImagePreviewState extends State<ImagePreview> {
  // Соотношение сторон по источнику кешируем глобально: при прокрутке/рециклинге
  // высота картинки известна сразу с первого кадра — лента не «прыгает» при
  // (пере)декодировании.
  static final Map<String, double> _aspectCache = {};

  // Декодируем один раз и держим стабильные байты — иначе Image.memory
  // перезагружается на каждый rebuild и лента «прыгает».
  Uint8List? _bytes;
  String? _url;
  double? _aspect;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(ImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        oldWidget.serverUrl != widget.serverUrl) {
      _decode();
    }
  }

  void _decode() {
    final b = bytesFromDataUrl(widget.source);
    _bytes = b;
    _url = b == null ? resolveMediaUrl(widget.source, widget.serverUrl) : null;
    final cached = _aspectCache[widget.source];
    if (cached != null) {
      _aspect = cached;
      return;
    }
    final ImageProvider? provider = b != null
        ? MemoryImage(b)
        : (_url != null && _url!.isNotEmpty ? NetworkImage(_url!) : null);
    if (provider != null) _resolveAspect(provider, widget.source);
  }

  // Получаем реальные размеры картинки (для memory и network) и кешируем аспект.
  void _resolveAspect(ImageProvider provider, String key) {
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      final hh = info.image.height;
      final a = hh == 0 ? 1.0 : info.image.width / hh;
      _aspectCache[key] = a;
      if (mounted) setState(() => _aspect = a);
      stream.removeListener(listener);
    }, onError: (_, __) => stream.removeListener(listener));
    stream.addListener(listener);
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    final url = _url;
    if (bytes == null && (url == null || url.isEmpty)) {
      return const Text('Фото не удалось открыть',
          style: TextStyle(color: muted));
    }
    // Фикс-размер по аспекту — стабильная высота, лента не прыгает при декоде.
    final aspect = _aspect ?? 1.0;
    const maxW = 250.0;
    const maxH = 320.0;
    double w = maxW;
    double h = maxW / aspect;
    if (h > maxH) {
      h = maxH;
      w = maxH * aspect;
    }
    return GestureDetector(
      onTap: () => _openViewer(context, bytes, url),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            SizedBox(
              width: w,
              height: h,
              child: bytes != null
                  ? Image.memory(bytes,
                      fit: BoxFit.cover, gaplessPlayback: true)
                  : Image.network(
                      url!,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => const Text(
                        'Фото не удалось загрузить',
                        style: TextStyle(color: muted),
                      ),
                    ),
            ),
            // Время + галочки поверх снимка (когда фото без пузыря).
            if (widget.timeLabel != null)
              Positioned(
                right: 8,
                bottom: 8,
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

  void _openViewer(BuildContext context, Uint8List? bytes, String? url) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onVerticalDragEnd: (d) {
                  if ((d.primaryVelocity ?? 0).abs() > 250) {
                    Navigator.pop(context);
                  }
                },
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

/// Увеличенный просмотр видеокружка: большой круг + кольцо-перемотка вокруг.
class _VideoNoteViewer extends StatefulWidget {
  const _VideoNoteViewer({required this.media, this.timeLabel});

  final MessageMedia media;
  final String? timeLabel;

  @override
  State<_VideoNoteViewer> createState() => _VideoNoteViewerState();
}

class _VideoNoteViewerState extends State<_VideoNoteViewer> {
  VideoPlayerController? _ctrl;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final bytes = bytesFromDataUrl(widget.media.dataUrl);
    if (bytes == null || bytes.isEmpty) return;
    try {
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/vnote_${widget.media.dataUrl.hashCode.abs()}.mp4';
      await io.File(path).writeAsBytes(bytes);
      final ctrl = VideoPlayerController.file(io.File(path));
      await ctrl.initialize();
      await ctrl.setLooping(true);
      ctrl.addListener(() {
        if (mounted) setState(() {});
      });
      await ctrl.play();
      if (mounted) setState(() => _ctrl = ctrl);
    } on Object {
      // не удалось — закроется по тапу
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final c = _ctrl;
    if (c == null) return;
    c.value.isPlaying ? c.pause() : c.play();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final c = _ctrl;
    final ready = c != null && c.value.isInitialized;
    final dia = (MediaQuery.of(context).size.shortestSide * 0.9)
        .clamp(280.0, 520.0)
        .toDouble();
    final dur = c?.value.duration ?? Duration.zero;
    final pos = c?.value.position ?? Duration.zero;
    final progress = dur.inMilliseconds == 0
        ? 0.0
        : (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);

    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      // Кружок увеличивается поверх живого чата (как в Telegram): фон не
      // размывается и не затемняется.
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: _togglePlay,
                  child: SizedBox(
                    width: dia,
                    height: dia,
                    child: CustomPaint(
                      painter: _RingPainter(
                        progress: progress.toDouble(),
                        color: accent,
                        bg: Colors.white.withValues(alpha: 0.18),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: ClipOval(
                          child: ready
                              ? FittedBox(
                                  fit: BoxFit.cover,
                                  child: SizedBox(
                                    width: c.value.size.width,
                                    height: c.value.size.height,
                                    child: VideoPlayer(c),
                                  ),
                                )
                              : Container(
                                  color: panelStrong,
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: dia - 8,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_fmt(pos),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13)),
                      if (widget.timeLabel != null)
                        Text(widget.timeLabel!,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Кольцо-прогресс вокруг увеличенного видеокружка.
class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.color, required this.bg});

  final double progress;
  final Color color;
  final Color bg;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 4.0;
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - stroke / 2;
    final bgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = bg;
    canvas.drawCircle(center, radius, bgPaint);
    if (progress > 0) {
      final fg = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        fg,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color || old.bg != bg;
}
