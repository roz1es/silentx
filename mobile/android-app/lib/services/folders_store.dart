import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Тип наполнения папки:
/// - manual — выбранные вручную чаты (chatIds);
/// - direct — все личные чаты (автоматически);
/// - groups — все группы/каналы/беседы (автоматически).
class FolderFilter {
  static const manual = 'manual';
  static const direct = 'direct';
  static const groups = 'groups';
}

/// Папка чатов. Хранится локально на устройстве.
class ChatFolder {
  ChatFolder({
    required this.id,
    required this.name,
    required this.chatIds,
    this.filterType = FolderFilter.manual,
  });

  final String id;
  String name;
  List<String> chatIds;
  String filterType;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'chatIds': chatIds,
        'filterType': filterType,
      };

  factory ChatFolder.fromJson(Map<String, dynamic> json) => ChatFolder(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        chatIds: (json['chatIds'] as List?)
                ?.map((e) => e.toString())
                .toList(growable: true) ??
            <String>[],
        filterType: json['filterType']?.toString() ?? FolderFilter.manual,
      );
}

/// Загрузка/сохранение папок в SharedPreferences.
class FoldersStore {
  static const _key = 'chat_folders_v1';

  static Future<List<ChatFolder>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      final folders = list
          .whereType<Map>()
          .map((m) => ChatFolder.fromJson(m.cast<String, dynamic>()))
          .toList();
      // Миграция: старое название папки → короткое «Группы».
      for (final f in folders) {
        if (f.name == 'Группы, беседы и боты') f.name = 'Группы';
      }
      return folders;
    } on Object {
      return [];
    }
  }

  static Future<void> save(List<ChatFolder> folders) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(folders.map((f) => f.toJson()).toList()),
    );
  }
}
