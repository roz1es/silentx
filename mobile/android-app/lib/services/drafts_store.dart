import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Черновики сообщений по чатам. Кеш в памяти — плитки списка читают
/// синхронно; persist в SharedPreferences переживает перезапуск.
class DraftsStore extends ChangeNotifier {
  DraftsStore._();
  static final DraftsStore instance = DraftsStore._();

  static const _prefix = 'draft_';
  final Map<String, String> _cache = {};

  /// Загружается один раз в main() до runApp.
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    for (final key in p.getKeys()) {
      if (!key.startsWith(_prefix)) continue;
      final value = p.getString(key);
      if (value != null && value.trim().isNotEmpty) {
        _cache[key.substring(_prefix.length)] = value;
      }
    }
  }

  String? draftFor(String chatId) => _cache[chatId];

  Future<void> save(String chatId, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      if (_cache.remove(chatId) == null) return;
    } else {
      if (_cache[chatId] == text) return;
      _cache[chatId] = text;
    }
    // Уведомляем слушателей (список чатов) вне текущей фазы — save зовётся
    // из dispose экрана чата.
    Future.microtask(notifyListeners);
    final p = await SharedPreferences.getInstance();
    if (trimmed.isEmpty) {
      await p.remove('$_prefix$chatId');
    } else {
      await p.setString('$_prefix$chatId', text);
    }
  }
}
