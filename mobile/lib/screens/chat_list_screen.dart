import 'package:flutter/material.dart';

import '../models.dart';
import '../services/messenger_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/brenks_avatar.dart';
import '../widgets/chat_tile.dart';
import '../widgets/empty_state.dart';
import '../widgets/new_chat_sheet.dart';
import 'chat_screen.dart';

/// Главный экран после входа: список чатов.
class ChatListScreen extends StatefulWidget {
  const ChatListScreen({
    super.key,
    required this.controller,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.onLogout,
  });

  final MessengerController controller;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final Future<void> Function() onLogout;

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final _searchController = TextEditingController();
  bool _searching = false;

  MessengerController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _openChat(Chat chat) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(controller: _controller, chatId: chat.id),
      ),
    );
  }

  Future<void> _newChat() async {
    try {
      final users = await _controller.api.fetchUserDirectory();
      if (!mounted) return;
      final result = await showNewChatSheet(
        context,
        serverUrl: _controller.serverUrl,
        users: users
            .where((u) => u.id != _controller.currentUser.id)
            .toList(growable: false),
      );
      if (result == null) return;
      final Chat chat;
      if (result.type == ChatType.direct) {
        chat = await _controller.createDirectChat(result.memberIds.first);
      } else if (result.type == ChatType.group) {
        chat = await _controller.createGroupChat(result.name, result.memberIds);
      } else {
        chat =
            await _controller.createChannelChat(result.name, result.memberIds);
      }
      if (!mounted) return;
      _openChat(chat);
    } on Object catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось создать чат: $err')),
        );
      }
    }
  }

  Future<void> _chatOptions(Chat chat) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: panel,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(chat.muted
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_off_rounded),
              title: Text(chat.muted ? 'Включить звук' : 'Выключить звук'),
              onTap: () {
                Navigator.pop(sheetContext);
                _controller.toggleMute(chat);
              },
            ),
            ListTile(
              leading: Icon(chat.pinnedToTop
                  ? Icons.push_pin_outlined
                  : Icons.push_pin_rounded),
              title: Text(chat.pinnedToTop ? 'Открепить чат' : 'Закрепить чат'),
              onTap: () {
                Navigator.pop(sheetContext);
                _controller.togglePinTop(chat);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: danger),
              title: const Text('Удалить чат', style: TextStyle(color: danger)),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _controller.deleteChat(chat);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openAccount() {
    final user = _controller.currentUser;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: panel,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  BrenksAvatar(
                    title: user.title,
                    imageUrl: user.avatarUrl,
                    baseUrl: _controller.serverUrl,
                    size: 64,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text('@${user.username}',
                            style: const TextStyle(color: muted)),
                        if (user.email?.isNotEmpty == true)
                          Text(
                            user.email!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: muted, fontSize: 13),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: panelSoft.withValues(alpha: 0.64),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.contrast_rounded, color: accent),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text('Тема',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                    SegmentedButton<ThemeMode>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.dark,
                          icon: Icon(Icons.dark_mode_rounded, size: 18),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          icon: Icon(Icons.light_mode_rounded, size: 18),
                        ),
                      ],
                      selected: {widget.themeMode},
                      onSelectionChanged: (value) {
                        widget.onThemeModeChanged(value.first);
                        Navigator.pop(sheetContext);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: () async {
                  Navigator.pop(sheetContext);
                  await widget.onLogout();
                },
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Выйти'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final chats = query.isEmpty
        ? _controller.chats
        : _controller.chats
            .where((chat) => chat.title.toLowerCase().contains(query))
            .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: InkWell(
            onTap: _openAccount,
            customBorder: const CircleBorder(),
            child: Center(
              child: BrenksAvatar(
                title: _controller.currentUser.title,
                imageUrl: _controller.currentUser.avatarUrl,
                baseUrl: _controller.serverUrl,
                size: 38,
              ),
            ),
          ),
        ),
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Поиск чатов...',
                  border: InputBorder.none,
                  filled: false,
                ),
              )
            : Row(
                children: [
                  const Text('БренксЧат',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(width: 8),
                  _connectionDot(),
                ],
              ),
        actions: [
          IconButton(
            tooltip: _searching ? 'Закрыть поиск' : 'Поиск',
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) _searchController.clear();
            }),
            icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
          ),
          IconButton(
            tooltip: 'Новый чат',
            onPressed: _newChat,
            icon: const Icon(Icons.add_comment_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _controller.loadChats,
        child: _buildBody(chats),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _newChat,
        backgroundColor: accent,
        foregroundColor: const Color(0xFF08131A),
        child: const Icon(Icons.edit_rounded),
      ),
    );
  }

  Widget _connectionDot() {
    final connected = _controller.socketConnected;
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: connected ? const Color(0xFF4AAE8A) : muted,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          connected ? 'онлайн' : 'связь...',
          style: const TextStyle(color: muted, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildBody(List<Chat> chats) {
    if (_controller.loadingChats && _controller.chats.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_controller.chatsError != null && _controller.chats.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          EmptyState(
            icon: Icons.wifi_off_rounded,
            title: 'Не удалось загрузить',
            subtitle: _controller.chatsError!,
          ),
          const SizedBox(height: 12),
          Center(
            child: OutlinedButton(
              onPressed: _controller.loadChats,
              child: const Text('Повторить'),
            ),
          ),
        ],
      );
    }
    if (chats.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 100),
          EmptyState(
            title: 'Чатов пока нет',
            subtitle: 'Создайте новый чат кнопкой в правом нижнем углу.',
          ),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: chats.length,
      itemBuilder: (context, index) {
        final chat = chats[index];
        return ChatTile(
          chat: chat,
          serverUrl: _controller.serverUrl,
          currentUserId: _controller.currentUser.id,
          unread: _controller.unreadFor(chat),
          peerOnline: _controller.isPeerOnline(chat),
          onTap: () => _openChat(chat),
          onLongPress: () => _chatOptions(chat),
        );
      },
    );
  }
}
