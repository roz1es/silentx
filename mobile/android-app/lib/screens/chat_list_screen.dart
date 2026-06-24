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
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
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
    final isLight = Theme.of(context).brightness == Brightness.light;
    final query = _searchController.text.trim().toLowerCase();
    final chats = query.isEmpty
        ? _controller.chats
        : _controller.chats
            .where((chat) => chat.title.toLowerCase().contains(query))
            .toList(growable: false);

    return GlassBackground(
      child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        flexibleSpace: const GlassBar(bottomBorder: true),
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
        titleSpacing: 4,
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
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _controller.currentUser.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Color(0xFF4AAE8A),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'онлайн',
                        style: TextStyle(
                          fontSize: 12,
                          color: isLight ? lightMuted : muted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
        actions: [
          _AnimatedCircleAction(
            tooltip: _searching ? 'Закрыть поиск' : 'Поиск',
            icon: _searching ? Icons.close_rounded : Icons.search_rounded,
            onTap: () => setState(() {
              _searching = !_searching;
              if (!_searching) _searchController.clear();
            }),
            isLight: isLight,
          ),
          const SizedBox(width: 6),
          _AnimatedCircleAction(
            tooltip: 'Новый чат',
            icon: Icons.maps_ugc_rounded,
            onTap: _newChat,
            isLight: isLight,
            accented: true,
          ),
          const SizedBox(width: 10),
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
    return DraggableScrollableSheet(
      initialChildSize: 0.86,
      maxChildSize: 0.96,
      minChildSize: 0.5,
      expand: false,
      builder: (_, scrollCtrl) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: Stack(
          children: [
            const Positioned.fill(
              child: GlassBackground(child: SizedBox.expand()),
            ),
            SingleChildScrollView(
              controller: scrollCtrl,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Drag handle
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: _mutedColor.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
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
                    FilledButton.tonalIcon(
                      onPressed: widget.onLogout,
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Готово'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                    const SizedBox(height: 8),
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
              ),
            ),
          ],
        ),
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

// ─── Анимированная круглая кнопка AppBar ──────────────────────────────────

class _AnimatedCircleAction extends StatefulWidget {
  const _AnimatedCircleAction({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    required this.isLight,
    this.accented = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool isLight;
  final bool accented;

  @override
  State<_AnimatedCircleAction> createState() => _AnimatedCircleActionState();
}

class _AnimatedCircleActionState extends State<_AnimatedCircleAction>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    if (widget.accented) _pulse.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.accented
        ? accent
        : (widget.isLight ? lightText : text);
    final bg = widget.accented
        ? accent.withValues(alpha: widget.isLight ? 0.16 : 0.18)
        : Colors.white.withValues(alpha: widget.isLight ? 0.55 : 0.08);
    return Tooltip(
      message: widget.tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.onTap,
        // Плавное сжатие при нажатии…
        child: AnimatedScale(
          scale: _pressed ? 0.82 : 1.0,
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOut,
          // …и непрерывная «дышащая» пульсация + свечение у кнопки нового чата.
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) {
              final t = Curves.easeInOut.transform(_pulse.value);
              return Transform.scale(
                scale: widget.accented ? 1.0 + 0.09 * t : 1.0,
                child: child,
              );
            },
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, child) {
                final t = Curves.easeInOut.transform(_pulse.value);
                return Container(
                  width: 42,
                  height: 42,
                  margin: const EdgeInsets.symmetric(vertical: 7),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: bg,
                    shape: BoxShape.circle,
                    boxShadow: widget.accented
                        ? [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.25 + 0.30 * t),
                              blurRadius: 8 + 10 * t,
                            ),
                          ]
                        : null,
                  ),
                  child: child,
                );
              },
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) => RotationTransition(
                  turns: Tween<double>(begin: 0.5, end: 1.0).animate(animation),
                  child: ScaleTransition(scale: animation, child: child),
                ),
                child: Icon(
                  widget.icon,
                  key: ValueKey(widget.icon.codePoint),
                  color: fg,
                  size: 22,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
