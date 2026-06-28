import { v4 as uuid } from 'uuid';
import type { Chat, Message, User } from './types.js';
import {
  DISABLED_PASSWORD,
  hashPassword,
  isPasswordHash,
} from './password.js';

export type PushSubscriptionData = {
  endpoint: string;
  keys: {
    p256dh: string;
    auth: string;
  };
};

export type ChatParticipantRow = {
  id: string;
  username: string;
  displayName?: string;
  avatarUrl?: string;
  privacy?: {
    showOnline?: boolean;
    allowCalls?: boolean;
    showEmail?: boolean;
  };
};

export type SerializedChat = Omit<Chat, 'pinnedMessageId'> & {
  displayName: string;
  participants: ChatParticipantRow[];
  muted: boolean;
  pinnedToTop: boolean;
  /** Всегда в JSON (в т.ч. null), чтобы клиент снимал закреп сообщения */
  pinnedMessageId: string | null;
};

export function previewForMessage(msg: Message): string {
  if (msg.encryptedText) return 'Сообщение';
  if (msg.media) {
    switch (msg.media.kind) {
      case 'image':
        return '📷 Фото';
      case 'file':
        return `📎 ${msg.media.fileName ?? 'Файл'}`;
      case 'voice':
        return '🎤 Голосовое';
      case 'video_note':
        return '🎬 Видеокружок';
      default:
        return 'Сообщение';
    }
  }
  if (msg.imageUrl) return '📷 Фото';
  return msg.text.slice(0, 120) || 'Сообщение';
}

const users = new Map<string, User>();
const chats = new Map<string, Chat>();
const messagesByChat = new Map<string, Message[]>();
/** userId -> Set<chatId> без уведомлений */
const mutedChatsByUser = new Map<string, Set<string>>();
/** userId -> Set<chatId> закреплённые вверху списка */
const pinnedChatsByUser = new Map<string, Set<string>>();
/** userId -> PushSubscriptionData[] (устройства пользователя) */
const pushSubscriptionsByUser = new Map<string, PushSubscriptionData[]>();

function mutedSet(userId: string): Set<string> {
  let s = mutedChatsByUser.get(userId);
  if (!s) {
    s = new Set();
    mutedChatsByUser.set(userId, s);
  }
  return s;
}

function pinnedSet(userId: string): Set<string> {
  let s = pinnedChatsByUser.get(userId);
  if (!s) {
    s = new Set();
    pinnedChatsByUser.set(userId, s);
  }
  return s;
}

export function setChatMutedForUser(
  userId: string,
  chatId: string,
  muted: boolean
): void {
  const s = mutedSet(userId);
  if (muted) s.add(chatId);
  else s.delete(chatId);
}

export function isChatMutedForUser(userId: string, chatId: string): boolean {
  return mutedChatsByUser.get(userId)?.has(chatId) ?? false;
}

export function setChatPinnedTopForUser(
  userId: string,
  chatId: string,
  pinned: boolean
): void {
  const s = pinnedSet(userId);
  if (pinned) s.add(chatId);
  else s.delete(chatId);
}

export function isChatPinnedTopForUser(userId: string, chatId: string): boolean {
  return pinnedChatsByUser.get(userId)?.has(chatId) ?? false;
}

function rowForParticipant(id: string): ChatParticipantRow {
  const p = users.get(id);
  return {
    id,
    username: p?.username ?? 'User',
    displayName: p?.displayName,
    avatarUrl: p?.avatarUrl,
    privacy: p?.privacy,
  };
}

/** Чат с именем и участниками с точки зрения конкретного пользователя (сокеты и API). */
export function serializeChatForViewer(
  chat: Chat,
  viewerId: string
): SerializedChat {
  const participants = chat.participantIds.map((id) => rowForParticipant(id));
  const displayName =
    chat.type === 'group' || chat.type === 'channel'
      ? chat.name
      : chat.participantIds
          .filter((id) => id !== viewerId)
          .map((id) => {
            const p = users.get(id);
            if (!p) return 'User';
            return p.displayName?.trim() || p.username;
          })
          .join(', ') || chat.name;
  return {
    ...chat,
    displayName,
    participants,
    muted: isChatMutedForUser(viewerId, chat.id),
    pinnedToTop: isChatPinnedTopForUser(viewerId, chat.id),
    pinnedMessageId: chat.pinnedMessageId ?? null,
    // Важно: undefined не сериализуется в JSON, из-за чего клиент не может
    // "сбросить" lastMessage после очистки чата. Поэтому отдаём null явно.
    lastMessage: chat.lastMessage
      ? {
          ...chat.lastMessage,
          text:
            chat.lastMessage.text === 'Защищённое сообщение' ||
            chat.lastMessage.text === 'Защищенное сообщение' ||
            chat.lastMessage.text === 'Пробуем расшифровать сообщение…' ||
            chat.lastMessage.text === 'Ожидается восстановление ключа шифрования' ||
            chat.lastMessage.text === 'Не удалось расшифровать защищённое сообщение' ||
            chat.lastMessage.text === 'Не удалось расшифровать защищенное сообщение' ||
            chat.lastMessage.text === 'Новое сообщение'
              ? 'Сообщение'
              : chat.lastMessage.text,
        }
      : null,
  };
}

/** Все пользователи кроме себя — для выбора в новом чате / группе. */
export function listDirectoryUsers(excludeUserId: string): ChatParticipantRow[] {
  return [...users.values()]
    .filter((u) => u.id !== excludeUserId && !u.banned)
    .map((u) => ({
      id: u.id,
      username: u.username,
      displayName: u.displayName,
      avatarUrl: u.avatarUrl,
      privacy: u.privacy,
    }))
    .sort((a, b) => {
      const la = (a.displayName?.trim() || a.username).toLowerCase();
      const lb = (b.displayName?.trim() || b.username).toLowerCase();
      return la.localeCompare(lb, 'ru');
    });
}

export function searchDirectoryUsers(
  viewerId: string,
  query: string,
  limit = 8
): ChatParticipantRow[] {
  const raw = query.trim();
  const q = raw.replace(/^@+/, '').toLowerCase();
  if (q.length < 2) return [];
  const searchByUsername = raw.startsWith('@') || !raw.startsWith('id:');
  const idQuery = raw.toLowerCase().startsWith('id:')
    ? raw.slice(3).trim().toLowerCase()
    : q;
  return listDirectoryUsers(viewerId)
    .filter((u) => {
      const usernameMatches =
        searchByUsername && u.username.toLowerCase().includes(q);
      const idMatches =
        idQuery.length >= 6 && u.id.toLowerCase().includes(idQuery);
      return usernameMatches || idMatches;
    })
    .slice(0, limit);
}

export function usersShareDirectChat(a: string, b: string): boolean {
  if (a === b) return true;
  for (const c of chats.values()) {
    if (
      c.type === 'direct' &&
      c.participantIds.includes(a) &&
      c.participantIds.includes(b)
    ) {
      return true;
    }
  }
  return false;
}

function canAddContactToSharedChat(requesterId: string, targetId: string): boolean {
  const requester = users.get(requesterId);
  if (requester?.isAdmin) return users.has(targetId);
  return usersShareDirectChat(requesterId, targetId);
}

export function listContactUsers(userId: string): ChatParticipantRow[] {
  const ids = new Set<string>();
  for (const c of chats.values()) {
    if (c.type !== 'direct' || !c.participantIds.includes(userId)) continue;
    c.participantIds.forEach((id) => {
      if (id !== userId) ids.add(id);
    });
  }
  return [...ids]
    .map((id) => users.get(id))
    .filter((u): u is User => Boolean(u && !u.banned))
    .map((u) => ({
      id: u.id,
      username: u.username,
      displayName: u.displayName,
      avatarUrl: u.avatarUrl,
      privacy: u.privacy,
    }))
    .sort((a, b) => {
      const la = (a.displayName?.trim() || a.username).toLowerCase();
      const lb = (b.displayName?.trim() || b.username).toLowerCase();
      return la.localeCompare(lb, 'ru');
    });
}

function ensureMessages(chatId: string): Message[] {
  let list = messagesByChat.get(chatId);
  if (!list) {
    list = [];
    messagesByChat.set(chatId, list);
  }
  return list;
}

/** Зарезервированные администраторы без встроенных паролей. */
const BUILTIN_ADMIN_ACCOUNTS: Array<Pick<User, 'id' | 'username' | 'isAdmin'>> = [
  {
    id: 'user-admin-roz1es',
    username: 'roz1es',
    isAdmin: true,
  },
  {
    id: 'user-admin-elzi',
    username: 'ELZI',
    isAdmin: true,
  },
];

/** Синхронизация флагов администраторов без изменения существующих паролей. */
export function ensureBuiltinAccounts(): void {
  for (const spec of BUILTIN_ADMIN_ACCOUNTS) {
    const byId = users.get(spec.id);
    if (byId) {
      byId.isAdmin = true;
      byId.username = spec.username;
      continue;
    }
    users.set(spec.id, { ...spec, password: DISABLED_PASSWORD });
  }

  const bot =
    users.get('user-bot') ??
    [...users.values()].find((u) =>
      ['silentx', 'brenkschat'].includes(u.username.toLowerCase())
    );
  if (bot) {
    bot.username = 'brenkschat';
    bot.displayName = 'БренксЧат';
    bot.password = DISABLED_PASSWORD;
    for (const chat of chats.values()) {
      if (chat.type !== 'direct' || !chat.participantIds.includes(bot.id)) continue;
      if (['silentx', 'brenkschat'].includes(chat.name.toLowerCase())) {
        chat.name = 'БренксЧат';
      }
      for (const message of messagesByChat.get(chat.id) ?? []) {
        if (
          message.senderId === bot.id &&
          /демо-мессенджер (?:SilentX|Silentix|BrenksChat)/i.test(message.text)
        ) {
          message.text = 'Добро пожаловать в БренксЧат!';
        }
      }
    }
  }
}

function seed() {
  const bot: User = {
    id: 'user-bot',
    username: 'brenkschat',
    displayName: 'БренксЧат',
    password: DISABLED_PASSWORD,
  };
  users.set(bot.id, bot);
  for (const a of BUILTIN_ADMIN_ACCOUNTS) {
    users.set(a.id, { ...a, password: DISABLED_PASSWORD });
  }
}

/**
 * Одноразово переводит старые открытые пароли в Argon2id.
 * Возвращает количество изменённых учётных записей.
 */
export async function migrateLegacyPasswords(): Promise<number> {
  let migrated = 0;
  for (const user of users.values()) {
    if (user.password === DISABLED_PASSWORD || isPasswordHash(user.password)) {
      continue;
    }
    user.password = user.password
      ? await hashPassword(user.password)
      : DISABLED_PASSWORD;
    migrated += 1;
  }
  return migrated;
}

export type PersistedStateV1 = {
  v: 1;
  users: User[];
  chats: Chat[];
  messagesByChat: [string, Message[]][];
  muted: [string, string[]][];
  pinned: [string, string[]][];
  pushSubscriptions: [string, PushSubscriptionData[]][];
};

export function exportPersistedState(): PersistedStateV1 {
  return {
    v: 1,
    users: [...users.values()],
    chats: [...chats.values()],
    messagesByChat: [...messagesByChat.entries()],
    muted: [...mutedChatsByUser.entries()].map(([k, v]) => [k, [...v]]),
    pinned: [...pinnedChatsByUser.entries()].map(([k, v]) => [k, [...v]]),
    pushSubscriptions: [...pushSubscriptionsByUser.entries()].map(([k, v]) => [k, [...v]]),
  };
}

export function importPersistedState(data: PersistedStateV1): void {
  users.clear();
  chats.clear();
  messagesByChat.clear();
  mutedChatsByUser.clear();
  pinnedChatsByUser.clear();
  pushSubscriptionsByUser.clear();
  for (const u of data.users) users.set(u.id, u);
  for (const c of data.chats) chats.set(c.id, c);
  for (const [id, arr] of data.messagesByChat) {
    messagesByChat.set(id, [...arr]);
  }
  for (const [uid, ids] of data.muted) {
    mutedChatsByUser.set(uid, new Set(ids));
  }
  for (const [uid, ids] of data.pinned) {
    pinnedChatsByUser.set(uid, new Set(ids));
  }
  for (const [uid, subs] of data.pushSubscriptions ?? []) {
    pushSubscriptionsByUser.set(uid, [...subs]);
  }
}

/** Первый запуск без файла состояния */
export function seedDatabase(): void {
  seed();
}

export function findUserByUsername(username: string): User | undefined {
  return [...users.values()].find(
    (u) => u.username.toLowerCase() === username.toLowerCase()
  );
}

export function findUserByEmail(email: string): User | undefined {
  const normalized = email.trim().toLowerCase();
  return [...users.values()].find((u) => u.email?.toLowerCase() === normalized);
}

export function createUser(
  username: string,
  passwordHash: string,
  email?: string,
  emailVerified = false
): User {
  if (!isPasswordHash(passwordHash)) {
    throw new Error('createUser requires an Argon2id password hash');
  }
  const user: User = {
    id: uuid(),
    username,
    password: passwordHash,
    email,
    emailVerified: email ? emailVerified : undefined,
  };
  users.set(user.id, user);
  return user;
}

export function updateUserPassword(
  userId: string,
  passwordHash: string
): User | undefined {
  if (!isPasswordHash(passwordHash)) {
    throw new Error('updateUserPassword requires an Argon2id password hash');
  }
  const u = users.get(userId);
  if (!u) return undefined;
  u.password = passwordHash;
  return u;
}

export function updateUserEmail(
  userId: string,
  email: string,
  verified: boolean
): User | undefined {
  const u = users.get(userId);
  if (!u) return undefined;
  u.email = email;
  u.emailVerified = verified;
  return u;
}

export function updateUserAvatar(
  userId: string,
  avatarUrl: string | undefined
): User | undefined {
  const u = users.get(userId);
  if (!u) return undefined;
  u.avatarUrl = avatarUrl && avatarUrl.length > 0 ? avatarUrl : undefined;
  return u;
}

export function updateUserProfile(
  userId: string,
  patch: {
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
  }
): User | undefined {
  const u = users.get(userId);
  if (!u) return undefined;
  if ('avatarUrl' in patch) {
    const v = patch.avatarUrl;
    u.avatarUrl = v && typeof v === 'string' && v.length > 0 ? v : undefined;
  }
  if ('bio' in patch) {
    const b = patch.bio;
    u.bio =
      typeof b === 'string' && b.trim().length > 0
        ? b.trim().slice(0, 500)
        : undefined;
  }
  if ('displayName' in patch) {
    const d = patch.displayName;
    u.displayName =
      typeof d === 'string' && d.trim().length > 0
        ? d.trim().slice(0, 64)
        : undefined;
  }
  if ('phone' in patch) {
    const p = patch.phone;
    u.phone =
      typeof p === 'string' && p.trim().length > 0
        ? p.trim().slice(0, 32)
        : undefined;
  }
  if ('birthDate' in patch) {
    const bd = patch.birthDate;
    if (bd == null || bd === '') u.birthDate = undefined;
    else if (typeof bd === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(bd.trim())) {
      u.birthDate = bd.trim();
    }
  }
  if ('privacy' in patch && patch.privacy) {
    u.privacy = {
      showOnline: patch.privacy.showOnline !== false,
      allowCalls: patch.privacy.allowCalls !== false,
      showEmail: patch.privacy.showEmail === true,
    };
  }
  return u;
}

export function setUserBlocked(userId: string, banned: boolean): User | undefined {
  const u = users.get(userId);
  if (!u || u.isAdmin) return undefined;
  u.banned = banned ? true : undefined;
  return u;
}

export function usersShareChat(a: string, b: string): boolean {
  if (a === b) return true;
  for (const c of chats.values()) {
    if (c.participantIds.includes(a) && c.participantIds.includes(b)) return true;
  }
  return false;
}

export function getUser(id: string): User | undefined {
  return users.get(id);
}

export function getChatsForUser(userId: string): Chat[] {
  return [...chats.values()].filter((c) => c.participantIds.includes(userId));
}

export function getChat(chatId: string): Chat | undefined {
  return chats.get(chatId);
}

export function getMessages(chatId: string): Message[] {
  return ensureMessages(chatId).filter((m) => !m.deleted);
}

export function addMessage(msg: Message): void {
  ensureMessages(msg.chatId).push(msg);
  const chat = chats.get(msg.chatId);
  if (!chat) return;
  const previewText = previewForMessage(msg);
  chat.lastMessage = {
    text: previewText,
    time: msg.createdAt,
    senderId: msg.senderId,
  };
  chat.participantIds.forEach((pid) => {
    if (pid !== msg.senderId) {
      chat.unread[pid] = (chat.unread[pid] ?? 0) + 1;
    }
  });
}

export function toggleMessageReaction(
  chatId: string,
  messageId: string,
  userId: string,
  emoji: string
): Message | undefined {
  const allowed = new Set(['👍', '❤️', '😂', '🔥', '😮']);
  if (!allowed.has(emoji)) return undefined;
  const list = ensureMessages(chatId);
  const msg = list.find((m) => m.id === messageId);
  if (!msg || msg.deleted) return undefined;
  const next = { ...(msg.reactions ?? {}) };
  for (const key of Object.keys(next)) {
    next[key] = next[key].filter((id) => id !== userId);
    if (next[key].length === 0) delete next[key];
  }
  const cur = next[emoji] ?? [];
  if (!msg.reactions?.[emoji]?.includes(userId)) {
    next[emoji] = [...cur, userId];
  }
  msg.reactions = Object.keys(next).length > 0 ? next : undefined;
  return msg;
}

function updateLastMessageForChat(chatId: string): void {
  const chat = chats.get(chatId);
  if (!chat) return;
  const list = ensureMessages(chatId);
  const last = [...list].reverse().find((m) => !m.deleted);
  chat.lastMessage = last
    ? {
        text: previewForMessage(last),
        time: last.createdAt,
        senderId: last.senderId,
      }
    : undefined;
}

export function markChatRead(chatId: string, userId: string): Chat | undefined {
  const chat = chats.get(chatId);
  if (!chat) return undefined;
  chat.unread[userId] = 0;
  const list = ensureMessages(chatId);
  const lastTime =
    list.length > 0 ? Math.max(...list.map((m) => m.createdAt)) : Date.now();
  if (!chat.lastReadAt) chat.lastReadAt = {};
  chat.lastReadAt[userId] = lastTime;
  return chat;
}

export function softDeleteMessage(
  chatId: string,
  messageId: string,
  requesterId: string
): Message | undefined {
  const list = ensureMessages(chatId);
  const msg = list.find((m) => m.id === messageId);
  if (!msg || msg.senderId !== requesterId) return undefined;
  msg.deleted = true;
  const chat = chats.get(chatId);
  if (chat?.lastMessage?.time === msg.createdAt) {
    updateLastMessageForChat(chatId);
  }
  if (chat?.pinnedMessageId === messageId) {
    chat.pinnedMessageId = undefined;
  }
  return msg;
}

const MAX_MSG_LEN = 12_000;

export function editMessageText(
  chatId: string,
  messageId: string,
  requesterId: string,
  newText: string
): { message: Message; chat: Chat | undefined } | undefined {
  const list = ensureMessages(chatId);
  const msg = list.find((m) => m.id === messageId);
  if (!msg || msg.senderId !== requesterId || msg.deleted) return undefined;
  if (msg.media || msg.imageUrl) return undefined;
  const text = newText.trim();
  if (!text || text.length > MAX_MSG_LEN) return undefined;
  msg.text = text;
  msg.editedAt = Date.now();
  const chat = chats.get(chatId);
  if (chat?.lastMessage) {
    const nonDeleted = list.filter((m) => !m.deleted);
    const last = nonDeleted[nonDeleted.length - 1];
    if (last?.id === messageId) {
      chat.lastMessage = {
        text: previewForMessage(msg),
        time: msg.createdAt,
        senderId: msg.senderId,
      };
    }
  }
  return { message: msg, chat };
}

export function editMessageEncryptedText(
  chatId: string,
  messageId: string,
  requesterId: string,
  encryptedText: Message['encryptedText']
): { message: Message; chat: Chat | undefined } | undefined {
  const list = ensureMessages(chatId);
  const msg = list.find((m) => m.id === messageId);
  if (!msg || msg.senderId !== requesterId || msg.deleted) return undefined;
  if (msg.media || msg.imageUrl || !encryptedText) return undefined;
  msg.text = '';
  msg.encryptedText = encryptedText;
  msg.editedAt = Date.now();
  const chat = chats.get(chatId);
  if (chat?.lastMessage) {
    const nonDeleted = list.filter((m) => !m.deleted);
    const last = nonDeleted[nonDeleted.length - 1];
    if (last?.id === messageId) {
      chat.lastMessage = {
        text: previewForMessage(msg),
        time: msg.createdAt,
        senderId: msg.senderId,
      };
    }
  }
  return { message: msg, chat };
}

export function updateChatProfile(
  chatId: string,
  requesterId: string,
  patch: { name?: string; avatarUrl?: string | null }
): Chat | undefined {
  const chat = chats.get(chatId);
  if (!chat || chat.type === 'direct') return undefined;
  if (!chat.participantIds.includes(requesterId)) return undefined;
  if (chat.type === 'channel' && chat.channelOwnerId !== requesterId)
    return undefined;
  if (typeof patch.name === 'string') {
    const n = patch.name.trim();
    if (n.length >= 2 && n.length <= 128) chat.name = n;
  }
  if ('avatarUrl' in patch) {
    const v = patch.avatarUrl;
    chat.avatarUrl =
      v && typeof v === 'string' && v.length > 0 ? v : undefined;
  }
  return chat;
}

/** Может ли пользователь писать в чат. В канале — владелец или админ. */
export function canWriteToChat(chat: Chat, userId: string): boolean {
  if (chat.type !== 'channel') return true;
  return (
    chat.channelOwnerId === userId ||
    (chat.channelAdminIds ?? []).includes(userId)
  );
}

/** Назначить/снять администратора канала. Только владелец канала. */
export function setChannelAdmin(
  chatId: string,
  requesterId: string,
  targetUserId: string,
  makeAdmin: boolean
): Chat | undefined {
  const chat = chats.get(chatId);
  if (!chat || chat.type !== 'channel') return undefined;
  if (chat.channelOwnerId !== requesterId) return undefined;
  if (targetUserId === chat.channelOwnerId) return chat;
  if (!chat.participantIds.includes(targetUserId)) return undefined;
  const set = new Set(chat.channelAdminIds ?? []);
  if (makeAdmin) {
    set.add(targetUserId);
  } else {
    set.delete(targetUserId);
  }
  chat.channelAdminIds = [...set];
  return chat;
}

export function addChatMembers(
  chatId: string,
  requesterId: string,
  memberIds: string[]
): Chat | undefined {
  const chat = chats.get(chatId);
  if (!chat || chat.type === 'direct') return undefined;
  if (!chat.participantIds.includes(requesterId)) return undefined;
  if (chat.type === 'channel' && chat.channelOwnerId !== requesterId)
    return undefined;
  const set = new Set(chat.participantIds);
  for (const id of memberIds) {
    if (!id || !users.has(id)) continue;
    if (!canAddContactToSharedChat(requesterId, id)) continue;
    set.add(id);
  }
  if (set.size === chat.participantIds.length) return chat;
  chat.participantIds = [...set];
  for (const id of chat.participantIds) {
    if (chat.unread[id] === undefined) chat.unread[id] = 0;
  }
  return chat;
}

export function purgeChatPrefsForUsers(chatId: string, userIds: string[]): void {
  for (const uid of userIds) {
    mutedChatsByUser.get(uid)?.delete(chatId);
    pinnedChatsByUser.get(uid)?.delete(chatId);
  }
}

/** Удалить чат полностью или выйти из группы/канала. */
export function userLeavesChat(
  userId: string,
  chatId: string
): {
  fullDelete: boolean;
  notifyDeletedFor: string[];
  remainingParticipantIds: string[];
} | null {
  const chat = chats.get(chatId);
  if (!chat || !chat.participantIds.includes(userId)) return null;

  const allBefore = [...chat.participantIds];

  if (chat.type === 'direct') {
    purgeChatPrefsForUsers(chatId, allBefore);
    chats.delete(chatId);
    messagesByChat.delete(chatId);
    return {
      fullDelete: true,
      notifyDeletedFor: allBefore,
      remainingParticipantIds: [],
    };
  }

  if (chat.type === 'channel') {
    if (chat.channelOwnerId === userId) {
      purgeChatPrefsForUsers(chatId, allBefore);
      chats.delete(chatId);
      messagesByChat.delete(chatId);
      return {
        fullDelete: true,
        notifyDeletedFor: allBefore,
        remainingParticipantIds: [],
      };
    }
    chat.participantIds = chat.participantIds.filter((id) => id !== userId);
    delete chat.unread[userId];
    if (chat.lastReadAt) delete chat.lastReadAt[userId];
    purgeChatPrefsForUsers(chatId, [userId]);
    return {
      fullDelete: false,
      notifyDeletedFor: [userId],
      remainingParticipantIds: [...chat.participantIds],
    };
  }

  chat.participantIds = chat.participantIds.filter((id) => id !== userId);
  delete chat.unread[userId];
  if (chat.lastReadAt) delete chat.lastReadAt[userId];
  purgeChatPrefsForUsers(chatId, [userId]);

  if (chat.participantIds.length === 0) {
    chats.delete(chatId);
    messagesByChat.delete(chatId);
    return {
      fullDelete: true,
      notifyDeletedFor: [userId],
      remainingParticipantIds: [],
    };
  }

  return {
    fullDelete: false,
    notifyDeletedFor: [userId],
    remainingParticipantIds: [...chat.participantIds],
  };
}

export function setChatPinnedMessage(
  chatId: string,
  messageId: string | null,
  requesterId: string
): Chat | undefined {
  const chat = chats.get(chatId);
  if (!chat?.participantIds.includes(requesterId)) return undefined;
  const channelNonOwner =
    chat.type === 'channel' && chat.channelOwnerId !== requesterId;
  if (channelNonOwner && messageId) return undefined;
  if (messageId) {
    const list = ensureMessages(chatId);
    const ok = list.some((m) => m.id === messageId && !m.deleted);
    if (!ok) return undefined;
    chat.pinnedMessageId = messageId;
  } else {
    chat.pinnedMessageId = undefined;
  }
  return chat;
}

export function clearAllMessagesInChat(
  chatId: string,
  requesterId: string
): Chat | undefined {
  const chat = chats.get(chatId);
  if (!chat?.participantIds.includes(requesterId)) return undefined;
  if (chat.type === 'channel' && chat.channelOwnerId !== requesterId)
    return undefined;
  const list = messagesByChat.get(chatId);
  if (list) list.length = 0;
  chat.lastMessage = undefined;
  chat.pinnedMessageId = undefined;
  return chat;
}

export function createDirectChatIfNeeded(
  userA: string,
  userB: string
): Chat {
  const existing = [...chats.values()].find(
    (c) =>
      c.type === 'direct' &&
      c.participantIds.includes(userA) &&
      c.participantIds.includes(userB)
  );
  if (existing) return existing;

  const other = users.get(userB);
  const chat: Chat = {
    id: uuid(),
    type: 'direct',
    name: other?.username ?? 'Чат',
    participantIds: [userA, userB],
    unread: {},
    lastReadAt: {},
  };
  chats.set(chat.id, chat);
  return chat;
}

export function ensureSavedChat(userId: string): Chat {
  const existing = [...chats.values()].find(
    (c) =>
      c.type === 'direct' &&
      c.participantIds.length === 1 &&
      c.participantIds[0] === userId
  );
  if (existing) return existing;
  const chat: Chat = {
    id: uuid(),
    type: 'direct',
    name: 'Избранное',
    participantIds: [userId],
    unread: {},
    lastReadAt: {},
  };
  chats.set(chat.id, chat);
  return chat;
}

export function createGroupChat(
  creatorId: string,
  name: string,
  memberIds: string[]
): Chat {
  const participantIds = [
    ...new Set([
      creatorId,
      ...memberIds.filter((id) => canAddContactToSharedChat(creatorId, id)),
    ]),
  ];
  const chat: Chat = {
    id: uuid(),
    type: 'group',
    name,
    participantIds,
    unread: {},
    lastReadAt: {},
  };
  chats.set(chat.id, chat);
  const welcome: Message = {
    id: uuid(),
    chatId: chat.id,
    senderId: creatorId,
    text: `Группа «${name}» создана`,
    createdAt: Date.now(),
  };
  addMessage(welcome);
  return chat;
}

export function createChannelChat(
  ownerId: string,
  name: string,
  subscriberIds: string[]
): Chat {
  const participantIds = [
    ...new Set([
      ownerId,
      ...subscriberIds.filter((id) => canAddContactToSharedChat(ownerId, id)),
    ]),
  ];
  const chat: Chat = {
    id: uuid(),
    type: 'channel',
    name,
    participantIds,
    channelOwnerId: ownerId,
    channelAdminIds: [],
    unread: {},
    lastReadAt: {},
  };
  chats.set(chat.id, chat);
  addMessage({
    id: uuid(),
    chatId: chat.id,
    senderId: ownerId,
    text: `Канал «${name}» создан. Писать может только владелец.`,
    createdAt: Date.now(),
  });
  return chat;
}

export function ensureWelcomeChat(userId: string): void {
  const bot = users.get('user-bot');
  if (!bot) return;
  const exists = [...chats.values()].some(
    (c) =>
      c.type === 'direct' &&
      c.participantIds.includes(userId) &&
      c.participantIds.includes(bot.id)
  );
  if (exists) return;
  const chat: Chat = {
    id: uuid(),
    type: 'direct',
    name: 'БренксЧат',
    participantIds: [userId, bot.id],
    unread: { [userId]: 1 },
    lastReadAt: {},
  };
  chats.set(chat.id, chat);
  addMessage({
    id: uuid(),
    chatId: chat.id,
    senderId: bot.id,
    text: 'Добро пожаловать в БренксЧат!',
    createdAt: Date.now(),
  });
}

export type AdminUserRow = {
  id: string;
  username: string;
  displayName?: string;
  isAdmin: boolean;
  email?: string;
  emailVerified: boolean;
  banned: boolean;
  messageCount: number;
  chatCount: number;
};

export function getAdminOverview(): {
  userCount: number;
  blockedUserCount: number;
  chatCount: number;
  directChatCount: number;
  groupChatCount: number;
  channelChatCount: number;
  messageCount: number;
  users: AdminUserRow[];
} {
  let messageCount = 0;
  const byUserMessages = new Map<string, number>();
  for (const list of messagesByChat.values()) {
    messageCount += list.length;
    for (const msg of list) {
      byUserMessages.set(msg.senderId, (byUserMessages.get(msg.senderId) ?? 0) + 1);
    }
  }
  const chatList = [...chats.values()];
  return {
    userCount: users.size,
    blockedUserCount: [...users.values()].filter((u) => !!u.banned).length,
    chatCount: chatList.length,
    directChatCount: chatList.filter((c) => c.type === 'direct').length,
    groupChatCount: chatList.filter((c) => c.type === 'group').length,
    channelChatCount: chatList.filter((c) => c.type === 'channel').length,
    messageCount,
    users: [...users.values()]
      .map((u) => ({
        id: u.id,
        username: u.username,
        displayName: u.displayName,
        isAdmin: !!u.isAdmin,
        email: u.email,
        emailVerified: !!u.emailVerified,
        banned: !!u.banned,
        messageCount: byUserMessages.get(u.id) ?? 0,
        chatCount: chatList.filter((c) => c.participantIds.includes(u.id)).length,
      }))
      .sort((a, b) => a.username.localeCompare(b.username, 'ru')),
  };
}

export function addPushSubscription(
  userId: string,
  subscription: PushSubscriptionData
): void {
  let subs = pushSubscriptionsByUser.get(userId);
  if (!subs) {
    subs = [];
    pushSubscriptionsByUser.set(userId, subs);
  }
  // Избегаем дубликатов по endpoint
  if (!subs.some((s) => s.endpoint === subscription.endpoint)) {
    subs.push(subscription);
  }
}

export function removePushSubscription(
  userId: string,
  endpoint: string
): void {
  const subs = pushSubscriptionsByUser.get(userId);
  if (!subs) return;
  const idx = subs.findIndex((s) => s.endpoint === endpoint);
  if (idx !== -1) subs.splice(idx, 1);
}

export function getPushSubscriptions(userId: string): PushSubscriptionData[] {
  return pushSubscriptionsByUser.get(userId) ?? [];
}

export function getAllPushSubscriptions(): Map<string, PushSubscriptionData[]> {
  return pushSubscriptionsByUser;
}
