import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math' as math;
import 'dart:ui' show FontFeature, ImageFilter;

import 'package:camera_macos/camera_macos.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mime/mime.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import '../services/api_client.dart';
import '../services/audio_message_service.dart';
import '../services/local_cache_service.dart';
import '../services/socket_service.dart';
import '../theme/app_theme.dart';
import '../widgets/brenks_avatar.dart';
import '../widgets/brenks_cached_image.dart';
import '../widgets/empty_state.dart';

const _quickReactions = ['👍', '❤️', '😂', '🔥', '😮'];
const _maxMediaDataUrlLength = 14 * 1000 * 1000;

enum _RecordKind { voice, videoNote }

class _CustomChatFolder {
  const _CustomChatFolder({
    required this.id,
    required this.name,
    required this.chatIds,
  });

  final String id;
  final String name;
  final Set<String> chatIds;

  factory _CustomChatFolder.fromJson(Map<String, dynamic> json) {
    final chatIds = json['chatIds'];
    return _CustomChatFolder(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Папка',
      chatIds: chatIds is List
          ? chatIds.map((item) => item.toString()).toSet()
          : <String>{},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'chatIds': chatIds.toList(growable: false),
    };
  }
}

BoxDecoration _glassDecoration({
  Color? color,
  double radius = 24,
  Color? borderColor,
  List<BoxShadow>? shadows,
}) {
  return BoxDecoration(
    color: color ?? const Color(0xB823252A),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: borderColor ?? Colors.white.withValues(alpha: 0.085),
    ),
    boxShadow: shadows ??
        [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
          BoxShadow(
            color: accent.withValues(alpha: 0.035),
            blurRadius: 0,
            offset: const Offset(0, 1),
          ),
        ],
  );
}

class _GlassSurface extends StatelessWidget {
  const _GlassSurface({
    required this.child,
    this.padding,
    this.margin,
    this.radius = 24,
    this.color,
    this.width,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final Color? color;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            width: width,
            padding: padding,
            decoration: _glassDecoration(color: color, radius: radius),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _SoftIconButton extends StatelessWidget {
  const _SoftIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        fixedSize: const Size(36, 36),
        backgroundColor: Colors.white.withValues(alpha: 0.048),
        disabledBackgroundColor: Colors.white.withValues(alpha: 0.025),
        foregroundColor: muted,
        disabledForegroundColor: muted.withValues(alpha: 0.38),
        side: BorderSide(
          color: accent.withValues(alpha: 0.105),
        ),
      ),
    );
  }
}

class MessengerScreen extends StatefulWidget {
  const MessengerScreen({
    super.key,
    required this.user,
    required this.api,
    required this.serverUrl,
    required this.token,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.uiScale,
    required this.onUiScaleChanged,
    required this.onLogout,
  });

  final User user;
  final ApiClient api;
  final String serverUrl;
  final String token;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final double uiScale;
  final ValueChanged<double> onUiScaleChanged;
  final VoidCallback onLogout;

  @override
  State<MessengerScreen> createState() => _MessengerScreenState();
}

class _MessengerScreenState extends State<MessengerScreen> {
  final _messageController = TextEditingController();
  final _messageFocusNode = FocusNode();
  final _messageScrollController = ScrollController();
  final _chatSearchController = TextEditingController();
  final _audioService = AudioMessageService();
  StreamSubscription<double>? _recordingLevelSub;

  late final LocalCacheService _cache;
  BrenksSocket? _socket;
  late User _currentUser;
  List<Chat> _chats = const [];
  List<Message> _messages = const [];
  Set<String> _onlineUserIds = const {};
  Map<String, String> _typingNames = const {};
  List<DirectoryUser> _userSearchResults = const [];
  List<_CustomChatFolder> _customFolders = const [];
  String? _activeCustomFolderId;
  String? _activeChatId;
  Message? _replyTo;
  Message? _editing;
  bool _loadingChats = true;
  bool _loadingMessages = false;
  bool _socketConnected = false;
  bool _sendingMedia = false;
  bool _recordingVoice = false;
  bool _recordingVideoNote = false;
  bool _pendingVideoNoteStart = false;
  bool _searchingUsers = false;
  _RecordKind _recordKind = _RecordKind.voice;
  CameraMacOSController? _videoNoteController;
  int _recordingMs = 0;
  int? _recordingStartedAt;
  double _recordingLevel = 0;
  String? _error;
  String? _userSearchError;
  Timer? _typingTimer;
  Timer? _userSearchTimer;
  bool _typingActive = false;

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
    _currentUser = widget.user;
    _cache = LocalCacheService(userId: widget.user.id);
    unawaited(_restoreCachedChats());
    unawaited(_loadCustomFolders());
    _loadChats();
    _connectSocket();
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _userSearchTimer?.cancel();
    _recordingLevelSub?.cancel();
    _sendTypingState(false);
    _socket?.dispose();
    unawaited(_audioService.dispose());
    unawaited(_videoNoteController?.destroy());
    _messageController.dispose();
    _messageFocusNode.dispose();
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
        unawaited(_cache.upsertMessage(message));
        final shouldFollow =
            message.senderId == _currentUser.id || _isNearMessageBottom();
        if (message.chatId == _activeChatId) {
          setState(() {
            if (!_messages.any((item) => item.id == message.id)) {
              _messages = [..._messages, message];
            }
          });
          _socket?.markRead(message.chatId);
          if (shouldFollow) _scrollToBottom();
        }
      },
      onChatUpdated: (chat) {
        if (!mounted) return;
        if (_isSameChatSnapshot(chat)) return;
        setState(() => _upsertChat(chat));
        unawaited(_cache.saveChats(_chats));
      },
      onMessageDeleted: (chatId, messageId) {
        unawaited(_cache.removeMessage(chatId: chatId, messageId: messageId));
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
        unawaited(_cache.upsertMessage(message));
        if (!mounted || message.chatId != _activeChatId) return;
        setState(() {
          _messages = _messages
              .map((item) => item.id == message.id ? message : item)
              .toList(growable: false);
        });
      },
      onChatDeleted: (chatId) {
        if (!mounted) return;
        unawaited(_cache.clearMessages(chatId));
        setState(() {
          _chats = _chats.where((chat) => chat.id != chatId).toList();
          if (_activeChatId == chatId) {
            _activeChatId = null;
            _messages = const [];
          }
        });
        unawaited(_cache.saveChats(_chats));
      },
      onMessagesCleared: (chatId) {
        unawaited(_cache.clearMessages(chatId));
        if (!mounted || chatId != _activeChatId) return;
        setState(() => _messages = const []);
      },
      onPresence: (userIds) {
        if (!mounted) return;
        final next = userIds.toSet();
        if (_setEquals(next, _onlineUserIds)) return;
        setState(() => _onlineUserIds = next);
      },
      onSocketError: _showSnack,
      onTyping: ({
        required chatId,
        required userId,
        required username,
        required isTyping,
      }) {
        if (!mounted || chatId != _activeChatId || userId == _currentUser.id) {
          return;
        }
        final current = _typingNames[userId];
        if (isTyping && current == username) return;
        if (!isTyping && current == null) return;
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

  Future<void> _restoreCachedChats() async {
    final cached = _sortChats(await _cache.loadChats());
    if (!mounted || cached.isEmpty || _chats.isNotEmpty) return;
    setState(() => _chats = cached);
    _joinAllChats();
    if (_activeChatId == null) {
      unawaited(_selectChat(cached.first.id, preferCache: true));
    }
  }

  String get _customFoldersKey => 'brenkschat.${_currentUser.id}.chatFolders';

  Future<void> _loadCustomFolders() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_customFoldersKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final folders = decoded
          .whereType<Map>()
          .map((item) =>
              _CustomChatFolder.fromJson(item.cast<String, dynamic>()))
          .where((folder) => folder.id.isNotEmpty)
          .toList(growable: false);
      if (!mounted) return;
      setState(() => _customFolders = folders);
    } on Object {
      return;
    }
  }

  Future<void> _saveCustomFolders() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _customFoldersKey,
      jsonEncode(_customFolders.map((folder) => folder.toJson()).toList()),
    );
  }

  Future<void> _showCreateFolderDialog() async {
    final result = await showDialog<_CustomChatFolder>(
      context: context,
      builder: (_) => _CreateChatFolderDialog(
        chats: _chats,
        currentUserId: _currentUser.id,
        serverUrl: widget.serverUrl,
      ),
    );
    if (result == null) return;
    setState(() {
      _customFolders = [..._customFolders, result];
      _activeCustomFolderId = result.id;
    });
    unawaited(_saveCustomFolders());
  }

  _CustomChatFolder? _customFolderById(String? folderId) {
    if (folderId == null) return null;
    for (final folder in _customFolders) {
      if (folder.id == folderId) return folder;
    }
    return null;
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
      unawaited(_cache.saveChats(chats));
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

  Future<void> _selectChat(String chatId, {bool preferCache = false}) async {
    _sendTypingState(false);
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
    final cached = await _cache.loadMessages(chatId);
    if (mounted && _activeChatId == chatId && cached.isNotEmpty) {
      setState(() => _messages = cached);
      if (preferCache) _scrollToBottom(instant: true);
    }
    try {
      final messages = await widget.api.fetchMessages(chatId);
      if (!mounted || _activeChatId != chatId) return;
      setState(() {
        _messages = messages;
        _loadingMessages = false;
      });
      unawaited(_cache.saveMessages(chatId, messages));
      _scrollToBottom(instant: true);
      _focusComposer();
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

  bool _isSameChatSnapshot(Chat incoming) {
    final index = _chats.indexWhere((item) => item.id == incoming.id);
    if (index == -1) return false;
    final current = _chats[index];
    return current.type == incoming.type &&
        current.name == incoming.name &&
        current.displayName == incoming.displayName &&
        current.avatarUrl == incoming.avatarUrl &&
        current.pinnedMessageId == incoming.pinnedMessageId &&
        current.muted == incoming.muted &&
        current.pinnedToTop == incoming.pinnedToTop &&
        current.verified == incoming.verified &&
        _listEquals(current.participantIds, incoming.participantIds) &&
        _unreadEquals(current.unread, incoming.unread) &&
        _sameLastMessage(current.lastMessage, incoming.lastMessage) &&
        _participantsEquals(current.participants, incoming.participants);
  }

  bool _sameLastMessage(LastMessage? a, LastMessage? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    return a.text == b.text && a.time == b.time && a.senderId == b.senderId;
  }

  bool _participantsEquals(
    List<ChatParticipant> a,
    List<ChatParticipant> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final left = a[i];
      final right = b[i];
      if (left.id != right.id ||
          left.username != right.username ||
          left.displayName != right.displayName ||
          left.avatarUrl != right.avatarUrl) {
        return false;
      }
    }
    return true;
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _unreadEquals(Map<String, int> a, Map<String, int> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  bool _setEquals(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final item in a) {
      if (!b.contains(item)) return false;
    }
    return true;
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
      allowMultiple: true,
    );
    final files = result?.files ?? const <PlatformFile>[];
    if (files.isEmpty) return;

    setState(() => _sendingMedia = true);
    try {
      var includeText = true;
      var sent = 0;
      for (final file in files) {
        final bytes = file.bytes ??
            (file.path == null
                ? null
                : await io.File(file.path!).readAsBytes());
        if (bytes == null || bytes.isEmpty) continue;
        final ok = _sendAttachmentBytes(
          bytes: bytes,
          fileName: file.name,
          mimeType: lookupMimeType(
            file.name,
            headerBytes: bytes.take(16).toList(),
          ),
          includeComposerText: includeText,
        );
        if (ok) {
          sent += 1;
          includeText = false;
        }
      }
      if (sent == 0) _showSnack('Не удалось прочитать выбранные файлы.');
    } on Object catch (err) {
      _showSnack('Не удалось отправить файл: $err');
    } finally {
      if (mounted) setState(() => _sendingMedia = false);
    }
  }

  Future<void> _sendDroppedFiles(List<DropItem> dropped) async {
    final chatId = _activeChatId;
    if (chatId == null || dropped.isEmpty || _sendingMedia) return;
    final allFiles = _flattenDroppedFiles(dropped).toList();
    final files = allFiles.take(20).toList();
    if (files.isEmpty) return;
    if (allFiles.length > 20) {
      _showSnack('Отправляю первые 20 файлов, чтобы чат не завис.');
    }

    setState(() => _sendingMedia = true);
    try {
      var includeText = true;
      var sent = 0;
      for (final file in files) {
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) continue;
        final fileName = file.name.isNotEmpty
            ? file.name
            : file.path.split(io.Platform.pathSeparator).last;
        final ok = _sendAttachmentBytes(
          bytes: bytes,
          fileName: fileName.isEmpty ? 'file' : fileName,
          mimeType: file.mimeType ??
              lookupMimeType(
                file.path,
                headerBytes: bytes.take(16).toList(),
              ),
          includeComposerText: includeText,
        );
        if (ok) {
          sent += 1;
          includeText = false;
        }
      }
      if (sent == 0) _showSnack('Не удалось отправить перетащенные файлы.');
    } on Object catch (err) {
      _showSnack('Не удалось отправить перетащенные файлы: $err');
    } finally {
      if (mounted) setState(() => _sendingMedia = false);
    }
  }

  Iterable<DropItem> _flattenDroppedFiles(List<DropItem> items) sync* {
    for (final item in items) {
      if (item is DropItemDirectory) {
        yield* _flattenDroppedFiles(item.children);
      } else {
        yield item;
      }
    }
  }

  Future<void> _pasteIntoComposer() async {
    if (_recordingVoice || _recordingVideoNote || _sendingMedia) return;
    try {
      final image = await Pasteboard.image;
      if (image != null && image.isNotEmpty) {
        setState(() => _sendingMedia = true);
        try {
          final ok = _sendAttachmentBytes(
            bytes: image,
            fileName: 'clipboard-image.png',
            mimeType: lookupMimeType(
                  'clipboard-image.png',
                  headerBytes: image.take(16).toList(),
                ) ??
                'image/png',
            includeComposerText: true,
          );
          if (!ok) _showSnack('Не удалось отправить изображение из буфера.');
        } finally {
          if (mounted) setState(() => _sendingMedia = false);
        }
        return;
      }

      final filePaths = await Pasteboard.files();
      if (filePaths.isNotEmpty) {
        setState(() => _sendingMedia = true);
        try {
          var includeText = true;
          var sent = 0;
          for (final path in filePaths.take(20)) {
            final file = io.File(path);
            if (!await file.exists()) continue;
            final bytes = await file.readAsBytes();
            if (bytes.isEmpty) continue;
            final fileName = path.split(io.Platform.pathSeparator).last;
            final ok = _sendAttachmentBytes(
              bytes: bytes,
              fileName: fileName.isEmpty ? 'file' : fileName,
              mimeType: lookupMimeType(
                path,
                headerBytes: bytes.take(16).toList(),
              ),
              includeComposerText: includeText,
            );
            if (ok) {
              sent += 1;
              includeText = false;
            }
          }
          if (sent > 0) return;
        } finally {
          if (mounted) setState(() => _sendingMedia = false);
        }
      }

      final text = await Pasteboard.text;
      if (text == null || text.isEmpty) return;
      _insertTextIntoComposer(text);
    } on Object catch (err) {
      _showSnack('Не удалось вставить из буфера: $err');
    }
  }

  void _insertTextIntoComposer(String value) {
    final current = _messageController.text;
    final selection = _messageController.selection;
    final start = selection.isValid ? selection.start : current.length;
    final end = selection.isValid ? selection.end : current.length;
    final next = current.replaceRange(start, end, value);
    final offset = start + value.length;
    _messageController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: offset),
    );
    _notifyTyping(next.trim().isNotEmpty);
    _focusComposer();
  }

  bool _sendAttachmentBytes({
    required List<int> bytes,
    required String fileName,
    required String? mimeType,
    required bool includeComposerText,
  }) {
    final chatId = _activeChatId;
    if (chatId == null || bytes.isEmpty) return false;
    final resolvedMimeType = mimeType ?? 'application/octet-stream';
    final dataUrl = 'data:$resolvedMimeType;base64,${base64Encode(bytes)}';
    if (dataUrl.length > _maxMediaDataUrlLength) {
      _showSnack('$fileName слишком большой для текущего сервера.');
      return false;
    }
    final media = MessageMedia(
      kind: resolvedMimeType.startsWith('image/') ? 'image' : 'file',
      dataUrl: dataUrl,
      fileName: fileName,
      mimeType: resolvedMimeType,
    );
    _socket?.sendMessage(
      chatId: chatId,
      text: includeComposerText ? _messageController.text.trim() : '',
      media: media,
      replyToMessageId: includeComposerText ? _replyTo?.id : null,
    );
    if (includeComposerText) {
      setState(() => _replyTo = null);
      _messageController.clear();
      _notifyTyping(false);
    }
    return true;
  }

  Future<void> _startVoiceRecording() async {
    final chatId = _activeChatId;
    if (chatId == null || _recordingVoice || _recordingVideoNote) return;
    try {
      await _audioService.startRecording();
      setState(() {
        _recordingVoice = true;
        _recordingMs = 0;
        _recordingLevel = 0;
        _recordingStartedAt = DateTime.now().millisecondsSinceEpoch;
        _editing = null;
        _replyTo = null;
      });
      _startRecordingLevelMeter();
    } on Object catch (err) {
      _showSnack('Не удалось начать запись: $err');
    }
  }

  void _setRecordKind(_RecordKind kind) {
    if (_recordingVoice || _recordingVideoNote || _sendingMedia) return;
    setState(() => _recordKind = kind);
  }

  void _toggleRecordKind() {
    _setRecordKind(
      _recordKind == _RecordKind.voice
          ? _RecordKind.videoNote
          : _RecordKind.voice,
    );
  }

  Future<void> _startSelectedRecording() async {
    if (_recordKind == _RecordKind.videoNote) {
      await _startVideoNoteRecording();
    } else {
      await _startVoiceRecording();
    }
  }

  Future<void> _finishVoiceRecording() async {
    final chatId = _activeChatId;
    if (chatId == null || !_recordingVoice) return;
    final startedAt = _recordingStartedAt;
    _stopRecordingLevelMeter();
    setState(() {
      _recordingVoice = false;
      _recordingMs = startedAt == null
          ? 0
          : DateTime.now().millisecondsSinceEpoch - startedAt;
      _recordingStartedAt = null;
      _recordingLevel = 0;
    });
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

  Future<void> _startVideoNoteRecording() async {
    final chatId = _activeChatId;
    if (chatId == null || _recordingVoice || _recordingVideoNote) return;
    if (!io.Platform.isMacOS) {
      _showSnack('Запись видеокружков пока доступна только в macOS-версии.');
      return;
    }
    setState(() {
      _recordKind = _RecordKind.videoNote;
      _recordingVideoNote = true;
      _pendingVideoNoteStart = true;
      _recordingMs = 0;
      _recordingLevel = 0.42;
      _recordingStartedAt = DateTime.now().millisecondsSinceEpoch;
      _editing = null;
      _replyTo = null;
    });
  }

  void _handleVideoNoteCameraReady(CameraMacOSController controller) {
    _videoNoteController = controller;
    unawaited(controller.setVideoMirrored(false).catchError((_) {}));
    if (_pendingVideoNoteStart) {
      _pendingVideoNoteStart = false;
      unawaited(_beginVideoNoteRecording(controller));
    }
  }

  Future<void> _beginVideoNoteRecording(
      CameraMacOSController controller) async {
    try {
      final ok = await controller.recordVideo(
        maxVideoDuration: 60,
        enableAudio: true,
      );
      if (ok != true) {
        throw Exception('Камера не начала запись.');
      }
    } on Object catch (err) {
      if (!mounted) return;
      setState(() {
        _recordingVideoNote = false;
        _pendingVideoNoteStart = false;
        _recordingMs = 0;
        _recordingLevel = 0;
        _recordingStartedAt = null;
      });
      _showSnack('Не удалось начать запись кружка: $err');
    }
  }

  Future<void> _finishVideoNoteRecording() async {
    final chatId = _activeChatId;
    final controller = _videoNoteController;
    if (chatId == null || !_recordingVideoNote || controller == null) return;
    final startedAt = _recordingStartedAt;
    try {
      final file = await controller.stopRecording();
      final durationMs = startedAt == null
          ? 0
          : DateTime.now().millisecondsSinceEpoch - startedAt;
      if (mounted) {
        setState(() {
          _recordingVideoNote = false;
          _pendingVideoNoteStart = false;
          _recordingMs = durationMs;
          _recordingLevel = 0;
          _recordingStartedAt = null;
          _videoNoteController = null;
        });
      }
      unawaited(controller.destroy().catchError((_) => null));
      final bytes = file?.bytes;
      if (bytes == null || bytes.isEmpty) {
        _showSnack('Кружок не записался.');
        return;
      }
      final media = MessageMedia(
        kind: 'video_note',
        dataUrl: 'data:video/mp4;base64,${base64Encode(bytes)}',
        fileName: 'video-note.mp4',
        mimeType: 'video/mp4',
        durationMs: durationMs,
      );
      if (media.dataUrl.length > _maxMediaDataUrlLength) {
        _showSnack('Кружок получился слишком большим.');
        return;
      }
      _socket?.sendMessage(chatId: chatId, text: '', media: media);
    } on Object catch (err) {
      if (mounted) {
        setState(() {
          _recordingVideoNote = false;
          _pendingVideoNoteStart = false;
          _recordingMs = 0;
          _recordingLevel = 0;
          _recordingStartedAt = null;
          _videoNoteController = null;
        });
      }
      unawaited(controller.destroy().catchError((_) => null));
      _showSnack('Не удалось отправить кружок: $err');
    }
  }

  Future<void> _cancelVoiceRecording() async {
    if (!_recordingVoice) return;
    _stopRecordingLevelMeter();
    setState(() {
      _recordingVoice = false;
      _recordingMs = 0;
      _recordingLevel = 0;
      _recordingStartedAt = null;
    });
    await _audioService.cancelRecording();
  }

  Future<void> _cancelVideoNoteRecording() async {
    final controller = _videoNoteController;
    if (!_recordingVideoNote) return;
    if (controller?.isRecording == true) {
      await controller?.stopRecording().catchError((_) => null);
    }
    if (!mounted) return;
    setState(() {
      _recordingVideoNote = false;
      _pendingVideoNoteStart = false;
      _recordingMs = 0;
      _recordingLevel = 0;
      _recordingStartedAt = null;
      _videoNoteController = null;
    });
    if (controller != null) {
      unawaited(controller.destroy().catchError((_) => null));
    }
  }

  void _startRecordingLevelMeter() {
    _recordingLevelSub?.cancel();
    _recordingLevelSub = _audioService
        .amplitudeLevels(const Duration(milliseconds: 70))
        .listen((level) {
      if (!mounted || !_recordingVoice) return;
      setState(() {
        _recordingLevel = _recordingLevel * 0.58 + level * 0.42;
      });
    }, onError: (_) {});
  }

  void _stopRecordingLevelMeter() {
    _recordingLevelSub?.cancel();
    _recordingLevelSub = null;
  }

  Future<void> _finishRecording() async {
    if (_recordingVideoNote) {
      await _finishVideoNoteRecording();
    } else {
      await _finishVoiceRecording();
    }
  }

  Future<void> _cancelRecording() async {
    if (_recordingVideoNote) {
      await _cancelVideoNoteRecording();
    } else {
      await _cancelVoiceRecording();
    }
  }

  Future<void> _playVoice(MessageMedia media) async {
    try {
      await _audioService.playDataUrl(media.dataUrl);
    } on Object catch (err) {
      _showSnack('Не удалось воспроизвести аудио: $err');
    }
  }

  void _startEdit(Message message) {
    if (message.deleted || message.senderId != _currentUser.id) return;
    setState(() {
      _editing = message;
      _replyTo = null;
    });
    _messageController.text = message.text.trim();
    _messageController.selection = TextSelection.collapsed(
      offset: _messageController.text.length,
    );
    _focusComposer();
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
    _typingTimer?.cancel();
    if (isTyping) {
      if (!_typingActive) {
        _typingActive = true;
        _socket?.typing(chatId: chatId, isTyping: true);
      }
      _typingTimer = Timer(const Duration(milliseconds: 1400), () {
        if (_activeChatId == chatId) {
          _sendTypingState(false);
        }
      });
    } else {
      _sendTypingState(false);
    }
  }

  void _sendTypingState(bool isTyping) {
    final chatId = _activeChatId;
    if (chatId == null) return;
    if (_typingActive == isTyping) return;
    _typingActive = isTyping;
    _socket?.typing(chatId: chatId, isTyping: isTyping);
  }

  void _focusComposer() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _messageFocusNode.requestFocus();
    });
  }

  void _handleSidebarSearchChanged() {
    final query = _chatSearchController.text.trim();
    setState(() {});
    _userSearchTimer?.cancel();

    final normalized = query.startsWith('@') ? query.substring(1) : query;
    if (normalized.length < 2) {
      setState(() {
        _userSearchResults = const [];
        _searchingUsers = false;
        _userSearchError = null;
      });
      return;
    }

    _userSearchTimer = Timer(const Duration(milliseconds: 320), () {
      unawaited(_searchUsers(normalized));
    });
  }

  Future<void> _searchUsers(String query) async {
    if (!mounted) return;
    setState(() {
      _searchingUsers = true;
      _userSearchError = null;
    });
    try {
      final users = await widget.api.searchUsers(query);
      if (!mounted) return;
      final currentQuery = _chatSearchController.text.trim();
      final normalized = currentQuery.startsWith('@')
          ? currentQuery.substring(1)
          : currentQuery;
      if (normalized != query) return;
      setState(() {
        _userSearchResults = users
            .where((item) => item.id != _currentUser.id)
            .toList(growable: false);
        _searchingUsers = false;
      });
    } on Object catch (err) {
      if (!mounted) return;
      setState(() {
        _userSearchResults = const [];
        _searchingUsers = false;
        _userSearchError = err.toString();
      });
    }
  }

  Future<void> _startDirectChat(DirectoryUser user) async {
    try {
      final chat = await widget.api.createDirectChat(targetUserId: user.id);
      _chatSearchController.clear();
      setState(() {
        _userSearchResults = const [];
        _userSearchError = null;
        _searchingUsers = false;
      });
      await _loadChats();
      await _selectChat(chat.id);
    } on Object catch (err) {
      _showSnack('Не удалось открыть чат: $err');
    }
  }

  Future<void> _showCreateSpaceDialog() async {
    final result = await showDialog<_CreateSpaceResult>(
      context: context,
      builder: (_) => const _CreateSpaceDialog(),
    );
    if (result == null) return;
    try {
      final chat = result.type == ChatType.channel
          ? await widget.api.createChannelChat(
              name: result.name,
              subscriberIds: const [],
            )
          : await widget.api.createGroupChat(
              name: result.name,
              memberIds: const [],
            );
      await _loadChats();
      await _selectChat(chat.id);
      setState(() => _activeCustomFolderId = null);
    } on Object catch (err) {
      _showSnack('Не удалось создать: $err');
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

  Future<void> _toggleChatVerified(Chat chat) async {
    if (!_currentUser.isAdmin || chat.type != ChatType.channel) return;
    try {
      final updated = await widget.api.setChatVerified(
        chatId: chat.id,
        verified: !chat.verified,
      );
      setState(() => _upsertChat(updated));
      unawaited(_cache.saveChats(_chats));
    } on Object catch (err) {
      _showSnack('Не удалось изменить галочку: $err');
    }
  }

  Future<void> _clearChat(Chat chat) async {
    final ok = await _confirm('Очистить чат?', 'Все сообщения пропадут у вас.');
    if (!ok) return;
    await widget.api.clearChat(chat.id);
    unawaited(_cache.clearMessages(chat.id));
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
    unawaited(_cache.saveChats(_chats));
    unawaited(_cache.clearMessages(chat.id));
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
    final activeMessages =
        chat.id == _activeChatId ? _messages : const <Message>[];
    showDialog<void>(
      context: context,
      builder: (_) => _ChatProfileDialog(
        serverUrl: widget.serverUrl,
        chat: chat,
        messages: activeMessages,
        currentUserId: _currentUser.id,
        onlineUserIds: _onlineUserIds,
      ),
    );
  }

  void _showAccountDialog() {
    showDialog<void>(
      context: context,
      builder: (_) => _AccountDialog(
        user: _currentUser,
        api: widget.api,
        serverUrl: widget.serverUrl,
        themeMode: widget.themeMode,
        onThemeModeChanged: widget.onThemeModeChanged,
        uiScale: widget.uiScale,
        onUiScaleChanged: widget.onUiScaleChanged,
        onProfileUpdated: (user) => setState(() => _currentUser = user),
        onLogout: widget.onLogout,
      ),
    );
  }

  void _scrollToBottom({bool instant = false}) {
    void scroll() {
      if (!_messageScrollController.hasClients) return;
      final target = _messageScrollController.position.maxScrollExtent;
      final current = _messageScrollController.offset;
      if ((target - current).abs() < 2) return;
      if (instant) {
        _messageScrollController.jumpTo(target);
        return;
      }
      unawaited(
        _messageScrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        ),
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      scroll();
    });
  }

  bool _isNearMessageBottom() {
    if (!_messageScrollController.hasClients) return true;
    final position = _messageScrollController.position;
    return position.maxScrollExtent - position.pixels < 120;
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
    final activeCustomFolder = _customFolderById(_activeCustomFolderId);
    final folderChats = activeCustomFolder == null
        ? _chats
        : _chats
            .where((chat) => activeCustomFolder.chatIds.contains(chat.id))
            .toList(growable: false);
    final visibleChats = query.isEmpty
        ? folderChats
        : folderChats
            .where((chat) => chat.title.toLowerCase().contains(query))
            .toList(growable: false);
    final allUnread =
        _chats.where((chat) => (chat.unread[_currentUser.id] ?? 0) > 0).length;
    final unreadByCustomFolder = {
      for (final folder in _customFolders)
        folder.id: _chats
            .where((chat) => folder.chatIds.contains(chat.id))
            .where((chat) => (chat.unread[_currentUser.id] ?? 0) > 0)
            .length,
    };

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF24262B).withValues(alpha: 0.98),
              const Color(0xFF181A1F),
              const Color(0xFF111215),
            ],
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 352,
              child: _Sidebar(
                user: _currentUser,
                serverUrl: widget.serverUrl,
                chats: visibleChats,
                userSearchResults: _userSearchResults,
                customFolders: _customFolders,
                activeCustomFolderId: _activeCustomFolderId,
                allUnread: allUnread,
                unreadByCustomFolder: unreadByCustomFolder,
                activeChatId: _activeChatId,
                loading: _loadingChats,
                searchingUsers: _searchingUsers,
                connected: _socketConnected,
                onlineUserIds: _onlineUserIds,
                userSearchError: _userSearchError,
                searchController: _chatSearchController,
                onSearchChanged: _handleSidebarSearchChanged,
                onCreateSpace: _showCreateSpaceDialog,
                onSelectAllChats: () => setState(() {
                  _activeCustomFolderId = null;
                  _userSearchResults = const [];
                  _userSearchError = null;
                  _searchingUsers = false;
                }),
                onSelectCustomFolder: (folderId) => setState(() {
                  _activeCustomFolderId = folderId;
                  _userSearchResults = const [];
                  _userSearchError = null;
                  _searchingUsers = false;
                }),
                onCreateFolder: _showCreateFolderDialog,
                onOpenAccount: _showAccountDialog,
                onSelectChat: _selectChat,
                onStartDirectChat: _startDirectChat,
                onToggleMute: _toggleMute,
                onTogglePinTop: _togglePinTop,
                onToggleVerified: _toggleChatVerified,
                onClearChat: _clearChat,
                onDeleteChat: _deleteChat,
              ),
            ),
            Container(width: 1, color: Colors.white.withValues(alpha: 0.07)),
            Expanded(
              child: _ChatPane(
                chat: _activeChat,
                serverUrl: widget.serverUrl,
                user: _currentUser,
                messages: _messages,
                pinnedMessage: _pinnedMessage,
                typingNames: _typingNames.values.toList(growable: false),
                onlineUserIds: _onlineUserIds,
                loading: _loadingMessages,
                sendingMedia: _sendingMedia,
                recordingVoice: _recordingVoice,
                recordingVideoNote: _recordingVideoNote,
                recordKind: _recordKind,
                recordingMs: _recordingMs,
                recordingStartedAt: _recordingStartedAt,
                recordingLevel: _recordingLevel,
                error: _error,
                replyTo: _replyTo,
                editing: _editing,
                messageController: _messageController,
                messageFocusNode: _messageFocusNode,
                scrollController: _messageScrollController,
                onSend: _sendMessage,
                onAttach: _pickAndSendAttachment,
                onDropFiles: _sendDroppedFiles,
                onPaste: _pasteIntoComposer,
                onToggleRecordKind: _toggleRecordKind,
                onStartRecording: _startSelectedRecording,
                onFinishRecording: _finishRecording,
                onCancelRecording: _cancelRecording,
                onVideoNoteCameraReady: _handleVideoNoteCameraReady,
                onCancelComposerMode: _cancelComposerMode,
                onTyping: _notifyTyping,
                onOpenProfile: _openChatProfile,
                onToggleMute: _toggleMute,
                onTogglePinTop: _togglePinTop,
                onToggleVerified: _toggleChatVerified,
                onClearChat: _clearChat,
                onDeleteChat: _deleteChat,
                onUnpinMessage: () => _setPinnedMessage(null),
                onReply: (message) {
                  setState(() {
                    _editing = null;
                    _replyTo = message;
                  });
                  _focusComposer();
                },
                onEdit: _startEdit,
                onDeleteMessage: (message) {
                  final chatId = _activeChatId;
                  if (chatId == null) return;
                  _socket?.deleteMessage(
                    chatId: chatId,
                    messageId: message.id,
                  );
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
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.user,
    required this.serverUrl,
    required this.chats,
    required this.userSearchResults,
    required this.customFolders,
    required this.activeCustomFolderId,
    required this.allUnread,
    required this.unreadByCustomFolder,
    required this.activeChatId,
    required this.loading,
    required this.searchingUsers,
    required this.connected,
    required this.onlineUserIds,
    required this.userSearchError,
    required this.searchController,
    required this.onSearchChanged,
    required this.onCreateSpace,
    required this.onSelectAllChats,
    required this.onSelectCustomFolder,
    required this.onCreateFolder,
    required this.onOpenAccount,
    required this.onSelectChat,
    required this.onStartDirectChat,
    required this.onToggleMute,
    required this.onTogglePinTop,
    required this.onToggleVerified,
    required this.onClearChat,
    required this.onDeleteChat,
  });

  final User user;
  final String serverUrl;
  final List<Chat> chats;
  final List<DirectoryUser> userSearchResults;
  final List<_CustomChatFolder> customFolders;
  final String? activeCustomFolderId;
  final int allUnread;
  final Map<String, int> unreadByCustomFolder;
  final String? activeChatId;
  final bool loading;
  final bool searchingUsers;
  final bool connected;
  final Set<String> onlineUserIds;
  final String? userSearchError;
  final TextEditingController searchController;
  final VoidCallback onSearchChanged;
  final VoidCallback onCreateSpace;
  final VoidCallback onSelectAllChats;
  final ValueChanged<String> onSelectCustomFolder;
  final VoidCallback onCreateFolder;
  final VoidCallback onOpenAccount;
  final ValueChanged<String> onSelectChat;
  final ValueChanged<DirectoryUser> onStartDirectChat;
  final ValueChanged<Chat> onToggleMute;
  final ValueChanged<Chat> onTogglePinTop;
  final ValueChanged<Chat> onToggleVerified;
  final ValueChanged<Chat> onClearChat;
  final ValueChanged<Chat> onDeleteChat;

  @override
  Widget build(BuildContext context) {
    final hasSearch = searchController.text.trim().isNotEmpty;
    final showUserSearch = hasSearch &&
        (searchingUsers ||
            userSearchResults.isNotEmpty ||
            userSearchError != null);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF24262C).withValues(alpha: 0.95),
            const Color(0xFF181A1F).withValues(alpha: 0.93),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(12, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
            child: Row(
              children: [
                InkWell(
                  onTap: onOpenAccount,
                  customBorder: const CircleBorder(),
                  child: BrenksAvatar(
                    title: user.title,
                    imageUrl: user.avatarUrl,
                    baseUrl: serverUrl,
                    size: 46,
                  ),
                ),
                const SizedBox(width: 12),
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
                            fontSize: 19,
                            letterSpacing: 0,
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
                Row(
                  children: [
                    _SoftIconButton(
                      tooltip: 'Создать группу или канал',
                      onPressed: onCreateSpace,
                      icon: Icons.add_comment_rounded,
                    ),
                    const SizedBox(width: 6),
                    _SoftIconButton(
                      tooltip: 'Профиль и настройки',
                      onPressed: onOpenAccount,
                      icon: Icons.tune_rounded,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: _GlassSurface(
              radius: 28,
              padding: EdgeInsets.zero,
              color: const Color(0x6614171C),
              child: TextField(
                controller: searchController,
                onChanged: (_) => onSearchChanged(),
                decoration: const InputDecoration(
                  hintText: 'Поиск чатов или @username',
                  prefixIcon: Icon(Icons.search_rounded),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: _ChatFolderBar(
              customFolders: customFolders,
              activeCustomFolderId: activeCustomFolderId,
              allUnread: allUnread,
              unreadByCustomFolder: unreadByCustomFolder,
              onSelectAll: onSelectAllChats,
              onSelectCustom: onSelectCustomFolder,
              onCreateFolder: onCreateFolder,
            ),
          ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : Scrollbar(
                    thumbVisibility: false,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
                      children: [
                        if (showUserSearch) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
                            child: Text(
                              'Пользователи',
                              style: TextStyle(
                                color: muted.withValues(alpha: 0.9),
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (searchingUsers)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            ),
                          if (!searchingUsers && userSearchError != null)
                            _SidebarHint(text: 'Не удалось выполнить поиск'),
                          if (!searchingUsers &&
                              userSearchError == null &&
                              userSearchResults.isEmpty)
                            _SidebarHint(text: 'Пользователь не найден'),
                          for (final result in userSearchResults) ...[
                            _UserSearchTile(
                              user: result,
                              serverUrl: serverUrl,
                              onTap: () => onStartDirectChat(result),
                            ),
                            const SizedBox(height: 6),
                          ],
                          const SizedBox(height: 8),
                          Divider(color: Colors.white.withValues(alpha: 0.06)),
                          const SizedBox(height: 8),
                        ],
                        if (chats.isEmpty)
                          EmptyState(
                            title: hasSearch
                                ? 'Чаты не найдены'
                                : 'Чатов пока нет',
                            subtitle: hasSearch
                                ? 'Можно найти человека по @username.'
                                : 'Найдите пользователя через поиск выше.',
                          )
                        else
                          for (final chat in chats) ...[
                            _ChatTile(
                              key: ValueKey('chat-${chat.id}'),
                              chat: chat,
                              serverUrl: serverUrl,
                              selected: chat.id == activeChatId,
                              onlineUserIds: onlineUserIds,
                              currentUserId: user.id,
                              canVerify: user.isAdmin,
                              onTap: () => onSelectChat(chat.id),
                              onToggleMute: () => onToggleMute(chat),
                              onTogglePinTop: () => onTogglePinTop(chat),
                              onToggleVerified: () => onToggleVerified(chat),
                              onClearChat: () => onClearChat(chat),
                              onDeleteChat: () => onDeleteChat(chat),
                            ),
                            const SizedBox(height: 6),
                          ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SidebarHint extends StatelessWidget {
  const _SidebarHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: muted, fontSize: 13),
      ),
    );
  }
}

class _VerifiedBadge extends StatelessWidget {
  const _VerifiedBadge({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.96),
            const Color(0xFF8F6F2E),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.14),
            blurRadius: 10,
          ),
        ],
      ),
      child: Icon(
        Icons.check_rounded,
        size: size * 0.74,
        color: const Color(0xFF101318),
      ),
    );
  }
}

class _UserSearchTile extends StatelessWidget {
  const _UserSearchTile({
    required this.user,
    required this.serverUrl,
    required this.onTap,
  });

  final DirectoryUser user;
  final String serverUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _GlassSurface(
      padding: EdgeInsets.zero,
      radius: 20,
      color: const Color(0x8124272D),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          splashColor: accent.withValues(alpha: 0.055),
          highlightColor: Colors.white.withValues(alpha: 0.025),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                BrenksAvatar(
                  title: user.title,
                  imageUrl: user.avatarUrl,
                  baseUrl: serverUrl,
                  size: 42,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '@${user.username}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded,
                    size: 15, color: muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatFolderBar extends StatelessWidget {
  const _ChatFolderBar({
    required this.customFolders,
    required this.activeCustomFolderId,
    required this.allUnread,
    required this.unreadByCustomFolder,
    required this.onSelectAll,
    required this.onSelectCustom,
    required this.onCreateFolder,
  });

  final List<_CustomChatFolder> customFolders;
  final String? activeCustomFolderId;
  final int allUnread;
  final Map<String, int> unreadByCustomFolder;
  final VoidCallback onSelectAll;
  final ValueChanged<String> onSelectCustom;
  final VoidCallback onCreateFolder;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: customFolders.length + 2,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _ChatFolderChip(
              label: 'Все',
              selected: activeCustomFolderId == null,
              unreadCount: allUnread,
              onTap: onSelectAll,
            );
          }
          if (index == customFolders.length + 1) {
            return _NewFolderChip(onTap: onCreateFolder);
          }
          final folder = customFolders[index - 1];
          return _ChatFolderChip(
            label: folder.name,
            selected: activeCustomFolderId == folder.id,
            unreadCount: unreadByCustomFolder[folder.id] ?? 0,
            onTap: () => onSelectCustom(folder.id),
          );
        },
      ),
    );
  }
}

class _ChatFolderChip extends StatelessWidget {
  const _ChatFolderChip({
    required this.label,
    required this.selected,
    required this.unreadCount,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final int unreadCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: selected
            ? accent.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected
              ? accent.withValues(alpha: 0.24)
              : Colors.white.withValues(alpha: 0.07),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: selected ? text : muted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (unreadCount > 0) ...[
                const SizedBox(width: 7),
                Container(
                  constraints: const BoxConstraints(minWidth: 20),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color:
                        selected ? accent : Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    unreadCount > 99 ? '99+' : '$unreadCount',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: selected ? const Color(0xFF101318) : text,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NewFolderChip extends StatelessWidget {
  const _NewFolderChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Создать папку',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.035),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          ),
          child: const Icon(Icons.add_rounded, size: 20, color: muted),
        ),
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({
    super.key,
    required this.chat,
    required this.serverUrl,
    required this.selected,
    required this.onlineUserIds,
    required this.currentUserId,
    required this.canVerify,
    required this.onTap,
    required this.onToggleMute,
    required this.onTogglePinTop,
    required this.onToggleVerified,
    required this.onClearChat,
    required this.onDeleteChat,
  });

  final Chat chat;
  final String serverUrl;
  final bool selected;
  final Set<String> onlineUserIds;
  final String currentUserId;
  final bool canVerify;
  final VoidCallback onTap;
  final VoidCallback onToggleMute;
  final VoidCallback onTogglePinTop;
  final VoidCallback onToggleVerified;
  final VoidCallback onClearChat;
  final VoidCallback onDeleteChat;

  @override
  Widget build(BuildContext context) {
    final unread = chat.unread[currentUserId] ?? 0;
    final peerOnline = chat.type == ChatType.direct &&
        chat.participantIds.any(
          (id) => id != currentUserId && onlineUserIds.contains(id),
        );
    return GestureDetector(
      onSecondaryTapDown: (details) =>
          _showChatContextMenu(context, details.globalPosition),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: selected
              ? const Color(0xFF2C2B29).withValues(alpha: 0.84)
              : Colors.white.withValues(alpha: 0.018),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.052),
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ]
              : const [],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            splashColor: accent.withValues(alpha: 0.055),
            highlightColor: Colors.white.withValues(alpha: 0.025),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Stack(
                    children: [
                      BrenksAvatar(
                        title: chat.titleFor(currentUserId),
                        imageUrl: chat.avatarFor(currentUserId),
                        baseUrl: serverUrl,
                        size: 46,
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
                                color: bg,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (chat.pinnedToTop) ...[
                              const Icon(
                                Icons.push_pin_rounded,
                                size: 15,
                                color: muted,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Expanded(
                              child: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      chat.titleFor(currentUserId),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  if (chat.verified) ...[
                                    const SizedBox(width: 5),
                                    const _VerifiedBadge(size: 15),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _lastMessageLabel(chat.lastMessage?.text),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color:
                                selected ? text.withValues(alpha: 0.74) : muted,
                            fontSize: 13.5,
                          ),
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
                          style: TextStyle(
                            color:
                                selected ? text.withValues(alpha: 0.66) : muted,
                            fontSize: 12,
                          ),
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
                            boxShadow: [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.18),
                                blurRadius: 14,
                                offset: const Offset(0, 6),
                              ),
                            ],
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
        ),
      ),
    );
  }

  Future<void> _showChatContextMenu(
      BuildContext context, Offset position) async {
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'pin',
          child: Text(chat.pinnedToTop ? 'Открепить чат' : 'Закрепить чат'),
        ),
        PopupMenuItem(
          value: 'mute',
          child: Text(chat.muted ? 'Включить звук' : 'Выключить звук'),
        ),
        if (canVerify && chat.type == ChatType.channel)
          PopupMenuItem(
            value: 'verify',
            child: Text(chat.verified ? 'Снять галочку' : 'Выдать галочку'),
          ),
        const PopupMenuItem(value: 'clear', child: Text('Очистить историю')),
        const PopupMenuItem(
          value: 'delete',
          child: Text('Удалить чат', style: TextStyle(color: danger)),
        ),
      ],
    );

    switch (value) {
      case 'pin':
        onTogglePinTop();
      case 'mute':
        onToggleMute();
      case 'verify':
        onToggleVerified();
      case 'clear':
        onClearChat();
      case 'delete':
        onDeleteChat();
    }
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
    required this.onlineUserIds,
    required this.loading,
    required this.sendingMedia,
    required this.recordingVoice,
    required this.recordingVideoNote,
    required this.recordKind,
    required this.recordingMs,
    required this.recordingStartedAt,
    required this.recordingLevel,
    required this.error,
    required this.replyTo,
    required this.editing,
    required this.messageController,
    required this.messageFocusNode,
    required this.scrollController,
    required this.onSend,
    required this.onAttach,
    required this.onDropFiles,
    required this.onPaste,
    required this.onToggleRecordKind,
    required this.onStartRecording,
    required this.onFinishRecording,
    required this.onCancelRecording,
    required this.onVideoNoteCameraReady,
    required this.onCancelComposerMode,
    required this.onTyping,
    required this.onOpenProfile,
    required this.onToggleMute,
    required this.onTogglePinTop,
    required this.onToggleVerified,
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
  final Set<String> onlineUserIds;
  final bool loading;
  final bool sendingMedia;
  final bool recordingVoice;
  final bool recordingVideoNote;
  final _RecordKind recordKind;
  final int recordingMs;
  final int? recordingStartedAt;
  final double recordingLevel;
  final String? error;
  final Message? replyTo;
  final Message? editing;
  final TextEditingController messageController;
  final FocusNode messageFocusNode;
  final ScrollController scrollController;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final ValueChanged<List<DropItem>> onDropFiles;
  final VoidCallback onPaste;
  final VoidCallback onToggleRecordKind;
  final VoidCallback onStartRecording;
  final VoidCallback onFinishRecording;
  final VoidCallback onCancelRecording;
  final ValueChanged<CameraMacOSController> onVideoNoteCameraReady;
  final VoidCallback onCancelComposerMode;
  final ValueChanged<bool> onTyping;
  final ValueChanged<Chat> onOpenProfile;
  final ValueChanged<Chat> onToggleMute;
  final ValueChanged<Chat> onTogglePinTop;
  final ValueChanged<Chat> onToggleVerified;
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

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          children: [
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (child, animation) {
        final offset = Tween<Offset>(
          begin: const Offset(0.018, 0),
          end: Offset.zero,
        ).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offset, child: child),
        );
      },
      child: _DropSendTarget(
        key: ValueKey(chat.id),
        enabled: !sendingMedia && !recordingVoice && !recordingVideoNote,
        onDropFiles: onDropFiles,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF24272D),
                Color(0xFF1C1F24),
                Color(0xFF15171B),
              ],
            ),
          ),
          child: Stack(
            children: [
              const Positioned.fill(
                  child: CustomPaint(painter: _PatternPainter())),
              Column(
                children: [
                  _ChatHeader(
                    chat: chat,
                    serverUrl: serverUrl,
                    currentUserId: user.id,
                    isAdmin: user.isAdmin,
                    typingNames: typingNames,
                    onlineUserIds: onlineUserIds,
                    onOpenProfile: () => onOpenProfile(chat),
                    onToggleMute: () => onToggleMute(chat),
                    onTogglePinTop: () => onTogglePinTop(chat),
                    onToggleVerified: () => onToggleVerified(chat),
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
                      child:
                          Text(error!, style: const TextStyle(color: danger)),
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
                                padding:
                                    const EdgeInsets.fromLTRB(20, 16, 20, 18),
                                itemCount: messages.length,
                                itemBuilder: (context, index) {
                                  final message = messages[index];
                                  final own = message.senderId == user.id;
                                  return _MessageBubble(
                                    message: message,
                                    serverUrl: serverUrl,
                                    own: own,
                                    readByRecipients: own
                                        ? _isOwnMessageReadByRecipients(
                                            chat: chat,
                                            messages: messages,
                                            index: index,
                                            currentUserId: user.id,
                                          )
                                        : null,
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
                  _Composer(
                    replyTo: replyTo,
                    editing: editing,
                    sendingMedia: sendingMedia,
                    recordingVoice: recordingVoice,
                    recordingVideoNote: recordingVideoNote,
                    recordKind: recordKind,
                    recordingMs: recordingMs,
                    recordingStartedAt: recordingStartedAt,
                    recordingLevel: recordingLevel,
                    controller: messageController,
                    focusNode: messageFocusNode,
                    onAttach: onAttach,
                    onPaste: onPaste,
                    onSend: onSend,
                    onToggleRecordKind: onToggleRecordKind,
                    onStartRecording: onStartRecording,
                    onFinishRecording: onFinishRecording,
                    onCancelRecording: onCancelRecording,
                    onCancelMode: onCancelComposerMode,
                    onTyping: onTyping,
                  ),
                ],
              ),
              if (recordingVideoNote)
                _VideoNoteRecordingOverlay(
                  onCameraReady: onVideoNoteCameraReady,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DropSendTarget extends StatefulWidget {
  const _DropSendTarget({
    super.key,
    required this.enabled,
    required this.onDropFiles,
    required this.child,
  });

  final bool enabled;
  final ValueChanged<List<DropItem>> onDropFiles;
  final Widget child;

  @override
  State<_DropSendTarget> createState() => _DropSendTargetState();
}

class _DropSendTargetState extends State<_DropSendTarget> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      enable: widget.enabled,
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (details) {
        setState(() => _dragging = false);
        widget.onDropFiles(details.files);
      },
      child: Stack(
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _dragging ? 1 : 0,
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                child: Container(
                  margin: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xDD17191D),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: accent.withValues(alpha: 0.45),
                      width: 1.4,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.09),
                        blurRadius: 36,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 18,
                      ),
                      decoration: BoxDecoration(
                        color: panel.withValues(alpha: 0.82),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.cloud_upload_rounded,
                            color: accent,
                            size: 32,
                          ),
                          SizedBox(width: 13),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Отпустите файлы',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                'Фото отправятся как изображения, остальное как файлы',
                                style: TextStyle(color: muted),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
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
    required this.currentUserId,
    required this.isAdmin,
    required this.typingNames,
    required this.onlineUserIds,
    required this.onOpenProfile,
    required this.onToggleMute,
    required this.onTogglePinTop,
    required this.onToggleVerified,
    required this.onClearChat,
    required this.onDeleteChat,
  });

  final Chat chat;
  final String serverUrl;
  final String currentUserId;
  final bool isAdmin;
  final List<String> typingNames;
  final Set<String> onlineUserIds;
  final VoidCallback onOpenProfile;
  final VoidCallback onToggleMute;
  final VoidCallback onTogglePinTop;
  final VoidCallback onToggleVerified;
  final VoidCallback onClearChat;
  final VoidCallback onDeleteChat;

  @override
  Widget build(BuildContext context) {
    final peer = chat.peerFor(currentUserId);
    final peerOnline = peer != null && onlineUserIds.contains(peer.id);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: 66,
          padding: const EdgeInsets.symmetric(horizontal: 17),
          decoration: BoxDecoration(
            color: const Color(0xDC191B20),
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.075)),
            ),
          ),
          child: Row(
            children: [
              InkWell(
                onTap: onOpenProfile,
                customBorder: const CircleBorder(),
                child: BrenksAvatar(
                  title: chat.titleFor(currentUserId),
                  imageUrl: chat.avatarFor(currentUserId),
                  baseUrl: serverUrl,
                  size: 44,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: onOpenProfile,
                  borderRadius: BorderRadius.circular(12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              chat.titleFor(currentUserId),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 18,
                                letterSpacing: 0,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          if (chat.verified) ...[
                            const SizedBox(width: 7),
                            const _VerifiedBadge(size: 18),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      _TypingSubtitle(
                        idleText: _chatSubtitle(
                          chat,
                          directPeerOnline: peerOnline,
                        ),
                        typingNames: typingNames,
                        showNames: chat.type != ChatType.direct,
                      ),
                    ],
                  ),
                ),
              ),
              _SoftIconButton(
                tooltip: 'Аудиозвонок будет следующим этапом',
                onPressed: null,
                icon: Icons.call_rounded,
              ),
              const SizedBox(width: 6),
              _SoftIconButton(
                tooltip: 'Видеозвонок будет следующим этапом',
                onPressed: null,
                icon: Icons.videocam_rounded,
              ),
              const SizedBox(width: 6),
              PopupMenuButton<String>(
                tooltip: 'Меню чата',
                offset: const Offset(0, 48),
                onSelected: (value) {
                  switch (value) {
                    case 'profile':
                      onOpenProfile();
                    case 'mute':
                      onToggleMute();
                    case 'pin':
                      onTogglePinTop();
                    case 'verify':
                      onToggleVerified();
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
                    child:
                        Text(chat.muted ? 'Включить звук' : 'Выключить звук'),
                  ),
                  PopupMenuItem(
                    value: 'pin',
                    child: Text(
                      chat.pinnedToTop ? 'Открепить чат' : 'Закрепить чат',
                    ),
                  ),
                  if (isAdmin && chat.type == ChatType.channel)
                    PopupMenuItem(
                      value: 'verify',
                      child: Text(
                        chat.verified ? 'Снять галочку' : 'Выдать галочку',
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'clear',
                    child: Text('Очистить чат'),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Удалить', style: TextStyle(color: danger)),
                  ),
                ],
                child: Container(
                  width: 42,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.045),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.075),
                    ),
                  ),
                  child: const Icon(Icons.more_vert_rounded, color: muted),
                ),
              ),
            ],
          ),
        ),
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
    return _GlassSurface(
      margin: const EdgeInsets.fromLTRB(18, 12, 18, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      radius: 18,
      color: const Color(0xA1282A2F),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.13),
              shape: BoxShape.circle,
              border: Border.all(color: accent.withValues(alpha: 0.18)),
            ),
            child: const Icon(Icons.push_pin_rounded, color: accent, size: 17),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Закреплено',
                  style: TextStyle(
                    color: accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  _messagePreview(message),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
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

class _TypingSubtitle extends StatefulWidget {
  const _TypingSubtitle({
    required this.idleText,
    required this.typingNames,
    required this.showNames,
  });

  final String idleText;
  final List<String> typingNames;
  final bool showNames;

  @override
  State<_TypingSubtitle> createState() => _TypingSubtitleState();
}

class _TypingSubtitleState extends State<_TypingSubtitle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
    );
    if (widget.typingNames.isNotEmpty) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _TypingSubtitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.typingNames.isNotEmpty && !_controller.isAnimating) {
      _controller.repeat();
    } else if (widget.typingNames.isEmpty && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final typing = widget.typingNames.isNotEmpty;
    final label = typing
        ? widget.showNames
            ? '${widget.typingNames.join(', ')} печатает'
            : 'печатает'
        : widget.idleText;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: typing
          ? Row(
              key: ValueKey('typing-${widget.typingNames.join(',')}'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(3, (index) {
                        final phase = (_controller.value + index / 3) % 1;
                        final opacity = 0.34 + math.sin(phase * math.pi) * 0.66;
                        final y = -math.sin(phase * math.pi) * 2.5;
                        return Transform.translate(
                          offset: Offset(0, y),
                          child: Opacity(
                            opacity: opacity.clamp(0.0, 1.0),
                            child: const Text(
                              '.',
                              style: TextStyle(
                                color: accent,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        );
                      }),
                    );
                  },
                ),
              ],
            )
          : Text(
              widget.idleText,
              key: ValueKey('idle-${widget.idleText}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: muted),
            ),
    );
  }
}

class _VoiceRecordingBar extends StatefulWidget {
  const _VoiceRecordingBar({
    required this.startedAt,
    required this.fallbackMs,
    required this.kind,
    required this.level,
    required this.onCancel,
    required this.onFinish,
  });

  final int? startedAt;
  final int fallbackMs;
  final _RecordKind kind;
  final double level;
  final VoidCallback onCancel;
  final VoidCallback onFinish;

  @override
  State<_VoiceRecordingBar> createState() => _VoiceRecordingBarState();
}

class _VoiceRecordingBarState extends State<_VoiceRecordingBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _waveController;
  late final Timer _clock;
  int _elapsedMs = 0;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1450),
    )..repeat();
    _updateElapsed();
    _clock = Timer.periodic(
      const Duration(milliseconds: 120),
      (_) => _updateElapsed(),
    );
  }

  @override
  void didUpdateWidget(covariant _VoiceRecordingBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startedAt != widget.startedAt) _updateElapsed();
  }

  @override
  void dispose() {
    _clock.cancel();
    _waveController.dispose();
    super.dispose();
  }

  void _updateElapsed() {
    final startedAt = widget.startedAt;
    final next = startedAt == null
        ? widget.fallbackMs
        : DateTime.now().millisecondsSinceEpoch - startedAt;
    if (next ~/ 100 == _elapsedMs ~/ 100) return;
    setState(() => _elapsedMs = next);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: _GlassSurface(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        radius: 22,
        color: const Color(0xB021242A),
        child: Row(
          children: [
            _RecordingLeading(
              kind: widget.kind,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFF7E7E),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.kind == _RecordKind.videoNote
                            ? 'Видеокружок'
                            : 'Голосовое',
                        style: const TextStyle(
                          color: text,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatDuration(_elapsedMs),
                        style: const TextStyle(
                          color: muted,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 24,
                    child: AnimatedBuilder(
                      animation: _waveController,
                      builder: (context, _) {
                        return CustomPaint(
                          painter: _RecordingWavePainter(
                            progress: _waveController.value,
                            level: widget.level,
                          ),
                          size: Size.infinite,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            TextButton.icon(
              onPressed: widget.onCancel,
              icon: const Icon(Icons.close_rounded),
              label: const Text('Отмена'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: widget.onFinish,
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text('Отправить'),
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: const Color(0xFF101318),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordingLeading extends StatelessWidget {
  const _RecordingLeading({
    required this.kind,
  });

  final _RecordKind kind;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.13),
        shape: BoxShape.circle,
        border: Border.all(color: accent.withValues(alpha: 0.26)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Icon(
        kind == _RecordKind.videoNote
            ? Icons.videocam_rounded
            : Icons.mic_rounded,
        color: accent,
        size: 21,
      ),
    );
  }
}

class _VideoNoteRecordingOverlay extends StatelessWidget {
  const _VideoNoteRecordingOverlay({required this.onCameraReady});

  final ValueChanged<CameraMacOSController> onCameraReady;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                width: 272,
                height: 272,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      accent.withValues(alpha: 0.22),
                      const Color(0xF0181A1F),
                    ],
                  ),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.48),
                    width: 3,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.36),
                      blurRadius: 46,
                      offset: const Offset(0, 24),
                    ),
                    BoxShadow(
                      color: accent.withValues(alpha: 0.16),
                      blurRadius: 32,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: io.Platform.isMacOS
                      ? CameraMacOSView(
                          fit: BoxFit.cover,
                          cameraMode: CameraMacOSMode.video,
                          resolution: PictureResolution.medium,
                          videoFormat: VideoFormat.mp4,
                          isVideoMirrored: false,
                          onCameraInizialized: onCameraReady,
                          onCameraLoading: (_) => const ColoredBox(
                            color: Color(0xFF181A1F),
                            child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      : const ColoredBox(
                          color: Color(0xFF181A1F),
                          child: Icon(
                            Icons.videocam_off_rounded,
                            color: muted,
                            size: 42,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecordingWavePainter extends CustomPainter {
  const _RecordingWavePainter({
    required this.progress,
    required this.level,
  });

  final double progress;
  final double level;

  @override
  void paint(Canvas canvas, Size size) {
    final activePaint = Paint()
      ..color = accent.withValues(alpha: 0.92)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5;
    final idlePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.095)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5;

    const bars = 34;
    final gap = size.width / bars;
    final center = size.height / 2;
    for (var i = 0; i < bars; i++) {
      final phase = (i / bars + progress) * 6.28318;
      final normalized = (math.sin(phase) + 1) / 2;
      final energy = (0.24 + level * 0.92).clamp(0.18, 1.0);
      final height = 4 + normalized * (size.height - 6) * energy;
      final x = i * gap + gap / 2;
      final paint = i < bars * 0.72 ? activePaint : idlePaint;
      canvas.drawLine(
        Offset(x, center - height / 2),
        Offset(x, center + height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RecordingWavePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.level != level;
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.replyTo,
    required this.editing,
    required this.sendingMedia,
    required this.recordingVoice,
    required this.recordingVideoNote,
    required this.recordKind,
    required this.recordingMs,
    required this.recordingStartedAt,
    required this.recordingLevel,
    required this.controller,
    required this.focusNode,
    required this.onAttach,
    required this.onPaste,
    required this.onSend,
    required this.onToggleRecordKind,
    required this.onStartRecording,
    required this.onFinishRecording,
    required this.onCancelRecording,
    required this.onCancelMode,
    required this.onTyping,
  });

  final Message? replyTo;
  final Message? editing;
  final bool sendingMedia;
  final bool recordingVoice;
  final bool recordingVideoNote;
  final _RecordKind recordKind;
  final int recordingMs;
  final int? recordingStartedAt;
  final double recordingLevel;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onAttach;
  final VoidCallback onPaste;
  final VoidCallback onSend;
  final VoidCallback onToggleRecordKind;
  final VoidCallback onStartRecording;
  final VoidCallback onFinishRecording;
  final VoidCallback onCancelRecording;
  final VoidCallback onCancelMode;
  final ValueChanged<bool> onTyping;

  @override
  Widget build(BuildContext context) {
    final modeMessage = editing ?? replyTo;
    final modeTitle = editing != null ? 'Редактирование' : 'Ответ';
    final recording = recordingVoice || recordingVideoNote;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          decoration: BoxDecoration(
            color: const Color(0xD0181A1E),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.075)),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (recording)
                _VoiceRecordingBar(
                  startedAt: recordingStartedAt,
                  fallbackMs: recordingMs,
                  kind: recordingVideoNote ? _RecordKind.videoNote : recordKind,
                  level: recordingLevel,
                  onCancel: onCancelRecording,
                  onFinish: onFinishRecording,
                ),
              if (!recording && modeMessage != null)
                _GlassSurface(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  radius: 18,
                  color: const Color(0x80272A30),
                  child: Row(
                    children: [
                      Container(
                        width: 3,
                        height: 38,
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
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: recording
                    ? const SizedBox.shrink()
                    : _ComposerInputBar(
                        controller: controller,
                        focusNode: focusNode,
                        editing: editing,
                        sendingMedia: sendingMedia,
                        recordKind: recordKind,
                        onAttach: onAttach,
                        onPaste: onPaste,
                        onSend: onSend,
                        onToggleRecordKind: onToggleRecordKind,
                        onStartRecording: onStartRecording,
                        onTyping: onTyping,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComposerInputBar extends StatelessWidget {
  const _ComposerInputBar({
    required this.controller,
    required this.focusNode,
    required this.editing,
    required this.sendingMedia,
    required this.recordKind,
    required this.onAttach,
    required this.onPaste,
    required this.onSend,
    required this.onToggleRecordKind,
    required this.onStartRecording,
    required this.onTyping,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final Message? editing;
  final bool sendingMedia;
  final _RecordKind recordKind;
  final VoidCallback onAttach;
  final VoidCallback onPaste;
  final VoidCallback onSend;
  final VoidCallback onToggleRecordKind;
  final VoidCallback onStartRecording;
  final ValueChanged<bool> onTyping;

  @override
  Widget build(BuildContext context) {
    return _GlassSurface(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      radius: 30,
      color: const Color(0xA51B1D22),
      child: Row(
        children: [
          _SoftIconButton(
            tooltip: 'Прикрепить файл',
            onPressed: sendingMedia ? null : onAttach,
            icon: Icons.attach_file_rounded,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter): () {
                  if (!sendingMedia) onSend();
                },
                const SingleActivator(LogicalKeyboardKey.keyV, meta: true): () {
                  if (!sendingMedia) onPaste();
                },
                const SingleActivator(LogicalKeyboardKey.keyV, control: true):
                    () {
                  if (!sendingMedia) onPaste();
                },
              },
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                minLines: 1,
                maxLines: 5,
                onChanged: (value) => onTyping(value.trim().isNotEmpty),
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: 'Сообщение',
                  filled: true,
                  fillColor: const Color(0x77121418),
                  suffixIcon: sendingMedia
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(
                      color: accent.withValues(alpha: 0.18),
                      width: 1.1,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 9),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final hasText = value.text.trim().isNotEmpty;
              final shouldSend = hasText || editing != null;
              return _HoldRecordButton(
                disabled: sendingMedia,
                shouldSend: shouldSend,
                recordKind: recordKind,
                onTap: shouldSend ? onSend : onToggleRecordKind,
                onLongPressStart: shouldSend ? null : onStartRecording,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HoldRecordButton extends StatefulWidget {
  const _HoldRecordButton({
    required this.disabled,
    required this.shouldSend,
    required this.recordKind,
    required this.onTap,
    required this.onLongPressStart,
  });

  final bool disabled;
  final bool shouldSend;
  final _RecordKind recordKind;
  final VoidCallback onTap;
  final VoidCallback? onLongPressStart;

  @override
  State<_HoldRecordButton> createState() => _HoldRecordButtonState();
}

class _HoldRecordButtonState extends State<_HoldRecordButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.recordKind == _RecordKind.videoNote;
    final icon = widget.shouldSend
        ? Icons.send_rounded
        : isVideo
            ? Icons.radio_button_checked_rounded
            : Icons.mic_rounded;
    final tooltip = widget.shouldSend
        ? 'Отправить'
        : isVideo
            ? 'Клик — голосовое, зажать — записать кружок'
            : 'Клик — кружок, зажать — записать голосовое';
    final active = widget.shouldSend || _pressed;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.disabled ? null : widget.onTap,
        onLongPressStart: widget.disabled || widget.onLongPressStart == null
            ? null
            : (_) {
                setState(() => _pressed = true);
                widget.onLongPressStart!();
              },
        onLongPressEnd: (_) {
          if (mounted) setState(() => _pressed = false);
        },
        onLongPressCancel: () {
          if (mounted) setState(() => _pressed = false);
        },
        child: AnimatedScale(
          scale: _pressed ? 0.92 : 1,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            width: 50,
            height: 50,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.disabled
                  ? Colors.white.withValues(alpha: 0.08)
                  : active
                      ? accent
                      : const Color(0xFF2D261C),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.18),
                        blurRadius: 22,
                        offset: const Offset(0, 10),
                      ),
                    ]
                  : const [],
            ),
            child: Icon(
              icon,
              color: active ? const Color(0xFF101318) : accent,
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.serverUrl,
    required this.own,
    required this.readByRecipients,
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
  final bool? readByRecipients;
  final VoidCallback onReply;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onPin;
  final ValueChanged<String> onReaction;
  final ValueChanged<MessageMedia> onPlayVoice;

  @override
  Widget build(BuildContext context) {
    final media = message.media;
    final mediaOnly = !message.deleted &&
        message.text.trim().isEmpty &&
        message.imageUrl?.isNotEmpty != true &&
        (media?.kind == 'voice' || media?.kind == 'video_note');
    return GestureDetector(
      onDoubleTap: message.deleted ? null : onReply,
      onSecondaryTapDown: (details) {
        _showMessageMenu(context, details.globalPosition);
      },
      child: Align(
        alignment: own ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          margin: const EdgeInsets.only(bottom: 7),
          child: Column(
            crossAxisAlignment:
                own ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Container(
                padding: mediaOnly
                    ? EdgeInsets.zero
                    : const EdgeInsets.fromLTRB(13, 9, 12, 7),
                decoration: mediaOnly
                    ? null
                    : BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: own
                              ? [
                                  bubbleOut.withValues(alpha: 0.92),
                                  const Color(0xFF2C2B2B)
                                      .withValues(alpha: 0.92),
                                ]
                              : [
                                  bubbleIn.withValues(alpha: 0.9),
                                  const Color(0xFF292B30)
                                      .withValues(alpha: 0.9),
                                ],
                        ),
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(19),
                          topRight: const Radius.circular(19),
                          bottomLeft: Radius.circular(own ? 19 : 6),
                          bottomRight: Radius.circular(own ? 6 : 19),
                        ),
                        border: Border.all(
                          color: own
                              ? accent.withValues(alpha: 0.13)
                              : Colors.white.withValues(alpha: 0.095),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 18,
                            offset: const Offset(0, 10),
                          ),
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.05),
                            blurRadius: 0,
                            offset: const Offset(0, 1),
                          ),
                        ],
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
                        if (own && !message.deleted) ...[
                          const SizedBox(width: 5),
                          _MessageReadTicks(read: readByRecipients == true),
                        ],
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
                        color: const Color(0xCC282B31),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
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

class _MessageReadTicks extends StatelessWidget {
  const _MessageReadTicks({required this.read});

  final bool read;

  @override
  Widget build(BuildContext context) {
    final color = read ? accent : muted.withValues(alpha: 0.8);
    return SizedBox(
      width: 18,
      height: 13,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 210),
            curve: Curves.easeOutCubic,
            left: read ? 1 : 5,
            top: 0,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: read ? 1 : 0,
              child: Icon(
                Icons.check_rounded,
                size: 13,
                color: color.withValues(alpha: read ? 0.88 : 0),
              ),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 210),
            curve: Curves.easeOutCubic,
            left: read ? 7 : 3,
            top: 0,
            child: Icon(Icons.check_rounded, size: 13, color: color),
          ),
        ],
      ),
    );
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
            style: const TextStyle(color: textColorAlias, fontSize: 15),
          ),
        ],
        if (media == null &&
            message.imageUrl?.isNotEmpty != true &&
            text.isEmpty &&
            message.encryptedText)
          const _EncryptedMessageNotice(),
        if (media == null &&
            message.imageUrl?.isNotEmpty != true &&
            text.isEmpty &&
            !message.encryptedText)
          const Text('Сообщение', style: TextStyle(fontSize: 15)),
      ],
    );
  }
}

const textColorAlias = text;

class _EncryptedMessageNotice extends StatelessWidget {
  const _EncryptedMessageNotice();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.lock_outline_rounded, size: 17, color: muted),
        SizedBox(width: 7),
        Flexible(
          child: Text(
            'Старое зашифрованное сообщение',
            style: TextStyle(color: muted, fontSize: 15),
          ),
        ),
      ],
    );
  }
}

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
    return _GlassSurface(
      width: 260,
      padding: const EdgeInsets.all(12),
      radius: 18,
      color: const Color(0x9A24272D),
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
    return _GlassSurface(
      width: 310,
      padding: const EdgeInsets.fromLTRB(12, 11, 14, 11),
      radius: 28,
      color: const Color(0x9822252A),
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
                  'Голосовое',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 24,
                  child: CustomPaint(
                    painter: _VoiceWavePreviewPainter(
                      seed: (media.durationMs ?? 1) / 1000,
                    ),
                    size: Size.infinite,
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

class _VoiceWavePreviewPainter extends CustomPainter {
  const _VoiceWavePreviewPainter({required this.seed});

  final double seed;

  @override
  void paint(Canvas canvas, Size size) {
    final active = Paint()
      ..color = accent.withValues(alpha: 0.86)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4.2;
    final passive = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4.2;
    const bars = 28;
    final gap = size.width / bars;
    final center = size.height / 2;
    for (var i = 0; i < bars; i++) {
      final wave = math.sin(i * 0.72 + seed) * 0.5 + 0.5;
      final height = 5 + wave * (size.height - 7);
      final x = gap * i + gap / 2;
      canvas.drawLine(
        Offset(x, center - height / 2),
        Offset(x, center + height / 2),
        i < bars * 0.58 ? active : passive,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VoiceWavePreviewPainter oldDelegate) {
    return oldDelegate.seed != seed;
  }
}

class _VideoNotePreview extends StatelessWidget {
  const _VideoNotePreview({required this.media});

  final MessageMedia media;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.96, end: 1),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutBack,
          builder: (context, scale, child) {
            return Transform.scale(scale: scale, child: child);
          },
          child: Container(
            width: 148,
            height: 148,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF3A3425).withValues(alpha: 0.82),
                  const Color(0xFF16181D).withValues(alpha: 0.98),
                ],
              ),
              border: Border.all(
                color: accent.withValues(alpha: 0.42),
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 28,
                  offset: const Offset(0, 16),
                ),
                BoxShadow(
                  color: accent.withValues(alpha: 0.12),
                  blurRadius: 24,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 26,
                  child: Text(
                    'BrenksChat',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.16),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Icon(
                  Icons.videocam_rounded,
                  color: Colors.white.withValues(alpha: 0.12),
                  size: 48,
                ),
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.28),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.16),
                    ),
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: accent,
                    size: 31,
                  ),
                ),
              ],
            ),
          ),
        ),
        if ((media.durationMs ?? 0) > 0) ...[
          const SizedBox(height: 6),
          Text(
            _formatDuration(media.durationMs ?? 0),
            style: const TextStyle(color: muted, fontSize: 12),
          ),
        ],
      ],
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
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: bytes != null
            ? Image.memory(bytes, width: 320, fit: BoxFit.cover)
            : BrenksCachedNetworkImage(
                url: url!,
                width: 320,
                fit: BoxFit.cover,
                placeholder: const SizedBox(
                  width: 320,
                  height: 180,
                  child: Center(child: CircularProgressIndicator()),
                ),
                errorWidget: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('Фото не удалось загрузить'),
                ),
              ),
      ),
    );
  }
}

class _CreateChatFolderDialog extends StatefulWidget {
  const _CreateChatFolderDialog({
    required this.chats,
    required this.currentUserId,
    required this.serverUrl,
  });

  final List<Chat> chats;
  final String currentUserId;
  final String serverUrl;

  @override
  State<_CreateChatFolderDialog> createState() =>
      _CreateChatFolderDialogState();
}

class _CreateChatFolderDialogState extends State<_CreateChatFolderDialog> {
  final _nameController = TextEditingController();
  final Set<String> _selectedChatIds = {};

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 650),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: _glassDecoration(
                color: const Color(0xE222252B),
                radius: 30,
                borderColor: Colors.white.withValues(alpha: 0.1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Новая папка',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Закрыть',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _nameController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Название',
                      hintText: 'Например: Работа, Друзья, Проекты',
                      prefixIcon: Icon(Icons.folder_rounded),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Чаты в папке',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: widget.chats.isEmpty
                        ? const EmptyState(
                            title: 'Чатов пока нет',
                            subtitle: 'Сначала начните переписку.',
                          )
                        : ListView.separated(
                            itemCount: widget.chats.length,
                            separatorBuilder: (_, __) => Divider(
                              color: Colors.white.withValues(alpha: 0.06),
                            ),
                            itemBuilder: (context, index) {
                              final chat = widget.chats[index];
                              final selected =
                                  _selectedChatIds.contains(chat.id);
                              return CheckboxListTile(
                                value: selected,
                                onChanged: (_) {
                                  setState(() {
                                    if (selected) {
                                      _selectedChatIds.remove(chat.id);
                                    } else {
                                      _selectedChatIds.add(chat.id);
                                    }
                                  });
                                },
                                controlAffinity:
                                    ListTileControlAffinity.trailing,
                                title: Row(
                                  children: [
                                    BrenksAvatar(
                                      title:
                                          chat.titleFor(widget.currentUserId),
                                      imageUrl:
                                          chat.avatarFor(widget.currentUserId),
                                      baseUrl: widget.serverUrl,
                                      size: 34,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        chat.titleFor(widget.currentUserId),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Создать папку'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty || _selectedChatIds.isEmpty) return;
    Navigator.pop(
      context,
      _CustomChatFolder(
        id: 'folder-${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        chatIds: Set.unmodifiable(_selectedChatIds),
      ),
    );
  }
}

class _CreateSpaceDialog extends StatefulWidget {
  const _CreateSpaceDialog();

  @override
  State<_CreateSpaceDialog> createState() => _CreateSpaceDialogState();
}

class _CreateSpaceDialogState extends State<_CreateSpaceDialog> {
  final _nameController = TextEditingController();
  ChatType _type = ChatType.group;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = _nameController.text.trim();
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            width: 440,
            decoration: _glassDecoration(
              color: panel.withValues(alpha: 0.9),
              radius: 32,
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(17),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Icon(
                        _type == ChatType.channel
                            ? Icons.campaign_rounded
                            : Icons.groups_rounded,
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Группа или канал',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Участников можно добавить позже',
                            style: TextStyle(color: muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SegmentedButton<ChatType>(
                  showSelectedIcon: false,
                  segments: const [
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
                    setState(() => _type = value.first);
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _nameController,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _submitIfReady(name),
                  decoration: InputDecoration(
                    labelText: _type == ChatType.channel
                        ? 'Название канала'
                        : 'Название группы',
                    prefixIcon: const Icon(Icons.edit_rounded),
                  ),
                ),
                const SizedBox(height: 22),
                Row(
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
                        onPressed: name.length < 2
                            ? null
                            : () => Navigator.pop(
                                  context,
                                  _CreateSpaceResult(type: _type, name: name),
                                ),
                        child: const Text('Создать'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _submitIfReady(String name) {
    if (name.length < 2) return;
    Navigator.pop(context, _CreateSpaceResult(type: _type, name: name));
  }
}

class _CreateSpaceResult {
  const _CreateSpaceResult({
    required this.type,
    required this.name,
  });

  final ChatType type;
  final String name;
}

class _AccountDialog extends StatefulWidget {
  const _AccountDialog({
    required this.user,
    required this.api,
    required this.serverUrl,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.uiScale,
    required this.onUiScaleChanged,
    required this.onProfileUpdated,
    required this.onLogout,
  });

  final User user;
  final ApiClient api;
  final String serverUrl;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final double uiScale;
  final ValueChanged<double> onUiScaleChanged;
  final ValueChanged<User> onProfileUpdated;
  final VoidCallback onLogout;

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  late final TextEditingController _displayNameController;
  String? _avatarDraft;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController(
      text: widget.user.displayName ?? widget.user.username,
    );
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null || bytes.isEmpty) return;
    final mimeType =
        lookupMimeType(file.name, headerBytes: bytes.take(16).toList()) ??
            'image/png';
    setState(() {
      _avatarDraft = 'data:$mimeType;base64,${base64Encode(bytes)}';
    });
  }

  Future<void> _saveProfile() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final updated = await widget.api.updateProfile(
        displayName: _displayNameController.text.trim(),
        avatarUrl: _avatarDraft ?? widget.user.avatarUrl,
      );
      widget.onProfileUpdated(updated);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Профиль обновлен')),
      );
    } on Object catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить профиль: $err')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatarPreview = _avatarDraft ?? widget.user.avatarUrl;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(34),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            width: 540,
            decoration: BoxDecoration(
              color: panel.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(34),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.44),
                  blurRadius: 42,
                  offset: const Offset(0, 24),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(26),
                    decoration: BoxDecoration(
                      color: panelSoft.withValues(alpha: 0.42),
                      border: Border(bottom: BorderSide(color: border)),
                    ),
                    child: Row(
                      children: [
                        Stack(
                          children: [
                            BrenksAvatar(
                              title: widget.user.title,
                              imageUrl: avatarPreview,
                              baseUrl: widget.serverUrl,
                              size: 86,
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: IconButton.filled(
                                tooltip: 'Изменить фото',
                                onPressed: _pickAvatar,
                                icon: const Icon(Icons.edit_rounded, size: 18),
                                style: IconButton.styleFrom(
                                  backgroundColor: accent,
                                  foregroundColor: const Color(0xFF101318),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.user.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '@${widget.user.username}',
                                style: const TextStyle(color: muted),
                              ),
                              if (widget.user.email?.isNotEmpty == true)
                                Text(
                                  widget.user.email!,
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
                        _SettingsCard(
                          icon: Icons.badge_rounded,
                          title: 'Имя профиля',
                          subtitle: 'Отображается в чатах и профиле',
                          trailing: SizedBox(
                            width: 220,
                            child: TextField(
                              controller: _displayNameController,
                              decoration: const InputDecoration(
                                hintText: 'Ваше имя',
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _SettingsCard(
                          icon: Icons.contrast_rounded,
                          title: 'Тема',
                          subtitle: 'Переключение интерфейса приложения',
                          trailing: SegmentedButton<ThemeMode>(
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
                            selected: {widget.themeMode},
                            onSelectionChanged: (value) {
                              widget.onThemeModeChanged(value.first);
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: panelSoft.withValues(alpha: 0.52),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: border),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.zoom_out_map_rounded,
                                color: accent,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Expanded(
                                          child: Text(
                                            'Масштаб',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          '${(widget.uiScale * 100).round()}%',
                                          style: const TextStyle(
                                            color: muted,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                    SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        activeTrackColor: accent,
                                        inactiveTrackColor:
                                            Colors.white.withValues(alpha: 0.1),
                                        thumbColor: text,
                                        overlayColor:
                                            accent.withValues(alpha: 0.12),
                                      ),
                                      child: Slider(
                                        value: widget.uiScale,
                                        min: 0.82,
                                        max: 1,
                                        divisions: 9,
                                        onChanged: widget.onUiScaleChanged,
                                      ),
                                    ),
                                  ],
                                ),
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
                              child: FilledButton.icon(
                                onPressed: _saving ? null : _saveProfile,
                                icon: _saving
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.check_rounded),
                                label: const Text('Сохранить'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.tonalIcon(
                            onPressed: () {
                              Navigator.pop(context);
                              widget.onLogout();
                            },
                            icon: const Icon(Icons.logout_rounded),
                            label: const Text('Выйти'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: panelSoft.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(icon, color: accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(color: muted, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }
}

class _ChatProfileDialog extends StatelessWidget {
  const _ChatProfileDialog({
    required this.serverUrl,
    required this.chat,
    required this.messages,
    required this.currentUserId,
    required this.onlineUserIds,
  });

  final String serverUrl;
  final Chat chat;
  final List<Message> messages;
  final String currentUserId;
  final Set<String> onlineUserIds;

  @override
  Widget build(BuildContext context) {
    final mediaMessages = messages
        .where((message) =>
            !message.deleted &&
            (message.media != null || message.imageUrl?.isNotEmpty == true))
        .toList(growable: false);
    final photos = mediaMessages
        .where((message) =>
            message.media?.kind == 'image' ||
            (message.media == null && message.imageUrl?.isNotEmpty == true))
        .toList(growable: false);
    final voices = mediaMessages
        .where((message) =>
            message.media?.kind == 'voice' ||
            message.media?.kind == 'video_note')
        .toList(growable: false);
    final files = mediaMessages
        .where((message) => message.media?.kind == 'file')
        .toList(growable: false);
    final peer = chat.peerFor(currentUserId);
    final isDirect = chat.type == ChatType.direct;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(34),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            width: 560,
            constraints: const BoxConstraints(maxHeight: 720),
            decoration: BoxDecoration(
              color: panel.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(34),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.46),
                  blurRadius: 42,
                  offset: const Offset(0, 24),
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
                    color: panelSoft.withValues(alpha: 0.42),
                    border: Border(bottom: BorderSide(color: border)),
                  ),
                  child: Column(
                    children: [
                      BrenksAvatar(
                        title: chat.titleFor(currentUserId),
                        imageUrl: chat.avatarFor(currentUserId),
                        baseUrl: serverUrl,
                        size: 92,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        chat.titleFor(currentUserId),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 180),
                        style: const TextStyle(color: muted),
                        child: Text(
                          isDirect && peer != null
                              ? '@${peer.username}'
                              : _chatSubtitle(chat),
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(18),
                    children: [
                      if (isDirect && peer != null) ...[
                        _ProfileInfoRow(
                          icon: onlineUserIds.contains(peer.id)
                              ? Icons.circle_rounded
                              : Icons.alternate_email_rounded,
                          label: onlineUserIds.contains(peer.id)
                              ? 'Статус'
                              : 'Username',
                          value: onlineUserIds.contains(peer.id)
                              ? 'онлайн'
                              : '@${peer.username}',
                        ),
                        const SizedBox(height: 14),
                      ],
                      _ProfileMediaTabs(
                        photos: photos,
                        voices: voices,
                        files: files,
                        serverUrl: serverUrl,
                      ),
                      if (!isDirect) ...[
                        const SizedBox(height: 18),
                        const Text(
                          'Участники',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
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
        ),
      ),
    );
  }
}

class _ProfileInfoRow extends StatelessWidget {
  const _ProfileInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return _GlassSurface(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      radius: 18,
      color: const Color(0x9A24272D),
      child: Row(
        children: [
          Icon(icon, color: accent, size: 18),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: muted)),
          const Spacer(),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _ProfileMediaTabs extends StatefulWidget {
  const _ProfileMediaTabs({
    required this.photos,
    required this.voices,
    required this.files,
    required this.serverUrl,
  });

  final List<Message> photos;
  final List<Message> voices;
  final List<Message> files;
  final String serverUrl;

  @override
  State<_ProfileMediaTabs> createState() => _ProfileMediaTabsState();
}

class _ProfileMediaTabsState extends State<_ProfileMediaTabs> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      ('Фото', widget.photos.length),
      ('Голосовые', widget.voices.length),
      ('Файлы', widget.files.length),
    ];
    final items = switch (_tab) {
      0 => widget.photos,
      1 => widget.voices,
      _ => widget.files,
    };

    return _GlassSurface(
      padding: const EdgeInsets.all(14),
      radius: 24,
      color: const Color(0x7A202329),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 0; i < tabs.length; i++)
                Expanded(
                  child: Padding(
                    padding:
                        EdgeInsets.only(right: i == tabs.length - 1 ? 0 : 8),
                    child: _MediaTabButton(
                      label: tabs[i].$1,
                      count: tabs[i].$2,
                      selected: _tab == i,
                      onTap: () => setState(() => _tab = i),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: items.isEmpty
                ? const Padding(
                    key: ValueKey('empty'),
                    padding: EdgeInsets.symmetric(vertical: 26),
                    child: Center(
                      child: Text('Здесь пока пусто',
                          style: TextStyle(color: muted)),
                    ),
                  )
                : _ProfileMediaGrid(
                    key: ValueKey(_tab),
                    tab: _tab,
                    messages: items,
                    serverUrl: widget.serverUrl,
                  ),
          ),
        ],
      ),
    );
  }
}

class _MediaTabButton extends StatelessWidget {
  const _MediaTabButton({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: selected
            ? accent.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected
              ? accent.withValues(alpha: 0.24)
              : Colors.white.withValues(alpha: 0.07),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Text(
            '$label $count',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? text : muted,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileMediaGrid extends StatelessWidget {
  const _ProfileMediaGrid({
    super.key,
    required this.tab,
    required this.messages,
    required this.serverUrl,
  });

  final int tab;
  final List<Message> messages;
  final String serverUrl;

  @override
  Widget build(BuildContext context) {
    if (tab == 0) {
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: math.min(messages.length, 9),
        itemBuilder: (context, index) {
          final message = messages[index];
          final source = message.media?.dataUrl ?? message.imageUrl ?? '';
          return ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: _ImagePreview(source: source, serverUrl: serverUrl),
          );
        },
      );
    }

    return Column(
      children: messages.take(6).map((message) {
        final media = message.media;
        final icon =
            tab == 1 ? Icons.graphic_eq_rounded : Icons.description_rounded;
        final title = tab == 1
            ? (media?.kind == 'video_note' ? 'Видеокружок' : 'Голосовое')
            : (media?.fileName ?? 'Файл');
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.035),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
            ),
            child: Row(
              children: [
                Icon(icon, color: accent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  _formatTime(message.createdAt),
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ),
          ),
        );
      }).toList(growable: false),
    );
  }
}

String _chatSubtitle(Chat chat, {bool directPeerOnline = false}) {
  return switch (chat.type) {
    ChatType.direct => directPeerOnline ? 'в сети' : 'не в сети',
    ChatType.group => '${chat.participants.length} участников',
    ChatType.channel => 'канал',
  };
}

bool _isOwnMessageReadByRecipients({
  required Chat chat,
  required List<Message> messages,
  required int index,
  required String currentUserId,
}) {
  if (index < 0 || index >= messages.length) return false;
  final message = messages[index];
  if (message.senderId != currentUserId || message.deleted) return false;

  final recipientIds = chat.participantIds
      .where((id) => id != currentUserId)
      .toList(growable: false);
  if (recipientIds.isEmpty) return true;

  for (final recipientId in recipientIds) {
    final unread = chat.unread[recipientId] ?? 0;
    if (unread <= 0) continue;

    var unreadCandidateCount = 0;
    for (var i = index; i < messages.length; i++) {
      final item = messages[i];
      if (!item.deleted && item.senderId != recipientId) {
        unreadCandidateCount++;
      }
    }
    if (unreadCandidateCount <= unread) return false;
  }

  return true;
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
  if (message.encryptedText) return '🔒 Зашифровано';
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
                  child: BrenksCachedNetworkImage(
                    url: url,
                    fit: BoxFit.contain,
                    placeholder: const CircularProgressIndicator(),
                    errorWidget: const Text('Фото не удалось загрузить'),
                  ),
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
      ..color = accent.withValues(alpha: 0.028)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    const gap = 44.0;
    const arm = 5.6;
    for (double y = 24; y < size.height; y += gap) {
      for (double x = 24; x < size.width; x += gap) {
        canvas.drawLine(Offset(x - arm, y), Offset(x + arm, y), paint);
        canvas.drawLine(Offset(x, y - arm), Offset(x, y + arm), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
