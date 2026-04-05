import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import cors from 'cors';
import express from 'express';
import rateLimit from 'express-rate-limit';
import helmet from 'helmet';
import http from 'http';
import { Server } from 'socket.io';
import webpush from 'web-push';
import type { User } from './types.js';
import { requireAdmin, requireAuth, signUserToken } from './auth.js';
import * as store from './store.js';
import { bootstrapPersistence, startPeriodicPersistence } from './persist.js';
import { registerSocketHandlers } from './socketHandlers.js';
import { setupWebPush } from './pushNotifications.js';

bootstrapPersistence();
startPeriodicPersistence();

// Настройка Web Push
const VAPID_PUBLIC_KEY = process.env.VAPID_PUBLIC_KEY || 'BETYIXs8gcpT-YJk_6e2T6_FBJjSnRuFrGrbkgd28paXd8LkOfzZQAAMpCTC8W4LW_Vdgycv46CbVteI2JxvsQI';
const VAPID_PRIVATE_KEY = process.env.VAPID_PRIVATE_KEY || 'IXVHj0JD5_A1d2QFn78-n4nS6g6jZzyttrmW22_q7O0';
const VAPID_SUBJECT = process.env.VAPID_SUBJECT || 'mailto:silentix@example.com';

setupWebPush(VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, VAPID_SUBJECT);

const MAX_AVATAR_LEN = 900_000;
const RESERVED_USERNAMES = new Set(['roz1es', 'elzi']);

function publicUser(u: User) {
  return {
    id: u.id,
    username: u.username,
    avatarUrl: u.avatarUrl,
    displayName: u.displayName,
    bio: u.bio,
    phone: u.phone,
    birthDate: u.birthDate,
    isAdmin: !!u.isAdmin,
  };
}

const PORT = Number(process.env.PORT) || 3001;
const HOST = process.env.HOST ?? '0.0.0.0';

function lanIPv4Addresses(): string[] {
  const nets = os.networkInterfaces();
  const out: string[] = [];
  for (const list of Object.values(nets)) {
    for (const net of list ?? []) {
      if (net.internal) continue;
      if (net.family !== 'IPv4') continue;
      out.push(net.address);
    }
  }
  return out;
}
const app = express();
app.use(helmet({ contentSecurityPolicy: false }));
app.use(cors({ origin: true, credentials: true }));
app.use(express.json({ limit: '50mb' }));

const server = http.createServer(app);
const io = new Server(server, {
  cors: { origin: true, credentials: true },
});
registerSocketHandlers(io);

function broadcastChatToParticipants(chatId: string): void {
  const chat = store.getChat(chatId);
  if (!chat) return;
  chat.participantIds.forEach((pid) => {
    io.to(`user:${pid}`).emit('chat_updated', {
      chat: store.serializeChatForViewer(chat, pid),
    });
  });
}

const apiGeneralLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 400,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Слишком много запросов. Подождите минуту.' },
});

const authRouteLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 40,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Слишком много попыток входа. Попробуйте позже.' },
});

app.use('/api', apiGeneralLimiter);

app.post('/api/register', authRouteLimiter, (req, res) => {
  const { username, password } = req.body ?? {};
  if (
    typeof username !== 'string' ||
    typeof password !== 'string' ||
    username.length < 2 ||
    password.length < 2
  ) {
    return res.status(400).json({ error: 'Некорректные данные' });
  }
  const unLower = username.trim().toLowerCase();
  if (RESERVED_USERNAMES.has(unLower)) {
    return res.status(403).json({ error: 'Это имя зарезервировано' });
  }
  if (store.findUserByUsername(username)) {
    return res.status(409).json({ error: 'Имя пользователя занято' });
  }
  const user = store.createUser(username.trim(), password);
  store.ensureWelcomeChat(user.id);
  res.json({
    user: publicUser(user),
    token: signUserToken(user.id),
  });
});

app.get('/api/me', requireAuth, (req, res) => {
  const userId = req.userId!;
  const u = store.getUser(userId);
  if (!u) return res.status(401).json({ error: 'Требуется авторизация' });
  res.json({ user: publicUser(u) });
});

app.get('/api/admin/overview', requireAuth, requireAdmin, (_req, res) => {
  res.json(store.getAdminOverview());
});

app.patch('/api/me', requireAuth, (req, res) => {
  const userId = req.userId!;
  const u = store.getUser(userId);
  if (!u) return res.status(401).json({ error: 'Требуется авторизация' });
  const body = req.body ?? {};
  const patch: {
    avatarUrl?: string | null;
    bio?: string | null;
    displayName?: string | null;
    phone?: string | null;
    birthDate?: string | null;
  } = {};
  if ('avatarUrl' in body) {
    const avatarUrl = body.avatarUrl as string | null | undefined;
    if (avatarUrl != null) {
      if (typeof avatarUrl !== 'string' || avatarUrl.length > MAX_AVATAR_LEN) {
        return res.status(400).json({ error: 'Некорректное изображение' });
      }
    }
    patch.avatarUrl = avatarUrl ?? null;
  }
  if ('bio' in body) {
    const bio = body.bio as string | null | undefined;
    if (bio != null && typeof bio !== 'string') {
      return res.status(400).json({ error: 'Некорректное поле bio' });
    }
    patch.bio = bio ?? null;
  }
  if ('displayName' in body) {
    const displayName = body.displayName as string | null | undefined;
    if (displayName != null && typeof displayName !== 'string') {
      return res.status(400).json({ error: 'Некорректное имя' });
    }
    patch.displayName = displayName ?? null;
  }
  if ('phone' in body) {
    const phone = body.phone as string | null | undefined;
    if (phone != null && typeof phone !== 'string') {
      return res.status(400).json({ error: 'Некорректный телефон' });
    }
    patch.phone = phone ?? null;
  }
  if ('birthDate' in body) {
    const birthDate = body.birthDate as string | null | undefined;
    if (birthDate != null && typeof birthDate !== 'string') {
      return res.status(400).json({ error: 'Некорректная дата' });
    }
    patch.birthDate = birthDate ?? null;
  }
  if (Object.keys(patch).length === 0) {
    return res.status(400).json({ error: 'Укажите поля профиля' });
  }
  store.updateUserProfile(userId, patch);
  const fresh = store.getUser(userId);
  if (!fresh) return res.status(500).json({ error: 'Ошибка' });
  res.json({ user: publicUser(fresh) });
});

app.get('/api/users/directory', requireAuth, (req, res) => {
  const userId = req.userId!;
  res.json({ users: store.listDirectoryUsers(userId) });
});

app.get('/api/users/:userId', requireAuth, (req, res) => {
  const viewerId = req.userId!;
  const targetId = req.params.userId;
  const target = store.getUser(targetId);
  if (!target) return res.status(404).json({ error: 'Пользователь не найден' });
  if (!store.usersShareChat(viewerId, targetId)) {
    return res.status(403).json({ error: 'Нет доступа к профилю' });
  }
  res.json({ user: publicUser(target) });
});

app.post('/api/login', authRouteLimiter, (req, res) => {
  const { username, password } = req.body ?? {};
  const u = store.findUserByUsername(String(username ?? ''));
  if (!u || u.password !== String(password)) {
    return res.status(401).json({ error: 'Неверный логин или пароль' });
  }
  res.json({
    user: publicUser(u),
    token: signUserToken(u.id),
  });
});

app.get('/api/chats', requireAuth, (req, res) => {
  const userId = req.userId!;
  const list = store
    .getChatsForUser(userId)
    .map((c) => store.serializeChatForViewer(c, userId));
  res.json({ chats: list });
});

app.get('/api/chats/:chatId/messages', requireAuth, (req, res) => {
  const userId = req.userId!;
  const chatId = req.params.chatId;
  const chat = store.getChat(chatId);
  if (!chat?.participantIds.includes(userId)) {
    return res.status(404).json({ error: 'Чат не найден' });
  }
  res.json({ messages: store.getMessages(chatId) });
});

app.post('/api/chats/:chatId/mute', requireAuth, (req, res) => {
  const userId = req.userId!;
  const chatId = req.params.chatId;
  const chat = store.getChat(chatId);
  if (!chat?.participantIds.includes(userId)) {
    return res.status(404).json({ error: 'Чат не найден' });
  }
  const muted = Boolean((req.body as { muted?: boolean })?.muted);
  store.setChatMutedForUser(userId, chatId, muted);
  broadcastChatToParticipants(chatId);
  res.json({ ok: true });
});

app.post('/api/chats/:chatId/pin-top', requireAuth, (req, res) => {
  const userId = req.userId!;
  const chatId = req.params.chatId;
  const chat = store.getChat(chatId);
  if (!chat?.participantIds.includes(userId)) {
    return res.status(404).json({ error: 'Чат не найден' });
  }
  const pinned = Boolean((req.body as { pinned?: boolean })?.pinned);
  store.setChatPinnedTopForUser(userId, chatId, pinned);
  broadcastChatToParticipants(chatId);
  res.json({ ok: true });
});

app.post('/api/chats/:chatId/pin-message', requireAuth, (req, res) => {
  const userId = req.userId!;
  const chatId = req.params.chatId;
  const chat = store.getChat(chatId);
  if (!chat?.participantIds.includes(userId)) {
    return res.status(404).json({ error: 'Чат не найден' });
  }
  const raw = (req.body as { messageId?: string | null })?.messageId;
  const messageId =
    raw === null || raw === undefined || raw === '' ? null : String(raw);
  const updated = store.setChatPinnedMessage(chatId, messageId, userId);
  if (!updated) {
    return res.status(400).json({ error: 'Сообщение не найдено' });
  }
  broadcastChatToParticipants(chatId);
  res.json({ ok: true });
});

app.post('/api/chats/:chatId/clear', requireAuth, (req, res) => {
  const userId = req.userId!;
  const chatId = req.params.chatId;
  const cleared = store.clearAllMessagesInChat(chatId, userId);
  if (!cleared) {
    return res.status(404).json({ error: 'Чат не найден' });
  }
  cleared.participantIds.forEach((pid) => {
    io.to(`user:${pid}`).emit('messages_cleared', { chatId });
  });
  broadcastChatToParticipants(chatId);
  res.json({ ok: true });
});

app.post('/api/chats/direct', requireAuth, (req, res) => {
  const userId = req.userId!;
  const { targetUsername, targetUserId } = req.body ?? {};
  let other = undefined as ReturnType<typeof store.getUser>;
  if (typeof targetUserId === 'string' && targetUserId.trim()) {
    const u = store.getUser(targetUserId.trim());
    if (u && u.id !== userId) other = u;
  }
  if (!other && typeof targetUsername === 'string') {
    other = store.findUserByUsername(targetUsername);
  }
  if (!other || other.id === userId) {
    return res.status(404).json({ error: 'Пользователь не найден' });
  }
  const chat = store.createDirectChatIfNeeded(userId, other.id);
  const forSelf = store.serializeChatForViewer(chat, userId);
  const forPeer = store.serializeChatForViewer(chat, other.id);
  io.to(`user:${userId}`).emit('chat_updated', { chat: forSelf });
  io.to(`user:${other.id}`).emit('chat_updated', { chat: forPeer });
  res.json({ chat: forSelf });
});

app.post('/api/chats/group', requireAuth, (req, res) => {
  const userId = req.userId!;
  const { name, memberUsernames, memberIds } = req.body ?? {};
  if (typeof name !== 'string' || name.trim().length < 2) {
    return res.status(400).json({ error: 'Некорректное имя группы' });
  }
  const ids: string[] = [];
  const seen = new Set<string>();
  const addId = (id: string) => {
    if (!id || id === userId || seen.has(id)) return;
    const u = store.getUser(id);
    if (u) {
      seen.add(id);
      ids.push(id);
    }
  };
  if (Array.isArray(memberIds)) {
    for (const mid of memberIds) addId(String(mid));
  }
  if (Array.isArray(memberUsernames)) {
    for (const un of memberUsernames) {
      const u = store.findUserByUsername(String(un));
      if (u) addId(u.id);
    }
  }
  const chat = store.createGroupChat(userId, name.trim(), ids);
  chat.participantIds.forEach((pid) => {
    io.to(`user:${pid}`).emit('chat_updated', {
      chat: store.serializeChatForViewer(chat, pid),
    });
  });
  res.json({ chat: store.serializeChatForViewer(chat, userId) });
});

app.post('/api/chats/channel', requireAuth, (req, res) => {
  const userId = req.userId!;
  const { name, memberUsernames, memberIds } = req.body ?? {};
  if (typeof name !== 'string' || name.trim().length < 2) {
    return res.status(400).json({ error: 'Некорректное название канала' });
  }
  const ids: string[] = [];
  const seen = new Set<string>();
  const addId = (id: string) => {
    if (!id || id === userId || seen.has(id)) return;
    const u = store.getUser(id);
    if (u) {
      seen.add(id);
      ids.push(id);
    }
  };
  if (Array.isArray(memberIds)) {
    for (const mid of memberIds) addId(String(mid));
  }
  if (Array.isArray(memberUsernames)) {
    for (const un of memberUsernames) {
      const u = store.findUserByUsername(String(un));
      if (u) addId(u.id);
    }
  }
  const chat = store.createChannelChat(userId, name.trim(), ids);
  chat.participantIds.forEach((pid) => {
    io.to(`user:${pid}`).emit('chat_updated', {
      chat: store.serializeChatForViewer(chat, pid),
    });
  });
  res.json({ chat: store.serializeChatForViewer(chat, userId) });
});

app.patch('/api/chats/:chatId', requireAuth, (req, res) => {
  const userId = req.userId!;
  const chatId = req.params.chatId;
  const body = req.body ?? {};
  const patch: { name?: string; avatarUrl?: string | null } = {};
  if (typeof body.name === 'string') patch.name = body.name;
  if ('avatarUrl' in body) {
    const a = body.avatarUrl as string | null | undefined;
    if (a != null && typeof a === 'string' && a.length > MAX_AVATAR_LEN) {
      return res.status(400).json({ error: 'Слишком большое изображение' });
    }
    patch.avatarUrl = a ?? null;
  }
  if (Object.keys(patch).length === 0) {
    return res.status(400).json({ error: 'Нет данных' });
  }
  const updated = store.updateChatProfile(chatId, userId, patch);
  if (!updated) {
    return res.status(403).json({ error: 'Нет прав или чат не найден' });
  }
  broadcastChatToParticipants(chatId);
  res.json({ chat: store.serializeChatForViewer(updated, userId) });
});

app.post('/api/chats/:chatId/members', requireAuth, (req, res) => {
  const userId = req.userId!;
  const chatId = req.params.chatId;
  const raw = (req.body as { memberIds?: unknown })?.memberIds;
  const memberIds = Array.isArray(raw)
    ? raw.map((x) => String(x)).filter(Boolean)
    : [];
  const updated = store.addChatMembers(chatId, userId, memberIds);
  if (!updated) {
    return res.status(403).json({ error: 'Нет прав или чат не найден' });
  }
  broadcastChatToParticipants(chatId);
  res.json({ chat: store.serializeChatForViewer(updated, userId) });
});

app.delete('/api/chats/:chatId', requireAuth, (req, res) => {
  const userId = req.userId!;
  const chatId = req.params.chatId;
  const result = store.userLeavesChat(userId, chatId);
  if (!result) {
    return res.status(404).json({ error: 'Чат не найден' });
  }
  result.notifyDeletedFor.forEach((pid) => {
    io.to(`user:${pid}`).emit('chat_deleted', { chatId });
  });
  if (!result.fullDelete) {
    result.remainingParticipantIds.forEach((pid) => {
      const c = store.getChat(chatId);
      if (c) {
        io.to(`user:${pid}`).emit('chat_updated', {
          chat: store.serializeChatForViewer(c, pid),
        });
      }
    });
  }
  res.json({ ok: true });
});

// Push-уведомления
app.get('/api/push/vapid-public-key', (_req, res) => {
  res.json({ publicKey: VAPID_PUBLIC_KEY });
});

app.post('/api/push/subscribe', requireAuth, (req, res) => {
  const userId = req.userId!;
  const subscription = req.body as store.PushSubscriptionData;
  if (!subscription?.endpoint || !subscription?.keys?.p256dh || !subscription?.keys?.auth) {
    return res.status(400).json({ error: 'Некорректная подписка' });
  }
  store.addPushSubscription(userId, subscription);
  res.json({ ok: true });
});

app.post('/api/push/unsubscribe', requireAuth, (req, res) => {
  const userId = req.userId!;
  const { endpoint } = req.body as { endpoint?: string };
  if (!endpoint) {
    return res.status(400).json({ error: 'Требуется endpoint' });
  }
  store.removePushSubscription(userId, endpoint);
  res.json({ ok: true });
});

const __dirname = path.dirname(fileURLToPath(import.meta.url));
// Поднимаемся на 2 уровня вверх из server/dist -> корень проекта
const projectRoot = path.join(__dirname, '..');
const clientDist = path.join(projectRoot, 'client/dist');
console.log('Путь к client/dist:', clientDist);
console.log('Существует:', fs.existsSync(clientDist));
// Всегда раздаём статику, если папка существует
if (fs.existsSync(clientDist)) {
  app.use(express.static(clientDist));
  app.get('*', (_req, res) => {
    res.sendFile(path.join(clientDist, 'index.html'));
  });
}

server.listen(PORT, HOST, () => {
  console.log(`API & WebSocket (все интерфейсы): http://localhost:${PORT}`);
  const addrs = lanIPv4Addresses();
  if (addrs.length > 0) {
    console.log('В локальной сети откройте у друзей:');
    for (const ip of addrs) {
      console.log(`  http://${ip}:${PORT}`);
    }
  } else {
    console.log(
      '(LAN IP не найден — проверьте Wi‑Fi / кабель; firewall может блокировать порт.)'
    );
  }
});
