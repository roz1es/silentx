import type { Server as IOServer } from 'socket.io';
import { v4 as uuid } from 'uuid';
import type { Message, MessageMedia } from './types.js';
import { verifyUserToken } from './auth.js';
import * as store from './store.js';

const typingTimeouts = new Map<string, ReturnType<typeof setTimeout>>();

function validMedia(m: MessageMedia): boolean {
  if (!m?.dataUrl || typeof m.dataUrl !== 'string') return false;
  if (m.dataUrl.length > 14_000_000) return false;
  if (!['image', 'file', 'voice', 'video_note'].includes(m.kind)) return false;
  return true;
}

export function registerSocketHandlers(io: IOServer): void {
  io.use((socket, next) => {
    const raw = socket.handshake.auth;
    const token =
      raw && typeof raw === 'object' && 'token' in raw
        ? String((raw as { token?: unknown }).token ?? '')
        : '';
    if (!token) {
      next(new Error('UNAUTHORIZED'));
      return;
    }
    const userId = verifyUserToken(token);
    if (!userId || !store.getUser(userId)) {
      next(new Error('UNAUTHORIZED'));
      return;
    }
    socket.data.userId = userId;
    next();
  });

  io.on('connection', (socket) => {
    const userId = socket.data.userId as string;

    socket.join(`user:${userId}`);

    const online = new Set<string>();
    for (const s of io.sockets.sockets.values()) {
      const id = s.data.userId as string | undefined;
      if (id) online.add(id);
    }
    io.emit('presence', { onlineUserIds: [...online] });

    const chats = store.getChatsForUser(userId);
    chats.forEach((c) => socket.join(`chat:${c.id}`));

    socket.on('join_chat', (chatId: string) => {
      const chat = store.getChat(chatId);
      if (!chat?.participantIds.includes(userId)) return;
      socket.join(`chat:${chatId}`);
    });

    socket.on(
      'send_message',
      (payload: {
        chatId: string;
        text?: string;
        imageUrl?: string;
        media?: MessageMedia;
      }) => {
        const chat = store.getChat(payload.chatId);
        if (!chat?.participantIds.includes(userId)) return;

        const text = (payload.text ?? '').trim();
        let media = payload.media;
        if (media && !validMedia(media)) return;
        if (payload.imageUrl && typeof payload.imageUrl === 'string') {
          if (payload.imageUrl.length > 14_000_000) return;
        }

        const hasLegacyImage =
          payload.imageUrl && payload.imageUrl.length > 0;
        if (!text && !hasLegacyImage && !media) return;

        if (media?.kind === 'image' && !media.mimeType?.startsWith('image/'))
          media = { ...media, mimeType: media.mimeType ?? 'image/jpeg' };

        const msg: Message = {
          id: uuid(),
          chatId: payload.chatId,
          senderId: userId,
          text: text || (hasLegacyImage || media ? ' ' : ''),
          imageUrl: hasLegacyImage ? payload.imageUrl : undefined,
          media: media && validMedia(media) ? media : undefined,
          createdAt: Date.now(),
        };
        store.addMessage(msg);
        const updated = store.getChat(payload.chatId);
        chat.participantIds.forEach((pid) => {
          io.to(`user:${pid}`).emit('message', { message: msg });
          if (updated) io.to(`user:${pid}`).emit('chat_updated', { chat: updated });
        });
      }
    );

    socket.on('mark_read', (chatId: string) => {
      const chat = store.markChatRead(chatId, userId);
      if (chat) {
        chat.participantIds.forEach((pid) => {
          io.to(`user:${pid}`).emit('chat_updated', { chat });
        });
      }
    });

    socket.on(
      'typing',
      (payload: { chatId: string; isTyping: boolean }) => {
        const chat = store.getChat(payload.chatId);
        if (!chat?.participantIds.includes(userId)) return;

        const uTyping = store.getUser(userId);
        const username =
          uTyping?.displayName?.trim() || uTyping?.username || 'User';
        const key = `${payload.chatId}:${userId}`;
        if (payload.isTyping) {
          if (typingTimeouts.has(key)) clearTimeout(typingTimeouts.get(key));
          typingTimeouts.set(
            key,
            setTimeout(() => {
              typingTimeouts.delete(key);
              socket.to(`chat:${payload.chatId}`).emit('typing', {
                chatId: payload.chatId,
                userId,
                username,
                isTyping: false,
              });
            }, 3000)
          );
        } else if (typingTimeouts.has(key)) {
          clearTimeout(typingTimeouts.get(key));
          typingTimeouts.delete(key);
        }

        socket.to(`chat:${payload.chatId}`).emit('typing', {
          chatId: payload.chatId,
          userId,
          username,
          isTyping: payload.isTyping,
        });
      }
    );

    socket.on(
      'delete_message',
      (payload: { chatId: string; messageId: string }) => {
        const msg = store.softDeleteMessage(
          payload.chatId,
          payload.messageId,
          userId
        );
        if (msg) {
          const chat = store.getChat(payload.chatId);
          chat?.participantIds.forEach((pid) => {
            io.to(`user:${pid}`).emit('message_deleted', {
              chatId: payload.chatId,
              messageId: payload.messageId,
            });
            if (chat)
              io.to(`user:${pid}`).emit('chat_updated', { chat });
          });
        }
      }
    );

    socket.on('disconnect', () => {
      const onlineAfter = new Set<string>();
      for (const s of io.sockets.sockets.values()) {
        const id = s.data.userId as string | undefined;
        if (id) onlineAfter.add(id);
      }
      io.emit('presence', { onlineUserIds: [...onlineAfter] });
    });
  });
}
