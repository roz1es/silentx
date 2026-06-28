import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swipeable_page_route/swipeable_page_route.dart';

import '../format.dart';
import '../models.dart';
import '../services/audio_message_service.dart';
import '../services/messenger_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/attach_sheet.dart';
import '../widgets/brenks_avatar.dart';
import '../widgets/camera_capture_screen.dart';
import '../widgets/empty_state.dart';
import '../widgets/glass.dart';
import '../widgets/inline_video_recorder.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_composer.dart';
import 'chat_profile_screen.dart';

const _maxMediaDataUrlLength = 14 * 1000 * 1000;

/// Экран переписки одного чата.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.controller,
    required this.chatId,
  });

  final MessengerController controller;
  final String chatId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _audioService = AudioMessageService();

  // Для перехода к оригиналу по тапу на ответ: подсветка + ключ по объекту
  // сообщения (GlobalObjectKey не сталкивается даже при дублирующихся id).
  String? _highlightId;
  Timer? _highlightTimer;

  // Кнопка «вниз»: показывается, когда лента прокручена вверх от конца.
  bool _showScrollDown = false;

  Message? _replyTo;
  Message? _editing;
  bool _sendingMedia = false;
  bool _recordingVoice = false;
  final ValueNotifier<int> _recordingMs = ValueNotifier<int>(0);
  Timer? _recordingTimer;
  int _lastTick = -1;
  int _bgIndex = 0;
  bool _recordingCircle = false;
  bool _msgSearch = false;
  final _msgSearchController = TextEditingController();

  MessengerController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
    _scrollController.addListener(_onScroll);
    // Открываем чат после первого кадра, чтобы синхронный notifyListeners
    // внутри openChat не вызвал setState во время инициализации.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_controller.openChat(widget.chatId));
    });
    _loadBg();
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.closeActiveChat();
    _recordingTimer?.cancel();
    _highlightTimer?.cancel();
    unawaited(_audioService.dispose());
    _messageController.dispose();
    _msgSearchController.dispose();
    _scrollController.dispose();
    _recordingMs.dispose();
    super.dispose();
  }

  Future<void> _loadBg() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getInt('chat_bg_${widget.chatId}') ?? 0;
    if (mounted) setState(() => _bgIndex = val);
  }

  Future<void> _saveBg(int idx) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('chat_bg_${widget.chatId}', idx);
    if (mounted) setState(() => _bgIndex = idx);
  }

  void _onControllerChanged() {
    if (!mounted) return;
    if (_controller.incomingMessageTick != _lastTick) {
      _lastTick = _controller.incomingMessageTick;
      _scrollToBottom();
    }
    setState(() {});
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final show = (pos.maxScrollExtent - pos.pixels) > 300;
    if (show != _showScrollDown) setState(() => _showScrollDown = show);
  }

  Widget _scrollDownButton() {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Material(
      color: isLight ? Colors.white : panelStrong,
      shape: const CircleBorder(),
      elevation: 4,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => _scrollToBottom(),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(Icons.keyboard_arrow_down_rounded,
              color: isLight ? lightText : text, size: 26),
        ),
      ),
    );
  }

  void _scrollToBottom({bool instant = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (instant) {
        _scrollController.jumpTo(target);
      } else {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
      // Повторно прижимаем к низу на следующем кадре: новый пузырёк/картинка
      // могли изменить высоту списка уже после расчёта maxScrollExtent —
      // именно из-за этого после отправки «перекидывало чуть выше».
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        final corrected = _scrollController.position.maxScrollExtent;
        if ((corrected - _scrollController.offset).abs() > 4) {
          _scrollController.jumpTo(corrected);
        }
      });
    });
  }

  void _send() {
    final text = _messageController.text.trim();
    final editing = _editing;
    if (editing != null) {
      if (text.isEmpty) return;
      _controller.editMessage(editing.id, text);
      setState(() => _editing = null);
      _messageController.clear();
      return;
    }
    if (text.isEmpty) return;
    _controller.sendMessage(text: text, replyToMessageId: _replyTo?.id);
    setState(() => _replyTo = null);
    _messageController.clear();
    _controller.notifyTyping(false);
    _scrollToBottom();
  }

  Future<void> _openAttachSheet() async {
    FocusScope.of(context).unfocus();
    final result = await showModalBottomSheet<AttachResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AttachSheet(),
    );
    if (!mounted || result == null) return;
    if (result.isFile) {
      await _attach();
    } else if (result.isCamera) {
      // Экран съёмки открываем уже ПОСЛЕ закрытия листа (его pop вернул
      // результат), иначе словим краш _dependents.isEmpty.
      final bytes = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const CameraCaptureScreen(),
        ),
      );
      if (!mounted || bytes == null) return;
      await _previewAndSendImage(bytes, 'camera.jpg');
    } else if (result.bytes != null) {
      await _previewAndSendImage(result.bytes!, result.name ?? 'photo.jpg');
    }
  }

  /// Предпросмотр изображения перед отправкой: подпись + «отправить как файл».
  Future<void> _previewAndSendImage(Uint8List bytes, String name) async {
    final captionController = TextEditingController();
    var asFile = false;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Dialog(
          backgroundColor: isLight ? Colors.white : panel,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Отправить изображение',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        color: isLight ? lightText : text),
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 300),
                      child: Image.memory(bytes, fit: BoxFit.contain),
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    activeColor: accent,
                    value: asFile,
                    onChanged: (v) => setLocal(() => asFile = v ?? false),
                    title: const Text('Отправить как файл'),
                  ),
                  TextField(
                    controller: captionController,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(hintText: 'Подпись'),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Отмена'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: FilledButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: const Color(0xFF08131A)),
                        child: const Text('Отправить'),
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
    if (confirmed == true) {
      await _sendMediaBytes(bytes, name,
          caption: captionController.text.trim(), asFile: asFile);
    }
    captionController.dispose();
  }

  Future<void> _sendMediaBytes(Uint8List bytes, String name,
      {String caption = '', bool asFile = false}) async {
    if (bytes.isEmpty) return;
    setState(() => _sendingMedia = true);
    try {
      final mimeType =
          lookupMimeType(name, headerBytes: bytes.take(16).toList()) ??
              'image/jpeg';
      final dataUrl = 'data:$mimeType;base64,${base64Encode(bytes)}';
      if (dataUrl.length > _maxMediaDataUrlLength) {
        _showSnack('Фото слишком большое для текущего сервера.');
        return;
      }
      final isImage = !asFile && mimeType.startsWith('image/');
      final media = MessageMedia(
        kind: isImage ? 'image' : 'file',
        dataUrl: dataUrl,
        fileName: name,
        mimeType: mimeType,
      );
      _controller.sendMessage(
        text: caption,
        media: media,
        replyToMessageId: _replyTo?.id,
      );
      setState(() => _replyTo = null);
      _scrollToBottom();
    } on Object catch (err) {
      _showSnack('Не удалось отправить фото: $err');
    } finally {
      if (mounted) setState(() => _sendingMedia = false);
    }
  }

  Future<void> _attach() async {
    setState(() => _sendingMedia = true);
    try {
      final result =
          await FilePicker.pickFiles(type: FileType.any, withData: true);
      final file = result?.files.single;
      if (file == null) return;
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
      _controller.sendMessage(
        text: _messageController.text.trim(),
        media: media,
        replyToMessageId: _replyTo?.id,
      );
      setState(() => _replyTo = null);
      _messageController.clear();
      _scrollToBottom();
    } on Object catch (err) {
      _showSnack('Не удалось отправить файл: $err');
    } finally {
      if (mounted) setState(() => _sendingMedia = false);
    }
  }

  Future<void> _startVoice() async {
    if (_recordingVoice) return;
    FocusScope.of(context).unfocus();
    try {
      await _audioService.startRecording();
      setState(() {
        _recordingVoice = true;
        _editing = null;
        _replyTo = null;
      });
      _recordingMs.value = 0;
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted) return;
        // Только обновляем таймер, без rebuild всего экрана (лента не прыгает).
        _recordingMs.value += 250;
      });
    } on Object catch (err) {
      _showSnack('Не удалось начать запись: $err');
    }
  }

  Future<void> _finishVoice() async {
    if (!_recordingVoice) return;
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
      _controller.sendMessage(media: recording.media);
      _scrollToBottom();
    } on Object catch (err) {
      _showSnack('Не удалось отправить голосовое: $err');
    }
  }

  Future<void> _cancelVoice() async {
    if (!_recordingVoice) return;
    _recordingTimer?.cancel();
    setState(() => _recordingVoice = false);
    _recordingMs.value = 0;
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
    if (message.deleted || message.senderId != _controller.currentUser.id) return;
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<bool> _confirm(String title, String body) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Да'),
          ),
        ],
      ),
    );
    return result == true;
  }

  String? _senderName(Chat chat, Message message) {
    if (chat.type == ChatType.direct) return null;
    for (final p in chat.participants) {
      if (p.id == message.senderId) return p.title;
    }
    return null;
  }

  String? _replyPreview(Message message) {
    final id = message.replyToMessageId;
    if (id == null) return null;
    for (final m in _controller.messages) {
      if (m.id == id) return messagePreview(m);
    }
    return 'Сообщение';
  }

  /// Тап по плашке-ответу: прокрутить ленту к оригинальному сообщению и кратко
  /// подсветить его. Если оригинал вне экрана — сначала грубо доскроллим по
  /// индексу, затем точно наводимся через ensureVisible.
  void _jumpToMessage(String? id) {
    if (id == null) return;
    final messages = _controller.messages;
    final idx = messages.indexWhere((m) => m.id == id);
    if (idx < 0) return; // оригинал не загружен (старее текущей страницы)
    final target = messages[idx];

    void highlight() {
      setState(() => _highlightId = id);
      _highlightTimer?.cancel();
      _highlightTimer = Timer(const Duration(milliseconds: 1600), () {
        if (mounted) setState(() => _highlightId = null);
      });
    }

    final ctx = GlobalObjectKey(target).currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        alignment: 0.3,
      );
      highlight();
      return;
    }
    // Оригинал не построен (вне области) — грубо доскроллим по доле индекса.
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    final offset =
        messages.length <= 1 ? 0.0 : (idx / (messages.length - 1)) * max;
    _scrollController
        .animateTo(
      offset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    )
        .then((_) {
      if (!mounted) return;
      final ctx2 = GlobalObjectKey(target).currentContext;
      if (ctx2 != null && ctx2.mounted) {
        Scrollable.ensureVisible(
          ctx2,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: 0.3,
        );
      }
      highlight();
    });
  }

  @override
  Widget build(BuildContext context) {
    final chat = _controller.chatById(widget.chatId);
    if (chat == null) {
      return const Scaffold(
        body: Center(child: Text('Чат недоступен')),
      );
    }
    final query = _msgSearchController.text.trim().toLowerCase();
    final messages = (_msgSearch && query.isNotEmpty)
        ? _controller.messages
            .where((m) => !m.deleted && m.text.toLowerCase().contains(query))
            .toList(growable: false)
        : _controller.messages;
    final pinned = _controller.pinnedMessage;

    return GlassBackground(
      child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: _appBar(chat),
      body: Column(
        children: [
          if (pinned != null) _pinnedBanner(pinned),
          if (_controller.messagesError != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: danger.withValues(alpha: 0.12),
              child: Text(_controller.messagesError!,
                  style: const TextStyle(color: danger)),
            ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: _bgIndex == 5
                      ? const SizedBox.shrink()
                      : _bgIndex == 0
                          ? const CustomPaint(painter: _PatternPainter())
                          : Container(decoration: BoxDecoration(gradient: _bgGradient(_bgIndex))),
                ),
                _controller.loadingMessages
                    ? const Center(child: CircularProgressIndicator())
                    : messages.isEmpty
                        ? const EmptyState(
                            title: 'Сообщений пока нет',
                            subtitle: 'Напишите первое сообщение.',
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(14, 16, 14, 92),
                            itemCount: messages.length,
                            itemBuilder: (context, index) {
                              final message = messages[index];
                              final isOwn = message.senderId ==
                                  _controller.currentUser.id;
                              return KeyedSubtree(
                                key: GlobalObjectKey(message),
                                child: MessageBubble(
                                  message: message,
                                  serverUrl: _controller.serverUrl,
                                  own: isOwn,
                                  read: isOwn &&
                                      _controller.isMessageRead(message),
                                  currentUserId: _controller.currentUser.id,
                                  senderName: _senderName(chat, message),
                                  replyPreview: _replyPreview(message),
                                  highlighted: message.id == _highlightId,
                                  onReplyTap: () =>
                                      _jumpToMessage(message.replyToMessageId),
                                  onReply: () => setState(() {
                                    _editing = null;
                                    _replyTo = message;
                                  }),
                                  onEdit: () => _startEdit(message),
                                  onDelete: () =>
                                      _controller.deleteMessage(message.id),
                                  onPin: () =>
                                      _controller.setPinnedMessage(message.id),
                                  onReaction: (emoji) => _controller
                                      .toggleReaction(message.id, emoji),
                                  onPlayVoice: _playVoice,
                                ),
                              );
                            },
                          ),
                // Composer поверх ленты — сообщения видны за ним (как в Telegram).
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!_canWrite(chat))
                        _muteBar(chat)
                      else if (!_recordingCircle)
                        MessageComposer(
                        controller: _messageController,
                        replyTo: _replyTo,
                        editing: _editing,
                        sendingMedia: _sendingMedia,
                        recordingVoice: _recordingVoice,
                        recordingMs: _recordingMs,
                        onAttach: _openAttachSheet,
                        onSend: _send,
                        onStartVoice: _startVoice,
                        onFinishVoice: _finishVoice,
                        onCancelVoice: _cancelVoice,
                        onCancelMode: _cancelComposerMode,
                        onTyping: _controller.notifyTyping,
                        onStartVideoCircle: () {
                          FocusScope.of(context).unfocus();
                          setState(() => _recordingCircle = true);
                        },
                      ),
                    ],
                  ),
                ),
                // Кнопка прокрутки в конец чата (видна при прокрутке вверх).
                Positioned(
                  right: 14,
                  bottom: MediaQuery.of(context).padding.bottom + 78,
                  child: IgnorePointer(
                    ignoring: !_showScrollDown,
                    child: AnimatedOpacity(
                      opacity: _showScrollDown ? 1 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: AnimatedScale(
                        scale: _showScrollDown ? 1 : 0.6,
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        child: _scrollDownButton(),
                      ),
                    ),
                  ),
                ),
                // Инлайн-запись видеокружка поверх всего чата.
                if (_recordingCircle)
                  Positioned.fill(
                    child: InlineVideoRecorder(
                      onSend: (media) {
                        setState(() => _recordingCircle = false);
                        _controller.sendMessage(media: media);
                        _scrollToBottom();
                      },
                      onCancel: () =>
                          setState(() => _recordingCircle = false),
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

  /// Может ли текущий пользователь писать в чат. В канале писать может только
  /// владелец, в группах/личных — все.
  bool _canWrite(Chat chat) {
    if (chat.type == ChatType.channel) {
      return chat.channelOwnerId == _controller.currentUser.id;
    }
    return true;
  }

  /// Вместо строки ввода (когда писать нельзя) — кнопка вкл/выкл звука канала.
  Widget _muteBar(Chat chat) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _controller.toggleMute(chat),
          child: Container(
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isLight ? Colors.white : panelStrong,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  chat.muted
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_off_rounded,
                  size: 20,
                  color: accent,
                ),
                const SizedBox(width: 10),
                Text(
                  chat.muted ? 'Включить звук' : 'Убрать звук',
                  style: TextStyle(
                    color: isLight ? lightText : text,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _appBar(Chat chat) {
    if (_msgSearch) {
      return AppBar(
        backgroundColor: Colors.transparent,
        flexibleSpace: const GlassBar(bottomBorder: true),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => setState(() {
            _msgSearch = false;
            _msgSearchController.clear();
          }),
        ),
        titleSpacing: 0,
        title: TextField(
          controller: _msgSearchController,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          cursorColor: accent,
          decoration: const InputDecoration(
            hintText: 'Поиск в чате',
            border: InputBorder.none,
            filled: false,
          ),
        ),
        actions: [
          if (_msgSearchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => setState(() => _msgSearchController.clear()),
            ),
        ],
      );
    }
    return AppBar(
      backgroundColor: Colors.transparent,
      flexibleSpace: const GlassBar(bottomBorder: true),
      titleSpacing: 0,
      title: InkWell(
        onTap: () => _openProfile(chat),
        child: Row(
          children: [
            BrenksAvatar(
              title: chat.title,
              imageUrl: _controller.displayAvatar(chat),
              baseUrl: _controller.serverUrl,
              size: 40,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          chat.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (chat.type == ChatType.channel && chat.verified) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.verified_rounded,
                            size: 17, color: accent),
                      ],
                    ],
                  ),
                  Builder(
                    builder: (context) {
                      final typing = _controller.typingNames;
                      if (typing.isNotEmpty) {
                        final label = chat.type == ChatType.direct
                            ? 'печатает'
                            : '${typing.join(', ')} печатает';
                        return _TypingIndicator(label: label);
                      }
                      return Text(
                        _controller.isPeerOnline(chat)
                            ? 'онлайн'
                            : chatSubtitle(chat),
                        style: const TextStyle(color: muted, fontSize: 12),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (chat.type == ChatType.direct &&
            _peerId(chat) != null &&
            chat.title != 'БренксЧат') ...[
          IconButton(
            tooltip: 'Аудиозвонок',
            icon: const Icon(Icons.call_rounded),
            onPressed: () =>
                _controller.call.startCall(_peerId(chat)!, 'audio'),
          ),
          IconButton(
            tooltip: 'Видеозвонок',
            icon: const Icon(Icons.videocam_rounded),
            onPressed: () =>
                _controller.call.startCall(_peerId(chat)!, 'video'),
          ),
        ],
        IconButton(
          tooltip: 'Поиск в чате',
          icon: const Icon(Icons.search_rounded),
          onPressed: () => setState(() => _msgSearch = true),
        ),
        PopupMenuButton<String>(
          onSelected: (value) => _onMenu(value, chat),
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'profile', child: Text('Профиль')),
            const PopupMenuItem(value: 'bg', child: Text('Изменить фон')),
            PopupMenuItem(
              value: 'mute',
              child: Text(chat.muted ? 'Включить звук' : 'Выключить звук'),
            ),
            PopupMenuItem(
              value: 'pin',
              child: Text(chat.pinnedToTop ? 'Открепить чат' : 'Закрепить чат'),
            ),
            if (_controller.currentUser.isAdmin &&
                chat.type == ChatType.channel)
              PopupMenuItem(
                value: 'verify',
                child: Text(
                    chat.verified ? 'Снять галочку' : 'Выдать галочку'),
              ),
            const PopupMenuItem(value: 'clear', child: Text('Очистить чат')),
            const PopupMenuItem(
              value: 'delete',
              child: Text('Удалить чат', style: TextStyle(color: danger)),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _onMenu(String value, Chat chat) async {
    switch (value) {
      case 'verify':
        try {
          await _controller.setChannelVerified(chat.id, !chat.verified);
        } on Object catch (e) {
          _showSnack('Не удалось изменить галочку: $e');
        }
      case 'profile':
        _openProfile(chat);
      case 'bg':
        _pickBackground();
      case 'mute':
        await _controller.toggleMute(chat);
      case 'pin':
        await _controller.togglePinTop(chat);
      case 'clear':
        if (await _confirm('Очистить чат?', 'Все сообщения пропадут у вас.')) {
          await _controller.clearChat(chat);
        }
      case 'delete':
        if (await _confirm('Удалить чат?', 'Чат будет удалён из списка.')) {
          await _controller.deleteChat(chat);
          if (mounted) Navigator.of(context).pop();
        }
    }
  }

  void _pickBackground() {
    final isLight = Theme.of(context).brightness == Brightness.light;
    const options = [
      ('По умолчанию', 0),
      ('Тёплый', 1),
      ('Графит', 2),
      ('Сепия', 3),
      ('Уголь', 4),
      ('Без фона', 5),
    ];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: isLight ? Colors.white : panel,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('Фон чата',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
              ),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.4,
                children: options.map(((String label, int idx) opt) {
                  final selected = _bgIndex == opt.$2;
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      _saveBg(opt.$2);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected ? accent : (isLight ? const Color(0xFFD4DAE3) : border),
                          width: selected ? 2.5 : 1,
                        ),
                        gradient: _bgGradient(opt.$2),
                        color: opt.$2 == 5
                            ? (isLight ? const Color(0xFFF3F5F8) : bg)
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          opt.$1,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: opt.$2 >= 1 && opt.$2 <= 4
                                ? Colors.white
                                : (isLight ? const Color(0xFF17202B) : text),
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static LinearGradient? _bgGradient(int idx) {
    switch (idx) {
      case 1: // Тёплый графит
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF26231D), Color(0xFF141209)],
        );
      case 2: // Холодный графит
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1C1F24), Color(0xFF111215)],
        );
      case 3: // Сепия
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2B261C), Color(0xFF161106)],
        );
      case 4: // Уголь
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF202327), Color(0xFF0E0F12)],
        );
      default:
        return null;
    }
  }

  void _openProfile(Chat chat) {
    Navigator.of(context).push(
      // Полноэкранный свайп-вправо назад в чат (как в самом чате).
      SwipeablePageRoute(
        canOnlySwipeFromEdge: false,
        builder: (_) =>
            ChatProfileScreen(controller: _controller, chatId: chat.id),
      ),
    );
  }

  /// id собеседника в личном чате (для звонка), иначе null.
  String? _peerId(Chat chat) {
    if (chat.type != ChatType.direct) return null;
    for (final p in chat.participants) {
      if (p.id != _controller.currentUser.id) return p.id;
    }
    for (final id in chat.participantIds) {
      if (id != _controller.currentUser.id) return id;
    }
    return null;
  }

  Widget _pinnedBanner(Message message) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: panelSoft.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.push_pin_rounded, color: accent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              messagePreview(message),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            tooltip: 'Открепить',
            visualDensity: VisualDensity.compact,
            onPressed: () => _controller.setPinnedMessage(null),
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}

/// Анимированный индикатор «печатает…» с волной из трёх точек.
class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator({required this.label});

  final String label;

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
              color: accent, fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 5),
        AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                final phase = (_c.value * 2 * math.pi) - i * 0.9;
                final t = (0.5 + 0.5 * math.sin(phase)).clamp(0.0, 1.0);
                return Padding(
                  padding: const EdgeInsets.only(right: 3),
                  child: Transform.translate(
                    offset: Offset(0, -2 * t),
                    child: Opacity(
                      opacity: (0.35 + 0.65 * t).clamp(0.0, 1.0),
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: const BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ],
    );
  }
}

/// Лёгкий фоновый «крестовый» паттерн как в desktop-версии.
class _PatternPainter extends CustomPainter {
  const _PatternPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = accent.withValues(alpha: 0.035)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    const gap = 44.0;
    const arm = 5.0;
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
