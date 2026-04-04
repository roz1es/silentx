import { v4 as uuid } from 'uuid';
import type { Chat, Message, User } from './types.js';

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

function ensureMessages(chatId: string): Message[] {
  let list = messagesByChat.get(chatId);
  if (!list) {
    list = [];
    messagesByChat.set(chatId, list);
  }
  return list;
}

function seed() {
  const alice: User = {
    id: 'user-alice',
    username: 'alice',
    password: 'alice',
  };
  const bob: User = {
    id: 'user-bob',
    username: 'bob',
    password: 'bob',
  };
  const bot: User = {
    id: 'user-bot',
    username: 'silentx',
    password: '',
  };
  users.set(alice.id, alice);
  users.set(bob.id, bob);
  users.set(bot.id, bot);

  const directChat: Chat = {
    id: 'chat-alice-bob',
    type: 'direct',
    name: 'bob',
    participantIds: [alice.id, bob.id],
    lastMessage: {
      text: 'Привет! Как дела?',
      time: Date.now() - 3600_000,
      senderId: bob.id,
    },
    unread: { [alice.id]: 2, [bob.id]: 0 },
    lastReadAt: {},
  };

  const groupChat: Chat = {
    id: 'chat-team',
    type: 'group',
    name: 'Команда разработки',
    participantIds: [alice.id, bob.id, bot.id],
    lastMessage: {
      text: 'Релиз завтра в 10:00',
      time: Date.now() - 1800_000,
      senderId: alice.id,
    },
    unread: { [alice.id]: 0, [bob.id]: 1, [bot.id]: 0 },
    lastReadAt: {},
  };

  chats.set(directChat.id, directChat);
  chats.set(groupChat.id, groupChat);

  const t = Date.now();
  ensureMessages(directChat.id).push(
    {
      id: uuid(),
      chatId: directChat.id,
      senderId: alice.id,
      text: 'Привет!',
      createdAt: t - 7200_000,
    },
    {
      id: uuid(),
      chatId: directChat.id,
      senderId: bob.id,
      text: 'Привет! Как дела?',
      createdAt: t - 3600_000,
    }
  );

  ensureMessages(groupChat.id).push(
    {
      id: uuid(),
      chatId: groupChat.id,
      senderId: bot.id,
      text: 'Добро пожаловать в группу 👋',
      createdAt: t - 10_800_000,
    },
    {
      id: uuid(),
      chatId: groupChat.id,
      senderId: alice.id,
      text: 'Релиз завтра в 10:00',
      createdAt: t - 1800_000,
    }
  );
}

seed();

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
    text: 'Добро пожаловать! Это демо-мессенджер Silentix.',
    createdAt: Date.now(),
  });
}
