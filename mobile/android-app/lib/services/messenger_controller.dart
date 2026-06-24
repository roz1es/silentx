import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models.dart';
import 'api_client.dart';
import 'socket_service.dart';

/// Единый источник состояния мессенджера для всех экранов.
///
/// Держит постоянное Socket.IO-соединение, список чатов, онлайн-статусы и
/// сообщения активного чата. Экраны слушают контроллер через [AnimatedBuilder]
/// / [ListenableBuilder], поэтому переход «список → чат» не разрывает сокет.
class MessengerController extends ChangeNotifier {
  MessengerController({
    required this.api,
    required this.currentUser,
    required this.serverUrl,
    required this.token,
  });

  final ApiClient api;
  final User currentUser;
  final String serverUrl;
  final String token;

  BrenksSocket? _socket;

  List<Chat> _chats = const [];
  Set<String> _onlineUserIds = const {};
  bool _socketConnected = false;
  bool _loadingChats = true;
  String? _chatsError;

  String? _activeChatId;
  List<Message> _messages = const [];
  Map<String, String> _typingNames = const {};
  bool _loadingMessages = false;
  String? _messagesError;

  /// Увеличивается каждый раз, когда в активный чат приходит новое сообщение —
  /// экран переписки использует это, чтобы прокрутиться вниз.
  int _incomingMessageTick = 0;

  // --- Геттеры ---

  List<Chat> get chats => _chats;
  Set<String> get onlineUserIds => _onlineUserIds;
  bool get socketConnected => _socketConnected;
  bool get loadingChats => _loadingChats;
  String? get chatsError => _chatsError;

  String? get activeChatId => _activeChatId;
  List<Message> get messages => _messages;
  List<String> get typingNames => _typingNames.values.toList(growable: false);
  bool get loadingMessages => _loadingMessages;
  String? get messagesError => _messagesError;
  int get incomingMessageTick => _incomingMessageTick;

  Chat? get activeChat {
    for (final chat in _chats) {
      if (chat.id == _activeChatId) return chat;
    }
    return null;
  }

  Chat? chatById(String id) {
    for (final chat in _chats) {
      if (chat.id == id) return chat;
    }
    return null;
  }

  Message? get pinnedMessage {
    final pinnedId = activeChat?.pinnedMessageId;
    if (pinnedId == null) return null;
    for (final message in _messages) {
      if (message.id == pinnedId && !message.deleted) return message;
    }
    return null;
  }

  int unreadFor(Chat chat) => chat.unread[currentUser.id] ?? 0;

  bool isPeerOnline(Chat chat) {
    return chat.type == ChatType.direct &&
        chat.participantIds.any(
          (id) => id != currentUser.id && _onlineUserIds.contains(id),
        );
  }

  // --- Жизненный цикл ---

  void start() {
    _connectSocket();
    unawaited(loadChats());
  }

  void reconnect() {
    _socket?.dispose();
    _socket = null;
    _socketConnected = false;
    notifyListeners();
    _connectSocket();
  }

  void _connectSocket() {
    final socket = BrenksSocket(baseUrl: serverUrl, token: token);
    socket.connect(
      onConnectionChanged: (connected) {
        _socketConnected = connected;
        if (connected) _joinAllChats();
        notifyListeners();
      },
      onMessage: (message) {
        _upsertLastMessageHint(message);
        if (message.chatId == _activeChatId) {
          if (!_messages.any((item) => item.id == message.id)) {
            _messages = [..._messages, message];
            _incomingMessageTick++;
          }
          _socket?.markRead(message.chatId);
        }
        notifyListeners();
      },
      onChatUpdated: (chat) {
        _upsertChat(chat);
        notifyListeners();
      },
      onMessageDeleted: (chatId, messageId) {
        if (chatId != _activeChatId) return;
        _messages = _messages
            .map((m) => m.id == messageId ? m.copyWith(deleted: true) : m)
            .toList(growable: false);
        notifyListeners();
      },
      onMessageEdited: (message) {
        if (message.chatId != _activeChatId) return;
        _messages = _messages
            .map((item) => item.id == message.id ? message : item)
            .toList(growable: false);
        notifyListeners();
      },
      onChatDeleted: (chatId) {
        _chats = _chats.where((chat) => chat.id != chatId).toList();
        if (_activeChatId == chatId) {
          _activeChatId = null;
          _messages = const [];
        }
        notifyListeners();
      },
      onMessagesCleared: (chatId) {
        if (chatId == _activeChatId) _messages = const [];
        notifyListeners();
      },
      onPresence: (userIds) {
        _onlineUserIds = userIds.toSet();
        notifyListeners();
      },
      onTyping: ({
        required chatId,
        required userId,
        required username,
        required isTyping,
      }) {
        if (chatId != _activeChatId || userId == currentUser.id) return;
        final next = {..._typingNames};
        if (isTyping) {
          next[userId] = username;
        } else {
          next.remove(userId);
        }
        _typingNames = next;
        notifyListeners();
      },
    );
    _socket = socket;
  }

  Future<void> loadChats() async {
    _loadingChats = true;
    _chatsError = null;
    notifyListeners();
    try {
      final chats = _sortChats(await api.fetchChats());
      _chats = chats;
      _loadingChats = false;
      _joinAllChats();
      notifyListeners();
    } on Object catch (err) {
      _chatsError = err.toString();
      _loadingChats = false;
      notifyListeners();
    }
  }

  void _joinAllChats() {
    final socket = _socket;
    if (socket == null) return;
    for (final chat in _chats) {
      socket.joinChat(chat.id);
    }
  }

  void _upsertChat(Chat chat) {
    final index = _chats.indexWhere((item) => item.id == chat.id);
    if (index == -1) {
      _chats = _sortChats([..._chats, chat]);
      return;
    }
    final next = [..._chats];
    next[index] = chat;
    _chats = _sortChats(next);
  }

  /// На случай, если сервер не пришлёт chat_updated сразу — поднимаем чат вверх.
  void _upsertLastMessageHint(Message message) {
    final index = _chats.indexWhere((item) => item.id == message.chatId);
    if (index == -1) return;
    final chat = _chats[index];
    if ((chat.lastMessage?.time ?? 0) >= message.createdAt) return;
    final updated = Chat(
      id: chat.id,
      type: chat.type,
      name: chat.name,
      displayName: chat.displayName,
      avatarUrl: chat.avatarUrl,
      participantIds: chat.participantIds,
      participants: chat.participants,
      lastMessage: LastMessage(
        text: message.text,
        time: message.createdAt,
        senderId: message.senderId,
      ),
      unread: chat.unread,
      pinnedMessageId: chat.pinnedMessageId,
      muted: chat.muted,
      pinnedToTop: chat.pinnedToTop,
    );
    final next = [..._chats];
    next[index] = updated;
    _chats = _sortChats(next);
  }

  // --- Активный чат ---

  Future<void> openChat(String chatId) async {
    _activeChatId = chatId;
    _messages = const [];
    _typingNames = const {};
    _loadingMessages = true;
    _messagesError = null;
    notifyListeners();

    _socket?.joinChat(chatId);
    _socket?.markRead(chatId);
    try {
      final messages = await api.fetchMessages(chatId);
      if (_activeChatId != chatId) return;
      _messages = messages;
      _loadingMessages = false;
      _incomingMessageTick++;
      notifyListeners();
    } on Object catch (err) {
      if (_activeChatId != chatId) return;
      _messagesError = err.toString();
      _loadingMessages = false;
      notifyListeners();
    }
  }

  /// Сбрасывает активный чат. Намеренно без notifyListeners: вызывается из
  /// [State.dispose] экрана переписки, где синхронное уведомление других
  /// слушателей (списка чатов) во время фазы построения недопустимо.
  void closeActiveChat() {
    _activeChatId = null;
    _messages = const [];
    _typingNames = const {};
  }

  // --- Действия с сообщениями ---

  void sendMessage({
    String? text,
    MessageMedia? media,
    String? replyToMessageId,
  }) {
    final chatId = _activeChatId;
    if (chatId == null) return;
    _socket?.sendMessage(
      chatId: chatId,
      text: text ?? '',
      media: media,
      replyToMessageId: replyToMessageId,
    );
  }

  void editMessage(String messageId, String text) {
    final chatId = _activeChatId;
    if (chatId == null) return;
    _socket?.editMessage(chatId: chatId, messageId: messageId, text: text);
  }

  void deleteMessage(String messageId) {
    final chatId = _activeChatId;
    if (chatId == null) return;
    _socket?.deleteMessage(chatId: chatId, messageId: messageId);
  }

  void toggleReaction(String messageId, String emoji) {
    final chatId = _activeChatId;
    if (chatId == null) return;
    _socket?.toggleReaction(
      chatId: chatId,
      messageId: messageId,
      emoji: emoji,
    );
  }

  Timer? _typingTimer;

  void notifyTyping(bool isTyping) {
    final chatId = _activeChatId;
    if (chatId == null) return;
    _socket?.typing(chatId: chatId, isTyping: isTyping);
    _typingTimer?.cancel();
    if (isTyping) {
      _typingTimer = Timer(const Duration(seconds: 2), () {
        _socket?.typing(chatId: chatId, isTyping: false);
      });
    }
  }

  // --- Действия с чатами ---

  Future<void> setPinnedMessage(String? messageId) async {
    final chatId = _activeChatId;
    if (chatId == null) return;
    await api.setPinnedMessage(chatId: chatId, messageId: messageId);
    await loadChats();
  }

  Future<void> toggleMute(Chat chat) async {
    await api.setChatMuted(chatId: chat.id, muted: !chat.muted);
    await loadChats();
  }

  Future<void> togglePinTop(Chat chat) async {
    await api.setChatPinnedTop(chatId: chat.id, pinned: !chat.pinnedToTop);
    await loadChats();
  }

  Future<void> clearChat(Chat chat) async {
    await api.clearChat(chat.id);
    if (chat.id == _activeChatId) {
      _messages = const [];
      notifyListeners();
    }
  }

  Future<void> deleteChat(Chat chat) async {
    await api.deleteChat(chat.id);
    _chats = _chats.where((item) => item.id != chat.id).toList();
    if (_activeChatId == chat.id) {
      _activeChatId = null;
      _messages = const [];
    }
    notifyListeners();
  }

  Future<Chat> createDirectChat(String targetUserId) async {
    final chat = await api.createDirectChat(targetUserId: targetUserId);
    await loadChats();
    return chat;
  }

  Future<Chat> createGroupChat(String name, List<String> memberIds) async {
    final chat = await api.createGroupChat(name: name, memberIds: memberIds);
    await loadChats();
    return chat;
  }

  Future<Chat> createChannelChat(String name, List<String> subscriberIds) async {
    final chat =
        await api.createChannelChat(name: name, subscriberIds: subscriberIds);
    await loadChats();
    return chat;
  }

  List<Chat> _sortChats(List<Chat> chats) {
    final next = [...chats];
    next.sort((a, b) {
      if (a.pinnedToTop != b.pinnedToTop) return a.pinnedToTop ? -1 : 1;
      return (b.lastMessage?.time ?? 0).compareTo(a.lastMessage?.time ?? 0);
    });
    return next;
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _socket?.dispose();
    super.dispose();
  }
}
