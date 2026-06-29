import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../theme/app_theme.dart';

/// Результат листа вложений: фото из галереи (байты + имя), запрос системного
/// файла или запрос моментальной съёмки на камеру.
class AttachResult {
  const AttachResult.image(this.bytes, this.name)
      : isFile = false,
        isCamera = false;
  const AttachResult.file()
      : bytes = null,
        name = null,
        isFile = true,
        isCamera = false;
  const AttachResult.camera()
      : bytes = null,
        name = null,
        isFile = false,
        isCamera = true;

  final Uint8List? bytes;
  final String? name;
  final bool isFile;
  final bool isCamera;
}

/// Telegram-стиль шторка вложений: заголовок «Недавние» со стрелкой, крестик
/// слева, кнопка «Файл» справа, а ниже — сетка из 3 колонок с реальными
/// последними фото устройства (через photo_manager). Первая ячейка —
/// моментальная съёмка на камеру. Выбор фото / камеры закрывает лист и
/// возвращает [AttachResult] через Navigator.pop.
class AttachSheet extends StatefulWidget {
  const AttachSheet({super.key});

  @override
  State<AttachSheet> createState() => _AttachSheetState();
}

class _AttachSheetState extends State<AttachSheet> {
  final List<AssetEntity> _assets = [];
  // Кеш миниатюр по id ассета — чтобы превью не мерцали при пересборке ячеек
  // во время прокрутки сетки.
  final Map<String, Uint8List> _thumbCache = {};

  bool _loading = true;
  bool _denied = false;
  bool _picking = false;

  static const _pageSize = 80;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final ps = await PhotoManager.requestPermissionExtend();
      if (!ps.hasAccess) {
        if (mounted) {
          setState(() {
            _loading = false;
            _denied = true;
          });
        }
        return;
      }
      final paths = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        onlyAll: true,
        filterOption: FilterOptionGroup(
          orders: [
            const OrderOption(type: OrderOptionType.createDate, asc: false),
          ],
        ),
      );
      if (paths.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final assets =
          await paths.first.getAssetListPaged(page: 0, size: _pageSize);
      if (!mounted) return;
      setState(() {
        _assets
          ..clear()
          ..addAll(assets);
        _loading = false;
      });
    } on Object {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickAsset(AssetEntity asset) async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final file = await asset.originFile;
      final bytes = await file?.readAsBytes();
      if (bytes == null || bytes.isEmpty) {
        if (mounted) setState(() => _picking = false);
        return;
      }
      final title = await asset.titleAsync;
      final name = title.isNotEmpty ? title : 'photo.jpg';
      if (!mounted) return;
      Navigator.of(context).pop(AttachResult.image(bytes, name));
    } on Object {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final sheetBg = isLight ? Colors.white : panel;
    final titleColor = isLight ? lightText : text;
    final mutedColor = isLight ? lightMuted : muted;

    return DraggableScrollableSheet(
      initialChildSize: 0.64,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: sheetBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 2),
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: mutedColor.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            _header(titleColor, mutedColor),
            Expanded(child: _body(scrollController, titleColor, mutedColor)),
          ],
        ),
      ),
    );
  }

  Widget _header(Color titleColor, Color mutedColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      child: Row(
        children: [
          _circleBtn(
            Icons.close_rounded,
            () => Navigator.of(context).pop(),
            titleColor,
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Недавние',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: titleColor,
                  ),
                ),
                Icon(Icons.keyboard_arrow_down_rounded,
                    size: 22, color: mutedColor),
              ],
            ),
          ),
          _circleBtn(
            Icons.insert_drive_file_rounded,
            () => Navigator.of(context).pop(const AttachResult.file()),
            titleColor,
          ),
        ],
      ),
    );
  }

  Widget _body(
      ScrollController scrollController, Color titleColor, Color mutedColor) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: accent));
    }
    if (_denied) {
      return _deniedView(titleColor, mutedColor);
    }
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Stack(
      children: [
        GridView.builder(
          controller: scrollController,
          padding: EdgeInsets.fromLTRB(2, 2, 2, bottomInset + 8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
          ),
          itemCount: _assets.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) return _cameraCell(titleColor);
            return _AssetThumb(
              asset: _assets[index - 1],
              cache: _thumbCache,
              onTap: _pickAsset,
            );
          },
        ),
        if (_picking)
          Positioned.fill(
            child: ColoredBox(
              color: const Color(0x66000000),
              child: Center(child: CircularProgressIndicator(color: accent)),
            ),
          ),
      ],
    );
  }

  Widget _cameraCell(Color titleColor) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(const AttachResult.camera()),
      child: Container(
        color: panelStrong,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.photo_camera_rounded, color: titleColor, size: 30),
              const SizedBox(height: 6),
              Text(
                'Камера',
                style: TextStyle(fontSize: 12, color: titleColor),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _deniedView(Color titleColor, Color mutedColor) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.no_photography_rounded, size: 42, color: mutedColor),
            const SizedBox(height: 14),
            Text(
              'Нет доступа к галерее',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: titleColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Разрешите доступ к фото, чтобы выбрать снимок,\nили снимите новое фото на камеру.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: mutedColor),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => PhotoManager.openSetting(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: titleColor,
                    side: BorderSide(color: border),
                  ),
                  icon: const Icon(Icons.settings_rounded, size: 18),
                  label: const Text('Настройки'),
                ),
                FilledButton.icon(
                  onPressed: () =>
                      Navigator.of(context).pop(const AttachResult.camera()),
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: const Color(0xFF08131A),
                  ),
                  icon: const Icon(Icons.photo_camera_rounded, size: 18),
                  label: const Text('Камера'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap, Color iconColor) {
    return Material(
      color: panelSoft,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, size: 20, color: iconColor),
        ),
      ),
    );
  }
}

/// Одна ячейка-превью галереи. Грузит миниатюру один раз и кладёт её в общий
/// кеш родителя, поэтому при прокрутке сетки картинки не перезагружаются.
class _AssetThumb extends StatefulWidget {
  const _AssetThumb({
    required this.asset,
    required this.cache,
    required this.onTap,
  });

  final AssetEntity asset;
  final Map<String, Uint8List> cache;
  final void Function(AssetEntity asset) onTap;

  @override
  State<_AssetThumb> createState() => _AssetThumbState();
}

class _AssetThumbState extends State<_AssetThumb> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    final cached = widget.cache[widget.asset.id];
    if (cached != null) {
      _bytes = cached;
    } else {
      _loadThumb();
    }
  }

  Future<void> _loadThumb() async {
    final data = await widget.asset
        .thumbnailDataWithSize(const ThumbnailSize.square(256));
    if (data == null) return;
    widget.cache[widget.asset.id] = data;
    if (mounted) setState(() => _bytes = data);
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return GestureDetector(
      onTap: () => widget.onTap(widget.asset),
      child: Container(
        color: panelSoft,
        child: bytes == null
            ? null
            : Image.memory(
                bytes,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
      ),
    );
  }
}
