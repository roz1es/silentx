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

  AudioRecorder _recorder;
  final AudioPlayer _player;
  DateTime? _startedAt;
  String? _recordingPath;

  Stream<PlayerState> get playerState => _player.onPlayerStateChanged;
  Stream<Duration> get positionChanged => _player.onPositionChanged;
  Stream<Duration> get durationChanged => _player.onDurationChanged;

  Stream<double> amplitudeLevels(Duration interval) {
    return _recorder.onAmplitudeChanged(interval).map((amplitude) {
      final current = amplitude.current;
      if (current.isNaN || current.isInfinite) return 0.0;
      return ((current + 55) / 55).clamp(0.0, 1.0).toDouble();
    });
  }

  Future<bool> hasRecordingPermission() => _recorder.hasPermission();

  Future<void> startRecording() async {
    if (await _recorder.isRecording().catchError((_) => false)) {
      await cancelRecording();
    }
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
        bitRate: 128000,
        sampleRate: 44100,
        numChannels: 1,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      ),
      path: path,
    );
  }

  Future<VoiceRecording?> stopRecording() async {
    final started = _startedAt;
    final path = await _recorder.stop().whenComplete(() {
      _startedAt = null;
      _recordingPath = null;
    });
    if (path == null) return null;

    final file = io.File(path);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    unawaited(file.delete().catchError((_) => file));
    await _resetRecorder();
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
    await _recorder.cancel().catchError((_) => null);
    final path = _recordingPath;
    _recordingPath = null;
    _startedAt = null;
    if (path != null) {
      unawaited(io.File(path).delete().catchError((_) => io.File(path)));
    }
    await _resetRecorder();
  }

  Future<void> playDataUrl(String dataUrl) async {
    await playSource(dataUrl);
  }

  Future<void> playSource(
    String source, {
    String? baseUrl,
    String? mimeType,
  }) async {
    final resolved = _resolveSource(source, baseUrl);
    if (resolved == null || resolved.isEmpty) return;
    await _player.stop();
    await _player.setReleaseMode(ReleaseMode.stop);
    await _player.setPlayerMode(PlayerMode.mediaPlayer);
    if (resolved.startsWith('data:')) {
      final bytes = _bytesFromDataUrl(resolved);
      if (bytes == null || bytes.isEmpty) return;
      final path = await _writePlaybackFile(bytes, resolved, mimeType);
      await _player.play(DeviceFileSource(path));
      return;
    }
    final uri = Uri.tryParse(resolved);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      await _player.play(UrlSource(resolved));
      return;
    }
    final file = io.File(resolved);
    if (await file.exists()) {
      await _player.play(DeviceFileSource(file.path));
    }
  }

  Future<void> stopPlayback() => _player.stop();

  Future<void> pausePlayback() => _player.pause();

  Future<void> resumePlayback() => _player.resume();

  Future<void> seekPlayback(Duration position) => _player.seek(position);

  Future<void> dispose() async {
    await _recorder.dispose();
    await _player.stop();
    await _player.dispose();
  }

  Future<void> _resetRecorder() async {
    await _recorder.dispose().catchError((_) {});
    _recorder = AudioRecorder();
  }

  Future<String> _writePlaybackFile(
    Uint8List bytes,
    String source,
    String? mimeType,
  ) async {
    final dir = await getApplicationCacheDirectory();
    final mediaDir = io.Directory('${dir.path}/brenkschat-playback');
    await mediaDir.create(recursive: true);
    final ext = _extensionFromMime(mimeType ?? _mimeFromDataUrl(source));
    final path = '${mediaDir.path}/${_stableHash(source)}$ext';
    final file = io.File(path);
    if (!await file.exists() || await file.length() != bytes.length) {
      await file.writeAsBytes(bytes, flush: false);
    }
    return path;
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

String? _resolveSource(String? value, String? baseUrl) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty || raw.startsWith('data:')) return raw;
  final uri = Uri.tryParse(raw);
  if (uri == null) return raw;
  if (uri.hasScheme || baseUrl == null || baseUrl.isEmpty) return raw;
  return Uri.parse(baseUrl).resolve(raw).toString();
}

String? _mimeFromDataUrl(String value) {
  if (!value.startsWith('data:')) return null;
  final semicolon = value.indexOf(';');
  if (semicolon <= 5) return null;
  return value.substring(5, semicolon);
}

String _extensionFromMime(String? mimeType) {
  return switch (mimeType) {
    'audio/mpeg' => '.mp3',
    'audio/wav' || 'audio/x-wav' => '.wav',
    'audio/ogg' => '.ogg',
    'video/mp4' => '.mp4',
    _ => '.m4a',
  };
}

String _stableHash(String value) {
  const offset = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  var hash = offset;
  for (final byte in utf8.encode(value)) {
    hash ^= byte;
    hash = (hash * prime) & 0xffffffffffffffff;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}
