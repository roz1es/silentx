import 'package:flutter/material.dart';

import '../models.dart';
import '../theme/app_theme.dart';
import 'brenks_avatar.dart';

class NewChatResult {
  const NewChatResult({
    required this.type,
    required this.name,
    required this.memberIds,
  });

  final ChatType type;
  final String name;
  final List<String> memberIds;
}

/// Открывает полноэкранный лист создания нового чата.
Future<NewChatResult?> showNewChatSheet(
  BuildContext context, {
  required String serverUrl,
  required List<DirectoryUser> users,
}) {
  return showModalBottomSheet<NewChatResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.92,
      child: _NewChatSheet(serverUrl: serverUrl, users: users),
    ),
  );
}

class _NewChatSheet extends StatefulWidget {
  const _NewChatSheet({required this.serverUrl, required this.users});

  final String serverUrl;
  final List<DirectoryUser> users;

  @override
  State<_NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends State<_NewChatSheet> {
  final _nameController = TextEditingController();
  final _searchController = TextEditingController();
  ChatType _type = ChatType.direct;
  Set<String> _selected = {};

  @override
  void dispose() {
    _nameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  bool get _canCreate {
    if (_selected.isEmpty) return false;
    if (_type != ChatType.direct && _nameController.text.trim().isEmpty) {
      return false;
    }
    return true;
  }

  void _submit() {
    if (!_canCreate) return;
    Navigator.pop(
      context,
      NewChatResult(
        type: _type,
        name: _nameController.text.trim(),
        memberIds: _selected.toList(growable: false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final users = query.isEmpty
        ? widget.users
        : widget.users
            .where((user) =>
                user.title.toLowerCase().contains(query) ||
                user.username.toLowerCase().contains(query))
            .toList(growable: false);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: muted.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Новый чат',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ChatType>(
              segments: const [
                ButtonSegment(
                  value: ChatType.direct,
                  label: Text('Личный'),
                  icon: Icon(Icons.person_rounded, size: 18),
                ),
                ButtonSegment(
                  value: ChatType.group,
                  label: Text('Группа'),
                  icon: Icon(Icons.groups_rounded, size: 18),
                ),
                ButtonSegment(
                  value: ChatType.channel,
                  label: Text('Канал'),
                  icon: Icon(Icons.campaign_rounded, size: 18),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (value) => setState(() {
                _type = value.first;
                _selected = {};
              }),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Column(
              children: [
                if (_type != ChatType.direct) ...[
                  TextField(
                    controller: _nameController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: _type == ChatType.group
                          ? 'Название группы'
                          : 'Название канала',
                      prefixIcon: const Icon(Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Поиск людей...',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: users.isEmpty
                ? const Center(
                    child: Text('Никого не найдено',
                        style: TextStyle(color: muted)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: users.length,
                    itemBuilder: (context, index) {
                      final user = users[index];
                      final selected = _selected.contains(user.id);
                      return ListTile(
                        leading: BrenksAvatar(
                          title: user.title,
                          imageUrl: user.avatarUrl,
                          baseUrl: widget.serverUrl,
                          size: 46,
                        ),
                        title: Text(user.title),
                        subtitle: Text('@${user.username}',
                            style: const TextStyle(color: muted)),
                        trailing: Icon(
                          selected
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: selected ? accent : muted,
                        ),
                        onTap: () => setState(() {
                          if (_type == ChatType.direct) {
                            _selected = {user.id};
                          } else if (selected) {
                            _selected = {..._selected}..remove(user.id);
                          } else {
                            _selected = {..._selected, user.id};
                          }
                        }),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _canCreate ? _submit : null,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    backgroundColor: accent,
                    foregroundColor: const Color(0xFF08131A),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    _type == ChatType.direct
                        ? 'Создать чат'
                        : _selected.isEmpty
                            ? 'Выберите участников'
                            : 'Создать (${_selected.length})',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
