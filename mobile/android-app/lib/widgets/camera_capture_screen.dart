import 'dart:io' as io;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Полноэкранная моментальная съёмка фото. Возвращает байты снимка через
/// Navigator.pop (Uint8List) либо null при отмене/ошибке.
class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({super.key});

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen> {
  CameraController? _camera;
  List<CameraDescription> _cameras = const [];
  CameraLensDirection _lens = CameraLensDirection.back;
  bool _ready = false;
  bool _busy = false;
  bool _flash = false;
  String? _error;

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
      await _open(_lens);
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'Ошибка камеры: $e');
    }
  }

  Future<void> _open(CameraLensDirection lens) async {
    final cam = _cameras.firstWhere(
      (c) => c.lensDirection == lens,
      orElse: () => _cameras.first,
    );
    _lens = cam.lensDirection;
    final ctrl = CameraController(
      cam,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    await ctrl.initialize();
    if (!mounted) {
      await ctrl.dispose();
      return;
    }
    try {
      await ctrl.setFlashMode(FlashMode.off);
    } on Object {
      // некоторые камеры (фронталка) без вспышки — игнорируем
    }
    setState(() {
      _camera = ctrl;
      _ready = true;
      _flash = false;
    });
  }

  Future<void> _flip() async {
    if (_busy) return;
    final next = _lens == CameraLensDirection.front
        ? CameraLensDirection.back
        : CameraLensDirection.front;
    if (!_cameras.any((c) => c.lensDirection == next)) return;
    final cam = _camera;
    setState(() {
      _camera = null;
      _ready = false;
    });
    try {
      await cam?.dispose();
    } on Object {
      // игнорируем
    }
    await _open(next);
  }

  Future<void> _toggleFlash() async {
    final cam = _camera;
    if (cam == null) return;
    try {
      _flash = !_flash;
      await cam.setFlashMode(_flash ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() {});
    } on Object {
      _flash = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _capture() async {
    final cam = _camera;
    if (_busy || cam == null || !cam.value.isInitialized) return;
    setState(() => _busy = true);
    try {
      final file = await cam.takePicture();
      final bytes = await io.File(file.path).readAsBytes();
      if (!mounted) return;
      if (bytes.isEmpty) {
        setState(() => _busy = false);
        return;
      }
      Navigator.of(context).pop<Uint8List>(bytes);
    } on Object {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _ready && _camera != null;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              ),
            )
          else if (!ready)
            const Center(child: CircularProgressIndicator(color: Colors.white))
          else
            Positioned.fill(child: _preview()),
          // Верхняя панель: закрыть + вспышка.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _topBtn(Icons.close_rounded,
                      () => Navigator.of(context).pop()),
                  if (ready)
                    _topBtn(
                      _flash ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                      _toggleFlash,
                    ),
                ],
              ),
            ),
          ),
          // Нижняя панель: спуск + переключение камеры.
          if (ready)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      _shutter(),
                      Align(
                        alignment: Alignment.centerRight,
                        child: _topBtn(Icons.cameraswitch_rounded, _flip),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _preview() {
    final cam = _camera!;
    final preview = cam.value.previewSize;
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: preview?.height ?? 1,
          height: preview?.width ?? 1,
          child: CameraPreview(cam),
        ),
      ),
    );
  }

  Widget _shutter() {
    return GestureDetector(
      onTap: _busy ? null : _capture,
      child: Container(
        width: 74,
        height: 74,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.18),
          border: Border.all(color: Colors.white, width: 4),
        ),
        child: Center(
          child: _busy
              ? const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 3),
                )
              : Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _topBtn(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.black.withValues(alpha: 0.4),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _busy ? null : onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}
