import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/folders_store.dart';
import '../services/messenger_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/brenks_avatar.dart';
import '../widgets/glass.dart';

/// Экран управления папками чатов (создать / переименовать / удалить).
class FoldersScreen extends StatefulWidget {
  const FoldersScreen({super.key, required this.controller});

  final MessengerController controller;

  @override
  State<FoldersScreen> createState() => _FoldersScreenState();
}

class _FoldersScreenState extends State<FoldersScreen> {
  List<ChatFolder> _folders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final f = await FoldersStore.load();
    if (mounted) {
      setState(() {
        _folders = f;
        _loading = false;
      });
    }
  }

  Future<void> _save() async => FoldersStore.save(_folders);

  Future<void> _createOrEdit([ChatFolder? folder]) async {
    final result = await Navigator.of(context).push<ChatFolder>(
      CupertinoPageRoute(
        builder: (_) => FolderEditScreen(
          controller: widget.controller,
          folder: folder,
        ),
      ),
    );
    if (result == null) return;
    setState(() {
      final i = _folders.indexWhere((f) => f.id == result.id);
      if (i == -1) {
        _folders = [..._folders, result];
      } else {
        final next = [..._folders];
        next[i] = result;
        _folders = next;
      }
    });
    await _save();
  }

  Future<void> _delete(ChatFolder folder) async {
    setState(() => _folders = _folders.where((f) => f.id != folder.id).toList());
    await _save();
  }

  /// Готовые папки по типу, которых ещё нет.
  List<({String name, String filter})> get _recommended {
    final existing = _folders.map((f) => f.filterType).toSet();
    final all = [
      (name: 'Личные', filter: FolderFilter.direct),
      (name: 'Группы, беседы и боты', filter: FolderFilter.groups),
    ];
    return all.where((p) => !existing.contains(p.filter)).toList();
  }

  Future<void> _addPreset(String name, String filter) async {
    setState(() {
      _folders = [
        ..._folders,
        ChatFolder(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          name: name,
          chatIds: [],
          filterType: filter,
        ),
      ];
    });
    await _save();
  }

  String _folderSubtitle(ChatFolder f) {
    switch (f.filterType) {
      case FolderFilter.direct:
        return 'Все личные чаты';
      case FolderFilter.groups:
        return 'Все группы, беседы и боты';
      default:
        return '${f.chatIds.length} чатов';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final textColor = isLight ? const Color(0xFF17202B) : text;
    final mutedColor = isLight ? lightMuted : muted;
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          flexibleSpace: const GlassBar(bottomBorder: true),
          title: const Text('Папки',
              style: TextStyle(fontWeight: FontWeight.w900)),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Создавайте папки с нужными чатами и переключайтесь между ними сверху списка.',
                    style: TextStyle(color: mutedColor, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  if (_folders.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(left: 6, bottom: 8),
                      child: Text('МОИ ПАПКИ',
                          style: TextStyle(
                              color: mutedColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2)),
                    ),
                    ..._folders.map(
                      (folder) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: GlassCard(
                          borderRadius: 16,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          child: Row(
                            children: [
                              _miniIcon(folder.filterType == FolderFilter.manual
                                  ? Icons.folder_rounded
                                  : Icons.auto_awesome_rounded),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(folder.name,
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: textColor)),
                                    Text(_folderSubtitle(folder),
                                        style: TextStyle(
                                            color: mutedColor, fontSize: 12)),
                                  ],
                                ),
                              ),
                              if (folder.filterType == FolderFilter.manual)
                                IconButton(
                                  tooltip: 'Изменить',
                                  onPressed: () => _createOrEdit(folder),
                                  icon: Icon(Icons.edit_rounded,
                                      color: mutedColor, size: 20),
                                ),
                              IconButton(
                                tooltip: 'Удалить',
                                onPressed: () => _delete(folder),
                                icon: const Icon(Icons.delete_outline_rounded,
                                    color: danger, size: 20),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (_recommended.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(left: 6, bottom: 8),
                      child: Text('ГОТОВЫЕ ПАПКИ',
                          style: TextStyle(
                              color: mutedColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2)),
                    ),
                    ..._recommended.map(
                      (preset) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: GlassCard(
                          borderRadius: 16,
                          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                          child: Row(
                            children: [
                              _miniIcon(Icons.auto_awesome_rounded),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(preset.name,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: textColor)),
                              ),
                              TextButton(
                                onPressed: () =>
                                    _addPreset(preset.name, preset.filter),
                                child: const Text('Добавить',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w800)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  FilledButton.tonalIcon(
                    onPressed: () => _createOrEdit(),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Создать новую папку'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _miniIcon(IconData icon) => Container(
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

/// Редактор папки: имя + выбор чатов.
class FolderEditScreen extends StatefulWidget {
  const FolderEditScreen({
    super.key,
    required this.controller,
    this.folder,
  });

  final MessengerController controller;
  final ChatFolder? folder;

  @override
  State<FolderEditScreen> createState() => _FolderEditScreenState();
}

class _FolderEditScreenState extends State<FolderEditScreen> {
  late final TextEditingController _name =
      TextEditingController(text: widget.folder?.name ?? '');
  late Set<String> _selected = {...?widget.folder?.chatIds};

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty || _selected.isEmpty) return;
    Navigator.of(context).pop(
      ChatFolder(
        id: widget.folder?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        name: name,
        chatIds: _selected.toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final mutedColor = isLight ? lightMuted : muted;
    final chats = widget.controller.chats;
    final canSave = _name.text.trim().isNotEmpty && _selected.isNotEmpty;
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          flexibleSpace: const GlassBar(bottomBorder: true),
          title: Text(widget.folder == null ? 'Новая папка' : 'Папка',
              style: const TextStyle(fontWeight: FontWeight.w900)),
          actions: [
            TextButton(
              onPressed: canSave ? _save : null,
              child: const Text('Готово',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _name,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Название папки',
                  prefixIcon: Icon(Icons.folder_rounded),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 4, 16, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'ЧАТЫ В ПАПКЕ (${_selected.length})',
                  style: TextStyle(
                      color: mutedColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2),
                ),
              ),
            ),
            Expanded(
              child: chats.isEmpty
                  ? Center(
                      child: Text('Чатов нет',
                          style: TextStyle(color: mutedColor)),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: chats.length,
                      itemBuilder: (context, index) {
                        final chat = chats[index];
                        final selected = _selected.contains(chat.id);
                        return CheckboxListTile(
                          value: selected,
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              _selected = {..._selected, chat.id};
                            } else {
                              _selected = {..._selected}..remove(chat.id);
                            }
                          }),
                          activeColor: accent,
                          controlAffinity: ListTileControlAffinity.trailing,
                          secondary: BrenksAvatar(
                            title: chat.title,
                            imageUrl: widget.controller.displayAvatar(chat),
                            baseUrl: widget.controller.serverUrl,
                            size: 42,
                          ),
                          title: Text(chat.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
