import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../models.dart';

class VoiceRecording {
  const VoiceRecording({
    required this.media,
    required this.durationMs,
  });

  final MessageMedia media;
  final int durationMs;
}

class AudioMessageService {
  AudioMessageService()
      : _recorder = AudioRecorder(),
        _player = AudioPlayer();

  final AudioRecorder _recorder;
  final AudioPlayer _player;
  DateTime? _startedAt;
  String? _recordingPath;

  Stream<PlayerState> get playerState => _player.onPlayerStateChanged;

  Future<bool> hasRecordingPermission() => _recorder.hasPermission();

  Future<void> startRecording() async {
    final allowed = await _recorder.hasPermission();
    if (!allowed) {
      throw Exception('Нет доступа к микрофону.');
    }

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/brenks-voice-${DateTime.now().millisecondsSinceEpoch}.m4a';
    _recordingPath = path;
    _startedAt = DateTime.now();
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 44100,
      ),
      path: path,
    );
  }

  Future<VoiceRecording?> stopRecording() async {
    final started = _startedAt;
    final path = await _recorder.stop();
    _startedAt = null;
    _recordingPath = null;
    if (path == null) return null;

    final file = io.File(path);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    unawaited(file.delete().catchError((_) => file));
    if (bytes.isEmpty) return null;

    final durationMs =
        started == null ? 0 : DateTime.now().difference(started).inMilliseconds;
    return VoiceRecording(
      durationMs: durationMs,
      media: MessageMedia(
        kind: 'voice',
        dataUrl: 'data:audio/mp4;base64,${base64Encode(bytes)}',
        fileName: 'voice.m4a',
        mimeType: 'audio/mp4',
        durationMs: durationMs,
      ),
    );
  }

  Future<void> cancelRecording() async {
    await _recorder.stop().catchError((_) => null);
    final path = _recordingPath;
    _recordingPath = null;
    _startedAt = null;
    if (path != null) {
      unawaited(io.File(path).delete().catchError((_) => io.File(path)));
    }
  }

  Future<void> playDataUrl(String dataUrl) async {
    final bytes = _bytesFromDataUrl(dataUrl);
    if (bytes == null || bytes.isEmpty) return;
    await _player.stop();
    await _player.play(BytesSource(bytes));
  }

  Future<void> stopPlayback() => _player.stop();

  Future<void> dispose() async {
    await _recorder.dispose();
    await _player.dispose();
  }
}

Uint8List? _bytesFromDataUrl(String dataUrl) {
  const marker = 'base64,';
  final index = dataUrl.indexOf(marker);
  if (index == -1) return null;
  try {
    return base64Decode(dataUrl.substring(index + marker.length));
  } on Object {
    return null;
  }
}
