import fs from 'node:fs';
import crypto from 'node:crypto';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import './env.js';
import cors from 'cors';
import express from 'express';
import rateLimit from 'express-rate-limit';
import helmet from 'helmet';
import http from 'http';
import { Server } from 'socket.io';
import webpush from 'web-push';
import type { User } from './types.js';
import {
  AUTH_COOKIE_NAME,
  issueUserToken,
  requireAdmin,
  requireAuth,
  revokeTokenSession,
  tokenFromRequest,
  verifyUserToken,
} from './auth.js';
import {
  consumeChallenge,
  consumeLoginChallenge,
  createChallenge,
  isValidEmail,
  maskEmail,
  normalizeEmail,
} from './emailAuth.js';
import { sendAuthCodeEmail } from './email.js';
import * as store from './store.js';
import { bootstrapPersistence, startPeriodicPersistence } from './persist.js';
import { registerSocketHandlers } from './socketHandlers.js';
import { setupWebPush } from './pushNotifications.js';
import {
  initializeSessionStore,
  listUserSessions,
  revokeAllUserSessions,
  revokeOtherUserSessions,
  revokeUserSession,
} from './sessions.js';
import {
  hashPassword,
  isAcceptableNewPassword,
  PASSWORD_MAX_LENGTH,
  PASSWORD_MIN_LENGTH,
  verifyPassword,
} from './password.js';
import {
  initializeE2eeDevices,
  getE2eeKeyBackup,
  isValidE2eeKeyBackup,
  isValidCurve25519PublicKey,
  isValidDeviceId,
  listE2eeDevices,
  registerE2eeDevice,
  removeE2eeDevice,
  saveE2eeKeyBackup,
} from './e2eeDevices.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

await bootstrapPersistence();
await initializeSessionStore();
await initializeE2eeDevices();
startPeriodicPersistence();

// Настройка Web Push
const VAPID_PUBLIC_KEY = process.env.VAPID_PUBLIC_KEY?.trim() ?? '';
const VAPID_PRIVATE_KEY = process.env.VAPID_PRIVATE_KEY?.trim() ?? '';
const VAPID_SUBJECT =
  process.env.VAPID_SUBJECT?.trim() || 'mailto:no-reply@silentx.ru';

if (VAPID_PUBLIC_KEY && VAPID_PRIVATE_KEY) {
  setupWebPush(VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, VAPID_SUBJECT);
} else {
  console.warn('[push] VAPID keys are not configured; web push is disabled');
}

const MAX_AVATAR_LEN = 900_000;
const RESERVED_USERNAMES = new Set(['roz1es', 'elzi']);

function publicUser(u: User, includePrivate = true) {
  return {
    id: u.id,
    username: u.username,
    avatarUrl: u.avatarUrl,
    displayName: u.displayName,
    bio: u.bio,
    phone: u.phone,
    email: includePrivate || u.privacy?.showEmail ? u.email : undefined,
    emailVerified: !!u.emailVerified,
    birthDate: u.birthDate,
    isAdmin: !!u.isAdmin,
    banned: !!u.banned,
    privacy: u.privacy,
  };
}

function validUsernamePassword(username: unknown, password: unknown): boolean {
  return (
    typeof username === 'string' &&
    username.trim().length >= 2 &&
    isAcceptableNewPassword(password)
  );
}

async function sendChallengeCode(
  email: string,
  code: string,
  purpose: 'login' | 'register' | 'reset' | 'bind'
): Promise<void> {
  await sendAuthCodeEmail(email, code, purpose);
}

const PORT = Number(process.env.PORT) || 3002;
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
app.set('trust proxy', 1);

const allowedOrigins = new Set(
  (
    process.env.CLIENT_ORIGINS ??
    'https://silentx.ru,https://www.silentx.ru,http://localhost:5173,http://127.0.0.1:5173'
  )
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean)
);
const corsOrigin: cors.CorsOptions['origin'] = (origin, callback) => {
  if (!origin || allowedOrigins.has(origin)) callback(null, true);
  else callback(null, false);
};

app.use(
  helmet({
    contentSecurityPolicy: {
      directives: {
        defaultSrc: ["'self'"],
        baseUri: ["'self'"],
        objectSrc: ["'none'"],
        frameAncestors: ["'self'"],
        formAction: ["'self'"],
        scriptSrc: ["'self'", "'wasm-unsafe-eval'"],
        styleSrc: ["'self'", "'unsafe-inline'"],
        imgSrc: ["'self'", 'data:', 'blob:'],
        mediaSrc: ["'self'", 'data:', 'blob:'],
        fontSrc: ["'self'", 'data:'],
        connectSrc: ["'self'", 'https:', 'wss:', 'ws:'],
        workerSrc: ["'self'", 'blob:'],
        manifestSrc: ["'self'"],
        upgradeInsecureRequests:
          process.env.NODE_ENV === 'production' ? [] : null,
      },
    },
    crossOriginEmbedderPolicy: false,
  })
);
app.use(cors({ origin: corsOrigin, credentials: true }));
app.use(express.json({ limit: '50mb' }));

const server = http.createServer(app);
const io = new Server(server, {
  cors: { origin: corsOrigin, credentials: true },
  maxHttpBufferSize: 16 * 1024 * 1024,
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

const REMEMBER_COOKIE_MAX_AGE_MS = 30 * 24 * 60 * 60 * 1000;

async function respondWithAuthenticatedUser(
  res: express.Response,
  user: User,
  rememberMe = false
): Promise<void> {
  const token = await issueUserToken(user.id, rememberMe);
  res.cookie(AUTH_COOKIE_NAME, token, {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'strict',
    path: '/',
    ...(rememberMe ? { maxAge: REMEMBER_COOKIE_MAX_AGE_MS } : {}),
  });
  res.json({ user: publicUser(user) });
}

function disconnectSession(sessionId: string): void {
  for (const socket of io.sockets.sockets.values()) {
    if (socket.data.sessionId === sessionId) socket.disconnect(true);
  }
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

app.post('/api/register', authRouteLimiter, async (req, res) => {
  const { username, password, email } = req.body ?? {};
  if (!validUsernamePassword(username, password)) {
    return res.status(400).json({
      error: `Пароль должен содержать от ${PASSWORD_MIN_LENGTH} до ${PASSWORD_MAX_LENGTH} символов`,
    });
  }
  if (typeof email !== 'string' || !isValidEmail(email)) {
    return res.status(400).json({ error: 'Укажите корректную почту' });
  }
  const cleanUsername = username.trim();
  const cleanEmail = normalizeEmail(email);
  const unLower = cleanUsername.toLowerCase();
  if (RESERVED_USERNAMES.has(unLower)) {
    return res.status(403).json({ error: 'Это имя зарезервировано' });
  }
  if (store.findUserByUsername(cleanUsername)) {
    return res.status(409).json({ error: 'Имя пользователя занято' });
  }
  if (store.findUserByEmail(cleanEmail)) {
    return res.status(409).json({ error: 'Эта почта уже используется' });
  }
  let passwordHash: string;
  try {
    passwordHash = await hashPassword(password);
  } catch (err) {
    console.error('[auth] password hashing failed', err);
    return res.status(500).json({ error: 'Не удалось безопасно сохранить пароль' });
  }
  const { ticket, code } = createChallenge({
    purpose: 'register',
    username: cleanUsername,
    passwordHash,
    email: cleanEmail,
  });
  try {
    await sendChallengeCode(cleanEmail, code, 'register');
  } catch {
    return res.status(502).json({ error: 'Не удалось отправить письмо' });
  }
  res.json({
    emailVerificationRequired: true,
    ticket,
    emailMasked: maskEmail(cleanEmail),
  });
});

app.post('/api/register/confirm', authRouteLimiter, async (req, res) => {
  const { ticket, code } = req.body ?? {};
  if (typeof ticket !== 'string' || typeof code !== 'string') {
    return res.status(400).json({ error: 'Укажите код подтверждения' });
  }
  const challenge = consumeChallenge(ticket, code, 'register');
  if (!challenge) {
    return res.status(400).json({ error: 'Неверный или просроченный код' });
  }
  if (store.findUserByUsername(challenge.username)) {
    return res.status(409).json({ error: 'Имя пользователя занято' });
  }
  if (store.findUserByEmail(challenge.email)) {
    return res.status(409).json({ error: 'Эта почта уже используется' });
  }
  const user = store.createUser(
    challenge.username,
    challenge.passwordHash,
    challenge.email,
    true
  );
  store.ensureWelcomeChat(user.id);
  await respondWithAuthenticatedUser(res, user);
});

app.get('/api/me', requireAuth, (req, res) => {
  const userId = req.userId!;
  const u = store.getUser(userId);
  if (!u) return res.status(401).json({ error: 'Требуется авторизация' });
  res.json({ user: publicUser(u) });
});

app.get('/api/me/sessions', requireAuth, (req, res) => {
  res.json({
    sessions: listUserSessions(req.userId!, req.sessionId),
  });
});

app.delete('/api/me/sessions/:sessionId', requireAuth, async (req, res) => {
  const sessionId = req.params.sessionId;
  if (sessionId === req.sessionId) {
    return res.status(400).json({ error: 'Текущую сессию завершите через выход' });
  }
  const revoked = await revokeUserSession(req.userId!, sessionId);
  if (!revoked) {
    return res.status(404).json({ error: 'Сессия не найдена' });
  }
  disconnectSession(sessionId);
  res.json({ ok: true });
});

app.post('/api/me/sessions/revoke-others', requireAuth, async (req, res) => {
  const removedIds = await revokeOtherUserSessions(req.userId!, req.sessionId!);
  removedIds.forEach(disconnectSession);
  res.json({ ok: true, revoked: removedIds.length });
});

app.get('/api/calls/ice-servers', requireAuth, (req, res) => {
  const iceServers: Array<{
    urls: string | string[];
    username?: string;
    credential?: string;
  }> = [
    { urls: 'stun:stun.l.google.com:19302' },
    { urls: 'stun:stun1.l.google.com:19302' },
    { urls: 'stun:stun.cloudflare.com:3478' },
  ];
  const secret = process.env.TURN_SECRET?.trim();
  const urls = process.env.TURN_URLS?.split(',')
    .map((x) => x.trim())
    .filter(Boolean);
  if (secret && urls?.length) {
    const expires = Math.floor(Date.now() / 1000) + 60 * 60;
    const username = `${expires}:${req.userId}`;
    const credential = crypto
      .createHmac('sha1', secret)
      .update(username)
      .digest('base64');
    iceServers.push({ urls, username, credential });
  }
  res.json({ iceServers });
});

app.get('/api/admin/overview', requireAuth, requireAdmin, (_req, res) => {
  res.json(store.getAdminOverview());
});

app.get('/api/admin/database', requireAuth, requireAdmin, (_req, res) => {
  const url = process.env.PHPMYADMIN_URL?.trim();
  res.json({ url: url || null });
});

app.post('/api/admin/users/:userId/block', requireAuth, requireAdmin, async (req, res) => {
  const targetId = req.params.userId;
  const banned = Boolean((req.body as { banned?: boolean })?.banned);
  if (targetId === req.userId) {
    return res.status(400).json({ error: 'Нельзя заблокировать себя' });
  }
  const updated = store.setUserBlocked(targetId, banned);
  if (!updated) {
    return res.status(404).json({ error: 'Пользователь не найден' });
  }
  if (banned) {
    await revokeAllUserSessions(targetId);
    io.in(`user:${targetId}`).disconnectSockets(true);
  }
  res.json({ user: publicUser(updated) });
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
    privacy?: {
      showOnline?: boolean;
      allowCalls?: boolean;
      showEmail?: boolean;
    };
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
  if ('privacy' in body) {
    const privacy = body.privacy as
      | {
          showOnline?: unknown;
          allowCalls?: unknown;
          showEmail?: unknown;
        }
      | undefined;
    if (!privacy || typeof privacy !== 'object') {
      return res.status(400).json({ error: 'Некорректные настройки приватности' });
    }
    patch.privacy = {
      showOnline: privacy.showOnline !== false,
      allowCalls: privacy.allowCalls !== false,
      showEmail: privacy.showEmail === true,
    };
  }
  if (Object.keys(patch).length === 0) {
    return res.status(400).json({ error: 'Укажите поля профиля' });
  }
  store.updateUserProfile(userId, patch);
  const fresh = store.getUser(userId);
  if (!fresh) return res.status(500).json({ error: 'Ошибка' });
  res.json({ user: publicUser(fresh) });
});

app.post('/api/me/email/request', authRouteLimiter, requireAuth, async (req, res) => {
  const userId = req.userId!;
  const { email } = req.body ?? {};
  if (typeof email !== 'string' || !isValidEmail(email)) {
    return res.status(400).json({ error: 'Укажите корректную почту' });
  }
  const cleanEmail = normalizeEmail(email);
  const existing = store.findUserByEmail(cleanEmail);
  if (existing && existing.id !== userId) {
    return res.status(409).json({ error: 'Эта почта уже используется' });
  }
  const { ticket, code } = createChallenge({
    purpose: 'bind',
    userId,
    email: cleanEmail,
  });
  try {
    await sendChallengeCode(cleanEmail, code, 'bind');
  } catch {
    return res.status(502).json({ error: 'Не удалось отправить письмо' });
  }
  res.json({
    ticket,
    emailMasked: maskEmail(cleanEmail),
  });
});

app.post('/api/me/email/confirm', authRouteLimiter, requireAuth, (req, res) => {
  const userId = req.userId!;
  const { ticket, code } = req.body ?? {};
  if (typeof ticket !== 'string' || typeof code !== 'string') {
    return res.status(400).json({ error: 'Укажите код подтверждения' });
  }
  const challenge = consumeChallenge(ticket, code, 'bind');
  if (!challenge || challenge.userId !== userId) {
    return res.status(400).json({ error: 'Неверный или просроченный код' });
  }
  const existing = store.findUserByEmail(challenge.email);
  if (existing && existing.id !== userId) {
    return res.status(409).json({ error: 'Эта почта уже используется' });
  }
  const fresh = store.updateUserEmail(userId, challenge.email, true);
  if (!fresh) return res.status(404).json({ error: 'Пользователь не найден' });
  res.json({ user: publicUser(fresh) });
});

app.get('/api/users/directory', requireAuth, (req, res) => {
  const userId = req.userId!;
  const me = store.getUser(userId);
  res.json({
    users: me?.isAdmin
      ? store.listDirectoryUsers(userId)
      : store.listContactUsers(userId),
  });
});

app.get('/api/users/contacts', requireAuth, (req, res) => {
  const userId = req.userId!;
  res.json({ users: store.listContactUsers(userId) });
});

app.get('/api/users/search', requireAuth, (req, res) => {
  const userId = req.userId!;
  const query = String(req.query.q ?? req.query.username ?? '');
  res.json({ users: store.searchDirectoryUsers(userId, query) });
});

app.get('/api/users/:userId', requireAuth, (req, res) => {
  const viewerId = req.userId!;
  const targetId = req.params.userId;
  const target = store.getUser(targetId);
  if (!target) return res.status(404).json({ error: 'Пользователь не найден' });
  if (!store.usersShareChat(viewerId, targetId)) {
    return res.status(403).json({ error: 'Нет доступа к профилю' });
  }
  res.json({ user: publicUser(target, viewerId === targetId) });
});

app.post('/api/login', authRouteLimiter, async (req, res) => {
  const { username, password, rememberMe } = req.body ?? {};
  const remember = rememberMe === true;
  if (
    typeof username !== 'string' ||
    typeof password !== 'string' ||
    password.length > PASSWORD_MAX_LENGTH
  ) {
    return res.status(401).json({ error: 'Неверный логин или пароль' });
  }
  const u = store.findUserByUsername(String(username ?? ''));
  const passwordCheck = u
    ? await verifyPassword(u.password, password)
    : { valid: false, needsRehash: false };
  if (!u || !passwordCheck.valid) {
    return res.status(401).json({ error: 'Неверный логин или пароль' });
  }
  if (passwordCheck.needsRehash) {
    try {
      store.updateUserPassword(u.id, await hashPassword(password));
    } catch (err) {
      console.error('[auth] legacy password migration failed', err);
      return res.status(500).json({ error: 'Не удалось обновить защиту пароля' });
    }
  }
  if (u.banned) {
    return res.status(403).json({ error: 'Аккаунт заблокирован' });
  }
  if (u.email && u.emailVerified) {
    if (u.isAdmin && process.env.ALLOW_ADMIN_LOGIN_WITHOUT_EMAIL === 'true') {
      console.warn(
        `[auth] admin email login code is temporarily bypassed for ${u.username}`
      );
      await respondWithAuthenticatedUser(res, u, remember);
      return;
    }
    const { ticket, code } = createChallenge({
      purpose: 'login',
      userId: u.id,
    });
    try {
      await sendChallengeCode(u.email, code, 'login');
    } catch (err) {
      console.error('[email] login code delivery failed', err);
      if (u.isAdmin && process.env.ALLOW_ADMIN_LOGIN_WITHOUT_EMAIL === 'true') {
        console.warn(
          `[auth] email delivery failed, allowing admin password login for ${u.username}`
        );
        await respondWithAuthenticatedUser(res, u, remember);
        return;
      }
      return res.status(502).json({ error: 'Не удалось отправить письмо' });
    }
    return res.json({
      emailCodeRequired: true,
      ticket,
      emailMasked: maskEmail(u.email),
    });
  }
  await respondWithAuthenticatedUser(res, u, remember);
});

app.post('/api/login/confirm', authRouteLimiter, async (req, res) => {
  const { ticket, code, rememberMe } = req.body ?? {};
  if (typeof ticket !== 'string' || typeof code !== 'string') {
    return res.status(400).json({ error: 'Укажите код подтверждения' });
  }
  const challenge = consumeLoginChallenge(ticket, code);
  if (!challenge) {
    return res.status(400).json({ error: 'Неверный или просроченный код' });
  }
  const u = store.getUser(challenge.userId);
  if (!u) return res.status(404).json({ error: 'Пользователь не найден' });
  if (u.banned) {
    return res.status(403).json({ error: 'Аккаунт заблокирован' });
  }
  await respondWithAuthenticatedUser(res, u, rememberMe === true);
});

app.post('/api/logout', async (req, res) => {
  const token = tokenFromRequest(req);
  const authenticated = token ? verifyUserToken(token) : null;
  await revokeTokenSession(token);
  if (authenticated) disconnectSession(authenticated.sessionId);
  res.clearCookie(AUTH_COOKIE_NAME, {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'strict',
    path: '/',
  });
  res.json({ ok: true });
});

app.post('/api/password-reset/request', authRouteLimiter, async (req, res) => {
  const login = String((req.body as { login?: unknown })?.login ?? '').trim();
  const u =
    store.findUserByUsername(login) ||
    (isValidEmail(login) ? store.findUserByEmail(normalizeEmail(login)) : undefined);
  if (!u?.email || !u.emailVerified) {
    return res.json({
      ok: true,
      message: 'Если почта привязана к аккаунту, мы отправили код.',
    });
  }
  const { ticket, code } = createChallenge({
    purpose: 'reset',
    userId: u.id,
  });
  try {
    await sendChallengeCode(u.email, code, 'reset');
  } catch {
    return res.status(502).json({ error: 'Не удалось отправить письмо' });
  }
  res.json({
    ok: true,
    ticket,
    emailMasked: maskEmail(u.email),
  });
});

app.post('/api/password-reset/confirm', authRouteLimiter, async (req, res) => {
  const { ticket, code, password } = req.body ?? {};
  if (
    typeof ticket !== 'string' ||
    typeof code !== 'string' ||
    !isAcceptableNewPassword(password)
  ) {
    return res.status(400).json({
      error: `Пароль должен содержать от ${PASSWORD_MIN_LENGTH} до ${PASSWORD_MAX_LENGTH} символов`,
    });
  }
  const challenge = consumeChallenge(ticket, code, 'reset');
  if (!challenge) {
    return res.status(400).json({ error: 'Неверный или просроченный код' });
  }
  let passwordHash: string;
  try {
    passwordHash = await hashPassword(password);
  } catch (err) {
    console.error('[auth] password reset hashing failed', err);
    return res.status(500).json({ error: 'Не удалось безопасно сохранить пароль' });
  }
  const u = store.updateUserPassword(challenge.userId, passwordHash);
  if (!u) return res.status(404).json({ error: 'Пользователь не найден' });
  await revokeAllUserSessions(u.id);
  io.in(`user:${u.id}`).disconnectSockets(true);
  res.json({ ok: true });
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

app.post('/api/e2ee/devices', requireAuth, async (req, res) => {
  const userId = req.userId!;
  const { deviceId, publicKey } = req.body as {
    deviceId?: unknown;
    publicKey?: unknown;
  };
  if (
    !isValidDeviceId(deviceId) ||
    !isValidCurve25519PublicKey(publicKey)
  ) {
    return res.status(400).json({ error: 'Некорректный ключ устройства' });
  }
  const result = await registerE2eeDevice(userId, deviceId, publicKey);
  if (result === 'key-mismatch') {
    return res.status(409).json({
      error: 'Ключ этого устройства изменился. Создайте новый идентификатор.',
    });
  }
  if (result === 'limit') {
    return res.status(409).json({
      error: 'Достигнут лимит защищённых устройств',
    });
  }
  res.json({ ok: true, deviceId });
});

app.get('/api/e2ee/key-backup', requireAuth, (req, res) => {
  res.json({ backup: getE2eeKeyBackup(req.userId!) ?? null });
});

app.put('/api/e2ee/key-backup', requireAuth, async (req, res) => {
  const value = {
    ...(req.body ?? {}),
    updatedAt: Date.now(),
  };
  if (!isValidE2eeKeyBackup(value)) {
    return res.status(400).json({ error: 'Некорректная копия ключа' });
  }
  await saveE2eeKeyBackup(req.userId!, {
    version: 1,
    salt: value.salt,
    iv: value.iv,
    ciphertext: value.ciphertext,
    iterations: value.iterations,
  });
  res.json({ ok: true });
});

app.delete('/api/e2ee/devices/:deviceId', requireAuth, async (req, res) => {
  const deviceId = req.params.deviceId;
  if (!isValidDeviceId(deviceId)) {
    return res.status(400).json({ error: 'Некорректное устройство' });
  }
  await removeE2eeDevice(req.userId!, deviceId);
  res.json({ ok: true });
});

app.get('/api/chats/:chatId/e2ee-devices', requireAuth, (req, res) => {
  const userId = req.userId!;
  const chat = store.getChat(req.params.chatId);
  if (
    !chat?.participantIds.includes(userId) ||
    chat.type !== 'direct'
  ) {
    return res.status(404).json({ error: 'Личный чат не найден' });
  }
  res.json({
    chatId: chat.id,
    participantIds: chat.participantIds,
    devices: listE2eeDevices(chat.participantIds),
  });
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
  if (!other || other.id === userId || other.banned) {
    return res.status(404).json({ error: 'Пользователь не найден' });
  }
  const chat = store.createDirectChatIfNeeded(userId, other.id);
  const forSelf = store.serializeChatForViewer(chat, userId);
  const forPeer = store.serializeChatForViewer(chat, other.id);
  io.to(`user:${userId}`).emit('chat_updated', { chat: forSelf });
  io.to(`user:${other.id}`).emit('chat_updated', { chat: forPeer });
  res.json({ chat: forSelf });
});

app.post('/api/chats/saved', requireAuth, (req, res) => {
  const userId = req.userId!;
  const chat = store.ensureSavedChat(userId);
  const forSelf = store.serializeChatForViewer(chat, userId);
  io.to(`user:${userId}`).emit('chat_updated', { chat: forSelf });
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

app.post('/api/chats/:chatId/admins', requireAuth, (req, res) => {
  const userId = req.userId!;
  const chatId = req.params.chatId;
  const body = req.body ?? {};
  const targetUserId = String(body.userId ?? '');
  const admin = body.admin === true;
  if (!targetUserId) {
    return res.status(400).json({ error: 'Укажите пользователя' });
  }
  const updated = store.setChannelAdmin(chatId, userId, targetUserId, admin);
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
  if (!VAPID_PUBLIC_KEY) {
    return res.status(503).json({ error: 'Push-уведомления не настроены' });
  }
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

// Поднимаемся на 3 уровня вверх из server/dist/src -> server/dist -> server -> корень проекта
const projectRoot = path.join(__dirname, '../..');
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
