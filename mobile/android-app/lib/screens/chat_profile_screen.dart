import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../format.dart';
import '../models.dart';
import '../services/messenger_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/brenks_avatar.dart';
import '../widgets/glass.dart';

/// Профиль собеседника: инфо (ID / телефон / дата рождения / описание),
/// кнопки действий и общие медиа (Фото / ГС / Кружки / Файлы).
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
  int _tab = 0; // 0 — Фото, 1 — ГС, 2 — Кружки, 3 — Файлы
  User? _profile;

  MessengerController get _ctrl => widget.controller;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final chat = _ctrl.chatById(widget.chatId);
    if (chat == null) return;
    final peer = _peer(chat);
    if (peer == null) return;
    try {
      final u = await _ctrl.api.fetchUserProfile(peer.id);
      if (mounted) setState(() => _profile = u);
    } on Object {
      // Профиль может быть недоступен — покажем то, что есть.
    }
  }

  ChatParticipant? _peer(Chat chat) {
    for (final p in chat.participants) {
      if (p.id != _ctrl.currentUser.id) return p;
    }
    return chat.participants.isNotEmpty ? chat.participants.first : null;
  }

  String? _formatBirth(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final d = DateTime.tryParse(raw);
    if (d == null) return raw;
    const months = [
      'января', 'февраля', 'марта', 'апреля', 'мая', 'июня', //
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year} г.';
  }

  List<Message> _photos() => _ctrl.messages
      .where((m) =>
          !m.deleted &&
          ((m.media?.kind == 'image') ||
              (m.media == null && (m.imageUrl?.isNotEmpty ?? false))))
      .toList()
      .reversed
      .toList(growable: false);

  List<Message> _circles() => _ctrl.messages
      .where((m) => !m.deleted && m.media?.kind == 'video_note')
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
    final circles = _circles();
    final files = _files();

    final prof = _profile;
    final phone = prof?.phone?.trim();
    final birth = _formatBirth(prof?.birthDate);
    final bioText = prof?.bio?.trim();
    final canCall =
        isDirect && peer != null && chat.title != 'БренксЧат';

    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              // Шапка: заголовок + крестик.
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 12, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Профиль',
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: textColor)),
                          Text('Информация и общие медиа',
                              style:
                                  TextStyle(color: mutedColor, fontSize: 12)),
                        ],
                      ),
                    ),
                    Material(
                      color:
                          Colors.white.withValues(alpha: isLight ? 0.5 : 0.08),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => Navigator.of(context).maybePop(),
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: Icon(Icons.close_rounded,
                              color: textColor, size: 22),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 6, 18, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Аватар + имя.
                      Center(
                        child: Column(
                          children: [
                            Stack(
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
                                if (online)
                                  Positioned(
                                    right: 6,
                                    bottom: 6,
                                    child: Container(
                                      width: 16,
                                      height: 16,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF4AAE8A),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color:
                                                isLight ? Colors.white : bg,
                                            width: 3),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(chat.title,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    color: textColor)),
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
                      const SizedBox(height: 16),
                      // Кнопки действий.
                      if (isDirect && peer != null)
                        Row(
                          children: [
                            Expanded(
                              child: _actionBtn(
                                  Icons.edit_rounded,
                                  'Написать',
                                  () => Navigator.of(context).maybePop(),
                                  isLight),
                            ),
                            if (canCall) ...[
                              const SizedBox(width: 10),
                              Expanded(
                                child: _actionBtn(Icons.call_rounded, 'Звонок',
                                    () {
                                  Navigator.of(context).maybePop();
                                  _ctrl.call.startCall(peer.id, 'audio');
                                }, isLight),
                              ),
                            ],
                            const SizedBox(width: 10),
                            Expanded(
                              child: _actionBtn(
                                  Icons.ios_share_rounded, 'Поделиться', () {
                                final link =
                                    '${_ctrl.serverUrl}/u/${peer.username}';
                                Clipboard.setData(ClipboardData(text: link));
                                showAppToast(context, 'Ссылка скопирована');
                              }, isLight),
                            ),
                          ],
                        ),
                      const SizedBox(height: 14),
                      // Карточки информации.
                      if (peer != null)
                        _infoCard('Юзернейм', '@${peer.username}', textColor,
                            mutedColor),
                      if (phone != null && phone.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _infoCard('Телефон', phone, textColor, mutedColor),
                      ],
                      if (birth != null) ...[
                        const SizedBox(height: 10),
                        _infoCard(
                            'Дата рождения', birth, textColor, mutedColor),
                      ],
                      const SizedBox(height: 14),
                      Center(
                        child: Text(
                          bioText != null && bioText.isNotEmpty
                              ? bioText
                              : 'Нет описания',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: mutedColor, fontSize: 14),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Вкладки.
                      Row(
                        children: [
                          _segItem('Фото ${photos.length}', 0, isLight),
                          const SizedBox(width: 8),
                          _segItem(
                              'Голосовые ${voices.length + circles.length}',
                              1,
                              isLight),
                          const SizedBox(width: 8),
                          _segItem('Файлы ${files.length}', 2, isLight),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _tabContent(photos, voices, circles, files, mutedColor),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionBtn(
      IconData icon, String label, VoidCallback onTap, bool isLight) {
    return Material(
      color: Colors.white.withValues(alpha: isLight ? 0.5 : 0.06),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: isLight ? lightText : text)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoCard(
      String label, String value, Color textColor, Color mutedColor) {
    return GlassCard(
      borderRadius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: TextStyle(
                  color: mutedColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  color: textColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
        ],
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
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabContent(List<Message> photos, List<Message> voices,
      List<Message> circles, List<Message> files, Color mutedColor) {
    switch (_tab) {
      case 0:
        if (photos.isEmpty) return _empty(mutedColor);
        return _grid(photos);
      case 1:
        if (voices.isEmpty && circles.isEmpty) return _empty(mutedColor);
        return Column(
          children: [
            for (final m in voices)
              _row(
                Icons.mic_rounded,
                'Голосовое',
                formatDuration(m.media?.durationMs ?? 0),
                mutedColor,
              ),
            for (final m in circles)
              _row(
                Icons.videocam_rounded,
                'Видеокружок',
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

  Widget _grid(List<Message> items) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) =>
          _MediaTile(message: items[i], serverUrl: _ctrl.serverUrl),
    );
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

/// Плитка медиа в сетке: фото или круглая заглушка видеокружка, тап — просмотр.
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
              child: GestureDetector(
                onVerticalDragEnd: (d) {
                  if ((d.primaryVelocity ?? 0).abs() > 250) {
                    Navigator.pop(context);
                  }
                },
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
