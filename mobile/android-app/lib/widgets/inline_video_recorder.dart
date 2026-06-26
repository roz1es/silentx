import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../theme/app_theme.dart';

/// Инлайн-запись видеокружка: затемнённая область с кругом сверху, а строка
/// ввода превращается в нижнюю панель записи (таймер + «Отмена» + отправка).
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
  List<CameraDescription> _cameras = const [];
  CameraLensDirection _lens = CameraLensDirection.front;
  bool _ready = false;
  bool _busy = false;
  bool _torch = false;
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
      _cameras = cameras;
      await _openAndRecord(_lens);
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'Ошибка камеры: $e');
    }
  }

  Future<void> _openAndRecord(CameraLensDirection lens) async {
    final cam = _cameras.firstWhere(
      (c) => c.lensDirection == lens,
      orElse: () => _cameras.first,
    );
    _lens = cam.lensDirection;
    final ctrl = CameraController(
      cam,
      ResolutionPreset.medium,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    await ctrl.initialize();
    if (!mounted) {
      await ctrl.dispose();
      return;
    }
    setState(() {
      _camera = ctrl;
      _ready = true;
      _torch = false;
    });
    await ctrl.prepareForVideoRecording();
    await ctrl.startVideoRecording();
    if (!mounted) return;
    setState(() => _elapsedMs = 0);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      setState(() => _elapsedMs += 100);
      if (_elapsedMs >= _maxMs) _send();
    });
  }

  Future<void> _flip() async {
    if (_busy) return;
    final next = _lens == CameraLensDirection.front
        ? CameraLensDirection.back
        : CameraLensDirection.front;
    if (!_cameras.any((c) => c.lensDirection == next)) return;
    final cam = _camera;
    try {
      _timer?.cancel();
      if (cam != null && cam.value.isRecordingVideo) {
        await cam.stopVideoRecording();
      }
      await cam?.dispose();
    } on Object {
      // игнорируем
    }
    if (!mounted) return;
    setState(() {
      _camera = null;
      _ready = false;
    });
    await _openAndRecord(next);
  }

  Future<void> _toggleTorch() async {
    final cam = _camera;
    if (cam == null) return;
    try {
      _torch = !_torch;
      await cam.setFlashMode(_torch ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() {});
    } on Object {
      _torch = false; // фронталка обычно без вспышки
      if (mounted) setState(() {});
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
    final ready = _ready && _camera != null;
    return Column(
      children: [
        // Затемнённая область с кругом и кнопками камеры.
        Expanded(
          child: Container(
            color: Colors.black.withValues(alpha: 0.72),
            child: SafeArea(
              bottom: false,
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
                  else if (!ready)
                    const CircularProgressIndicator(color: Colors.white)
                  else
                    _circle(context),
                  const Spacer(),
                  if (ready)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: Row(
                        children: [
                          _smallBtn(Icons.cameraswitch_rounded, _flip),
                          const SizedBox(width: 12),
                          _smallBtn(
                            _torch
                                ? Icons.flash_on_rounded
                                : Icons.flash_off_rounded,
                            _toggleTorch,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        // Нижняя панель — «превращённая» строка ввода (непрозрачная).
        _bottomPanel(),
      ],
    );
  }

  Widget _bottomPanel() {
    return Material(
      color: bg,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              Expanded(child: _recordPill()),
              const SizedBox(width: 10),
              _sendBtn(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _recordPill() {
    return Container(
      height: 52,
      padding: const EdgeInsets.fromLTRB(16, 0, 6, 0),
      decoration: BoxDecoration(
        color: panelSoft,
        borderRadius: BorderRadius.circular(26),
      ),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: const BoxDecoration(
              color: danger,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _fmt(_elapsedMs),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          // Кнопка «Отмена» с большой зоной нажатия.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _busy ? null : _cancel,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Text(
                'Отмена',
                style: TextStyle(
                  color: danger,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sendBtn() {
    return Material(
      color: accent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _busy ? null : _send,
        child: const SizedBox(
          width: 52,
          height: 52,
          child: Icon(Icons.arrow_upward_rounded,
              color: Color(0xFF08131A), size: 26),
        ),
      ),
    );
  }

  Widget _circle(BuildContext context) {
    final size = (MediaQuery.of(context).size.width * 0.78).clamp(220.0, 340.0);
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

  Widget _smallBtn(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.white.withValues(alpha: 0.16),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _busy ? null : onTap,
        child: SizedBox(
          width: 46,
          height: 46,
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}
