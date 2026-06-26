import 'package:socket_io_client/socket_io_client.dart' as socket_io;

import '../models.dart';

/// Обёртка над Socket.IO-клиентом BrenksChat.
///
/// События и их формат совпадают с веб- и desktop-клиентами,
/// сервер не требует никаких изменений.
class BrenksSocket {
  BrenksSocket({
    required this.baseUrl,
    required this.token,
  });

  final String baseUrl;
  final String token;
  socket_io.Socket? _socket;

  bool get isConnected => _socket?.connected ?? false;

  void connect({
    required void Function(bool connected) onConnectionChanged,
    required void Function(Message message) onMessage,
    required void Function(Chat chat) onChatUpdated,
    required void Function(String chatId, String messageId) onMessageDeleted,
    required void Function(Message message) onMessageEdited,
    required void Function(String chatId) onChatDeleted,
    required void Function(String chatId) onMessagesCleared,
    required void Function(List<String> userIds) onPresence,
    required void Function({
      required String chatId,
      required String userId,
      required String username,
      required bool isTyping,
    }) onTyping,
    required void Function(Map<String, dynamic> payload) onCallSignal,
  }) {
    final socket = socket_io.io(
      baseUrl,
      socket_io.OptionBuilder()
          .setPath('/socket.io')
          .setTransports(['websocket', 'polling'])
          .setAuth({'token': token})
          .enableReconnection()
          .enableAutoConnect()
          .build(),
    );

    socket.onConnect((_) => onConnectionChanged(true));
    socket.onReconnect((_) => onConnectionChanged(true));
    socket.onDisconnect((_) => onConnectionChanged(false));
    socket.onConnectError((_) => onConnectionChanged(false));

    socket.on('message', (payload) {
      if (payload is! Map || payload['message'] is! Map) return;
      onMessage(
        Message.fromJson((payload['message'] as Map).cast<String, dynamic>()),
      );
    });

    socket.on('chat_updated', (payload) {
      if (payload is! Map || payload['chat'] is! Map) return;
      onChatUpdated(
        Chat.fromJson((payload['chat'] as Map).cast<String, dynamic>()),
      );
    });

    socket.on('message_deleted', (payload) {
      if (payload is! Map) return;
      onMessageDeleted(
        payload['chatId']?.toString() ?? '',
        payload['messageId']?.toString() ?? '',
      );
    });

    socket.on('message_edited', (payload) {
      if (payload is! Map || payload['message'] is! Map) return;
      onMessageEdited(
        Message.fromJson((payload['message'] as Map).cast<String, dynamic>()),
      );
    });

    socket.on('chat_deleted', (payload) {
      if (payload is! Map) return;
      onChatDeleted(payload['chatId']?.toString() ?? '');
    });

    socket.on('messages_cleared', (payload) {
      if (payload is! Map) return;
      onMessagesCleared(payload['chatId']?.toString() ?? '');
    });

    socket.on('presence', (payload) {
      if (payload is! Map || payload['onlineUserIds'] is! List) return;
      onPresence(
        (payload['onlineUserIds'] as List)
            .map((item) => item.toString())
            .toList(growable: false),
      );
    });

    socket.on('typing', (payload) {
      if (payload is! Map) return;
      onTyping(
        chatId: payload['chatId']?.toString() ?? '',
        userId: payload['userId']?.toString() ?? '',
        username: payload['username']?.toString() ?? '...',
        isTyping: payload['isTyping'] == true,
      );
    });

    socket.on('call_signal', (payload) {
      if (payload is! Map) return;
      onCallSignal(payload.cast<String, dynamic>());
    });

    _socket = socket;
  }

  void joinChat(String chatId) {
    _socket?.emit('join_chat', chatId);
  }

  void sendMessage({
    required String chatId,
    String? text,
    MessageMedia? media,
    String? replyToMessageId,
  }) {
    _socket?.emit('send_message', {
      'chatId': chatId,
      'text': text ?? '',
      if (media != null) 'media': media.toJson(),
      if (replyToMessageId != null) 'replyToMessageId': replyToMessageId,
    });
  }

  void editMessage({
    required String chatId,
    required String messageId,
    required String text,
  }) {
    _socket?.emit('edit_message', {
      'chatId': chatId,
      'messageId': messageId,
      'text': text,
    });
  }

  void deleteMessage({
    required String chatId,
    required String messageId,
  }) {
    _socket?.emit('delete_message', {
      'chatId': chatId,
      'messageId': messageId,
    });
  }

  void toggleReaction({
    required String chatId,
    required String messageId,
    required String emoji,
  }) {
    _socket?.emit('toggle_reaction', {
      'chatId': chatId,
      'messageId': messageId,
      'emoji': emoji,
    });
  }

  void typing({
    required String chatId,
    required bool isTyping,
  }) {
    _socket?.emit('typing', {
      'chatId': chatId,
      'isTyping': isTyping,
    });
  }

  void markRead(String chatId) {
    _socket?.emit('mark_read', chatId);
  }

  void sendCallSignal(Map<String, dynamic> data) {
    _socket?.emit('call_signal', data);
  }

  void dispose() {
    _socket?.dispose();
    _socket = null;
  }
}
