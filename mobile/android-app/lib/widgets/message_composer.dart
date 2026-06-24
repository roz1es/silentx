import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../format.dart';
import '../models.dart';
import '../screens/video_recorder_screen.dart';
import '../theme/app_theme.dart';

const _emojis = [
  '😀','😂','😍','🥰','😊','😎','🤔','😒','😢','😭','😡','🤯',
  '👍','👎','🙌','👏','🤝','💪','🎉','❤️','💔','💕','🔥','✨',
  '🤣','😅','😆','🥹','🥺','😏','😌','😴','🤗','😷','🤒','🤑',
  '😻','🙈','🙉','🙊','💀','👻','👾','🤖','💩','🎃','😈','🤡',
  '👋','🤚','🖐','✌️','🤞','🤟','🤘','🤙','👌','🤌','🫶','🫂',
  '🍕','🍔','🍟','🌮','🍜','🍣','🍺','🥂','🎂','🍫','🍬','🍭',
  '⚽','🏀','🏈','⚾','🎾','🏉','🎱','🏓','🎮','🎯','🎲','🏆',
  '🌍','🌙','⭐','🌟','💫','⚡','🌈','🌊','🌸','🌹','🌻','🍀',
  '🚀','✈️','🚗','🚂','🏠','🏖','🏔','🌃','🌉','🌆','🎡','🎢',
  '💎','💰','💳','🔑','🎁','🎈','🎊','🎆','📱','💻','🖥','⌚',
];

/// Нижняя панель ввода сообщения: вложения, текст, эмодзи, запись голосового, отправка.
class MessageComposer extends StatefulWidget {
  const MessageComposer({
    super.key,
    required this.controller,
    required this.replyTo,
    required this.editing,
    required this.sendingMedia,
    required this.recordingVoice,
    required this.recordingMs,
    required this.onAttach,
    required this.onSend,
    required this.onStartVoice,
    required this.onFinishVoice,
    required this.onCancelVoice,
    required this.onCancelMode,
    required this.onTyping,
    required this.onVideoCircle,
  });

  final TextEditingController controller;
  final Message? replyTo;
  final Message? editing;
  final bool sendingMedia;
  final bool recordingVoice;
  final int recordingMs;
  final VoidCallback onAttach;
  final VoidCallback onSend;
  final VoidCallback onStartVoice;
  final VoidCallback onFinishVoice;
  final VoidCallback onCancelVoice;
  final VoidCallback onCancelMode;
  final ValueChanged<bool> onTyping;
  final ValueChanged<MessageMedia> onVideoCircle;

  @override
  State<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<MessageComposer> {
  final _focusNode = FocusNode();
  bool _showEmoji = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _toggleEmoji() {
    if (_showEmoji) {
      setState(() => _showEmoji = false);
      _focusNode.requestFocus();
    } else {
      _focusNode.unfocus();
      SystemChannels.textInput.invokeMethod('TextInput.hide');
      setState(() => _showEmoji = true);
    }
  }

  Future<void> _openVideoCircle() async {
    if (_showEmoji) setState(() => _showEmoji = false);
    _focusNode.unfocus();
    final result = await Navigator.of(context).push<MessageMedia>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const VideoRecorderScreen(),
      ),
    );
    if (result != null) widget.onVideoCircle(result);
  }

  void _insertEmoji(String emoji) {
    final ctrl = widget.controller;
    final text = ctrl.text;
    final sel = ctrl.selection;
    final start = sel.start < 0 ? text.length : sel.start;
    final end = sel.end < 0 ? text.length : sel.end;
    final newText = text.replaceRange(start, end, emoji);
    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
    widget.onTyping(newText.trim().isNotEmpty);
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final modeMessage = widget.editing ?? widget.replyTo;
    final panelBg = Colors.white.withValues(alpha: isLight ? 0.55 : 0.07);
    final topBorder = Colors.white.withValues(alpha: isLight ? 0.6 : 0.12);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 12, 10),
          decoration: BoxDecoration(
            color: panelBg,
            border: Border(top: BorderSide(color: topBorder)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.recordingVoice) _recordingBanner(isLight),
                if (modeMessage != null) _modeBanner(modeMessage, isLight),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Emoji toggle
                    IconButton(
                      tooltip: _showEmoji ? 'Клавиатура' : 'Эмодзи',
                      onPressed: widget.recordingVoice ? null : _toggleEmoji,
                      icon: Icon(
                        _showEmoji
                            ? Icons.keyboard_rounded
                            : Icons.emoji_emotions_rounded,
                      ),
                    ),
                    // Video circle
                    IconButton(
                      tooltip: 'Видеокружок',
                      onPressed: widget.recordingVoice ? null : _openVideoCircle,
                      icon: const Icon(Icons.videocam_rounded),
                    ),
                    // Attach
                    IconButton(
                      tooltip: 'Прикрепить файл',
                      onPressed: widget.sendingMedia || widget.recordingVoice ? null : widget.onAttach,
                      icon: widget.sendingMedia
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.attach_file_rounded),
                    ),
                    Expanded(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 130),
                        child: TextField(
                          controller: widget.controller,
                          focusNode: _focusNode,
                          minLines: 1,
                          maxLines: 5,
                          enabled: !widget.recordingVoice,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          onChanged: (value) {
                            widget.onTyping(value.trim().isNotEmpty);
                            if (_showEmoji) setState(() => _showEmoji = false);
                          },
                          onTap: () {
                            if (_showEmoji) setState(() => _showEmoji = false);
                          },
                          decoration: const InputDecoration(
                            hintText: 'Сообщение',
                            contentPadding:
                                EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _sendArea(),
                  ],
                ),
              ],
            ),
          ),
            ),
          ),
        ),
        // Emoji panel
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: _showEmoji
              ? _emojiPanel(isLight, panelBg)
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _emojiPanel(bool isLight, Color bg) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
      height: 260,
      color: Colors.white.withValues(alpha: isLight ? 0.6 : 0.08),
      child: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 10,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
          childAspectRatio: 1,
        ),
        itemCount: _emojis.length,
        itemBuilder: (_, i) => GestureDetector(
          onTap: () => _insertEmoji(_emojis[i]),
          child: Center(
            child: Text(_emojis[i], style: const TextStyle(fontSize: 22)),
          ),
        ),
      ),
        ),
      ),
    );
  }

  Widget _sendArea() {
    if (widget.recordingVoice) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Отмена',
            onPressed: widget.onCancelVoice,
            icon: const Icon(Icons.delete_outline_rounded, color: danger),
          ),
          _circleButton(Icons.send_rounded, widget.onFinishVoice),
        ],
      );
    }

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: widget.controller,
      builder: (context, value, _) {
        final hasText = value.text.trim().isNotEmpty;
        if (hasText || widget.editing != null) {
          return _circleButton(
            widget.editing != null ? Icons.check_rounded : Icons.send_rounded,
            widget.onSend,
          );
        }
        return _circleButton(Icons.mic_rounded, widget.onStartVoice);
      },
    );
  }

  Widget _circleButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: accent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(icon, color: const Color(0xFF08131A)),
        ),
      ),
    );
  }

  Widget _recordingBanner(bool isLight) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: danger.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          const Icon(Icons.fiber_manual_record_rounded, color: danger, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Запись голосового... ${formatDuration(widget.recordingMs)}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeBanner(Message modeMessage, bool isLight) {
    final title = widget.editing != null ? 'Редактирование' : 'Ответ';
    final bannerBg = isLight ? const Color(0xFFF3F5F8) : panelSoft;
    final bannerBorder = isLight ? const Color(0xFFD4DAE3) : border;
    final previewColor = isLight ? const Color(0xFF637083) : muted;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bannerBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: bannerBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 32,
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
                  title,
                  style: const TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                Text(
                  messagePreview(modeMessage),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: previewColor, fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Отмена',
            onPressed: widget.onCancelMode,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}
