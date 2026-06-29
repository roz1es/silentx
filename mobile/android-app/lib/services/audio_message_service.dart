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

/// Запись и воспроизведение голосовых сообщений.
/// Требует разрешение RECORD_AUDIO (Android) / NSMicrophoneUsageDescription (iOS).
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

  /// Поток нормализованной громкости (0..1) во время записи — для живой волны.
  /// Интервал маленький, чтобы волна шла плавно почти в реальном времени.
  Stream<double> amplitudeStream(
          {Duration interval = const Duration(milliseconds: 60)}) =>
      _recorder.onAmplitudeChanged(interval).map((a) {
        final db = a.current.isFinite ? a.current : -45.0;
        return ((db + 45) / 45).clamp(0.0, 1.0).toDouble();
      });

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

  Future<VoiceRecording?> stopRecording({List<double>? envelope}) async {
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
        fileName: encodeVoiceWaveform(envelope),
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
    // Проигрываем из временного файла: BytesSource на Android часто
    // не воспроизводит m4a/aac.
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/play-${dataUrl.hashCode.abs()}.m4a';
    final file = io.File(path);
    if (!await file.exists()) {
      await file.writeAsBytes(bytes);
    }
    await _player.play(DeviceFileSource(path));
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

// ── Огибающая громкости голосового ────────────────────────────────────────
// Реальная форма волны снимается при записи (амплитуда микрофона) и кодируется
// в media.fileName (сервер хранит это поле как есть). Иначе волна на
// воспроизведении считается из сжатых AAC-байтов и не отражает голос.
const _wfMarker = '~wf';
const _wfBars = 28;

/// Кодирует огибающую (0..1) в строку для media.fileName. Пусто → обычное имя.
String encodeVoiceWaveform(List<double>? env) {
  if (env == null || env.isEmpty) return 'voice.m4a';
  final sb = StringBuffer(_wfMarker);
  final n = env.length;
  for (var i = 0; i < _wfBars; i++) {
    final start = (i * n / _wfBars).floor();
    final end = ((i + 1) * n / _wfBars).ceil();
    var m = 0.0;
    for (var j = start; j < end && j < n; j++) {
      if (env[j] > m) m = env[j];
    }
    final q = (m.clamp(0.0, 1.0) * 35).round().clamp(0, 35);
    sb.write(q.toRadixString(36));
  }
  return sb.toString();
}

/// Декодирует огибающую (0..1) из media.fileName, либо null если её там нет.
List<double>? decodeVoiceWaveform(String? fileName) {
  if (fileName == null || !fileName.startsWith(_wfMarker)) return null;
  final body = fileName.substring(_wfMarker.length);
  if (body.isEmpty) return null;
  final out = <double>[];
  for (var i = 0; i < body.length; i++) {
    final q = int.tryParse(body[i], radix: 36);
    if (q == null) return null;
    out.add(q / 35);
  }
  return out.isEmpty ? null : out;
}
