import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../theme/app_theme.dart';

/// Лист вложений в стиле Telegram: сетка недавних фото галереи + «Файл».
class AttachSheet extends StatefulWidget {
  const AttachSheet({super.key, required this.onImage, required this.onFile});

  /// Выбрано фото из галереи (готовые байты + имя).
  final void Function(Uint8List bytes, String name) onImage;

  /// Нажата кнопка «Файл» — обычный системный выбор файла.
  final VoidCallback onFile;

  @override
  State<AttachSheet> createState() => _AttachSheetState();
}

class _AttachSheetState extends State<AttachSheet> {
  List<AssetEntity> _assets = const [];
  bool _loading = true;
  bool _denied = false;

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
      );
      if (paths.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final recent = await paths.first.getAssetListPaged(page: 0, size: 60);
      if (mounted) {
        setState(() {
          _assets = recent;
          _loading = false;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _loading = false;
          _denied = true;
        });
      }
    }
  }

  Future<void> _pick(AssetEntity asset) async {
    final bytes = await asset.originBytes;
    if (bytes == null || bytes.isEmpty) return;
    final title = await asset.titleAsync;
    if (!mounted) return;
    Navigator.of(context).pop();
    widget.onImage(bytes, title.isEmpty ? 'photo.jpg' : title);
  }

  /// Системный выбор фото — надёжный путь на любой версии Android.
  Future<void> _pickSystemImage() async {
    final res =
        await FilePicker.pickFiles(type: FileType.image, withData: true);
    final file = res?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null || bytes.isEmpty) return;
    if (!mounted) return;
    Navigator.of(context).pop();
    widget.onImage(bytes, file.name);
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final sheetBg = isLight ? Colors.white : panel;
    final titleColor = isLight ? lightText : text;
    final mutedColor = isLight ? lightMuted : muted;

    return Container(
      decoration: BoxDecoration(
        color: sheetBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: mutedColor.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Галерея',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: titleColor),
                ),
              ),
            ),
            SizedBox(
              height: 330,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _assets.isEmpty
                      ? _emptyState(mutedColor)
                      : GridView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 4,
                            crossAxisSpacing: 4,
                          ),
                          itemCount: _assets.length,
                          itemBuilder: (_, i) => _Thumb(
                            asset: _assets[i],
                            onTap: () => _pick(_assets[i]),
                          ),
                        ),
            ),
            Divider(height: 1, color: border),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _category(
                    Icons.photo_library_rounded,
                    'Галерея',
                    _pickSystemImage,
                    titleColor,
                  ),
                  const SizedBox(width: 28),
                  _category(
                    Icons.insert_drive_file_rounded,
                    'Файл',
                    () {
                      Navigator.of(context).pop();
                      widget.onFile();
                    },
                    titleColor,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(Color mutedColor) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _denied ? 'Нет доступа к недавним' : 'Недавние фото не найдены',
            style: TextStyle(color: mutedColor),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _pickSystemImage,
            style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: const Color(0xFF08131A)),
            icon: const Icon(Icons.photo_library_rounded, size: 18),
            label: const Text('Открыть галерею'),
          ),
          if (_denied) ...[
            const SizedBox(height: 6),
            TextButton(
              onPressed: PhotoManager.openSetting,
              child: const Text('Открыть настройки'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _category(
      IconData icon, String label, VoidCallback onTap, Color textColor) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: accent),
            ),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontSize: 12, color: textColor)),
          ],
        ),
      ),
    );
  }
}

/// Миниатюра фото в сетке (грузит превью один раз).
class _Thumb extends StatefulWidget {
  const _Thumb({required this.asset, required this.onTap});

  final AssetEntity asset;
  final VoidCallback onTap;

  @override
  State<_Thumb> createState() => _ThumbState();
}

class _ThumbState extends State<_Thumb> {
  Uint8List? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await widget.asset
        .thumbnailDataWithSize(const ThumbnailSize.square(300));
    if (mounted) setState(() => _data = d);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        color: Colors.black.withValues(alpha: 0.18),
        child: _data == null
            ? null
            : Image.memory(_data!, fit: BoxFit.cover, gaplessPlayback: true),
      ),
    );
  }
}
