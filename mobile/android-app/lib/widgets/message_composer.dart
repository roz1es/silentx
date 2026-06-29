import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../format.dart';
import '../models.dart';
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
    required this.recordingLevels,
    required this.onAttach,
    required this.onSend,
    required this.onStartVoice,
    required this.onFinishVoice,
    required this.onCancelVoice,
    required this.onCancelMode,
    required this.onTyping,
    required this.onStartVideoCircle,
  });

  final TextEditingController controller;
  final Message? replyTo;
  final Message? editing;
  final bool sendingMedia;
  final bool recordingVoice;
  final ValueListenable<int> recordingMs;
  final ValueListenable<List<double>> recordingLevels;
  final VoidCallback onAttach;
  final VoidCallback onSend;
  final VoidCallback onStartVoice;
  final VoidCallback onFinishVoice;
  final VoidCallback onCancelVoice;
  final VoidCallback onCancelMode;
  final ValueChanged<bool> onTyping;
  final VoidCallback onStartVideoCircle;

  @override
  State<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<MessageComposer> {
  final _focusNode = FocusNode();
  bool _showEmoji = false;
  // false — режим голосовых, true — режим видеокружков.
  bool _circleMode = false;

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

  void _startVideoCircle() {
    if (_showEmoji) setState(() => _showEmoji = false);
    _focusNode.unfocus();
    widget.onStartVideoCircle();
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
    final blob = isLight ? Colors.white : panelSoft;
    final iconColor = isLight ? lightMuted : muted;
    final hintColor = isLight ? const Color(0xFF8A857B) : hint;
    final hasText = widget.controller.text.trim().isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (modeMessage != null) _modeBanner(modeMessage, isLight),
                if (widget.recordingVoice)
                  _voiceBar(isLight)
                else
                  Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Левый кружок — вложение
                    _blob(
                      color: blob,
                      isLight: isLight,
                      onTap: (widget.sendingMedia || widget.recordingVoice)
                          ? null
                          : widget.onAttach,
                      child: widget.sendingMedia
                          ? SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: iconColor),
                            )
                          : Icon(Icons.attach_file_rounded,
                              color: iconColor, size: 24),
                    ),
                    const SizedBox(width: 8),
                    // Центральная «пилюля» с полем ввода
                    Expanded(
                      child: _pill(isLight, blob, iconColor, hintColor, hasText),
                    ),
                    const SizedBox(width: 8),
                    // Правый кружок — видео / отправка / запись
                    _rightArea(isLight, blob, iconColor, hasText),
                  ],
                ),
              ],
            ),
          ),
        ),
        // Панель эмодзи
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: _showEmoji && !widget.recordingVoice
              ? _emojiPanel(isLight)
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _pill(bool isLight, Color blob, Color iconColor, Color hintColor,
      bool hasText) {
    return Material(
      color: blob,
      elevation: isLight ? 2 : 1,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(26),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52, maxHeight: 132),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(width: 18),
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: _focusNode,
                minLines: 1,
                maxLines: 5,
                enabled: !widget.recordingVoice,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                cursorColor: accent,
                style: TextStyle(
                    color: isLight ? const Color(0xFF17202B) : text,
                    fontSize: 16),
                onChanged: (value) {
                  widget.onTyping(value.trim().isNotEmpty);
                  if (_showEmoji) {
                    _showEmoji = false;
                  }
                  setState(() {});
                },
                onTap: () {
                  if (_showEmoji) setState(() => _showEmoji = false);
                },
                decoration: InputDecoration(
                  isCollapsed: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  hintText: 'Сообщение',
                  hintStyle: TextStyle(color: hintColor, fontSize: 16),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
            ),
            _pillIcon(
              _showEmoji
                  ? Icons.keyboard_rounded
                  : Icons.emoji_emotions_outlined,
              iconColor,
              widget.recordingVoice ? null : _toggleEmoji,
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }

  Widget _pillIcon(IconData icon, Color color, VoidCallback? onTap) {
    return InkResponse(
      onTap: onTap,
      radius: 24,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }

  Widget _rightArea(bool isLight, Color blob, Color iconColor, bool hasText) {
    if (widget.recordingVoice) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _blob(
            color: blob,
            isLight: isLight,
            onTap: widget.onCancelVoice,
            child: const Icon(Icons.delete_outline_rounded,
                color: danger, size: 24),
          ),
          const SizedBox(width: 8),
          _blob(
            color: accent,
            isLight: isLight,
            onTap: widget.onFinishVoice,
            child: const Icon(Icons.send_rounded,
                color: Color(0xFF08131A), size: 24),
          ),
        ],
      );
    }
    if (hasText || widget.editing != null) {
      return _SendButton(
        icon: widget.editing != null
            ? Icons.check_rounded
            : Icons.send_rounded,
        isLight: isLight,
        onTap: widget.onSend,
      );
    }
    // Пусто → кнопка режима: тап переключает голос/кружок,
    // удержание — запись (голос) либо открытие записи кружка.
    return Tooltip(
      message: _circleMode
          ? 'Видеокружок (удерживайте). Тап — голосовое'
          : 'Голосовое (удерживайте). Тап — видеокружок',
      child: _blob(
        color: blob,
        isLight: isLight,
        onTap: () => setState(() => _circleMode = !_circleMode),
        onLongPress: _circleMode ? _startVideoCircle : widget.onStartVoice,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          transitionBuilder: (child, animation) => ScaleTransition(
            scale: animation,
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: _circleMode
              ? _VideoCircleIcon(
                  key: const ValueKey('circle'), color: iconColor)
              : Icon(
                  Icons.mic_rounded,
                  key: const ValueKey('mic'),
                  color: iconColor,
                  size: 24,
                ),
        ),
      ),
    );
  }

  Widget _blob({
    required Color color,
    required bool isLight,
    required Widget child,
    required VoidCallback? onTap,
    VoidCallback? onLongPress,
  }) {
    return Material(
      color: color,
      shape: const CircleBorder(),
      elevation: isLight ? 2 : 1,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        onLongPress: onLongPress,
        child: SizedBox(width: 52, height: 52, child: Center(child: child)),
      ),
    );
  }

  Widget _emojiPanel(bool isLight) {
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

  /// Панель записи голосового: строка ввода превращается в таймер + «Отмена» +
  /// кнопку отправки (как при записи видеокружка).
  Widget _voiceBar(bool isLight) {
    final pillBg = isLight ? const Color(0xFFEDEFF3) : panelSoft;
    final timeColor = isLight ? lightText : text;
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 52,
            padding: const EdgeInsets.fromLTRB(16, 0, 6, 0),
            decoration: BoxDecoration(
              color: pillBg,
              borderRadius: BorderRadius.circular(26),
            ),
            child: Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: danger,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                ValueListenableBuilder<int>(
                  valueListenable: widget.recordingMs,
                  builder: (_, ms, __) => Text(
                    _fmtVoice(ms),
                    style: TextStyle(
                      color: timeColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ValueListenableBuilder<List<double>>(
                    valueListenable: widget.recordingLevels,
                    builder: (_, levels, __) => SizedBox(
                      height: 24,
                      child: CustomPaint(
                        painter: _RecWavePainter(levels, accent),
                        size: Size.infinite,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onCancelVoice,
                  child: const Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Text(
                      'Отмена',
                      style: TextStyle(
                        color: danger,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Material(
          color: accent,
          shape: const CircleBorder(),
          elevation: isLight ? 2 : 1,
          shadowColor: Colors.black.withValues(alpha: 0.25),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: widget.onFinishVoice,
            child: const SizedBox(
              width: 52,
              height: 52,
              child: Icon(Icons.arrow_upward_rounded,
                  color: Color(0xFF08131A), size: 26),
            ),
          ),
        ),
      ],
    );
  }

  String _fmtVoice(int ms) {
    final s = (ms / 1000).truncate();
    final cs = (ms % 1000) ~/ 10; // сотые доли секунды (две цифры)
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')},'
        '${cs.toString().padLeft(2, '0')}';
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
                  style: TextStyle(
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

/// Живая волна записи: бегущие столбики из уровней громкости (новые справа).
class _RecWavePainter extends CustomPainter {
  _RecWavePainter(this.levels, this.color);

  final List<double> levels;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (levels.isEmpty) return;
    const barW = 2.5;
    const step = barW + 2.0;
    final maxBars = (size.width / step).floor();
    if (maxBars <= 0) return;
    final shown = levels.length > maxBars
        ? levels.sublist(levels.length - maxBars)
        : levels;
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barW;
    final cy = size.height / 2;
    double x = size.width - shown.length * step + barW / 2;
    for (final lvl in shown) {
      final h = lvl.clamp(0.0, 1.0) * (size.height - 3) + 3;
      canvas.drawLine(Offset(x, cy - h / 2), Offset(x, cy + h / 2), paint);
      x += step;
    }
  }

  @override
  bool shouldRepaint(covariant _RecWavePainter old) =>
      !identical(old.levels, levels) || old.color != color;
}

/// Кнопка отправки с анимацией «вылета» самолётика при нажатии.
class _SendButton extends StatefulWidget {
  const _SendButton({
    required this.icon,
    required this.isLight,
    required this.onTap,
  });

  final IconData icon;
  final bool isLight;
  final VoidCallback onTap;

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _handleTap() {
    _c.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: accent,
      shape: const CircleBorder(),
      elevation: widget.isLight ? 2 : 1,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _handleTap,
        child: SizedBox(
          width: 52,
          height: 52,
          child: Center(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, child) {
                final t = _c.value;
                double dx, dy, op;
                if (t < 0.5) {
                  // улетает вправо-вверх и затухает
                  final p = t / 0.5;
                  dx = p * 26;
                  dy = -p * 14;
                  op = 1 - p;
                } else {
                  // прилетает обратно слева-снизу
                  final p = Curves.easeOutBack.transform((t - 0.5) / 0.5);
                  dx = (1 - p) * -12;
                  dy = (1 - p) * 8;
                  op = ((t - 0.5) / 0.5).clamp(0.0, 1.0);
                }
                return Transform.translate(
                  offset: Offset(dx, dy),
                  child: Opacity(opacity: op.clamp(0.0, 1.0), child: child),
                );
              },
              child: Icon(widget.icon,
                  color: const Color(0xFF08131A), size: 24),
            ),
          ),
        ),
      ),
    );
  }
}

/// Иконка «видеокружок» для строки ввода: кольцо с камерой внутри —
/// сразу понятно, что запись будет круглой (видеокружок), а не обычным видео.
class _VideoCircleIcon extends StatelessWidget {
  const _VideoCircleIcon({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    // Визуальный размер ~22px — как у иконок скрепки/смайла (Icon size 24
    // рисует глиф с внутренним отступом), чтобы все элементы были в ряд.
    return SizedBox(
      width: 22,
      height: 22,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2),
            ),
          ),
          Icon(Icons.videocam_rounded, color: color, size: 12),
        ],
      ),
    );
  }
}
