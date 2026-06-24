import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';
import '../theme/app_theme.dart';

/// Нижняя панель ввода сообщения: вложения, текст, запись голосового, отправка.
class MessageComposer extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final modeMessage = editing ?? replyTo;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : const Color(0xFF202329),
        border: Border(
          top: BorderSide(color: isLight ? const Color(0xFFE2E7EF) : const Color(0xFF323946)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (recordingVoice) _recordingBanner(),
            if (modeMessage != null) _modeBanner(modeMessage),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
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
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 130),
                    child: TextField(
                      controller: controller,
                      minLines: 1,
                      maxLines: 5,
                      enabled: !recordingVoice,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      onChanged: (value) => onTyping(value.trim().isNotEmpty),
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
    );
  }

  Widget _sendArea() {
    if (recordingVoice) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Отмена',
            onPressed: onCancelVoice,
            icon: const Icon(Icons.delete_outline_rounded, color: danger),
          ),
          _circleButton(Icons.send_rounded, onFinishVoice),
        ],
      );
    }

    // Показываем «отправить», если есть текст или режим редактирования,
    // иначе — кнопку записи голосового.
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final hasText = value.text.trim().isNotEmpty;
        if (hasText || editing != null) {
          return _circleButton(
            editing != null ? Icons.check_rounded : Icons.send_rounded,
            onSend,
          );
        }
        return _circleButton(Icons.mic_rounded, onStartVoice);
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

  Widget _recordingBanner() {
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
              'Запись голосового... ${formatDuration(recordingMs)}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeBanner(Message modeMessage) {
    final title = editing != null ? 'Редактирование' : 'Ответ';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: panelSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
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
                  style: const TextStyle(color: muted, fontSize: 13),
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
    );
  }
}
