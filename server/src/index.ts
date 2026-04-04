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
import type { User } from './types.js';
import { requireAuth, signUserToken } from './auth.js';
import * as store from './store.js';
import { registerSocketHandlers } from './socketHandlers.js';

const MAX_AVATAR_LEN = 900_000;

function publicUser(u: User) {
  return {
    id: u.id,
    username: u.username,
    avatarUrl: u.avatarUrl,
    displayName: u.displayName,
    bio: u.bio,
  };
}

function participantRow(id: string) {
  const p = store.getUser(id);
  return {
    id,
    username: p?.username ?? 'User',
    displayName: p?.displayName,
    avatarUrl: p?.avatarUrl,
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

app.patch('/api/me', requireAuth, (req, res) => {
  const userId = req.userId!;
  const u = store.getUser(userId);
  if (!u) return res.status(401).json({ error: 'Требуется авторизация' });
  const body = req.body ?? {};
  const patch: {
    avatarUrl?: string | null;
    bio?: string | null;
    displayName?: string | null;
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
  if (Object.keys(patch).length === 0) {
    return res.status(400).json({ error: 'Укажите поля профиля' });
  }
  store.updateUserProfile(userId, patch);
  const fresh = store.getUser(userId);
  if (!fresh) return res.status(500).json({ error: 'Ошибка' });
  res.json({ user: publicUser(fresh) });
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
  const list = store.getChatsForUser(userId).map((c) => ({
    ...c,
    displayName:
      c.type === 'group'
        ? c.name
        : c.participantIds
            .filter((id) => id !== userId)
            .map((id) => {
              const p = store.getUser(id);
              if (!p) return 'User';
              const label = p.displayName?.trim() || p.username;
              return label;
            })
            .join(', ') || c.name,
    participants: c.participantIds.map((id) => participantRow(id)),
  }));
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

app.post('/api/chats/direct', requireAuth, (req, res) => {
  const userId = req.userId!;
  const { targetUsername } = req.body ?? {};
  const other = store.findUserByUsername(String(targetUsername ?? ''));
  if (!other || other.id === userId) {
    return res.status(404).json({ error: 'Пользователь не найден' });
  }
  const chat = store.createDirectChatIfNeeded(userId, other.id);
  res.json({
    chat: {
      ...chat,
      displayName: other.displayName?.trim() || other.username,
      participants: chat.participantIds.map((id) => participantRow(id)),
    },
  });
});

app.post('/api/chats/group', requireAuth, (req, res) => {
  const userId = req.userId!;
  const { name, memberUsernames } = req.body ?? {};
  if (typeof name !== 'string' || name.trim().length < 2) {
    return res.status(400).json({ error: 'Некорректное имя группы' });
  }
  const ids: string[] = [];
  if (Array.isArray(memberUsernames)) {
    for (const un of memberUsernames) {
      const u = store.findUserByUsername(String(un));
      if (u && u.id !== userId) ids.push(u.id);
    }
  }
  const chat = store.createGroupChat(userId, name.trim(), ids);
  res.json({
    chat: {
      ...chat,
      participants: chat.participantIds.map((id) => participantRow(id)),
    },
  });
});

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const clientDist = path.join(__dirname, '../../client/dist');
if (process.env.NODE_ENV === 'production' && fs.existsSync(clientDist)) {
  app.use(express.static(clientDist));
  app.get('*', (_req, res) => {
    res.sendFile(path.join(clientDist, 'index.html'));
  });
}

const server = http.createServer(app);
const io = new Server(server, {
  cors: { origin: true, credentials: true },
});

registerSocketHandlers(io);

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
