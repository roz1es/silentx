import 'package:socket_io_client/socket_io_client.dart' as socket_io;

import '../models.dart';

class BrenksSocket {
  BrenksSocket({
    required this.baseUrl,
    required this.token,
  });

  final String baseUrl;
  final String token;
  socket_io.Socket? _socket;

  void connect({
    required void Function(bool connected) onConnectionChanged,
    required void Function(Message message) onMessage,
    required void Function(Chat chat) onChatUpdated,
    required void Function(String chatId, String messageId) onMessageDeleted,
    required void Function(Message message) onMessageEdited,
    required void Function(String chatId) onChatDeleted,
    required void Function(String chatId) onMessagesCleared,
    required void Function(List<String> userIds) onPresence,
    required void Function(Map<String, dynamic> signal) onCallSignal,
    void Function(UserReport report)? onAdminReportCreated,
    void Function(UserReport report)? onAdminReportUpdated,
    required void Function(String message) onSocketError,
    required void Function({
      required String chatId,
      required String userId,
      required String username,
      required String activity,
      required bool isTyping,
    }) onTyping,
  }) {
    final socket = socket_io.io(
      baseUrl,
      socket_io.OptionBuilder()
          .setPath('/socket.io')
          .setTransports(['websocket', 'polling'])
          .setAuth({'token': token})
          .enableAutoConnect()
          .build(),
    );

    socket.onConnect((_) => onConnectionChanged(true));
    socket.onDisconnect((_) => onConnectionChanged(false));
    socket.onConnectError((error) {
      onConnectionChanged(false);
      final message = error?.toString() ?? '';
      if (message.contains('UNAUTHORIZED')) {
        onSocketError('Сессия истекла. Войдите в аккаунт заново.');
      }
    });

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
        activity: payload['activity']?.toString() ?? 'text',
        isTyping: payload['isTyping'] == true,
      );
    });

    socket.on('call_signal', (payload) {
      if (payload is! Map) return;
      onCallSignal(payload.cast<String, dynamic>());
    });

    socket.on('admin_report_created', (payload) {
      if (payload is! Map || payload['report'] is! Map) return;
      onAdminReportCreated?.call(
        UserReport.fromJson((payload['report'] as Map).cast<String, dynamic>()),
      );
    });

    socket.on('admin_report_updated', (payload) {
      if (payload is! Map || payload['report'] is! Map) return;
      onAdminReportUpdated?.call(
        UserReport.fromJson((payload['report'] as Map).cast<String, dynamic>()),
      );
    });

    _socket = socket;
  }

  void joinChat(String chatId) {
    _socket?.emit('join_chat', chatId);
  }

  void sendTextMessage({
    required String chatId,
    required String text,
  }) {
    _socket?.emit('send_message', {
      'chatId': chatId,
      'text': text,
    });
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

  void forwardMessages({
    required String sourceChatId,
    required String targetChatId,
    required List<String> messageIds,
  }) {
    _socket?.emit('forward_messages', {
      'sourceChatId': sourceChatId,
      'targetChatId': targetChatId,
      'messageIds': messageIds,
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
    String activity = 'text',
  }) {
    _socket?.emit('typing', {
      'chatId': chatId,
      'isTyping': isTyping,
      'activity': activity,
    });
  }

  void markRead(String chatId) {
    _socket?.emit('mark_read', chatId);
  }

  void sendCallSignal({
    required String toUserId,
    required String kind,
    String? callId,
    String? callType,
    String? sdp,
    Map<String, dynamic>? candidate,
  }) {
    _socket?.emit('call_signal', {
      'toUserId': toUserId,
      'kind': kind,
      if (callId != null) 'callId': callId,
      if (callType != null) 'callType': callType,
      if (sdp != null) 'sdp': sdp,
      if (candidate != null) 'candidate': candidate,
    });
  }

  void dispose() {
    _socket?.dispose();
    _socket = null;
  }
}
