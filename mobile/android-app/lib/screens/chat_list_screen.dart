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
import '../widgets/glass.dart';
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
  bool _showOffline = false;
  DateTime? _disconnectedAt;
  int _tabIndex = 1; // 0 = Контакты, 1 = Чаты, 2 = Настройки
  int _filter = 0; // 0 = Все, 1 = Личные, 2 = Группы

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

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: IndexedStack(
          index: _tabIndex,
          children: [
            _contactsTab(isLight),
            _chatTab(isLight),
            _settingsTab(isLight),
          ],
        ),
        bottomNavigationBar: _bottomNav(isLight),
      ),
    );
  }

  Widget _bottomNav(bool isLight) {
    return GlassBar(
      topBorder: true,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              _navItem(0, Icons.person_rounded, 'Контакты', isLight),
              _navItem(1, Icons.chat_bubble_rounded, 'Чаты', isLight),
              _navItem(2, Icons.settings_rounded, 'Настройки', isLight),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, String label, bool isLight) {
    final selected = _tabIndex == index;
    final color = selected ? accent : (isLight ? lightMuted : muted);
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _tabIndex = index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _settingsTab(bool isLight) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        toolbarHeight: 64,
        automaticallyImplyLeading: false,
        flexibleSpace: const GlassBar(bottomBorder: true),
        titleSpacing: 20,
        title: const Text(
          'Настройки',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
      ),
      body: _SettingsView(
        controller: _controller,
        themeMode: widget.themeMode,
        onThemeModeChanged: widget.onThemeModeChanged,
        onLogout: widget.onLogout,
        isLight: isLight,
      ),
    );
  }

  Widget _contactsTab(bool isLight) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        toolbarHeight: 64,
        automaticallyImplyLeading: false,
        flexibleSpace: const GlassBar(bottomBorder: true),
        titleSpacing: 20,
        title: const Text(
          'Контакты',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
      ),
      body: _ContactsView(
        controller: _controller,
        isLight: isLight,
        onOpenChat: _openChat,
      ),
    );
  }

  Widget _chatTab(bool isLight) {
    final chats = _filteredChats();
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        toolbarHeight: 56,
        centerTitle: true,
        titleSpacing: 0,
        automaticallyImplyLeading: false,
        flexibleSpace: const GlassBar(),
        leadingWidth: 84,
        leading: Center(
          child: _pillButton(
            isLight: isLight,
            onTap: () => showAppToast(context, 'Редактирование списка — скоро'),
            child: const Text('Изм.',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
        title: const Text('Чаты',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        actions: [
          _pillButton(
            isLight: isLight,
            onTap: _newChat,
            child: const Icon(Icons.add_rounded, size: 22),
          ),
          const SizedBox(width: 8),
          _pillButton(
            isLight: isLight,
            onTap: _newChat,
            child: const Icon(Icons.edit_square, size: 19),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          _offlineBanner(),
          _searchBar(isLight),
          _filterTabs(isLight),
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

  List<Chat> _filteredChats() {
    final query = _searchController.text.trim().toLowerCase();
    Iterable<Chat> list = _controller.chats;
    if (_filter == 1) {
      list = list.where((c) => c.type == ChatType.direct);
    } else if (_filter == 2) {
      list = list.where(
          (c) => c.type == ChatType.group || c.type == ChatType.channel);
    }
    if (query.isNotEmpty) {
      list = list.where((c) => c.title.toLowerCase().contains(query));
    }
    return list.toList(growable: false);
  }

  Widget _offlineBanner() {
    return AnimatedSize(
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
    );
  }

  Widget _searchBar(bool isLight) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: isLight ? 0.55 : 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withValues(alpha: isLight ? 0.6 : 0.10),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.search_rounded,
                size: 20, color: isLight ? lightMuted : muted),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  isCollapsed: true,
                  hintText: 'Поиск',
                  hintStyle: TextStyle(
                      color: isLight ? lightMuted : muted, fontSize: 15),
                  border: InputBorder.none,
                  filled: false,
                ),
              ),
            ),
            if (_searchController.text.isNotEmpty)
              GestureDetector(
                onTap: () => setState(() => _searchController.clear()),
                child: Icon(Icons.close_rounded,
                    size: 18, color: isLight ? lightMuted : muted),
              ),
          ],
        ),
      ),
    );
  }

  Widget _filterTabs(bool isLight) {
    final groupCount = _controller.chats
        .where((c) => c.type == ChatType.group || c.type == ChatType.channel)
        .length;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(
        children: [
          _filterPill('Все', 0, isLight, null),
          const SizedBox(width: 8),
          _filterPill('Личные', 1, isLight, null),
          const SizedBox(width: 8),
          _filterPill('Группы', 2, isLight, groupCount),
        ],
      ),
    );
  }

  Widget _filterPill(String label, int index, bool isLight, int? count) {
    final selected = _filter == index;
    final bg = selected
        ? accent
        : Colors.white.withValues(alpha: isLight ? 0.55 : 0.07);
    final fg =
        selected ? const Color(0xFF08131A) : (isLight ? lightText : text);
    return GestureDetector(
      onTap: () => setState(() => _filter = index),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha: isLight ? 0.6 : 0.10),
          ),
        ),
        child: Row(
          children: [
            Text(label,
                style: TextStyle(
                    color: fg, fontWeight: FontWeight.w800, fontSize: 14)),
            if (count != null && count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.black.withValues(alpha: 0.18)
                      : (isLight ? lightMuted : muted).withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text('$count',
                    style: TextStyle(
                        color: fg, fontSize: 12, fontWeight: FontWeight.w800)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _pillButton({
    required bool isLight,
    required VoidCallback onTap,
    required Widget child,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        constraints: const BoxConstraints(minWidth: 44),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: isLight ? 0.7 : 0.09),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withValues(alpha: isLight ? 0.6 : 0.10),
          ),
        ),
        child: child,
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
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
      itemCount: chats.length,
      itemBuilder: (context, index) {
        final chat = chats[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GlassCard(
            borderRadius: 20,
            padding: EdgeInsets.zero,
            child: ChatTile(
              chat: chat,
              serverUrl: _controller.serverUrl,
              unread: _controller.unreadFor(chat),
              peerOnline: _controller.isPeerOnline(chat),
              onTap: () => _openChat(chat),
              onLongPress: () => _chatOptions(chat),
            ),
          ),
        );
      },
    );
  }
}

// ─── Вкладка «Настройки» (профиль) ────────────────────────────────────────

class _SettingsView extends StatefulWidget {
  const _SettingsView({
    required this.controller,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.onLogout,
    required this.isLight,
  });

  final MessengerController controller;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final Future<void> Function() onLogout;
  final bool isLight;

  @override
  State<_SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<_SettingsView> {
  bool _uploadingPhoto = false;

  MessengerController get _ctrl => widget.controller;
  bool get _isLight => widget.isLight;

  Color get _textColor => _isLight ? const Color(0xFF17202B) : text;
  Color get _mutedColor => _isLight ? const Color(0xFF637083) : muted;

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
      if (mounted) showAppToast(context, 'Фото обновлено');
    } on Object catch (e) {
      if (mounted) showAppToast(context, 'Ошибка: $e', error: true);
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _removePhoto() async {
    try {
      await _ctrl.api.removeAvatar();
      if (mounted) showAppToast(context, 'Фото удалено');
    } on Object catch (e) {
      if (mounted) showAppToast(context, 'Ошибка: $e', error: true);
    }
  }

  void _copyUsername() {
    Clipboard.setData(ClipboardData(text: '@${_ctrl.currentUser.username}'));
    showAppToast(context, 'Имя скопировано');
  }

  void _copyProfileLink() {
    final link = '${_ctrl.serverUrl}/u/${_ctrl.currentUser.username}';
    Clipboard.setData(ClipboardData(text: link));
    showAppToast(context, 'Ссылка скопирована');
  }

  @override
  Widget build(BuildContext context) {
    final user = _ctrl.currentUser;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
                    // Hero card: avatar + name + status
                    GlassCard(
                      borderRadius: 26,
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
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
                                color: _isLight ? Colors.white : bg,
                              ),
                              child: BrenksAvatar(
                                title: user.title,
                                imageUrl: user.avatarUrl,
                                baseUrl: _ctrl.serverUrl,
                                size: 88,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            user.title,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w900,
                              color: _textColor,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '@${user.username}',
                            style: TextStyle(color: _mutedColor, fontSize: 15),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4AAE8A).withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 7,
                                  height: 7,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Color(0xFF4AAE8A),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'в сети',
                                  style: TextStyle(
                                    color: Color(0xFF4AAE8A),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Quick action buttons
                    Row(
                      children: [
                        _actionBtn(
                          icon: Icons.link_rounded,
                          label: 'Ссылка',
                          onTap: _copyProfileLink,
                        ),
                        const SizedBox(width: 10),
                        _actionBtn(
                          icon: Icons.ios_share_rounded,
                          label: 'Поделиться',
                          onTap: _copyProfileLink,
                        ),
                        const SizedBox(width: 10),
                        _actionBtn(
                          icon: Icons.alternate_email_rounded,
                          label: 'Юзернейм',
                          onTap: _copyUsername,
                        ),
                      ],
                    ),
                    if (user.email?.isNotEmpty == true) ...[
                      const SizedBox(height: 20),
                      _sectionLabel('ИНФОРМАЦИЯ'),
                      const SizedBox(height: 8),
                      GlassCard(
                        borderRadius: 18,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        child: Row(
                          children: [
                            _miniIcon(Icons.mail_outline_rounded),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Почта для входа',
                                      style: TextStyle(
                                          color: _mutedColor, fontSize: 12)),
                                  const SizedBox(height: 2),
                                  Text(
                                    user.email!,
                                    style: TextStyle(
                                      color: _textColor,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    _sectionLabel('ФОТОГРАФИЯ'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _photoBtn(
                            icon: Icons.camera_alt_rounded,
                            label: 'Сменить',
                            onTap: _uploadingPhoto ? null : _changePhoto,
                            loading: _uploadingPhoto,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _photoBtn(
                            icon: Icons.delete_outline_rounded,
                            label: 'Убрать',
                            onTap: _removePhoto,
                            danger: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _sectionLabel('ОФОРМЛЕНИЕ'),
                    const SizedBox(height: 8),
                    GlassCard(
                      borderRadius: 18,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          _miniIcon(Icons.contrast_rounded),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text('Тема оформления',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: _textColor)),
                          ),
                          SegmentedButton<ThemeMode>(
                            showSelectedIcon: false,
                            style: ButtonStyle(
                              visualDensity: VisualDensity.compact,
                            ),
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
                            onSelectionChanged: (v) =>
                                widget.onThemeModeChanged(v.first),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: widget.onLogout,
                      icon: const Icon(Icons.logout_rounded, color: danger),
                      label: const Text('Выйти из аккаунта',
                          style: TextStyle(color: danger)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: danger.withValues(alpha: 0.6)),
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Text(
        label,
        style: TextStyle(
          color: _mutedColor,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _miniIcon(IconData icon) {
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: accent, size: 20),
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
        behavior: HitTestBehavior.opaque,
        child: GlassCard(
          borderRadius: 18,
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Icon(icon, color: accent, size: 24),
              const SizedBox(height: 7),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _photoBtn({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool danger = false,
    bool loading = false,
  }) {
    final color = danger ? const Color(0xFFFF7474) : accent;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: GlassCard(
        borderRadius: 16,
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            else
              Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: danger ? color : _textColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Вкладка «Контакты» ───────────────────────────────────────────────────

class _ContactsView extends StatefulWidget {
  const _ContactsView({
    required this.controller,
    required this.isLight,
    required this.onOpenChat,
  });

  final MessengerController controller;
  final bool isLight;
  final void Function(Chat) onOpenChat;

  @override
  State<_ContactsView> createState() => _ContactsViewState();
}

class _ContactsViewState extends State<_ContactsView> {
  List<DirectoryUser>? _users;
  String? _error;
  bool _creating = false;

  MessengerController get _ctrl => widget.controller;
  Color get _muted => widget.isLight ? lightMuted : muted;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final users = await _ctrl.api.fetchUserDirectory();
      if (!mounted) return;
      setState(() {
        _users = users
            .where((u) => u.id != _ctrl.currentUser.id)
            .toList(growable: false);
        _error = null;
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _startChat(DirectoryUser user) async {
    if (_creating) return;
    setState(() => _creating = true);
    try {
      final chat = await _ctrl.createDirectChat(user.id);
      if (mounted) widget.onOpenChat(chat);
    } on Object catch (e) {
      if (mounted) showAppToast(context, 'Ошибка: $e', error: true);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            const SizedBox(height: 120),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Не удалось загрузить контакты\n$_error',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _muted),
                ),
              ),
            ),
          ],
        ),
      );
    }
    final users = _users;
    if (users == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (users.isEmpty) {
      return Center(child: Text('Контактов нет', style: TextStyle(color: _muted)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: users.length,
        itemBuilder: (context, index) {
          final user = users[index];
          return ListTile(
            leading: BrenksAvatar(
              title: user.title,
              imageUrl: user.avatarUrl,
              baseUrl: _ctrl.serverUrl,
              size: 46,
            ),
            title: Text(user.title,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle:
                Text('@${user.username}', style: TextStyle(color: _muted)),
            trailing:
                const Icon(Icons.chat_bubble_outline_rounded, color: accent, size: 20),
            onTap: () => _startChat(user),
          );
        },
      ),
    );
  }
}
