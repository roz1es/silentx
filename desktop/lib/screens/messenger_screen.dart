import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui' show FontFeature, ImageFilter;

import 'package:camera_macos/camera_macos.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:mime/mime.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart' hide VideoFormat;

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

enum _CallKind { audio, video }

enum _CallPhase { idle, incoming, outgoing, connected }

class _IncomingCallOffer {
  const _IncomingCallOffer({
    required this.fromUserId,
    required this.callId,
    required this.callKind,
    required this.sdp,
  });

  final String fromUserId;
  final String callId;
  final _CallKind callKind;
  final String sdp;
}

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

bool _isLightUi(BuildContext context) {
  return Theme.of(context).brightness == Brightness.light;
}

Color _themeGlassColor(
  BuildContext context, {
  required Color dark,
  required Color light,
}) {
  return _isLightUi(context) ? light : dark;
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
    final lightUi = _isLightUi(context);
    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            width: width,
            padding: padding,
            decoration: _glassDecoration(
              color: color ??
                  (lightUi
                      ? Colors.white.withValues(alpha: 0.72)
                      : const Color(0xB823252A)),
              radius: radius,
              borderColor: lightUi
                  ? border.withValues(alpha: 0.7)
                  : Colors.white.withValues(alpha: 0.085),
              shadows: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: lightUi ? 0.055 : 0.16),
                  blurRadius: lightUi ? 18 : 24,
                  offset: const Offset(0, 12),
                ),
                BoxShadow(
                  color: accent.withValues(alpha: lightUi ? 0.045 : 0.035),
                  blurRadius: 0,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
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
    required this.accentPreset,
    required this.onAccentPresetChanged,
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
  final BrenksAccentPreset accentPreset;
  final ValueChanged<BrenksAccentPreset> onAccentPresetChanged;
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
  final Map<String, GlobalKey> _messageKeys = {};
  StreamSubscription<double>? _recordingLevelSub;
  StreamSubscription<PlayerState>? _voicePlayerStateSub;
  StreamSubscription<Duration>? _voicePositionSub;
  StreamSubscription<Duration>? _voiceDurationSub;
  Timer? _videoNoteLevelTimer;

  late final LocalCacheService _cache;
  BrenksSocket? _socket;
  late User _currentUser;
  List<Chat> _chats = const [];
  List<Message> _messages = const [];
  Set<String> _vanishingMessageIds = const {};
  Set<String> _onlineUserIds = const {};
  Map<String, String> _typingNames = const {};
  Map<String, Map<String, String>> _typingByChat = const {};
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
  String? _playingVoiceKey;
  PlayerState _voicePlayerState = PlayerState.stopped;
  Duration _voicePosition = Duration.zero;
  Duration _voiceDuration = Duration.zero;
  RTCPeerConnection? _callPeerConnection;
  MediaStream? _localCallStream;
  MediaStream? _remoteCallStream;
  final _localCallRenderer = RTCVideoRenderer();
  final _remoteCallRenderer = RTCVideoRenderer();
  bool _callRenderersReady = false;
  _CallPhase _callPhase = _CallPhase.idle;
  _CallKind _callKind = _CallKind.audio;
  String? _callPeerId;
  String? _callId;
  String? _callStatusText;
  _IncomingCallOffer? _incomingCallOffer;
  final List<Map<String, dynamic>> _pendingCallIce = [];
  bool _callMicMuted = false;
  bool _callSpeakerMuted = false;
  bool _callCameraOff = false;
  bool _localVideoLarge = false;

  Chat? get _activeChat {
    for (final chat in _chats) {
      if (chat.id == _activeChatId) return chat;
    }
    return null;
  }

  Chat? _chatById(String chatId) {
    for (final chat in _chats) {
      if (chat.id == chatId) return chat;
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
    unawaited(_initCallRenderers());
    _bindVoicePlayer();
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _userSearchTimer?.cancel();
    _recordingLevelSub?.cancel();
    _voicePlayerStateSub?.cancel();
    _voicePositionSub?.cancel();
    _voiceDurationSub?.cancel();
    _videoNoteLevelTimer?.cancel();
    unawaited(_cleanupCall(sendEnd: false));
    _sendTypingState(false);
    _socket?.dispose();
    unawaited(_audioService.dispose());
    unawaited(_videoNoteController?.destroy());
    unawaited(_localCallRenderer.dispose());
    unawaited(_remoteCallRenderer.dispose());
    _messageController.dispose();
    _messageFocusNode.dispose();
    _messageScrollController.dispose();
    _chatSearchController.dispose();
    super.dispose();
  }

  void _bindVoicePlayer() {
    _voicePlayerStateSub = _audioService.playerState.listen((state) {
      if (!mounted) return;
      setState(() {
        _voicePlayerState = state;
        if (state == PlayerState.stopped || state == PlayerState.completed) {
          _voicePosition =
              state == PlayerState.completed ? _voiceDuration : Duration.zero;
        }
      });
    });
    _voicePositionSub = _audioService.positionChanged.listen((position) {
      if (!mounted) return;
      setState(() => _voicePosition = position);
    });
    _voiceDurationSub = _audioService.durationChanged.listen((duration) {
      if (!mounted) return;
      setState(() => _voiceDuration = duration);
    });
  }

  Future<void> _initCallRenderers() async {
    await Future.wait([
      _localCallRenderer.initialize(),
      _remoteCallRenderer.initialize(),
    ]);
    if (!mounted) return;
    setState(() => _callRenderersReady = true);
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
        setState(() => _vanishingMessageIds = {
              ..._vanishingMessageIds,
              messageId,
            });
        Future.delayed(const Duration(milliseconds: 260), () {
          if (!mounted || chatId != _activeChatId) return;
          setState(() {
            _messages = _messages
                .where((message) => message.id != messageId)
                .toList(growable: false);
            final next = {..._vanishingMessageIds}..remove(messageId);
            _vanishingMessageIds = next;
          });
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
      onCallSignal: _handleCallSignal,
      onAdminReportCreated: (report) {
        if (!_currentUser.isAdmin || !mounted) return;
        final target = report.target?.title ?? 'пользователя';
        _showSnack('Новая жалоба на $target');
      },
      onSocketError: _showSnack,
      onTyping: ({
        required chatId,
        required userId,
        required username,
        required activity,
        required isTyping,
      }) {
        if (!mounted || userId == _currentUser.id) return;
        final chat = _chatById(chatId);
        final label = _typingActivityLabel(
          username: username,
          activity: activity,
          direct: chat?.type == ChatType.direct,
        );
        final currentChatTyping = _typingByChat[chatId] ?? const {};
        final current = currentChatTyping[userId];
        if (isTyping && current == label) return;
        if (!isTyping && current == null) return;
        setState(() {
          final nextByChat = {
            for (final entry in _typingByChat.entries)
              entry.key: {...entry.value},
          };
          final next = {...currentChatTyping};
          if (isTyping) {
            next[userId] = label;
          } else {
            next.remove(userId);
          }
          if (next.isEmpty) {
            nextByChat.remove(chatId);
          } else {
            nextByChat[chatId] = next;
          }
          _typingByChat = nextByChat;
          if (chatId == _activeChatId) {
            _typingNames = next;
          }
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
      _vanishingMessageIds = const {};
      _typingNames = _typingByChat[chatId] ?? const {};
      _messageKeys.clear();
      _replyTo = null;
      _editing = null;
      _loadingMessages = true;
      _error = null;
    });
    _focusComposer();
    _socket?.joinChat(chatId);
    _socket?.markRead(chatId);
    final cached = (await _cache.loadMessages(chatId))
        .where((message) => !message.deleted)
        .toList(growable: false);
    if (mounted && _activeChatId == chatId && cached.isNotEmpty) {
      setState(() => _messages = cached);
      if (preferCache) _scrollToBottom(instant: true);
    }
    try {
      final messages = await widget.api.fetchMessages(chatId);
      if (!mounted || _activeChatId != chatId) return;
      final visibleMessages =
          messages.where((message) => !message.deleted).toList(growable: false);
      setState(() {
        _messages = visibleMessages;
        _loadingMessages = false;
      });
      unawaited(_cache.saveMessages(chatId, visibleMessages));
      _scrollToBottom(instant: true);
      for (final delayMs in const [120, 420, 760]) {
        Future<void>.delayed(Duration(milliseconds: delayMs), () {
          if (mounted && _activeChatId == chatId) {
            _scrollToBottom(instant: true);
          }
        });
      }
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
        final ok = await _sendAttachmentBytes(
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
        final ok = await _sendAttachmentBytes(
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
          final ok = await _sendAttachmentBytes(
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
            final ok = await _sendAttachmentBytes(
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

  Future<bool> _sendAttachmentBytes({
    required List<int> bytes,
    required String fileName,
    required String? mimeType,
    required bool includeComposerText,
  }) async {
    final chatId = _activeChatId;
    if (chatId == null || bytes.isEmpty) return false;
    final resolvedMimeType = mimeType ?? 'application/octet-stream';
    final editableMedia = resolvedMimeType.startsWith('image/') ||
        resolvedMimeType.startsWith('video/');
    var outgoingText =
        includeComposerText ? _messageController.text.trim() : '';
    var items = [
      _MediaSendItem(
        bytes: Uint8List.fromList(bytes),
        fileName: fileName,
        mimeType: resolvedMimeType,
      ),
    ];
    if (editableMedia) {
      final result = await showDialog<_MediaSendResult>(
        context: context,
        builder: (_) => _MediaSendPreviewDialog(
          initialItems: items,
          initialCaption: outgoingText,
        ),
      );
      if (result == null) return false;
      outgoingText = result.caption.trim();
      items = result.items;
    }

    var sent = 0;
    for (final item in items) {
      final dataUrl =
          'data:${item.mimeType};base64,${base64Encode(item.bytes)}';
      if (dataUrl.length > _maxMediaDataUrlLength) {
        _showSnack('${item.fileName} слишком большой для текущего сервера.');
        continue;
      }
      final media = MessageMedia(
        kind: item.mimeType.startsWith('image/') ? 'image' : 'file',
        dataUrl: dataUrl,
        fileName: item.fileName,
        mimeType: item.mimeType,
      );
      _socket?.sendMessage(
        chatId: chatId,
        text: sent == 0 ? outgoingText : '',
        media: media,
        replyToMessageId:
            includeComposerText && sent == 0 ? _replyTo?.id : null,
      );
      sent += 1;
    }
    if (sent == 0) return false;
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
      _sendRecordingActivity(_RecordKind.voice, true);
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
    _sendRecordingActivity(_RecordKind.voice, false);
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
    _startVideoNoteLevelMeter();
    _sendRecordingActivity(_RecordKind.videoNote, true);
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
      _stopVideoNoteLevelMeter();
      _sendRecordingActivity(_RecordKind.videoNote, false);
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
      _stopVideoNoteLevelMeter();
      _sendRecordingActivity(_RecordKind.videoNote, false);
      unawaited(controller.destroy().catchError((_) => null));
      final bytes = await _readCameraFileBytes(file);
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
      _stopVideoNoteLevelMeter();
      _sendRecordingActivity(_RecordKind.videoNote, false);
      unawaited(controller.destroy().catchError((_) => null));
      _showSnack('Не удалось отправить кружок: $err');
    }
  }

  Future<void> _cancelVoiceRecording() async {
    if (!_recordingVoice) return;
    _stopRecordingLevelMeter();
    _sendRecordingActivity(_RecordKind.voice, false);
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
    _stopVideoNoteLevelMeter();
    _sendRecordingActivity(_RecordKind.videoNote, false);
    if (controller != null) {
      unawaited(controller.destroy().catchError((_) => null));
    }
  }

  Future<Uint8List?> _readCameraFileBytes(CameraMacOSFile? file) async {
    final directBytes = file?.bytes;
    if (directBytes != null && directBytes.isNotEmpty) return directBytes;
    final rawUrl = file?.url;
    if (rawUrl == null || rawUrl.isEmpty) return null;
    final uri = Uri.tryParse(rawUrl);
    final path = uri?.scheme == 'file' ? uri!.toFilePath() : rawUrl;
    final diskFile = io.File(path);
    if (!await diskFile.exists()) return null;
    final bytes = await diskFile.readAsBytes();
    return bytes.isEmpty ? null : bytes;
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

  void _startVideoNoteLevelMeter() {
    _videoNoteLevelTimer?.cancel();
    _videoNoteLevelTimer =
        Timer.periodic(const Duration(milliseconds: 64), (_) {
      if (!mounted || !_recordingVideoNote) return;
      final phase = DateTime.now().millisecondsSinceEpoch / 150;
      final pulse = 0.34 + (math.sin(phase) * 0.5 + 0.5) * 0.42;
      final flutter = math.Random().nextDouble() * 0.18;
      final next = (pulse + flutter).clamp(0.16, 1.0);
      setState(() {
        _recordingLevel = _recordingLevel * 0.68 + next * 0.32;
      });
    });
  }

  void _stopVideoNoteLevelMeter() {
    _videoNoteLevelTimer?.cancel();
    _videoNoteLevelTimer = null;
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
      final key = _mediaPlaybackKey(media);
      if (_playingVoiceKey == key && _voicePlayerState == PlayerState.playing) {
        await _audioService.pausePlayback();
        return;
      }
      if (_playingVoiceKey == key && _voicePlayerState == PlayerState.paused) {
        await _audioService.resumePlayback();
        return;
      }
      setState(() {
        _playingVoiceKey = key;
        _voicePlayerState = PlayerState.playing;
        _voicePosition = Duration.zero;
        _voiceDuration = Duration(milliseconds: media.durationMs ?? 0);
      });
      await _audioService.playSource(
        media.dataUrl,
        baseUrl: widget.serverUrl,
        mimeType: media.mimeType,
      );
    } on Object catch (err) {
      setState(() {
        _playingVoiceKey = null;
        _voicePlayerState = PlayerState.stopped;
        _voicePosition = Duration.zero;
      });
      _showSnack('Не удалось воспроизвести аудио: $err');
    }
  }

  Future<void> _seekVoice(MessageMedia media, double progress) async {
    final durationMs = _voiceDuration.inMilliseconds > 0
        ? _voiceDuration.inMilliseconds
        : media.durationMs ?? 0;
    if (durationMs <= 0) return;
    final position = Duration(
      milliseconds: (durationMs * progress.clamp(0, 1)).round(),
    );
    await _audioService.seekPlayback(position);
  }

  ChatParticipant? _callPeerFromChat(Chat? chat) {
    if (chat?.type != ChatType.direct) return null;
    return chat!.peerFor(_currentUser.id);
  }

  ChatParticipant? _participantById(String? userId) {
    if (userId == null || userId.isEmpty) return null;
    for (final chat in _chats) {
      for (final participant in chat.participants) {
        if (participant.id == userId) return participant;
      }
    }
    return null;
  }

  String _newCallId() {
    final millis = DateTime.now().millisecondsSinceEpoch;
    final salt = math.Random().nextInt(0x7fffffff).toRadixString(16);
    return 'call-$millis-$salt';
  }

  Future<Map<String, dynamic>> _callIceConfiguration() async {
    try {
      final iceServers = await widget.api.fetchCallIceServers();
      if (iceServers.isNotEmpty) return {'iceServers': iceServers};
    } on Object {
      // The public STUN fallback keeps local testing usable when the server
      // cannot return a TURN configuration.
    }
    return {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    };
  }

  Future<MediaStream> _openCallMedia(_CallKind kind) async {
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': kind == _CallKind.video
          ? {
              'facingMode': 'user',
              'width': {'ideal': 1280},
              'height': {'ideal': 720},
            }
          : false,
    });
    _localCallRenderer.srcObject = stream;
    return stream;
  }

  Future<RTCPeerConnection> _createCallPeerConnection(
    String peerId,
    _CallKind kind,
  ) async {
    final pc = await createPeerConnection(
      await _callIceConfiguration(),
      {
        'optional': [
          {'DtlsSrtpKeyAgreement': true},
        ],
      },
    );
    pc.onIceCandidate = (candidate) {
      final value = candidate.candidate;
      if (value == null || value.isEmpty) return;
      _socket?.sendCallSignal(
        toUserId: peerId,
        kind: 'ice',
        callId: _callId,
        callType: kind == _CallKind.video ? 'video' : 'audio',
        candidate: {
          'candidate': value,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      );
    };
    pc.onTrack = (event) {
      final stream = event.streams.isNotEmpty ? event.streams.first : null;
      if (stream == null) return;
      _remoteCallStream = stream;
      _remoteCallRenderer.srcObject = stream;
      if (mounted && _callPhase != _CallPhase.connected) {
        setState(() => _callPhase = _CallPhase.connected);
      }
    };
    pc.onConnectionState = (state) {
      if (!mounted) return;
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        setState(() => _callPhase = _CallPhase.connected);
      }
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _showSnack('Звонок завершен.');
        unawaited(_cleanupCall(sendEnd: false));
      }
    };
    return pc;
  }

  Future<void> _startCall(Chat chat, _CallKind kind) async {
    final peer = _callPeerFromChat(chat);
    if (peer == null) {
      _showSnack('Пока звонки доступны только в личных чатах.');
      return;
    }
    if (_callPhase != _CallPhase.idle) {
      _showSnack('Уже есть активный звонок.');
      return;
    }
    final callId = _newCallId();
    setState(() {
      _callPhase = _CallPhase.outgoing;
      _callKind = kind;
      _callPeerId = peer.id;
      _callId = callId;
      _callStatusText = 'Соединение...';
      _callMicMuted = false;
      _callSpeakerMuted = false;
      _callCameraOff = false;
      _localVideoLarge = false;
    });
    try {
      final stream = await _openCallMedia(kind);
      final pc = await _createCallPeerConnection(peer.id, kind);
      for (final track in stream.getTracks()) {
        await pc.addTrack(track, stream);
      }
      _localCallStream = stream;
      _callPeerConnection = pc;
      final offer = await pc.createOffer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': kind == _CallKind.video ? 1 : 0,
      });
      await pc.setLocalDescription(offer);
      _socket?.sendCallSignal(
        toUserId: peer.id,
        kind: 'offer',
        callId: callId,
        callType: kind == _CallKind.video ? 'video' : 'audio',
        sdp: offer.sdp,
      );
    } on Object catch (err) {
      _showSnack('Не удалось начать звонок: $err');
      await _cleanupCall(sendEnd: true);
    }
  }

  Future<void> _acceptCall() async {
    final offer = _incomingCallOffer;
    if (offer == null) return;
    setState(() {
      _callPhase = _CallPhase.connected;
      _callStatusText = 'Соединение...';
    });
    try {
      final stream = await _openCallMedia(offer.callKind);
      final pc =
          await _createCallPeerConnection(offer.fromUserId, offer.callKind);
      for (final track in stream.getTracks()) {
        await pc.addTrack(track, stream);
      }
      _localCallStream = stream;
      _callPeerConnection = pc;
      await pc.setRemoteDescription(
        RTCSessionDescription(offer.sdp, 'offer'),
      );
      await _flushPendingIce();
      final answer = await pc.createAnswer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': offer.callKind == _CallKind.video ? 1 : 0,
      });
      await pc.setLocalDescription(answer);
      _socket?.sendCallSignal(
        toUserId: offer.fromUserId,
        kind: 'answer',
        callId: offer.callId,
        callType: offer.callKind == _CallKind.video ? 'video' : 'audio',
        sdp: answer.sdp,
      );
    } on Object catch (err) {
      _showSnack('Не удалось принять звонок: $err');
      await _cleanupCall(sendEnd: true);
    }
  }

  Future<void> _handleCallSignal(Map<String, dynamic> signal) async {
    final kind = signal['kind']?.toString();
    final fromUserId = signal['fromUserId']?.toString() ??
        signal['userId']?.toString() ??
        signal['from']?.toString() ??
        '';
    if (fromUserId.isEmpty || fromUserId == _currentUser.id) return;
    final callId = signal['callId']?.toString() ?? _newCallId();
    final type = signal['callType']?.toString() == 'video'
        ? _CallKind.video
        : _CallKind.audio;

    switch (kind) {
      case 'offer':
        final sdp = signal['sdp']?.toString();
        if (sdp == null || sdp.isEmpty) return;
        if (_callPhase != _CallPhase.idle) {
          _socket?.sendCallSignal(
              toUserId: fromUserId, kind: 'end', callId: callId);
          return;
        }
        setState(() {
          _callPhase = _CallPhase.incoming;
          _callKind = type;
          _callPeerId = fromUserId;
          _callId = callId;
          _incomingCallOffer = _IncomingCallOffer(
            fromUserId: fromUserId,
            callId: callId,
            callKind: type,
            sdp: sdp,
          );
          _callStatusText = 'Входящий звонок';
          _pendingCallIce.clear();
        });
      case 'answer':
        final pc = _callPeerConnection;
        final sdp = signal['sdp']?.toString();
        if (pc == null || sdp == null || sdp.isEmpty) return;
        await pc.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
        await _flushPendingIce();
        if (mounted) {
          setState(() {
            _callPhase = _CallPhase.connected;
            _callStatusText = null;
          });
        }
      case 'ice':
        final rawCandidate = signal['candidate'];
        if (rawCandidate is! Map) return;
        final candidate = rawCandidate.cast<String, dynamic>();
        final pc = _callPeerConnection;
        if (pc == null || await pc.getRemoteDescription() == null) {
          _pendingCallIce.add(candidate);
          return;
        }
        await _addIceCandidate(candidate);
      case 'end':
        _showSnack('Звонок завершен.');
        await _cleanupCall(sendEnd: false);
    }
  }

  Future<void> _flushPendingIce() async {
    if (_pendingCallIce.isEmpty) return;
    final items = List<Map<String, dynamic>>.from(_pendingCallIce);
    _pendingCallIce.clear();
    for (final candidate in items) {
      await _addIceCandidate(candidate);
    }
  }

  Future<void> _addIceCandidate(Map<String, dynamic> candidate) async {
    final pc = _callPeerConnection;
    final raw = candidate['candidate']?.toString();
    if (pc == null || raw == null || raw.isEmpty) return;
    final lineIndex = candidate['sdpMLineIndex'];
    await pc.addCandidate(
      RTCIceCandidate(
        raw,
        candidate['sdpMid']?.toString(),
        lineIndex is int
            ? lineIndex
            : int.tryParse(lineIndex?.toString() ?? ''),
      ),
    );
  }

  Future<void> _toggleCallMic() async {
    final next = !_callMicMuted;
    for (final track
        in _localCallStream?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = !next;
    }
    if (mounted) setState(() => _callMicMuted = next);
  }

  Future<void> _toggleCallSpeaker() async {
    final next = !_callSpeakerMuted;
    for (final track
        in _remoteCallStream?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = !next;
    }
    if (mounted) setState(() => _callSpeakerMuted = next);
  }

  Future<void> _toggleCallCamera() async {
    final next = !_callCameraOff;
    for (final track
        in _localCallStream?.getVideoTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = !next;
    }
    if (mounted) setState(() => _callCameraOff = next);
  }

  Future<void> _cleanupCall({required bool sendEnd}) async {
    final peerId = _callPeerId;
    final callId = _callId;
    if (sendEnd && peerId != null) {
      _socket?.sendCallSignal(toUserId: peerId, kind: 'end', callId: callId);
    }
    _pendingCallIce.clear();
    _incomingCallOffer = null;
    await _callPeerConnection?.close().catchError((_) {});
    _callPeerConnection = null;
    for (final track
        in _localCallStream?.getTracks() ?? const <MediaStreamTrack>[]) {
      track.stop();
    }
    await _localCallStream?.dispose().catchError((_) {});
    await _remoteCallStream?.dispose().catchError((_) {});
    _localCallStream = null;
    _remoteCallStream = null;
    _localCallRenderer.srcObject = null;
    _remoteCallRenderer.srcObject = null;
    if (!mounted) return;
    setState(() {
      _callPhase = _CallPhase.idle;
      _callKind = _CallKind.audio;
      _callPeerId = null;
      _callId = null;
      _callStatusText = null;
      _callMicMuted = false;
      _callSpeakerMuted = false;
      _callCameraOff = false;
      _localVideoLarge = false;
    });
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

  Future<void> _forwardMessage(Message message) async {
    if (message.deleted) return;
    final availableChats = _chats
        .where((chat) => chat.canPost(_currentUser.id))
        .toList(growable: false);
    if (availableChats.isEmpty) {
      _showSnack('Нет чатов для пересылки.');
      return;
    }

    final target = await showDialog<Chat>(
      context: context,
      builder: (_) => _ForwardMessageDialog(
        chats: availableChats,
        currentUserId: _currentUser.id,
        serverUrl: widget.serverUrl,
      ),
    );
    if (target == null || !mounted) return;

    _socket?.forwardMessages(
      sourceChatId: message.chatId,
      targetChatId: target.id,
      messageIds: [message.id],
    );
    _showSnack('Сообщение переслано в «${target.titleFor(_currentUser.id)}».');
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

  void _sendRecordingActivity(_RecordKind kind, bool active) {
    final chatId = _activeChatId;
    if (chatId == null) return;
    _socket?.typing(
      chatId: chatId,
      isTyping: active,
      activity: kind == _RecordKind.videoNote ? 'video_note' : 'voice',
    );
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

  Future<void> _startDirectChatByUserId(String userId) async {
    if (userId == _currentUser.id) {
      _showAccountDialog();
      return;
    }
    try {
      final chat = await widget.api.createDirectChat(targetUserId: userId);
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

  Future<void> _addMembersToChat(Chat chat) async {
    final selectedIds = await showDialog<List<String>>(
      context: context,
      builder: (_) => _PickUsersDialog(
        api: widget.api,
        serverUrl: widget.serverUrl,
        title: chat.type == ChatType.channel
            ? 'Добавить подписчиков'
            : 'Добавить участников',
        excludedUserIds: chat.participantIds.toSet(),
      ),
    );
    if (selectedIds == null || selectedIds.isEmpty) return;
    try {
      await widget.api.addChatMembers(chatId: chat.id, memberIds: selectedIds);
      await _loadChats();
      await _selectChat(chat.id);
      _showSnack('Участники добавлены');
    } on Object catch (err) {
      _showSnack('Не удалось добавить участников: $err');
    }
  }

  Future<void> _manageChannelAdmins(Chat chat) async {
    final selectedIds = await showDialog<List<String>>(
      context: context,
      builder: (_) => _PickChannelAdminsDialog(
        chat: chat,
        serverUrl: widget.serverUrl,
      ),
    );
    if (selectedIds == null) return;
    try {
      await widget.api.setChannelAdmins(
        chatId: chat.id,
        adminIds: selectedIds,
      );
      await _loadChats();
      await _selectChat(chat.id);
      _showSnack('Админы канала обновлены');
    } on Object catch (err) {
      _showSnack('Не удалось обновить админов: $err');
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
            child: Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Да'),
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
        onToggleBlockUser: (userId, blocked) async {
          final updated = await widget.api.setUserBlocked(
            userId: userId,
            blocked: blocked,
          );
          if (!mounted) return;
          setState(() => _currentUser = updated);
          await _loadChats();
        },
        onReportUser: (userId) async {
          final peer = chat.participants.firstWhere(
            (participant) => participant.id == userId,
            orElse: () => ChatParticipant(id: userId, username: 'user'),
          );
          final sent = await showDialog<bool>(
            context: context,
            builder: (_) => _ReportUserDialog(
              api: widget.api,
              target: peer,
              chatId: chat.id,
            ),
          );
          if (sent == true && mounted) {
            _showSnack('Жалоба отправлена администраторам');
          }
        },
        onAddMembers: chat.type == ChatType.direct
            ? null
            : () {
                Navigator.of(context, rootNavigator: true).pop();
                unawaited(_addMembersToChat(chat));
              },
        onManageChannelAdmins: chat.canManageChannel(_currentUser.id)
            ? () {
                Navigator.of(context, rootNavigator: true).pop();
                unawaited(_manageChannelAdmins(chat));
              }
            : null,
        onOpenDirectChat: (userId) {
          Navigator.of(context, rootNavigator: true).pop();
          unawaited(_startDirectChatByUserId(userId));
        },
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
        accentPreset: widget.accentPreset,
        onAccentPresetChanged: widget.onAccentPresetChanged,
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

  void _jumpToMessage(String messageId) {
    final index = _messages.indexWhere((message) => message.id == messageId);
    if (index == -1) {
      _showSnack('Это сообщение не загружено в текущей истории.');
      return;
    }

    void ensureVisible() {
      final ctx = _messageKeys[messageId]?.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        alignment: 0.34,
      );
    }

    if (!_messageScrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) => ensureVisible());
      return;
    }
    final max = _messageScrollController.position.maxScrollExtent;
    final ratio = _messages.length <= 1 ? 1.0 : index / (_messages.length - 1);
    unawaited(
      _messageScrollController
          .animateTo(
            (max * ratio).clamp(0.0, max),
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
          )
          .then((_) => ensureVisible()),
    );
  }

  GlobalKey _messageKey(String messageId) {
    return _messageKeys.putIfAbsent(messageId, GlobalKey.new);
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
    final lightUi = _isLightUi(context);
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
    final typingPreviewByChat = {
      for (final entry in _typingByChat.entries)
        if (entry.value.isNotEmpty)
          entry.key: entry.value.length > 1
              ? entry.value.values.join(', ')
              : entry.value.values.first,
    };
    final callPeer = _participantById(_callPeerId) ??
        (_activeChat?.peerFor(_currentUser.id));

    return Scaffold(
      body: Stack(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: lightUi
                    ? [
                        const Color(0xFFF8FAFD),
                        const Color(0xFFF1F4F8),
                        Color.alphaBlend(
                          accent.withValues(alpha: 0.035),
                          const Color(0xFFE9EEF5),
                        ),
                      ]
                    : [
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
                    typingPreviewByChat: typingPreviewByChat,
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
                Container(width: 1, color: border.withValues(alpha: 0.85)),
                Expanded(
                  child: _ChatPane(
                    chat: _activeChat,
                    serverUrl: widget.serverUrl,
                    user: _currentUser,
                    messages: _messages,
                    vanishingMessageIds: _vanishingMessageIds,
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
                    onStartAudioCall: (chat) =>
                        _startCall(chat, _CallKind.audio),
                    onStartVideoCall: (chat) =>
                        _startCall(chat, _CallKind.video),
                    onUnpinMessage: () => _setPinnedMessage(null),
                    onOpenPinnedMessage: (message) =>
                        _jumpToMessage(message.id),
                    onReply: (message) {
                      setState(() {
                        _editing = null;
                        _replyTo = message;
                      });
                      _focusComposer();
                    },
                    onEdit: _startEdit,
                    onForwardMessage: _forwardMessage,
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
                    playingVoiceKey: _playingVoiceKey,
                    voicePlayerState: _voicePlayerState,
                    voicePosition: _voicePosition,
                    voiceDuration: _voiceDuration,
                    onPlayVoice: _playVoice,
                    onSeekVoice: _seekVoice,
                    messageKeyFor: _messageKey,
                  ),
                ),
              ],
            ),
          ),
          if (_callPhase != _CallPhase.idle)
            _CallOverlay(
              phase: _callPhase,
              kind: _callKind,
              peer: callPeer,
              renderersReady: _callRenderersReady,
              localRenderer: _localCallRenderer,
              remoteRenderer: _remoteCallRenderer,
              localVideoLarge: _localVideoLarge,
              micMuted: _callMicMuted,
              speakerMuted: _callSpeakerMuted,
              cameraOff: _callCameraOff,
              statusText: _callStatusText,
              onAccept: _acceptCall,
              onReject: () => _cleanupCall(sendEnd: true),
              onHangup: () => _cleanupCall(sendEnd: true),
              onToggleMic: _toggleCallMic,
              onToggleSpeaker: _toggleCallSpeaker,
              onToggleCamera: _toggleCallCamera,
              onSwapVideo: () {
                setState(() => _localVideoLarge = !_localVideoLarge);
              },
            ),
        ],
      ),
    );
  }
}

class _CallOverlay extends StatelessWidget {
  const _CallOverlay({
    required this.phase,
    required this.kind,
    required this.peer,
    required this.renderersReady,
    required this.localRenderer,
    required this.remoteRenderer,
    required this.localVideoLarge,
    required this.micMuted,
    required this.speakerMuted,
    required this.cameraOff,
    required this.statusText,
    required this.onAccept,
    required this.onReject,
    required this.onHangup,
    required this.onToggleMic,
    required this.onToggleSpeaker,
    required this.onToggleCamera,
    required this.onSwapVideo,
  });

  final _CallPhase phase;
  final _CallKind kind;
  final ChatParticipant? peer;
  final bool renderersReady;
  final RTCVideoRenderer localRenderer;
  final RTCVideoRenderer remoteRenderer;
  final bool localVideoLarge;
  final bool micMuted;
  final bool speakerMuted;
  final bool cameraOff;
  final String? statusText;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onHangup;
  final VoidCallback onToggleMic;
  final VoidCallback onToggleSpeaker;
  final VoidCallback onToggleCamera;
  final VoidCallback onSwapVideo;

  @override
  Widget build(BuildContext context) {
    final name = peer?.title ?? 'Собеседник';
    final incoming = phase == _CallPhase.incoming;
    final video = kind == _CallKind.video;
    final status = statusText ??
        switch (phase) {
          _CallPhase.incoming => 'Входящий ${video ? 'видеозвонок' : 'звонок'}',
          _CallPhase.outgoing => 'Звоним...',
          _CallPhase.connected => 'Идет звонок',
          _CallPhase.idle => '',
        };

    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.42),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: _GlassSurface(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(18),
                radius: 34,
                color: const Color(0xE01D2025),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (video)
                      _CallVideoStage(
                        renderersReady: renderersReady,
                        localRenderer: localRenderer,
                        remoteRenderer: remoteRenderer,
                        localVideoLarge: localVideoLarge,
                        cameraOff: cameraOff,
                        onSwapVideo: onSwapVideo,
                      )
                    else
                      _CallAvatarStage(name: name, status: status),
                    const SizedBox(height: 18),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 5),
                    _CallStatusLine(text: status),
                    const SizedBox(height: 22),
                    if (incoming)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _CallRoundButton(
                            icon: Icons.call_end_rounded,
                            label: 'Отклонить',
                            color: danger,
                            onPressed: onReject,
                          ),
                          const SizedBox(width: 18),
                          _CallRoundButton(
                            icon: video
                                ? Icons.video_call_rounded
                                : Icons.call_rounded,
                            label: 'Принять',
                            color: const Color(0xFF65D48F),
                            onPressed: onAccept,
                          ),
                        ],
                      )
                    else
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 14,
                        runSpacing: 12,
                        children: [
                          _CallRoundButton(
                            icon: micMuted
                                ? Icons.mic_off_rounded
                                : Icons.mic_rounded,
                            label: micMuted ? 'Микрофон выкл.' : 'Микрофон',
                            active: !micMuted,
                            onPressed: onToggleMic,
                          ),
                          _CallRoundButton(
                            icon: speakerMuted
                                ? Icons.volume_off_rounded
                                : Icons.volume_up_rounded,
                            label: speakerMuted ? 'Звук выкл.' : 'Звук',
                            active: !speakerMuted,
                            onPressed: onToggleSpeaker,
                          ),
                          if (video)
                            _CallRoundButton(
                              icon: cameraOff
                                  ? Icons.videocam_off_rounded
                                  : Icons.videocam_rounded,
                              label: cameraOff ? 'Камера выкл.' : 'Камера',
                              active: !cameraOff,
                              onPressed: onToggleCamera,
                            ),
                          _CallRoundButton(
                            icon: Icons.call_end_rounded,
                            label: 'Завершить',
                            color: danger,
                            onPressed: onHangup,
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
    );
  }
}

class _CallVideoStage extends StatelessWidget {
  const _CallVideoStage({
    required this.renderersReady,
    required this.localRenderer,
    required this.remoteRenderer,
    required this.localVideoLarge,
    required this.cameraOff,
    required this.onSwapVideo,
  });

  final bool renderersReady;
  final RTCVideoRenderer localRenderer;
  final RTCVideoRenderer remoteRenderer;
  final bool localVideoLarge;
  final bool cameraOff;
  final VoidCallback onSwapVideo;

  @override
  Widget build(BuildContext context) {
    final mainRenderer = localVideoLarge ? localRenderer : remoteRenderer;
    final pipRenderer = localVideoLarge ? remoteRenderer : localRenderer;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                color: const Color(0xFF121419),
                child: renderersReady
                    ? RTCVideoView(mainRenderer,
                        objectFit:
                            RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                    : Center(child: CircularProgressIndicator()),
              ),
            ),
            if (cameraOff && localVideoLarge)
              Center(
                child: Icon(Icons.videocam_off_rounded, color: muted, size: 56),
              ),
            Positioned(
              right: 16,
              bottom: 16,
              child: GestureDetector(
                onTap: onSwapVideo,
                child: Container(
                  width: 150,
                  height: 92,
                  decoration: BoxDecoration(
                    color: const Color(0xC021242A),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: accent.withValues(alpha: 0.28)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.24),
                        blurRadius: 18,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: renderersReady
                      ? RTCVideoView(
                          pipRenderer,
                          mirror: false,
                          objectFit:
                              RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallAvatarStage extends StatelessWidget {
  const _CallAvatarStage({required this.name, required this.status});

  final String name;
  final String status;

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isEmpty ? 'B' : name.trim()[0].toUpperCase();
    return Container(
      width: 168,
      height: 168,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF796B45), Color(0xFF252015)],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.36), width: 2),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.13),
            blurRadius: 42,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 32,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Center(
        child: Text(
          letter,
          style: TextStyle(fontSize: 58, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class _CallStatusLine extends StatefulWidget {
  const _CallStatusLine({required this.text});

  final String text;

  @override
  State<_CallStatusLine> createState() => _CallStatusLineState();
}

class _CallStatusLineState extends State<_CallStatusLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.58, end: 1).animate(_controller),
      child: Text(
        widget.text,
        style: TextStyle(color: muted, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _CallRoundButton extends StatelessWidget {
  const _CallRoundButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
    this.active = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color? color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final fill =
        color ?? (active ? accent : Colors.white.withValues(alpha: 0.1));
    final foreground = color == null && active ? const Color(0xFF101318) : text;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onPressed,
          icon: Icon(icon),
          style: IconButton.styleFrom(
            fixedSize: const Size(58, 58),
            backgroundColor: fill,
            foregroundColor: foreground,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
            shadowColor: fill.withValues(alpha: 0.28),
            elevation: 8,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          label,
          style: TextStyle(color: muted, fontSize: 12),
        ),
      ],
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
    required this.typingPreviewByChat,
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
  final Map<String, String> typingPreviewByChat;
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
    final lightUi = _isLightUi(context);
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
          colors: lightUi
              ? [
                  const Color(0xFFFFFFFF).withValues(alpha: 0.96),
                  Color.alphaBlend(
                    accent.withValues(alpha: 0.035),
                    const Color(0xFFF1F4F8),
                  ),
                ]
              : [
                  const Color(0xFF24262C).withValues(alpha: 0.95),
                  const Color(0xFF181A1F).withValues(alpha: 0.93),
                ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: lightUi ? 0.06 : 0.18),
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
                          style: TextStyle(
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
                            style: TextStyle(color: muted),
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
              color: lightUi
                  ? Colors.white.withValues(alpha: 0.8)
                  : const Color(0x6614171C),
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
                ? Center(child: CircularProgressIndicator())
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
                          Divider(color: border.withValues(alpha: 0.8)),
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
                              typingPreview: typingPreviewByChat[chat.id],
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
        style: TextStyle(color: muted, fontSize: 13),
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
      color: _themeGlassColor(
        context,
        dark: const Color(0x8124272D),
        light: Colors.white.withValues(alpha: 0.78),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          splashColor: accent.withValues(alpha: 0.055),
          highlightColor: accent.withValues(alpha: 0.045),
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
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '@${user.username}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded, size: 15, color: muted),
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
          child: Icon(Icons.add_rounded, size: 20, color: muted),
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
    required this.typingPreview,
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
  final String? typingPreview;
  final VoidCallback onTap;
  final VoidCallback onToggleMute;
  final VoidCallback onTogglePinTop;
  final VoidCallback onToggleVerified;
  final VoidCallback onClearChat;
  final VoidCallback onDeleteChat;

  @override
  Widget build(BuildContext context) {
    final lightUi = _isLightUi(context);
    final unread = chat.unread[currentUserId] ?? 0;
    final peerOnline = chat.type == ChatType.direct &&
        chat.participantIds.any(
          (id) => id != currentUserId && onlineUserIds.contains(id),
        );
    final activityPreview = typingPreview;
    return GestureDetector(
      onSecondaryTapDown: (details) =>
          _showChatContextMenu(context, details.globalPosition),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: selected
              ? Color.alphaBlend(
                  accent.withValues(alpha: lightUi ? 0.16 : 0.12),
                  panelSoft.withValues(alpha: lightUi ? 0.94 : 0.84),
                )
              : _themeGlassColor(
                  context,
                  dark: Colors.white.withValues(alpha: 0.018),
                  light: Colors.white.withValues(alpha: 0.62),
                ),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: lightUi ? 0.28 : 0.18)
                : border.withValues(alpha: 0.74),
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color:
                        Colors.black.withValues(alpha: lightUi ? 0.07 : 0.12),
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
            highlightColor: accent.withValues(alpha: 0.045),
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
                              Icon(
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
                                      style: TextStyle(
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
                          activityPreview ??
                              _lastMessageLabel(chat.lastMessage?.text),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: activityPreview != null
                                ? accent
                                : selected
                                    ? text.withValues(alpha: 0.74)
                                    : muted,
                            fontSize: 13.5,
                            fontWeight: activityPreview != null
                                ? FontWeight.w800
                                : FontWeight.w500,
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
                            style: TextStyle(
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
    required this.vanishingMessageIds,
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
    required this.onStartAudioCall,
    required this.onStartVideoCall,
    required this.onUnpinMessage,
    required this.onOpenPinnedMessage,
    required this.onReply,
    required this.onEdit,
    required this.onForwardMessage,
    required this.onDeleteMessage,
    required this.onPinMessage,
    required this.onReaction,
    required this.playingVoiceKey,
    required this.voicePlayerState,
    required this.voicePosition,
    required this.voiceDuration,
    required this.onPlayVoice,
    required this.onSeekVoice,
    required this.messageKeyFor,
  });

  final Chat? chat;
  final String serverUrl;
  final User user;
  final List<Message> messages;
  final Set<String> vanishingMessageIds;
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
  final ValueChanged<Chat> onStartAudioCall;
  final ValueChanged<Chat> onStartVideoCall;
  final VoidCallback onUnpinMessage;
  final ValueChanged<Message> onOpenPinnedMessage;
  final ValueChanged<Message> onReply;
  final ValueChanged<Message> onEdit;
  final ValueChanged<Message> onForwardMessage;
  final ValueChanged<Message> onDeleteMessage;
  final ValueChanged<Message> onPinMessage;
  final void Function(Message message, String emoji) onReaction;
  final String? playingVoiceKey;
  final PlayerState voicePlayerState;
  final Duration voicePosition;
  final Duration voiceDuration;
  final ValueChanged<MessageMedia> onPlayVoice;
  final void Function(MessageMedia media, double progress) onSeekVoice;
  final GlobalKey Function(String messageId) messageKeyFor;

  @override
  Widget build(BuildContext context) {
    final chat = this.chat;
    if (chat == null) {
      return const EmptyState(
        title: 'Выберите чат',
        subtitle: 'Откройте переписку или найдите собеседника слева.',
      );
    }
    final canPost = chat.canPost(user.id);

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
        enabled:
            canPost && !sendingMedia && !recordingVoice && !recordingVideoNote,
        onDropFiles: onDropFiles,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: _isLightUi(context)
                  ? [
                      const Color(0xFFF7F9FC),
                      const Color(0xFFF1F4F8),
                      Color.alphaBlend(
                        accent.withValues(alpha: 0.035),
                        const Color(0xFFE9EEF5),
                      ),
                    ]
                  : const [
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
                    onStartAudioCall: () => onStartAudioCall(chat),
                    onStartVideoCall: () => onStartVideoCall(chat),
                  ),
                  if (pinnedMessage != null)
                    _PinnedBanner(
                      message: pinnedMessage!,
                      onTap: () => onOpenPinnedMessage(pinnedMessage!),
                      onClose: onUnpinMessage,
                    ),
                  if (error != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      color: danger.withValues(alpha: 0.12),
                      child: Text(error!, style: TextStyle(color: danger)),
                    ),
                  Expanded(
                    child: loading
                        ? Center(child: CircularProgressIndicator())
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
                                  return KeyedSubtree(
                                    key: messageKeyFor(message.id),
                                    child: _MessageBubble(
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
                                      vanishing: vanishingMessageIds
                                          .contains(message.id),
                                      onReply: () => onReply(message),
                                      onEdit: () => onEdit(message),
                                      onForward: () =>
                                          onForwardMessage(message),
                                      onDelete: () => onDeleteMessage(message),
                                      onPin: () => onPinMessage(message),
                                      onReaction: (emoji) =>
                                          onReaction(message, emoji),
                                      playingVoiceKey: playingVoiceKey,
                                      voicePlayerState: voicePlayerState,
                                      voicePosition: voicePosition,
                                      voiceDuration: voiceDuration,
                                      onPlayVoice: onPlayVoice,
                                      onSeekVoice: onSeekVoice,
                                    ),
                                  );
                                },
                              ),
                  ),
                  if (canPost)
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
                    )
                  else
                    _ChannelSubscribeBar(
                      muted: chat.muted,
                      onToggleMute: () => onToggleMute(chat),
                    ),
                ],
              ),
              if (recordingVideoNote)
                _VideoNoteRecordingOverlay(
                  level: recordingLevel,
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
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.cloud_upload_rounded,
                            color: accent,
                            size: 32,
                          ),
                          const SizedBox(width: 13),
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
    required this.onStartAudioCall,
    required this.onStartVideoCall,
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
  final VoidCallback onStartAudioCall;
  final VoidCallback onStartVideoCall;

  @override
  Widget build(BuildContext context) {
    final peer = chat.peerFor(currentUserId);
    final peerOnline = peer != null && onlineUserIds.contains(peer.id);
    final headerColor = _themeGlassColor(
      context,
      dark: const Color(0xDC191B20),
      light: const Color(0xEAF8FAFD),
    );
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: 66,
          padding: const EdgeInsets.symmetric(horizontal: 17),
          decoration: BoxDecoration(
            color: headerColor,
            border: Border(
              bottom: BorderSide(color: border.withValues(alpha: 0.8)),
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
                              style: TextStyle(
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
              if (chat.type != ChatType.channel) ...[
                _SoftIconButton(
                  tooltip: chat.type == ChatType.direct
                      ? 'Аудиозвонок'
                      : 'Групповые звонки готовятся',
                  onPressed:
                      chat.type == ChatType.direct ? onStartAudioCall : null,
                  icon: Icons.call_rounded,
                ),
                const SizedBox(width: 6),
                _SoftIconButton(
                  tooltip: chat.type == ChatType.direct
                      ? 'Видеозвонок'
                      : 'Групповые видеозвонки готовятся',
                  onPressed:
                      chat.type == ChatType.direct ? onStartVideoCall : null,
                  icon: Icons.videocam_rounded,
                ),
                const SizedBox(width: 6),
              ],
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
                  child: Icon(Icons.more_vert_rounded, color: muted),
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
    required this.onTap,
    required this.onClose,
  });

  final Message message;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return _GlassSurface(
      margin: const EdgeInsets.fromLTRB(18, 12, 18, 0),
      padding: EdgeInsets.zero,
      radius: 18,
      color: const Color(0xA1282A2F),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                  child: Icon(
                    Icons.push_pin_rounded,
                    color: accent,
                    size: 17,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
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
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Открепить',
                  onPressed: onClose,
                  icon: Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
        ),
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
            ? widget.typingNames.join(', ')
            : widget.typingNames.first
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
                    style: TextStyle(
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
                            child: Text(
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
              style: TextStyle(color: muted),
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
    return _GlassSurface(
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
                      style: TextStyle(
                        color: text,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatDuration(_elapsedMs),
                      style: TextStyle(
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
            icon: Icon(Icons.close_rounded),
            label: Text('Отмена'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: widget.onFinish,
            icon: Icon(Icons.send_rounded, size: 18),
            label: Text('Отправить'),
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: const Color(0xFF101318),
            ),
          ),
        ],
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
  const _VideoNoteRecordingOverlay({
    required this.level,
    required this.onCameraReady,
  });

  final double level;
  final ValueChanged<CameraMacOSController> onCameraReady;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: AnimatedScale(
            scale: 1 + level.clamp(0, 1) * 0.025,
            duration: const Duration(milliseconds: 90),
            curve: Curves.easeOutCubic,
            child: CustomPaint(
              painter: _VideoNoteRingWavePainter(level: level),
              child: Padding(
                padding: const EdgeInsets.all(15),
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
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                ),
                              )
                            : ColoredBox(
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
          ),
        ),
      ),
    );
  }
}

class _VideoNoteRingWavePainter extends CustomPainter {
  const _VideoNoteRingWavePainter({required this.level});

  final double level;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 8;
    final paint = Paint()
      ..color = accent.withValues(alpha: 0.62)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4.4;
    const bars = 48;
    final energy = level.clamp(0.12, 1.0);
    for (var i = 0; i < bars; i++) {
      final angle = (i / bars) * math.pi * 2;
      final wave =
          math.sin(i * 0.92 + DateTime.now().millisecondsSinceEpoch / 120);
      final height = 5 + (wave * 0.5 + 0.5) * 16 * energy;
      final start = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      final end = Offset(
        center.dx + math.cos(angle) * (radius + height),
        center.dy + math.sin(angle) * (radius + height),
      );
      canvas.drawLine(start, end, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _VideoNoteRingWavePainter oldDelegate) {
    return oldDelegate.level != level;
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
    final lightUi = _isLightUi(context);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          decoration: BoxDecoration(
            color: lightUi
                ? Colors.white.withValues(alpha: 0.78)
                : const Color(0xD0181A1E),
            border: Border(
              top: BorderSide(
                color: lightUi
                    ? border.withValues(alpha: 0.85)
                    : Colors.white.withValues(alpha: 0.075),
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: lightUi ? 0.06 : 0.24),
                blurRadius: 28,
                offset: const Offset(0, -10),
              ),
            ],
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
                  color: lightUi
                      ? Colors.white.withValues(alpha: 0.82)
                      : const Color(0x80272A30),
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
                              style: TextStyle(
                                color: accent,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              _messagePreview(modeMessage),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: muted),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Отмена',
                        onPressed: onCancelMode,
                        icon: Icon(Icons.close_rounded),
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

class _ChannelSubscribeBar extends StatelessWidget {
  const _ChannelSubscribeBar({
    required this.muted,
    required this.onToggleMute,
  });

  final bool muted;
  final VoidCallback onToggleMute;

  @override
  Widget build(BuildContext context) {
    final lightUi = _isLightUi(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
      child: _GlassSurface(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        radius: 26,
        color: lightUi
            ? Colors.white.withValues(alpha: 0.78)
            : const Color(0xB01D2026),
        child: Row(
          children: [
            Icon(
              muted
                  ? Icons.notifications_off_rounded
                  : Icons.notifications_active_rounded,
              color: accent,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                muted
                    ? 'Уведомления канала выключены'
                    : 'Вы подписаны на канал',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: onToggleMute,
              icon: Icon(
                muted
                    ? Icons.notifications_rounded
                    : Icons.notifications_off_rounded,
              ),
              label: Text(muted ? 'Включить звук' : 'Выключить звук'),
            ),
          ],
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
    final lightUi = _isLightUi(context);
    return _GlassSurface(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      radius: 30,
      color: lightUi
          ? Colors.white.withValues(alpha: 0.82)
          : const Color(0xA51B1D22),
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
                  fillColor: lightUi
                      ? const Color(0xFFF2F5F9)
                      : const Color(0x77121418),
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
                      color: accent.withValues(alpha: lightUi ? 0.28 : 0.18),
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
    final lightUi = _isLightUi(context);
    final icon = widget.shouldSend
        ? Icons.send_rounded
        : isVideo
            ? Icons.motion_photos_on_rounded
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
                  ? (lightUi
                      ? const Color(0xFFE8EDF4)
                      : Colors.white.withValues(alpha: 0.08))
                  : active
                      ? accent
                      : lightUi
                          ? Color.alphaBlend(
                              accent.withValues(alpha: 0.08),
                              Colors.white,
                            )
                          : const Color(0xFF2D261C),
              border: Border.all(
                color: lightUi
                    ? border.withValues(alpha: 0.9)
                    : Colors.white.withValues(alpha: 0.08),
              ),
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
              color: active
                  ? const Color(0xFF101318)
                  : lightUi
                      ? HSLColor.fromColor(accent).withLightness(0.42).toColor()
                      : accent,
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
    required this.vanishing,
    required this.onReply,
    required this.onEdit,
    required this.onForward,
    required this.onDelete,
    required this.onPin,
    required this.onReaction,
    required this.playingVoiceKey,
    required this.voicePlayerState,
    required this.voicePosition,
    required this.voiceDuration,
    required this.onPlayVoice,
    required this.onSeekVoice,
  });

  final Message message;
  final String serverUrl;
  final bool own;
  final bool? readByRecipients;
  final bool vanishing;
  final VoidCallback onReply;
  final VoidCallback onEdit;
  final VoidCallback onForward;
  final VoidCallback onDelete;
  final VoidCallback onPin;
  final ValueChanged<String> onReaction;
  final String? playingVoiceKey;
  final PlayerState voicePlayerState;
  final Duration voicePosition;
  final Duration voiceDuration;
  final ValueChanged<MessageMedia> onPlayVoice;
  final void Function(MessageMedia media, double progress) onSeekVoice;

  @override
  Widget build(BuildContext context) {
    final media = message.media;
    final lightUi = _isLightUi(context);
    final mediaOnly = !message.deleted &&
        message.text.trim().isEmpty &&
        (message.imageUrl?.isNotEmpty == true ||
            media?.kind == 'voice' ||
            media?.kind == 'video_note' ||
            media?.kind == 'image' ||
            media?.kind == 'video' ||
            media?.mimeType?.startsWith('video/') == true);
    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOutCubic,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 210),
        opacity: vanishing ? 0 : 1,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeInBack,
          scale: vanishing ? 0.86 : 1,
          child: GestureDetector(
            onDoubleTap: message.deleted ? null : onReply,
            onSecondaryTapDown: (details) {
              _showMessageMenu(context, details.globalPosition);
            },
            child: Align(
              alignment: own ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 560),
                margin: const EdgeInsets.only(bottom: 7),
                child: Column(
                  crossAxisAlignment:
                      own ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: mediaOnly
                          ? EdgeInsets.zero
                          : const EdgeInsets.fromLTRB(15, 6, 12, 5),
                      decoration: mediaOnly
                          ? null
                          : BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: lightUi
                                    ? own
                                        ? [
                                            Color.alphaBlend(
                                              accent.withValues(alpha: 0.13),
                                              Colors.white,
                                            ),
                                            Color.alphaBlend(
                                              accent.withValues(alpha: 0.07),
                                              const Color(0xFFF4F6FA),
                                            ),
                                          ]
                                        : [
                                            Colors.white
                                                .withValues(alpha: 0.98),
                                            const Color(0xFFF1F4F8),
                                          ]
                                    : own
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
                                color: lightUi
                                    ? own
                                        ? accent.withValues(alpha: 0.2)
                                        : border.withValues(alpha: 0.75)
                                    : own
                                        ? accent.withValues(alpha: 0.13)
                                        : Colors.white.withValues(alpha: 0.095),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black
                                      .withValues(alpha: lightUi ? 0.07 : 0.15),
                                  blurRadius: lightUi ? 16 : 18,
                                  offset: Offset(0, lightUi ? 8 : 10),
                                ),
                                BoxShadow(
                                  color: Colors.white
                                      .withValues(alpha: lightUi ? 0.55 : 0.05),
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
                            playingVoiceKey: playingVoiceKey,
                            voicePlayerState: voicePlayerState,
                            voicePosition: voicePosition,
                            voiceDuration: voiceDuration,
                            onPlayVoice: onPlayVoice,
                            onSeekVoice: onSeekVoice,
                          ),
                          const SizedBox(height: 3),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (message.editedAt != null &&
                                  !message.deleted) ...[
                                Text(
                                  'изм.',
                                  style: TextStyle(
                                    color: muted,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ],
                              Text(
                                _formatTime(message.createdAt),
                                style: TextStyle(
                                  color: muted,
                                  fontSize: 12,
                                ),
                              ),
                              if (own && !message.deleted) ...[
                                const SizedBox(width: 5),
                                _MessageReadTicks(
                                  read: readByRecipients == true,
                                ),
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
                              color: lightUi
                                  ? Colors.white.withValues(alpha: 0.88)
                                  : const Color(0xCC282B31),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: lightUi
                                    ? border.withValues(alpha: 0.72)
                                    : Colors.white.withValues(alpha: 0.08),
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
          ),
        ),
      ),
    );
  }

  Future<void> _showMessageMenu(BuildContext context, Offset position) async {
    final value = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Закрыть меню',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 140),
      pageBuilder: (context, _, __) => _MessageActionOverlay(
        position: position,
        message: message,
        own: own,
      ),
      transitionBuilder: (context, animation, _, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: ScaleTransition(
            alignment: Alignment.topCenter,
            scale: Tween<double>(begin: 0.96, end: 1).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
    );
    if (!context.mounted) return;

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
      case 'forward':
        onForward();
      case 'delete':
        onDelete();
      case 'select':
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Массовый выбор сообщений пока готовится')),
        );
    }
  }
}

class _MessageActionOverlay extends StatelessWidget {
  const _MessageActionOverlay({
    required this.position,
    required this.message,
    required this.own,
  });

  final Offset position;
  final Message message;
  final bool own;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    const menuWidth = 304.0;
    const reactionWidth = 360.0;
    final maxMenuLeft = math.max(14.0, size.width - menuWidth - 14);
    final maxReactionLeft = math.max(14.0, size.width - reactionWidth - 14);
    final maxTop = math.max(14.0, size.height - 430);
    final left = (position.dx - (own ? menuWidth * 0.9 : 40))
        .clamp(14.0, maxMenuLeft)
        .toDouble();
    final top = (position.dy - 74).clamp(14.0, maxTop).toDouble();
    final reactionLeft = (left - 18).clamp(14.0, maxReactionLeft).toDouble();
    final hasText = message.text.trim().isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.pop(context),
            ),
          ),
          Positioned(
            left: reactionLeft,
            top: top,
            child: _ReactionStrip(
              onSelected: (emoji) => Navigator.pop(context, 'react:$emoji'),
            ),
          ),
          Positioned(
            left: left,
            top: top + 58,
            child: _GlassMessageMenu(
              width: menuWidth,
              children: [
                _MessageMenuRow(
                  icon: Icons.reply_rounded,
                  label: 'Ответить',
                  onTap: () => Navigator.pop(context, 'reply'),
                ),
                if (hasText)
                  _MessageMenuRow(
                    icon: Icons.copy_rounded,
                    label: 'Скопировать',
                    onTap: () => Navigator.pop(context, 'copy'),
                  ),
                if (own && !message.deleted)
                  _MessageMenuRow(
                    icon: Icons.edit_square,
                    label: 'Изменить',
                    onTap: () => Navigator.pop(context, 'edit'),
                  ),
                _MessageMenuRow(
                  icon: Icons.push_pin_outlined,
                  label: 'Закрепить',
                  onTap: () => Navigator.pop(context, 'pin'),
                ),
                _MessageMenuRow(
                  icon: Icons.ios_share_rounded,
                  label: 'Переслать',
                  onTap: () => Navigator.pop(context, 'forward'),
                ),
                if (own)
                  _MessageMenuRow(
                    icon: Icons.delete_outline_rounded,
                    label: 'Удалить',
                    dangerAction: true,
                    onTap: () => Navigator.pop(context, 'delete'),
                  ),
                const _MessageMenuDivider(),
                _MessageMenuRow(
                  icon: Icons.check_circle_outline_rounded,
                  label: 'Выбрать',
                  onTap: () => Navigator.pop(context, 'select'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReactionStrip extends StatelessWidget {
  const _ReactionStrip({required this.onSelected});

  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return _GlassSurface(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      radius: 24,
      color: const Color(0xEC191A1F),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ..._quickReactions.map(
            (emoji) => InkWell(
              onTap: () => onSelected(emoji),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                child: Text(emoji, style: TextStyle(fontSize: 25)),
              ),
            ),
          ),
          const SizedBox(width: 5),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.07),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.keyboard_arrow_down_rounded, color: muted),
          ),
        ],
      ),
    );
  }
}

class _GlassMessageMenu extends StatelessWidget {
  const _GlassMessageMenu({
    required this.width,
    required this.children,
  });

  final double width;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          width: width,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xEC17181D),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.42),
                blurRadius: 34,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }
}

class _MessageMenuRow extends StatelessWidget {
  const _MessageMenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.dangerAction = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool dangerAction;

  @override
  Widget build(BuildContext context) {
    final color = dangerAction ? danger : text;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageMenuDivider extends StatelessWidget {
  const _MessageMenuDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
      child: Divider(height: 1, color: Colors.white.withValues(alpha: 0.09)),
    );
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
    required this.playingVoiceKey,
    required this.voicePlayerState,
    required this.voicePosition,
    required this.voiceDuration,
    required this.onPlayVoice,
    required this.onSeekVoice,
  });

  final Message message;
  final String serverUrl;
  final String? playingVoiceKey;
  final PlayerState voicePlayerState;
  final Duration voicePosition;
  final Duration voiceDuration;
  final ValueChanged<MessageMedia> onPlayVoice;
  final void Function(MessageMedia media, double progress) onSeekVoice;

  @override
  Widget build(BuildContext context) {
    if (message.deleted) {
      return Text(
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
            playingVoiceKey: playingVoiceKey,
            voicePlayerState: voicePlayerState,
            voicePosition: voicePosition,
            voiceDuration: voiceDuration,
            onPlayVoice: onPlayVoice,
            onSeekVoice: onSeekVoice,
          ),
        if (message.imageUrl?.isNotEmpty == true)
          _LegacyImagePreview(dataUrl: message.imageUrl!, serverUrl: serverUrl),
        if (text.isNotEmpty) ...[
          if (media != null || message.imageUrl?.isNotEmpty == true)
            const SizedBox(height: 8),
          Text(
            text,
            style: TextStyle(color: textColorAlias, fontSize: 15),
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
          Text('Сообщение', style: TextStyle(fontSize: 15)),
      ],
    );
  }
}

final textColorAlias = text;

class _EncryptedMessageNotice extends StatelessWidget {
  const _EncryptedMessageNotice();

  @override
  Widget build(BuildContext context) {
    return Row(
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
    required this.playingVoiceKey,
    required this.voicePlayerState,
    required this.voicePosition,
    required this.voiceDuration,
    required this.onPlayVoice,
    required this.onSeekVoice,
  });

  final MessageMedia media;
  final String serverUrl;
  final String? playingVoiceKey;
  final PlayerState voicePlayerState;
  final Duration voicePosition;
  final Duration voiceDuration;
  final ValueChanged<MessageMedia> onPlayVoice;
  final void Function(MessageMedia media, double progress) onSeekVoice;

  @override
  Widget build(BuildContext context) {
    if (media.kind == 'image') {
      return _ImagePreview(source: media.dataUrl, serverUrl: serverUrl);
    }
    if (media.kind == 'voice') {
      return _VoicePreview(
        media: media,
        playing: playingVoiceKey == _mediaPlaybackKey(media) &&
            voicePlayerState == PlayerState.playing,
        position: playingVoiceKey == _mediaPlaybackKey(media)
            ? voicePosition
            : Duration.zero,
        duration: playingVoiceKey == _mediaPlaybackKey(media)
            ? voiceDuration
            : Duration(milliseconds: media.durationMs ?? 0),
        onPlay: () => onPlayVoice(media),
        onSeek: (progress) => onSeekVoice(media, progress),
      );
    }
    if (media.kind == 'video_note') {
      return _VideoNotePreview(media: media, serverUrl: serverUrl);
    }
    if (media.mimeType?.startsWith('video/') == true || media.kind == 'video') {
      return _VideoPreview(media: media, serverUrl: serverUrl);
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
              style: TextStyle(fontWeight: FontWeight.w700),
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
    required this.playing,
    required this.position,
    required this.duration,
    required this.onPlay,
    required this.onSeek,
  });

  final MessageMedia media;
  final bool playing;
  final Duration position;
  final Duration duration;
  final VoidCallback onPlay;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    final fallbackMs = media.durationMs ?? 0;
    final totalMs =
        duration.inMilliseconds > 0 ? duration.inMilliseconds : fallbackMs;
    final progress = totalMs <= 0
        ? 0.0
        : (position.inMilliseconds / totalMs).clamp(0.0, 1.0);
    return _GlassSurface(
      width: 292,
      padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
      radius: 25,
      color: const Color(0xA0202328),
      child: Row(
        children: [
          IconButton.filled(
            tooltip: playing ? 'Пауза' : 'Воспроизвести',
            onPressed: onPlay,
            icon: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            ),
            style: IconButton.styleFrom(
              fixedSize: const Size(48, 48),
              backgroundColor: accent,
              foregroundColor: const Color(0xFF08131A),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Голосовое',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) {
                    final width = context.size?.width ?? 1;
                    onSeek(details.localPosition.dx / width);
                  },
                  child: SizedBox(
                    height: 26,
                    child: CustomPaint(
                      painter: _VoiceWavePreviewPainter(
                        seed: (media.durationMs ?? 1) / 1000,
                        progress: progress,
                        playing: playing,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _formatDuration(
              playing || position.inMilliseconds > 0
                  ? position.inMilliseconds
                  : totalMs,
            ),
            style: TextStyle(color: muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _VoiceWavePreviewPainter extends CustomPainter {
  const _VoiceWavePreviewPainter({
    required this.seed,
    required this.progress,
    required this.playing,
  });

  final double seed;
  final double progress;
  final bool playing;

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
      final pulse = playing
          ? math.sin(DateTime.now().millisecondsSinceEpoch / 130 + i) * 1.6
          : 0.0;
      final height =
          (5 + wave * (size.height - 7) + pulse).clamp(4, size.height);
      final x = gap * i + gap / 2;
      final activeBar = i / bars <= progress;
      canvas.drawLine(
        Offset(x, center - height / 2),
        Offset(x, center + height / 2),
        activeBar ? active : passive,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VoiceWavePreviewPainter oldDelegate) {
    return oldDelegate.seed != seed ||
        oldDelegate.progress != progress ||
        oldDelegate.playing != playing;
  }
}

class _VideoNotePreview extends StatelessWidget {
  const _VideoNotePreview({
    required this.media,
    required this.serverUrl,
  });

  final MessageMedia media;
  final String serverUrl;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openVideoNoteViewer(context, media, serverUrl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.94, end: 1),
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutBack,
            builder: (context, scale, child) {
              return Transform.scale(scale: scale, child: child);
            },
            child: _VideoNoteCircle(
              media: media,
              serverUrl: serverUrl,
              size: 246,
              autoplay: false,
            ),
          ),
          if ((media.durationMs ?? 0) > 0) ...[
            const SizedBox(height: 6),
            Text(
              _formatDuration(media.durationMs ?? 0),
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _VideoNoteCircle extends StatefulWidget {
  const _VideoNoteCircle({
    required this.media,
    required this.serverUrl,
    required this.size,
    required this.autoplay,
  });

  final MessageMedia media;
  final String serverUrl;
  final double size;
  final bool autoplay;

  @override
  State<_VideoNoteCircle> createState() => _VideoNoteCircleState();
}

class _VideoNoteCircleState extends State<_VideoNoteCircle> {
  VideoPlayerController? _controller;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  @override
  void didUpdateWidget(covariant _VideoNoteCircle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media.dataUrl != widget.media.dataUrl) {
      unawaited(_prepare());
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final previous = _controller;
    _controller = null;
    await previous?.dispose();
    try {
      final controller = await _createVideoController(
        widget.media.dataUrl,
        widget.serverUrl,
        mimeType: widget.media.mimeType ?? 'video/mp4',
      );
      await controller.initialize();
      await controller.setLooping(false);
      if (widget.autoplay) {
        await controller.play();
      }
      controller.addListener(() {
        if (mounted) setState(() {});
      });
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final activeController =
        controller != null && controller.value.isInitialized
            ? controller
            : null;
    final playing = activeController?.value.isPlaying == true;
    final progress = activeController != null &&
            activeController.value.duration.inMilliseconds > 0
        ? (activeController.value.position.inMilliseconds /
                activeController.value.duration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;
    return GestureDetector(
      onTap: activeController != null
          ? () {
              if (playing) {
                activeController.pause();
              } else {
                activeController.play();
              }
            }
          : null,
      child: AnimatedScale(
        scale: playing ? 1.045 : 1,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: accent.withValues(alpha: 0.38), width: 3),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 28,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: activeController != null
                    ? FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: activeController.value.size.width,
                          height: activeController.value.size.height,
                          child: VideoPlayer(activeController),
                        ),
                      )
                    : const ColoredBox(color: Color(0xFF181A1F)),
              ),
              if (_loading)
                const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (_failed)
                Icon(Icons.error_outline_rounded, color: muted, size: 34)
              else if (!playing)
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.36),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.16),
                    ),
                  ),
                  child: Icon(
                    Icons.play_arrow_rounded,
                    color: accent,
                    size: 32,
                  ),
                ),
              Positioned.fill(
                child: CustomPaint(
                  painter: _VideoNoteProgressPainter(progress: progress),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoNoteProgressPainter extends CustomPainter {
  const _VideoNoteProgressPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final paint = Paint()
      ..color = accent.withValues(alpha: 0.82)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final rect = Offset.zero & size;
    canvas.drawArc(
      rect.deflate(5),
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _VideoNoteProgressPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _VideoPreview extends StatefulWidget {
  const _VideoPreview({required this.media, required this.serverUrl});

  final MessageMedia media;
  final String serverUrl;

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  VideoPlayerController? _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    try {
      final controller = await _createVideoController(
        widget.media.dataUrl,
        widget.serverUrl,
        mimeType: widget.media.mimeType ?? 'video/mp4',
      );
      await controller.initialize();
      controller.addListener(() {
        if (mounted) setState(() {});
      });
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _loading = false;
      });
    } on Object {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final activeController =
        controller != null && controller.value.isInitialized
            ? controller
            : null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 320,
        constraints: const BoxConstraints(maxHeight: 220),
        color: Colors.black.withValues(alpha: 0.24),
        child: AspectRatio(
          aspectRatio: activeController?.value.aspectRatio ?? 16 / 9,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (activeController != null) VideoPlayer(activeController),
              if (_loading)
                const CircularProgressIndicator(strokeWidth: 2)
              else
                IconButton.filled(
                  onPressed: activeController != null
                      ? () {
                          activeController.value.isPlaying
                              ? activeController.pause()
                              : activeController.play();
                        }
                      : null,
                  icon: Icon(
                    controller?.value.isPlaying == true
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.4),
                    foregroundColor: accent,
                  ),
                ),
            ],
          ),
        ),
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
      return Text('Фото не удалось открыть');
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
        borderRadius: BorderRadius.circular(18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 420,
            maxHeight: 360,
            minWidth: 120,
            minHeight: 90,
          ),
          child: bytes != null
              ? Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                )
              : BrenksCachedNetworkImage(
                  url: url!,
                  fit: BoxFit.contain,
                  placeholder: const SizedBox(
                    width: 260,
                    height: 180,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  errorWidget: const Padding(
                    padding: EdgeInsets.all(14),
                    child: Text('Фото не удалось загрузить'),
                  ),
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
                      Expanded(
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
                        icon: Icon(Icons.close_rounded),
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
                  Text(
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
                                        style: TextStyle(
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
                    icon: Icon(Icons.check_rounded),
                    label: Text('Создать папку'),
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
                    Expanded(
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
                    prefixIcon: Icon(Icons.edit_rounded),
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('Отмена'),
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
                        child: Text('Создать'),
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

class _MediaSendResult {
  const _MediaSendResult({
    required this.caption,
    required this.items,
  });

  final String caption;
  final List<_MediaSendItem> items;
}

class _MediaSendItem {
  const _MediaSendItem({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;
}

class _MediaSendPreviewDialog extends StatefulWidget {
  const _MediaSendPreviewDialog({
    required this.initialItems,
    required this.initialCaption,
  });

  final List<_MediaSendItem> initialItems;
  final String initialCaption;

  @override
  State<_MediaSendPreviewDialog> createState() =>
      _MediaSendPreviewDialogState();
}

class _MediaSendPreviewDialogState extends State<_MediaSendPreviewDialog> {
  late final TextEditingController _captionController;
  late List<_MediaSendItem> _items;
  final Map<int, int> _turns = {};
  int _activeIndex = 0;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _items = [...widget.initialItems];
    _captionController = TextEditingController(text: widget.initialCaption);
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = _items[_activeIndex];
    final isImage = item.mimeType.startsWith('image/');
    final title = _items.length == 1
        ? (isImage ? 'Отправить фото' : 'Отправить видео')
        : 'Отправить медиа (${_items.length})';
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): _submit,
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): _submit,
      },
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              width: 620,
              constraints: const BoxConstraints(maxHeight: 790),
              padding: const EdgeInsets.all(20),
              decoration: _glassDecoration(
                color: panel.withValues(alpha: 0.92),
                radius: 32,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Добавить фото или видео',
                        onPressed: _pickMore,
                        icon: Icon(Icons.add_rounded),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Закрыть',
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Flexible(
                    child: Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Container(
                          constraints: const BoxConstraints(
                            maxWidth: 560,
                            maxHeight: 430,
                            minHeight: 240,
                          ),
                          color: Colors.black.withValues(alpha: 0.18),
                          child: isImage
                              ? RotatedBox(
                                  quarterTurns: _turns[_activeIndex] ?? 0,
                                  child: InteractiveViewer(
                                    minScale: 0.8,
                                    maxScale: 4,
                                    child: Image.memory(
                                      item.bytes,
                                      fit: BoxFit.contain,
                                      gaplessPlayback: true,
                                    ),
                                  ),
                                )
                              : Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.play_circle_fill_rounded,
                                        color: accent,
                                        size: 72,
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        item.fileName,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: isImage ? _rotateActiveImage : null,
                        icon: Icon(Icons.rotate_90_degrees_ccw_rounded),
                        label: Text('Коррекция'),
                      ),
                      const SizedBox(width: 10),
                      if (_items.length > 1)
                        Expanded(
                          child: SizedBox(
                            height: 58,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _items.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 8),
                              itemBuilder: (context, index) {
                                return _MediaSendThumb(
                                  item: _items[index],
                                  active: index == _activeIndex,
                                  onTap: () =>
                                      setState(() => _activeIndex = index),
                                  onRemove: _items.length <= 1
                                      ? null
                                      : () => _removeItem(index),
                                );
                              },
                            ),
                          ),
                        )
                      else
                        Expanded(
                          child: Text(
                            item.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: muted),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _captionController,
                    autofocus: true,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Добавить подпись',
                      prefixIcon: Icon(Icons.short_text_rounded),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text('Отмена'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _submitting ? null : _submit,
                          icon: _submitting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Icon(Icons.send_rounded),
                          label: Text(_items.length > 1
                              ? 'Отправить ${_items.length}'
                              : 'Отправить'),
                        ),
                      ),
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

  Future<void> _pickMore() async {
    final result = await FilePicker.pickFiles(
      type: FileType.media,
      withData: true,
      allowMultiple: true,
    );
    final files = result?.files ?? const <PlatformFile>[];
    if (files.isEmpty || !mounted) return;
    final next = [..._items];
    for (final file in files) {
      final bytes = file.bytes ??
          (file.path == null ? null : await io.File(file.path!).readAsBytes());
      if (bytes == null || bytes.isEmpty) continue;
      final mimeType = lookupMimeType(
            file.name,
            headerBytes: bytes.take(16).toList(),
          ) ??
          'application/octet-stream';
      if (!mimeType.startsWith('image/') && !mimeType.startsWith('video/')) {
        continue;
      }
      next.add(_MediaSendItem(
        bytes: Uint8List.fromList(bytes),
        fileName: file.name,
        mimeType: mimeType,
      ));
    }
    if (!mounted) return;
    setState(() {
      _items = next;
      _activeIndex = _items.length - 1;
    });
  }

  void _removeItem(int index) {
    setState(() {
      final oldTurns = Map<int, int>.from(_turns);
      _items = [..._items]..removeAt(index);
      _turns
        ..clear()
        ..addEntries(oldTurns.entries
            .where((entry) => entry.key != index)
            .map((entry) => MapEntry(
                  entry.key > index ? entry.key - 1 : entry.key,
                  entry.value,
                )));
      _activeIndex = math.min(_activeIndex, _items.length - 1);
    });
  }

  void _rotateActiveImage() {
    setState(() {
      _turns[_activeIndex] = ((_turns[_activeIndex] ?? 0) + 1) % 4;
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final prepared = <_MediaSendItem>[];
    for (var i = 0; i < _items.length; i++) {
      final item = _items[i];
      final turns = _turns[i] ?? 0;
      if (turns == 0 || !item.mimeType.startsWith('image/')) {
        prepared.add(item);
        continue;
      }
      final rotated = await _rotateImageBytes(item.bytes, turns);
      prepared.add(_MediaSendItem(
        bytes: rotated ?? item.bytes,
        fileName: item.fileName.replaceFirst(RegExp(r'\.[^.]*$'), '.png'),
        mimeType: rotated == null ? item.mimeType : 'image/png',
      ));
    }
    if (!mounted) return;
    Navigator.pop(
      context,
      _MediaSendResult(caption: _captionController.text, items: prepared),
    );
  }
}

class _MediaSendThumb extends StatelessWidget {
  const _MediaSendThumb({
    required this.item,
    required this.active,
    required this.onTap,
    required this.onRemove,
  });

  final _MediaSendItem item;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final isImage = item.mimeType.startsWith('image/');
    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: panelSoft.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: active
                    ? accent.withValues(alpha: 0.72)
                    : Colors.white.withValues(alpha: 0.1),
                width: active ? 2 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: isImage
                ? Image.memory(item.bytes, fit: BoxFit.cover)
                : Icon(Icons.play_circle_fill_rounded, color: accent),
          ),
        ),
        if (onRemove != null)
          Positioned(
            right: -7,
            top: -7,
            child: InkWell(
              onTap: onRemove,
              customBorder: const CircleBorder(),
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: danger,
                  shape: BoxShape.circle,
                  border: Border.all(color: panel),
                ),
                child: const Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

Future<Uint8List?> _rotateImageBytes(Uint8List bytes, int quarterTurns) async {
  final turns = quarterTurns % 4;
  if (turns == 0) return bytes;
  ui.Codec? codec;
  ui.Image? source;
  ui.Image? rotated;
  try {
    codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    source = frame.image;
    final sourceWidth = source.width;
    final sourceHeight = source.height;
    final targetWidth = turns.isOdd ? sourceHeight : sourceWidth;
    final targetHeight = turns.isOdd ? sourceWidth : sourceHeight;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    switch (turns) {
      case 1:
        canvas
          ..translate(targetWidth.toDouble(), 0)
          ..rotate(math.pi / 2);
      case 2:
        canvas
          ..translate(targetWidth.toDouble(), targetHeight.toDouble())
          ..rotate(math.pi);
      case 3:
        canvas
          ..translate(0, targetHeight.toDouble())
          ..rotate(-math.pi / 2);
    }

    canvas.drawImage(source, Offset.zero, ui.Paint());
    final picture = recorder.endRecording();
    rotated = await picture.toImage(targetWidth, targetHeight);
    picture.dispose();
    final data = await rotated.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } on Object {
    return null;
  } finally {
    source?.dispose();
    rotated?.dispose();
    codec?.dispose();
  }
}

class _AvatarPreviewDialog extends StatelessWidget {
  const _AvatarPreviewDialog({
    required this.dataUrl,
    required this.title,
    required this.serverUrl,
  });

  final String dataUrl;
  final String title;
  final String serverUrl;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            width: 430,
            padding: const EdgeInsets.all(22),
            decoration: _glassDecoration(
              color: panel.withValues(alpha: 0.92),
              radius: 32,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Фото профиля',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 18),
                Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: accent.withValues(alpha: 0.3),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.34),
                        blurRadius: 28,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: BrenksAvatar(
                    title: title,
                    imageUrl: dataUrl,
                    baseUrl: serverUrl,
                    size: 220,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Проверьте, как аватарка будет выглядеть в круге.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('Отмена'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, dataUrl),
                        child: Text('Применить'),
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
}

class _PickUsersDialog extends StatefulWidget {
  const _PickUsersDialog({
    required this.api,
    required this.serverUrl,
    required this.title,
    required this.excludedUserIds,
  });

  final ApiClient api;
  final String serverUrl;
  final String title;
  final Set<String> excludedUserIds;

  @override
  State<_PickUsersDialog> createState() => _PickUsersDialogState();
}

class _PickUsersDialogState extends State<_PickUsersDialog> {
  final _controller = TextEditingController();
  final Set<String> _selectedIds = {};
  List<DirectoryUser> _results = const [];
  Timer? _debounce;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _scheduleSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 260), _search);
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.length < 2) {
      setState(() {
        _results = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final found = await widget.api.searchUsers(query);
      if (!mounted) return;
      setState(() {
        _results = found
            .where((user) => !widget.excludedUserIds.contains(user.id))
            .toList(growable: false);
        _loading = false;
      });
    } on Object catch (err) {
      if (!mounted) return;
      setState(() {
        _error = err.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            width: 520,
            constraints: const BoxConstraints(maxHeight: 620),
            decoration: _glassDecoration(
              color: panel.withValues(alpha: 0.9),
              radius: 32,
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 20, 16, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.title,
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Закрыть',
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    onChanged: (_) => _scheduleSearch(),
                    decoration: const InputDecoration(
                      hintText: 'Введите @username',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _loading
                      ? Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(
                              child: Text(
                                'Не удалось выполнить поиск',
                                style: TextStyle(color: danger),
                              ),
                            )
                          : _results.isEmpty
                              ? const EmptyState(
                                  title: 'Никого не найдено',
                                  subtitle:
                                      'Введите username пользователя полностью или частично.',
                                )
                              : ListView.separated(
                                  padding:
                                      const EdgeInsets.fromLTRB(18, 0, 18, 8),
                                  itemCount: _results.length,
                                  separatorBuilder: (_, __) => const SizedBox(
                                    height: 6,
                                  ),
                                  itemBuilder: (context, index) {
                                    final user = _results[index];
                                    final selected =
                                        _selectedIds.contains(user.id);
                                    return _GlassSurface(
                                      radius: 20,
                                      padding: EdgeInsets.zero,
                                      color: const Color(0x7024272D),
                                      child: CheckboxListTile(
                                        value: selected,
                                        onChanged: (_) {
                                          setState(() {
                                            selected
                                                ? _selectedIds.remove(user.id)
                                                : _selectedIds.add(user.id);
                                          });
                                        },
                                        secondary: BrenksAvatar(
                                          title: user.title,
                                          imageUrl: user.avatarUrl,
                                          baseUrl: widget.serverUrl,
                                          size: 38,
                                        ),
                                        title: Text(
                                          user.title,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        subtitle: Text('@${user.username}'),
                                      ),
                                    );
                                  },
                                ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text('Отмена'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _selectedIds.isEmpty
                              ? null
                              : () => Navigator.pop(
                                    context,
                                    _selectedIds.toList(growable: false),
                                  ),
                          child: Text('Добавить ${_selectedIds.length}'),
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
    );
  }
}

class _PickChannelAdminsDialog extends StatefulWidget {
  const _PickChannelAdminsDialog({
    required this.chat,
    required this.serverUrl,
  });

  final Chat chat;
  final String serverUrl;

  @override
  State<_PickChannelAdminsDialog> createState() =>
      _PickChannelAdminsDialogState();
}

class _PickChannelAdminsDialogState extends State<_PickChannelAdminsDialog> {
  late final Set<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = {...widget.chat.channelAdminIds};
  }

  @override
  Widget build(BuildContext context) {
    final candidates = widget.chat.participants
        .where((user) => user.id != widget.chat.channelOwnerId)
        .toList(growable: false);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            width: 500,
            constraints: const BoxConstraints(maxHeight: 620),
            padding: const EdgeInsets.all(20),
            decoration: _glassDecoration(
              color: panel.withValues(alpha: 0.9),
              radius: 32,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Админы канала',
                        style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Закрыть',
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: candidates.isEmpty
                      ? const EmptyState(
                          title: 'Некого назначить',
                          subtitle: 'Сначала добавьте подписчиков в канал.',
                        )
                      : ListView.separated(
                          itemCount: candidates.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 6),
                          itemBuilder: (context, index) {
                            final user = candidates[index];
                            final selected = _selectedIds.contains(user.id);
                            return _GlassSurface(
                              radius: 20,
                              padding: EdgeInsets.zero,
                              color: const Color(0x7024272D),
                              child: CheckboxListTile(
                                value: selected,
                                onChanged: (_) {
                                  setState(() {
                                    selected
                                        ? _selectedIds.remove(user.id)
                                        : _selectedIds.add(user.id);
                                  });
                                },
                                secondary: BrenksAvatar(
                                  title: user.title,
                                  imageUrl: user.avatarUrl,
                                  baseUrl: widget.serverUrl,
                                  size: 38,
                                ),
                                title: Text(
                                  user.title,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                subtitle: Text('@${user.username}'),
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(
                    context,
                    _selectedIds.toList(growable: false),
                  ),
                  icon: Icon(Icons.check_rounded),
                  label: Text('Сохранить'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ForwardMessageDialog extends StatefulWidget {
  const _ForwardMessageDialog({
    required this.chats,
    required this.currentUserId,
    required this.serverUrl,
  });

  final List<Chat> chats;
  final String currentUserId;
  final String serverUrl;

  @override
  State<_ForwardMessageDialog> createState() => _ForwardMessageDialogState();
}

class _ForwardMessageDialogState extends State<_ForwardMessageDialog> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController()..addListener(_handleSearch);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_handleSearch)
      ..dispose();
    super.dispose();
  }

  void _handleSearch() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final chats = widget.chats.where((chat) {
      if (query.isEmpty) return true;
      return chat.titleFor(widget.currentUserId).toLowerCase().contains(query);
    }).toList(growable: false);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            width: 430,
            constraints: const BoxConstraints(maxHeight: 660),
            decoration: BoxDecoration(
              color: panel.withValues(alpha: 0.86),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: Colors.white.withValues(alpha: 0.11)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.42),
                  blurRadius: 46,
                  offset: const Offset(0, 24),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 20, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Переслать',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Выберите чат, куда отправить сообщение',
                              style: TextStyle(color: muted, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                      IconButton.filled(
                        tooltip: 'Закрыть',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          foregroundColor: muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Поиск чата',
                      prefixIcon: Icon(Icons.search_rounded, color: muted),
                    ),
                  ),
                ),
                Flexible(
                  child: chats.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(22, 18, 22, 34),
                          child: EmptyState(
                            title: 'Ничего не найдено',
                            subtitle: query.isEmpty
                                ? 'Нет чатов, куда можно переслать сообщение.'
                                : 'Попробуйте ввести другое название.',
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                          shrinkWrap: true,
                          itemCount: chats.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 7),
                          itemBuilder: (context, index) {
                            final chat = chats[index];
                            return _ForwardChatTile(
                              chat: chat,
                              currentUserId: widget.currentUserId,
                              serverUrl: widget.serverUrl,
                              onTap: () => Navigator.pop(context, chat),
                            );
                          },
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

class _ForwardChatTile extends StatelessWidget {
  const _ForwardChatTile({
    required this.chat,
    required this.currentUserId,
    required this.serverUrl,
    required this.onTap,
  });

  final Chat chat;
  final String currentUserId;
  final String serverUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _GlassSurface(
      radius: 22,
      padding: EdgeInsets.zero,
      color: Colors.white.withValues(alpha: 0.035),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        splashColor: accent.withValues(alpha: 0.07),
        highlightColor: Colors.white.withValues(alpha: 0.025),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              BrenksAvatar(
                title: chat.titleFor(currentUserId),
                imageUrl: chat.avatarFor(currentUserId),
                baseUrl: serverUrl,
                size: 46,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            chat.titleFor(currentUserId),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        if (chat.verified) ...[
                          const SizedBox(width: 6),
                          const _VerifiedBadge(size: 15),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _lastMessageLabel(chat.lastMessage?.text),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(Icons.arrow_forward_ios_rounded, color: muted, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountDialog extends StatefulWidget {
  const _AccountDialog({
    required this.user,
    required this.api,
    required this.serverUrl,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.accentPreset,
    required this.onAccentPresetChanged,
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
  final BrenksAccentPreset accentPreset;
  final ValueChanged<BrenksAccentPreset> onAccentPresetChanged;
  final double uiScale;
  final ValueChanged<double> onUiScaleChanged;
  final ValueChanged<User> onProfileUpdated;
  final VoidCallback onLogout;

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  late final TextEditingController _displayNameController;
  late final TextEditingController _bioController;
  late final TextEditingController _phoneController;
  late BrenksAccentPreset _accentPreset;
  late bool _showOnline;
  late bool _allowMessages;
  late bool _allowCalls;
  late bool _showEmail;
  List<AuthSessionInfo> _sessions = const [];
  String? _avatarDraft;
  bool _saving = false;
  bool _sessionsLoading = false;
  String? _sessionsBusyId;

  @override
  void initState() {
    super.initState();
    _accentPreset = widget.accentPreset;
    _displayNameController = TextEditingController(
      text: widget.user.displayName ?? widget.user.username,
    );
    _bioController = TextEditingController(text: widget.user.bio ?? '');
    _phoneController = TextEditingController(text: widget.user.phone ?? '');
    _showOnline = widget.user.privacy.showOnline;
    _allowMessages = widget.user.privacy.allowMessages;
    _allowCalls = widget.user.privacy.allowCalls;
    _showEmail = widget.user.privacy.showEmail;
    unawaited(_loadSessions());
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  String get _profileUrl {
    final api = Uri.tryParse(widget.serverUrl);
    final host = api?.host ?? 'brenkschat.ru';
    final siteHost = host.startsWith('api.') ? host.substring(4) : host;
    final origin = Uri(
      scheme: api?.scheme == 'http' ? 'http' : 'https',
      host: siteHost,
    ).toString().replaceFirst(RegExp(r'/$'), '');
    return '$origin/u/${Uri.encodeComponent(widget.user.username)}';
  }

  Future<void> _loadSessions() async {
    setState(() => _sessionsLoading = true);
    try {
      final sessions = await widget.api.fetchSessions();
      if (mounted) setState(() => _sessions = sessions);
    } on Object catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось загрузить сессии: $err')),
      );
    } finally {
      if (mounted) setState(() => _sessionsLoading = false);
    }
  }

  Future<void> _copyProfileLink() async {
    await Clipboard.setData(ClipboardData(text: _profileUrl));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ссылка профиля скопирована')),
    );
  }

  Future<void> _resetPasswordFromSettings() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _PasswordResetSettingsDialog(
        api: widget.api,
        username: widget.user.username,
      ),
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Пароль обновлен')),
      );
    }
  }

  Future<void> _changeEmailFromSettings() async {
    final updated = await showDialog<User>(
      context: context,
      builder: (_) => _EmailChangeSettingsDialog(api: widget.api),
    );
    if (updated == null || !mounted) return;
    widget.onProfileUpdated(updated);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Почта обновлена')),
    );
  }

  Future<void> _openAdminPanel() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _AdminPanelDialog(api: widget.api),
    );
  }

  Future<void> _revokeSession(AuthSessionInfo session) async {
    if (session.current || _sessionsBusyId != null) return;
    setState(() => _sessionsBusyId = session.id);
    try {
      await widget.api.revokeSession(session.id);
      if (mounted) {
        setState(() {
          _sessions = _sessions
              .where((item) => item.id != session.id)
              .toList(growable: false);
        });
      }
    } on Object catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось завершить сессию: $err')),
      );
    } finally {
      if (mounted) setState(() => _sessionsBusyId = null);
    }
  }

  Future<void> _revokeOtherSessions() async {
    if (_sessionsBusyId != null) return;
    setState(() => _sessionsBusyId = 'all');
    try {
      await widget.api.revokeOtherSessions();
      if (mounted) {
        setState(() {
          _sessions =
              _sessions.where((item) => item.current).toList(growable: false);
        });
      }
    } on Object catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось завершить другие сессии: $err')),
      );
    } finally {
      if (mounted) setState(() => _sessionsBusyId = null);
    }
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
    await _previewAvatarBytes(bytes, mimeType);
  }

  Future<void> _pasteAvatar() async {
    final image = await Pasteboard.image;
    if (image == null || image.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('В буфере нет изображения')),
      );
      return;
    }
    final mimeType = lookupMimeType(
          'clipboard-image.png',
          headerBytes: image.take(16).toList(),
        ) ??
        'image/png';
    await _previewAvatarBytes(image, mimeType);
  }

  Future<void> _previewAvatarBytes(List<int> bytes, String mimeType) async {
    final dataUrl = 'data:$mimeType;base64,${base64Encode(bytes)}';
    final selected = await showDialog<String>(
      context: context,
      builder: (_) => _AvatarPreviewDialog(
        dataUrl: dataUrl,
        title: widget.user.title,
        serverUrl: widget.serverUrl,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => _avatarDraft = selected);
  }

  Future<void> _saveProfile() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final updated = await widget.api.updateProfile(
        displayName: _displayNameController.text.trim(),
        avatarUrl: _avatarDraft ?? widget.user.avatarUrl,
        bio: _bioController.text.trim(),
        phone: _phoneController.text.trim(),
        privacy: UserPrivacy(
          showOnline: _showOnline,
          allowMessages: _allowMessages,
          allowCalls: _allowCalls,
          showEmail: _showEmail,
        ),
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

  Future<void> _deleteAccount() async {
    if (_saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _DangerConfirmDialog(
        title: 'Удалить аккаунт?',
        text:
            'Профиль, личные чаты и ваши сессии будут удалены. Это действие нельзя отменить.',
        confirmLabel: 'Удалить аккаунт',
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await widget.api.deleteAccount();
      if (!mounted) return;
      Navigator.pop(context);
      widget.onLogout();
    } on Object catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось удалить аккаунт: $err')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _setAccentPreset(BrenksAccentPreset preset) {
    setState(() => _accentPreset = preset);
    widget.onAccentPresetChanged(preset);
  }

  Future<void> _setCustomAccent() async {
    final color = await showDialog<Color>(
      context: context,
      builder: (_) => const _CustomAccentDialog(),
    );
    if (color == null || !mounted) return;
    setBrenksCustomAccent(color);
    _setAccentPreset(BrenksAccentPreset.custom);
  }

  @override
  Widget build(BuildContext context) {
    final avatarPreview = _avatarDraft ?? widget.user.avatarUrl;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyV, meta: true):
            _pasteAvatar,
      },
      child: Dialog(
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
                                  icon: Icon(Icons.edit_rounded, size: 18),
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
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '@${widget.user.username}',
                                  style: TextStyle(color: muted),
                                ),
                                if (widget.user.email?.isNotEmpty == true)
                                  Text(
                                    widget.user.email!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: muted),
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
                          const _SettingsSectionTitle(
                            icon: Icons.person_rounded,
                            title: 'Профиль',
                          ),
                          const SizedBox(height: 10),
                          _ProfileShareCard(
                            profileUrl: _profileUrl,
                            username: widget.user.username,
                            title: widget.user.title,
                            avatarUrl: avatarPreview,
                            serverUrl: widget.serverUrl,
                            onCopy: _copyProfileLink,
                          ),
                          const SizedBox(height: 12),
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
                          _ProfileTextCard(
                            icon: Icons.notes_rounded,
                            title: 'Описание',
                            subtitle: 'Статус или короткая информация о себе',
                            controller: _bioController,
                            hintText: 'Например: работаю над БренксЧат',
                            maxLines: 3,
                          ),
                          const SizedBox(height: 12),
                          _ProfileTextCard(
                            icon: Icons.call_rounded,
                            title: 'Телефон',
                            subtitle: 'Будет виден только если вы решите',
                            controller: _phoneController,
                            hintText: '+7...',
                          ),
                          if (widget.user.isAdmin) ...[
                            const SizedBox(height: 18),
                            const _SettingsSectionTitle(
                              icon: Icons.admin_panel_settings_rounded,
                              title: 'Администрирование',
                            ),
                            const SizedBox(height: 10),
                            _SettingsCard(
                              icon: Icons.report_gmailerrorred_rounded,
                              title: 'Жалобы и пользователи',
                              subtitle:
                                  'Модерация жалоб, блокировки и обзор системы',
                              trailing: FilledButton.tonalIcon(
                                onPressed: _openAdminPanel,
                                icon: Icon(Icons.dashboard_customize_rounded),
                                label: Text('Открыть'),
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          const _SettingsSectionTitle(
                            icon: Icons.shield_rounded,
                            title: 'Безопасность',
                          ),
                          const SizedBox(height: 10),
                          _SettingsCard(
                            icon: Icons.lock_reset_rounded,
                            title: 'Пароль',
                            subtitle:
                                'Сменить пароль через код на привязанной почте',
                            trailing: FilledButton.tonalIcon(
                              onPressed: _resetPasswordFromSettings,
                              icon: Icon(Icons.password_rounded),
                              label: Text('Сбросить'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _SettingsCard(
                            icon: Icons.alternate_email_rounded,
                            title: 'Почта',
                            subtitle: widget.user.email?.isNotEmpty == true
                                ? widget.user.email!
                                : 'Почта не привязана',
                            trailing: FilledButton.tonalIcon(
                              onPressed: _changeEmailFromSettings,
                              icon: Icon(Icons.mark_email_read_rounded),
                              label: Text('Изменить'),
                            ),
                          ),
                          const SizedBox(height: 18),
                          const _SettingsSectionTitle(
                            icon: Icons.visibility_rounded,
                            title: 'Приватность',
                          ),
                          const SizedBox(height: 10),
                          _PrivacySettingsCard(
                            showOnline: _showOnline,
                            allowMessages: _allowMessages,
                            allowCalls: _allowCalls,
                            showEmail: _showEmail,
                            onShowOnlineChanged: (value) =>
                                setState(() => _showOnline = value),
                            onAllowMessagesChanged: (value) =>
                                setState(() => _allowMessages = value),
                            onAllowCallsChanged: (value) =>
                                setState(() => _allowCalls = value),
                            onShowEmailChanged: (value) =>
                                setState(() => _showEmail = value),
                          ),
                          const SizedBox(height: 18),
                          const _SettingsSectionTitle(
                            icon: Icons.palette_rounded,
                            title: 'Внешний вид',
                          ),
                          const SizedBox(height: 10),
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
                          _SettingsCard(
                            icon: Icons.palette_rounded,
                            title: 'Акцент',
                            subtitle: 'Цвет стекла, галочек и активных кнопок',
                            trailing: _AccentPresetPicker(
                              selected: _accentPreset,
                              onChanged: _setAccentPreset,
                              onCustomColor: _setCustomAccent,
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
                                Icon(
                                  Icons.zoom_out_map_rounded,
                                  color: accent,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              'Масштаб',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            '${(widget.uiScale * 100).round()}%',
                                            style: TextStyle(
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
                                          inactiveTrackColor: Colors.white
                                              .withValues(alpha: 0.1),
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
                          const _SettingsSectionTitle(
                            icon: Icons.devices_rounded,
                            title: 'Устройства',
                          ),
                          const SizedBox(height: 10),
                          _SessionsCard(
                            sessions: _sessions,
                            loading: _sessionsLoading,
                            busyId: _sessionsBusyId,
                            onRefresh: _loadSessions,
                            onRevoke: _revokeSession,
                            onRevokeOthers: _revokeOtherSessions,
                          ),
                          const SizedBox(height: 18),
                          _SettingsCard(
                            icon: Icons.delete_forever_rounded,
                            title: 'Удалить аккаунт',
                            subtitle:
                                'Полное удаление профиля и завершение сессий',
                            trailing: FilledButton.tonal(
                              onPressed: _saving ? null : _deleteAccount,
                              style: FilledButton.styleFrom(
                                foregroundColor: danger,
                                backgroundColor: danger.withValues(alpha: 0.12),
                              ),
                              child: Text('Удалить'),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: Text('Закрыть'),
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
                                      : Icon(Icons.check_rounded),
                                  label: Text('Сохранить'),
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
                              icon: Icon(Icons.logout_rounded),
                              label: Text('Выйти'),
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
      ),
    );
  }
}

class _ReportUserDialog extends StatefulWidget {
  const _ReportUserDialog({
    required this.api,
    required this.target,
    required this.chatId,
  });

  final ApiClient api;
  final ChatParticipant target;
  final String chatId;

  @override
  State<_ReportUserDialog> createState() => _ReportUserDialogState();
}

class _ReportUserDialogState extends State<_ReportUserDialog> {
  final _commentController = TextEditingController();
  String _reason = 'Спам или реклама';
  bool _sending = false;

  static const _reasons = [
    'Спам или реклама',
    'Оскорбления',
    'Мошенничество',
    'Запрещенный контент',
    'Другая причина',
  ];

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      await widget.api.createUserReport(
        targetUserId: widget.target.id,
        chatId: widget.chatId,
        reason: _reason,
        comment: _commentController.text,
      );
      if (mounted) Navigator.pop(context, true);
    } on Object catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось отправить жалобу: $err')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            width: 460,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: panel.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.42),
                  blurRadius: 40,
                  offset: const Offset(0, 22),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.report_gmailerrorred_rounded, color: danger),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Жалоба на ${widget.target.title}',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Причина', style: TextStyle(color: muted)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final reason in _reasons)
                      ChoiceChip(
                        label: Text(reason),
                        selected: _reason == reason,
                        onSelected: (_) => setState(() => _reason = reason),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _commentController,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    hintText: 'Комментарий для администрации',
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            _sending ? null : () => Navigator.pop(context),
                        child: Text('Отмена'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _sending ? null : _submit,
                        icon: _sending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(Icons.send_rounded),
                        label: Text('Отправить'),
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
}

class _AdminPanelDialog extends StatefulWidget {
  const _AdminPanelDialog({required this.api});

  final ApiClient api;

  @override
  State<_AdminPanelDialog> createState() => _AdminPanelDialogState();
}

class _AdminPanelDialogState extends State<_AdminPanelDialog> {
  AdminOverview? _overview;
  List<UserReport> _reports = const [];
  String _status = 'all';
  bool _loading = true;
  String? _busyUserId;
  String? _busyReportId;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        widget.api.fetchAdminOverview(),
        widget.api.fetchAdminReports(status: _status),
      ]);
      if (!mounted) return;
      setState(() {
        _overview = results[0] as AdminOverview;
        _reports = results[1] as List<UserReport>;
      });
    } on Object catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось загрузить админку: $err')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setReportStatus(UserReport report, String status) async {
    setState(() => _busyReportId = report.id);
    try {
      final updated = await widget.api.setAdminReportStatus(
        reportId: report.id,
        status: status,
      );
      if (!mounted) return;
      setState(() {
        _reports = _reports
            .map((item) => item.id == updated.id ? updated : item)
            .where((item) => _status == 'all' || item.status == _status)
            .toList(growable: false);
      });
      unawaited(_load());
    } on Object catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось обновить жалобу: $err')),
      );
    } finally {
      if (mounted) setState(() => _busyReportId = null);
    }
  }

  Future<void> _toggleUser(AdminUserRow user) async {
    if (user.isAdmin || _busyUserId != null) return;
    setState(() => _busyUserId = user.id);
    try {
      await widget.api.setAdminUserBlocked(
        userId: user.id,
        banned: !user.banned,
      );
      await _load();
    } on Object catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось изменить пользователя: $err')),
      );
    } finally {
      if (mounted) setState(() => _busyUserId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final overview = _overview;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(34),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            width: 920,
            constraints: const BoxConstraints(maxHeight: 760),
            decoration: BoxDecoration(
              color: panel.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(34),
              border: Border.all(color: border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 46,
                  offset: const Offset(0, 24),
                ),
              ],
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 18, 14, 16),
                  child: Row(
                    children: [
                      Icon(Icons.admin_panel_settings_rounded, color: accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Админ-панель',
                              style: TextStyle(
                                fontSize: 23,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              'Жалобы, пользователи и состояние системы',
                              style: TextStyle(color: muted),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Обновить',
                        onPressed: _loading ? null : _load,
                        icon: Icon(Icons.refresh_rounded),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                if (overview != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _AdminStat('Пользователи', overview.userCount),
                        _AdminStat('Жалобы', overview.openReportCount),
                        _AdminStat('Заблокировано', overview.blockedUserCount),
                        _AdminStat('Чаты', overview.chatCount),
                        _AdminStat('Сообщения', overview.messageCount),
                      ],
                    ),
                  ),
                const SizedBox(height: 14),
                Expanded(
                  child: _loading && overview == null
                      ? Center(child: CircularProgressIndicator())
                      : Row(
                          children: [
                            Expanded(
                              flex: 6,
                              child: _AdminReportsPanel(
                                reports: _reports,
                                status: _status,
                                busyReportId: _busyReportId,
                                onStatusFilterChanged: (value) {
                                  setState(() => _status = value);
                                  unawaited(_load());
                                },
                                onSetStatus: _setReportStatus,
                              ),
                            ),
                            Container(width: 1, color: border),
                            Expanded(
                              flex: 5,
                              child: _AdminUsersPanel(
                                users: overview?.users ?? const [],
                                busyUserId: _busyUserId,
                                onToggleUser: _toggleUser,
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
    );
  }
}

class _AdminStat extends StatelessWidget {
  const _AdminStat(this.label, this.value);

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 156,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: panelSoft.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: muted, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            value.toString(),
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _AdminReportsPanel extends StatelessWidget {
  const _AdminReportsPanel({
    required this.reports,
    required this.status,
    required this.busyReportId,
    required this.onStatusFilterChanged,
    required this.onSetStatus,
  });

  final List<UserReport> reports;
  final String status;
  final String? busyReportId;
  final ValueChanged<String> onStatusFilterChanged;
  final Future<void> Function(UserReport report, String status) onSetStatus;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Жалобы',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
              DropdownButton<String>(
                value: status,
                dropdownColor: panel,
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('Все')),
                  DropdownMenuItem(value: 'open', child: Text('Открытые')),
                  DropdownMenuItem(value: 'reviewing', child: Text('В работе')),
                  DropdownMenuItem(value: 'closed', child: Text('Закрытые')),
                ],
                onChanged: (value) {
                  if (value != null) onStatusFilterChanged(value);
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: reports.isEmpty
                ? const EmptyState(
                    title: 'Жалоб нет',
                    subtitle:
                        'Когда пользователи отправят жалобы, они появятся здесь.',
                  )
                : ListView.separated(
                    itemCount: reports.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final report = reports[index];
                      final busy = busyReportId == report.id;
                      return _AdminReportTile(
                        report: report,
                        busy: busy,
                        onSetStatus: (status) => onSetStatus(report, status),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _AdminReportTile extends StatelessWidget {
  const _AdminReportTile({
    required this.report,
    required this.busy,
    required this.onSetStatus,
  });

  final UserReport report;
  final bool busy;
  final ValueChanged<String> onSetStatus;

  @override
  Widget build(BuildContext context) {
    final reporter = report.reporter?.title ?? report.reporterId;
    final target = report.target?.title ?? report.targetUserId;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: panelSoft.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: report.status == 'closed'
              ? border
              : danger.withValues(alpha: 0.28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$reporter → $target',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              _ReportStatusPill(status: report.status),
            ],
          ),
          const SizedBox(height: 6),
          Text(report.reason, style: TextStyle(color: text)),
          if (report.comment?.isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Text(report.comment!, style: TextStyle(color: muted)),
          ],
          const SizedBox(height: 8),
          Text(
            _formatDateTimeShort(report.createdAt),
            style: TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: busy ? null : () => onSetStatus('reviewing'),
                child: Text('В работу'),
              ),
              FilledButton.tonal(
                onPressed: busy ? null : () => onSetStatus('closed'),
                child: Text('Закрыть'),
              ),
              if (report.status == 'closed')
                TextButton(
                  onPressed: busy ? null : () => onSetStatus('open'),
                  child: Text('Открыть'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReportStatusPill extends StatelessWidget {
  const _ReportStatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      'reviewing' => 'В работе',
      'closed' => 'Закрыта',
      _ => 'Открыта',
    };
    final color = switch (status) {
      'reviewing' => accent,
      'closed' => muted,
      _ => danger,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _AdminUsersPanel extends StatelessWidget {
  const _AdminUsersPanel({
    required this.users,
    required this.busyUserId,
    required this.onToggleUser,
  });

  final List<AdminUserRow> users;
  final String? busyUserId;
  final ValueChanged<AdminUserRow> onToggleUser;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Пользователи',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.separated(
              itemCount: users.length,
              separatorBuilder: (_, __) => Divider(color: border, height: 1),
              itemBuilder: (context, index) {
                final user = users[index];
                final busy = busyUserId == user.id;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          user.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (user.isAdmin)
                        Icon(Icons.shield_rounded, color: accent, size: 17),
                    ],
                  ),
                  subtitle: Text(
                    '@${user.username} · ${user.chatCount} чатов · ${user.messageCount} сообщений',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: user.isAdmin
                      ? Text('Админ', style: TextStyle(color: muted))
                      : FilledButton.tonal(
                          onPressed: busy ? null : () => onToggleUser(user),
                          style: FilledButton.styleFrom(
                            foregroundColor: user.banned ? accent : danger,
                            backgroundColor: (user.banned ? accent : danger)
                                .withValues(alpha: 0.1),
                          ),
                          child: Text(user.banned ? 'Разблок.' : 'Блок'),
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileShareCard extends StatelessWidget {
  const _ProfileShareCard({
    required this.profileUrl,
    required this.username,
    required this.title,
    required this.avatarUrl,
    required this.serverUrl,
    required this.onCopy,
  });

  final String profileUrl;
  final String username;
  final String title;
  final String? avatarUrl;
  final String serverUrl;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            panelStrong.withValues(alpha: 0.76),
            panelSoft.withValues(alpha: 0.52),
            accent.withValues(alpha: 0.08),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: () => _openExpandedProfileQr(context),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 146,
              child: _ProfileQrCard(
                profileUrl: profileUrl,
                username: username,
                title: title,
                avatarUrl: avatarUrl,
                serverUrl: serverUrl,
                size: 146,
                qrSize: 116,
                avatarSize: 42,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Публичный профиль',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '/u/$username',
                    style:
                        TextStyle(color: accent, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    profileUrl,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: muted, fontSize: 12.5),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.tonalIcon(
                    onPressed: onCopy,
                    icon: Icon(Icons.link_rounded),
                    label: Text('Скопировать ссылку'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openExpandedProfileQr(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (context) {
        return Dialog.fullscreen(
          backgroundColor: Colors.transparent,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.pop(context),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: Center(
                child: GestureDetector(
                  onTap: () {},
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.88, end: 1),
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutBack,
                    builder: (context, scale, child) {
                      return Transform.scale(scale: scale, child: child);
                    },
                    child: _ProfileQrCard(
                      profileUrl: profileUrl,
                      username: username,
                      title: title,
                      avatarUrl: avatarUrl,
                      serverUrl: serverUrl,
                      size: 370,
                      qrSize: 282,
                      avatarSize: 62,
                      expanded: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProfileQrCard extends StatelessWidget {
  const _ProfileQrCard({
    required this.profileUrl,
    required this.username,
    required this.title,
    required this.avatarUrl,
    required this.serverUrl,
    required this.size,
    required this.qrSize,
    required this.avatarSize,
    this.expanded = false,
  });

  final String profileUrl;
  final String username;
  final String title;
  final String? avatarUrl;
  final String serverUrl;
  final double size;
  final double qrSize;
  final double avatarSize;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final cardBg = Color.alphaBlend(
      accent.withValues(alpha: 0.035),
      panel,
    );
    final qrColor = HSLColor.fromColor(accent)
        .withLightness(
          Theme.of(context).brightness == Brightness.light ? 0.42 : 0.74,
        )
        .withSaturation(0.68)
        .toColor();
    final innerSize = size - (expanded ? 56 : 28);
    return Container(
      width: size,
      padding: EdgeInsets.fromLTRB(
        expanded ? 28 : 14,
        expanded ? 26 : 14,
        expanded ? 28 : 14,
        expanded ? 22 : 12,
      ),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(expanded ? 34 : 26),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.16),
            blurRadius: expanded ? 34 : 20,
            offset: Offset(0, expanded ? 18 : 10),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: expanded ? 34 : 18,
            offset: Offset(0, expanded ? 18 : 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: innerSize,
            height: innerSize,
            child: Stack(
              alignment: Alignment.center,
              children: [
                QrImageView(
                  data: profileUrl,
                  version: QrVersions.auto,
                  errorCorrectionLevel: QrErrorCorrectLevel.H,
                  gapless: true,
                  backgroundColor: Colors.transparent,
                  eyeStyle: QrEyeStyle(
                    eyeShape: QrEyeShape.circle,
                    color: qrColor,
                  ),
                  dataModuleStyle: QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.circle,
                    color: qrColor,
                  ),
                  padding: EdgeInsets.zero,
                  size: qrSize,
                ),
                Container(
                  padding: EdgeInsets.all(expanded ? 5 : 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cardBg,
                    border: Border.all(
                      color: accent.withValues(alpha: 0.28),
                      width: expanded ? 2 : 1.4,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                  child: BrenksAvatar(
                    title: title,
                    imageUrl: avatarUrl,
                    baseUrl: serverUrl,
                    size: avatarSize,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: expanded ? 14 : 7),
          Text(
            '@${username.toUpperCase()}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: accentSecondary,
              fontWeight: FontWeight.w900,
              fontSize: expanded ? 22 : 12,
              letterSpacing: 0,
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: 5),
            Text(
              'Отсканируйте, чтобы открыть профиль',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfileTextCard extends StatelessWidget {
  const _ProfileTextCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.controller,
    required this.hintText,
    this.maxLines = 1,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final TextEditingController controller;
  final String hintText;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: panelSoft.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontWeight: FontWeight.w800)),
                    Text(
                      subtitle,
                      style: TextStyle(color: muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            maxLines: maxLines,
            maxLength: maxLines > 1 ? 500 : null,
            decoration: InputDecoration(hintText: hintText),
          ),
        ],
      ),
    );
  }
}

class _PrivacySettingsCard extends StatelessWidget {
  const _PrivacySettingsCard({
    required this.showOnline,
    required this.allowMessages,
    required this.allowCalls,
    required this.showEmail,
    required this.onShowOnlineChanged,
    required this.onAllowMessagesChanged,
    required this.onAllowCallsChanged,
    required this.onShowEmailChanged,
  });

  final bool showOnline;
  final bool allowMessages;
  final bool allowCalls;
  final bool showEmail;
  final ValueChanged<bool> onShowOnlineChanged;
  final ValueChanged<bool> onAllowMessagesChanged;
  final ValueChanged<bool> onAllowCallsChanged;
  final ValueChanged<bool> onShowEmailChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: panelSoft.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.lock_rounded, color: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Приватность',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      'Кто видит активность и может связаться с вами',
                      style: TextStyle(color: muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _ProfileSwitchRow(
            title: 'Показывать онлайн',
            subtitle: 'Если выключить, статус и “печатает” скрываются',
            value: showOnline,
            onChanged: onShowOnlineChanged,
          ),
          _ProfileSwitchRow(
            title: 'Разрешить личные сообщения',
            subtitle: 'Новые сообщения в личных чатах будут ограничены',
            value: allowMessages,
            onChanged: onAllowMessagesChanged,
          ),
          _ProfileSwitchRow(
            title: 'Разрешить звонки',
            subtitle: 'Пользователи не смогут начать аудио/видеозвонок',
            value: allowCalls,
            onChanged: onAllowCallsChanged,
          ),
          _ProfileSwitchRow(
            title: 'Показывать почту',
            subtitle: 'Email будет виден в профиле собеседникам',
            value: showEmail,
            onChanged: onShowEmailChanged,
          ),
        ],
      ),
    );
  }
}

class _ProfileSwitchRow extends StatelessWidget {
  const _ProfileSwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
      activeThumbColor: accent,
      activeTrackColor: accent.withValues(alpha: 0.28),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(subtitle, style: TextStyle(color: muted, fontSize: 12.5)),
    );
  }
}

class _SessionsCard extends StatelessWidget {
  const _SessionsCard({
    required this.sessions,
    required this.loading,
    required this.busyId,
    required this.onRefresh,
    required this.onRevoke,
    required this.onRevokeOthers,
  });

  final List<AuthSessionInfo> sessions;
  final bool loading;
  final String? busyId;
  final VoidCallback onRefresh;
  final ValueChanged<AuthSessionInfo> onRevoke;
  final VoidCallback onRevokeOthers;

  @override
  Widget build(BuildContext context) {
    final otherSessions = sessions.where((item) => !item.current).length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: panelSoft.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.devices_rounded, color: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Устройства и сессии',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      'Здесь можно завершить вход на других устройствах',
                      style: TextStyle(color: muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Обновить',
                onPressed: loading ? null : onRefresh,
                icon: loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (sessions.isEmpty && !loading)
            Text('Активных сессий не найдено.', style: TextStyle(color: muted))
          else
            for (final session in sessions) ...[
              _SessionTile(
                session: session,
                busy: busyId == session.id,
                onRevoke: () => onRevoke(session),
              ),
              const SizedBox(height: 8),
            ],
          if (otherSessions > 0)
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: busyId == null ? onRevokeOthers : null,
                icon: busyId == 'all'
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.logout_rounded),
                label: Text('Завершить другие сессии'),
              ),
            ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.busy,
    required this.onRevoke,
  });

  final AuthSessionInfo session;
  final bool busy;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.065)),
      ),
      child: Row(
        children: [
          Icon(
            session.current
                ? Icons.computer_rounded
                : Icons.devices_other_rounded,
            color: session.current ? accent : muted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.current ? 'Это устройство' : 'Другое устройство',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_formatDateTimeShort(session.createdAt)}'
                  ' · до ${_formatDateTimeShort(session.expiresAt)}'
                  '${session.remembered ? ' · запомнено' : ''}',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ),
          ),
          if (!session.current)
            TextButton(
              onPressed: busy ? null : onRevoke,
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text('Завершить'),
            ),
        ],
      ),
    );
  }
}

class _DangerConfirmDialog extends StatelessWidget {
  const _DangerConfirmDialog({
    required this.title,
    required this.text,
    required this.confirmLabel,
  });

  final String title;
  final String text;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            width: 420,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: panel.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: danger.withValues(alpha: 0.24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.42),
                  blurRadius: 38,
                  offset: const Offset(0, 22),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: danger.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: danger.withValues(alpha: 0.22)),
                  ),
                  child: Icon(
                    Icons.delete_forever_rounded,
                    color: danger,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(text, style: TextStyle(color: muted, height: 1.35)),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text('Отмена'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: danger.withValues(alpha: 0.18),
                          foregroundColor: danger,
                        ),
                        child: Text(confirmLabel),
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
}

class _PasswordResetSettingsDialog extends StatefulWidget {
  const _PasswordResetSettingsDialog({
    required this.api,
    required this.username,
  });

  final ApiClient api;
  final String username;

  @override
  State<_PasswordResetSettingsDialog> createState() =>
      _PasswordResetSettingsDialogState();
}

class _PasswordResetSettingsDialogState
    extends State<_PasswordResetSettingsDialog> {
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _ticket;
  String? _emailMasked;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_requestCode());
  }

  @override
  void dispose() {
    _codeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.api.requestPasswordReset(
        login: widget.username,
      );
      if (!mounted) return;
      setState(() {
        _ticket = result.ticket;
        _emailMasked = result.emailMasked;
      });
    } on Object catch (err) {
      if (mounted) setState(() => _error = 'Не удалось отправить код: $err');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirm() async {
    final ticket = _ticket;
    final code = _codeController.text.trim();
    final password = _passwordController.text;
    if (ticket == null || code.isEmpty || password.length < 8) {
      setState(() => _error = 'Введите код и новый пароль от 8 символов.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.api.confirmPasswordReset(
        ticket: ticket,
        code: code,
        password: password,
      );
      if (mounted) Navigator.pop(context, true);
    } on Object catch (err) {
      if (mounted) setState(() => _error = 'Не удалось сменить пароль: $err');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SecurityActionDialogShell(
      icon: Icons.lock_reset_rounded,
      title: 'Сброс пароля',
      subtitle: _emailMasked == null
          ? 'Отправляем код подтверждения...'
          : 'Код отправлен на $_emailMasked',
      error: _error,
      loading: _loading,
      onCancel: () => Navigator.pop(context, false),
      onConfirm: _confirm,
      confirmLabel: 'Сменить пароль',
      children: [
        TextField(
          controller: _codeController,
          decoration: const InputDecoration(
            labelText: 'Код из письма',
            prefixIcon: Icon(Icons.mark_email_read_rounded),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _passwordController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Новый пароль',
            prefixIcon: Icon(Icons.password_rounded),
          ),
          onSubmitted: (_) => _confirm(),
        ),
      ],
    );
  }
}

class _EmailChangeSettingsDialog extends StatefulWidget {
  const _EmailChangeSettingsDialog({required this.api});

  final ApiClient api;

  @override
  State<_EmailChangeSettingsDialog> createState() =>
      _EmailChangeSettingsDialogState();
}

class _EmailChangeSettingsDialogState
    extends State<_EmailChangeSettingsDialog> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  String? _ticket;
  String? _emailMasked;
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    final email = _emailController.text.trim();
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _error = 'Введите корректную почту.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.api.requestEmailChange(email: email);
      if (!mounted) return;
      setState(() {
        _ticket = result.ticket;
        _emailMasked = result.emailMasked;
      });
    } on Object catch (err) {
      if (mounted) setState(() => _error = 'Не удалось отправить код: $err');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirm() async {
    final ticket = _ticket;
    final code = _codeController.text.trim();
    if (ticket == null) {
      await _requestCode();
      return;
    }
    if (code.isEmpty) {
      setState(() => _error = 'Введите код подтверждения.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = await widget.api.confirmEmailChange(
        ticket: ticket,
        code: code,
      );
      if (mounted) Navigator.pop(context, user);
    } on Object catch (err) {
      if (mounted) setState(() => _error = 'Не удалось сменить почту: $err');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SecurityActionDialogShell(
      icon: Icons.alternate_email_rounded,
      title: 'Смена почты',
      subtitle: _emailMasked == null
          ? 'Введите новую почту, затем подтвердите кодом.'
          : 'Код отправлен на $_emailMasked',
      error: _error,
      loading: _loading,
      onCancel: () => Navigator.pop(context),
      onConfirm: _confirm,
      confirmLabel: _ticket == null ? 'Отправить код' : 'Подтвердить',
      children: [
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          enabled: _ticket == null,
          decoration: const InputDecoration(
            labelText: 'Новая почта',
            prefixIcon: Icon(Icons.mail_rounded),
          ),
          onSubmitted: (_) => _requestCode(),
        ),
        if (_ticket != null) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _codeController,
            decoration: const InputDecoration(
              labelText: 'Код из письма',
              prefixIcon: Icon(Icons.mark_email_read_rounded),
            ),
            onSubmitted: (_) => _confirm(),
          ),
        ],
      ],
    );
  }
}

class _SecurityActionDialogShell extends StatelessWidget {
  const _SecurityActionDialogShell({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
    required this.onCancel,
    required this.onConfirm,
    required this.confirmLabel,
    required this.loading,
    this.error,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  final String confirmLabel;
  final bool loading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            width: 430,
            padding: const EdgeInsets.all(20),
            decoration: _glassDecoration(
              color: panel.withValues(alpha: 0.92),
              radius: 30,
              borderColor: accent.withValues(alpha: 0.16),
            ),
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
                        shape: BoxShape.circle,
                        color: accent.withValues(alpha: 0.13),
                        border:
                            Border.all(color: accent.withValues(alpha: 0.22)),
                      ),
                      child: Icon(icon, color: accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            subtitle,
                            style: TextStyle(color: muted, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ...children,
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!, style: TextStyle(color: danger, fontSize: 13)),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: loading ? null : onCancel,
                        child: Text('Отмена'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: loading ? null : onConfirm,
                        child: loading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(confirmLabel),
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
}

class _CustomAccentDialog extends StatefulWidget {
  const _CustomAccentDialog();

  @override
  State<_CustomAccentDialog> createState() => _CustomAccentDialogState();
}

class _CustomAccentDialogState extends State<_CustomAccentDialog> {
  late HSVColor _selected;
  static const _quickColors = [
    Color(0xFFD8B76C),
    Color(0xFFE2687C),
    Color(0xFF8BE9FD),
    Color(0xFF8C7BFF),
    Color(0xFF5EEAD4),
    Color(0xFFFF9F6E),
    Color(0xFFF472B6),
    Color(0xFFA7F3D0),
  ];

  @override
  void initState() {
    super.initState();
    final current = HSVColor.fromColor(accent);
    _selected = HSVColor.fromAHSV(
      1,
      current.hue,
      current.saturation.clamp(0.24, 1),
      current.value.clamp(0.42, 1),
    );
  }

  Color get _color => _selected.toColor();

  void _pickFromPlane(Offset position, Size size) {
    final saturation = (position.dx / size.width).clamp(0.0, 1.0);
    final value = (1 - position.dy / size.height).clamp(0.0, 1.0);
    setState(() {
      _selected = _selected.withSaturation(saturation).withValue(value);
    });
  }

  void _pickQuickColor(Color color) {
    final hsv = HSVColor.fromColor(color);
    setState(() {
      _selected = HSVColor.fromAHSV(
        1,
        hsv.hue,
        hsv.saturation.clamp(0.32, 1),
        hsv.value.clamp(0.5, 1),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final selected = _color;
    final soft = HSLColor.fromColor(selected).withLightness(0.82).toColor();
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            width: 460,
            padding: const EdgeInsets.all(20),
            decoration: _glassDecoration(
              color: panel.withValues(alpha: 0.9),
              radius: 32,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [soft, selected],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: selected.withValues(alpha: 0.34),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Выбор акцента',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Выберите оттенок для стекла, кнопок, галочек и активных элементов.',
                  style: TextStyle(color: muted, height: 1.35),
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final size = Size(constraints.maxWidth, 176);
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanDown: (details) =>
                          _pickFromPlane(details.localPosition, size),
                      onPanUpdate: (details) =>
                          _pickFromPlane(details.localPosition, size),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: SizedBox(
                          height: size.height,
                          child: CustomPaint(
                            painter: _AccentColorPlanePainter(
                              hue: _selected.hue,
                              saturation: _selected.saturation,
                              value: _selected.value,
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Icon(Icons.color_lens_rounded, color: selected, size: 19),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: selected,
                          inactiveTrackColor:
                              Colors.white.withValues(alpha: 0.1),
                          thumbColor: selected,
                          overlayColor: selected.withValues(alpha: 0.14),
                        ),
                        child: Slider(
                          value: _selected.hue,
                          min: 0,
                          max: 360,
                          onChanged: (value) {
                            setState(
                                () => _selected = _selected.withHue(value));
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final color in _quickColors)
                      _AccentSwatchButton(
                        color: color,
                        selected: color.toARGB32() == selected.toARGB32(),
                        onTap: () => _pickQuickColor(color),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('Отмена'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, selected),
                        child: Text('Применить'),
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
}

class _AccentColorPlanePainter extends CustomPainter {
  const _AccentColorPlanePainter({
    required this.hue,
    required this.saturation,
    required this.value,
  });

  final double hue;
  final double saturation;
  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final hueColor = HSVColor.fromAHSV(1, hue, 1, 1).toColor();
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.white, hueColor],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.92)],
        ).createShader(rect),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(0.6), const Radius.circular(24)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: 0.18),
    );

    final marker = Offset(saturation * size.width, (1 - value) * size.height);
    canvas.drawCircle(
      marker,
      9,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );
    canvas.drawCircle(
      marker,
      9,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );
  }

  @override
  bool shouldRepaint(covariant _AccentColorPlanePainter oldDelegate) {
    return oldDelegate.hue != hue ||
        oldDelegate.saturation != saturation ||
        oldDelegate.value != value;
  }
}

class _AccentSwatchButton extends StatelessWidget {
  const _AccentSwatchButton({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final soft = HSLColor.fromColor(color).withLightness(0.82).toColor();
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [soft, color],
          ),
          border: Border.all(
            color: selected
                ? Colors.white.withValues(alpha: 0.9)
                : Colors.white.withValues(alpha: 0.12),
            width: selected ? 2 : 1,
          ),
          boxShadow: [
            if (selected)
              BoxShadow(
                color: color.withValues(alpha: 0.34),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
          ],
        ),
        child: selected
            ? Icon(Icons.check_rounded, color: Colors.white, size: 20)
            : null,
      ),
    );
  }
}

class _AccentPresetPicker extends StatelessWidget {
  const _AccentPresetPicker({
    required this.selected,
    required this.onChanged,
    required this.onCustomColor,
  });

  final BrenksAccentPreset selected;
  final ValueChanged<BrenksAccentPreset> onChanged;
  final VoidCallback onCustomColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 270,
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final preset in BrenksAccentPreset.values)
            _AccentPresetButton(
              preset: preset,
              selected: selected == preset,
              onTap: preset == BrenksAccentPreset.custom
                  ? onCustomColor
                  : () => onChanged(preset),
            ),
        ],
      ),
    );
  }
}

class _AccentPresetButton extends StatelessWidget {
  const _AccentPresetButton({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final BrenksAccentPreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final swatchAccent = preset == BrenksAccentPreset.custom && selected
        ? accent
        : preset.accent;
    final swatchSecondary = preset == BrenksAccentPreset.custom && selected
        ? accentSecondary
        : preset.secondary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? swatchAccent.withValues(alpha: 0.16)
                : Colors.white.withValues(alpha: 0.045),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? swatchAccent.withValues(alpha: 0.55)
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [swatchSecondary, swatchAccent],
                  ),
                  boxShadow: [
                    if (selected)
                      BoxShadow(
                        color: swatchAccent.withValues(alpha: 0.34),
                        blurRadius: 12,
                        offset: const Offset(0, 5),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 7),
              Text(
                preset.label,
                style: TextStyle(
                  color: selected ? text : muted,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsSectionTitle extends StatelessWidget {
  const _SettingsSectionTitle({
    required this.icon,
    required this.title,
  });

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: accent, size: 19),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: text,
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 1,
            color: border.withValues(alpha: 0.75),
          ),
        ),
      ],
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
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  subtitle,
                  style: TextStyle(color: muted, fontSize: 13),
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
    required this.onToggleBlockUser,
    required this.onReportUser,
    required this.onAddMembers,
    required this.onManageChannelAdmins,
    required this.onOpenDirectChat,
  });

  final String serverUrl;
  final Chat chat;
  final List<Message> messages;
  final String currentUserId;
  final Set<String> onlineUserIds;
  final Future<void> Function(String userId, bool blocked) onToggleBlockUser;
  final Future<void> Function(String userId) onReportUser;
  final VoidCallback? onAddMembers;
  final VoidCallback? onManageChannelAdmins;
  final ValueChanged<String> onOpenDirectChat;

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
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 180),
                        style: TextStyle(color: muted),
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
                        _PeerProfileActions(
                          peer: peer,
                          blocked: peer.blockedByViewer,
                          onCopyUsername: () {
                            Clipboard.setData(
                              ClipboardData(text: '@${peer.username}'),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Username скопирован')),
                            );
                          },
                          onToggleBlock: () async {
                            await onToggleBlockUser(
                              peer.id,
                              !peer.blockedByViewer,
                            );
                            if (context.mounted) Navigator.pop(context);
                          },
                          onReport: () async {
                            await onReportUser(peer.id);
                          },
                        ),
                        const SizedBox(height: 18),
                      ],
                      _ProfileMediaTabs(
                        photos: photos,
                        voices: voices,
                        files: files,
                        serverUrl: serverUrl,
                      ),
                      if (onAddMembers != null ||
                          onManageChannelAdmins != null) ...[
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            if (onAddMembers != null)
                              FilledButton.tonalIcon(
                                onPressed: onAddMembers,
                                icon: Icon(Icons.person_add_rounded),
                                label: Text(
                                  chat.type == ChatType.channel
                                      ? 'Добавить подписчиков'
                                      : 'Добавить участников',
                                ),
                              ),
                            if (onManageChannelAdmins != null)
                              FilledButton.tonalIcon(
                                onPressed: onManageChannelAdmins,
                                icon: Icon(Icons.admin_panel_settings_rounded),
                                label: Text('Админы канала'),
                              ),
                          ],
                        ),
                      ],
                      if (!isDirect) ...[
                        const SizedBox(height: 18),
                        Text(
                          'Участники',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        for (final participant in chat.participants)
                          ListTile(
                            onTap: () => onOpenDirectChat(participant.id),
                            leading: BrenksAvatar(
                              title: participant.title,
                              imageUrl: participant.avatarUrl,
                              baseUrl: serverUrl,
                            ),
                            title: Text(participant.title),
                            subtitle: Text(
                              _participantSubtitle(
                                chat: chat,
                                participant: participant,
                                online: onlineUserIds.contains(participant.id),
                              ),
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
                      child: Text('Закрыть'),
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

class _PeerProfileActions extends StatelessWidget {
  const _PeerProfileActions({
    required this.peer,
    required this.blocked,
    required this.onCopyUsername,
    required this.onToggleBlock,
    required this.onReport,
  });

  final ChatParticipant peer;
  final bool blocked;
  final VoidCallback onCopyUsername;
  final VoidCallback onToggleBlock;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    return _GlassSurface(
      padding: const EdgeInsets.all(14),
      radius: 24,
      color: const Color(0x7A202329),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            blocked
                ? 'Пользователь заблокирован: личные сообщения и звонки отключены.'
                : 'Публичная карточка @${peer.username}',
            style: TextStyle(color: muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.tonalIcon(
                onPressed: onCopyUsername,
                icon: Icon(Icons.alternate_email_rounded),
                label: Text('@${peer.username}'),
              ),
              FilledButton.tonalIcon(
                onPressed: onToggleBlock,
                style: FilledButton.styleFrom(
                  foregroundColor: blocked ? accent : danger,
                  backgroundColor:
                      (blocked ? accent : danger).withValues(alpha: 0.12),
                ),
                icon: Icon(
                  blocked ? Icons.lock_open_rounded : Icons.block_rounded,
                ),
                label: Text(blocked ? 'Разблокировать' : 'Заблокировать'),
              ),
              FilledButton.tonalIcon(
                onPressed: onReport,
                style: FilledButton.styleFrom(
                  foregroundColor: danger,
                  backgroundColor: danger.withValues(alpha: 0.1),
                ),
                icon: Icon(Icons.report_gmailerrorred_rounded),
                label: Text('Пожаловаться'),
              ),
            ],
          ),
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
    }
        .toList(growable: false)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

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
                ? Padding(
                    key: const ValueKey('empty'),
                    padding: const EdgeInsets.symmetric(vertical: 26),
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
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  _formatTime(message.createdAt),
                  style: TextStyle(color: muted, fontSize: 12),
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

String _participantSubtitle({
  required Chat chat,
  required ChatParticipant participant,
  required bool online,
}) {
  final role = chat.channelOwnerId == participant.id
      ? 'владелец'
      : chat.channelAdminIds.contains(participant.id)
          ? 'админ'
          : null;
  final status = online ? 'онлайн' : '@${participant.username}';
  return role == null ? status : '$role • $status';
}

String _typingActivityLabel({
  required String username,
  required String activity,
  required bool direct,
}) {
  final action = switch (activity) {
    'voice' => 'записывает голосовое',
    'video_note' => 'записывает видеокружок',
    _ => 'печатает',
  };
  return direct ? action : '$username $action';
}

String _mediaPlaybackKey(MessageMedia media) {
  return '${media.kind}:${media.dataUrl.hashCode}:${media.durationMs ?? 0}';
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

String _formatDateTimeShort(int timestamp) {
  if (timestamp <= 0) return 'неизвестно';
  final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$day.$month $hour:$minute';
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

Future<VideoPlayerController> _createVideoController(
  String source,
  String serverUrl, {
  required String mimeType,
}) async {
  final bytes = _bytesFromDataUrl(source);
  if (bytes != null) {
    final file = await _writeMediaCacheFile(
      bytes: bytes,
      source: source,
      mimeType: mimeType,
    );
    return VideoPlayerController.file(file);
  }
  final url = _resolveMediaUrl(source, serverUrl);
  if (url == null || url.isEmpty) {
    throw StateError('Видео не найдено');
  }
  return VideoPlayerController.networkUrl(Uri.parse(url));
}

Future<io.File> _writeMediaCacheFile({
  required Uint8List bytes,
  required String source,
  required String mimeType,
}) async {
  final dir = await getApplicationCacheDirectory();
  final mediaDir = io.Directory('${dir.path}/brenkschat-media');
  await mediaDir.create(recursive: true);
  final ext = mimeType.contains('webm')
      ? '.webm'
      : mimeType.contains('quicktime')
          ? '.mov'
          : '.mp4';
  final file = io.File('${mediaDir.path}/${_stableHash(source)}$ext');
  if (!await file.exists() || await file.length() != bytes.length) {
    await file.writeAsBytes(bytes, flush: false);
  }
  return file;
}

String _stableHash(String value) {
  const offset = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  var hash = offset;
  for (final byte in utf8.encode(value)) {
    hash ^= byte;
    hash = (hash * prime) & 0xffffffffffffffff;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

void _openVideoNoteViewer(
  BuildContext context,
  MessageMedia media,
  String serverUrl,
) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (context) {
      return Dialog.fullscreen(
        backgroundColor: Colors.transparent,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.pop(context),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Center(
              child: GestureDetector(
                onTap: () {},
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final available = math.min(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    );
                    final size = (available - 88).clamp(340.0, 560.0);
                    return TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.72, end: 1),
                      duration: const Duration(milliseconds: 360),
                      curve: Curves.easeOutBack,
                      builder: (context, scale, child) {
                        return Transform.scale(scale: scale, child: child);
                      },
                      child: _VideoNoteCircle(
                        media: media,
                        serverUrl: serverUrl,
                        size: size,
                        autoplay: true,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

void _openImageViewer(BuildContext context, Uint8List bytes) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.78),
    builder: (context) {
      return Dialog.fullscreen(
        backgroundColor: Colors.transparent,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.pop(context),
          child: Stack(
            children: [
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Center(
                      child: GestureDetector(
                        onTap: () {},
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: constraints.maxWidth - 96,
                            maxHeight: constraints.maxHeight - 96,
                          ),
                          child: Image.memory(
                            bytes,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                right: 24,
                top: 24,
                child: IconButton.filledTonal(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close_rounded),
                ),
              ),
            ],
          ),
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
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.pop(context),
          child: Stack(
            children: [
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Center(
                      child: GestureDetector(
                        onTap: () {},
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: constraints.maxWidth - 96,
                            maxHeight: constraints.maxHeight - 96,
                          ),
                          child: BrenksCachedNetworkImage(
                            url: url,
                            fit: BoxFit.contain,
                            placeholder: const CircularProgressIndicator(),
                            errorWidget: Text('Фото не удалось загрузить'),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                right: 24,
                top: 24,
                child: IconButton.filledTonal(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close_rounded),
                ),
              ),
            ],
          ),
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
