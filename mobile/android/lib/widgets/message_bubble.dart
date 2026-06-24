import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../format.dart';
import '../models.dart';
import '../theme/app_theme.dart';
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
  });

  final Message message;
  final String serverUrl;
  final bool own;
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
      onLongPress: () => _openMenu(context),
      child: Align(
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
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                decoration: BoxDecoration(
                  color: own ? const Color(0xFF3B5568) : panelSoft,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(own ? 18 : 6),
                    bottomRight: Radius.circular(own ? 6 : 18),
                  ),
                  border: Border.all(
                    color: own
                        ? accent.withValues(alpha: 0.2)
                        : Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                      _ReplyChip(preview: replyPreview!),
                    _content(),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (message.editedAt != null && !message.deleted) ...[
                          const Text('изм.',
                              style: TextStyle(color: muted, fontSize: 11)),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          formatTime(message.createdAt),
                          style: const TextStyle(color: muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (message.reactions.isNotEmpty) _reactions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content() {
    if (message.deleted) {
      return const Text(
        'Сообщение удалено',
        style: TextStyle(
          color: muted,
          fontSize: 15,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    final media = message.media;
    final body = message.text.trim();
    final hasMedia = media != null || (message.imageUrl?.isNotEmpty == true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (media != null)
          MediaPreview(media: media, serverUrl: serverUrl, onPlayVoice: onPlayVoice),
        if (message.imageUrl?.isNotEmpty == true)
          ImagePreview(source: message.imageUrl!, serverUrl: serverUrl),
        if (body.isNotEmpty) ...[
          if (hasMedia) const SizedBox(height: 8),
          Text(body, style: const TextStyle(color: text, fontSize: 15.5)),
        ],
        if (!hasMedia && body.isEmpty)
          const Text('Сообщение', style: TextStyle(color: text, fontSize: 15.5)),
      ],
    );
  }

  Widget _reactions() {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: message.reactions.entries.map((entry) {
          final reacted = entry.value.contains(currentUserId);
          return GestureDetector(
            onTap: () => onReaction(entry.key),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: reacted ? accent.withValues(alpha: 0.22) : panelStrong,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: reacted ? accent : border,
                ),
              ),
              child: Text(
                '${entry.key} ${entry.value.length}',
                style: const TextStyle(fontSize: 13, color: text),
              ),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }

  Future<void> _openMenu(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: panel,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!message.deleted)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: quickReactions.map((emoji) {
                      return InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          onReaction(emoji);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(emoji, style: const TextStyle(fontSize: 26)),
                        ),
                      );
                    }).toList(growable: false),
                  ),
                ),
              const Divider(height: 1, color: border),
              _action(sheetContext, Icons.reply_rounded, 'Ответить', onReply),
              if (own && !message.deleted)
                _action(sheetContext, Icons.edit_rounded, 'Изменить', onEdit),
              if (!message.deleted)
                _action(
                  sheetContext,
                  Icons.copy_rounded,
                  'Копировать текст',
                  () => Clipboard.setData(
                      ClipboardData(text: message.text.trim())),
                ),
              if (!message.deleted)
                _action(sheetContext, Icons.push_pin_rounded, 'Закрепить', onPin),
              if (own)
                _action(
                  sheetContext,
                  Icons.delete_outline_rounded,
                  'Удалить',
                  onDelete,
                  isDanger: true,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _action(
    BuildContext sheetContext,
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool isDanger = false,
  }) {
    final color = isDanger ? danger : text;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(color: color)),
      onTap: () {
        Navigator.pop(sheetContext);
        onTap();
      },
    );
  }
}

class _ReplyChip extends StatelessWidget {
  const _ReplyChip({required this.preview});

  final String preview;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      child: Text(
        preview,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: muted, fontSize: 13),
      ),
    );
  }
}
