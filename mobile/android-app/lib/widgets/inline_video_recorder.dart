import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../theme/app_theme.dart';

/// Инлайн-запись видеокружка прямо в чате (как в Telegram): живое видео в круге,
/// таймер, «Отмена» и отправка. Запись стартует автоматически при показе.
class InlineVideoRecorder extends StatefulWidget {
  const InlineVideoRecorder({
    super.key,
    required this.onSend,
    required this.onCancel,
  });

  final void Function(MessageMedia media) onSend;
  final VoidCallback onCancel;

  @override
  State<InlineVideoRecorder> createState() => _InlineVideoRecorderState();
}

class _InlineVideoRecorderState extends State<InlineVideoRecorder> {
  CameraController? _camera;
  bool _ready = false;
  bool _busy = false;
  int _elapsedMs = 0;
  Timer? _timer;
  String? _error;

  static const _maxMs = 60000;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _error = 'Камера недоступна');
        return;
      }
      final cam = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final ctrl = CameraController(
        cam,
        ResolutionPreset.medium,
        enableAudio: true,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await ctrl.initialize();
      if (!mounted) return;
      setState(() {
        _camera = ctrl;
        _ready = true;
      });
      await ctrl.prepareForVideoRecording();
      await ctrl.startVideoRecording();
      if (!mounted) return;
      setState(() => _elapsedMs = 0);
      _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (!mounted) return;
        setState(() => _elapsedMs += 100);
        if (_elapsedMs >= _maxMs) _send();
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'Ошибка камеры: $e');
    }
  }

  Future<void> _send() async {
    if (_busy) return;
    setState(() => _busy = true);
    _timer?.cancel();
    final cam = _camera;
    if (cam == null || !cam.value.isRecordingVideo) {
      widget.onCancel();
      return;
    }
    try {
      final file = await cam.stopVideoRecording();
      final ms = _elapsedMs;
      final bytes = await io.File(file.path).readAsBytes();
      if (bytes.isEmpty) {
        widget.onCancel();
        return;
      }
      final dataUrl = 'data:video/mp4;base64,${base64Encode(bytes)}';
      widget.onSend(MessageMedia(
        kind: 'video_note',
        dataUrl: dataUrl,
        fileName: 'video_note.mp4',
        mimeType: 'video/mp4',
        durationMs: ms,
      ));
    } on Object {
      widget.onCancel();
    }
  }

  Future<void> _cancel() async {
    _timer?.cancel();
    final cam = _camera;
    try {
      if (cam != null && cam.value.isRecordingVideo) {
        await cam.stopVideoRecording();
      }
    } on Object {
      // игнорируем
    }
    widget.onCancel();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _camera?.dispose();
    super.dispose();
  }

  String _fmt(int ms) {
    final s = (ms / 1000).truncate();
    final r = (ms % 1000) ~/ 100;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')},$r';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.62),
      child: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white)),
              )
            else if (!_ready || _camera == null)
              const CircularProgressIndicator(color: Colors.white)
            else
              _circle(),
            const SizedBox(height: 28),
            // Таймер с мигающей красной точкой
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: danger,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _fmt(_elapsedMs),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: _busy ? null : _cancel,
                    child: const Text(
                      'Отмена',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Material(
                    color: accent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _busy ? null : _send,
                      child: const SizedBox(
                        width: 60,
                        height: 60,
                        child: Icon(Icons.send_rounded,
                            color: Color(0xFF08131A), size: 28),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circle() {
    const size = 260.0;
    final preview = _camera!.value.previewSize;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: danger, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 24,
          ),
        ],
      ),
      child: ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: preview?.height ?? size,
              height: preview?.width ?? size,
              child: CameraPreview(_camera!),
            ),
          ),
        ),
      ),
    );
  }
}
