import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../config.dart';

class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.url,
    this.notes,
    this.publishedAt,
  });

  final String version;
  final String url;
  final String? notes;
  final DateTime? publishedAt;

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    final published = json['publishedAt']?.toString();
    return UpdateInfo(
      version: json['version']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      notes: json['notes']?.toString(),
      publishedAt: published == null ? null : DateTime.tryParse(published),
    );
  }
}

class AutoUpdateService {
  const AutoUpdateService({
    this.currentVersion = appVersion,
    this.manifestUrl = updateManifestUrl,
  });

  final String currentVersion;
  final String manifestUrl;

  bool get supported => Platform.isWindows;

  Future<UpdateInfo?> checkForUpdate() async {
    if (!supported) return null;
    final uri = Uri.tryParse(manifestUrl);
    if (uri == null) return null;

    final client = HttpClient();
    try {
      final request =
          await client.getUrl(uri).timeout(const Duration(seconds: 10));
      final response =
          await request.close().timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final body = await utf8.decodeStream(response);
      final parsed = jsonDecode(body);
      if (parsed is! Map<String, dynamic>) return null;
      final info = UpdateInfo.fromJson(parsed);
      if (info.version.isEmpty || info.url.isEmpty) return null;
      if (compareVersions(currentVersion, info.version) >= 0) return null;
      return info;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<File> downloadInstaller(
    UpdateInfo info, {
    void Function(double progress)? onProgress,
  }) async {
    final uri = Uri.parse(info.url);
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}${Platform.pathSeparator}BrenksChatSetup-${info.version}.exe');
    if (await file.exists()) {
      await file.delete();
    }

    final client = HttpClient();
    IOSink? sink;
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Не удалось скачать обновление.');
      }
      final total = response.contentLength;
      var loaded = 0;
      sink = file.openWrite();
      await for (final chunk in response) {
        loaded += chunk.length;
        sink.add(chunk);
        if (total > 0) {
          onProgress?.call((loaded / total).clamp(0, 1));
        }
      }
      await sink.flush();
      await sink.close();
      onProgress?.call(1);
      return file;
    } finally {
      client.close(force: true);
      await sink?.close().catchError((_) {});
    }
  }

  Future<void> launchInstaller(File file) async {
    if (!Platform.isWindows) return;
    await Process.start(
      file.path,
      const [],
      mode: ProcessStartMode.detached,
      runInShell: true,
    );
  }
}
