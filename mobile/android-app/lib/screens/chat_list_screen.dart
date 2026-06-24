import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  bool _showOffline = false;
  DateTime? _disconnectedAt;

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
    if (!mounted) return;
    final connected = _controller.socketConnected;
    if (!connected) {
      _disconnectedAt ??= DateTime.now();
      final secs = DateTime.now().difference(_disconnectedAt!).inSeconds;
      setState(() => _showOffline = secs >= 3);
    } else {
      _disconnectedAt = null;
      setState(() => _showOffline = false);
    }
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
    final isLight = Theme.of(context).brightness == Brightness.light;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: isLight ? Colors.white : panel,
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
    final isLight = Theme.of(context).brightness == Brightness.light;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: isLight ? Colors.white : panel,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => _ProfileSheet(
        controller: _controller,
        themeMode: widget.themeMode,
        onThemeModeChanged: (mode) {
          widget.onThemeModeChanged(mode);
          Navigator.pop(sheetContext);
        },
        onLogout: () async {
          Navigator.pop(sheetContext);
          await widget.onLogout();
        },
        isLight: isLight,
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
            : const SizedBox.shrink(),
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
      body: Column(
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOutCubic,
            child: _showOffline
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 16),
                    color: const Color(0xFFFF9800).withValues(alpha: 0.14),
                    child: Row(
                      children: [
                        const Icon(Icons.wifi_off_rounded,
                            color: Color(0xFFFF9800), size: 16),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Нет подключения к серверу — сообщения не доставляются',
                            style: TextStyle(
                              color: Color(0xFFFF9800),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: _controller.reconnect,
                          child: const Text(
                            'Повторить',
                            style: TextStyle(
                              color: Color(0xFFFF9800),
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _controller.loadChats,
              child: _buildBody(chats),
            ),
          ),
        ],
      ),
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
          unread: _controller.unreadFor(chat),
          peerOnline: _controller.isPeerOnline(chat),
          onTap: () => _openChat(chat),
          onLongPress: () => _chatOptions(chat),
        );
      },
    );
  }
}

// ─── Профиль-шит (как в веб-версии) ───────────────────────────────────────

class _ProfileSheet extends StatefulWidget {
  const _ProfileSheet({
    required this.controller,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.onLogout,
    required this.isLight,
  });

  final MessengerController controller;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final VoidCallback onLogout;
  final bool isLight;

  @override
  State<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<_ProfileSheet> {
  bool _uploadingPhoto = false;

  MessengerController get _ctrl => widget.controller;
  bool get _isLight => widget.isLight;

  Color get _textColor => _isLight ? const Color(0xFF17202B) : text;
  Color get _mutedColor => _isLight ? const Color(0xFF637083) : muted;
  Color get _cardBg => _isLight ? const Color(0xFFF3F5F8) : panelSoft;
  Color get _cardBorder => _isLight ? const Color(0xFFD4DAE3) : border;

  Future<void> _changePhoto() async {
    setState(() => _uploadingPhoto = true);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        withData: true,
      );
      final file = result?.files.single;
      if (file == null) return;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) return;
      final mime = file.extension?.toLowerCase() == 'png' ? 'image/png' : 'image/jpeg';
      final dataUrl = 'data:$mime;base64,${base64Encode(bytes)}';
      await _ctrl.api.updateProfile(avatarDataUrl: dataUrl);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Фото обновлено')),
        );
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _removePhoto() async {
    try {
      await _ctrl.api.removeAvatar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Фото удалено')),
        );
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }

  void _copyUsername() {
    Clipboard.setData(ClipboardData(text: '@${_ctrl.currentUser.username}'));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Юзернейм скопирован')),
    );
  }

  void _copyProfileLink() {
    final link = '${_ctrl.serverUrl}/u/${_ctrl.currentUser.username}';
    Clipboard.setData(ClipboardData(text: link));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ссылка скопирована')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _ctrl.currentUser;
    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      maxChildSize: 0.96,
      minChildSize: 0.4,
      expand: false,
      builder: (_, scrollCtrl) => SingleChildScrollView(
        controller: scrollCtrl,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title
              Text(
                'Мой профиль',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: _textColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Аккаунт, приватность и уведомления',
                style: TextStyle(color: _mutedColor, fontSize: 13),
              ),
              const SizedBox(height: 20),
              // Avatar + name
              Center(
                child: Column(
                  children: [
                    BrenksAvatar(
                      title: user.title,
                      imageUrl: user.avatarUrl,
                      baseUrl: _ctrl.serverUrl,
                      size: 84,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      user.title,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: _textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@${user.username}',
                      style: TextStyle(color: _mutedColor, fontSize: 15),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // 3 action buttons
              Row(
                children: [
                  _actionBtn(
                    icon: Icons.link_rounded,
                    label: 'Ссылка\nпрофиля',
                    onTap: _copyProfileLink,
                  ),
                  const SizedBox(width: 10),
                  _actionBtn(
                    icon: Icons.share_rounded,
                    label: 'Поде-\nлиться',
                    onTap: _copyProfileLink,
                  ),
                  const SizedBox(width: 10),
                  _actionBtn(
                    icon: Icons.alternate_email_rounded,
                    label: '@${user.username}',
                    onTap: _copyUsername,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Email
              if (user.email?.isNotEmpty == true)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: _cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _cardBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.email_rounded, color: accent, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Почта для входа',
                                style: TextStyle(color: _mutedColor, fontSize: 12)),
                            const SizedBox(height: 2),
                            Text(user.email!,
                                style: TextStyle(color: _textColor, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 14),
              // Photo buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _uploadingPhoto ? null : _changePhoto,
                      icon: _uploadingPhoto
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.camera_alt_rounded, size: 18),
                      label: const Text('Сменить фото'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _removePhoto,
                      icon: const Icon(Icons.no_photography_rounded, size: 18, color: danger),
                      label: const Text('Убрать фото',
                          style: TextStyle(color: danger)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: danger),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Theme toggle
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _cardBorder),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.contrast_rounded, color: accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Тема',
                          style: TextStyle(fontWeight: FontWeight.w800, color: _textColor)),
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
                      onSelectionChanged: (v) => widget.onThemeModeChanged(v.first),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // Logout
              FilledButton.tonalIcon(
                onPressed: widget.onLogout,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Закрыть'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: widget.onLogout,
                icon: const Icon(Icons.exit_to_app_rounded, color: danger),
                label: const Text('Выйти из аккаунта', style: TextStyle(color: danger)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: danger),
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _cardBorder),
          ),
          child: Column(
            children: [
              Icon(icon, color: accent, size: 22),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _textColor,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
