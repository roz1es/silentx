import 'dart:io';

import 'package:flutter/material.dart';

import '../config.dart';
import '../services/auto_update_service.dart';
import '../theme/app_theme.dart';

Future<void> showBrenksUpdateDialog({
  required BuildContext context,
  required AutoUpdateService updater,
  required UpdateInfo update,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UpdateDialog(updater: updater, update: update),
  );
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({
    required this.updater,
    required this.update,
  });

  final AutoUpdateService updater;
  final UpdateInfo update;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double? _progress;
  File? _installer;
  String? _error;
  bool _busy = false;

  Future<void> _download() async {
    setState(() {
      _busy = true;
      _error = null;
      _progress = 0;
    });
    try {
      final file = await widget.updater.downloadInstaller(
        widget.update,
        onProgress: (value) {
          if (!mounted) return;
          setState(() => _progress = value);
        },
      );
      if (!mounted) return;
      setState(() {
        _installer = file;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Не удалось скачать обновление. Попробуйте позже.';
      });
    }
  }

  Future<void> _install() async {
    final installer = _installer;
    if (installer == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.updater.launchInstaller(installer);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Не удалось запустить установщик.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = ((_progress ?? 0) * 100).round();
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: border.withValues(alpha: 0.55)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.24),
                blurRadius: 36,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 116,
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFFFFF4D2),
                        Color(0xFFD5B462),
                        Color(0xFF2B2116),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        right: -22,
                        top: -42,
                        child: Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.20),
                          ),
                        ),
                      ),
                      const Positioned(
                        left: 24,
                        bottom: 24,
                        child: Text(
                          'БренксЧат',
                          style: TextStyle(
                            color: Color(0xFF12100D),
                            fontWeight: FontWeight.w900,
                            fontSize: 28,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Доступно обновление',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Текущая версия: $appVersion\nНовая версия: ${widget.update.version}',
                        style: const TextStyle(color: muted, height: 1.35),
                      ),
                      if ((widget.update.notes ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: panelSoft.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                                color: border.withValues(alpha: 0.45)),
                          ),
                          child: Text(
                            widget.update.notes!,
                            style: const TextStyle(color: text, height: 1.35),
                          ),
                        ),
                      ],
                      if (_progress != null) ...[
                        const SizedBox(height: 18),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: _progress,
                            minHeight: 8,
                            backgroundColor:
                                panelStrong.withValues(alpha: 0.45),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _installer == null
                              ? 'Загрузка: $percent%'
                              : 'Обновление скачано',
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!, style: const TextStyle(color: danger)),
                      ],
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _busy
                                  ? null
                                  : () => Navigator.of(context).pop(),
                              child: const Text('Позже'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: _busy
                                  ? null
                                  : _installer == null
                                      ? _download
                                      : _install,
                              child: Text(_installer == null
                                  ? 'Скачать'
                                  : 'Установить'),
                            ),
                          ),
                        ],
                      ),
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
