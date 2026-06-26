import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';

class LocalCacheService {
  const LocalCacheService({required this.userId});

  static const _maxChats = 120;
  static const _maxMessagesPerChat = 120;

  final String userId;

  String get _chatKey => 'brenkschat.cache.$userId.chats';

  String _messagesKey(String chatId) =>
      'brenkschat.cache.$userId.messages.$chatId';

  Future<List<Chat>> loadChats() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_chatKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => Chat.fromJson(item.cast<String, dynamic>()))
          .toList(growable: false);
    } on Object {
      return const [];
    }
  }

  Future<void> saveChats(List<Chat> chats) async {
    final prefs = await SharedPreferences.getInstance();
    final bounded = chats.take(_maxChats).map((chat) => chat.toJson()).toList();
    await prefs.setString(_chatKey, jsonEncode(bounded));
  }

  Future<List<Message>> loadMessages(String chatId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_messagesKey(chatId));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => Message.fromJson(item.cast<String, dynamic>()))
          .toList(growable: false);
    } on Object {
      return const [];
    }
  }

  Future<void> saveMessages(String chatId, List<Message> messages) async {
    final prefs = await SharedPreferences.getInstance();
    final bounded = messages.length > _maxMessagesPerChat
        ? messages.sublist(messages.length - _maxMessagesPerChat)
        : messages;
    await prefs.setString(
      _messagesKey(chatId),
      jsonEncode(bounded.map((message) => message.toJson()).toList()),
    );
  }

  Future<void> upsertMessage(Message message) async {
    final current = await loadMessages(message.chatId);
    final index = current.indexWhere((item) => item.id == message.id);
    final next = [...current];
    if (index == -1) {
      next.add(message);
    } else {
      next[index] = message;
    }
    next.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    await saveMessages(message.chatId, next);
  }

  Future<void> removeMessage({
    required String chatId,
    required String messageId,
  }) async {
    final current = await loadMessages(chatId);
    await saveMessages(
      chatId,
      current.where((item) => item.id != messageId).toList(growable: false),
    );
  }

  Future<void> clearMessages(String chatId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_messagesKey(chatId));
  }
}
