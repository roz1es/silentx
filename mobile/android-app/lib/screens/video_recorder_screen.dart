import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models.dart';
import '../theme/app_theme.dart';

/// Экран записи видеокружка (аналог Telegram видеозаметок).
/// При успешной отправке возвращает [MessageMedia] через Navigator.pop.
class VideoRecorderScreen extends StatefulWidget {
  const VideoRecorderScreen({super.key});

  @override
  State<VideoRecorderScreen> createState() => _VideoRecorderScreenState();
}

class _VideoRecorderScreenState extends State<VideoRecorderScreen> {
  CameraController? _camera;
  VideoPlayerController? _preview;
  bool _initialized = false;
  bool _recording = false;
  bool _previewing = false;
  int _elapsedMs = 0;
  Timer? _timer;
  XFile? _recorded;
  String? _error;

  static const _maxMs = 30000;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'Камера недоступна');
        return;
      }
      // Prefer front camera
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
        _initialized = true;
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'Ошибка камеры: $e');
    }
  }

  Future<void> _startRecording() async {
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized) return;
    try {
      await cam.prepareForVideoRecording();
      await cam.startVideoRecording();
      setState(() {
        _recording = true;
        _elapsedMs = 0;
      });
      _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (!mounted) return;
        setState(() => _elapsedMs += 100);
        if (_elapsedMs >= _maxMs) _stopRecording();
      });
    } on Object catch (e) {
      _showError('Не удалось начать запись: $e');
    }
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    final cam = _camera;
    if (cam == null || !cam.value.isRecordingVideo) return;
    try {
      final file = await cam.stopVideoRecording();
      setState(() {
        _recording = false;
        _recorded = file;
        _previewing = true;
      });
      final ctrl = VideoPlayerController.file(io.File(file.path));
      await ctrl.initialize();
      await ctrl.setLooping(true);
      await ctrl.play();
      if (mounted) setState(() => _preview = ctrl);
    } on Object catch (e) {
      _showError('Ошибка при остановке записи: $e');
    }
  }

  Future<void> _retake() async {
    await _preview?.dispose();
    final path = _recorded?.path;
    if (path != null) {
      try {
        await io.File(path).delete();
      } on Object {
        //
      }
    }
    setState(() {
      _preview = null;
      _recorded = null;
      _previewing = false;
      _elapsedMs = 0;
    });
  }

  Future<void> _send() async {
    final file = _recorded;
    if (file == null) return;
    final bytes = await io.File(file.path).readAsBytes();
    if (!mounted) return;
    final dataUrl = 'data:video/mp4;base64,${base64Encode(bytes)}';
    Navigator.pop(
      context,
      MessageMedia(
        kind: 'video_note',
        dataUrl: dataUrl,
        fileName: 'video_note.mp4',
        mimeType: 'video/mp4',
        durationMs: _elapsedMs,
      ),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _camera?.dispose();
    _preview?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text(
                        'Видеокружок',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            // Camera / preview circle
            Expanded(
              child: Center(
                child: _error != null
                    ? Text(_error!, style: const TextStyle(color: Colors.white))
                    : !_initialized
                        ? const CircularProgressIndicator(color: Colors.white)
                        : _circleArea(),
              ),
            ),
            // Duration label
            if (_recording || _previewing)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _formatMs(_elapsedMs),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            // Controls
            Padding(
              padding: const EdgeInsets.only(bottom: 32),
              child: _controls(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleArea() {
    const size = 270.0;
    if (_previewing && _preview != null && _preview!.value.isInitialized) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: accent, width: 3),
        ),
        child: ClipOval(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _preview!.value.size.width,
              height: _preview!.value.size.height,
              child: VideoPlayer(_preview!),
            ),
          ),
        ),
      );
    }
    final preview = _camera!.value.previewSize;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: _recording ? danger : Colors.white30,
          width: _recording ? 3 : 1.5,
        ),
      ),
      child: ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          // Заполняем круг кадром (cover), иначе 4:3-превью даёт чёрную рамку.
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

  Widget _controls() {
    if (_previewing) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _controlBtn(
            icon: Icons.refresh_rounded,
            label: 'Заново',
            color: Colors.white,
            onTap: _retake,
          ),
          const SizedBox(width: 48),
          _controlBtn(
            icon: Icons.send_rounded,
            label: 'Отправить',
            color: accent,
            onTap: _send,
            filled: true,
          ),
        ],
      );
    }

    final progress = _maxMs > 0 ? _elapsedMs / _maxMs : 0.0;
    return GestureDetector(
      onTap: _recording ? _stopRecording : _startRecording,
      child: SizedBox(
        width: 80,
        height: 80,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_recording)
              CircularProgressIndicator(
                value: progress.toDouble(),
                strokeWidth: 5,
                color: danger,
                backgroundColor: Colors.white24,
              ),
            Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                color: _recording ? danger : Colors.white,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _recording ? Icons.stop_rounded : Icons.fiber_manual_record_rounded,
                color: _recording ? Colors.white : danger,
                size: 34,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _controlBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool filled = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: filled ? color : Colors.white12,
              shape: BoxShape.circle,
              border: filled ? null : Border.all(color: color, width: 2),
            ),
            child: Icon(icon, color: filled ? Colors.white : color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }

  String _formatMs(int ms) {
    final s = (ms / 1000).truncate();
    final rem = (ms % 1000) ~/ 100;
    final min = s ~/ 60;
    final sec = s % 60;
    return '$min:${sec.toString().padLeft(2, '0')}.$rem';
  }
}
