import 'dart:io' as io;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Результат листа вложений: фото (байты + имя) или запрос системного файла.
class AttachResult {
  const AttachResult.image(this.bytes, this.name) : isFile = false;
  const AttachResult.file()
      : bytes = null,
        name = null,
        isFile = true;

  final Uint8List? bytes;
  final String? name;
  final bool isFile;
}

/// Лист вложений: «Галерея» (системный выбор изображения — открывает галерею
/// телефона) и «Файл». Возвращает [AttachResult] через Navigator.pop.
class AttachSheet extends StatelessWidget {
  const AttachSheet({super.key});

  Future<void> _pickGallery(BuildContext context) async {
    try {
      final res =
          await FilePicker.pickFiles(type: FileType.image, withData: true);
      final file = res?.files.single;
      if (file == null) return;
      final bytes = file.bytes ??
          (file.path == null
              ? null
              : await io.File(file.path!).readAsBytes());
      if (bytes == null || bytes.isEmpty) return;
      if (!context.mounted) return;
      Navigator.of(context).pop(AttachResult.image(bytes, file.name));
    } on Object {
      if (context.mounted) Navigator.of(context).pop();
    }
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
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: mutedColor.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Вложение',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: titleColor),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _option(
                    Icons.photo_library_rounded,
                    'Галерея',
                    () => _pickGallery(context),
                    titleColor,
                  ),
                  _option(
                    Icons.insert_drive_file_rounded,
                    'Файл',
                    () => Navigator.of(context).pop(const AttachResult.file()),
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

  Widget _option(
      IconData icon, String label, VoidCallback onTap, Color textColor) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: accent, size: 26),
            ),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(fontSize: 13, color: textColor)),
          ],
        ),
      ),
    );
  }
}
