import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mime/mime.dart';

import '../models.dart';
import '../services/api_client.dart';
import '../services/audio_message_service.dart';
import '../services/socket_service.dart';
import '../theme/app_theme.dart';
import '../widgets/brenks_avatar.dart';
import '../widgets/empty_state.dart';

const _quickReactions = ['👍', '❤️', '😂', '🔥', '😮'];
const _maxMediaDataUrlLength = 14 * 1000 * 1000;

class MessengerScreen extends StatefulWidget {
  const MessengerScreen({
    super.key,
    required this.user,
    required this.api,
    required this.serverUrl,
    required this.token,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.onLogout,
  });

  final User user;
  final ApiClient api;
  final String serverUrl;
  final String token;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final VoidCallback onLogout;

  @override
  State<MessengerScreen> createState() => _MessengerScreenState();
}

class _MessengerScreenState extends State<MessengerScreen> {
  final _messageController = TextEditingController();
  final _messageScrollController = ScrollController();
  final _chatSearchController = TextEditingController();
  final _audioService = AudioMessageService();

  BrenksSocket? _socket;
  List<Chat> _chats = const [];
  List<Message> _messages = const [];
  Set<String> _onlineUserIds = const {};
  Map<String, String> _typingNames = const {};
  String? _activeChatId;
  Message? _replyTo;
  Message? _editing;
  bool _loadingChats = true;
  bool _loadingMessages = false;
  bool _socketConnected = false;
  bool _sendingMedia = false;
  bool _recordingVoice = false;
  int _recordingMs = 0;
  String? _error;
  Timer? _typingTimer;
  Timer? _recordingTimer;

  Chat? get _activeChat {
    for (final chat in _chats) {
      if (chat.id == _activeChatId) return chat;
    }
    return null;
  }

  Message? get _pinnedMessage {
    final pinnedId = _activeChat?.pinnedMessageId;
    if (pinnedId == null) return null;
    for (final message in _messages) {
      if (message.id == pinnedId && !message.deleted) return message;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadChats();
    _connectSocket();
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _recordingTimer?.cancel();
    _socket?.dispose();
    unawaited(_audioService.dispose());
    _messageController.dispose();
    _messageScrollController.dispose();
    _chatSearchController.dispose();
    super.dispose();
  }

  void _connectSocket() {
    final socket = BrenksSocket(
      baseUrl: widget.serverUrl,
      token: widget.token,
    );
    socket.connect(
      onConnectionChanged: (connected) {
        if (!mounted) return;
        setState(() => _socketConnected = connected);
        if (connected) _joinAllChats();
      },
      onMessage: (message) {
        if (!mounted) return;
        if (message.chatId == _activeChatId) {
          setState(() {
            if (!_messages.any((item) => item.id == message.id)) {
              _messages = [..._messages, message];
            }
          });
          _socket?.markRead(message.chatId);
          _scrollToBottom();
        }
      },
      onChatUpdated: (chat) {
        if (!mounted) return;
        setState(() => _upsertChat(chat));
      },
      onMessageDeleted: (chatId, messageId) {
        if (!mounted || chatId != _activeChatId) return;
        setState(() {
          _messages = _messages
              .map(
                (message) => message.id == messageId
                    ? Message(
                        id: message.id,
                        chatId: message.chatId,
                        senderId: message.senderId,
                        text: message.text,
                        createdAt: message.createdAt,
                        imageUrl: message.imageUrl,
                        media: message.media,
                        deleted: true,
                        editedAt: message.editedAt,
                        replyToMessageId: message.replyToMessageId,
                        reactions: message.reactions,
                      )
                    : message,
              )
              .toList(growable: false);
        });
      },
      onMessageEdited: (message) {
        if (!mounted || message.chatId != _activeChatId) return;
        setState(() {
          _messages = _messages
              .map((item) => item.id == message.id ? message : item)
              .toList(growable: false);
        });
      },
      onChatDeleted: (chatId) {
        if (!mounted) return;
        setState(() {
          _chats = _chats.where((chat) => chat.id != chatId).toList();
          if (_activeChatId == chatId) {
            _activeChatId = null;
            _messages = const [];
          }
        });
      },
      onMessagesCleared: (chatId) {
        if (!mounted || chatId != _activeChatId) return;
        setState(() => _messages = const []);
      },
      onPresence: (userIds) {
        if (!mounted) return;
        setState(() => _onlineUserIds = userIds.toSet());
      },
      onTyping: ({
        required chatId,
        required userId,
        required username,
        required isTyping,
      }) {
        if (!mounted || chatId != _activeChatId || userId == widget.user.id) {
          return;
        }
        setState(() {
          final next = {..._typingNames};
          if (isTyping) {
            next[userId] = username;
          } else {
            next.remove(userId);
          }
          _typingNames = next;
        });
      },
    );
    _socket = socket;
  }

  Future<void> _loadChats() async {
    setState(() {
      _loadingChats = true;
      _error = null;
    });
    try {
      final chats = _sortChats(await widget.api.fetchChats());
      if (!mounted) return;
      setState(() {
        _chats = chats;
        _loadingChats = false;
      });
      _joinAllChats();
      if (chats.isNotEmpty && _activeChatId == null) {
        await _selectChat(chats.first.id);
      }
    } on Object catch (err) {
      if (!mounted) return;
      setState(() {
        _error = err.toString();
        _loadingChats = false;
      });
    }
  }

  Future<void> _selectChat(String chatId) async {
    setState(() {
      _activeChatId = chatId;
      _messages = const [];
      _typingNames = const {};
      _replyTo = null;
      _editing = null;
      _loadingMessages = true;
      _error = null;
    });
    _socket?.joinChat(chatId);
    _socket?.markRead(chatId);
    try {
      final messages = await widget.api.fetchMessages(chatId);
      if (!mounted || _activeChatId != chatId) return;
      setState(() {
        _messages = messages;
        _loadingMessages = false;
      });
      _scrollToBottom(instant: true);
    } on Object catch (err) {
      if (!mounted) return;
      setState(() {
        _error = err.toString();
        _loadingMessages = false;
      });
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

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    final chatId = _activeChatId;
    if (chatId == null) return;

    final editing = _editing;
    if (editing != null) {
      if (text.isEmpty) return;
      _socket?.editMessage(chatId: chatId, messageId: editing.id, text: text);
      setState(() => _editing = null);
      _messageController.clear();
      return;
    }

    if (text.isEmpty) return;
    _socket?.sendMessage(
      chatId: chatId,
      text: text,
      replyToMessageId: _replyTo?.id,
    );
    setState(() => _replyTo = null);
    _messageController.clear();
    _notifyTyping(false);
  }

  Future<void> _pickAndSendAttachment() async {
    final chatId = _activeChatId;
    if (chatId == null) return;
    final result = await FilePicker.pickFiles(
      type: FileType.any,
      withData: true,
    );
    final file = result?.files.single;
    if (file == null) return;

    setState(() => _sendingMedia = true);
    try {
      final bytes = file.bytes ??
          (file.path == null ? null : await io.File(file.path!).readAsBytes());
      if (bytes == null || bytes.isEmpty) return;
      final mimeType =
          lookupMimeType(file.name, headerBytes: bytes.take(16).toList()) ??
              'application/octet-stream';
      final dataUrl = 'data:$mimeType;base64,${base64Encode(bytes)}';
      if (dataUrl.length > _maxMediaDataUrlLength) {
        _showSnack('Файл слишком большой для текущего сервера.');
        return;
      }
      final media = MessageMedia(
        kind: mimeType.startsWith('image/') ? 'image' : 'file',
        dataUrl: dataUrl,
        fileName: file.name,
        mimeType: mimeType,
      );
      _socket?.sendMessage(
        chatId: chatId,
        text: _messageController.text.trim(),
        media: media,
        replyToMessageId: _replyTo?.id,
      );
      setState(() => _replyTo = null);
      _messageController.clear();
    } on Object catch (err) {
      _showSnack('Не удалось отправить файл: $err');
    } finally {
      if (mounted) setState(() => _sendingMedia = false);
    }
  }

  Future<void> _startVoiceRecording() async {
    final chatId = _activeChatId;
    if (chatId == null || _recordingVoice) return;
    try {
      await _audioService.startRecording();
      setState(() {
        _recordingVoice = true;
        _recordingMs = 0;
        _editing = null;
        _replyTo = null;
      });
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted) return;
        setState(() => _recordingMs += 250);
      });
    } on Object catch (err) {
      _showSnack('Не удалось начать запись: $err');
    }
  }

  Future<void> _finishVoiceRecording() async {
    final chatId = _activeChatId;
    if (chatId == null || !_recordingVoice) return;
    _recordingTimer?.cancel();
    setState(() => _recordingVoice = false);
    try {
      final recording = await _audioService.stopRecording();
      if (recording == null || recording.durationMs < 500) {
        _showSnack('Голосовое слишком короткое.');
        return;
      }
      if (recording.media.dataUrl.length > _maxMediaDataUrlLength) {
        _showSnack('Голосовое получилось слишком большим.');
        return;
      }
      _socket?.sendMessage(
        chatId: chatId,
        text: '',
        media: recording.media,
      );
    } on Object catch (err) {
      _showSnack('Не удалось отправить голосовое: $err');
    }
  }

  Future<void> _cancelVoiceRecording() async {
    if (!_recordingVoice) return;
    _recordingTimer?.cancel();
    setState(() {
      _recordingVoice = false;
      _recordingMs = 0;
    });
    await _audioService.cancelRecording();
  }

  Future<void> _playVoice(MessageMedia media) async {
    try {
      await _audioService.playDataUrl(media.dataUrl);
    } on Object catch (err) {
      _showSnack('Не удалось воспроизвести аудио: $err');
    }
  }

  void _startEdit(Message message) {
    if (message.deleted || message.senderId != widget.user.id) return;
    setState(() {
      _editing = message;
      _replyTo = null;
    });
    _messageController.text = message.text.trim();
    _messageController.selection = TextSelection.collapsed(
      offset: _messageController.text.length,
    );
  }

  void _cancelComposerMode() {
    final wasEditing = _editing != null;
    setState(() {
      _replyTo = null;
      _editing = null;
    });
    if (wasEditing) _messageController.clear();
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  void _notifyTyping(bool isTyping) {
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

  Future<void> _showNewChatDialog() async {
    try {
      final users = await widget.api.fetchUserDirectory();
      if (!mounted) return;
      final result = await showDialog<_NewChatResult>(
        context: context,
        builder: (_) => _NewChatDialog(
          serverUrl: widget.serverUrl,
          users: users.where((item) => item.id != widget.user.id).toList(),
        ),
      );
      if (result == null) return;

      late final Chat chat;
      if (result.type == ChatType.direct) {
        chat = await widget.api.createDirectChat(
          targetUserId: result.memberIds.first,
        );
      } else if (result.type == ChatType.group) {
        chat = await widget.api.createGroupChat(
          name: result.name,
          memberIds: result.memberIds,
        );
      } else {
        chat = await widget.api.createChannelChat(
          name: result.name,
          subscriberIds: result.memberIds,
        );
      }
      await _loadChats();
      await _selectChat(chat.id);
    } on Object catch (err) {
      _showSnack('Не удалось создать чат: $err');
    }
  }

  Future<void> _setPinnedMessage(Message? message) async {
    final chatId = _activeChatId;
    if (chatId == null) return;
    await widget.api.setPinnedMessage(
      chatId: chatId,
      messageId: message?.id,
    );
    await _loadChats();
  }

  Future<void> _toggleMute(Chat chat) async {
    await widget.api.setChatMuted(chatId: chat.id, muted: !chat.muted);
    await _loadChats();
  }

  Future<void> _togglePinTop(Chat chat) async {
    await widget.api
        .setChatPinnedTop(chatId: chat.id, pinned: !chat.pinnedToTop);
    await _loadChats();
  }

  Future<void> _clearChat(Chat chat) async {
    final ok = await _confirm('Очистить чат?', 'Все сообщения пропадут у вас.');
    if (!ok) return;
    await widget.api.clearChat(chat.id);
    if (chat.id == _activeChatId) setState(() => _messages = const []);
  }

  Future<void> _deleteChat(Chat chat) async {
    final ok = await _confirm('Удалить чат?', 'Чат будет удален из списка.');
    if (!ok) return;
    await widget.api.deleteChat(chat.id);
    setState(() {
      _chats = _chats.where((item) => item.id != chat.id).toList();
      if (_activeChatId == chat.id) {
        _activeChatId = null;
        _messages = const [];
      }
    });
  }

  Future<bool> _confirm(String title, String text) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Да'),
          ),
        ],
      ),
    );
    return result == true;
  }

  void _openChatProfile(Chat chat) {
    showDialog<void>(
      context: context,
      builder: (_) => _ChatProfileDialog(
        serverUrl: widget.serverUrl,
        chat: chat,
        onlineUserIds: _onlineUserIds,
      ),
    );
  }

  void _showAccountDialog() {
    showDialog<void>(
      context: context,
      builder: (_) => _AccountDialog(
        user: widget.user,
        serverUrl: widget.serverUrl,
        themeMode: widget.themeMode,
        onThemeModeChanged: widget.onThemeModeChanged,
        onLogout: widget.onLogout,
      ),
    );
  }

  void _scrollToBottom({bool instant = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_messageScrollController.hasClients) return;
      final target = _messageScrollController.position.maxScrollExtent;
      if (instant) {
        _messageScrollController.jumpTo(target);
        return;
      }
      _messageScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
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
  Widget build(BuildContext context) {
    final query = _chatSearchController.text.trim().toLowerCase();
    final visibleChats = query.isEmpty
        ? _chats
        : _chats
            .where((chat) => chat.title.toLowerCase().contains(query))
            .toList(growable: false);

    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 384,
            child: _Sidebar(
              user: widget.user,
              serverUrl: widget.serverUrl,
              chats: visibleChats,
              activeChatId: _activeChatId,
              loading: _loadingChats,
              connected: _socketConnected,
              onlineUserIds: _onlineUserIds,
              searchController: _chatSearchController,
              onSearchChanged: () => setState(() {}),
              onRefresh: _loadChats,
              onLogout: widget.onLogout,
              onNewChat: _showNewChatDialog,
              onOpenAccount: _showAccountDialog,
              onSelectChat: _selectChat,
            ),
          ),
          const VerticalDivider(width: 1, color: Color(0xFF323946)),
          Expanded(
            child: _ChatPane(
              chat: _activeChat,
              serverUrl: widget.serverUrl,
              user: widget.user,
              messages: _messages,
              pinnedMessage: _pinnedMessage,
              typingNames: _typingNames.values.toList(growable: false),
              loading: _loadingMessages,
              sendingMedia: _sendingMedia,
              recordingVoice: _recordingVoice,
              recordingMs: _recordingMs,
              error: _error,
              replyTo: _replyTo,
              editing: _editing,
              messageController: _messageController,
              scrollController: _messageScrollController,
              onSend: _sendMessage,
              onAttach: _pickAndSendAttachment,
              onStartVoice: _startVoiceRecording,
              onFinishVoice: _finishVoiceRecording,
              onCancelVoice: _cancelVoiceRecording,
              onCancelComposerMode: _cancelComposerMode,
              onTyping: _notifyTyping,
              onOpenProfile: _openChatProfile,
              onToggleMute: _toggleMute,
              onTogglePinTop: _togglePinTop,
              onClearChat: _clearChat,
              onDeleteChat: _deleteChat,
              onUnpinMessage: () => _setPinnedMessage(null),
              onReply: (message) => setState(() {
                _editing = null;
                _replyTo = message;
              }),
              onEdit: _startEdit,
              onDeleteMessage: (message) {
                final chatId = _activeChatId;
                if (chatId == null) return;
                _socket?.deleteMessage(chatId: chatId, messageId: message.id);
              },
              onPinMessage: _setPinnedMessage,
              onReaction: (message, emoji) {
                final chatId = _activeChatId;
                if (chatId == null) return;
                _socket?.toggleReaction(
                  chatId: chatId,
                  messageId: message.id,
                  emoji: emoji,
                );
              },
              onPlayVoice: _playVoice,
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.user,
    required this.serverUrl,
    required this.chats,
    required this.activeChatId,
    required this.loading,
    required this.connected,
    required this.onlineUserIds,
    required this.searchController,
    required this.onSearchChanged,
    required this.onRefresh,
    required this.onLogout,
    required this.onNewChat,
    required this.onOpenAccount,
    required this.onSelectChat,
  });

  final User user;
  final String serverUrl;
  final List<Chat> chats;
  final String? activeChatId;
  final bool loading;
  final bool connected;
  final Set<String> onlineUserIds;
  final TextEditingController searchController;
  final VoidCallback onSearchChanged;
  final VoidCallback onRefresh;
  final VoidCallback onLogout;
  final VoidCallback onNewChat;
  final VoidCallback onOpenAccount;
  final ValueChanged<String> onSelectChat;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF22262E),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 14, 16),
            child: Row(
              children: [
                InkWell(
                  onTap: onOpenAccount,
                  customBorder: const CircleBorder(),
                  child: BrenksAvatar(
                    title: user.title,
                    imageUrl: user.avatarUrl,
                    baseUrl: serverUrl,
                    size: 58,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        onTap: onOpenAccount,
                        borderRadius: BorderRadius.circular(10),
                        child: Text(
                          user.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: connected ? accent : muted,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 7),
                          Text(
                            connected ? 'онлайн' : 'подключение...',
                            style: const TextStyle(color: muted),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Новый чат',
                  onPressed: onNewChat,
                  icon: const Icon(Icons.add_comment_rounded),
                ),
                IconButton(
                  tooltip: 'Профиль и настройки',
                  onPressed: onOpenAccount,
                  icon: const Icon(Icons.tune_rounded),
                ),
                IconButton(
                  tooltip: 'Обновить',
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh_rounded),
                ),
                IconButton(
                  tooltip: 'Выйти',
                  onPressed: onLogout,
                  icon: const Icon(Icons.logout_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
            child: TextField(
              controller: searchController,
              onChanged: (_) => onSearchChanged(),
              decoration: const InputDecoration(
                hintText: 'Поиск чатов...',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : chats.isEmpty
                    ? const EmptyState(
                        title: 'Чатов пока нет',
                        subtitle: 'Создайте новый чат кнопкой сверху.',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                        itemBuilder: (context, index) {
                          final chat = chats[index];
                          return _ChatTile(
                            chat: chat,
                            serverUrl: serverUrl,
                            selected: chat.id == activeChatId,
                            onlineUserIds: onlineUserIds,
                            currentUserId: user.id,
                            onTap: () => onSelectChat(chat.id),
                          );
                        },
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemCount: chats.length,
                      ),
          ),
        ],
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({
    required this.chat,
    required this.serverUrl,
    required this.selected,
    required this.onlineUserIds,
    required this.currentUserId,
    required this.onTap,
  });

  final Chat chat;
  final String serverUrl;
  final bool selected;
  final Set<String> onlineUserIds;
  final String currentUserId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = chat.unread[currentUserId] ?? 0;
    final peerOnline = chat.type == ChatType.direct &&
        chat.participantIds.any(
          (id) => id != currentUserId && onlineUserIds.contains(id),
        );
    return Material(
      color: selected ? panelStrong : Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.28)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Stack(
                children: [
                  BrenksAvatar(
                    title: chat.title,
                    imageUrl: chat.avatarUrl,
                    baseUrl: serverUrl,
                    size: 52,
                  ),
                  if (peerOnline)
                    Positioned(
                      right: 1,
                      bottom: 1,
                      child: Container(
                        width: 13,
                        height: 13,
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF22262E),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (chat.pinnedToTop) ...[
                          const Icon(Icons.push_pin_rounded,
                              size: 15, color: muted),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            chat.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _lastMessageLabel(chat.lastMessage?.text),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (chat.lastMessage != null)
                    Text(
                      _formatTime(chat.lastMessage!.time),
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  if (unread > 0) ...[
                    const SizedBox(height: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        unread > 99 ? '99+' : '$unread',
                        style: const TextStyle(
                          color: Color(0xFF08131A),
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatPane extends StatelessWidget {
  const _ChatPane({
    required this.chat,
    required this.serverUrl,
    required this.user,
    required this.messages,
    required this.pinnedMessage,
    required this.typingNames,
    required this.loading,
    required this.sendingMedia,
    required this.recordingVoice,
    required this.recordingMs,
    required this.error,
    required this.replyTo,
    required this.editing,
    required this.messageController,
    required this.scrollController,
    required this.onSend,
    required this.onAttach,
    required this.onStartVoice,
    required this.onFinishVoice,
    required this.onCancelVoice,
    required this.onCancelComposerMode,
    required this.onTyping,
    required this.onOpenProfile,
    required this.onToggleMute,
    required this.onTogglePinTop,
    required this.onClearChat,
    required this.onDeleteChat,
    required this.onUnpinMessage,
    required this.onReply,
    required this.onEdit,
    required this.onDeleteMessage,
    required this.onPinMessage,
    required this.onReaction,
    required this.onPlayVoice,
  });

  final Chat? chat;
  final String serverUrl;
  final User user;
  final List<Message> messages;
  final Message? pinnedMessage;
  final List<String> typingNames;
  final bool loading;
  final bool sendingMedia;
  final bool recordingVoice;
  final int recordingMs;
  final String? error;
  final Message? replyTo;
  final Message? editing;
  final TextEditingController messageController;
  final ScrollController scrollController;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final VoidCallback onStartVoice;
  final VoidCallback onFinishVoice;
  final VoidCallback onCancelVoice;
  final VoidCallback onCancelComposerMode;
  final ValueChanged<bool> onTyping;
  final ValueChanged<Chat> onOpenProfile;
  final ValueChanged<Chat> onToggleMute;
  final ValueChanged<Chat> onTogglePinTop;
  final ValueChanged<Chat> onClearChat;
  final ValueChanged<Chat> onDeleteChat;
  final VoidCallback onUnpinMessage;
  final ValueChanged<Message> onReply;
  final ValueChanged<Message> onEdit;
  final ValueChanged<Message> onDeleteMessage;
  final ValueChanged<Message> onPinMessage;
  final void Function(Message message, String emoji) onReaction;
  final ValueChanged<MessageMedia> onPlayVoice;

  @override
  Widget build(BuildContext context) {
    final chat = this.chat;
    if (chat == null) {
      return const EmptyState(
        title: 'Выберите чат',
        subtitle: 'Откройте переписку или найдите собеседника слева.',
      );
    }

    return ColoredBox(
      color: bg,
      child: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _PatternPainter())),
          Column(
            children: [
              _ChatHeader(
                chat: chat,
                serverUrl: serverUrl,
                onOpenProfile: () => onOpenProfile(chat),
                onToggleMute: () => onToggleMute(chat),
                onTogglePinTop: () => onTogglePinTop(chat),
                onClearChat: () => onClearChat(chat),
                onDeleteChat: () => onDeleteChat(chat),
              ),
              if (pinnedMessage != null)
                _PinnedBanner(
                  message: pinnedMessage!,
                  onClose: onUnpinMessage,
                ),
              if (error != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: danger.withValues(alpha: 0.12),
                  child: Text(error!, style: const TextStyle(color: danger)),
                ),
              Expanded(
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : messages.isEmpty
                        ? const EmptyState(
                            title: 'Сообщений пока нет',
                            subtitle:
                                'Напишите первое сообщение из приложения.',
                          )
                        : ListView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                            itemCount: messages.length,
                            itemBuilder: (context, index) {
                              final message = messages[index];
                              return _MessageBubble(
                                message: message,
                                serverUrl: serverUrl,
                                own: message.senderId == user.id,
                                onReply: () => onReply(message),
                                onEdit: () => onEdit(message),
                                onDelete: () => onDeleteMessage(message),
                                onPin: () => onPinMessage(message),
                                onReaction: (emoji) =>
                                    onReaction(message, emoji),
                                onPlayVoice: onPlayVoice,
                              );
                            },
                          ),
              ),
              if (typingNames.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${typingNames.join(', ')} печатает...',
                      style: const TextStyle(color: muted),
                    ),
                  ),
                ),
              _Composer(
                replyTo: replyTo,
                editing: editing,
                sendingMedia: sendingMedia,
                recordingVoice: recordingVoice,
                recordingMs: recordingMs,
                controller: messageController,
                onAttach: onAttach,
                onSend: onSend,
                onStartVoice: onStartVoice,
                onFinishVoice: onFinishVoice,
                onCancelVoice: onCancelVoice,
                onCancelMode: onCancelComposerMode,
                onTyping: onTyping,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.chat,
    required this.serverUrl,
    required this.onOpenProfile,
    required this.onToggleMute,
    required this.onTogglePinTop,
    required this.onClearChat,
    required this.onDeleteChat,
  });

  final Chat chat;
  final String serverUrl;
  final VoidCallback onOpenProfile;
  final VoidCallback onToggleMute;
  final VoidCallback onTogglePinTop;
  final VoidCallback onClearChat;
  final VoidCallback onDeleteChat;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 82,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: const BoxDecoration(
        color: Color(0xFF202329),
        border: Border(
          bottom: BorderSide(color: Color(0xFF323946)),
        ),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: onOpenProfile,
            customBorder: const CircleBorder(),
            child: BrenksAvatar(
              title: chat.title,
              imageUrl: chat.avatarUrl,
              baseUrl: serverUrl,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: InkWell(
              onTap: onOpenProfile,
              borderRadius: BorderRadius.circular(12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chat.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _chatSubtitle(chat),
                    style: const TextStyle(color: muted),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Аудиозвонок будет следующим этапом',
            onPressed: null,
            icon: const Icon(Icons.call_rounded),
          ),
          IconButton(
            tooltip: 'Видеозвонок будет следующим этапом',
            onPressed: null,
            icon: const Icon(Icons.videocam_rounded),
          ),
          PopupMenuButton<String>(
            tooltip: 'Меню чата',
            onSelected: (value) {
              switch (value) {
                case 'profile':
                  onOpenProfile();
                case 'mute':
                  onToggleMute();
                case 'pin':
                  onTogglePinTop();
                case 'clear':
                  onClearChat();
                case 'delete':
                  onDeleteChat();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'profile', child: Text('Профиль')),
              PopupMenuItem(
                value: 'mute',
                child: Text(chat.muted ? 'Включить звук' : 'Выключить звук'),
              ),
              PopupMenuItem(
                value: 'pin',
                child:
                    Text(chat.pinnedToTop ? 'Открепить чат' : 'Закрепить чат'),
              ),
              const PopupMenuItem(value: 'clear', child: Text('Очистить чат')),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Удалить', style: TextStyle(color: danger)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PinnedBanner extends StatelessWidget {
  const _PinnedBanner({
    required this.message,
    required this.onClose,
  });

  final Message message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 12, 18, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: panelSoft.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          const Icon(Icons.push_pin_rounded, color: accent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _messagePreview(message),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            tooltip: 'Открепить',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.replyTo,
    required this.editing,
    required this.sendingMedia,
    required this.recordingVoice,
    required this.recordingMs,
    required this.controller,
    required this.onAttach,
    required this.onSend,
    required this.onStartVoice,
    required this.onFinishVoice,
    required this.onCancelVoice,
    required this.onCancelMode,
    required this.onTyping,
  });

  final Message? replyTo;
  final Message? editing;
  final bool sendingMedia;
  final bool recordingVoice;
  final int recordingMs;
  final TextEditingController controller;
  final VoidCallback onAttach;
  final VoidCallback onSend;
  final VoidCallback onStartVoice;
  final VoidCallback onFinishVoice;
  final VoidCallback onCancelVoice;
  final VoidCallback onCancelMode;
  final ValueChanged<bool> onTyping;

  @override
  Widget build(BuildContext context) {
    final modeMessage = editing ?? replyTo;
    final modeTitle = editing != null ? 'Редактирование' : 'Ответ';
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 18),
      decoration: const BoxDecoration(
        color: Color(0xCC202329),
        border: Border(top: BorderSide(color: Color(0xFF323946))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (recordingVoice)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: danger.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: danger.withValues(alpha: 0.28)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.mic_rounded, color: danger),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Запись голосового... ${_formatDuration(recordingMs)}',
                      style: const TextStyle(
                        color: text,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: onCancelVoice,
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Отмена'),
                  ),
                ],
              ),
            ),
          if (modeMessage != null)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: panelSoft,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 34,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          modeTitle,
                          style: const TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          _messagePreview(modeMessage),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: muted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Отмена',
                    onPressed: onCancelMode,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              IconButton(
                tooltip: 'Прикрепить файл',
                onPressed: sendingMedia || recordingVoice ? null : onAttach,
                icon: sendingMedia
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.attach_file_rounded),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 5,
                  enabled: !recordingVoice,
                  onChanged: (value) => onTyping(value.trim().isNotEmpty),
                  onSubmitted: (_) => onSend(),
                  decoration: const InputDecoration(
                    hintText: 'Сообщение',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filledTonal(
                tooltip: recordingVoice
                    ? 'Отправить голосовое'
                    : 'Записать голосовое',
                onPressed: recordingVoice ? onFinishVoice : onStartVoice,
                icon: Icon(
                  recordingVoice ? Icons.check_rounded : Icons.mic_rounded,
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: recordingVoice ? null : onSend,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(54, 54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  backgroundColor: accent,
                  foregroundColor: const Color(0xFF08131A),
                ),
                child: Icon(
                  editing != null ? Icons.check_rounded : Icons.send_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.serverUrl,
    required this.own,
    required this.onReply,
    required this.onEdit,
    required this.onDelete,
    required this.onPin,
    required this.onReaction,
    required this.onPlayVoice,
  });

  final Message message;
  final String serverUrl;
  final bool own;
  final VoidCallback onReply;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onPin;
  final ValueChanged<String> onReaction;
  final ValueChanged<MessageMedia> onPlayVoice;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapDown: (details) {
        _showMessageMenu(context, details.globalPosition);
      },
      child: Align(
        alignment: own ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 540),
          margin: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment:
                own ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 14, 10),
                decoration: BoxDecoration(
                  color: own ? const Color(0xFF3B5568) : panelSoft,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(20),
                    topRight: const Radius.circular(20),
                    bottomLeft: Radius.circular(own ? 20 : 6),
                    bottomRight: Radius.circular(own ? 6 : 20),
                  ),
                  border: Border.all(
                    color: own
                        ? accent.withValues(alpha: 0.2)
                        : Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _MessageContent(
                      message: message,
                      serverUrl: serverUrl,
                      onPlayVoice: onPlayVoice,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (message.editedAt != null && !message.deleted) ...[
                          const Text(
                            'изм.',
                            style: TextStyle(color: muted, fontSize: 12),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          _formatTime(message.createdAt),
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (message.reactions.isNotEmpty) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: message.reactions.entries.map((entry) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: panelStrong,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: border),
                      ),
                      child: Text('${entry.key} ${entry.value.length}'),
                    );
                  }).toList(growable: false),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showMessageMenu(BuildContext context, Offset position) async {
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        const PopupMenuItem(
          enabled: false,
          child: Text('Реакция', style: TextStyle(color: muted)),
        ),
        ..._quickReactions.map(
          (emoji) => PopupMenuItem(
            enabled: !message.deleted,
            value: 'react:$emoji',
            child: Text(emoji, style: const TextStyle(fontSize: 20)),
          ),
        ),
        const PopupMenuItem(value: 'reply', child: Text('Ответить')),
        if (own && !message.deleted)
          const PopupMenuItem(value: 'edit', child: Text('Изменить')),
        if (!message.deleted)
          const PopupMenuItem(value: 'copy', child: Text('Копировать текст')),
        if (!message.deleted)
          const PopupMenuItem(value: 'pin', child: Text('Закрепить')),
        if (own)
          const PopupMenuItem(
            value: 'delete',
            child: Text('Удалить', style: TextStyle(color: danger)),
          ),
      ],
    );

    switch (value) {
      case final reaction when reaction?.startsWith('react:') == true:
        onReaction(reaction!.substring('react:'.length));
      case 'reply':
        onReply();
      case 'edit':
        onEdit();
      case 'copy':
        await Clipboard.setData(ClipboardData(text: message.text.trim()));
      case 'pin':
        onPin();
      case 'delete':
        onDelete();
    }
  }
}

class _MessageContent extends StatelessWidget {
  const _MessageContent({
    required this.message,
    required this.serverUrl,
    required this.onPlayVoice,
  });

  final Message message;
  final String serverUrl;
  final ValueChanged<MessageMedia> onPlayVoice;

  @override
  Widget build(BuildContext context) {
    if (message.deleted) {
      return const Text(
        'Сообщение удалено',
        style: TextStyle(
          color: muted,
          fontSize: 16,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    final media = message.media;
    final text = message.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (media != null)
          _MediaPreview(
            media: media,
            serverUrl: serverUrl,
            onPlayVoice: onPlayVoice,
          ),
        if (message.imageUrl?.isNotEmpty == true)
          _LegacyImagePreview(dataUrl: message.imageUrl!, serverUrl: serverUrl),
        if (text.isNotEmpty) ...[
          if (media != null || message.imageUrl?.isNotEmpty == true)
            const SizedBox(height: 8),
          Text(
            text,
            style: const TextStyle(color: textColorAlias, fontSize: 16),
          ),
        ],
        if (media == null &&
            message.imageUrl?.isNotEmpty != true &&
            text.isEmpty)
          const Text('Сообщение', style: TextStyle(fontSize: 16)),
      ],
    );
  }
}

const textColorAlias = text;

class _MediaPreview extends StatelessWidget {
  const _MediaPreview({
    required this.media,
    required this.serverUrl,
    required this.onPlayVoice,
  });

  final MessageMedia media;
  final String serverUrl;
  final ValueChanged<MessageMedia> onPlayVoice;

  @override
  Widget build(BuildContext context) {
    if (media.kind == 'image') {
      return _ImagePreview(source: media.dataUrl, serverUrl: serverUrl);
    }
    if (media.kind == 'voice') {
      return _VoicePreview(
        media: media,
        onPlay: () => onPlayVoice(media),
      );
    }
    if (media.kind == 'video_note') {
      return _VideoNotePreview(media: media);
    }
    final icon = switch (media.kind) {
      _ => Icons.insert_drive_file_rounded,
    };
    final label = switch (media.kind) {
      _ => media.fileName ?? 'Файл',
    };
    return Container(
      width: 260,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF242A33),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _VoicePreview extends StatelessWidget {
  const _VoicePreview({
    required this.media,
    required this.onPlay,
  });

  final MessageMedia media;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 286,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF242A33),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          IconButton.filled(
            tooltip: 'Воспроизвести',
            onPressed: onPlay,
            icon: const Icon(Icons.play_arrow_rounded),
            style: IconButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: const Color(0xFF08131A),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Голосовое сообщение',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 7),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 5,
                    value: 0.44,
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      accent.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _formatDuration(media.durationMs ?? 0),
            style: const TextStyle(color: muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _VideoNotePreview extends StatelessWidget {
  const _VideoNotePreview({required this.media});

  final MessageMedia media;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF242A33),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 124,
            height: 124,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: panelStrong,
              border:
                  Border.all(color: accent.withValues(alpha: 0.32), width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: const Icon(
              Icons.play_arrow_rounded,
              color: accent,
              size: 54,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Видеокружок',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          if ((media.durationMs ?? 0) > 0)
            Text(
              _formatDuration(media.durationMs ?? 0),
              style: const TextStyle(color: muted, fontSize: 12),
            ),
        ],
      ),
    );
  }
}

class _LegacyImagePreview extends StatelessWidget {
  const _LegacyImagePreview({required this.dataUrl, required this.serverUrl});

  final String dataUrl;
  final String serverUrl;

  @override
  Widget build(BuildContext context) {
    return _ImagePreview(source: dataUrl, serverUrl: serverUrl);
  }
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.source, required this.serverUrl});

  final String source;
  final String serverUrl;

  @override
  Widget build(BuildContext context) {
    final bytes = _bytesFromDataUrl(source);
    final url = bytes == null ? _resolveMediaUrl(source, serverUrl) : null;
    if (bytes == null && (url == null || url.isEmpty)) {
      return const Text('Фото не удалось открыть');
    }
    return GestureDetector(
      onTap: () {
        if (bytes != null) {
          _openImageViewer(context, bytes);
        } else {
          _openNetworkImageViewer(context, url!);
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: bytes != null
            ? Image.memory(
                bytes,
                width: 320,
                fit: BoxFit.cover,
              )
            : Image.network(
                url!,
                width: 320,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const Text('Фото не удалось загрузить'),
              ),
      ),
    );
  }
}

class _NewChatDialog extends StatefulWidget {
  const _NewChatDialog({
    required this.serverUrl,
    required this.users,
  });

  final String serverUrl;
  final List<DirectoryUser> users;

  @override
  State<_NewChatDialog> createState() => _NewChatDialogState();
}

class _NewChatDialogState extends State<_NewChatDialog> {
  final _nameController = TextEditingController();
  final _searchController = TextEditingController();
  ChatType _type = ChatType.direct;
  Set<String> _selected = {};

  @override
  void dispose() {
    _nameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final users = query.isEmpty
        ? widget.users
        : widget.users
            .where((user) => user.title.toLowerCase().contains(query))
            .toList(growable: false);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Container(
        width: 560,
        height: 620,
        decoration: BoxDecoration(
          color: panel.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.42),
              blurRadius: 36,
              offset: const Offset(0, 22),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 24, 18, 18),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Новый чат',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Выберите формат и собеседников',
                          style: TextStyle(color: muted),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26),
              child: SegmentedButton<ChatType>(
                segments: const [
                  ButtonSegment(
                    value: ChatType.direct,
                    label: Text('Личный'),
                    icon: Icon(Icons.person_rounded),
                  ),
                  ButtonSegment(
                    value: ChatType.group,
                    label: Text('Группа'),
                    icon: Icon(Icons.groups_rounded),
                  ),
                  ButtonSegment(
                    value: ChatType.channel,
                    label: Text('Канал'),
                    icon: Icon(Icons.campaign_rounded),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (value) {
                  setState(() {
                    _type = value.first;
                    _selected = {};
                  });
                },
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(26, 18, 26, 8),
                child: Column(
                  children: [
                    if (_type != ChatType.direct) ...[
                      TextField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: _type == ChatType.group
                              ? 'Название группы'
                              : 'Название канала',
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        hintText: 'Поиск людей...',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: border),
                        ),
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: users.length,
                          separatorBuilder: (_, __) =>
                              Divider(height: 1, color: border),
                          itemBuilder: (context, index) {
                            final user = users[index];
                            final selected = _selected.contains(user.id);
                            return ListTile(
                              leading: BrenksAvatar(
                                title: user.title,
                                imageUrl: user.avatarUrl,
                                baseUrl: widget.serverUrl,
                              ),
                              title: Text(user.title),
                              subtitle: Text('@${user.username}'),
                              trailing: selected
                                  ? const Icon(
                                      Icons.check_circle_rounded,
                                      color: accent,
                                    )
                                  : const Icon(Icons.chevron_right_rounded),
                              onTap: () {
                                setState(() {
                                  if (_type == ChatType.direct) {
                                    _selected = {user.id};
                                  } else if (selected) {
                                    _selected = {..._selected}..remove(user.id);
                                  } else {
                                    _selected = {..._selected, user.id};
                                  }
                                });
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 10, 26, 24),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Отмена'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _selected.isEmpty
                          ? null
                          : () {
                              final name = _nameController.text.trim();
                              if (_type != ChatType.direct && name.isEmpty) {
                                return;
                              }
                              Navigator.pop(
                                context,
                                _NewChatResult(
                                  type: _type,
                                  name: name,
                                  memberIds: _selected.toList(growable: false),
                                ),
                              );
                            },
                      child: const Text('Создать'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewChatResult {
  const _NewChatResult({
    required this.type,
    required this.name,
    required this.memberIds,
  });

  final ChatType type;
  final String name;
  final List<String> memberIds;
}

class _AccountDialog extends StatelessWidget {
  const _AccountDialog({
    required this.user,
    required this.serverUrl,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.onLogout,
  });

  final User user;
  final String serverUrl;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Container(
        width: 500,
        decoration: BoxDecoration(
          color: panel.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.42),
              blurRadius: 36,
              offset: const Offset(0, 22),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(
                color: panelSoft.withValues(alpha: 0.68),
                border: Border(bottom: BorderSide(color: border)),
              ),
              child: Row(
                children: [
                  BrenksAvatar(
                    title: user.title,
                    imageUrl: user.avatarUrl,
                    baseUrl: serverUrl,
                    size: 78,
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text('@${user.username}',
                            style: const TextStyle(color: muted)),
                        if (user.email?.isNotEmpty == true)
                          Text(
                            user.email!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: muted),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: panelSoft.withValues(alpha: 0.64),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: border),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.contrast_rounded, color: accent),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Тема',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              Text(
                                'Переключение интерфейса приложения',
                                style: TextStyle(color: muted, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        SegmentedButton<ThemeMode>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(
                              value: ThemeMode.dark,
                              label: Text('Темная'),
                              icon: Icon(Icons.dark_mode_rounded),
                            ),
                            ButtonSegment(
                              value: ThemeMode.light,
                              label: Text('Светлая'),
                              icon: Icon(Icons.light_mode_rounded),
                            ),
                          ],
                          selected: {themeMode},
                          onSelectionChanged: (value) {
                            onThemeModeChanged(value.first);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Закрыть'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: () {
                            Navigator.pop(context);
                            onLogout();
                          },
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text('Выйти'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatProfileDialog extends StatelessWidget {
  const _ChatProfileDialog({
    required this.serverUrl,
    required this.chat,
    required this.onlineUserIds,
  });

  final String serverUrl;
  final Chat chat;
  final Set<String> onlineUserIds;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Container(
        width: 520,
        constraints: const BoxConstraints(maxHeight: 680),
        decoration: BoxDecoration(
          color: panel.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.42),
              blurRadius: 36,
              offset: const Offset(0, 22),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(
                color: panelSoft.withValues(alpha: 0.68),
                border: Border(bottom: BorderSide(color: border)),
              ),
              child: Column(
                children: [
                  BrenksAvatar(
                    title: chat.title,
                    imageUrl: chat.avatarUrl,
                    baseUrl: serverUrl,
                    size: 92,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    chat.title,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(_chatSubtitle(chat),
                      style: const TextStyle(color: muted)),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(18),
                children: [
                  const Text(
                    'Участники',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  for (final participant in chat.participants)
                    ListTile(
                      leading: BrenksAvatar(
                        title: participant.title,
                        imageUrl: participant.avatarUrl,
                        baseUrl: serverUrl,
                      ),
                      title: Text(participant.title),
                      subtitle: Text(
                        onlineUserIds.contains(participant.id)
                            ? 'онлайн'
                            : '@${participant.username}',
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Закрыть'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _chatSubtitle(Chat chat) {
  return switch (chat.type) {
    ChatType.direct => 'личный чат',
    ChatType.group => '${chat.participants.length} участников',
    ChatType.channel => 'канал',
  };
}

String _lastMessageLabel(String? text) {
  final trimmed = text?.trim();
  if (trimmed == null || trimmed.isEmpty) return 'Нет сообщений';
  if (trimmed == ' ') return 'Медиа';
  return trimmed;
}

String _messagePreview(Message message) {
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
  return message.text.trim().isEmpty ? 'Сообщение' : message.text.trim();
}

String _formatTime(int timestamp) {
  if (timestamp <= 0) return '';
  final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _formatDuration(int milliseconds) {
  final totalSeconds = (milliseconds / 1000).round();
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

Uint8List? _bytesFromDataUrl(String dataUrl) {
  final marker = 'base64,';
  final index = dataUrl.indexOf(marker);
  if (index == -1) return null;
  try {
    return base64Decode(dataUrl.substring(index + marker.length));
  } on Object {
    return null;
  }
}

String? _resolveMediaUrl(String? value, String baseUrl) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty || raw.startsWith('data:')) return raw;
  final uri = Uri.tryParse(raw);
  if (uri == null || uri.hasScheme) return raw;
  return Uri.parse(baseUrl).resolve(raw).toString();
}

void _openImageViewer(BuildContext context, Uint8List bytes) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.78),
    builder: (context) {
      return Dialog.fullscreen(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 0.6,
                maxScale: 5,
                child: Center(
                  child: Image.memory(bytes, fit: BoxFit.contain),
                ),
              ),
            ),
            Positioned(
              right: 24,
              top: 24,
              child: IconButton.filledTonal(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ],
        ),
      );
    },
  );
}

void _openNetworkImageViewer(BuildContext context, String url) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.78),
    builder: (context) {
      return Dialog.fullscreen(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 0.6,
                maxScale: 5,
                child: Center(
                  child: Image.network(url, fit: BoxFit.contain),
                ),
              ),
            ),
            Positioned(
              right: 24,
              top: 24,
              child: IconButton.filledTonal(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _PatternPainter extends CustomPainter {
  const _PatternPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.035)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    const gap = 46.0;
    const arm = 6.0;
    for (double y = 26; y < size.height; y += gap) {
      for (double x = 26; x < size.width; x += gap) {
        canvas.drawLine(Offset(x - arm, y), Offset(x + arm, y), paint);
        canvas.drawLine(Offset(x, y - arm), Offset(x, y + arm), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
