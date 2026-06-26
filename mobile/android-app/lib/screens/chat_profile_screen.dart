import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';
import '../services/messenger_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/brenks_avatar.dart';
import '../widgets/glass.dart';

/// Профиль собеседника/чата: сверху информация, ниже — Фото / Голосовые / Файлы.
class ChatProfileScreen extends StatefulWidget {
  const ChatProfileScreen({
    super.key,
    required this.controller,
    required this.chatId,
  });

  final MessengerController controller;
  final String chatId;

  @override
  State<ChatProfileScreen> createState() => _ChatProfileScreenState();
}

class _ChatProfileScreenState extends State<ChatProfileScreen> {
  int _tab = 0; // 0 — Фото, 1 — Голосовые, 2 — Файлы

  MessengerController get _ctrl => widget.controller;

  ChatParticipant? _peer(Chat chat) {
    for (final p in chat.participants) {
      if (p.id != _ctrl.currentUser.id) return p;
    }
    return chat.participants.isNotEmpty ? chat.participants.first : null;
  }

  List<Message> _photos() => _ctrl.messages
      .where((m) =>
          !m.deleted &&
          ((m.media != null &&
                  (m.media!.kind == 'image' ||
                      m.media!.kind == 'video_note')) ||
              (m.media == null && (m.imageUrl?.isNotEmpty ?? false))))
      .toList()
      .reversed
      .toList(growable: false);

  List<Message> _voices() => _ctrl.messages
      .where((m) => !m.deleted && m.media?.kind == 'voice')
      .toList()
      .reversed
      .toList(growable: false);

  List<Message> _files() => _ctrl.messages
      .where((m) => !m.deleted && m.media?.kind == 'file')
      .toList()
      .reversed
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final chat = _ctrl.chatById(widget.chatId);
        if (chat == null) {
          return const Scaffold(body: Center(child: Text('Чат недоступен')));
        }
        return _build(context, chat);
      },
    );
  }

  Widget _build(BuildContext context, Chat chat) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final peer = _peer(chat);
    final isDirect = chat.type == ChatType.direct;
    final online = peer != null && _ctrl.onlineUserIds.contains(peer.id);
    final textColor = isLight ? lightText : text;
    final mutedColor = isLight ? lightMuted : muted;

    final photos = _photos();
    final voices = _voices();
    final files = _files();

    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              // Шапка с кнопкой назад (свайп тоже работает).
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: Icon(Icons.arrow_back_rounded, color: textColor),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Информация о пользователе ──
                      Center(
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [softGold, goldDark],
                                ),
                              ),
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isLight ? Colors.white : bg,
                                ),
                                child: BrenksAvatar(
                                  title: chat.title,
                                  imageUrl: _ctrl.displayAvatar(chat),
                                  baseUrl: _ctrl.serverUrl,
                                  size: 84,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              chat.title,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: textColor),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isDirect && peer != null
                                  ? '@${peer.username}'
                                  : chatSubtitle(chat),
                              style:
                                  TextStyle(color: mutedColor, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      // ── Карточка статуса ──
                      GlassCard(
                        borderRadius: 16,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                        child: Row(
                          children: [
                            Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                color: online
                                    ? const Color(0xFF4AAE8A)
                                    : mutedColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text('Статус',
                                  style: TextStyle(
                                      color: mutedColor,
                                      fontWeight: FontWeight.w600)),
                            ),
                            Text(
                              online ? 'онлайн' : 'не в сети',
                              style: TextStyle(
                                color: online ? accent : mutedColor,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      // ── Сегмент: Фото / Голосовые / Файлы ──
                      Row(
                        children: [
                          _segItem('Фото ${photos.length}', 0, isLight),
                          const SizedBox(width: 8),
                          _segItem('Голосовые ${voices.length}', 1, isLight),
                          const SizedBox(width: 8),
                          _segItem('Файлы ${files.length}', 2, isLight),
                        ],
                      ),
                      const SizedBox(height: 14),
                      // ── Содержимое выбранной вкладки ──
                      _tabContent(photos, voices, files, mutedColor),
                    ],
                  ),
                ),
              ),
              // ── Кнопка «Закрыть» ──
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    foregroundColor: textColor,
                    side: BorderSide(color: border),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Закрыть',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _segItem(String label, int index, bool isLight) {
    final selected = _tab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.12)
                : Colors.white.withValues(alpha: isLight ? 0.45 : 0.05),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? goldBorder
                  : Colors.white.withValues(alpha: isLight ? 0.5 : 0.08),
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? accent : (isLight ? lightMuted : muted),
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabContent(List<Message> photos, List<Message> voices,
      List<Message> files, Color mutedColor) {
    switch (_tab) {
      case 0:
        if (photos.isEmpty) return _empty(mutedColor);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemCount: photos.length,
          itemBuilder: (context, i) =>
              _MediaTile(message: photos[i], serverUrl: _ctrl.serverUrl),
        );
      case 1:
        if (voices.isEmpty) return _empty(mutedColor);
        return Column(
          children: [
            for (final m in voices)
              _row(
                Icons.mic_rounded,
                'Голосовое',
                formatDuration(m.media?.durationMs ?? 0),
                mutedColor,
              ),
          ],
        );
      default:
        if (files.isEmpty) return _empty(mutedColor);
        return Column(
          children: [
            for (final m in files)
              _row(
                Icons.insert_drive_file_rounded,
                m.media?.fileName ?? 'Файл',
                '',
                mutedColor,
              ),
          ],
        );
    }
  }

  Widget _row(IconData icon, String title, String trailing, Color mutedColor) {
    final textColor = mutedColor == lightMuted ? lightText : text;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        borderRadius: 14,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: accent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: textColor)),
            ),
            if (trailing.isNotEmpty)
              Text(trailing, style: TextStyle(color: mutedColor, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _empty(Color mutedColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Text('Здесь пока пусто',
            style: TextStyle(color: mutedColor, fontSize: 14)),
      ),
    );
  }
}

/// Плитка медиа в сетке: фото или заглушка видеокружка, тап — просмотр.
class _MediaTile extends StatelessWidget {
  const _MediaTile({required this.message, required this.serverUrl});

  final Message message;
  final String serverUrl;

  @override
  Widget build(BuildContext context) {
    final media = message.media;
    final isVideo = media?.kind == 'video_note';
    final source = media?.dataUrl ?? message.imageUrl ?? '';

    if (isVideo) {
      // Видеокружок — круглая плитка с золотой иконкой, чтобы было понятно.
      return Padding(
        padding: const EdgeInsets.all(6),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black,
            border: Border.all(color: accent.withValues(alpha: 0.55), width: 2),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.videocam_rounded, color: accent, size: 30),
        ),
      );
    }

    final bytes = bytesFromDataUrl(source);
    final url = bytes == null ? resolveMediaUrl(source, serverUrl) : null;
    final image = bytes != null
        ? Image.memory(bytes, fit: BoxFit.cover)
        : (url != null && url.isNotEmpty)
            ? Image.network(url, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _broken())
            : _broken();

    return GestureDetector(
      onTap: () => _openViewer(context, bytes, url),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(color: Colors.black26, child: image),
      ),
    );
  }

  Widget _broken() => Container(
        color: Colors.black26,
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image_rounded, color: Colors.white54),
      );

  void _openViewer(BuildContext context, Uint8List? bytes, String? url) {
    if (bytes == null && (url == null || url.isEmpty)) return;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 0.6,
                maxScale: 5,
                child: Center(
                  child: bytes != null
                      ? Image.memory(bytes, fit: BoxFit.contain)
                      : Image.network(url!, fit: BoxFit.contain),
                ),
              ),
            ),
            Positioned(
              right: 16,
              top: 16,
              child: SafeArea(
                child: IconButton.filledTonal(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
