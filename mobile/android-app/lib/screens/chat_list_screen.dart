import 'dart:convert';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../format.dart';
import '../models.dart';
import '../services/folders_store.dart';
import '../services/messenger_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/brenks_avatar.dart';
import '../widgets/chat_tile.dart';
import '../widgets/empty_state.dart';
import '../widgets/glass.dart';
import '../widgets/ios_context_menu.dart';
import '../widgets/night_mode_switch.dart';
import '../widgets/new_chat_sheet.dart';
import 'chat_profile_screen.dart';
import 'chat_screen.dart';
import 'folders_screen.dart';

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

class _ChatListScreenState extends State<ChatListScreen>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  late final AnimationController _searchReveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  );
  bool _showOffline = false;
  DateTime? _disconnectedAt;
  int _tabIndex = 0; // 0 = Чаты, 1 = Настройки
  bool _editMode = false;
  bool _searchVisible = false;
  List<String> _manualOrder = const [];
  List<ChatFolder> _folders = const [];
  int _activeFolder = 0; // 0 = «Все»

  // Скользящий индикатор активной папки: ключи сегментов + измеренные позиция
  // и ширина (в координатах панели вкладок).
  final GlobalKey _folderStackKey = GlobalKey();
  final Map<int, GlobalKey> _folderKeys = {};
  double _indLeft = 0;
  double _indWidth = 0;
  bool _indReady = false;

  MessengerController get _controller => widget.controller;

  Future<void> _loadFolders() async {
    final folders = await FoldersStore.load();
    if (mounted) {
      setState(() {
        _folders = folders;
        if (_activeFolder > folders.length) _activeFolder = 0;
      });
    }
  }

  Future<void> _openFolders() async {
    await Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => FoldersScreen(controller: _controller),
      ),
    );
    await _loadFolders();
  }

  void _toggleSearch() {
    if (_searchVisible) {
      _closeSearch();
      return;
    }
    setState(() {
      _tabIndex = 0;
      _searchVisible = true;
    });
    _searchReveal.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _closeSearch() {
    if (!_searchVisible) return;
    setState(() {
      _searchVisible = false;
      _searchController.clear();
    });
    _searchReveal.reverse();
    _searchFocus.unfocus();
  }

  /// Закрывает поиск, если он открыт и в строке ничего не введено.
  void _maybeCloseEmptySearch() {
    if (_searchVisible && _searchController.text.trim().isEmpty) {
      _closeSearch();
    }
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    _loadOrder();
    _loadFolders();
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    _searchReveal.dispose();
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
    _maybeCloseEmptySearch();
    Navigator.of(context).push(
      // Cupertino-роут даёт свайп-назад (edge swipe) и на Android.
      CupertinoPageRoute(
        builder: (_) => ChatScreen(controller: _controller, chatId: chat.id),
      ),
    );
  }

  Future<void> _newChat() async {
    _maybeCloseEmptySearch();
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
    final screenW = MediaQuery.of(context).size.width;
    final width = (screenW - 40).clamp(240.0, 360.0);
    // Окно-предпросмотр крупнее меню (~+40%), но не шире экрана.
    final previewWidth = math.min(width * 1.4, screenW - 32);
    final unread = _controller.unreadFor(chat);

    await showIosContextMenu(
      context: context,
      preview: _chatPreview(chat, previewWidth),
      menuWidth: width,
      actions: [
        if (unread > 0)
          IosMenuAction(
            icon: Icons.mark_chat_read_rounded,
            label: 'Отметить прочитанным',
            onTap: () => _controller.markChatRead(chat.id),
          ),
        IosMenuAction(
          icon: chat.pinnedToTop
              ? Icons.push_pin_outlined
              : Icons.push_pin_rounded,
          label: chat.pinnedToTop ? 'Открепить' : 'Закрепить',
          onTap: () => _controller.togglePinTop(chat),
        ),
        IosMenuAction(
          icon: chat.muted
              ? Icons.notifications_active_rounded
              : Icons.notifications_off_rounded,
          label: chat.muted ? 'Включить уведомления' : 'Выключить уведомления',
          onTap: () => _controller.toggleMute(chat),
        ),
        IosMenuAction(
          icon: Icons.create_new_folder_outlined,
          label: 'Добавить в папку',
          onTap: () => _addChatToFolderSheet(chat),
        ),
        IosMenuAction(
          icon: Icons.delete_outline_rounded,
          label: 'Удалить',
          danger: true,
          dividerBefore: true,
          onTap: () => _controller.deleteChat(chat),
        ),
      ],
    );
  }

  /// Закрывает меню-предпросмотр и открывает профиль собеседника.
  void _openProfileFromMenu(Chat chat) {
    Navigator.of(context, rootNavigator: true).pop();
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) =>
            ChatProfileScreen(controller: _controller, chatId: chat.id),
      ),
    );
  }

  /// Предпросмотр окна чата: шапка (имя + статус) и последнее сообщение.
  Widget _chatPreview(Chat chat, double width) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final online = _controller.isPeerOnline(chat);
    final last = chat.lastMessage;
    final ownLast =
        last != null && last.senderId == _controller.currentUser.id;
    final headerBg =
        isLight ? const Color(0xFFF4F2EC) : const Color(0xFF1A1C20);
    final bodyBg = isLight ? const Color(0xFFECE9E1) : chatBg;
    final statusColor =
        online ? const Color(0xFF4AAE8A) : (isLight ? lightMuted : muted);

    return Container(
      width: width,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.32),
              blurRadius: 24,
              offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Шапка как в окне чата — тап открывает профиль собеседника.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openProfileFromMenu(chat),
            child: Container(
            color: headerBg,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Stack(
                  children: [
                    BrenksAvatar(
                      title: chat.title,
                      imageUrl: _controller.displayAvatar(chat),
                      baseUrl: _controller.serverUrl,
                      size: 46,
                    ),
                    if (online)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 13,
                          height: 13,
                          decoration: BoxDecoration(
                            color: const Color(0xFF4AAE8A),
                            shape: BoxShape.circle,
                            border: Border.all(color: headerBg, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        chat.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        online ? 'в сети' : chatSubtitle(chat),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: statusColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ),
          // Лента: последние сообщения чата (подгружаем при открытии меню).
          SizedBox(
            height: 220,
            width: double.infinity,
            child: Container(
              color: bodyBg,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: FutureBuilder<List<Message>>(
                future: _controller.api.fetchMessages(chat.id),
                builder: (ctx, snap) {
                  final myId = _controller.currentUser.id;
                  final rows = <Widget>[];
                  if (snap.hasData && snap.data!.isNotEmpty) {
                    final all = snap.data!;
                    final tail =
                        all.length > 50 ? all.sublist(all.length - 50) : all;
                    for (final m in tail) {
                      rows.add(_previewRow(messagePreview(m),
                          m.senderId == myId, isLight, width));
                    }
                  } else if (last != null) {
                    // Пока грузится (или при ошибке) — последнее сообщение.
                    rows.add(_previewRow(
                        lastMessageLabel(last.text), ownLast, isLight, width));
                  }
                  if (rows.isEmpty) {
                    return Center(
                      child: Text('Нет сообщений',
                          style: TextStyle(
                              color: isLight ? lightMuted : muted,
                              fontSize: 13)),
                    );
                  }
                  return SingleChildScrollView(
                    reverse: true,
                    physics: const ClampingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: rows,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewRow(String label, bool own, bool isLight, double maxW) {
    final ownBg = isLight ? const Color(0xFFF0E7D6) : const Color(0xFF34312A);
    final otherBg = isLight ? Colors.white : const Color(0xFF34373E);
    final textColor = isLight ? lightText : text;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Align(
        alignment: own ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW * 0.74),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              color: own ? ownBg : otherBg,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(13),
                topRight: const Radius.circular(13),
                bottomLeft: Radius.circular(own ? 13 : 4),
                bottomRight: Radius.circular(own ? 4 : 13),
              ),
              border: Border.all(
                  color: own
                      ? accent.withValues(alpha: 0.18)
                      : Colors.white.withValues(alpha: 0.06)),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: textColor, fontSize: 13.5),
            ),
          ),
        ),
      ),
    );
  }

  /// Лист выбора ручных папок: галочкой включаем/убираем чат из папки.
  Future<void> _addChatToFolderSheet(Chat chat) async {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final manual =
        _folders.where((f) => f.filterType == FolderFilter.manual).toList();
    if (manual.isEmpty) {
      showAppToast(context, 'Сначала создайте папку в Настройках');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: isLight ? Colors.white : panel,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: StatefulBuilder(
          builder: (_, setSheet) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Папки для «${chat.title}»',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ),
              ),
              for (final f in manual)
                ListTile(
                  leading: Icon(
                    f.chatIds.contains(chat.id)
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: f.chatIds.contains(chat.id)
                        ? accent
                        : (isLight ? lightMuted : muted),
                  ),
                  title: Text(f.name),
                  onTap: () async {
                    setSheet(() {
                      if (f.chatIds.contains(chat.id)) {
                        f.chatIds.remove(chat.id);
                      } else {
                        f.chatIds.add(chat.id);
                      }
                    });
                    await FoldersStore.save(_folders);
                    if (mounted) setState(() {});
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final canExit = !_searchVisible && _tabIndex == 0 && _activeFolder == 0;
    return PopScope(
      canPop: canExit,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        setState(() {
          if (_searchVisible) {
            _searchVisible = false;
            _searchController.clear();
            _searchReveal.reverse();
          } else if (_tabIndex != 0) {
            _tabIndex = 0;
          } else if (_activeFolder != 0) {
            _activeFolder = 0;
          }
        });
      },
      child: GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: IndexedStack(
          index: _tabIndex,
          children: [
            _chatTab(isLight),
            _settingsTab(isLight),
          ],
        ),
        bottomNavigationBar: _bottomNav(isLight),
      ),
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
                            alignment: Alignment(_tabIndex * 2 - 1, 0),
                            duration: const Duration(milliseconds: 340),
                            curve: Curves.easeOutCubic,
                            child: FractionallySizedBox(
                              widthFactor: 1 / 2,
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
                            icon: Icons.chat_bubble_rounded,
                            iconOutline: Icons.chat_bubble_outline_rounded,
                            label: 'Чаты',
                            selected: _tabIndex == 0,
                            isLight: isLight,
                            effect: _NavEffect.bounce,
                            onTap: () {
                              _maybeCloseEmptySearch();
                              setState(() => _tabIndex = 0);
                            },
                          ),
                          _NavItem(
                            icon: Icons.settings_rounded,
                            iconOutline: Icons.settings_outlined,
                            label: 'Настройки',
                            selected: _tabIndex == 1,
                            isLight: isLight,
                            effect: _NavEffect.spin,
                            onTap: () {
                              _maybeCloseEmptySearch();
                              setState(() => _tabIndex = 1);
                            },
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
        onManageFolders: _openFolders,
        isLight: isLight,
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
            onTap: () {
              if (!_editMode && _searchVisible) {
                _searchVisible = false;
                _searchController.clear();
                _searchReveal.value = 0;
                _searchFocus.unfocus();
              }
              setState(() => _editMode = !_editMode);
            },
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
          if (!_editMode)
            SizeTransition(
              alignment: Alignment.topCenter,
              sizeFactor: CurvedAnimation(
                parent: _searchReveal,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              ),
              child: FadeTransition(
                opacity: CurvedAnimation(
                  parent: _searchReveal,
                  curve: const Interval(0.2, 1, curve: Curves.easeOut),
                ),
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, -0.35),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                    parent: _searchReveal,
                    curve: Curves.easeOutCubic,
                  )),
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.94, end: 1.0).animate(
                      CurvedAnimation(
                          parent: _searchReveal, curve: Curves.easeOutCubic),
                    ),
                    alignment: Alignment.topCenter,
                    child: _searchBar(isLight),
                  ),
                ),
              ),
            ),
          Expanded(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              // Если строка поиска пустая — любое касание (чат, кнопка, пустое
              // место) закрывает поиск. Событие не поглощается, так что чат/
              // кнопка всё равно срабатывают.
              onPointerDown: (_) => _maybeCloseEmptySearch(),
              child: Column(
                children: [
                  if (!_editMode && _folders.isNotEmpty) _folderTabs(isLight),
                  Expanded(
                    child: _editMode
                        ? _buildEditList()
                        : GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            // Тап по пустому месту закрывает поиск (при любом
                            // тексте); по плитке чата — открывает чат.
                            onTap: () {
                              if (_searchVisible) _closeSearch();
                            },
                            // Свайп влево/вправо переключает папки.
                            onHorizontalDragEnd: _folders.isEmpty
                                ? null
                                : (details) {
                                    final v = details.primaryVelocity ?? 0;
                                    if (v < -250) {
                                      setState(() => _activeFolder =
                                          (_activeFolder + 1)
                                              .clamp(0, _folders.length));
                                    } else if (v > 250) {
                                      setState(() => _activeFolder =
                                          (_activeFolder - 1)
                                              .clamp(0, _folders.length));
                                    }
                                  },
                            child: RefreshIndicator(
                              onRefresh: _controller.loadChats,
                              child: _buildBody(chats),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _folderTabs(bool isLight) {
    final names = ['Все', ..._folders.map((f) => f.name)];
    // Измеряем положение активного сегмента после кадра — стеклянная «пилюля»
    // плавно переезжает к нему (AnimatedPositioned).
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _measureFolderIndicator());
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: GlassPanel(
          borderRadius: 22,
          shadow: true,
          padding: const EdgeInsets.all(5),
          child: Stack(
            key: _folderStackKey,
            children: [
              // Скользящая матовая «пилюля» под активной папкой.
              if (_indReady)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  left: _indLeft,
                  top: 0,
                  bottom: 0,
                  width: _indWidth,
                  child: const GlassPanel(
                    borderRadius: 16,
                    blur: 14,
                    strength: 1.6,
                    shadow: true,
                    child: SizedBox.expand(),
                  ),
                ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < names.length; i++)
                    KeyedSubtree(
                      key: _folderKeys[i] ??= GlobalKey(),
                      child: _folderTab(names[i], i, isLight),
                    ),
                  _folderFilterButton(isLight),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Меряет положение/ширину активного сегмента относительно панели и двигает
  /// туда скользящий индикатор. Вызывается после кадра; setState — только при
  /// реальном изменении, чтобы не зациклиться.
  void _measureFolderIndicator() {
    final segCtx = _folderKeys[_activeFolder]?.currentContext;
    final stackCtx = _folderStackKey.currentContext;
    if (segCtx == null || stackCtx == null) return;
    final seg = segCtx.findRenderObject() as RenderBox?;
    final stack = stackCtx.findRenderObject() as RenderBox?;
    if (seg == null || stack == null || !seg.hasSize || !stack.hasSize) return;
    final left = seg.localToGlobal(Offset.zero, ancestor: stack).dx;
    final width = seg.size.width;
    if (_indReady &&
        (left - _indLeft).abs() < 0.5 &&
        (width - _indWidth).abs() < 0.5) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _indLeft = left;
      _indWidth = width;
      _indReady = true;
    });
  }

  Widget _folderFilterButton(bool isLight) {
    return GestureDetector(
      onTap: _openFolders,
      child: SizedBox(
        height: 36,
        width: 42,
        child: Center(
          child: Icon(Icons.tune_rounded,
              size: 18, color: isLight ? lightMuted : muted),
        ),
      ),
    );
  }

  /// Чаты, попадающие в папку (0 = «Все»).
  Iterable<Chat> _chatsInFolder(int index) {
    Iterable<Chat> list = _controller.chats;
    if (index > 0 && index <= _folders.length) {
      final folder = _folders[index - 1];
      switch (folder.filterType) {
        case FolderFilter.direct:
          list = list.where((c) => c.type == ChatType.direct);
        case FolderFilter.groups:
          list = list.where((c) =>
              c.type == ChatType.group || c.type == ChatType.channel);
        default:
          final ids = folder.chatIds.toSet();
          list = list.where((c) => ids.contains(c.id));
      }
    }
    return list;
  }

  /// Количество чатов с непрочитанными сообщениями в папке.
  int _folderUnread(int index) =>
      _chatsInFolder(index).where((c) => _controller.unreadFor(c) > 0).length;

  void _markFolderRead(int index) {
    for (final c in _chatsInFolder(index).toList()) {
      if (_controller.unreadFor(c) > 0) _controller.markChatRead(c.id);
    }
  }

  Future<void> _deleteFolder(int index) async {
    if (index <= 0 || index > _folders.length) return;
    final next = [..._folders]..removeAt(index - 1);
    setState(() {
      _folders = next;
      _activeFolder = 0;
    });
    await FoldersStore.save(next);
  }

  Future<void> _editFolder(ChatFolder folder) async {
    final result = await Navigator.of(context).push<ChatFolder>(
      CupertinoPageRoute(
        builder: (_) =>
            FolderEditScreen(controller: _controller, folder: folder),
      ),
    );
    if (result == null) return;
    final i = _folders.indexWhere((f) => f.id == result.id);
    if (i == -1) return;
    final next = [..._folders];
    next[i] = result;
    setState(() => _folders = next);
    await FoldersStore.save(next);
  }

  /// Всплывающее меню папки (iOS-стиль) по долгому нажатию на вкладку.
  Future<void> _folderMenu(int index, Offset pos) async {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final folder =
        (index > 0 && index <= _folders.length) ? _folders[index - 1] : null;
    final hasUnread = _folderUnread(index) > 0;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    Widget item(IconData icon, String label, {bool danger_ = false}) {
      final c = danger_ ? danger : (isLight ? lightText : text);
      return Row(
        children: [
          Icon(icon, size: 20, color: danger_ ? danger : accent),
          const SizedBox(width: 14),
          Text(label,
              style: TextStyle(
                  color: c, fontWeight: FontWeight.w600, fontSize: 15)),
        ],
      );
    }

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        pos & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      color: isLight ? Colors.white : panel,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: border),
      ),
      items: [
        PopupMenuItem(
          value: 'read',
          enabled: hasUnread,
          child: item(Icons.done_all_rounded, 'Прочитать всё'),
        ),
        if (folder != null && folder.filterType == FolderFilter.manual)
          PopupMenuItem(
            value: 'edit',
            child: item(Icons.edit_rounded, 'Настроить папку'),
          ),
        if (folder != null)
          PopupMenuItem(
            value: 'delete',
            child: item(Icons.delete_outline_rounded, 'Удалить', danger_: true),
          ),
      ],
    );

    switch (result) {
      case 'read':
        _markFolderRead(index);
      case 'edit':
        if (folder != null) _editFolder(folder);
      case 'delete':
        _deleteFolder(index);
    }
  }

  Widget _folderTab(String name, int index, bool isLight) {
    final selected = _activeFolder == index;
    final unread = _folderUnread(index);
    final inner = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            style: TextStyle(
              color: selected ? accent : (isLight ? lightMuted : muted),
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          if (unread > 0) ...[
            const SizedBox(width: 7),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              constraints: const BoxConstraints(minWidth: 18),
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                unread > 99 ? '99+' : '$unread',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF08131A),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
      ),
    );
    return GestureDetector(
      onTap: () => setState(() => _activeFolder = index),
      onLongPressStart: (d) => _folderMenu(index, d.globalPosition),
      child: SizedBox(
        height: 36,
        child: Center(child: inner),
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
          padding: const EdgeInsets.only(bottom: 5),
          child: GlassCard(
            borderRadius: 18,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                Expanded(
                  child: ChatTile(
                    chat: chat,
                    avatarUrl: _controller.displayAvatar(chat),
                    serverUrl: _controller.serverUrl,
                    unread: _controller.unreadFor(chat),
                    peerOnline: _controller.isPeerOnline(chat),
                    onTap: () {},
                    onLongPress: (_) {},
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
    // Фильтр по активной папке (0 = «Все»).
    if (_activeFolder > 0 && _activeFolder <= _folders.length) {
      final folder = _folders[_activeFolder - 1];
      switch (folder.filterType) {
        case FolderFilter.direct:
          list = list.where((c) => c.type == ChatType.direct);
        case FolderFilter.groups:
          list = list.where((c) =>
              c.type == ChatType.group || c.type == ChatType.channel);
        default:
          final ids = folder.chatIds.toSet();
          list = list.where((c) => ids.contains(c.id));
      }
    }
    if (query.isNotEmpty) {
      list = list.where((c) => c.title.toLowerCase().contains(query));
    }
    // Сортировка приходит из контроллера: закреплённые сверху, остальные по
    // свежести. Ручной порядок здесь не применяем, чтобы новые сообщения
    // поднимали чат вверх.
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
          padding: const EdgeInsets.only(bottom: 5),
          child: GlassCard(
            borderRadius: 18,
            padding: EdgeInsets.zero,
            child: ChatTile(
              chat: chat,
              avatarUrl: _controller.displayAvatar(chat),
              serverUrl: _controller.serverUrl,
              unread: _controller.unreadFor(chat),
              peerOnline: _controller.isPeerOnline(chat),
              onTap: () => _openChat(chat),
              onLongPress: (_) => _chatOptions(chat),
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
    required this.onManageFolders,
    required this.isLight,
  });

  final MessengerController controller;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final Future<void> Function() onLogout;
  final VoidCallback onManageFolders;
  final bool isLight;

  @override
  State<_SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<_SettingsView> {
  bool _uploadingPhoto = false;
  List<String> _avatarHistory = const [];

  MessengerController get _ctrl => widget.controller;
  bool get _isLight => widget.isLight;

  Color get _textColor => _isLight ? const Color(0xFF17202B) : text;
  Color get _mutedColor => _isLight ? const Color(0xFF637083) : muted;

  String get _historyKey => 'avatar_history_${_ctrl.currentUser.id}';

  @override
  void initState() {
    super.initState();
    _loadAvatarHistory();
  }

  Future<void> _loadAvatarHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_historyKey);
    if (raw != null && mounted) setState(() => _avatarHistory = raw);
  }

  Future<void> _pushAvatarHistory(String dataUrl) async {
    final next = [dataUrl, ..._avatarHistory.where((a) => a != dataUrl)]
        .take(12)
        .toList();
    setState(() => _avatarHistory = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_historyKey, next);
  }

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
      await _pushAvatarHistory(dataUrl);
      if (mounted) showAppToast(context, 'Аватар обновлён');
    } on Object catch (e) {
      if (mounted) showAppToast(context, 'Ошибка: $e', error: true);
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _applyHistoryAvatar(String dataUrl) async {
    Navigator.of(context).pop();
    try {
      await _ctrl.api.updateProfile(avatarDataUrl: dataUrl);
      await _pushAvatarHistory(dataUrl);
      if (mounted) showAppToast(context, 'Аватар обновлён');
    } on Object catch (e) {
      if (mounted) showAppToast(context, 'Ошибка: $e', error: true);
    }
  }

  void _openAvatarGallery() {
    if (_avatarHistory.isEmpty) {
      showAppToast(context, 'История аватаров пуста — добавьте аватар');
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _isLight ? Colors.white : panel,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Мои аватары',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: _textColor)),
              const SizedBox(height: 12),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                ),
                itemCount: _avatarHistory.length,
                itemBuilder: (context, index) {
                  final dataUrl = _avatarHistory[index];
                  final bytes = bytesFromDataUrl(dataUrl);
                  return GestureDetector(
                    onTap: () => _applyHistoryAvatar(dataUrl),
                    child: ClipOval(
                      child: bytes == null
                          ? Container(color: panelSoft)
                          : Image.memory(bytes,
                              fit: BoxFit.cover,
                              alignment: const Alignment(0, -0.55)),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
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
                          GestureDetector(
                            onTap: _openAvatarGallery,
                            child: Container(
                            padding: const EdgeInsets.all(4),
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
                    _sectionLabel('АВАТАР'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _photoBtn(
                            icon: Icons.add_a_photo_rounded,
                            label: 'Добавить аватар',
                            onTap: _uploadingPhoto ? null : _changePhoto,
                            loading: _uploadingPhoto,
                          ),
                        ),
                        if (_ctrl.currentUser.avatarUrl != null &&
                            _ctrl.currentUser.avatarUrl!.isNotEmpty) ...[
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
                      ],
                    ),
                    const SizedBox(height: 20),
                    _sectionLabel('QR-КОД'),
                    const SizedBox(height: 8),
                    GlassCard(
                      borderRadius: 18,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: QrImageView(
                              data: '${_ctrl.serverUrl}/u/${user.username}',
                              version: QrVersions.auto,
                              size: 184,
                              backgroundColor: Colors.white,
                              eyeStyle: const QrEyeStyle(
                                eyeShape: QrEyeShape.square,
                                color: Color(0xFF101317),
                              ),
                              dataModuleStyle: const QrDataModuleStyle(
                                dataModuleShape: QrDataModuleShape.square,
                                color: Color(0xFF101317),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Отсканируйте, чтобы открыть чат со мной',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: _mutedColor, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    _sectionLabel('ЧАТЫ'),
                    const SizedBox(height: 8),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onManageFolders,
                      child: GlassCard(
                        borderRadius: 18,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        child: Row(
                          children: [
                            _miniIcon(Icons.folder_rounded),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text('Папки чатов',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: _textColor)),
                            ),
                            Icon(Icons.chevron_right_rounded,
                                color: _mutedColor),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _sectionLabel('ОФОРМЛЕНИЕ'),
                    const SizedBox(height: 8),
                    GlassCard(
                      borderRadius: 18,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      child: Row(
                        children: [
                          _miniIcon(Icons.dark_mode_rounded),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text('Ночной режим',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: _textColor)),
                          ),
                          NightModeSwitch(
                            isLight: _isLight,
                            onChanged: widget.onThemeModeChanged,
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

// ─── Элемент нижней навигации с анимацией иконки при выборе ────────────────

enum _NavEffect { bounce, spin }

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.icon,
    required this.iconOutline,
    required this.label,
    required this.selected,
    required this.isLight,
    required this.onTap,
    this.effect = _NavEffect.bounce,
  });

  final IconData icon; // заполненная (выбрано)
  final IconData iconOutline; // контурная (не выбрано)
  final String label;
  final bool selected;
  final bool isLight;
  final VoidCallback onTap;
  final _NavEffect effect;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void didUpdateWidget(_NavItem old) {
    super.didUpdateWidget(old);
    if (widget.selected && !old.selected) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  // Преобразование иконки по ходу анимации выбора.
  Widget _transform(Widget child) {
    final t = _c.value;
    if (t == 0) return child;
    if (widget.effect == _NavEffect.spin) {
      // Шестерёнка: полный оборот на 360° (возвращается на место) + «дыхание».
      final turns = Curves.easeInOutCubic.transform(t);
      final scale = 1 + 0.22 * math.sin(t * math.pi);
      return Transform.rotate(
        angle: turns * 2 * math.pi,
        child: Transform.scale(scale: scale, child: child),
      );
    }
    // Чаты: упругий «желейный» отскок с лёгким покачиванием.
    final scale =
        (1 + 0.4 * math.sin(t * math.pi) - 0.12 * math.sin(t * 2 * math.pi))
            .clamp(0.8, 1.5);
    final wobble = math.sin(t * math.pi * 3) * 0.14 * (1 - t);
    return Transform.rotate(
      angle: wobble,
      child: Transform.scale(scale: scale.toDouble(), child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.selected
        ? accent
        : (widget.isLight ? lightMuted : muted);
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _c,
              builder: (context, child) => _transform(child!),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: Icon(
                  widget.selected ? widget.icon : widget.iconOutline,
                  key: ValueKey(widget.selected),
                  color: color,
                  size: 24,
                ),
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 260),
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight:
                    widget.selected ? FontWeight.w800 : FontWeight.w600,
              ),
              child: Text(widget.label),
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
