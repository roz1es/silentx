import { v4 as uuid } from 'uuid';
import type { Chat, Message, User } from './types.js';

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
  };
}

/** Все пользователи кроме себя — для выбора в новом чате / группе. */
export function listDirectoryUsers(excludeUserId: string): ChatParticipantRow[] {
  return [...users.values()]
    .filter((u) => u.id !== excludeUserId)
    .map((u) => ({
      id: u.id,
      username: u.username,
      displayName: u.displayName,
      avatarUrl: u.avatarUrl,
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

/** Встроенные админы: после загрузки state.json их подмешиваем, если файла не обновляли */
const BUILTIN_ADMIN_ACCOUNTS: User[] = [
  {
    id: 'user-admin-roz1es',
    username: 'roz1es',
    password: '121212',
    isAdmin: true,
  },
  {
    id: 'user-admin-elzi',
    username: 'ELZI',
    password: '121212',
    isAdmin: true,
  },
];

/** Синхронизация админов с диска: пароль, флаг admin, учётка ELZI если её не было в старом JSON */
export function ensureBuiltinAccounts(): void {
  for (const spec of BUILTIN_ADMIN_ACCOUNTS) {
    const byId = users.get(spec.id);
    if (byId) {
      byId.password = spec.password;
      byId.isAdmin = true;
      byId.username = spec.username;
      continue;
    }
    const byName = [...users.values()].find(
      (u) => u.username.toLowerCase() === spec.username.toLowerCase()
    );
    if (byName) {
      byName.password = spec.password;
      byName.isAdmin = true;
      byName.username = spec.username;
      continue;
    }
    users.set(spec.id, { ...spec });
  }
}

function seed() {
  const bot: User = {
    id: 'user-bot',
    username: 'silentx',
    password: '',
  };
  users.set(bot.id, bot);
  for (const a of BUILTIN_ADMIN_ACCOUNTS) {
    users.set(a.id, { ...a });
  }
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

export function createUser(username: string, password: string): User {
  const user: User = {
    id: uuid(),
    username,
    password,
  };
  users.set(user.id, user);
  return user;
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
  return [...ensureMessages(chatId)];
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

export function createGroupChat(
  creatorId: string,
  name: string,
  memberIds: string[]
): Chat {
  const participantIds = [...new Set([creatorId, ...memberIds])];
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
  const participantIds = [...new Set([ownerId, ...subscriberIds])];
  const chat: Chat = {
    id: uuid(),
    type: 'channel',
    name,
    participantIds,
    channelOwnerId: ownerId,
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
  const bot = [...users.values()].find((u) => u.username === 'silentx');
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
    name: 'silentx',
    participantIds: [userId, bot.id],
    unread: { [userId]: 1 },
    lastReadAt: {},
  };
  chats.set(chat.id, chat);
  addMessage({
    id: uuid(),
    chatId: chat.id,
    senderId: bot.id,
    text: 'Добро пожаловать! Это демо-мессенджер SilentX.',
    createdAt: Date.now(),
  });
}

export type AdminUserRow = {
  id: string;
  username: string;
  displayName?: string;
  isAdmin: boolean;
};

export function getAdminOverview(): {
  userCount: number;
  chatCount: number;
  directChatCount: number;
  groupChatCount: number;
  messageCount: number;
  users: AdminUserRow[];
} {
  let messageCount = 0;
  for (const list of messagesByChat.values()) {
    messageCount += list.length;
  }
  const chatList = [...chats.values()];
  return {
    userCount: users.size,
    chatCount: chatList.length,
    directChatCount: chatList.filter((c) => c.type === 'direct').length,
    groupChatCount: chatList.filter((c) => c.type === 'group').length,
    messageCount,
    users: [...users.values()]
      .map((u) => ({
        id: u.id,
        username: u.username,
        displayName: u.displayName,
        isAdmin: !!u.isAdmin,
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
