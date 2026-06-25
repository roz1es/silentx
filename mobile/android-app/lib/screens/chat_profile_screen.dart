import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';
import '../services/messenger_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/brenks_avatar.dart';
import '../widgets/glass.dart';

/// Экран профиля собеседника / чата: шапка + общие медиа, файлы и информация.
class ChatProfileScreen extends StatelessWidget {
  const ChatProfileScreen({
    super.key,
    required this.controller,
    required this.chatId,
  });

  final MessengerController controller;
  final String chatId;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final chat = controller.chatById(chatId);
        if (chat == null) {
          return const Scaffold(body: Center(child: Text('Чат недоступен')));
        }
        return _build(context, chat);
      },
    );
  }

  ChatParticipant? _peer(Chat chat) {
    for (final p in chat.participants) {
      if (p.id != controller.currentUser.id) return p;
    }
    return chat.participants.isNotEmpty ? chat.participants.first : null;
  }

  List<Message> _mediaMessages() {
    return controller.messages
        .where((m) =>
            !m.deleted &&
            ((m.media != null &&
                    (m.media!.kind == 'image' || m.media!.kind == 'video_note')) ||
                (m.media == null && (m.imageUrl?.isNotEmpty ?? false))))
        .toList()
        .reversed
        .toList(growable: false);
  }

  List<Message> _fileMessages() {
    return controller.messages
        .where((m) => !m.deleted && m.media != null && m.media!.kind == 'file')
        .toList()
        .reversed
        .toList(growable: false);
  }

  Widget _build(BuildContext context, Chat chat) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final peer = _peer(chat);
    final isDirect = chat.type == ChatType.direct;
    final online = peer != null && controller.onlineUserIds.contains(peer.id);
    final media = _mediaMessages();
    final files = _fileMessages();

    return GlassBackground(
      child: DefaultTabController(
        length: 3,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            flexibleSpace: const GlassBar(bottomBorder: true),
            title: const Text('Профиль',
                style: TextStyle(fontWeight: FontWeight.w900)),
          ),
          body: Column(
            children: [
              _header(context, chat, peer, isDirect, online, isLight),
              Material(
                color: Colors.transparent,
                child: TabBar(
                  labelColor: accent,
                  unselectedLabelColor: isLight ? lightMuted : muted,
                  indicatorColor: accent,
                  indicatorSize: TabBarIndicatorSize.label,
                  labelStyle: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 13),
                  tabs: [
                    Tab(text: 'Медиа ${media.isEmpty ? '' : media.length}'.trim()),
                    Tab(text: 'Файлы ${files.isEmpty ? '' : files.length}'.trim()),
                    const Tab(text: 'Инфо'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _mediaGrid(context, media),
                    _fileList(context, files, isLight),
                    _infoTab(context, chat, peer, isDirect, isLight),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, Chat chat, ChatParticipant? peer,
      bool isDirect, bool online, bool isLight) {
    final textColor = isLight ? const Color(0xFF17202B) : text;
    final mutedColor = isLight ? lightMuted : muted;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [accent, Color(0xFF7C5CF5)],
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
                imageUrl: controller.displayAvatar(chat),
                baseUrl: controller.serverUrl,
                size: 92,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            chat.title,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 23, fontWeight: FontWeight.w900, color: textColor),
          ),
          const SizedBox(height: 3),
          Text(
            isDirect && peer != null ? '@${peer.username}' : chatSubtitle(chat),
            style: TextStyle(color: mutedColor, fontSize: 15),
          ),
          if (isDirect) ...[
            const SizedBox(height: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: (online ? const Color(0xFF4AAE8A) : mutedColor)
                    .withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: online ? const Color(0xFF4AAE8A) : mutedColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    online ? 'в сети' : 'не в сети',
                    style: TextStyle(
                      color: online ? const Color(0xFF4AAE8A) : mutedColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _mediaGrid(BuildContext context, List<Message> media) {
    final mutedColor =
        Theme.of(context).brightness == Brightness.light ? lightMuted : muted;
    if (media.isEmpty) {
      return Center(
        child: Text('Общих медиа пока нет',
            style: TextStyle(color: mutedColor)),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemCount: media.length,
      itemBuilder: (context, index) {
        final m = media[index];
        return _MediaTile(message: m, serverUrl: controller.serverUrl);
      },
    );
  }

  Widget _fileList(BuildContext context, List<Message> files, bool isLight) {
    final mutedColor = isLight ? lightMuted : muted;
    final textColor = isLight ? const Color(0xFF17202B) : text;
    if (files.isEmpty) {
      return Center(
        child: Text('Файлов пока нет', style: TextStyle(color: mutedColor)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final media = files[index].media!;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GlassCard(
            borderRadius: 16,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.insert_drive_file_rounded,
                      color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    media.fileName ?? 'Файл',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: textColor),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _infoTab(BuildContext context, Chat chat, ChatParticipant? peer,
      bool isDirect, bool isLight) {
    final textColor = isLight ? const Color(0xFF17202B) : text;
    final mutedColor = isLight ? lightMuted : muted;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (isDirect && peer != null)
          _infoRow(Icons.alternate_email_rounded, 'Имя пользователя',
              '@${peer.username}', textColor, mutedColor),
        _infoRow(
          isDirect ? Icons.person_rounded : Icons.groups_rounded,
          'Тип чата',
          isDirect ? 'Личный чат' : (chat.type == ChatType.group ? 'Группа' : 'Канал'),
          textColor,
          mutedColor,
        ),
        if (!isDirect)
          _infoRow(Icons.people_rounded, 'Участники',
              '${chat.participants.length}', textColor, mutedColor),
        if (!isDirect && chat.participants.isNotEmpty) ...[
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 6),
            child: Text('УЧАСТНИКИ',
                style: TextStyle(
                    color: mutedColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2)),
          ),
          ...chat.participants.map(
            (p) => GlassCard(
              borderRadius: 14,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  BrenksAvatar(
                    title: p.title,
                    imageUrl: p.avatarUrl,
                    baseUrl: controller.serverUrl,
                    size: 40,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.title,
                            style: TextStyle(
                                fontWeight: FontWeight.w700, color: textColor)),
                        Text(
                          controller.onlineUserIds.contains(p.id)
                              ? 'в сети'
                              : '@${p.username}',
                          style: TextStyle(color: mutedColor, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _infoRow(IconData icon, String label, String value, Color textColor,
      Color mutedColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        borderRadius: 16,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: accent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(color: mutedColor, fontSize: 12)),
                  const SizedBox(height: 2),
                  Text(value,
                      style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
                ],
              ),
            ),
          ],
        ),
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
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: const Icon(Icons.videocam_rounded, color: Colors.white70, size: 30),
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
      child: Container(color: Colors.black12, child: image),
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
