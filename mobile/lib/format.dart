import 'dart:convert';
import 'dart:typed_data';

import 'models.dart';

/// Утилиты форматирования и работы с медиа, общие для экранов и виджетов.

String formatTime(int timestamp) {
  if (timestamp <= 0) return '';
  final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

/// Метка времени для списка чатов: «14:05», «вчера» или дата.
String formatChatTimestamp(int timestamp) {
  if (timestamp <= 0) return '';
  final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(date.year, date.month, date.day);
  final diffDays = today.difference(that).inDays;
  if (diffDays <= 0) return formatTime(timestamp);
  if (diffDays == 1) return 'вчера';
  if (diffDays < 7) {
    const days = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];
    return days[date.weekday - 1];
  }
  return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}';
}

String formatDuration(int milliseconds) {
  final totalSeconds = (milliseconds / 1000).round();
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

String lastMessageLabel(String? text) {
  final trimmed = text?.trim();
  if (trimmed == null || trimmed.isEmpty) return 'Нет сообщений';
  if (trimmed == ' ') return 'Медиа';
  return trimmed;
}

String messagePreview(Message message) {
  if (message.deleted) return 'Сообщение удалено';
  final media = message.media;
  if (media != null) {
    return switch (media.kind) {
      'image' => 'Фото',
      'voice' => 'Голосовое сообщение',
      'video_note' => 'Видеокружок',
      'file' => media.fileName ?? 'Файл',
      _ => 'Медиа',
    };
  }
  if (message.imageUrl?.isNotEmpty == true) return 'Фото';
  if (message.encryptedText) return '🔒 Зашифровано';
  return message.text.trim().isEmpty ? 'Сообщение' : message.text.trim();
}

String chatSubtitle(Chat chat) {
  return switch (chat.type) {
    ChatType.direct => 'личный чат',
    ChatType.group => '${chat.participants.length} участников',
    ChatType.channel => 'канал',
  };
}

Uint8List? bytesFromDataUrl(String dataUrl) {
  const marker = 'base64,';
  final index = dataUrl.indexOf(marker);
  if (index == -1) return null;
  try {
    return base64Decode(dataUrl.substring(index + marker.length));
  } on Object {
    return null;
  }
}

String? resolveMediaUrl(String? value, String baseUrl) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty || raw.startsWith('data:')) return raw;
  final uri = Uri.tryParse(raw);
  if (uri == null || uri.hasScheme) return raw;
  return Uri.parse(baseUrl).resolve(raw).toString();
}
