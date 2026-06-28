import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../format.dart';
import '../models.dart';
import '../theme/app_theme.dart';
import 'glass.dart';
import 'media_preview.dart';

const quickReactions = ['👍', '❤️', '😂', '🔥', '😮', '😢'];

/// Пузырь сообщения с мобильным контекстным меню (long-press).
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.serverUrl,
    required this.own,
    required this.currentUserId,
    required this.onReply,
    required this.onEdit,
    required this.onDelete,
    required this.onPin,
    required this.onReaction,
    required this.onPlayVoice,
    this.senderName,
    this.replyPreview,
    this.read = false,
  });

  final Message message;
  final String serverUrl;
  final bool own;
  final bool read;
  final String currentUserId;
  final VoidCallback onReply;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onPin;
  final ValueChanged<String> onReaction;
  final ValueChanged<MessageMedia> onPlayVoice;
  final String? senderName;
  final String? replyPreview;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (d) => _openMenu(context, d.globalPosition),
      child: _bubbleBody(context),
    );
  }

  /// Тело пузыря без жестов — переиспользуется как «приподнятая» копия в меню.
  Widget _bubbleBody(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    // Исходящее — тёплый тёмный (лёгкий золотой оттенок), входящее — графит.
    final ownBg = isLight ? const Color(0xFFF0E7D6) : const Color(0xFF34312A);
    final otherBg = isLight ? Colors.white : const Color(0xFF34373E);
    final ownBorder =
        isLight ? const Color(0xFFE3D6B8) : accent.withValues(alpha: 0.18);
    final otherBorder = isLight
        ? const Color(0xFFE6E2D8)
        : Colors.white.withValues(alpha: 0.06);
    final msgTextColor = isLight ? lightText : text;
    final timeColor = isLight ? lightMuted : muted;

    // Видеокружок (без текста) — отдельно, без прямоугольного пузыря.
    final m = message.media;
    final isCircleNote = !message.deleted &&
        m != null &&
        m.kind == 'video_note' &&
        message.text.trim().isEmpty &&
        (message.imageUrl?.isEmpty ?? true);
    if (isCircleNote) {
      return Align(
        alignment: own ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment:
                own ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!own && senderName != null && senderName!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4, left: 4),
                  child: Text(
                    senderName!,
                    style: const TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              MediaPreview(
                media: m,
                serverUrl: serverUrl,
                onPlayVoice: onPlayVoice,
                timeLabel: formatTime(message.createdAt),
                read: read,
                own: own,
              ),
            ],
          ),
        ),
      );
    }

    // Чистое фото без подписи и без ответа — без прямоугольного пузыря
    // (как в Telegram): «голый» снимок со временем/галочками поверх.
    final isPhotoOnly = !message.deleted &&
        message.text.trim().isEmpty &&
        replyPreview == null &&
        ((m != null && m.kind == 'image') ||
            (message.imageUrl?.isNotEmpty ?? false));
    if (isPhotoOnly) {
      return Align(
        alignment: own ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.82,
          ),
          margin: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment:
                own ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!own && senderName != null && senderName!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4, left: 4),
                  child: Text(
                    senderName!,
                    style: const TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              if (m != null)
                MediaPreview(
                  media: m,
                  serverUrl: serverUrl,
                  onPlayVoice: onPlayVoice,
                  timeLabel: formatTime(message.createdAt),
                  read: read,
                  own: own,
                )
              else
                ImagePreview(
                  source: message.imageUrl!,
                  serverUrl: serverUrl,
                  timeLabel: formatTime(message.createdAt),
                  read: read,
                  own: own,
                ),
              if (message.reactions.isNotEmpty) _reactions(isLight),
            ],
          ),
        ),
      );
    }

    return Align(
        alignment: own ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.82,
          ),
          margin: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment:
                own ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(11, 6, 11, 6),
                decoration: BoxDecoration(
                  color: own ? ownBg : otherBg,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(own ? 18 : 5),
                    bottomRight: Radius.circular(own ? 5 : 18),
                  ),
                  border: Border.all(color: own ? ownBorder : otherBorder),
                ),
                child: IntrinsicWidth(
                  child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!own && senderName != null && senderName!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          senderName!,
                          style: const TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    if (replyPreview != null && !message.deleted)
                      _ReplyChip(preview: replyPreview!, isLight: isLight),
                    ..._bubbleInner(msgTextColor, timeColor, isLight),
                  ],
                ),
                ),
              ),
              if (message.reactions.isNotEmpty) _reactions(isLight),
            ],
          ),
        ),
    );
  }

  /// Содержимое пузыря. Для чистого текста время «втекает» в строку (инлайн
  /// справа внизу) — компактнее. Для медиа с подписью время идёт отдельной
  /// строкой под контентом.
  List<Widget> _bubbleInner(Color textColor, Color timeColor, bool isLight) {
    if (message.deleted) {
      return [_inlineText('Сообщение удалено', textColor, timeColor, isLight)];
    }

    final media = message.media;
    final body = message.text.trim();
    final hasMedia = media != null || (message.imageUrl?.isNotEmpty == true);

    if (!hasMedia) {
      return [
        _inlineText(
            body.isEmpty ? 'Сообщение' : body, textColor, timeColor, isLight),
      ];
    }

    return [
      if (media != null)
        MediaPreview(
            media: media, serverUrl: serverUrl, onPlayVoice: onPlayVoice),
      if (message.imageUrl?.isNotEmpty == true)
        ImagePreview(source: message.imageUrl!, serverUrl: serverUrl),
      if (body.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(body, style: TextStyle(color: textColor, fontSize: 15)),
      ],
      const SizedBox(height: 3),
      Align(alignment: Alignment.centerRight, child: _meta(timeColor, isLight)),
    ];
  }

  /// Текст с временем, наложенным в правый нижний угол. В конце текста —
  /// невидимый «резерв» шириной под метку времени, поэтому последняя строка
  /// оставляет ей место (как в Telegram).
  Widget _inlineText(
      String body, Color textColor, Color timeColor, bool isLight) {
    final hasEdited = message.editedAt != null && !message.deleted;
    final reserve = (own && !message.deleted ? 54.0 : 38.0) +
        (hasEdited ? 30.0 : 0.0);
    return Stack(
      children: [
        Text.rich(
          TextSpan(
            text: body,
            children: [
              WidgetSpan(child: SizedBox(width: reserve, height: 1)),
            ],
          ),
          style: TextStyle(
            color: textColor,
            fontSize: 15,
            fontStyle:
                message.deleted ? FontStyle.italic : FontStyle.normal,
          ),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: _meta(timeColor, isLight),
        ),
      ],
    );
  }

  /// Компактная метка времени: «изм.» + время + галочки прочтения.
  Widget _meta(Color timeColor, bool isLight) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (message.editedAt != null && !message.deleted) ...[
          Text('изм.', style: TextStyle(color: timeColor, fontSize: 10.5)),
          const SizedBox(width: 5),
        ],
        Text(
          formatTime(message.createdAt),
          style: TextStyle(color: timeColor, fontSize: 10.5),
        ),
        if (own && !message.deleted) ...[
          const SizedBox(width: 3),
          Icon(
            read ? Icons.done_all_rounded : Icons.done_rounded,
            size: 13,
            color: read ? (isLight ? lightAccent : softGold) : timeColor,
          ),
        ],
      ],
    );
  }

  Widget _reactions(bool isLight) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: message.reactions.entries.map((entry) {
          final reacted = entry.value.contains(currentUserId);
          final reactBg = reacted
              ? accent.withValues(alpha: 0.22)
              : (isLight ? const Color(0xFFE8EEF5) : panelStrong);
          final reactBorder = reacted ? accent : (isLight ? const Color(0xFFD4DAE3) : border);
          final reactText = isLight ? const Color(0xFF17202B) : text;
          return GestureDetector(
            onTap: () => onReaction(entry.key),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: reactBg,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: reactBorder),
              ),
              child: Text(
                '${entry.key} ${entry.value.length}',
                style: TextStyle(fontSize: 13, color: reactText),
              ),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }

  Future<void> _openMenu(BuildContext context, Offset pos) async {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final bubble = _bubbleBody(context);
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'menu',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (ctx, _, __) => _ContextMenu(
        pos: pos,
        isLight: isLight,
        own: own,
        deleted: message.deleted,
        messageText: message.text,
        bubble: bubble,
        onReply: onReply,
        onEdit: onEdit,
        onPin: onPin,
        onDelete: onDelete,
        onReaction: onReaction,
      ),
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(opacity: curved, child: child);
      },
    );
  }
}

/// Всплывающее контекстное меню сообщения (iOS-стиль):
/// размытый фон + приподнятое сообщение + пилюля реакций + действия.
class _ContextMenu extends StatefulWidget {
  const _ContextMenu({
    required this.pos,
    required this.isLight,
    required this.own,
    required this.deleted,
    required this.messageText,
    required this.bubble,
    required this.onReply,
    required this.onEdit,
    required this.onPin,
    required this.onDelete,
    required this.onReaction,
  });

  final Offset pos;
  final bool isLight;
  final bool own;
  final bool deleted;
  final String messageText;
  final Widget bubble;
  final VoidCallback onReply;
  final VoidCallback onEdit;
  final VoidCallback onPin;
  final VoidCallback onDelete;
  final ValueChanged<String> onReaction;

  @override
  State<_ContextMenu> createState() => _ContextMenuState();
}

class _ContextMenuState extends State<_ContextMenu> {
  static const _primary = ['❤️', '👍', '👎', '😂', '😮', '🔥'];
  static const _secondary = ['😢', '🎉', '🙏', '💯', '😡', '👏'];

  bool _more = false;

  void _close() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final cardBg = widget.isLight ? Colors.white : panel;
    final actionColor = widget.isLight ? lightText : text;
    final scrim = widget.isLight
        ? Colors.black.withValues(alpha: 0.18)
        : Colors.black.withValues(alpha: 0.34);
    // Привязываем «остров» к точке нажатия, оставляя запас у краёв.
    final alignY = ((widget.pos.dy / size.height) * 2 - 1).clamp(-0.82, 0.82);

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Размытие + лёгкое затемнение фона чата.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _close,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(color: scrim),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _close,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                          minHeight: constraints.maxHeight - 24),
                      child: Align(
                        alignment: Alignment(0, alignY),
                        child: Column(
                          crossAxisAlignment: widget.own
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!widget.deleted) ...[
                              _reactionsBar(cardBg),
                              const SizedBox(height: 12),
                            ],
                            // Само сообщение «всплывает» над размытием.
                            GestureDetector(
                              onTap: () {},
                              child: widget.bubble,
                            ),
                            const SizedBox(height: 10),
                            GestureDetector(
                              onTap: () {},
                              child: _menuCard(cardBg, actionColor),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _reactionsBar(Color cardBg) {
    final emojis = _more ? _secondary : _primary;
    return Align(
      alignment: widget.own ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.3), blurRadius: 16),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final emoji in emojis)
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () {
                  _close();
                  widget.onReaction(emoji);
                },
                child: Padding(
                  padding: const EdgeInsets.all(7),
                  child: Text(emoji, style: const TextStyle(fontSize: 25)),
                ),
              ),
            // Кнопка «ещё реакции».
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => setState(() => _more = !_more),
              child: Container(
                margin: const EdgeInsets.only(left: 2),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color:
                      widget.isLight ? const Color(0xFFEDEDED) : panelStrong,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _more
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 22,
                  color: widget.isLight ? lightMuted : muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuCard(Color cardBg, Color actionColor) {
    return Align(
      alignment: widget.own ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width: 248,
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 26,
                offset: const Offset(0, 10)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _item(Icons.reply_rounded, 'Ответить', () {
              _close();
              widget.onReply();
            }, actionColor),
            if (!widget.deleted)
              _item(Icons.copy_rounded, 'Скопировать', () {
                Clipboard.setData(
                    ClipboardData(text: widget.messageText.trim()));
                showAppToast(context, 'Скопировано');
                _close();
              }, actionColor),
            if (widget.own && !widget.deleted)
              _item(Icons.edit_rounded, 'Изменить', () {
                _close();
                widget.onEdit();
              }, actionColor),
            if (!widget.deleted)
              _item(Icons.push_pin_rounded, 'Закрепить', () {
                _close();
                widget.onPin();
              }, actionColor),
            if (widget.own) ...[
              Container(height: 1, color: border),
              _item(Icons.delete_outline_rounded, 'Удалить', () {
                _close();
                widget.onDelete();
              }, danger),
            ],
          ],
        ),
      ),
    );
  }

  Widget _item(IconData icon, String label, VoidCallback onTap, Color color) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 14),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class _ReplyChip extends StatelessWidget {
  const _ReplyChip({required this.preview, required this.isLight});

  final String preview;
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isLight
            ? const Color(0xFF96BFDF).withValues(alpha: 0.25)
            : Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      child: Text(
        preview,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isLight ? const Color(0xFF637083) : muted,
          fontSize: 13,
        ),
      ),
    );
  }
}
