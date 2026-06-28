import type { Server as IOServer } from 'socket.io';
import { spawn } from 'node:child_process';
import { promises as fs } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { v4 as uuid } from 'uuid';
import type {
  EncryptedTextEnvelope,
  Message,
  MessageMedia,
} from './types.js';
import { tokenFromCookieHeader, verifyUserToken } from './auth.js';
import * as store from './store.js';
import { notifyChatParticipants, sendPushNotification } from './pushNotifications.js';
import {
  isRegisteredE2eeDevice,
  ownsE2eeDevice,
} from './e2eeDevices.js';

const typingTimeouts = new Map<string, ReturnType<typeof setTimeout>>();

function validMedia(m: MessageMedia): boolean {
  if (!m?.dataUrl || typeof m.dataUrl !== 'string') return false;
  if (m.dataUrl.length > 14_000_000) return false;
  if (!['image', 'file', 'voice', 'video_note'].includes(m.kind)) return false;
  return true;
}

function decodedBase64UrlLength(value: string): number {
  try {
    return Buffer.from(value, 'base64url').length;
  } catch {
    return -1;
  }
}

function validEncryptedText(
  envelope: EncryptedTextEnvelope,
  participantIds: string[],
  senderId: string
): boolean {
  if (
    envelope?.version !== 1 ||
    envelope.algorithm !== 'crypto_box_curve25519xsalsa20poly1305' ||
    typeof envelope.senderDeviceId !== 'string' ||
    !ownsE2eeDevice(senderId, envelope.senderDeviceId) ||
    (envelope.senderPublicKey !== undefined &&
      (typeof envelope.senderPublicKey !== 'string' ||
        decodedBase64UrlLength(envelope.senderPublicKey) !== 32)) ||
    !Array.isArray(envelope.recipients) ||
    envelope.recipients.length === 0 ||
    envelope.recipients.length > 40
  ) {
    return false;
  }
  const participants = new Set(participantIds);
  const seen = new Set<string>();
  for (const recipient of envelope.recipients) {
    if (
      !recipient ||
      typeof recipient.userId !== 'string' ||
      typeof recipient.deviceId !== 'string' ||
      typeof recipient.nonce !== 'string' ||
      typeof recipient.ciphertext !== 'string' ||
      !participants.has(recipient.userId) ||
      !isRegisteredE2eeDevice(recipient.userId, recipient.deviceId) ||
      decodedBase64UrlLength(recipient.nonce) !== 24 ||
      decodedBase64UrlLength(recipient.ciphertext) < 17 ||
      recipient.ciphertext.length > 24_000
    ) {
      return false;
    }
    const key = `${recipient.userId}:${recipient.deviceId}`;
    if (seen.has(key)) return false;
    seen.add(key);
  }
  return true;
}

function parseDataUrl(dataUrl: string): { mime: string; buffer: Buffer } | null {
  const match = dataUrl.match(/^data:([^;,\s]+)(?:;.*)?;base64,(.+)$/);
  if (!match) return null;
  try {
    return {
      mime: match[1],
      buffer: Buffer.from(match[2], 'base64'),
    };
  } catch {
    return null;
  }
}

function runFfmpeg(args: string[]): Promise<void> {
  return new Promise((resolve, reject) => {
    const child = spawn('ffmpeg', args, { stdio: 'ignore' });
    child.on('error', reject);
    child.on('close', (code) => {
      if (code === 0) resolve();
      else reject(new Error(`ffmpeg exited with ${code}`));
    });
  });
}

async function transcodeVideoNoteIfPossible(
  media: MessageMedia | undefined
): Promise<MessageMedia | undefined> {
  if (!media || media.kind !== 'video_note') return media;

  const parsed = parseDataUrl(media.dataUrl);
  if (!parsed || parsed.buffer.length === 0) return media;

  const id = uuid();
  const inputExt = parsed.mime.includes('webm') ? 'webm' : 'video';
  const inputPath = path.join(os.tmpdir(), `brenks-${id}.${inputExt}`);
  const outputPath = path.join(os.tmpdir(), `brenks-${id}.mp4`);
  try {
    await fs.writeFile(inputPath, parsed.buffer);
    await runFfmpeg([
      '-y',
      '-hide_banner',
      '-loglevel',
      'error',
      '-i',
      inputPath,
      '-map',
      '0:v:0',
      '-map',
      '0:a?',
      '-vf',
      'crop=min(iw\\,ih):min(iw\\,ih),scale=360:360:flags=lanczos,fps=24,format=yuv420p',
      '-c:v',
      'libx264',
      '-preset',
      'fast',
      '-crf',
      '29',
      '-profile:v',
      'baseline',
      '-level',
      '3.0',
      '-tag:v',
      'avc1',
      '-movflags',
      '+faststart',
      '-c:a',
      'aac',
      '-b:a',
      '48k',
      '-map_metadata',
      '-1',
      outputPath,
    ]);
    const output = await fs.readFile(outputPath);
    const dataUrl = `data:video/mp4;base64,${output.toString('base64')}`;
    if (dataUrl.length > 14_000_000) return media;
    return {
      ...media,
      dataUrl,
      mimeType: 'video/mp4',
    };
  } catch (error) {
    console.warn('[video-note] не удалось перекодировать кружок:', error);
    return media;
  } finally {
    await Promise.allSettled([fs.rm(inputPath), fs.rm(outputPath)]);
  }
}

function looksLikeRegularMp4(dataUrl: string, expectedMime: string): boolean {
  if (!dataUrl.startsWith(`data:${expectedMime};base64,`)) return false;
  const base64 = dataUrl.slice(dataUrl.indexOf(',') + 1, dataUrl.indexOf(',') + 129);
  try {
    const header = Buffer.from(base64, 'base64').toString('latin1');
    return header.includes('ftyp') && !header.includes('moof');
  } catch {
    return false;
  }
}

async function transcodeVoiceIfPossible(
  media: MessageMedia | undefined
): Promise<MessageMedia | undefined> {
  if (!media || media.kind !== 'voice') return media;
  if (looksLikeRegularMp4(media.dataUrl, 'audio/mp4')) return media;

  const parsed = parseDataUrl(media.dataUrl);
  if (!parsed || parsed.buffer.length === 0) return media;

  const id = uuid();
  const inputPath = path.join(os.tmpdir(), `brenks-${id}.audio`);
  const outputPath = path.join(os.tmpdir(), `brenks-${id}.m4a`);
  try {
    await fs.writeFile(inputPath, parsed.buffer);
    await runFfmpeg([
      '-y',
      '-hide_banner',
      '-loglevel',
      'error',
      '-i',
      inputPath,
      '-map',
      '0:a:0',
      '-vn',
      '-c:a',
      'aac',
      '-b:a',
      '56k',
      '-movflags',
      '+faststart',
      '-map_metadata',
      '-1',
      outputPath,
    ]);
    const output = await fs.readFile(outputPath);
    const dataUrl = `data:audio/mp4;base64,${output.toString('base64')}`;
    if (dataUrl.length > 14_000_000) return media;
    return {
      ...media,
      dataUrl,
      mimeType: 'audio/mp4',
    };
  } catch (error) {
    console.warn('[voice] не удалось нормализовать голосовое:', error);
    return media;
  } finally {
    await Promise.allSettled([fs.rm(inputPath), fs.rm(outputPath)]);
  }
}

async function normalizeMediaForBrowsers(
  media: MessageMedia | undefined
): Promise<MessageMedia | undefined> {
  if (media?.kind === 'video_note') return transcodeVideoNoteIfPossible(media);
  if (media?.kind === 'voice') return transcodeVoiceIfPossible(media);
  return media;
}

function visibleOnlineUserIds(io: IOServer): string[] {
  const online = new Set<string>();
  for (const s of io.sockets.sockets.values()) {
    const id = s.data.userId as string | undefined;
    if (!id) continue;
    const u = store.getUser(id);
    if (u && u.privacy?.showOnline !== false) online.add(id);
  }
  return [...online];
}

export function registerSocketHandlers(io: IOServer): void {
  io.use((socket, next) => {
    const raw = socket.handshake.auth;
    const authToken =
      raw && typeof raw === 'object' && 'token' in raw
        ? String((raw as { token?: unknown }).token ?? '')
        : '';
    const token =
      tokenFromCookieHeader(socket.handshake.headers.cookie) || authToken;
    if (!token) {
      next(new Error('UNAUTHORIZED'));
      return;
    }
    const authenticated = verifyUserToken(token);
    const socketUser = authenticated
      ? store.getUser(authenticated.userId)
      : undefined;
    if (!authenticated || !socketUser || socketUser.banned) {
      next(new Error('UNAUTHORIZED'));
      return;
    }
    socket.data.userId = authenticated.userId;
    socket.data.sessionId = authenticated.sessionId;
    next();
  });

  io.on('connection', (socket) => {
    const userId = socket.data.userId as string;

    socket.join(`user:${userId}`);

    io.emit('presence', { onlineUserIds: visibleOnlineUserIds(io) });

    const chats = store.getChatsForUser(userId);
    chats.forEach((c) => socket.join(`chat:${c.id}`));

    socket.on('join_chat', (chatId: string) => {
      const chat = store.getChat(chatId);
      if (!chat?.participantIds.includes(userId)) return;
      socket.join(`chat:${chatId}`);
    });

    socket.on(
      'send_message',
      async (payload: {
        chatId: string;
        text?: string;
        encryptedText?: EncryptedTextEnvelope;
        imageUrl?: string;
        media?: MessageMedia;
        replyToMessageId?: string;
      }) => {
        const chat = store.getChat(payload.chatId);
        if (!chat?.participantIds.includes(userId)) return;
        if (!store.canWriteToChat(chat, userId)) {
          return;
        }

        const encryptedText = payload.encryptedText;
        if (
          encryptedText &&
          (chat.type !== 'direct' ||
            !validEncryptedText(
              encryptedText,
              chat.participantIds,
              userId
            ))
        ) {
          return;
        }
        const text = encryptedText ? '' : (payload.text ?? '').trim();
        let media = payload.media;
        if (media && !validMedia(media)) return;
        if (payload.imageUrl && typeof payload.imageUrl === 'string') {
          if (payload.imageUrl.length > 14_000_000) return;
        }

        const hasLegacyImage =
          payload.imageUrl && payload.imageUrl.length > 0;
        if (!text && !encryptedText && !hasLegacyImage && !media) return;

        if (media?.kind === 'image' && !media.mimeType?.startsWith('image/'))
          media = { ...media, mimeType: media.mimeType ?? 'image/jpeg' };
        if (media?.kind === 'video_note' || media?.kind === 'voice') {
          media = await normalizeMediaForBrowsers(media);
        }

        const replyToMessageId =
          typeof payload.replyToMessageId === 'string'
            ? payload.replyToMessageId
            : undefined;
        const replyOk =
          replyToMessageId &&
          store
            .getMessages(payload.chatId)
            .some((m) => m.id === replyToMessageId && !m.deleted);

        const msg: Message = {
          id: uuid(),
          chatId: payload.chatId,
          senderId: userId,
          text: text || (hasLegacyImage || media ? ' ' : ''),
          encryptedText,
          imageUrl: hasLegacyImage ? payload.imageUrl : undefined,
          media: media && validMedia(media) ? media : undefined,
          createdAt: Date.now(),
          replyToMessageId: replyOk ? replyToMessageId : undefined,
        };
        store.addMessage(msg);
        const updated = store.getChat(payload.chatId);
        
        // Отправляем WebSocket всем участникам
        chat.participantIds.forEach((pid) => {
          io.to(`user:${pid}`).emit('message', { message: msg });
          if (updated) {
            io.to(`user:${pid}`).emit('chat_updated', {
              chat: store.serializeChatForViewer(updated, pid),
            });
          }
        });
        
        // Отправляем push-уведомления
        const sender = store.getUser(userId);
        const senderName = sender?.displayName?.trim() || sender?.username || 'User';
        const chatName = chat.type === 'direct' ? senderName : chat.name;
        
        let notificationBody = '';
        if (msg.media) {
          switch (msg.media.kind) {
            case 'image': notificationBody = '📷 Фото'; break;
            case 'file': notificationBody = `📎 ${msg.media.fileName ?? 'Файл'}`; break;
            case 'voice': notificationBody = '🎤 Голосовое сообщение'; break;
            case 'video_note': notificationBody = '🎬 Видеокружок'; break;
            default: notificationBody = 'Сообщение';
          }
        } else if (msg.imageUrl) {
          notificationBody = '📷 Фото';
        } else if (msg.encryptedText) {
          notificationBody = 'Новое сообщение';
        } else {
          notificationBody = msg.text.slice(0, 100) || 'Сообщение';
        }
        
        void notifyChatParticipants(payload.chatId, userId, chatName, notificationBody);
      }
    );

    socket.on(
      'edit_message',
      (payload: {
        chatId?: string;
        messageId?: string;
        text?: string;
        encryptedText?: EncryptedTextEnvelope;
      }) => {
        const chatId = String(payload?.chatId ?? '');
        const messageId = String(payload?.messageId ?? '');
        const text = String(payload?.text ?? '');
        const chat = store.getChat(chatId);
        if (!chat?.participantIds.includes(userId)) return;
        if (!store.canWriteToChat(chat, userId)) {
          return;
        }
        const encryptedText = payload.encryptedText;
        if (
          encryptedText &&
          (chat.type !== 'direct' ||
            !validEncryptedText(
              encryptedText,
              chat.participantIds,
              userId
            ))
        ) {
          return;
        }
        const result = encryptedText
          ? store.editMessageEncryptedText(
              chatId,
              messageId,
              userId,
              encryptedText
            )
          : store.editMessageText(chatId, messageId, userId, text);
        if (!result) return;
        chat.participantIds.forEach((pid) => {
          io.to(`user:${pid}`).emit('message_edited', {
            message: result.message,
          });
          if (result.chat) {
            io.to(`user:${pid}`).emit('chat_updated', {
              chat: store.serializeChatForViewer(result.chat, pid),
            });
          }
        });
      }
    );

    socket.on(
      'toggle_reaction',
      (payload: { chatId?: string; messageId?: string; emoji?: string }) => {
        const chatId = String(payload?.chatId ?? '');
        const messageId = String(payload?.messageId ?? '');
        const emoji = String(payload?.emoji ?? '');
        const chat = store.getChat(chatId);
        if (!chat?.participantIds.includes(userId)) return;
        const msg = store.toggleMessageReaction(chatId, messageId, userId, emoji);
        if (!msg) return;
        chat.participantIds.forEach((pid) => {
          io.to(`user:${pid}`).emit('message_edited', { message: msg });
        });
      }
    );

    socket.on(
      'forward_messages',
      async (payload: {
        sourceChatId?: string;
        targetChatId?: string;
        messageIds?: string[];
      }) => {
        const sourceChatId = String(payload?.sourceChatId ?? '');
        const targetChatId = String(payload?.targetChatId ?? '');
        const sourceChat = store.getChat(sourceChatId);
        const targetChat = store.getChat(targetChatId);
        if (!sourceChat?.participantIds.includes(userId)) return;
        if (!targetChat?.participantIds.includes(userId)) return;
        if (!store.canWriteToChat(targetChat, userId)) {
          return;
        }
        const ids = Array.isArray(payload?.messageIds)
          ? payload.messageIds.map((id) => String(id)).slice(0, 25)
          : [];
        if (ids.length === 0) return;

        const sourceMessages = store
          .getMessages(sourceChatId)
          .filter((m) => ids.includes(m.id));
        const ordered = ids
          .map((id) => sourceMessages.find((m) => m.id === id))
          .filter((m): m is Message => Boolean(m));
        for (const original of ordered) {
          if (original.encryptedText) continue;
          let media = original.media ? { ...original.media } : undefined;
          if (media?.kind === 'video_note' || media?.kind === 'voice') {
            media = await normalizeMediaForBrowsers(media);
          }
          const msg: Message = {
            id: uuid(),
            chatId: targetChatId,
            senderId: userId,
            text: original.text || (original.imageUrl || media ? ' ' : ''),
            imageUrl: original.imageUrl,
            media,
            createdAt: Date.now(),
          };
          store.addMessage(msg);
          const updated = store.getChat(targetChatId);
          targetChat.participantIds.forEach((pid) => {
            io.to(`user:${pid}`).emit('message', { message: msg });
            if (updated) {
              io.to(`user:${pid}`).emit('chat_updated', {
                chat: store.serializeChatForViewer(updated, pid),
              });
            }
          });
        }
      }
    );

    socket.on('mark_read', (chatId: string) => {
      const chat = store.markChatRead(chatId, userId);
      if (chat) {
        chat.participantIds.forEach((pid) => {
          io.to(`user:${pid}`).emit('chat_updated', {
            chat: store.serializeChatForViewer(chat, pid),
          });
        });
      }
    });

    socket.on(
      'typing',
      (payload: { chatId: string; isTyping: boolean }) => {
        const chat = store.getChat(payload.chatId);
        if (!chat?.participantIds.includes(userId)) return;
        if (!store.canWriteToChat(chat, userId)) {
          return;
        }

        const uTyping = store.getUser(userId);
        if (uTyping?.privacy?.showOnline === false) return;
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
            if (chat) {
              io.to(`user:${pid}`).emit('chat_updated', {
                chat: store.serializeChatForViewer(chat, pid),
              });
            }
          });
        }
      }
    );

    socket.on(
      'call_signal',
      (payload: {
        toUserId?: string;
        kind?: 'offer' | 'answer' | 'ice' | 'end';
        callId?: string;
        callType?: 'audio' | 'video';
        sdp?: string;
        candidate?: RTCIceCandidateInit;
      }) => {
        const toUserId = payload?.toUserId;
        const kind = payload?.kind;
        if (typeof toUserId !== 'string' || typeof kind !== 'string') return;
        if (!store.usersShareChat(userId, toUserId)) return;
        const callee = store.getUser(toUserId);
        if (callee?.privacy?.allowCalls === false) return;
        io.to(`user:${toUserId}`).emit('call_signal', {
          fromUserId: userId,
          kind,
          callId: typeof payload.callId === 'string' ? payload.callId : undefined,
          callType: payload.callType,
          sdp: payload.sdp,
          candidate: payload.candidate,
        });
        if (kind === 'offer') {
          const caller = store.getUser(userId);
          const callerName =
            caller?.displayName?.trim() || caller?.username || 'БренксЧат';
          void sendPushNotification(toUserId, {
            title: 'Входящий звонок БренксЧат',
            body:
              payload.callType === 'video'
                ? `${callerName} зовёт вас в видеозвонок`
                : `${callerName} звонит вам`,
            tag: `call-${userId}`,
            requireInteraction: true,
            data: {
              call: true,
              fromUserId: userId,
              callType: payload.callType ?? 'audio',
            },
          });
        }
      }
    );

    socket.on('disconnect', () => {
      io.emit('presence', { onlineUserIds: visibleOnlineUserIds(io) });
    });
  });
}
