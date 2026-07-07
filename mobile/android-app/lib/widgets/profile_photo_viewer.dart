import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../format.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import 'glass.dart';

/// Открывает Telegram-стиль просмотрщик фото профиля.
/// [photos] — data-url или сетевые адреса; [dates] (мс) — необязательные даты
/// загрузки в том же порядке.
Future<void> showProfilePhotos(
  BuildContext context, {
  required String title,
  required List<String> photos,
  required String serverUrl,
  List<int?>? dates,
  int initialIndex = 0,
}) {
  final unique = <String>[];
  for (final p in photos) {
    if (p.trim().isNotEmpty && !unique.contains(p)) unique.add(p);
  }
  if (unique.isEmpty) return Future<void>.value();
  return Navigator.of(context).push(PageRouteBuilder<void>(
    opaque: false,
    barrierColor: Colors.black,
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, anim, __) => FadeTransition(
      opacity: anim,
      child: _ProfilePhotoViewer(
        title: title,
        photos: unique,
        serverUrl: serverUrl,
        dates: dates,
        initialIndex: initialIndex.clamp(0, unique.length - 1),
      ),
    ),
  ));
}

class _ProfilePhotoViewer extends StatefulWidget {
  const _ProfilePhotoViewer({
    required this.title,
    required this.photos,
    required this.serverUrl,
    required this.dates,
    required this.initialIndex,
  });

  final String title;
  final List<String> photos;
  final String serverUrl;
  final List<int?>? dates;
  final int initialIndex;

  @override
  State<_ProfilePhotoViewer> createState() => _ProfilePhotoViewerState();
}

class _ProfilePhotoViewerState extends State<_ProfilePhotoViewer> {
  late final PageController _page =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  double _dragY = 0; // свайп вниз для закрытия
  bool _saving = false;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  Uint8List? _bytesOf(String src) =>
      src.startsWith('data:') ? bytesFromDataUrl(src) : null;

  Widget _image(String src, {BoxFit fit = BoxFit.contain}) {
    final bytes = _bytesOf(src);
    if (bytes != null) return Image.memory(bytes, fit: fit, gaplessPlayback: true);
    final url = resolveMediaUrl(src, widget.serverUrl);
    if (url == null || url.isEmpty) {
      return const ColoredBox(color: Colors.black);
    }
    return Image.network(url, fit: fit, gaplessPlayback: true);
  }

  String? _dateLabel() {
    final ms = (widget.dates != null && _index < widget.dates!.length)
        ? widget.dates![_index]
        : null;
    if (ms == null || ms <= 0) return null;
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    const months = [
      'янв', 'фев', 'мар', 'апр', 'мая', 'июн',
      'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
    ];
    final t =
        '${d.hour}:${d.minute.toString().padLeft(2, '0')}';
    return '${d.day} ${months[d.month - 1]} ${d.year} в $t';
  }

  Future<void> _save() async {
    if (_saving) return;
    final bytes = _bytesOf(widget.photos[_index]);
    if (bytes == null) {
      showAppToast(context, 'Это фото нельзя сохранить', error: true);
      return;
    }
    setState(() => _saving = true);
    final ok = await saveImageToGallery(
        bytes, 'brenks_${DateTime.now().millisecondsSinceEpoch}.jpg');
    if (!mounted) return;
    setState(() => _saving = false);
    showAppToast(context, ok ? 'Сохранено в галерею' : 'Не удалось сохранить',
        error: !ok);
  }

  Future<void> _share() async {
    final bytes = _bytesOf(widget.photos[_index]);
    if (bytes == null) {
      showAppToast(context, 'Это фото нельзя переслать', error: true);
      return;
    }
    final ok = await shareImageBytes(bytes, 'photo.jpg');
    if (!ok && mounted) showAppToast(context, 'Не удалось поделиться', error: true);
  }

  void _menu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: panel,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.download_rounded),
              title: const Text('Сохранить в галерею'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _save();
              },
            ),
            ListTile(
              leading: const Icon(Icons.ios_share_rounded),
              title: const Text('Поделиться'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _share();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding;
    final bgOpacity = (1 - (_dragY.abs() / 400)).clamp(0.0, 1.0);
    final date = _dateLabel();
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: bgOpacity),
      body: Stack(
        children: [
          // Листаемые фото + свайп вниз для закрытия.
          Positioned.fill(
            child: Transform.translate(
              offset: Offset(0, _dragY),
              child: PageView.builder(
                controller: _page,
                itemCount: widget.photos.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) => GestureDetector(
                  onVerticalDragUpdate: (d) {
                    if (d.delta.dy > 0 || _dragY > 0) {
                      setState(() => _dragY += d.delta.dy);
                    }
                  },
                  onVerticalDragEnd: (d) {
                    if (_dragY > 130 || (d.primaryVelocity ?? 0) > 700) {
                      Navigator.of(context).pop();
                    } else {
                      setState(() => _dragY = 0);
                    }
                  },
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 5,
                    child: Center(child: _image(widget.photos[i])),
                  ),
                ),
              ),
            ),
          ),
          // Верх: имя + закрыть.
          Positioned(
            top: pad.top,
            left: 0,
            right: 0,
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.55),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Низ: счётчик/дата + кнопки + лента миниатюр.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.only(bottom: pad.bottom + 8, top: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.6),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.photos.length > 1) _thumbs(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 6, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Фотография ${_index + 1} из ${widget.photos.length}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700),
                              ),
                              if (date != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(date,
                                      style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.7),
                                          fontSize: 12)),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.download_rounded,
                                  color: Colors.white),
                          onPressed: _save,
                        ),
                        IconButton(
                          icon: const Icon(Icons.ios_share_rounded,
                              color: Colors.white),
                          onPressed: _share,
                        ),
                        IconButton(
                          icon: const Icon(Icons.more_vert_rounded,
                              color: Colors.white),
                          onPressed: _menu,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _thumbs() {
    return SizedBox(
      height: 60,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: widget.photos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final selected = i == _index;
          return GestureDetector(
            onTap: () => _page.animateToPage(
              i,
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
            ),
            child: Container(
              width: 48,
              height: 48,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected ? accent : Colors.white.withValues(alpha: 0.2),
                  width: selected ? 2.5 : 1,
                ),
              ),
              child: _image(widget.photos[i], fit: BoxFit.cover),
            ),
          );
        },
      ),
    );
  }
}
