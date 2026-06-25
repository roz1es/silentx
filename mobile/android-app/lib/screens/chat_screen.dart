import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../format.dart';
import '../models.dart';
import '../services/audio_message_service.dart';
import '../services/messenger_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/brenks_avatar.dart';
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

  Message? _replyTo;
  Message? _editing;
  bool _sendingMedia = false;
  bool _recordingVoice = false;
  int _recordingMs = 0;
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
    unawaited(_audioService.dispose());
    _messageController.dispose();
    _msgSearchController.dispose();
    _scrollController.dispose();
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
    } on Object catch (err) {
      _showSnack('Не удалось отправить файл: $err');
    } finally {
      if (mounted) setState(() => _sendingMedia = false);
    }
  }

  Future<void> _startVoice() async {
    if (_recordingVoice) return;
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
    } on Object catch (err) {
      _showSnack('Не удалось отправить голосовое: $err');
    }
  }

  Future<void> _cancelVoice() async {
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
                              return MessageBubble(
                                message: message,
                                serverUrl: _controller.serverUrl,
                                own: isOwn,
                                read: isOwn &&
                                    _controller.isMessageRead(message),
                                currentUserId: _controller.currentUser.id,
                                senderName: _senderName(chat, message),
                                replyPreview: _replyPreview(message),
                                onReply: () => setState(() {
                                  _editing = null;
                                  _replyTo = message;
                                }),
                                onEdit: () => _startEdit(message),
                                onDelete: () =>
                                    _controller.deleteMessage(message.id),
                                onPin: () =>
                                    _controller.setPinnedMessage(message.id),
                                onReaction: (emoji) =>
                                    _controller.toggleReaction(message.id, emoji),
                                onPlayVoice: _playVoice,
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
                      MessageComposer(
                        controller: _messageController,
                        replyTo: _replyTo,
                        editing: _editing,
                        sendingMedia: _sendingMedia,
                        recordingVoice: _recordingVoice,
                        recordingMs: _recordingMs,
                        onAttach: _attach,
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
                  Text(
                    chat.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
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
      CupertinoPageRoute(
        builder: (_) =>
            ChatProfileScreen(controller: _controller, chatId: chat.id),
      ),
    );
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
