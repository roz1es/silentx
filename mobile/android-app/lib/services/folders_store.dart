import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Папка чатов: имя + набор id чатов. Хранится локально на устройстве.
class ChatFolder {
  ChatFolder({
    required this.id,
    required this.name,
    required this.chatIds,
  });

  final String id;
  String name;
  List<String> chatIds;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'chatIds': chatIds,
      };

  factory ChatFolder.fromJson(Map<String, dynamic> json) => ChatFolder(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        chatIds: (json['chatIds'] as List?)
                ?.map((e) => e.toString())
                .toList(growable: true) ??
            <String>[],
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
      return list
          .whereType<Map>()
          .map((m) => ChatFolder.fromJson(m.cast<String, dynamic>()))
          .toList();
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
