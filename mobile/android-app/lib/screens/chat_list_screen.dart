import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  final _searchFocus = FocusNode();
  bool _showOffline = false;
  DateTime? _disconnectedAt;
  int _tabIndex = 1; // 0 = Контакты, 1 = Чаты, 2 = Настройки
  bool _editMode = false;
  bool _searchVisible = false;
  List<String> _manualOrder = const [];

  MessengerController get _controller => widget.controller;

  void _toggleSearch() {
    final show = !_searchVisible;
    setState(() {
      _tabIndex = 1;
      _searchVisible = show;
      if (!show) _searchController.clear();
    });
    if (show) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
    } else {
      _searchFocus.unfocus();
    }
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    _loadOrder();
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _loadOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('chat_manual_order');
    if (raw != null && mounted) setState(() => _manualOrder = raw);
  }

  Future<void> _saveOrder(List<String> order) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('chat_manual_order', order);
  }

  /// Применяет ручной порядок: вручную упорядоченные чаты идут первыми,
  /// остальные — следом в исходном порядке (стабильно).
  List<Chat> _applyManualOrder(List<Chat> chats) {
    if (_manualOrder.isEmpty) return chats;
    final byId = {for (final c in chats) c.id: c};
    final used = <String>{};
    final result = <Chat>[];
    for (final id in _manualOrder) {
      final c = byId[id];
      if (c != null) {
        result.add(c);
        used.add(id);
      }
    }
    for (final c in chats) {
      if (!used.contains(c.id)) result.add(c);
    }
    return result;
  }

  void _onReorder(List<Chat> display, int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final ids = display.map((c) => c.id).toList();
    final moved = ids.removeAt(oldIndex);
    ids.insert(newIndex, moved);
    setState(() => _manualOrder = ids);
    _saveOrder(ids);
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
      // Cupertino-роут даёт свайп-назад (edge swipe) и на Android.
      CupertinoPageRoute(
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
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
        child: Row(
          children: [
            Expanded(
              child: GlassPanel(
                borderRadius: 28,
                shadow: true,
                child: SizedBox(
                  height: 58,
                  child: Stack(
                    children: [
                      // Скользящий индикатор из настоящего матового стекла
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: AnimatedAlign(
                            alignment: Alignment((_tabIndex / 2) * 2 - 1, 0),
                            duration: const Duration(milliseconds: 340),
                            curve: Curves.easeOutCubic,
                            child: FractionallySizedBox(
                              widthFactor: 1 / 3,
                              heightFactor: 1,
                              child: GlassPanel(
                                borderRadius: 20,
                                blur: 14,
                                strength: 1.6,
                                shadow: true,
                                child: const SizedBox.expand(),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          _NavItem(
                            icon: Icons.person_rounded,
                            iconOutline: Icons.person_outline_rounded,
                            label: 'Контакты',
                            selected: _tabIndex == 0,
                            isLight: isLight,
                            onTap: () => setState(() => _tabIndex = 0),
                          ),
                          _NavItem(
                            icon: Icons.chat_bubble_rounded,
                            iconOutline: Icons.chat_bubble_outline_rounded,
                            label: 'Чаты',
                            selected: _tabIndex == 1,
                            isLight: isLight,
                            onTap: () => setState(() => _tabIndex = 1),
                          ),
                          _NavItem(
                            icon: Icons.settings_rounded,
                            iconOutline: Icons.settings_outlined,
                            label: 'Настройки',
                            selected: _tabIndex == 2,
                            isLight: isLight,
                            onTap: () => setState(() => _tabIndex = 2),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _TapBounce(
              onTap: _toggleSearch,
              child: GlassPanel(
                borderRadius: 28,
                shadow: true,
                child: SizedBox(
                  width: 58,
                  height: 58,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, animation) => ScaleTransition(
                      scale: animation,
                      child: FadeTransition(opacity: animation, child: child),
                    ),
                    child: Icon(
                      _searchVisible ? Icons.close_rounded : Icons.search_rounded,
                      key: ValueKey(_searchVisible),
                      color: _searchVisible ? accent : (isLight ? lightText : text),
                      size: 25,
                    ),
                  ),
                ),
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
        leadingWidth: 96,
        leading: Center(
          child: _PillButton(
            isLight: isLight,
            onTap: () => setState(() => _editMode = !_editMode),
            child: Text(_editMode ? 'Готово' : 'Изм.',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: _editMode ? accent : (isLight ? lightText : text))),
          ),
        ),
        title: const Text('Чаты',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        actions: [
          _PillButton(
            isLight: isLight,
            onTap: _newChat,
            child: const Icon(Icons.add_rounded, size: 24),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          _offlineBanner(),
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: (_searchVisible && !_editMode)
                ? _searchBar(isLight)
                : const SizedBox(width: double.infinity),
          ),
          Expanded(
            child: _editMode
                ? _buildEditList()
                : RefreshIndicator(
                    onRefresh: _controller.loadChats,
                    child: _buildBody(chats),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditList() {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final handleColor = isLight ? lightMuted : muted;
    final chats = _applyManualOrder(_controller.chats);
    if (chats.isEmpty) {
      return const Center(
        child: EmptyState(
          title: 'Чатов пока нет',
          subtitle: 'Создайте чат кнопкой «+».',
        ),
      );
    }
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
      itemCount: chats.length,
      // ignore: deprecated_member_use
      onReorder: (oldIndex, newIndex) => _onReorder(chats, oldIndex, newIndex),
      itemBuilder: (context, index) {
        final chat = chats[index];
        return Padding(
          key: ValueKey(chat.id),
          padding: const EdgeInsets.only(bottom: 8),
          child: GlassCard(
            borderRadius: 20,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                Expanded(
                  child: ChatTile(
                    chat: chat,
                    serverUrl: _controller.serverUrl,
                    unread: _controller.unreadFor(chat),
                    peerOnline: _controller.isPeerOnline(chat),
                    onTap: () {},
                    onLongPress: () {},
                  ),
                ),
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(Icons.drag_handle_rounded, color: handleColor),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Chat> _filteredChats() {
    final query = _searchController.text.trim().toLowerCase();
    Iterable<Chat> list = _controller.chats;
    if (query.isNotEmpty) {
      list = list.where((c) => c.title.toLowerCase().contains(query));
    }
    return _applyManualOrder(list.toList(growable: false));
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
                focusNode: _searchFocus,
                onChanged: (_) => setState(() {}),
                textAlignVertical: TextAlignVertical.center,
                style: const TextStyle(fontSize: 15),
                cursorColor: accent,
                decoration: InputDecoration(
                  isCollapsed: true,
                  contentPadding: EdgeInsets.zero,
                  hintText: 'Поиск',
                  hintStyle: TextStyle(
                      color: isLight ? lightMuted : muted, fontSize: 15),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
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

// ─── Элемент нижней навигации с анимацией иконки при выборе ────────────────

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.iconOutline,
    required this.label,
    required this.selected,
    required this.isLight,
    required this.onTap,
  });

  final IconData icon; // заполненная (выбрано)
  final IconData iconOutline; // контурная (не выбрано)
  final String label;
  final bool selected;
  final bool isLight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color =
        selected ? (isLight ? lightText : text) : (isLight ? lightMuted : muted);
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Плавно: иконка чуть подрастает + контур мягко перетекает в заливку.
            AnimatedScale(
              scale: selected ? 1.14 : 1.0,
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              child: AnimatedSlide(
                offset: selected ? const Offset(0, -0.05) : Offset.zero,
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, animation) =>
                      FadeTransition(opacity: animation, child: child),
                  child: Icon(
                    selected ? icon : iconOutline,
                    key: ValueKey(selected),
                    color: color,
                    size: 24,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 260),
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Обёртка: «поп» любого виджета при нажатии ────────────────────────────

class _TapBounce extends StatefulWidget {
  const _TapBounce({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_TapBounce> createState() => _TapBounceState();
}

class _TapBounceState extends State<_TapBounce>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: 1.18)
          .chain(CurveTween(curve: Curves.easeOut)),
      weight: 45,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 1.18, end: 1.0)
          .chain(CurveTween(curve: Curves.easeIn)),
      weight: 55,
    ),
  ]).animate(_c);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _handleTap() {
    _c.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handleTap,
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}

// ─── Пилюля-кнопка шапки с «попом» при нажатии ────────────────────────────

class _PillButton extends StatefulWidget {
  const _PillButton({
    required this.isLight,
    required this.onTap,
    required this.child,
  });

  final bool isLight;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<_PillButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _tap = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  late final Animation<double> _bounce = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: 1.14)
          .chain(CurveTween(curve: Curves.easeOut)),
      weight: 45,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 1.14, end: 1.0)
          .chain(CurveTween(curve: Curves.easeIn)),
      weight: 55,
    ),
  ]).animate(_tap);

  @override
  void dispose() {
    _tap.dispose();
    super.dispose();
  }

  void _handleTap() {
    _tap.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: ScaleTransition(
        scale: _bounce,
        child: Container(
          height: 36,
          constraints: const BoxConstraints(minWidth: 44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: widget.isLight ? 0.7 : 0.09),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withValues(alpha: widget.isLight ? 0.6 : 0.10),
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
