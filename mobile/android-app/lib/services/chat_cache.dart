import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';

/// Локальный кеш списка чатов (с последним сообщением каждого) — чтобы при
/// запуске не было пустого экрана. Хранится в SharedPreferences.
class ChatCache {
  static const _chatsKey = 'cache_chats_v1';

  static Future<void> saveChats(List<Chat> chats) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _chatsKey,
        jsonEncode(chats.map((c) => c.toJson()).toList()),
      );
    } on Object {
      // кеш не критичен
    }
  }

  static Future<List<Chat>> loadChats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_chatsKey);
      if (raw == null || raw.isEmpty) return const [];
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map>()
          .map((m) => Chat.fromJson(m.cast<String, dynamic>()))
          .toList();
    } on Object {
      return const [];
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_chatsKey);
    } on Object {
      // noop
    }
  }
}
