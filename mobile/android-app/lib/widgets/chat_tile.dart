import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';
import '../theme/app_theme.dart';
import 'brenks_avatar.dart';

/// Плитка чата в списке чатов.
class ChatTile extends StatelessWidget {
  const ChatTile({
    super.key,
    required this.chat,
    required this.serverUrl,
    required this.unread,
    required this.peerOnline,
    required this.onTap,
    required this.onLongPress,
    this.avatarUrl,
  });

  final Chat chat;
  final String? avatarUrl;
  final String serverUrl;
  final int unread;
  final bool peerOnline;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final mutedColor = isLight ? lightMuted : muted;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            children: [
              Stack(
                children: [
                  BrenksAvatar(
                    title: chat.title,
                    imageUrl: avatarUrl ?? chat.avatarUrl,
                    baseUrl: serverUrl,
                    size: 50,
                  ),
                  if (peerOnline)
                    Positioned(
                      right: 1,
                      bottom: 1,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: const Color(0xFF4AAE8A),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isLight ? Colors.white : bg,
                            width: 2.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (chat.pinnedToTop) ...[
                          Icon(Icons.push_pin_rounded,
                              size: 14, color: mutedColor),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            chat.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (chat.lastMessage != null)
                          Text(
                            formatChatTimestamp(chat.lastMessage!.time),
                            style: TextStyle(color: mutedColor, fontSize: 12),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (chat.muted) ...[
                          Icon(Icons.volume_off_rounded,
                              size: 14, color: mutedColor),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            lastMessageLabel(chat.lastMessage?.text),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: mutedColor, fontSize: 14),
                          ),
                        ),
                        if (unread > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            constraints: const BoxConstraints(minWidth: 22),
                            decoration: BoxDecoration(
                              color: chat.muted ? muted : accent,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              unread > 99 ? '99+' : '$unread',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF08131A),
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
