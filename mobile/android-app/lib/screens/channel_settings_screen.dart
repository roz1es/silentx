import 'package:flutter/material.dart';

import '../models.dart';
import '../services/messenger_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/brenks_avatar.dart';
import '../widgets/glass.dart';

/// Настройки канала для владельца: изменить название и назначить
/// администраторов (они тоже получают право писать в канал).
class ChannelSettingsScreen extends StatefulWidget {
  const ChannelSettingsScreen({
    super.key,
    required this.controller,
    required this.chatId,
  });

  final MessengerController controller;
  final String chatId;

  @override
  State<ChannelSettingsScreen> createState() => _ChannelSettingsScreenState();
}

class _ChannelSettingsScreenState extends State<ChannelSettingsScreen> {
  late final TextEditingController _nameCtrl;
  bool _savingName = false;
  final Set<String> _busyUsers = {};

  MessengerController get _ctrl => widget.controller;

  @override
  void initState() {
    super.initState();
    _nameCtrl =
        TextEditingController(text: _ctrl.chatById(widget.chatId)?.name ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    final name = _nameCtrl.text.trim();
    if (name.length < 2) {
      showAppToast(context, 'Название слишком короткое', error: true);
      return;
    }
    setState(() => _savingName = true);
    try {
      await _ctrl.updateChatName(widget.chatId, name);
      if (mounted) showAppToast(context, 'Название изменено');
    } on Object catch (e) {
      if (mounted) showAppToast(context, 'Ошибка: $e', error: true);
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _toggleAdmin(String userId, bool admin) async {
    setState(() => _busyUsers.add(userId));
    try {
      await _ctrl.setChannelAdmin(widget.chatId, userId, admin);
    } on Object catch (e) {
      if (mounted) showAppToast(context, 'Ошибка: $e', error: true);
    } finally {
      if (mounted) setState(() => _busyUsers.remove(userId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final textColor = isLight ? lightText : text;
    final mutedColor = isLight ? lightMuted : muted;
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          flexibleSpace: const GlassBar(bottomBorder: true),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: const Text('Настройки канала',
              style: TextStyle(fontWeight: FontWeight.w900)),
        ),
        body: ListenableBuilder(
          listenable: _ctrl,
          builder: (context, _) {
            final chat = _ctrl.chatById(widget.chatId);
            if (chat == null) {
              return const Center(child: Text('Канал недоступен'));
            }
            final ownerId = chat.channelOwnerId;
            final admins = chat.channelAdminIds.toSet();
            final others = chat.participants
                .where((p) => p.id != ownerId)
                .toList(growable: false);
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _label('НАЗВАНИЕ', mutedColor),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameCtrl,
                  style: TextStyle(color: textColor, fontSize: 16),
                  decoration:
                      const InputDecoration(hintText: 'Название канала'),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _savingName ? null : _saveName,
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: const Color(0xFF08131A),
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _savingName
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Color(0xFF08131A)))
                        : const Text('Сохранить',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(height: 24),
                _label('АДМИНИСТРАТОРЫ', mutedColor),
                const SizedBox(height: 4),
                Text('Администраторы тоже могут писать в канал.',
                    style: TextStyle(color: mutedColor, fontSize: 12.5)),
                const SizedBox(height: 10),
                if (others.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text('В канале пока только вы.',
                        style: TextStyle(color: mutedColor)),
                  )
                else
                  for (final p in others)
                    _participantRow(
                        p, admins.contains(p.id), textColor, mutedColor),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _label(String text, Color color) => Text(text,
      style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2));

  Widget _participantRow(
      ChatParticipant p, bool isAdmin, Color textColor, Color mutedColor) {
    final busy = _busyUsers.contains(p.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        borderRadius: 16,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            BrenksAvatar(
                title: p.title,
                imageUrl: p.avatarUrl,
                baseUrl: _ctrl.serverUrl,
                size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.title,
                      style: TextStyle(
                          color: textColor, fontWeight: FontWeight.w700)),
                  Text(isAdmin ? 'Администратор' : '@${p.username}',
                      style: TextStyle(
                          color: isAdmin ? accent : mutedColor,
                          fontSize: 12.5)),
                ],
              ),
            ),
            if (busy)
              const SizedBox(
                width: 40,
                height: 40,
                child: Center(
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              )
            else
              Switch(
                value: isAdmin,
                onChanged: (v) => _toggleAdmin(p.id, v),
                activeThumbColor: accent,
              ),
          ],
        ),
      ),
    );
  }
}
